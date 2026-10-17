-- ============================================================================
-- Kötüye kullanım / gizlilik düzeltmeleri (2026-10-17)
-- ----------------------------------------------------------------------------
-- Canlı taramada (istemcinin çağırabildiği, çağıranı doğrulamayan SECURITY
-- DEFINER fonksiyonlar) bulunanlar:
--
-- 1) get_pending_reviews(p_user_id): p_user_id çağıranla karşılaştırılmıyordu;
--    herhangi bir kullanıcı başkasının son 30 günde hangi dükkândan ne
--    aldığını (sipariş id, ürün adı) okuyabiliyordu. → yalnız kendisi/admin.
--
-- 2) add_notification: herhangi bir kullanıcı herhangi birine, istediği
--    gönderen kimliğiyle (actor_id/ad/avatar) ve istediği türde ("admin_…",
--    "balance…") bildirim yazabiliyordu (oltalama, spam). İstemcide 8 akış
--    (sipariş durumu, kurye talebi, beğeni…) bu RPC'yi kullandığı için
--    ilişki zorunluluğu yerine kırmayan sertleştirme:
--      • gönderen taklidi yok: actor_id verilirse çağıranın kendisi olmalı,
--        değilse çağırana çevrilir ve ad/avatar profilden alınır;
--      • sistem/para türleri yalnız admin ve service_role;
--      • gönderen başına dakikada 30 bildirim (aşan sessizce atlanır);
--      • başlık 200, içerik 2000 karakterle sınırlı.
--
-- 3) Flaş satış stoku: istemci sepete eklerken claim_flash_sale ile
--    sold_count'u artırıp çıkarırken release_flash_sale ile azaltıyor.
--      • İkisi de çağıranı izlemiyordu: herkes claim ile bir fırsatı
--        "tükendi" yapabilir, release ile sold_count'u sıfırlayıp satıcının
--        stok sınırının üstünde satış açabilirdi.
--      • Ana sepet ödemesi (eski doğrudan-insert akışı) başarıdan sonra
--        cartProvider.clearCart() çağırıyor; bu da sepetteki flaş kalemleri
--        release ediyordu → satılan flaş adetleri hiç sayılmıyordu.
--    Çözüm (istemci değişmeden): kullanıcı başına talep defteri
--    (private.flash_sale_claims). release yalnız kendi talebi kadar geri
--    verir; eski akışta sipariş kalemi oluşunca talep "tüketilir" (sonraki
--    clearCart release'i boşa düşer, satış sayılı kalır); talep yoksa/süresi
--    dolduysa satış o anda sayılır. Eski akışta sipariş iptal olursa talep
--    sepete geri yazılır. 2 saatten eski talepler 15 dakikada bir serbest
--    bırakılır (terk edilen sepet stoğu kilitlemesin). Kişi başı aynı
--    fırsattan aynı anda en fazla 5 adet talep.
--    Sunucu oturumlu akış (checkout_session_id dolu; commit_*_order kendi
--    rezervasyonuyla sayar) bu defterden etkilenmez.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1) get_pending_reviews: yalnız kendisi (veya admin)
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_pending_reviews(p_user_id uuid)
 RETURNS TABLE(order_id uuid, digital_order_id uuid, is_digital boolean, shop_id uuid, shop_name text, shop_logo text, order_date timestamp with time zone, delivered_at timestamp with time zone, product_id uuid, product_name text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
    IF auth.uid() IS NULL
       OR (p_user_id IS DISTINCT FROM auth.uid() AND NOT public.auth_is_admin()) THEN
        RETURN;
    END IF;

    RETURN QUERY
    -- Fiziksel siparişler
    SELECT
        o.id as order_id,
        NULL::UUID as digital_order_id,
        FALSE as is_digital,
        o.shop_id,
        s.name as shop_name,
        s.logo_url as shop_logo,
        o.created_at as order_date,
        o.updated_at as delivered_at,
        (SELECT oi.product_id FROM order_items oi WHERE oi.order_id = o.id LIMIT 1) as product_id,
        (SELECT oi.product_name FROM order_items oi WHERE oi.order_id = o.id LIMIT 1) as product_name
    FROM orders o
    JOIN shops s ON s.id = o.shop_id
    LEFT JOIN shop_reviews sr ON sr.shop_id = o.shop_id AND sr.user_id = o.user_id AND sr.order_id = o.id
    LEFT JOIN product_reviews pr ON pr.order_id = o.id AND pr.user_id = o.user_id
    WHERE o.user_id = p_user_id
    AND o.status = 'delivered'
    AND o.review_reminder_dismissed IS NOT TRUE
    AND sr.id IS NULL
    AND pr.id IS NULL
    AND o.updated_at >= NOW() - INTERVAL '30 days'

    UNION ALL

    -- Tamamlanmış dijital (SMM) siparişler
    SELECT
        NULL::UUID as order_id,
        d.id as digital_order_id,
        TRUE as is_digital,
        p.shop_id,
        s.name as shop_name,
        s.logo_url as shop_logo,
        d.created_at as order_date,
        d.last_checked_at as delivered_at,
        d.product_id,
        p.name as product_name
    FROM digital_orders d
    JOIN products p ON p.id = d.product_id
    JOIN shops s ON s.id = p.shop_id
    LEFT JOIN shop_reviews sr ON sr.shop_id = p.shop_id AND sr.user_id = d.user_id AND sr.digital_order_id = d.id
    LEFT JOIN product_reviews pr ON pr.digital_order_id = d.id AND pr.user_id = d.user_id
    WHERE d.user_id = p_user_id
    AND d.status = 'completed'
    AND d.review_reminder_dismissed IS NOT TRUE
    AND sr.id IS NULL
    AND pr.id IS NULL
    AND d.created_at >= NOW() - INTERVAL '30 days'

    ORDER BY delivered_at DESC;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 2) add_notification sertleştirme
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS private.notification_send_rate (
  sender_id    uuid        NOT NULL,
  window_start timestamptz NOT NULL,
  n            integer     NOT NULL DEFAULT 0,
  PRIMARY KEY (sender_id, window_start)
);
REVOKE ALL ON private.notification_send_rate FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.add_notification(p_user_id uuid, p_type text, p_title text, p_content text, p_actor_id uuid DEFAULT NULL::uuid, p_actor_name text DEFAULT NULL::text, p_actor_avatar text DEFAULT NULL::text, p_entity_id text DEFAULT NULL::text, p_entity_image text DEFAULT NULL::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  c_per_minute CONSTANT integer := 30;
  v_new_id  uuid;
  v_uid     uuid := auth.uid();
  v_count   integer;
BEGIN
  IF v_uid IS NULL THEN
    -- Yalnız sunucu (service_role) kullanıcısız çağırabilir.
    IF COALESCE(NULLIF(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role', '') <> 'service_role' THEN
      RAISE EXCEPTION 'add_notification: oturum gerekli' USING ERRCODE = '28000';
    END IF;
  ELSIF NOT public.auth_is_admin() THEN
    -- Sistem / para / moderasyon türleri istemciden yazılamaz.
    IF p_type IS NULL
       OR p_type ~* '^(admin|system|balance|wallet|payment|payout|withdraw|refund|topup|reward|security|account|verification|task_|return_|cancellation|sponsorship|digital_order|courier_document)' THEN
      RETURN NULL;
    END IF;

    -- Gönderen taklidi: actor_id verildiyse çağıranın kendisi olmalı.
    IF p_actor_id IS NOT NULL AND p_actor_id <> v_uid THEN
      p_actor_id := v_uid;
      SELECT COALESCE(NULLIF(pr.full_name, ''), pr.username), pr.avatar_url
        INTO p_actor_name, p_actor_avatar
      FROM public.profiles pr
      WHERE pr.id = v_uid;
    END IF;

    -- Hız sınırı (gönderen başına dakikalık pencere).
    INSERT INTO private.notification_send_rate AS r (sender_id, window_start, n)
    VALUES (v_uid, date_trunc('minute', now()), 1)
    ON CONFLICT (sender_id, window_start) DO UPDATE SET n = r.n + 1
    RETURNING r.n INTO v_count;

    IF random() < 0.02 THEN
      DELETE FROM private.notification_send_rate
      WHERE window_start < now() - interval '1 day';
    END IF;

    IF v_count > c_per_minute THEN
      RETURN NULL;
    END IF;
  END IF;

  INSERT INTO public.notifications (
    user_id, type, title, content,
    actor_id, actor_name, actor_avatar,
    entity_id, entity_image,
    is_read, created_at
  )
  VALUES (
    p_user_id, p_type, left(p_title, 200), left(p_content, 2000),
    p_actor_id, p_actor_name, p_actor_avatar,
    p_entity_id, p_entity_image,
    FALSE, NOW()
  )
  RETURNING id INTO v_new_id;

  RETURN v_new_id;
END;
$function$;

-- ---------------------------------------------------------------------------
-- 3) Flaş satış talep defteri
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS private.flash_sale_claims (
  user_id    uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  sale_id    uuid        NOT NULL REFERENCES public.flash_sales(id) ON DELETE CASCADE,
  quantity   integer     NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, sale_id)
);
CREATE INDEX IF NOT EXISTS idx_flash_sale_claims_sale_id ON private.flash_sale_claims (sale_id);
CREATE INDEX IF NOT EXISTS idx_flash_sale_claims_open_updated
  ON private.flash_sale_claims (updated_at) WHERE quantity > 0;
REVOKE ALL ON private.flash_sale_claims FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.claim_flash_sale(p_sale_id uuid, p_quantity integer, p_user_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  c_per_user_max CONSTANT integer := 5;
  v_uid       uuid := auth.uid();  -- p_user_id geriye uyum için duruyor, kullanılmaz
  v_sale      flash_sales%ROWTYPE;
  v_reserved  integer;
  v_remaining integer;
  v_mine      integer;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Oturum açmanız gerekli');
  END IF;

  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Geçersiz miktar');
  END IF;

  -- Row-level kilitle (FOR UPDATE) - eşzamanlı claim'ler sıralı işlenir
  SELECT * INTO v_sale
    FROM flash_sales
    WHERE id = p_sale_id
    FOR UPDATE;

  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Satış bulunamadı');
  END IF;

  IF NOT v_sale.is_active THEN
    RETURN jsonb_build_object('success', false, 'error', 'Satış aktif değil');
  END IF;

  IF NOW() < v_sale.start_at THEN
    RETURN jsonb_build_object('success', false, 'error', 'Satış henüz başlamadı');
  END IF;

  IF NOW() >= v_sale.end_at THEN
    RETURN jsonb_build_object('success', false, 'error', 'Satış süresi doldu');
  END IF;

  -- Sunucu oturumlu ödemenin aktif rezervasyonları da stoktan düşer.
  SELECT COALESCE(SUM(fsr.quantity), 0) INTO v_reserved
  FROM private.flash_sale_reservations fsr
  WHERE fsr.sale_id = p_sale_id
    AND fsr.status = 'active'
    AND fsr.expires_at > NOW();

  v_remaining := v_sale.stock_limit - v_sale.sold_count - v_reserved;
  IF p_quantity > v_remaining THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', 'Yetersiz stok',
      'remaining', GREATEST(v_remaining, 0)
    );
  END IF;

  SELECT c.quantity INTO v_mine
  FROM private.flash_sale_claims c
  WHERE c.user_id = v_uid AND c.sale_id = p_sale_id
  FOR UPDATE;

  IF COALESCE(v_mine, 0) + p_quantity > c_per_user_max THEN
    RETURN jsonb_build_object(
      'success', false,
      'error', format('Bu fırsattan kişi başı en fazla %s adet sepete eklenebilir', c_per_user_max),
      'remaining', v_remaining
    );
  END IF;

  UPDATE flash_sales
    SET sold_count = sold_count + p_quantity
    WHERE id = p_sale_id;

  INSERT INTO private.flash_sale_claims AS c (user_id, sale_id, quantity)
  VALUES (v_uid, p_sale_id, p_quantity)
  ON CONFLICT (user_id, sale_id) DO UPDATE
    SET quantity = c.quantity + EXCLUDED.quantity,
        updated_at = NOW();

  RETURN jsonb_build_object(
    'success', true,
    'remaining', v_remaining - p_quantity,
    'flash_price', v_sale.flash_price,
    'product_id', v_sale.product_id
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.release_flash_sale(p_sale_id uuid, p_quantity integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid  uuid := auth.uid();
  v_mine integer;
  v_rel  integer;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('success', false, 'error', 'Oturum açmanız gerekli');
  END IF;

  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RETURN jsonb_build_object('success', false, 'error', 'Geçersiz miktar');
  END IF;

  PERFORM 1 FROM flash_sales WHERE id = p_sale_id FOR UPDATE;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('success', false, 'error', 'Satış bulunamadı');
  END IF;

  -- Yalnız kendi (henüz satın alınmamış) talebi kadar geri verilir.
  SELECT c.quantity INTO v_mine
  FROM private.flash_sale_claims c
  WHERE c.user_id = v_uid AND c.sale_id = p_sale_id
  FOR UPDATE;

  v_rel := LEAST(p_quantity, COALESCE(v_mine, 0));
  IF v_rel > 0 THEN
    UPDATE flash_sales
      SET sold_count = GREATEST(0, sold_count - v_rel)
      WHERE id = p_sale_id;
    UPDATE private.flash_sale_claims
      SET quantity = quantity - v_rel, updated_at = NOW()
      WHERE user_id = v_uid AND sale_id = p_sale_id;
  END IF;

  RETURN jsonb_build_object('success', true, 'released', v_rel);
END;
$function$;

-- Eski (doğrudan insert) akışta flaş kalem siparişe dönüşünce talep tüketilir.
CREATE OR REPLACE FUNCTION private.consume_flash_sale_claim_on_order_item()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_user    uuid;
  v_session uuid;
  v_mine    integer;
  v_take    integer;
BEGIN
  IF NEW.flash_sale_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT o.user_id, o.checkout_session_id
    INTO v_user, v_session
  FROM public.orders o
  WHERE o.id = NEW.order_id;

  -- Sunucu oturumlu akış sold_count'u rezervasyonla kendisi sayar.
  IF v_user IS NULL OR v_session IS NOT NULL THEN
    RETURN NEW;
  END IF;

  SELECT c.quantity INTO v_mine
  FROM private.flash_sale_claims c
  WHERE c.user_id = v_user AND c.sale_id = NEW.flash_sale_id
  FOR UPDATE;

  v_take := LEAST(COALESCE(v_mine, 0), NEW.quantity);
  IF v_take > 0 THEN
    UPDATE private.flash_sale_claims
      SET quantity = quantity - v_take, updated_at = now()
      WHERE user_id = v_user AND sale_id = NEW.flash_sale_id;
  END IF;

  -- Talep yoksa / süresi dolup serbest bırakıldıysa satış burada sayılır.
  IF NEW.quantity > v_take THEN
    UPDATE public.flash_sales
      SET sold_count = sold_count + (NEW.quantity - v_take)
      WHERE id = NEW.flash_sale_id;
  END IF;

  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.consume_flash_sale_claim_on_order_item() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_order_items_consume_flash_claim ON public.order_items;
CREATE TRIGGER trg_order_items_consume_flash_claim
  AFTER INSERT ON public.order_items
  FOR EACH ROW EXECUTE FUNCTION private.consume_flash_sale_claim_on_order_item();

-- Eski akışta sipariş iptal olursa flaş adetleri talep olarak geri yazılır
-- (kalem sepette kaldıysa kullanıcı tekrar dener ya da çıkarınca release
-- eder; kalmadıysa süre dolunca serbest kalır).
CREATE OR REPLACE FUNCTION private.restore_flash_sale_claims_on_cancel()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
BEGIN
  IF NEW.status = 'cancelled'
     AND OLD.status IS DISTINCT FROM 'cancelled'
     AND NEW.checkout_session_id IS NULL
     AND NEW.user_id IS NOT NULL THEN
    INSERT INTO private.flash_sale_claims AS c (user_id, sale_id, quantity)
    SELECT NEW.user_id, oi.flash_sale_id, SUM(oi.quantity)::integer
    FROM public.order_items oi
    JOIN public.flash_sales f ON f.id = oi.flash_sale_id
    WHERE oi.order_id = NEW.id
    GROUP BY oi.flash_sale_id
    ON CONFLICT (user_id, sale_id) DO UPDATE
      SET quantity = c.quantity + EXCLUDED.quantity,
          updated_at = now();
  END IF;
  RETURN NEW;
END;
$function$;

REVOKE ALL ON FUNCTION private.restore_flash_sale_claims_on_cancel() FROM PUBLIC, anon, authenticated;

DROP TRIGGER IF EXISTS trg_orders_restore_flash_claims_on_cancel ON public.orders;
CREATE TRIGGER trg_orders_restore_flash_claims_on_cancel
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW EXECUTE FUNCTION private.restore_flash_sale_claims_on_cancel();

-- Terk edilen sepet talepleri (2 saat) stoğa geri döner.
CREATE OR REPLACE FUNCTION private.release_expired_flash_sale_claims()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_released integer := 0;
BEGIN
  WITH expired AS (
    DELETE FROM private.flash_sale_claims
    WHERE quantity > 0 AND updated_at < now() - interval '2 hours'
    RETURNING sale_id, quantity
  ), per_sale AS (
    SELECT sale_id, SUM(quantity)::integer AS q FROM expired GROUP BY sale_id
  ), upd AS (
    UPDATE public.flash_sales f
       SET sold_count = GREATEST(0, f.sold_count - p.q)
      FROM per_sale p
     WHERE f.id = p.sale_id
    RETURNING p.q
  )
  SELECT COALESCE(SUM(q), 0) INTO v_released FROM upd;

  DELETE FROM private.flash_sale_claims
  WHERE quantity = 0 AND updated_at < now() - interval '1 day';

  RETURN v_released;
END;
$function$;

REVOKE ALL ON FUNCTION private.release_expired_flash_sale_claims() FROM PUBLIC, anon, authenticated;

SELECT cron.schedule(
  'release-expired-flash-sale-claims',
  '*/15 * * * *',
  'select private.release_expired_flash_sale_claims();'
);

COMMIT;

NOTIFY pgrst, 'reload schema';
