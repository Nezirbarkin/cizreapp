-- ============================================================================
-- SİPARİŞ (order) kurye teslimat akışını sunucu-otoriteli RPC'lere taşı
-- ----------------------------------------------------------------------------
-- ARKA PLAN
--   PAKET akışı (courier_requests) uçtan uca SECURITY DEFINER RPC'lerle
--   çalışıyor (create/accept/reject/confirm_package_delivery). Ancak SİPARİŞ
--   kurye teslimat akışı (courier_assignments + orders) istemcide doğrudan
--   INSERT/UPDATE yapıyordu ve RLS/yetki modeline çarparak tamamen kırıktı:
--     * courier_assignments için INSERT policy'si yok → atama 42501.
--     * courier_earnings INSERT authenticated'a REVOKE → kazanç hiç oluşmaz.
--     * profiles.delivered_count guard trigger'ı istemci UPDATE'ini engeller.
--     * notifications çapraz-kullanıcı INSERT (user_id=auth.uid()) → blok.
--     * profiles'ta email/phone/delivered_count/is_online/last_known_*
--       grant DIŞI → istemci kurye seçim/profil sorguları 42501.
--   Sonuç: kurye sipariş alamıyor, teslimde kazanç/count/bildirim oluşmuyor,
--   payout çalışmıyor; müşteri/satıcı teslim bildirimi gitmiyor.
--
-- ÇÖZÜM
--   Paket akışını modelleyen 4 yeni SECURITY DEFINER RPC + earnings idempotency
--   index'i. İstemci artık finansal/atama yazımlarını doğrudan tabloya değil
--   bu RPC'lere yapar. RLS bypass edilir (SECURITY DEFINER + postgres owner),
--   delivered_count atomik artar (guard'ı sadece service/postgres bypass eder),
--   bildirimler add_notification üzerinden gider.
--
--   assign_order_to_courier(p_order_id, p_courier_id)     — atama (self/auto/seller)
--   complete_order_delivery(p_assignment_id)              — teslim + kazanç + bildirim
--   get_assigned_courier_location(p_request_id)           — paket takip kurye konumu
--   broadcast_order_to_couriers(p_order_id,type,title,..) — yeni sipariş kurye yayını
--
-- GÜVENLİK
--   * Her RPC auth.uid() ve rol doğrulaması yapar (is_courier_role/is_admin/shop owner).
--   * Atamada FOR UPDATE(order) + aktif-atama kontrolü = TOCTOU'a karşı serialize.
--   * earnings assignment_id başına idempotent (partial unique index + ON CONFLICT).
--   * get_assigned_courier_location yalnız gönderici/atanmış kurye/admin'e açılır;
--     gizlilik (ghost/offline/private) durumunda koordinat NULL döner, ~1m yuvarlanır.
--   * İstemci PII (email/phone/address) SELECT etmez; adres/telefon yalnız atanmış
--     kuryeye RPC üzerinden (complete/get_assigned_package_details) döner.
-- ============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '5s';

-- -----------------------------------------------------------------------------
-- 0) courier_earnings: assignment_id / order_id kolonları + idempotency index
-- -----------------------------------------------------------------------------
-- Atanan sipariş tesliminde, aynı assignment için tek kazanç satırı garanti.
-- package_request_id üzerindeki mevcut unique index korunur; order akışı için
-- assignment_id üzerinde paralel bir partial unique index eklenir.
ALTER TABLE public.courier_earnings
  ADD COLUMN IF NOT EXISTS assignment_id uuid,
  ADD COLUMN IF NOT EXISTS order_id uuid;

-- Güvenli dedup: aynı assignment_id'ye ait mükerrer kazançları en yeniyi
-- tutacak şekilde temizle (akış kırık olduğu için pratikte no-op; yine de
-- index oluşturmayı engelleyecek eski çift kayıt varsa güvenli şekilde
-- tekilleştirir — assignment başına yalnız tek kazanç doğrudur).
DELETE FROM public.courier_earnings
WHERE id IN (
  SELECT id FROM (
    SELECT id,
           row_number() OVER (
             PARTITION BY assignment_id
             ORDER BY created_at DESC NULLS LAST, id DESC
           ) AS rn
    FROM public.courier_earnings
    WHERE assignment_id IS NOT NULL
  ) x
  WHERE rn > 1
);

CREATE UNIQUE INDEX IF NOT EXISTS uq_courier_earnings_assignment
  ON public.courier_earnings (assignment_id)
  WHERE assignment_id IS NOT NULL;

-- -----------------------------------------------------------------------------
-- 1) assign_order_to_courier: atomik atama (self-accept / auto-select / seller)
-- -----------------------------------------------------------------------------
-- p_courier_id NULL + çağıran kurye  -> self-accept (kurye havuzdan alır)
-- p_courier_id NULL + çağıran satıcı/admin -> sunucu en uygun kuryeyi seçer
-- p_courier_id verilmiş              -> o kuryeye ata (admin / dükkan sahibi)
-- Side-effect: orders.status='on_the_way'; müşteriye "yolda" + atanan kuryeye
-- "atandı" bildirimi (add_notification). returns assignment_id/courier/fee.
DROP FUNCTION IF EXISTS public.assign_order_to_courier(uuid, uuid);

CREATE FUNCTION public.assign_order_to_courier(
  p_order_id uuid,
  p_courier_id uuid DEFAULT NULL
)
RETURNS TABLE(
  r_assignment_id uuid,
  r_courier_id uuid,
  r_courier_name text,
  r_fee_amount numeric,
  r_order_status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid        CONSTANT uuid := (SELECT auth.uid());
  v_target     uuid;
  v_self_assign boolean := false;
  v_order      public.orders%ROWTYPE;
  v_assignment_id uuid;
  v_existing   uuid;
  v_fee        numeric(12, 2);
  v_courier_name text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF p_order_id IS NULL THEN
    RAISE EXCEPTION 'APP:order_id_required' USING ERRCODE = '22023';
  END IF;

  -- Siparişi kilitle (paralel atayan çağrıları serialize eder)
  SELECT o.* INTO v_order
  FROM public.orders AS o
  WHERE o.id = p_order_id
  FOR UPDATE;

  IF v_order.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;

  -- Hedef kurye + yetkilendirme
  IF p_courier_id IS NULL THEN
    IF public.is_courier_role() THEN
      v_target := v_uid;
      v_self_assign := true;
    ELSE
      -- satıcı/admin değilse reddet; satıcı yalnız kendi dükkanının siparişini atayabilir
      IF NOT public.is_admin() AND NOT EXISTS (
        SELECT 1 FROM public.shops AS s
        WHERE s.id = v_order.shop_id AND s.owner_id = v_uid
      ) THEN
        RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
      END IF;
      -- En uygun kurye: online优先, en az teslimat, reddetmeyen
      SELECT p.id INTO v_target
      FROM public.profiles AS p
      WHERE p.role = 'courier'::public.user_role
        AND p.id IS DISTINCT FROM v_order.user_id
        AND NOT EXISTS (
          SELECT 1 FROM public.courier_order_rejections AS cor
          WHERE cor.order_id = p_order_id AND cor.courier_id = p.id
        )
      ORDER BY COALESCE(p.is_online, false) DESC,
               COALESCE(p.delivered_count, 0) ASC,
               p.id
      LIMIT 1;
      IF v_target IS NULL THEN
        RAISE EXCEPTION 'APP:no_courier_available' USING ERRCODE = 'P0001';
      END IF;
    END IF;
  ELSE
    v_target := p_courier_id;
    IF NOT public.is_admin() AND NOT EXISTS (
      SELECT 1 FROM public.shops AS s
      WHERE s.id = v_order.shop_id AND s.owner_id = v_uid
    ) THEN
      RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
    END IF;
  END IF;

  -- Zaten aktif atama var mı (anti-race; order FOR UPDATE ile serialize edildi)
  SELECT ca.id INTO v_existing
  FROM public.courier_assignments AS ca
  WHERE ca.order_id = p_order_id
    AND ca.status IN ('assigned', 'picked_up', 'on_the_way')
  LIMIT 1;
  IF v_existing IS NOT NULL THEN
    RAISE EXCEPTION 'APP:already_assigned' USING ERRCODE = 'P0001';
  END IF;

  -- Ücret: courier_settings.fee_per_delivery (yoksa 15)
  SELECT cs.fee_per_delivery INTO v_fee
  FROM public.courier_settings AS cs
  LIMIT 1;
  v_fee := COALESCE(v_fee, 15);

  INSERT INTO public.courier_assignments (
    order_id, courier_id, status, fee_amount, assigned_at
  ) VALUES (
    p_order_id, v_target, 'assigned', v_fee, now()
  )
  RETURNING id INTO v_assignment_id;

  -- Müşteriye "yolda" görünsün (mevcut _acceptOrder davranışını korur)
  UPDATE public.orders
     SET status = 'on_the_way', updated_at = now()
   WHERE id = p_order_id
     AND status IN ('confirmed', 'preparing', 'ready');

  SELECT COALESCE(p.full_name, p.username, 'Kurye') INTO v_courier_name
  FROM public.profiles AS p
  WHERE p.id = v_target;

  -- Müşteriye tek "yolda" bildirimi (önceden hem accept hem pickup'ta çift gidiyordu)
  PERFORM public.add_notification(
    p_user_id  => v_order.user_id,
    p_type     => 'order_update',
    p_title    => '🚴 Siparişiniz Yolda!',
    p_content  => v_courier_name || ' siparişinizi teslim etmek için yola çıktı.',
    p_entity_id => p_order_id::text
  );

  -- Atanan kuryeye bildirim (otomatik/satıcı yolu); self-accept'te atlanır
  IF NOT v_self_assign THEN
    PERFORM public.add_notification(
      p_user_id   => v_target,
      p_type      => 'courier_order_assigned',
      p_title     => '🛵 Sipariş Sana Atandı!',
      p_content   => 'Sana bir sipariş atandı. Kurye panelinden teslim alabilirsin.',
      p_entity_id => p_order_id::text
    );
  END IF;

  RETURN QUERY
  SELECT v_assignment_id, v_target, v_courier_name, v_fee, 'on_the_way'::text;
END;
$$;

REVOKE ALL ON FUNCTION public.assign_order_to_courier(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.assign_order_to_courier(uuid, uuid) TO authenticated;

COMMENT ON FUNCTION public.assign_order_to_courier(uuid, uuid) IS
  'Siparişi atomik olarak kuryeye atar (self-accept / auto-select / seller). FOR UPDATE ile TOCTOU koruması; orders.status=on_the_way; müşteriye tek "yolda" bildirimi. İstemci doğrudan courier_assignments INSERT edemez (RLS INSERT policy yok).';

-- -----------------------------------------------------------------------------
-- 2) complete_order_delivery: teslim + earnings + delivered_count + bildirim
-- -----------------------------------------------------------------------------
-- confirm_package_delivery deseninin sipariş karşılığı. Atama sahibi kurye
-- (veya admin) çağırır. Tek atomik işlemde:
--   * courier_assignments.status='delivered', delivered_at
--   * orders.status='delivered', payment_status='paid', delivered_courier_*
--   * profiles.delivered_count + 1 (SECURITY DEFINER guard'ı bypass eder)
--   * courier_earnings idempotent insert (assignment_id unique)
--   * müşteri + satıcı teslim bildirimi (add_notification)
DROP FUNCTION IF EXISTS public.complete_order_delivery(uuid);

CREATE FUNCTION public.complete_order_delivery(p_assignment_id uuid)
RETURNS TABLE(
  r_assignment_id uuid,
  r_earning_id uuid,
  r_amount numeric,
  r_status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid       CONSTANT uuid := (SELECT auth.uid());
  v_assignment public.courier_assignments%ROWTYPE;
  v_fee        numeric(12, 2);
  v_earning_id uuid;
  v_courier_name text;
  v_courier_phone text;
  v_customer_id uuid;
  v_seller_id   uuid;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF p_assignment_id IS NULL THEN
    RAISE EXCEPTION 'APP:assignment_id_required' USING ERRCODE = '22023';
  END IF;

  SELECT ca.* INTO v_assignment
  FROM public.courier_assignments AS ca
  WHERE ca.id = p_assignment_id
  FOR UPDATE;

  IF v_assignment.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_assignment.courier_id <> v_uid AND NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:not_assignment_owner' USING ERRCODE = '42501';
  END IF;
  IF v_assignment.status = 'delivered' THEN
    RAISE EXCEPTION 'APP:already_delivered' USING ERRCODE = 'P0001';
  END IF;
  IF v_assignment.status NOT IN ('assigned', 'picked_up', 'on_the_way') THEN
    RAISE EXCEPTION 'APP:invalid_state | durum: %', v_assignment.status
      USING ERRCODE = 'P0001';
  END IF;

  v_fee := COALESCE(v_assignment.fee_amount, 0);

  UPDATE public.courier_assignments
     SET status = 'delivered', delivered_at = now()
   WHERE id = p_assignment_id;

  SELECT COALESCE(p.full_name, p.username, 'Kurye'), COALESCE(p.phone, '')
    INTO v_courier_name, v_courier_phone
  FROM public.profiles AS p
  WHERE p.id = v_assignment.courier_id;

  UPDATE public.orders
     SET status = 'delivered',
         payment_status = 'paid',
         delivered_at = now(),
         delivered_courier_id = v_assignment.courier_id,
         delivered_courier_name = v_courier_name,
         delivered_courier_phone = v_courier_phone,
         updated_at = now()
   WHERE id = v_assignment.order_id;

  -- delivered_count atomik artış (RPC postgres owner => guard trigger bypass)
  UPDATE public.profiles
     SET delivered_count = COALESCE(delivered_count, 0) + 1
   WHERE id = v_assignment.courier_id;

  -- Idempotent kazanç (assignment başına tek satır)
  INSERT INTO public.courier_earnings (
    courier_id, assignment_id, order_id, amount, amount_snapshot, status
  ) VALUES (
    v_assignment.courier_id, p_assignment_id, v_assignment.order_id,
    v_fee, v_fee, 'pending'
  )
  ON CONFLICT (assignment_id) WHERE assignment_id IS NOT NULL DO NOTHING
  RETURNING id INTO v_earning_id;

  IF v_earning_id IS NULL THEN
    SELECT ce.id INTO v_earning_id
    FROM public.courier_earnings AS ce
    WHERE ce.assignment_id = p_assignment_id
    LIMIT 1;
  END IF;

  -- Müşteri + satıcı teslim bildirimi
  SELECT o.user_id, s.owner_id INTO v_customer_id, v_seller_id
  FROM public.orders AS o
  JOIN public.shops AS s ON s.id = o.shop_id
  WHERE o.id = v_assignment.order_id;

  IF v_customer_id IS NOT NULL THEN
    PERFORM public.add_notification(
      p_user_id   => v_customer_id,
      p_type      => 'order_delivered',
      p_title     => 'Sipariş Teslim Edildi',
      p_content   => 'Siparişiniz teslim edildi. Değerlendirme için tıklayın.',
      p_entity_id => v_assignment.order_id::text
    );
  END IF;
  IF v_seller_id IS NOT NULL THEN
    PERFORM public.add_notification(
      p_user_id   => v_seller_id,
      p_type      => 'order_delivered',
      p_title     => '✅ Sipariş Teslim Edildi',
      p_content   => v_courier_name || ' siparişi teslim etti.',
      p_entity_id => v_assignment.order_id::text
    );
  END IF;

  RETURN QUERY
  SELECT p_assignment_id, v_earning_id, v_fee, 'pending'::text;
END;
$$;

REVOKE ALL ON FUNCTION public.complete_order_delivery(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.complete_order_delivery(uuid) TO authenticated;

COMMENT ON FUNCTION public.complete_order_delivery(uuid) IS
  'Sipariş teslimini atomik tamamlar: assignment delivered + orders(delivered/paid/kurye bilgisi) + delivered_count++ + idempotent earnings + müşteri/satıcı bildirimi. İstemci doğrudan courier_earnings INSERT edemez (REVOKE) ve delivered_count guardı istemci UPDATEini engeller; bu RPC ikisini de sunucu-otoriteli yapar.';

-- -----------------------------------------------------------------------------
-- 3) get_assigned_courier_location: paket takip için atanmış kurye konumu
-- -----------------------------------------------------------------------------
-- Gönderici, kendi courier_request'ine atanmış kuryenin canlı konumunu okur.
-- profiles.last_known_* grant dışı olduğu için istemci tabloyu doğrudan
-- okuyamaz/realtime alamaz. Bu RPC gizlilik kurallarıyla (~1m yuvarlama,
-- ghost/offline/private => NULL) koordinatı yalnız gönderici/kurye/admin'e döner.
DROP FUNCTION IF EXISTS public.get_assigned_courier_location(uuid);

CREATE FUNCTION public.get_assigned_courier_location(p_request_id uuid)
RETURNS TABLE(
  r_courier_id uuid,
  r_full_name text,
  r_lat double precision,
  r_lng double precision,
  r_heading real,
  r_last_location_update timestamptz,
  r_request_status text
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid  CONSTANT uuid := (SELECT auth.uid());
  v_rec  public.courier_requests%ROWTYPE;
  v_show boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF p_request_id IS NULL THEN
    RAISE EXCEPTION 'APP:request_id_required' USING ERRCODE = '22023';
  END IF;

  SELECT cr.* INTO v_rec
  FROM public.courier_requests AS cr
  WHERE cr.id = p_request_id;

  IF v_rec.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;

  IF NOT (v_rec.sender_id = v_uid OR v_rec.courier_id = v_uid OR public.is_admin()) THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;

  -- Henüz kurye atanmadıysa sadece durum bilgisini döner
  IF v_rec.courier_id IS NULL THEN
    RETURN QUERY SELECT NULL::uuid, NULL::text, NULL::double precision,
                       NULL::double precision, NULL::real, NULL::timestamptz,
                       v_rec.status::text;
    RETURN;
  END IF;

  SELECT COALESCE(p.is_online_enabled, true) = true
     AND COALESCE(p.is_ghost_mode, false) = false
     AND COALESCE(p.profile_is_public, true) = true
     AND p.last_known_lat IS NOT NULL
     AND p.last_known_lng IS NOT NULL
    INTO v_show
  FROM public.profiles AS p
  WHERE p.id = v_rec.courier_id;

  RETURN QUERY
  SELECT
    v_rec.courier_id,
    p.full_name,
    CASE WHEN v_show THEN round(p.last_known_lat::numeric, 3)::double precision
         ELSE NULL END,
    CASE WHEN v_show THEN round(p.last_known_lng::numeric, 3)::double precision
         ELSE NULL END,
    CASE WHEN v_show THEN p.last_known_heading ELSE NULL END,
    p.last_location_update,
    v_rec.status::text
  FROM public.profiles AS p
  WHERE p.id = v_rec.courier_id;
END;
$$;

REVOKE ALL ON FUNCTION public.get_assigned_courier_location(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_assigned_courier_location(uuid) TO authenticated;

COMMENT ON FUNCTION public.get_assigned_courier_location(uuid) IS
  'Göndericinin kendi paketine atanmış kuryenin canlı konumunu (approx, ~1m) döner. Gizlilik kuralları (ghost/offline/private) altında koordinat NULL döner. profiles.last_known_* istemciye grant edilmediği için RPC üzerinden okunur.';

-- -----------------------------------------------------------------------------
-- 4) broadcast_order_to_couriers: yeni siparişte tüm kuryelere bildirim
-- -----------------------------------------------------------------------------
-- profiles.select(role=courier) istemcide grant dışı olduğu için kurye listesi
-- istemciden çekilemez; bu RPC sunucu tarafında uygun kuryelere bildirim yazar.
-- Aynı (order_id, type) için tekrar yayın yapmaz (dedup, entity_id üzerinden).
DROP FUNCTION IF EXISTS public.broadcast_order_to_couriers(uuid, text, text, text);

CREATE FUNCTION public.broadcast_order_to_couriers(
  p_order_id uuid,
  p_type text,
  p_title text,
  p_content text
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $$
DECLARE
  v_uid   CONSTANT uuid := (SELECT auth.uid());
  v_count integer := 0;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF p_order_id IS NULL THEN
    RAISE EXCEPTION 'APP:order_id_required' USING ERRCODE = '22023';
  END IF;

  -- satıcı (kendi dükkanı) veya admin
  IF NOT public.is_admin() AND NOT EXISTS (
    SELECT 1
    FROM public.orders AS o
    JOIN public.shops AS s ON s.id = o.shop_id
    WHERE o.id = p_order_id AND s.owner_id = v_uid
  ) THEN
    RAISE EXCEPTION 'APP:forbidden' USING ERRCODE = '42501';
  END IF;

  -- Dükkanın kendi kuryesi varsa yayın yapma
  IF EXISTS (
    SELECT 1 FROM public.orders o
    JOIN public.shops s ON s.id = o.shop_id
    WHERE o.id = p_order_id AND COALESCE(s.has_own_courier, false) = true
  ) THEN
    RETURN 0;
  END IF;

  -- Aynı sipariş+tip için zaten bildirim atıldıysa tekrar atma
  IF EXISTS (
    SELECT 1 FROM public.notifications n
    WHERE n.entity_id = p_order_id::text AND n.type = p_type
  ) THEN
    RETURN 0;
  END IF;

  WITH ins AS (
    INSERT INTO public.notifications (user_id, type, title, content, entity_id, is_read, created_at)
    SELECT p.id, p_type, p_title, p_content, p_order_id::text, false, now()
    FROM public.profiles AS p
    WHERE p.role = 'courier'::public.user_role
    RETURNING 1
  )
  SELECT count(*) INTO v_count FROM ins;

  RETURN v_count;
END;
$$;

REVOKE ALL ON FUNCTION public.broadcast_order_to_couriers(uuid, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.broadcast_order_to_couriers(uuid, text, text, text) TO authenticated;

COMMENT ON FUNCTION public.broadcast_order_to_couriers(uuid, text, text, text) IS
  'Yeni siparişte (kuryesi olmayan dükkansa) tüm kuryelere bildirim yazar. Kurye listesi istemciden çekilemediği için (profiles.role grant dışı) sunucu-otoritelidir. Aynı order+tip için dedup.';

-- -----------------------------------------------------------------------------
-- 5) PostgREST şema cache'ini tazele
-- -----------------------------------------------------------------------------
DO $$
BEGIN
  PERFORM pg_notify('pgrst', 'reload schema');
  RAISE NOTICE '✓ 4 yeni order-delivery RPC''si + earnings idempotency index eklendi; pgrst reload tetiklendi';
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'pgrst reload başarısız: %. Dashboard > API > Reload schema cache kullanın.', SQLERRM;
END;
$$;

-- ============================================================================
-- DOĞRULAMA (migration sonrası SQL Editor):
--   SELECT proname FROM pg_proc WHERE proname IN
--     ('assign_order_to_courier','complete_order_delivery',
--      'get_assigned_courier_location','broadcast_order_to_couriers');
--   SELECT indexname FROM pg_indexes WHERE indexname = 'uq_courier_earnings_assignment';
-- ============================================================================
