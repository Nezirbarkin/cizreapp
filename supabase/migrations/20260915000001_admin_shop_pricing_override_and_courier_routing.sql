-- ============================================================================
-- Admin müdahalesi: (1) satıcı teslimat ücreti / min. sepet tutarı geçici
-- override'ı, (2) siparişi istenen kuryenin paneline düşürme.
--
-- 1) FİYAT / TESLİMAT OVERRIDE'I
--    Admin tek tek ya da TÜM dükkânlar için delivery_fee, min_order_amount ve
--    delivery_time (ortalama teslimat süresi) değerlerini ezebilir. Ezmeden
--    önce satıcının o anki değeri pre_override_* sütunlarına yedeklenir; admin
--    override'ı geri aldığında satıcının eski teslimat ücreti, min. sepet
--    tutarı ve teslimat süresi aynen geri gelir.
--
--    Canonical değer HÂLÂ shops.delivery_fee / min_order_amount /
--    delivery_time'dır -- sepet, checkout, mağaza kartı gibi tüm mevcut okuma
--    yolları hiç değişmeden override'lı değeri görür. pre_override_* yalnız
--    geri alma için tutulan yedektir; NULL ise o alanda override yok demektir.
--
--    delivery_time nullable olduğu için yedek sütunda boş dize ('') "satıcının
--    değeri yoktu" anlamına gelen sentinel'dir; geri alırken NULL'a çevrilir.
--    Böylece "yedek NULL = override yok" değişmezi üç alanda da aynı kalır.
--
--    Override yürürlükteyken satıcı kendi panelinden ücret/min sepet/teslimat
--    süresi kaydederse, girdiği değer canlı değeri DEĞİŞTİRMEZ;
--    pre_override_* yedeğine yazılır -- yani "admin müdahalesi kalkınca
--    geçerli olacak değer" olur. Böylece satıcı kilitlenmez ama admin'in
--    koyduğu değer de sessizce delinmez.
--
-- 2) ADMIN -> KURYE YÖNLENDİRME
--    Admin bir siparişi belirli bir kuryeye yönlendirir. Sipariş genel
--    havuzdan çıkar (aktif courier_assignments satırı oluşur) ve yalnız hedef
--    kuryenin panelinde "yönlendirilmiş teklif" olarak görünür. Mevcut
--    devretme (reject -> route) altyapısı aynen kullanılır; tek fark
--    courier_work_offers.routed_by_admin bayrağıdır.
-- ============================================================================

SET search_path = public, pg_temp;

-- ----------------------------------------------------------------------------
-- 1.a) shops: override yedeği + denetim sütunları
-- ----------------------------------------------------------------------------
ALTER TABLE public.shops
  ADD COLUMN IF NOT EXISTS pre_override_delivery_fee numeric,
  ADD COLUMN IF NOT EXISTS pre_override_min_order_amount numeric,
  ADD COLUMN IF NOT EXISTS pre_override_delivery_time text,
  ADD COLUMN IF NOT EXISTS admin_pricing_override_at timestamptz,
  ADD COLUMN IF NOT EXISTS admin_pricing_override_by uuid,
  ADD COLUMN IF NOT EXISTS admin_pricing_override_note text;

COMMENT ON COLUMN public.shops.pre_override_delivery_fee IS
  'Admin teslimat ücretini ezmeden önceki satıcı değeri. NULL = teslimat ücretinde admin override yok. Override geri alındığında delivery_fee bu değere döner.';
COMMENT ON COLUMN public.shops.pre_override_min_order_amount IS
  'Admin min. sepet tutarını ezmeden önceki satıcı değeri. NULL = min. sepette admin override yok.';
COMMENT ON COLUMN public.shops.pre_override_delivery_time IS
  'Admin ortalama teslimat süresini ezmeden önceki satıcı değeri. NULL = teslimat süresinde admin override yok; boş dize = satıcının değeri yoktu (geri alınırken NULL yazılır).';
COMMENT ON COLUMN public.shops.admin_pricing_override_at IS
  'Son admin fiyat müdahalesinin zamanı.';
COMMENT ON COLUMN public.shops.admin_pricing_override_by IS
  'Fiyat müdahalesini yapan admin (auth.users.id).';
COMMENT ON COLUMN public.shops.admin_pricing_override_note IS
  'Adminin müdahale gerekçesi (opsiyonel, satıcıya gösterilir).';

-- ----------------------------------------------------------------------------
-- 1.b) Override koruması: satıcı yazımlarını yedeğe yönlendiren trigger
--
-- shops_update_policy hem sahibe hem admin'e UPDATE veriyor; override
-- sütunları RLS ile kolon bazında korunamadığı için koruma trigger'da.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.shops_guard_admin_pricing_override()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
BEGIN
  -- Servis rolü / bakım bağlamı (auth.uid() yok) ve admin serbest.
  IF (SELECT auth.uid()) IS NULL OR public.is_admin() THEN
    RETURN NEW;
  END IF;

  -- Teslimat ücreti
  IF OLD.pre_override_delivery_fee IS NULL THEN
    -- Override yok: satıcı kendi kendine override yedeği oluşturamaz.
    NEW.pre_override_delivery_fee := NULL;
  ELSIF NEW.delivery_fee IS DISTINCT FROM OLD.delivery_fee THEN
    -- Override var: satıcının yeni değeri canlıya değil yedeğe yazılır.
    NEW.pre_override_delivery_fee := NEW.delivery_fee;
    NEW.delivery_fee := OLD.delivery_fee;
  ELSE
    NEW.pre_override_delivery_fee := OLD.pre_override_delivery_fee;
  END IF;

  -- Min. sepet tutarı
  IF OLD.pre_override_min_order_amount IS NULL THEN
    NEW.pre_override_min_order_amount := NULL;
  ELSIF NEW.min_order_amount IS DISTINCT FROM OLD.min_order_amount THEN
    NEW.pre_override_min_order_amount := NEW.min_order_amount;
    NEW.min_order_amount := OLD.min_order_amount;
  ELSE
    NEW.pre_override_min_order_amount := OLD.pre_override_min_order_amount;
  END IF;

  -- Ortalama teslimat süresi (nullable; yedekte '' = "satıcının değeri yoktu")
  IF OLD.pre_override_delivery_time IS NULL THEN
    NEW.pre_override_delivery_time := NULL;
  ELSIF NEW.delivery_time IS DISTINCT FROM OLD.delivery_time THEN
    NEW.pre_override_delivery_time := COALESCE(NEW.delivery_time, '');
    NEW.delivery_time := OLD.delivery_time;
  ELSE
    NEW.pre_override_delivery_time := OLD.pre_override_delivery_time;
  END IF;

  -- Denetim sütunlarını satıcı değiştiremez.
  NEW.admin_pricing_override_at := OLD.admin_pricing_override_at;
  NEW.admin_pricing_override_by := OLD.admin_pricing_override_by;
  NEW.admin_pricing_override_note := OLD.admin_pricing_override_note;

  RETURN NEW;
END;
$fn$;

COMMENT ON FUNCTION public.shops_guard_admin_pricing_override() IS
  'Admin fiyat override yürürlükteyken satıcının delivery_fee / min_order_amount yazımını canlı değere değil pre_override_* yedeğine yönlendirir; denetim sütunlarını satıcıya kapatır.';

DROP TRIGGER IF EXISTS trg_shops_guard_admin_pricing_override ON public.shops;
CREATE TRIGGER trg_shops_guard_admin_pricing_override
  BEFORE UPDATE ON public.shops
  FOR EACH ROW
  EXECUTE FUNCTION public.shops_guard_admin_pricing_override();

-- ----------------------------------------------------------------------------
-- 1.c) admin_set_shop_pricing_override: override uygula
--   p_shop_ids NULL/boş     -> TÜM dükkânlar
--   p_delivery_fee NULL     -> teslimat ücretine dokunma
--   p_min_order_amount NULL -> min. sepete dokunma
--   p_delivery_time NULL    -> teslimat süresine dokunma
-- ----------------------------------------------------------------------------
-- Eski 4 parametreli sürüm (teslimat süresi eklenmeden önce) kaldırılır;
-- iki imza bir arada kalırsa PostgREST adlandırılmış parametrelerle yanlış
-- olanı seçebilir.
DROP FUNCTION IF EXISTS public.admin_set_shop_pricing_override(uuid[], numeric, numeric, text);
DROP FUNCTION IF EXISTS public.admin_set_shop_pricing_override(uuid[], numeric, numeric, text, text);

CREATE FUNCTION public.admin_set_shop_pricing_override(
  p_shop_ids uuid[] DEFAULT NULL,
  p_delivery_fee numeric DEFAULT NULL,
  p_min_order_amount numeric DEFAULT NULL,
  p_delivery_time text DEFAULT NULL,
  p_note text DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_count integer := 0;
  v_delivery_time text := NULLIF(btrim(COALESCE(p_delivery_time, '')), '');
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden | admin gerekli' USING ERRCODE = '42501';
  END IF;
  IF p_delivery_fee IS NULL
     AND p_min_order_amount IS NULL
     AND v_delivery_time IS NULL THEN
    RAISE EXCEPTION 'APP:nothing_to_override | teslimat ücreti, min. sepet tutarı veya teslimat süresi verilmeli'
      USING ERRCODE = '22023';
  END IF;
  IF p_delivery_fee IS NOT NULL AND (p_delivery_fee < 0 OR p_delivery_fee > 100000) THEN
    RAISE EXCEPTION 'APP:invalid_delivery_fee' USING ERRCODE = '22023';
  END IF;
  IF p_min_order_amount IS NOT NULL AND (p_min_order_amount < 0 OR p_min_order_amount > 1000000) THEN
    RAISE EXCEPTION 'APP:invalid_min_order_amount' USING ERRCODE = '22023';
  END IF;
  IF v_delivery_time IS NOT NULL AND length(v_delivery_time) > 60 THEN
    RAISE EXCEPTION 'APP:invalid_delivery_time | teslimat süresi en fazla 60 karakter'
      USING ERRCODE = '22023';
  END IF;

  WITH updated AS (
    UPDATE public.shops AS s
       SET pre_override_delivery_fee = CASE
             WHEN p_delivery_fee IS NULL THEN s.pre_override_delivery_fee
             WHEN s.pre_override_delivery_fee IS NULL THEN s.delivery_fee
             ELSE s.pre_override_delivery_fee
           END,
           delivery_fee = COALESCE(p_delivery_fee, s.delivery_fee),
           pre_override_min_order_amount = CASE
             WHEN p_min_order_amount IS NULL THEN s.pre_override_min_order_amount
             WHEN s.pre_override_min_order_amount IS NULL THEN s.min_order_amount
             ELSE s.pre_override_min_order_amount
           END,
           min_order_amount = COALESCE(p_min_order_amount, s.min_order_amount),
           -- Yedekte '' sentinel'i: satıcının teslimat süresi hiç yoktu.
           pre_override_delivery_time = CASE
             WHEN v_delivery_time IS NULL THEN s.pre_override_delivery_time
             WHEN s.pre_override_delivery_time IS NULL THEN COALESCE(s.delivery_time, '')
             ELSE s.pre_override_delivery_time
           END,
           delivery_time = COALESCE(v_delivery_time, s.delivery_time),
           admin_pricing_override_at = now(),
           admin_pricing_override_by = v_uid,
           admin_pricing_override_note = p_note,
           updated_at = now()
     WHERE (p_shop_ids IS NULL
            OR cardinality(p_shop_ids) = 0
            OR s.id = ANY (p_shop_ids))
    RETURNING 1 AS touched
  )
  SELECT count(*)::integer INTO v_count FROM updated;

  RETURN v_count;
END;
$fn$;

REVOKE ALL ON FUNCTION public.admin_set_shop_pricing_override(uuid[], numeric, numeric, text, text)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_shop_pricing_override(uuid[], numeric, numeric, text, text)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.admin_set_shop_pricing_override(uuid[], numeric, numeric, text, text) IS
  'Admin: seçili (veya tüm) dükkânların teslimat ücreti / min. sepet tutarı / ortalama teslimat süresini ezer, satıcının eski değerini pre_override_* sütunlarında saklar. Geri alma: admin_clear_shop_pricing_override.';

-- ----------------------------------------------------------------------------
-- 1.d) admin_clear_shop_pricing_override: override'ı geri al
--   Satıcının kaydedilmiş eski (ya da override sırasında kaydettiği yeni)
--   teslimat ücreti ve min. sepet tutarı canlıya geri döner.
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_clear_shop_pricing_override(uuid[]);

CREATE FUNCTION public.admin_clear_shop_pricing_override(
  p_shop_ids uuid[] DEFAULT NULL
)
RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_count integer := 0;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden | admin gerekli' USING ERRCODE = '42501';
  END IF;

  WITH restored AS (
    UPDATE public.shops AS s
       SET delivery_fee = COALESCE(s.pre_override_delivery_fee, s.delivery_fee),
           min_order_amount = COALESCE(s.pre_override_min_order_amount, s.min_order_amount),
           -- '' sentinel'i satıcıda teslimat süresi olmadığı anlamına gelir.
           delivery_time = CASE
             WHEN s.pre_override_delivery_time IS NULL THEN s.delivery_time
             WHEN s.pre_override_delivery_time = '' THEN NULL
             ELSE s.pre_override_delivery_time
           END,
           pre_override_delivery_fee = NULL,
           pre_override_min_order_amount = NULL,
           pre_override_delivery_time = NULL,
           admin_pricing_override_at = NULL,
           admin_pricing_override_by = NULL,
           admin_pricing_override_note = NULL,
           updated_at = now()
     WHERE (p_shop_ids IS NULL
            OR cardinality(p_shop_ids) = 0
            OR s.id = ANY (p_shop_ids))
       AND (s.pre_override_delivery_fee IS NOT NULL
            OR s.pre_override_min_order_amount IS NOT NULL
            OR s.pre_override_delivery_time IS NOT NULL)
    RETURNING 1 AS touched
  )
  SELECT count(*)::integer INTO v_count FROM restored;

  RETURN v_count;
END;
$fn$;

REVOKE ALL ON FUNCTION public.admin_clear_shop_pricing_override(uuid[])
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_clear_shop_pricing_override(uuid[])
  TO authenticated, service_role;

COMMENT ON FUNCTION public.admin_clear_shop_pricing_override(uuid[]) IS
  'Admin: fiyat/teslimat müdahalesini geri alır; dükkânın teslimat ücreti, min. sepet tutarı ve ortalama teslimat süresi satıcının kendi değerine döner.';

-- ============================================================================
-- 2) ADMIN -> KURYE YÖNLENDİRME
-- ============================================================================

ALTER TABLE public.courier_work_offers
  ADD COLUMN IF NOT EXISTS routed_by_admin boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS routed_by uuid;

COMMENT ON COLUMN public.courier_work_offers.routed_by_admin IS
  'true ise teklif kurye devri sonucu değil, adminin doğrudan yönlendirmesiyle oluştu.';
COMMENT ON COLUMN public.courier_work_offers.routed_by IS
  'Yönlendirmeyi yapan kullanıcı (admin) auth.users.id.';

-- ----------------------------------------------------------------------------
-- 2.a) get_courier_routed_order_offers: admin bayrağı + durum filtresi
--
-- Eski sürüm yalnız o.status = 'ready' teklifleri döndürüyordu; devretme
-- akışında sipariş zaten 'ready'ye çekildiği için sorun değildi. Admin
-- yönlendirmesi ise confirmed/preparing siparişlerde de yapılabilmeli
-- (genel havuz da bu üç durumu kabul ediyor), bu yüzden filtre havuzla
-- aynı kümeye genişletildi.
-- Dönüş sütunu eklendiği için CREATE OR REPLACE yetmez, önce DROP gerekir.
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_courier_routed_order_offers();

CREATE FUNCTION public.get_courier_routed_order_offers()
RETURNS TABLE(
  offer_id uuid,
  assignment_id uuid,
  fee_amount numeric,
  order_id uuid,
  order_total numeric,
  order_status text,
  delivery_address_text text,
  customer_phone text,
  created_at timestamp with time zone,
  shop_id uuid,
  shop_name text,
  order_items_json jsonb,
  shop_phone text,
  shop_address text,
  shop_latitude numeric,
  shop_longitude numeric,
  routed_by_admin boolean
)
LANGUAGE plpgsql
STABLE SECURITY DEFINER
SET search_path TO ''
AS $fn$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_courier_role() THEN
    RAISE EXCEPTION 'APP:forbidden | kurye rolü gerekli' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    cwo.id::uuid,
    ca.id::uuid,
    ca.fee_amount::numeric,
    o.id::uuid,
    o.total::numeric,
    o.status::text,
    o.delivery_address_text::text,
    o.customer_phone::text,
    o.created_at::timestamptz,
    o.shop_id::uuid,
    s.name::text,
    COALESCE(
      (
        SELECT jsonb_agg(
          jsonb_build_object(
            'quantity', oi.quantity,
            'product_name', oi.product_name
          ) ORDER BY oi.product_name, oi.quantity
        )
        FROM public.order_items AS oi
        WHERE oi.order_id = o.id
      ),
      '[]'::jsonb
    ),
    s.phone::text,
    s.address::text,
    s.latitude::numeric,
    s.longitude::numeric,
    cwo.routed_by_admin::boolean
  FROM public.courier_work_offers AS cwo
  JOIN public.courier_assignments AS ca
    ON ca.id = cwo.assignment_id
   AND ca.order_id = cwo.order_id
   AND ca.courier_id = cwo.courier_id
  JOIN public.orders AS o ON o.id = cwo.order_id
  JOIN public.shops AS s ON s.id = o.shop_id
  WHERE cwo.work_type = 'order'
    AND cwo.status = 'pending'
    AND cwo.courier_id = v_uid
    AND ca.status = 'assigned'
    AND o.status IN ('confirmed', 'preparing', 'ready')
    AND o.is_pickup = false
  ORDER BY cwo.offered_at ASC;
END;
$fn$;

REVOKE ALL ON FUNCTION public.get_courier_routed_order_offers() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_courier_routed_order_offers()
  TO authenticated, service_role;

COMMENT ON FUNCTION public.get_courier_routed_order_offers() IS
  'Kuryeye özel bekleyen sipariş teklifleri (devir ya da admin yönlendirmesi). routed_by_admin = adminin doğrudan atadığı işler.';

-- ----------------------------------------------------------------------------
-- 2.b) admin_route_order_to_courier: siparişi istenen kuryenin paneline düşür
--
-- Sonuç: aktif courier_assignments satırı (status 'assigned') + hedef kuryeye
-- pending courier_work_offers teklifi. Sipariş genel havuzdan çıkar
-- (get_available_orders_for_courier aktif atamalı siparişleri eler) ve
-- get_courier_routed_order_offers üzerinden yalnız hedef kuryede görünür.
-- Kurye kabul edince mevcut accept_routed_order_offer akışı devralır.
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_route_order_to_courier(uuid, uuid);

CREATE FUNCTION public.admin_route_order_to_courier(
  p_order_id uuid,
  p_courier_id uuid
)
RETURNS TABLE(
  r_assignment_id uuid,
  r_offer_id uuid,
  r_courier_id uuid,
  r_courier_name text,
  r_order_status text,
  r_previous_courier_id uuid
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_order public.orders%ROWTYPE;
  v_assignment public.courier_assignments%ROWTYPE;
  v_target_existing public.courier_assignments%ROWTYPE;
  v_had_pending_offer boolean := false;
  v_prev_courier uuid;
  v_assignment_id uuid;
  v_offer_id uuid;
  v_fee numeric(12, 2);
  v_courier_name text;
  v_shop_name text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden | admin gerekli' USING ERRCODE = '42501';
  END IF;
  IF p_order_id IS NULL OR p_courier_id IS NULL THEN
    RAISE EXCEPTION 'APP:order_and_courier_required' USING ERRCODE = '22023';
  END IF;

  SELECT o.* INTO v_order
  FROM public.orders AS o
  WHERE o.id = p_order_id
  FOR UPDATE;

  IF v_order.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found | sipariş bulunamadı' USING ERRCODE = 'P0001';
  END IF;
  IF v_order.is_pickup THEN
    RAISE EXCEPTION 'APP:pickup_order | Gel Al siparişine kurye atanamaz'
      USING ERRCODE = 'P0001';
  END IF;
  IF v_order.status NOT IN ('confirmed', 'preparing', 'ready', 'on_the_way') THEN
    RAISE EXCEPTION 'APP:invalid_order_status | bu durumdaki siparişe kurye atanamaz'
      USING ERRCODE = 'P0001';
  END IF;
  IF v_order.user_id = p_courier_id THEN
    RAISE EXCEPTION 'APP:self_delivery | kurye kendi siparişini teslim alamaz'
      USING ERRCODE = 'P0001';
  END IF;

  -- Hedef gerçekten kurye mi ve evrakı onaylı mı?
  IF NOT EXISTS (
    SELECT 1 FROM public.profiles AS p
    WHERE p.id = p_courier_id AND p.role = 'courier'::public.user_role
  ) THEN
    RAISE EXCEPTION 'APP:not_a_courier | seçilen kullanıcı kurye değil'
      USING ERRCODE = 'P0001';
  END IF;
  IF NOT public.is_courier_document_approved(p_courier_id) THEN
    RAISE EXCEPTION 'APP:courier_documents_not_approved | kuryenin evrakları onaylı değil'
      USING ERRCODE = '42501';
  END IF;

  -- Mevcut aktif atama (varsa) önce serbest bırakılır.
  --
  -- courier_assignments üzerinde UNIQUE (order_id, courier_id) var; bu yüzden
  -- atama satırının courier_id'sini "devretmek" yerine eski satır iptal edilip
  -- hedef kuryenin satırı upsert edilir. Aksi halde daha önce bu siparişe
  -- atanıp iptal edilmiş bir kuryeye yeniden yönlendirme 23505 verirdi.
  SELECT ca.* INTO v_assignment
  FROM public.courier_assignments AS ca
  WHERE ca.order_id = p_order_id
    AND ca.status IN ('assigned', 'picked_up', 'on_the_way')
  ORDER BY ca.assigned_at DESC NULLS LAST
  LIMIT 1
  FOR UPDATE;

  IF v_assignment.id IS NOT NULL THEN
    IF v_assignment.courier_id = p_courier_id THEN
      RAISE EXCEPTION 'APP:already_assigned_to_courier | sipariş zaten bu kuryede'
        USING ERRCODE = 'P0001';
    END IF;
    IF v_assignment.status <> 'assigned' THEN
      RAISE EXCEPTION 'APP:already_picked_up | sipariş mevcut kurye tarafından teslim alındı'
        USING ERRCODE = 'P0001';
    END IF;

    v_prev_courier := v_assignment.courier_id;
    SELECT EXISTS (
      SELECT 1 FROM public.courier_work_offers AS cwo
      WHERE cwo.assignment_id = v_assignment.id AND cwo.status = 'pending'
    ) INTO v_had_pending_offer;

    -- Eski teklifi kapat, eski atamayı iptal et.
    UPDATE public.courier_work_offers
       SET status = 'expired', responded_at = now()
     WHERE assignment_id = v_assignment.id
       AND status = 'pending';

    UPDATE public.courier_assignments
       SET status = 'cancelled'
     WHERE id = v_assignment.id;

    -- Kabul etmiş kurye elinden alınıyorsa sipariş yeniden "hazır" olur;
    -- müşteriye "yolda" denmiş olmasın diye durum geri çekilir.
    IF NOT v_had_pending_offer AND v_order.status = 'on_the_way' THEN
      UPDATE public.orders
         SET status = 'ready', updated_at = now()
       WHERE id = p_order_id;
      v_order.status := 'ready';
    END IF;

    IF v_prev_courier IS NOT NULL AND NOT v_had_pending_offer THEN
      PERFORM public.add_notification(
        p_user_id   => v_prev_courier,
        p_type      => 'courier_order_assigned',
        p_title     => 'Sipariş Başka Kuryeye Aktarıldı',
        p_content   => 'Yönetici bu siparişi başka bir kuryeye aktardı.',
        p_entity_id => p_order_id::text
      );
    END IF;
  END IF;

  -- Teslim edilmiş atama canlandırılmaz: kazanç/ödeme kayıtları o satıra
  -- bağlı, delivered_at'i sıfırlamak muhasebeyi bozar.
  SELECT ca.* INTO v_target_existing
  FROM public.courier_assignments AS ca
  WHERE ca.order_id = p_order_id
    AND ca.courier_id = p_courier_id
  FOR UPDATE;

  IF v_target_existing.id IS NOT NULL
     AND v_target_existing.status = 'delivered' THEN
    RAISE EXCEPTION 'APP:already_delivered_by_courier | bu kurye siparişi zaten teslim etmiş'
      USING ERRCODE = 'P0001';
  END IF;

  -- Ücret: courier_settings.fee_per_delivery (yoksa 15)
  SELECT cs.fee_per_delivery INTO v_fee
  FROM public.courier_settings AS cs
  LIMIT 1;
  v_fee := COALESCE(v_fee, 15);

  -- Hedef kuryenin bu siparişte eski (iptal/ret) satırı varsa canlandırılır.
  INSERT INTO public.courier_assignments (
    order_id, courier_id, status, fee_amount, assigned_at
  ) VALUES (
    p_order_id, p_courier_id, 'assigned', v_fee, now()
  )
  ON CONFLICT (order_id, courier_id) DO UPDATE
     SET status = 'assigned',
         fee_amount = EXCLUDED.fee_amount,
         assigned_at = now(),
         picked_up_at = NULL,
         delivered_at = NULL
  RETURNING id INTO v_assignment_id;

  -- Admin kararı, kuryenin daha önceki reddini geçersiz kılar.
  DELETE FROM public.courier_order_rejections AS cor
   WHERE cor.order_id = p_order_id
     AND cor.courier_id = p_courier_id;

  INSERT INTO public.courier_work_offers (
    work_type, order_id, assignment_id, courier_id, routed_by_admin, routed_by
  ) VALUES (
    'order', p_order_id, v_assignment_id, p_courier_id, true, v_uid
  )
  RETURNING id INTO v_offer_id;

  SELECT COALESCE(p.full_name, p.username, 'Kurye') INTO v_courier_name
  FROM public.profiles AS p
  WHERE p.id = p_courier_id;

  SELECT s.name INTO v_shop_name
  FROM public.shops AS s
  WHERE s.id = v_order.shop_id;

  PERFORM public.add_notification(
    p_user_id   => p_courier_id,
    p_type      => 'courier_order_assigned',
    p_title     => 'Yönetici Sana Sipariş Yönlendirdi',
    p_content   => COALESCE(v_shop_name, 'Bir dükkân')
                   || ' siparişi yönetici tarafından sana atandı. Kurye panelinden kabul edebilirsin.',
    p_entity_id => p_order_id::text
  );

  RETURN QUERY
  SELECT v_assignment_id, v_offer_id, p_courier_id, v_courier_name,
         v_order.status::text, v_prev_courier;
END;
$fn$;

REVOKE ALL ON FUNCTION public.admin_route_order_to_courier(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_route_order_to_courier(uuid, uuid)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.admin_route_order_to_courier(uuid, uuid) IS
  'Admin: siparişi seçilen kuryenin paneline düşürür (aktif atama + pending teklif). Sipariş genel havuzdan çıkar; teslim alınmış siparişler devredilemez.';

-- ----------------------------------------------------------------------------
-- 2.c) admin_cancel_order_courier_routing: yönlendirmeyi geri al
--   Atama iptal edilir, sipariş genel kurye havuzuna döner.
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.admin_cancel_order_courier_routing(uuid);

CREATE FUNCTION public.admin_cancel_order_courier_routing(p_order_id uuid)
RETURNS TABLE(
  r_assignment_id uuid,
  r_order_status text
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_assignment public.courier_assignments%ROWTYPE;
  v_order_status text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'APP:forbidden | admin gerekli' USING ERRCODE = '42501';
  END IF;
  IF p_order_id IS NULL THEN
    RAISE EXCEPTION 'APP:order_id_required' USING ERRCODE = '22023';
  END IF;

  SELECT ca.* INTO v_assignment
  FROM public.courier_assignments AS ca
  WHERE ca.order_id = p_order_id
    AND ca.status IN ('assigned', 'picked_up', 'on_the_way')
  ORDER BY ca.assigned_at DESC NULLS LAST
  LIMIT 1
  FOR UPDATE;

  IF v_assignment.id IS NULL THEN
    RAISE EXCEPTION 'APP:not_found | siparişte aktif kurye ataması yok'
      USING ERRCODE = 'P0001';
  END IF;
  IF v_assignment.status <> 'assigned' THEN
    RAISE EXCEPTION 'APP:already_picked_up | teslim alınmış sipariş havuza döndürülemez'
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.courier_work_offers
     SET status = 'expired', responded_at = now()
   WHERE assignment_id = v_assignment.id
     AND status = 'pending';

  UPDATE public.courier_assignments
     SET status = 'cancelled'
   WHERE id = v_assignment.id;

  UPDATE public.orders
     SET status = CASE WHEN status = 'on_the_way' THEN 'ready' ELSE status END,
         updated_at = now()
   WHERE id = p_order_id
  RETURNING status INTO v_order_status;

  PERFORM public.add_notification(
    p_user_id   => v_assignment.courier_id,
    p_type      => 'courier_order_assigned',
    p_title     => 'Sipariş Ataması Kaldırıldı',
    p_content   => 'Yönetici bu siparişin atamasını kaldırdı.',
    p_entity_id => p_order_id::text
  );

  RETURN QUERY SELECT v_assignment.id, v_order_status;
END;
$fn$;

REVOKE ALL ON FUNCTION public.admin_cancel_order_courier_routing(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_cancel_order_courier_routing(uuid)
  TO authenticated, service_role;

COMMENT ON FUNCTION public.admin_cancel_order_courier_routing(uuid) IS
  'Admin: sipariş-kurye yönlendirmesini iptal eder; sipariş genel kurye havuzuna döner.';

DO $notify$
BEGIN
  PERFORM pg_notify('pgrst', 'reload schema');
EXCEPTION WHEN OTHERS THEN
  NULL;
END;
$notify$;

-- ----------------------------------------------------------------------------
-- 2.d) accept_routed_order_offer: kabul edilebilir sipariş durumlarını havuzla
--      hizala.
--
-- Eski sürüm yalnız o.status = 'ready' teklifini kabul ediyordu; devretme
-- akışında sipariş zaten 'ready'ye çekildiği için yeterliydi. Admin
-- yönlendirmesi confirmed/preparing siparişte de yapılabildiği için (genel
-- havuz ve assign_order_to_courier de bu üç durumu kabul ediyor) aynı küme
-- burada da geçerli olmalı — aksi halde admin'in yönlendirdiği sipariş
-- kuryede görünür ama kabul denemesinde 'offer_stale' ile teklifi öldürürdü.
-- Gövdenin geri kalanı canlı sürümle birebir aynıdır.
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.accept_routed_order_offer(p_offer_id uuid)
RETURNS TABLE(r_assignment_id uuid, r_order_id uuid, r_fee_amount numeric, r_order_status text)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO ''
AS $fn$
DECLARE
  v_uid CONSTANT uuid := (SELECT auth.uid());
  v_offer public.courier_work_offers%ROWTYPE;
  v_assignment public.courier_assignments%ROWTYPE;
  v_order public.orders%ROWTYPE;
  v_courier_name text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'APP:auth_required' USING ERRCODE = '42501';
  END IF;
  IF p_offer_id IS NULL THEN
    RAISE EXCEPTION 'APP:offer_id_required' USING ERRCODE = '22023';
  END IF;
  IF NOT public.is_courier_role() THEN
    RAISE EXCEPTION 'APP:forbidden | kurye rolü gerekli' USING ERRCODE = '42501';
  END IF;
  IF NOT public.is_courier_document_approved(v_uid) THEN
    RAISE EXCEPTION 'APP:courier_documents_not_approved' USING ERRCODE = '42501';
  END IF;

  SELECT cwo.* INTO v_offer
  FROM public.courier_work_offers AS cwo
  WHERE cwo.id = p_offer_id
  FOR UPDATE;

  IF v_offer.id IS NULL OR v_offer.work_type <> 'order' THEN
    RAISE EXCEPTION 'APP:not_found' USING ERRCODE = 'P0001';
  END IF;
  IF v_offer.courier_id <> v_uid THEN
    RAISE EXCEPTION 'APP:not_offer_owner' USING ERRCODE = '42501';
  END IF;
  IF v_offer.status <> 'pending' THEN
    RAISE EXCEPTION 'APP:offer_not_pending' USING ERRCODE = 'P0001';
  END IF;

  SELECT ca.* INTO v_assignment
  FROM public.courier_assignments AS ca
  WHERE ca.id = v_offer.assignment_id
  FOR UPDATE;

  SELECT o.* INTO v_order
  FROM public.orders AS o
  WHERE o.id = v_offer.order_id
  FOR UPDATE;

  IF v_assignment.id IS NULL
     OR v_assignment.order_id <> v_offer.order_id
     OR v_assignment.courier_id <> v_uid
     OR v_assignment.status <> 'assigned'
     OR v_order.id IS NULL
     OR v_order.status NOT IN ('confirmed', 'preparing', 'ready') THEN
    UPDATE public.courier_work_offers
    SET status = 'expired', responded_at = now()
    WHERE id = p_offer_id;
    RAISE EXCEPTION 'APP:offer_stale' USING ERRCODE = 'P0001';
  END IF;

  UPDATE public.courier_work_offers
  SET status = 'accepted', responded_at = now()
  WHERE id = p_offer_id;

  UPDATE public.orders
  SET status = 'on_the_way', updated_at = now()
  WHERE id = v_order.id;

  SELECT COALESCE(p.full_name, p.username, 'Kurye') INTO v_courier_name
  FROM public.profiles AS p
  WHERE p.id = v_uid;

  PERFORM public.add_notification(
    p_user_id => v_order.user_id,
    p_type => 'order_update',
    p_title => '🚴 Siparişiniz Yolda!',
    p_content => COALESCE(v_courier_name, 'Kurye') ||
      ' siparişinizi teslim etmek için yola çıktı.',
    p_entity_id => v_order.id::text
  );

  RETURN QUERY SELECT
    v_assignment.id,
    v_order.id,
    v_assignment.fee_amount::numeric,
    'on_the_way'::text;
END;
$fn$;

REVOKE ALL ON FUNCTION public.accept_routed_order_offer(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.accept_routed_order_offer(uuid) TO authenticated;
