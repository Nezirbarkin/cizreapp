-- =============================================================================
-- Canlı yayın: "yayın başladı" bildirimi, abonelik, yayın geçmişi, ana sayfa kartı
-- =============================================================================
--
-- 1) Bildirim (uygulama içi + push, notifications outbox'ı üzerinden): yayın
--    hazırlıktan canlıya İLK geçtiğinde alıcılar, öncelik sırasıyla:
--      mağazaya abone olanlar → satıcıyı takip edenler → mağazanın ürünlerini
--      favorileyenler → (isteğe bağlı) son 90 günün müşterileri.
--    Satıcı/yayıncı, botlar, askıdaki/silinmiş hesaplar, satıcıyla
--    engelleşenler ve bildirim tercihinde "Canlı yayınlar"ı kapatanlar hariç.
--    Aynı mağaza için bekleme süresi (varsayılan 3 sa): bağlantısı kopup
--    yeniden açılan yayın tekrar bildirmez. Bildirim hatası yayını ASLA
--    engellemez (alt işlem). start_live_session dönüşüne `notified` eklenir.
-- 2) live_subscriptions — "yayınlarından haberdar ol" (kişi yalnız kendi
--    satırını okur; yazma RPC ile).
-- 3) Yayın geçmişi: biten yayınlar ayardaki gün kadar (varsayılan 30);
--    her satırda süre, mesaj sayısı ve "yayında öne çıkan ürünler"
--    (live_pinned_products). live_session_detail de bu alanları döner.
-- 4) live_home_card(): ana sayfadaki Şehiriçi kartının yanındaki kart —
--    canlı yayın varsa en çok izleneni, yoksa son biten yayını gösterir.
-- 5) Yönetici ayarları: admin_live_options / admin_set_live_options.
--
-- start_live_session gövdesi 20260928000016'dan birebir kopyalanır; yalnız
-- bildirim bloğu ve dönüş satırı değişir (sözleşme testi doğrular).

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Ayarlar ve bildirim tercihi
-- -----------------------------------------------------------------------------
INSERT INTO public.app_settings (key, value, description)
VALUES
  ('live_notify_enabled', '"true"', 'Canlı yayın başlayınca ilgili kullanıcılara bildirim gönderilsin mi.'),
  ('live_notify_cooldown_hours', '"3"', 'Aynı mağaza için iki yayın bildirimi arasındaki en kısa süre (saat, 0–72).'),
  ('live_notify_followers', '"true"', 'Satıcıyı takip edenlere yayın bildirimi.'),
  ('live_notify_product_fans', '"true"', 'Mağazanın ürünlerini favorileyenlere yayın bildirimi.'),
  ('live_notify_customers', '"false"', 'Mağazadan son 90 günde sipariş verenlere yayın bildirimi.'),
  ('live_notify_max_recipients', '"2000"', 'Bir yayın bildiriminin en çok kaç kişiye gideceği (0–20000).'),
  ('live_home_card_enabled', '"true"', 'Ana sayfada (Şehiriçi kartının yanında) canlı yayın kartı gösterilsin mi.'),
  ('live_history_days', '"30"', 'Biten yayınlar kaç gün boyunca geçmişte listelensin (1–180).')
ON CONFLICT (key) DO NOTHING;

ALTER TABLE public.notification_preferences
  ADD COLUMN IF NOT EXISTS live_streams_enabled boolean NOT NULL DEFAULT true;

COMMENT ON COLUMN public.notification_preferences.live_streams_enabled IS
  'Takip ettiğim/abone olduğum mağaza canlı yayına başlayınca bildirim (varsayılan açık).';

-- -----------------------------------------------------------------------------
-- 2) Abonelik ve bildirim günlüğü
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.live_subscriptions (
  user_id    uuid NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  shop_id    uuid NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
  created_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, shop_id)
);
CREATE INDEX IF NOT EXISTS idx_live_subscriptions_shop ON public.live_subscriptions (shop_id);

COMMENT ON TABLE public.live_subscriptions IS
  'Mağazanın canlı yayınlarından haberdar olmak isteyenler. Kişi kendi satırını okur; yazma live_set_subscription ile.';

ALTER TABLE public.live_subscriptions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.live_subscriptions FROM PUBLIC, anon, authenticated;
GRANT SELECT ON public.live_subscriptions TO authenticated;
DROP POLICY IF EXISTS live_subscriptions_read_own ON public.live_subscriptions;
CREATE POLICY live_subscriptions_read_own ON public.live_subscriptions
  FOR SELECT TO authenticated
  USING (user_id = (SELECT auth.uid()));

-- Yayın başına tek satır: kaç kişiye gitti ya da neden gitmedi. Bekleme
-- süresi mağazanın son GÖNDERİLEN bildirimine bakar. İstemciye kapalı.
CREATE TABLE IF NOT EXISTS public.live_notify_log (
  session_id  uuid PRIMARY KEY REFERENCES public.live_sessions(id) ON DELETE CASCADE,
  shop_id     uuid NOT NULL REFERENCES public.shops(id) ON DELETE CASCADE,
  notified_at timestamptz NOT NULL DEFAULT now(),
  recipients  integer NOT NULL DEFAULT 0 CHECK (recipients >= 0),
  skipped     text CHECK (skipped IS NULL OR skipped IN ('cooldown', 'disabled'))
);
CREATE INDEX IF NOT EXISTS idx_live_notify_log_shop_sent
  ON public.live_notify_log (shop_id, notified_at DESC)
  WHERE skipped IS NULL;

ALTER TABLE public.live_notify_log ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.live_notify_log FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 3) Yardımcılar
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION private.live_setting_bool(p_key text, p_default boolean)
RETURNS boolean
LANGUAGE sql
STABLE
SET search_path = ''
AS $fn$
  SELECT CASE
    WHEN private.live_setting(p_key) IN ('true', 't', '1', 'yes', 'on') THEN true
    WHEN private.live_setting(p_key) IN ('false', 'f', '0', 'no', 'off') THEN false
    ELSE p_default
  END;
$fn$;

-- Sayı değilse varsayılan; sonra [p_min, p_max] aralığına sıkıştırılır.
CREATE OR REPLACE FUNCTION private.live_setting_int(p_key text, p_default integer, p_min integer, p_max integer)
RETURNS integer
LANGUAGE sql
STABLE
SET search_path = ''
AS $fn$
  SELECT LEAST(GREATEST(
    CASE WHEN private.live_setting(p_key) ~ '^-?\d{1,9}$' THEN private.live_setting(p_key)::integer ELSE p_default END,
    p_min), p_max);
$fn$;

CREATE OR REPLACE FUNCTION private.live_history_days()
RETURNS integer
LANGUAGE sql
STABLE
SET search_path = ''
AS $fn$
  SELECT private.live_setting_int('live_history_days', 30, 1, 180);
$fn$;

-- Yayında sabitlenmiş (öne çıkan) ürünler, ilk sabitlenme sırasıyla (en çok 8).
CREATE OR REPLACE FUNCTION private.live_featured_products(p_session_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = ''
AS $fn$
  SELECT COALESCE(jsonb_agg(x.j ORDER BY x.first_pinned, x.id), '[]'::jsonb)
    FROM (
      SELECT p.id,
             min(lp.pinned_at) AS first_pinned,
             jsonb_build_object(
               'id', p.id,
               'name', p.name,
               'image_url', p.image_url,
               'price', p.price,
               'discount_price', p.discount_price,
               'effective_price', CASE
                 WHEN p.discount_price IS NOT NULL AND p.discount_price > 0 AND p.discount_price < p.price
                   THEN p.discount_price
                 ELSE p.price
               END,
               'is_available', COALESCE(p.is_available, false) AND COALESCE(p.is_active, true)
             ) AS j
        FROM public.live_pinned_products lp
        JOIN public.products p ON p.id = lp.product_id
       WHERE lp.session_id = p_session_id
       GROUP BY p.id
       ORDER BY min(lp.pinned_at), p.id
       LIMIT 8
    ) x;
$fn$;

-- Geçmiş/ayrıntı satırı: oturum + öne çıkan ürünler + süre + mesaj sayısı.
CREATE OR REPLACE FUNCTION private.live_history_json(p_session_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SET search_path = ''
AS $fn$
  SELECT private.live_session_json(ls.id) || jsonb_build_object(
           'featured_products', private.live_featured_products(ls.id),
           'duration_seconds', CASE WHEN ls.started_at IS NULL THEN 0 ELSE
             GREATEST(0, floor(extract(epoch FROM (COALESCE(ls.ended_at, now()) - ls.started_at))))::integer END,
           'message_count', (SELECT count(*) FROM public.live_messages m WHERE m.session_id = ls.id)
         )
    FROM public.live_sessions ls
   WHERE ls.id = p_session_id;
$fn$;

-- "Yayın başladı" bildirimi; gönderilen kişi sayısını döner (0 = kimse ya da
-- kapalı/bekleme süresinde). Aynı yayın için ikinci kez çalışmaz.
CREATE OR REPLACE FUNCTION private.live_notify_started(p_session_id uuid)
RETURNS integer
LANGUAGE plpgsql
SET search_path = ''
AS $fn$
DECLARE
  v record;
  v_cooldown integer;
  v_max integer;
  v_followers boolean;
  v_fans boolean;
  v_customers boolean;
  v_n integer := 0;
BEGIN
  SELECT ls.id, ls.shop_id, ls.title, ls.host_user_id, s.name AS shop_name, s.owner_id, s.logo_url
    INTO v
    FROM public.live_sessions ls
    JOIN public.shops s ON s.id = ls.shop_id
   WHERE ls.id = p_session_id;
  IF NOT FOUND OR EXISTS (SELECT 1 FROM public.live_notify_log l WHERE l.session_id = p_session_id) THEN
    RETURN 0;
  END IF;

  IF NOT private.live_setting_bool('live_notify_enabled', true) THEN
    INSERT INTO public.live_notify_log (session_id, shop_id, recipients, skipped)
    VALUES (v.id, v.shop_id, 0, 'disabled');
    RETURN 0;
  END IF;

  v_cooldown := private.live_setting_int('live_notify_cooldown_hours', 3, 0, 72);
  IF EXISTS (SELECT 1 FROM public.live_notify_log l
              WHERE l.shop_id = v.shop_id AND l.skipped IS NULL
                AND l.notified_at > now() - make_interval(hours => v_cooldown)) THEN
    INSERT INTO public.live_notify_log (session_id, shop_id, recipients, skipped)
    VALUES (v.id, v.shop_id, 0, 'cooldown');
    RETURN 0;
  END IF;

  v_max := private.live_setting_int('live_notify_max_recipients', 2000, 0, 20000);
  v_followers := private.live_setting_bool('live_notify_followers', true);
  v_fans := private.live_setting_bool('live_notify_product_fans', true);
  v_customers := private.live_setting_bool('live_notify_customers', false);

  WITH audience AS (
    SELECT sub.user_id, 1 AS prio
      FROM public.live_subscriptions sub
     WHERE sub.shop_id = v.shop_id
    UNION ALL
    SELECT f.follower_id, 2
      FROM public.follows f
     WHERE v_followers AND f.following_id = v.owner_id
    UNION ALL
    SELECT pf.user_id, 3
      FROM public.product_favorites pf
      JOIN public.products pr ON pr.id = pf.product_id
     WHERE v_fans AND pr.shop_id = v.shop_id
    UNION ALL
    SELECT o.user_id, 4
      FROM public.orders o
     WHERE v_customers AND o.shop_id = v.shop_id AND o.created_at > now() - interval '90 days'
  ),
  ranked AS (
    SELECT a.user_id, min(a.prio) AS prio
      FROM audience a
     WHERE a.user_id IS NOT NULL
     GROUP BY a.user_id
  ),
  eligible AS (
    SELECT r.user_id
      FROM ranked r
      JOIN public.profiles p ON p.id = r.user_id
     WHERE r.user_id IS DISTINCT FROM v.owner_id
       AND r.user_id IS DISTINCT FROM v.host_user_id
       AND NOT COALESCE(p.is_bot, false)
       AND p.status::text = 'active'
       AND NOT EXISTS (SELECT 1 FROM public.notification_preferences np
                        WHERE np.user_id = r.user_id AND np.live_streams_enabled = false)
       AND NOT EXISTS (SELECT 1 FROM public.blocked_users b
                        WHERE (b.blocker_id = r.user_id AND b.blocked_id = v.owner_id)
                           OR (b.blocker_id = v.owner_id AND b.blocked_id = r.user_id))
     ORDER BY r.prio, r.user_id
     LIMIT v_max
  )
  INSERT INTO public.notifications (
    user_id, type, title, content, actor_id, actor_name, actor_avatar,
    entity_id, entity_type, entity_image, metadata, is_read, created_at
  )
  SELECT e.user_id, 'live_started',
         format('🔴 %s canlı yayında', v.shop_name),
         left(v.title, 120),
         v.owner_id, v.shop_name, v.logo_url,
         v.id::text, 'live_session', v.logo_url,
         jsonb_build_object('route', '/live/' || v.id::text, 'shop_id', v.shop_id::text, 'source', 'live_started'),
         false, now()
    FROM eligible e;
  GET DIAGNOSTICS v_n = ROW_COUNT;

  INSERT INTO public.live_notify_log (session_id, shop_id, recipients, skipped)
  VALUES (v.id, v.shop_id, v_n, NULL);
  RETURN v_n;
END;
$fn$;

REVOKE ALL ON FUNCTION private.live_setting_bool(text, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.live_setting_int(text, integer, integer, integer) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.live_history_days() FROM PUBLIC;
REVOKE ALL ON FUNCTION private.live_featured_products(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.live_history_json(uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION private.live_notify_started(uuid) FROM PUBLIC;

-- -----------------------------------------------------------------------------
-- 4) Abonelik RPC'leri
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.live_shop_subscription(p_shop_id uuid)
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT jsonb_build_object(
    'shop_id', p_shop_id,
    'subscribed', EXISTS (SELECT 1 FROM public.live_subscriptions
                           WHERE shop_id = p_shop_id AND user_id = (SELECT auth.uid())),
    'subscribers', (SELECT count(*) FROM public.live_subscriptions WHERE shop_id = p_shop_id)
  );
$fn$;

CREATE OR REPLACE FUNCTION public.live_set_subscription(p_shop_id uuid, p_on boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'Oturum açmanız gerekli' USING ERRCODE = '42501', HINT = 'AUTH_REQUIRED';
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.shops s WHERE s.id = p_shop_id) THEN
    RAISE EXCEPTION 'Mağaza bulunamadı' USING ERRCODE = 'P0001', HINT = 'LIVE_SHOP_NOT_FOUND';
  END IF;
  IF COALESCE(p_on, false) THEN
    INSERT INTO public.live_subscriptions (user_id, shop_id) VALUES (v_uid, p_shop_id)
    ON CONFLICT (user_id, shop_id) DO NOTHING;
  ELSE
    DELETE FROM public.live_subscriptions WHERE user_id = v_uid AND shop_id = p_shop_id;
  END IF;
  RETURN public.live_shop_subscription(p_shop_id);
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 5) Geçmiş, ayrıntı ve ana sayfa kartı
-- -----------------------------------------------------------------------------
-- p_shop_id: yalnız o mağazanın yayınları (NULL = hepsi).
CREATE OR REPLACE FUNCTION public.live_history(
  p_limit integer DEFAULT 20,
  p_offset integer DEFAULT 0,
  p_shop_id uuid DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 20), 1), 50);
  v_offset integer := GREATEST(COALESCE(p_offset, 0), 0);
  v_days integer := private.live_history_days();
  v_total integer;
  v_rows jsonb;
BEGIN
  WITH filtered AS (
    SELECT ls.id, ls.ended_at
      FROM public.live_sessions ls
      JOIN public.shops s ON s.id = ls.shop_id
     WHERE ls.status = 'ended'
       AND ls.started_at IS NOT NULL
       AND ls.ended_at > now() - make_interval(days => v_days)
       AND COALESCE(s.is_active, false)
       AND COALESCE(s.is_approved, false)
       AND (p_shop_id IS NULL OR ls.shop_id = p_shop_id)
  ),
  page AS (
    -- Sayfa kesimi ile sayfa içi sıra aynı ifade (sayfalar birleşince bozulmaz).
    SELECT f.id, row_number() OVER (ORDER BY f.ended_at DESC, f.id) AS rn
      FROM filtered f
     ORDER BY rn
     LIMIT v_limit OFFSET v_offset
  )
  SELECT (SELECT count(*) FROM filtered),
         COALESCE(jsonb_agg(private.live_history_json(p.id) ORDER BY p.rn), '[]'::jsonb)
    INTO v_total, v_rows
    FROM page p;

  RETURN jsonb_build_object('total', COALESCE(v_total, 0), 'days', v_days, 'rows', v_rows);
END;
$fn$;

CREATE OR REPLACE FUNCTION public.live_session_detail(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  RETURN private.live_history_json(p_session_id);
END;
$fn$;

-- Ana sayfa kartı: {enabled, live_count, live (en çok izlenen), last (son biten)}.
-- Kart ayarı ya da modül kapalıysa yalnız {enabled:false}.
CREATE OR REPLACE FUNCTION public.live_home_card()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_live uuid;
  v_last uuid;
  v_count integer;
BEGIN
  IF NOT private.live_setting_bool('live_home_card_enabled', true) OR NOT private.live_module_enabled() THEN
    RETURN jsonb_build_object('enabled', false);
  END IF;

  SELECT count(*) INTO v_count
    FROM public.live_sessions ls
    JOIN public.shops s ON s.id = ls.shop_id
   WHERE ls.status = 'live'
     AND ls.last_heartbeat_at > now() - interval '2 minutes'
     AND COALESCE(s.is_active, false)
     AND COALESCE(s.is_approved, false);

  SELECT ls.id INTO v_live
    FROM public.live_sessions ls
    JOIN public.shops s ON s.id = ls.shop_id
   WHERE ls.status = 'live'
     AND ls.last_heartbeat_at > now() - interval '2 minutes'
     AND COALESCE(s.is_active, false)
     AND COALESCE(s.is_approved, false)
   ORDER BY ls.viewer_count DESC, ls.started_at DESC, ls.id
   LIMIT 1;

  SELECT ls.id INTO v_last
    FROM public.live_sessions ls
    JOIN public.shops s ON s.id = ls.shop_id
   WHERE ls.status = 'ended'
     AND ls.started_at IS NOT NULL
     AND ls.ended_at > now() - make_interval(days => private.live_history_days())
     AND COALESCE(s.is_active, false)
     AND COALESCE(s.is_approved, false)
   ORDER BY ls.ended_at DESC, ls.id
   LIMIT 1;

  RETURN jsonb_build_object(
    'enabled', true,
    'live_count', COALESCE(v_count, 0),
    'live', CASE WHEN v_live IS NULL THEN NULL ELSE private.live_session_json(v_live) END,
    'last', CASE WHEN v_last IS NULL THEN NULL ELSE private.live_history_json(v_last) END
  );
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 6) Yönetici: bildirim / ana sayfa / geçmiş ayarları
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.admin_live_options()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  IF NOT public.auth_is_admin() THEN
    RAISE EXCEPTION 'Yönetici yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  RETURN jsonb_build_object(
    'notify_enabled', private.live_setting_bool('live_notify_enabled', true),
    'notify_cooldown_hours', private.live_setting_int('live_notify_cooldown_hours', 3, 0, 72),
    'notify_followers', private.live_setting_bool('live_notify_followers', true),
    'notify_product_fans', private.live_setting_bool('live_notify_product_fans', true),
    'notify_customers', private.live_setting_bool('live_notify_customers', false),
    'notify_max_recipients', private.live_setting_int('live_notify_max_recipients', 2000, 0, 20000),
    'home_card_enabled', private.live_setting_bool('live_home_card_enabled', true),
    'history_days', private.live_history_days(),
    'stats', jsonb_build_object(
      'subscriptions', (SELECT count(*) FROM public.live_subscriptions),
      'subscribed_shops', (SELECT count(DISTINCT shop_id) FROM public.live_subscriptions),
      'notifications_30d', (SELECT count(*) FROM public.live_notify_log
                             WHERE skipped IS NULL AND notified_at > now() - interval '30 days'),
      'recipients_30d', (SELECT COALESCE(sum(recipients), 0) FROM public.live_notify_log
                          WHERE skipped IS NULL AND notified_at > now() - interval '30 days'),
      'cooldown_skips_30d', (SELECT count(*) FROM public.live_notify_log
                              WHERE skipped = 'cooldown' AND notified_at > now() - interval '30 days')
    )
  );
END;
$fn$;

-- Yalnız verilen anahtarları yazar; sayılar sınırlara sıkıştırılır.
CREATE OR REPLACE FUNCTION public.admin_set_live_options(p_options jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_key text;
  v_value jsonb;
  v_setting text;
  v_text text;
  v_num numeric;
BEGIN
  IF NOT public.auth_is_admin() THEN
    RAISE EXCEPTION 'Yönetici yetkisi gerekli' USING ERRCODE = '42501';
  END IF;
  IF p_options IS NULL OR jsonb_typeof(p_options) <> 'object' THEN
    RAISE EXCEPTION 'Geçersiz ayar' USING ERRCODE = 'P0001', HINT = 'LIVE_OPTIONS_INVALID';
  END IF;

  FOR v_key, v_value IN SELECT e.key, e.value FROM jsonb_each(p_options) e LOOP
    v_setting := CASE v_key
      WHEN 'notify_enabled' THEN 'live_notify_enabled'
      WHEN 'notify_cooldown_hours' THEN 'live_notify_cooldown_hours'
      WHEN 'notify_followers' THEN 'live_notify_followers'
      WHEN 'notify_product_fans' THEN 'live_notify_product_fans'
      WHEN 'notify_customers' THEN 'live_notify_customers'
      WHEN 'notify_max_recipients' THEN 'live_notify_max_recipients'
      WHEN 'home_card_enabled' THEN 'live_home_card_enabled'
      WHEN 'history_days' THEN 'live_history_days'
    END;
    IF v_setting IS NULL THEN
      RAISE EXCEPTION 'Bilinmeyen ayar: %', v_key USING ERRCODE = 'P0001', HINT = 'LIVE_OPTIONS_INVALID';
    END IF;

    IF v_key IN ('notify_enabled', 'notify_followers', 'notify_product_fans', 'notify_customers', 'home_card_enabled') THEN
      IF jsonb_typeof(v_value) <> 'boolean' THEN
        RAISE EXCEPTION 'Geçersiz değer: %', v_key USING ERRCODE = 'P0001', HINT = 'LIVE_OPTIONS_INVALID';
      END IF;
      v_text := CASE WHEN (v_value #>> '{}')::boolean THEN 'true' ELSE 'false' END;
    ELSE
      IF jsonb_typeof(v_value) <> 'number' THEN
        RAISE EXCEPTION 'Geçersiz değer: %', v_key USING ERRCODE = 'P0001', HINT = 'LIVE_OPTIONS_INVALID';
      END IF;
      v_num := (v_value #>> '{}')::numeric;
      v_text := round(CASE v_key
        WHEN 'notify_cooldown_hours' THEN LEAST(GREATEST(v_num, 0), 72)
        WHEN 'notify_max_recipients' THEN LEAST(GREATEST(v_num, 0), 20000)
        ELSE LEAST(GREATEST(v_num, 1), 180)
      END)::integer::text;
    END IF;

    INSERT INTO public.app_settings (key, value, updated_at)
    VALUES (v_setting, to_jsonb(v_text), now())
    ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value, updated_at = EXCLUDED.updated_at;
  END LOOP;

  RETURN public.admin_live_options();
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 7) Yayını başlat: 20260928000016 tanımı + bildirim
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.start_live_session(p_session_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v public.live_sessions%ROWTYPE;
  v_active boolean;
  v_notified integer;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Oturum açmanız gerekli' USING ERRCODE = '42501', HINT = 'AUTH_REQUIRED';
  END IF;
  SELECT * INTO v FROM public.live_sessions WHERE id = p_session_id FOR UPDATE;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Yayın bulunamadı' USING ERRCODE = 'P0001', HINT = 'LIVE_NOT_FOUND';
  END IF;
  IF v.host_user_id <> auth.uid() THEN
    RAISE EXCEPTION 'Bu yayın size ait değil' USING ERRCODE = '42501', HINT = 'LIVE_NOT_HOST';
  END IF;
  IF v.status = 'ended' THEN
    RAISE EXCEPTION 'Bu yayın sona erdi' USING ERRCODE = 'P0001', HINT = 'LIVE_ENDED';
  END IF;
  SELECT COALESCE(s.is_active, false) AND COALESCE(s.is_approved, false) INTO v_active
    FROM public.shops s WHERE s.id = v.shop_id;
  IF NOT COALESCE(v_active, false) THEN
    RAISE EXCEPTION 'Yayın için mağazanız aktif ve onaylı olmalı' USING ERRCODE = 'P0001', HINT = 'LIVE_SHOP_INACTIVE';
  END IF;
  -- Görev 4.3: hazırlıktan canlıya geçiş izin ister (canlıyken tekrar çağrı = sinyal).
  IF v.status = 'scheduled' THEN
    PERFORM private.live_assert_access(v.shop_id);
  END IF;

  UPDATE public.live_sessions
     SET status = 'live',
         started_at = COALESCE(started_at, now()),
         last_heartbeat_at = now()
   WHERE id = p_session_id;

  -- Hazırlıktan canlıya ilk geçiş: "yayın başladı" bildirimi. Hata yayını
  -- engellemez (alt işlem geri alınır, yayın başlar).
  IF v.status = 'scheduled' THEN
    BEGIN
      v_notified := private.live_notify_started(p_session_id);
    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'live_notify_started(%): % (%)', p_session_id, SQLERRM, SQLSTATE;
    END;
  END IF;

  RETURN private.live_session_json(p_session_id) || jsonb_build_object('notified', v_notified);
END;
$fn$;

-- -----------------------------------------------------------------------------
-- 8) Yetkiler
-- -----------------------------------------------------------------------------
REVOKE ALL ON FUNCTION public.live_set_subscription(uuid, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.live_set_subscription(uuid, boolean) TO authenticated;
REVOKE ALL ON FUNCTION public.live_shop_subscription(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.live_shop_subscription(uuid) TO anon, authenticated;
REVOKE ALL ON FUNCTION public.live_history(integer, integer, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.live_history(integer, integer, uuid) TO anon, authenticated;
REVOKE ALL ON FUNCTION public.live_home_card() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.live_home_card() TO anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_live_options() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_live_options() TO authenticated;
REVOKE ALL ON FUNCTION public.admin_set_live_options(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_live_options(jsonb) TO authenticated;

-- Yeniden tanımlananların yetkileri korunur (CREATE OR REPLACE); yine de açıkça:
REVOKE ALL ON FUNCTION public.start_live_session(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.start_live_session(uuid) TO authenticated;
REVOKE ALL ON FUNCTION public.live_session_detail(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.live_session_detail(uuid) TO anon, authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
