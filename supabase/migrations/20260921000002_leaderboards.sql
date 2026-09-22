-- =============================================================================
-- 20260921000002_leaderboards.sql
-- -----------------------------------------------------------------------------
-- Ana sayfadaki "Liderler Tablosu": sekiz pano, hepsi admin panelinden açılıp
-- kapatılabilir.
--
--   new_members      Yeni üyeler (en son katılanlar)
--   top_followed     En çok takipçisi olan kullanıcılar
--   top_sellers      En çok sipariş alan dükkanlar
--   top_customers    En çok sipariş veren müşteriler
--   top_rated_shops  En yüksek puanlı dükkanlar
--   top_couriers     En çok teslimat yapan kurye
--   top_posters      En çok paylaşım yapanlar
--   most_liked       En çok beğeni alanlar
--
-- ## "Sipariş" ne demek
--
-- TAMAMLANAN sipariş: fiziksel `orders.status = 'delivered'` + dijital
-- `digital_orders.status = 'completed'`. İptal/başarısız/iade sayılmaz; aksi
-- halde bekleyen veya sahte siparişle listeye girilebilirdi. Dijital siparişler
-- dahil çünkü canlıda dijital tamamlanan sipariş sayısı fiziksel olanları
-- geçiyor — sadece `orders`a bakmak dijital satıcıları listeden silerdi.
-- `digital_orders`ın `shop_id`si yok; dükkan `products.shop_id` üzerinden bulunur.
--
-- ## Kimler listede olmaz (kullanıcı panoları)
--
--   * `profiles.is_bot` — vitrin hesapları gerçek üye değil; üye sayaçlarının
--     hepsi zaten onları hariç tutuyor (bkz. bot vitrin hesapları).
--   * `status <> 'active'` (askıya alınmış / silinmiş),
--   * `profile_is_public = false` — gizli hesap sahibinin adı ve sayıları
--     herkese açık bir listede görünmemeli,
--   * çağıran ile aralarında engel olan kullanıcılar (iki yönlü),
--   * `needs_username` — kaydı yarım kalmış OAuth hesapları.
--
-- Botların BEĞENİ/TAKİP olarak gerçek kullanıcılara verdikleri sayılır: profilde
-- görünen takipçi/beğeni rakamı da onları içeriyor, pano ondan farklı bir sayı
-- göstermemeli.
--
-- ## Kapılar sunucuda
--
-- `app_settings` bayrağı arayüzü gizlemek için yeterli değildir. Ana anahtar ya
-- da panonun kendi anahtarı kapalıysa `get_leaderboard` BOŞ döner; istemciyi
-- kurcalayan biri kapalı bir panoyu açamaz. Yalnızca oturum açmış kullanıcı
-- çağırabilir (müşteri sipariş sayıları anonim ziyaretçiye gösterilmez).
-- =============================================================================

begin;

SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- 1) Admin anahtarları
-- -----------------------------------------------------------------------------
INSERT INTO public.app_settings (key, value, description)
VALUES
  ('leaderboard_enabled', '"true"',
   'Ana sayfada Liderler Tablosu görünsün mü? Kapalıyken hiçbir pano sunucudan dönmez.'),
  ('leaderboard_period', '"all"',
   'Sipariş/paylaşım/beğeni panolarının dönemi: week (son 7 gün), month (son 30 gün) ya da all (tüm zamanlar).'),
  ('leaderboard_limit', '"5"',
   'Her panoda gösterilecek kişi sayısı (3-10).'),
  ('leaderboard_board_new_members', '"true"', 'Pano: Yeni üyeler'),
  ('leaderboard_board_top_followed', '"true"', 'Pano: En çok takipçisi olanlar'),
  ('leaderboard_board_top_sellers', '"true"', 'Pano: En çok sipariş alan dükkanlar'),
  ('leaderboard_board_top_customers', '"true"', 'Pano: En çok sipariş verenler'),
  ('leaderboard_board_top_rated_shops', '"true"', 'Pano: En yüksek puanlı dükkanlar'),
  ('leaderboard_board_top_couriers', '"true"', 'Pano: En çok teslimat yapan kuryeler'),
  ('leaderboard_board_top_posters', '"true"', 'Pano: En çok paylaşım yapanlar'),
  ('leaderboard_board_most_liked', '"true"', 'Pano: En çok beğeni alanlar')
ON CONFLICT (key) DO NOTHING;

-- Ham ayar metni. Konvansiyon: jsonb kolonuna JSON string yazılır ("true") ve
-- istemci düz `'true'` gönderir. Ama bir istemci `'"true"'` gönderirse jsonb'de
-- TIRNAKLI metin (`"true"`) kalır ve `#>> '{}'` tırnaklarıyla döner; `::boolean`
-- ya da `::integer` çevrimi hata verirdi. Kenar tırnakları/boşlukları buradan
-- soyup her iki biçimi de kabul ediyoruz — bir admin anahtarı yüzünden panonun
-- 500 vermesi kabul edilemez.
CREATE OR REPLACE FUNCTION public.leaderboard_setting(p_key text)
RETURNS text
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT NULLIF(btrim(s.value #>> '{}', E'" \t\r\n'), '')
  FROM public.app_settings s
  WHERE s.key = p_key;
$fn$;

CREATE OR REPLACE FUNCTION public.leaderboard_flag(p_key text, p_default boolean)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT COALESCE(
    lower(public.leaderboard_setting(p_key)) IN ('true', 't', '1', 'yes', 'on'),
    p_default
  );
$fn$;

CREATE OR REPLACE FUNCTION public.leaderboard_period_since()
RETURNS timestamptz
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT CASE lower(public.leaderboard_setting('leaderboard_period'))
           WHEN 'week'  THEN now() - interval '7 days'
           WHEN 'month' THEN now() - interval '30 days'
           ELSE '-infinity'::timestamptz
         END;
$fn$;

CREATE OR REPLACE FUNCTION public.leaderboard_limit_value()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT LEAST(10, GREATEST(3, COALESCE(
    CASE WHEN public.leaderboard_setting('leaderboard_limit') ~ '^[0-9]{1,3}$'
         THEN public.leaderboard_setting('leaderboard_limit')::integer END,
    5)));
$fn$;

-- İstemci tüm anahtarları TEK çağrıda alır.
CREATE OR REPLACE FUNCTION public.leaderboard_settings()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT jsonb_build_object(
    'enabled', public.leaderboard_flag('leaderboard_enabled', true),
    'period', CASE lower(public.leaderboard_setting('leaderboard_period'))
      WHEN 'week'  THEN 'week'
      WHEN 'month' THEN 'month'
      ELSE 'all'
    END,
    'limit', public.leaderboard_limit_value(),
    'boards', jsonb_build_object(
      'new_members',     public.leaderboard_flag('leaderboard_board_new_members', true),
      'top_followed',    public.leaderboard_flag('leaderboard_board_top_followed', true),
      'top_sellers',     public.leaderboard_flag('leaderboard_board_top_sellers', true),
      'top_customers',   public.leaderboard_flag('leaderboard_board_top_customers', true),
      'top_rated_shops', public.leaderboard_flag('leaderboard_board_top_rated_shops', true),
      'top_couriers',    public.leaderboard_flag('leaderboard_board_top_couriers', true),
      'top_posters',     public.leaderboard_flag('leaderboard_board_top_posters', true),
      'most_liked',      public.leaderboard_flag('leaderboard_board_most_liked', true)
    )
  );
$fn$;

-- -----------------------------------------------------------------------------
-- 2) Yardımcılar (istemciye kapalı; yalnız get_leaderboard'ın içinden çağrılır)
-- -----------------------------------------------------------------------------

-- Bir kullanıcı herkese açık bir listede görünebilir mi?
CREATE OR REPLACE FUNCTION public.leaderboard_user_ok(p_id uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT EXISTS (
           SELECT 1
           FROM public.profiles p
           WHERE p.id = p_id
             AND NOT COALESCE(p.is_bot, false)
             AND p.status::text = 'active'
             AND COALESCE(p.profile_is_public, true)
             AND NOT COALESCE(p.needs_username, false)
             AND COALESCE(NULLIF(btrim(p.full_name), ''),
                          NULLIF(btrim(p.username), '')) IS NOT NULL
         )
         AND NOT public.social_block_exists(p_id);
$fn$;

-- Tamamlanan siparişler: fiziksel + dijital tek şekilde.
CREATE OR REPLACE FUNCTION public.leaderboard_completed_orders(p_since timestamptz)
RETURNS TABLE (o_shop_id uuid, o_user_id uuid, o_courier_id uuid)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT o.shop_id, o.user_id, o.delivered_courier_id
  FROM public.orders o
  WHERE o.status::text = 'delivered' AND o.created_at >= p_since
  UNION ALL
  SELECT pr.shop_id, d.user_id, NULL::uuid
  FROM public.digital_orders d
  JOIN public.products pr ON pr.id = d.product_id
  WHERE d.status::text = 'completed' AND d.created_at >= p_since;
$fn$;

REVOKE ALL ON FUNCTION public.leaderboard_setting(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.leaderboard_flag(text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.leaderboard_period_since() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.leaderboard_limit_value() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.leaderboard_user_ok(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.leaderboard_completed_orders(timestamptz) FROM PUBLIC, anon, authenticated;

REVOKE ALL ON FUNCTION public.leaderboard_settings() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.leaderboard_settings() TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 3) get_leaderboard — tek bir panonun sıralı satırları
--
-- Çıktı sütunları `r_` önekli: RETURNS TABLE adları plpgsql değişkeni olur ve
-- `name`/`avatar_url` gibi sütun adlarıyla çakışırdı.
--
--   r_type   'user' | 'shop'  (istemci hangi ekrana gideceğini buradan bilir)
--   r_metric sıralanan sayı; new_members için NULL
--   r_extra  top_rated_shops'ta yorum sayısı, diğerlerinde NULL
--   r_at     new_members'ta katılma zamanı, diğerlerinde NULL
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_leaderboard(p_board text)
RETURNS TABLE (
  r_rank    integer,
  r_type    text,
  r_id      uuid,
  r_name    text,
  r_handle  text,
  r_avatar  text,
  r_metric  numeric,
  r_extra   numeric,
  r_at      timestamptz
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_limit integer;
  v_since timestamptz;
BEGIN
  IF (SELECT auth.uid()) IS NULL THEN
    RETURN;
  END IF;
  IF NOT public.leaderboard_flag('leaderboard_enabled', true) THEN
    RETURN;
  END IF;
  IF p_board IS NULL OR p_board NOT IN (
       'new_members', 'top_followed', 'top_sellers', 'top_customers',
       'top_rated_shops', 'top_couriers', 'top_posters', 'most_liked'
     )
     OR NOT public.leaderboard_flag('leaderboard_board_' || p_board, true) THEN
    RETURN;
  END IF;

  v_limit := public.leaderboard_limit_value();
  v_since := public.leaderboard_period_since();

  IF p_board = 'new_members' THEN
    RETURN QUERY
    SELECT (row_number() OVER (ORDER BY p.created_at DESC, p.id))::integer,
           'user'::text, p.id,
           COALESCE(NULLIF(btrim(p.full_name), ''), p.username),
           CASE WHEN NULLIF(btrim(p.username), '') IS NULL THEN NULL
                ELSE '@' || p.username END,
           p.avatar_url, NULL::numeric, NULL::numeric, p.created_at
    FROM public.profiles p
    WHERE public.leaderboard_user_ok(p.id)
    ORDER BY p.created_at DESC, p.id
    LIMIT v_limit;

  ELSIF p_board = 'top_followed' THEN
    RETURN QUERY
    SELECT (row_number() OVER (ORDER BY c.n DESC, p.created_at, p.id))::integer,
           'user'::text, p.id,
           COALESCE(NULLIF(btrim(p.full_name), ''), p.username),
           CASE WHEN NULLIF(btrim(p.username), '') IS NULL THEN NULL
                ELSE '@' || p.username END,
           p.avatar_url, c.n::numeric, NULL::numeric, NULL::timestamptz
    FROM (SELECT f.following_id AS uid, count(*) AS n
            FROM public.follows f GROUP BY f.following_id) c
    JOIN public.profiles p ON p.id = c.uid
    WHERE c.n > 0 AND public.leaderboard_user_ok(p.id)
    ORDER BY c.n DESC, p.created_at, p.id
    LIMIT v_limit;

  ELSIF p_board = 'top_sellers' THEN
    RETURN QUERY
    SELECT (row_number() OVER (ORDER BY c.n DESC, s.created_at, s.id))::integer,
           'shop'::text, s.id, s.name, NULL::text, s.logo_url,
           c.n::numeric, NULL::numeric, NULL::timestamptz
    FROM (SELECT o.o_shop_id AS sid, count(*) AS n
            FROM public.leaderboard_completed_orders(v_since) o
            GROUP BY o.o_shop_id) c
    JOIN public.shops s ON s.id = c.sid
    JOIN public.profiles owner ON owner.id = s.owner_id
    WHERE s.is_active AND COALESCE(s.is_approved, true)
      AND NOT COALESCE(owner.is_bot, false)
    ORDER BY c.n DESC, s.created_at, s.id
    LIMIT v_limit;

  ELSIF p_board = 'top_customers' THEN
    RETURN QUERY
    SELECT (row_number() OVER (ORDER BY c.n DESC, p.created_at, p.id))::integer,
           'user'::text, p.id,
           COALESCE(NULLIF(btrim(p.full_name), ''), p.username),
           CASE WHEN NULLIF(btrim(p.username), '') IS NULL THEN NULL
                ELSE '@' || p.username END,
           p.avatar_url, c.n::numeric, NULL::numeric, NULL::timestamptz
    FROM (SELECT o.o_user_id AS uid, count(*) AS n
            FROM public.leaderboard_completed_orders(v_since) o
            GROUP BY o.o_user_id) c
    JOIN public.profiles p ON p.id = c.uid
    WHERE public.leaderboard_user_ok(p.id)
    ORDER BY c.n DESC, p.created_at, p.id
    LIMIT v_limit;

  ELSIF p_board = 'top_rated_shops' THEN
    RETURN QUERY
    SELECT (row_number() OVER (ORDER BY c.a DESC, c.n DESC, s.created_at, s.id))::integer,
           'shop'::text, s.id, s.name, NULL::text, s.logo_url,
           round(c.a, 1), c.n::numeric, NULL::timestamptz
    FROM (SELECT r.shop_id AS sid, avg(r.rating)::numeric AS a, count(*) AS n
            FROM public.shop_reviews r
            WHERE r.rating IS NOT NULL
            GROUP BY r.shop_id) c
    JOIN public.shops s ON s.id = c.sid
    JOIN public.profiles owner ON owner.id = s.owner_id
    WHERE s.is_active AND COALESCE(s.is_approved, true)
      AND NOT COALESCE(owner.is_bot, false)
    ORDER BY c.a DESC, c.n DESC, s.created_at, s.id
    LIMIT v_limit;

  ELSIF p_board = 'top_couriers' THEN
    RETURN QUERY
    SELECT (row_number() OVER (ORDER BY c.n DESC, p.created_at, p.id))::integer,
           'user'::text, p.id,
           COALESCE(NULLIF(btrim(p.full_name), ''), p.username),
           CASE WHEN NULLIF(btrim(p.username), '') IS NULL THEN NULL
                ELSE '@' || p.username END,
           p.avatar_url, c.n::numeric, NULL::numeric, NULL::timestamptz
    FROM (SELECT o.o_courier_id AS uid, count(*) AS n
            FROM public.leaderboard_completed_orders(v_since) o
            WHERE o.o_courier_id IS NOT NULL
            GROUP BY o.o_courier_id) c
    JOIN public.profiles p ON p.id = c.uid
    WHERE public.leaderboard_user_ok(p.id)
    ORDER BY c.n DESC, p.created_at, p.id
    LIMIT v_limit;

  ELSIF p_board = 'top_posters' THEN
    RETURN QUERY
    SELECT (row_number() OVER (ORDER BY c.n DESC, p.created_at, p.id))::integer,
           'user'::text, p.id,
           COALESCE(NULLIF(btrim(p.full_name), ''), p.username),
           CASE WHEN NULLIF(btrim(p.username), '') IS NULL THEN NULL
                ELSE '@' || p.username END,
           p.avatar_url, c.n::numeric, NULL::numeric, NULL::timestamptz
    FROM (SELECT x.user_id AS uid, count(*) AS n
            FROM public.posts x
            WHERE x.is_active IS NOT FALSE AND x.created_at >= v_since
            GROUP BY x.user_id) c
    JOIN public.profiles p ON p.id = c.uid
    WHERE public.leaderboard_user_ok(p.id)
    ORDER BY c.n DESC, p.created_at, p.id
    LIMIT v_limit;

  ELSE -- most_liked
    RETURN QUERY
    SELECT (row_number() OVER (ORDER BY c.n DESC, p.created_at, p.id))::integer,
           'user'::text, p.id,
           COALESCE(NULLIF(btrim(p.full_name), ''), p.username),
           CASE WHEN NULLIF(btrim(p.username), '') IS NULL THEN NULL
                ELSE '@' || p.username END,
           p.avatar_url, c.n::numeric, NULL::numeric, NULL::timestamptz
    FROM (SELECT x.user_id AS uid, sum(COALESCE(x.likes_count, 0)) AS n
            FROM public.posts x
            WHERE x.is_active IS NOT FALSE AND x.created_at >= v_since
            GROUP BY x.user_id) c
    JOIN public.profiles p ON p.id = c.uid
    WHERE c.n > 0 AND public.leaderboard_user_ok(p.id)
    ORDER BY c.n DESC, p.created_at, p.id
    LIMIT v_limit;
  END IF;
END;
$fn$;

REVOKE ALL ON FUNCTION public.get_leaderboard(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_leaderboard(text) TO authenticated, service_role;

commit;
