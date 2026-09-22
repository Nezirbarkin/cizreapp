-- =============================================================================
-- 20260921000003_leaderboards_v2.sql
-- -----------------------------------------------------------------------------
-- Liderler Tablosu ikinci tur (ilk tur: 20260921000002_leaderboards.sql):
--
--   * 5 yeni pano:  top_liked_posts, top_viewed_posts, top_viewed_stories,
--                   top_logins, top_product_sellers
--   * "Rakamlarla Cizre" sayaç kartı (`stats`): toplam üye, bugün aktif,
--     tamamlanan sipariş, dükkan, ürün, gönderi — her sayaç ayrı açılıp kapanır
--   * KENDİNİ GİZLEME: kullanıcı kendini listelerden çıkarabilir, admin de
--     bir kullanıcıyı gizleyebilir (kullanıcı bunu geri alamaz)
--   * Kart SIRASI admin tarafından belirlenir (`leaderboard_order`)
--   * "Senin sıran": listede ilk N'de olmayan kullanıcı kendi sırasını görür
--   * `get_leaderboards()`: ana sayfa TEK çağrıyla her şeyi alır (kaydırmalı
--     kartlarda komşu sayfa için bekleme olmasın diye)
--   * "BUGÜN CİZRE'DE" sayaç kartı (`stats_today`): bugün ziyaretçi (misafirler
--     dahil), bugün aktif üye, bugün üyesiz ziyaretçi, şu an çevrimiçi, bugün yeni
--     üye, bugün paylaşım/sipariş; ve genel sayaç kartına "üyesiz (misafir)
--     kullanıcı" ile "hayalet mod kullanıcısı" sayıları
--   * 101 OKEY kartları (`okey_*`): en çok maç oynayan / kazanan / kaybeden,
--     kazanma oranı, en çok puanı olan (cüzdan), en çok puan ve el kazanan, en
--     iyi maç skoru + "Oynanan Okey maçı" sayacı
--
-- ## Gizleme neden ayrı bir tablo (profiles'a kolon DEĞİL)
--
-- Kullanıcı kendi `profiles` satırını güncelleyebilir. Admin gizlemesini aynı
-- satıra koysaydık kullanıcı kendi güncellemesiyle admin kararını geri alırdı.
-- `leaderboard_exclusions` istemciye tamamen kapalıdır; yalnız RPC yazar ve iki
-- bayrak (self_hidden / admin_hidden) birbirinden bağımsızdır. Ayrıca profiles
-- sütun GRANT'lerine ve `posts_with_profiles` gibi görünümlere dokunmak gerekmez.
--
-- Gizli kullanıcı: kendi sıralamasında, gönderi/hikayesinin panolarında ve
-- SAHİBİ olduğu dükkanların dükkan panolarında görünmez. Sayaçlara (toplam üye
-- vb.) yine dahildir — sayaç kimseyi açığa çıkarmaz.
--
-- ## Hikaye panosu neden yalnız YAYINDAKİ hikayeler
--
-- Hikayeler 24 saatte sona erer ama satırı silinmez (canlıda 47'sinin de süresi
-- dolmuş, en eskisi Haziran'dan). "Tüm zamanların en çok izlenen hikayesi"ni
-- herkese açık bir listede açılabilir yapmak, süresi dolmuş hikayeyi yeniden
-- yayına sokmak olurdu — sahibi bunu beklemiyor. Bu yüzden yalnız `expires_at >
-- now()` olanlar sıralanır ve dönem ayarından etkilenmez.
-- =============================================================================

begin;

SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- 1) Gizleme tablosu — istemciye kapalı, yalnız RPC
-- -----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.leaderboard_exclusions (
  user_id      uuid PRIMARY KEY REFERENCES public.profiles(id) ON DELETE CASCADE,
  self_hidden  boolean NOT NULL DEFAULT false,
  admin_hidden boolean NOT NULL DEFAULT false,
  updated_at   timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.leaderboard_exclusions ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.leaderboard_exclusions FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.leaderboard_exclusions TO service_role;

COMMENT ON TABLE public.leaderboard_exclusions IS
  'Liderler Tablosu gizleme bayrakları. self_hidden: kullanıcı kendi istedi; admin_hidden: admin gizledi (kullanıcı geri alamaz). Yalnız RPC ile yazılır.';

-- -----------------------------------------------------------------------------
-- 2) Yeni anahtarlar
-- -----------------------------------------------------------------------------
INSERT INTO public.app_settings (key, value, description)
VALUES
  ('leaderboard_board_stats', '"true"', 'Kart: Rakamlarla Cizre (sayaçlar)'),
  ('leaderboard_board_top_liked_posts', '"true"', 'Pano: En çok beğenilen gönderi'),
  ('leaderboard_board_top_viewed_posts', '"true"', 'Pano: En çok görüntülenen gönderi'),
  ('leaderboard_board_top_viewed_stories', '"true"', 'Pano: En çok izlenen hikaye (yalnız yayındakiler)'),
  ('leaderboard_board_top_logins', '"true"', 'Pano: En çok giriş yapanlar (giriş günlüğünden, 90 gün saklanır)'),
  ('leaderboard_board_top_product_sellers', '"true"', 'Pano: En çok ürün yükleyen dükkanlar'),
  ('leaderboard_stat_members', '"true"', 'Sayaç: Toplam üye'),
  ('leaderboard_stat_active_today', '"true"', 'Sayaç: Bugün aktif kullanıcı'),
  ('leaderboard_stat_orders', '"true"', 'Sayaç: Tamamlanan sipariş'),
  ('leaderboard_stat_shops', '"true"', 'Sayaç: Aktif dükkan'),
  ('leaderboard_stat_products', '"true"', 'Sayaç: Toplam ürün'),
  ('leaderboard_stat_posts', '"true"', 'Sayaç: Toplam gönderi'),
  ('leaderboard_board_okey_most_played', '"true"', 'Pano: Okey - en çok maç oynayanlar'),
  ('leaderboard_board_okey_most_wins', '"true"', 'Pano: Okey - en çok maç kazananlar'),
  ('leaderboard_board_okey_most_losses', '"true"', 'Pano: Okey - en çok maç kaybedenler'),
  ('leaderboard_board_okey_win_rate', '"true"', 'Pano: Okey - en yüksek kazanma oranı (en az 5 maç)'),
  ('leaderboard_board_okey_richest', '"true"', 'Pano: Okey - en çok puanı olanlar (cüzdan)'),
  ('leaderboard_board_okey_points_won', '"true"', 'Pano: Okey - en çok puan kazananlar'),
  ('leaderboard_board_okey_hands_won', '"true"', 'Pano: Okey - en çok el kazananlar'),
  ('leaderboard_board_okey_best_score', '"true"', 'Pano: Okey - en iyi (en düşük) maç skoru'),
  ('leaderboard_stat_okey_matches', '"true"', 'Sayaç: Oynanan Okey maçı'),
  ('leaderboard_board_stats_today', '"true"', 'Kart: Bugün Cizre''de (günlük sayaçlar)'),
  ('leaderboard_stat_guests', '"true"', 'Sayaç: Üyesiz (misafir) kullanıcı'),
  ('leaderboard_stat_ghosts', '"true"', 'Sayaç: Hayalet mod kullanıcısı'),
  ('leaderboard_stat_visitors_today', '"true"', 'Sayaç: Bugün ziyaretçi (misafirler dahil)'),
  ('leaderboard_stat_guests_today', '"true"', 'Sayaç: Bugün üyesiz ziyaretçi'),
  ('leaderboard_stat_online_now', '"true"', 'Sayaç: Şu an çevrimiçi'),
  ('leaderboard_stat_new_today', '"true"', 'Sayaç: Bugün yeni üye'),
  ('leaderboard_stat_posts_today', '"true"', 'Sayaç: Bugün paylaşım'),
  ('leaderboard_stat_orders_today', '"true"', 'Sayaç: Bugün verilen sipariş'),
  ('leaderboard_order', '""',
   'Kartların sırası: virgülle ayrılmış anahtarlar. Boş/eksik anahtarlar varsayılan sırayla sona eklenir.')
ON CONFLICT (key) DO NOTHING;

-- -----------------------------------------------------------------------------
-- 3) Küçük yardımcılar
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.leaderboard_name(p_full text, p_user text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $fn$
  SELECT COALESCE(NULLIF(btrim(p_full), ''), p_user);
$fn$;

CREATE OR REPLACE FUNCTION public.leaderboard_handle(p_user text)
RETURNS text
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $fn$
  SELECT CASE WHEN NULLIF(btrim(p_user), '') IS NULL THEN NULL ELSE '@' || p_user END;
$fn$;

CREATE OR REPLACE FUNCTION public.leaderboard_card_keys()
RETURNS text[]
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $fn$
  SELECT ARRAY[
    'stats', 'stats_today', 'new_members', 'top_followed', 'top_liked_posts',
    'top_viewed_posts', 'top_viewed_stories', 'top_sellers',
    'top_product_sellers', 'top_customers', 'top_rated_shops',
    'top_posters', 'most_liked', 'top_logins', 'top_couriers',
    'okey_most_played', 'okey_most_wins', 'okey_most_losses',
    'okey_win_rate', 'okey_richest', 'okey_points_won',
    'okey_hands_won', 'okey_best_score'
  ];
$fn$;

-- Admin'in kaydettiği sıra; bilinmeyen anahtarlar atılır, eksikler varsayılan
-- sırayla sona eklenir (yeni bir pano eklenince eski kayıt bozulmaz).
CREATE OR REPLACE FUNCTION public.leaderboard_order()
RETURNS text[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  WITH saved AS (
    SELECT btrim(t.k) AS key, t.ord
    FROM unnest(string_to_array(COALESCE(public.leaderboard_setting('leaderboard_order'), ''), ','))
         WITH ORDINALITY AS t(k, ord)
  ),
  picked AS (
    SELECT DISTINCT ON (s.key) s.key, s.ord
    FROM saved s
    WHERE s.key = ANY (public.leaderboard_card_keys())
    ORDER BY s.key, s.ord
  ),
  rest AS (
    SELECT d.k AS key, 100000 + d.ord AS ord
    FROM unnest(public.leaderboard_card_keys()) WITH ORDINALITY AS d(k, ord)
    WHERE d.k NOT IN (SELECT key FROM picked)
  )
  SELECT array_agg(u.key ORDER BY u.ord)
  FROM (SELECT key, ord FROM picked UNION ALL SELECT key, ord FROM rest) u;
$fn$;

-- Bir kullanıcı herkese açık bir listede görünebilir mi? (v1'e gizleme eklendi)
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
         AND NOT EXISTS (
           SELECT 1 FROM public.leaderboard_exclusions e
           WHERE e.user_id = p_id AND (e.self_hidden OR e.admin_hidden)
         )
         AND NOT public.social_block_exists(p_id);
$fn$;

-- Bir dükkanın sahibi listede görünebilir mi? Gizli/bot sahibin dükkanı da
-- dükkan panolarında yer almaz. Sahibin PROFİL gizliliği (özel hesap) dükkanı
-- etkilemez: dükkan zaten herkese açık bir işletme.
CREATE OR REPLACE FUNCTION public.leaderboard_owner_ok(p_owner uuid)
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT EXISTS (
           SELECT 1 FROM public.profiles p
           WHERE p.id = p_owner AND NOT COALESCE(p.is_bot, false)
         )
         AND NOT EXISTS (
           SELECT 1 FROM public.leaderboard_exclusions e
           WHERE e.user_id = p_owner AND (e.self_hidden OR e.admin_hidden)
         );
$fn$;

-- Listede görünebilecek kullanıcıların KÜMESİ — bir kez, küme olarak hesaplanır.
--
-- `leaderboard_user_ok(id)` her profil satırı için ayrı çağrılınca (SECURITY
-- DEFINER olduğundan satır içine açılamaz) ~34 ms harcıyordu ve altı kullanıcı
-- panosunun hepsi bunu ödüyordu. Aynı kuralları (bot/askı/gizli hesap/kullanıcı
-- gizlemesi/iki yönlü engel/adı olmayan) tek bir taramada uygular; panolar buna
-- JOIN eder. Kural değişirse `leaderboard_user_ok` ile BİRLİKTE güncelle.
CREATE OR REPLACE FUNCTION public.leaderboard_eligible_users()
RETURNS TABLE (
  e_id         uuid,
  e_created_at timestamptz,
  e_name       text,
  e_handle     text,
  e_avatar     text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT p.id, p.created_at,
         public.leaderboard_name(p.full_name, p.username),
         public.leaderboard_handle(p.username),
         p.avatar_url
  FROM public.profiles p
  WHERE NOT COALESCE(p.is_bot, false)
    AND p.status::text = 'active'
    AND COALESCE(p.profile_is_public, true)
    AND NOT COALESCE(p.needs_username, false)
    AND COALESCE(NULLIF(btrim(p.full_name), ''), NULLIF(btrim(p.username), '')) IS NOT NULL
    AND NOT EXISTS (
      SELECT 1 FROM public.leaderboard_exclusions x
      WHERE x.user_id = p.id AND (x.self_hidden OR x.admin_hidden)
    )
    AND NOT EXISTS (
      SELECT 1 FROM public.blocked_users b
      WHERE (b.blocker_id = (SELECT auth.uid()) AND b.blocked_id = p.id)
         OR (b.blocker_id = p.id AND b.blocked_id = (SELECT auth.uid()))
    );
$fn$;

-- Kullanıcı bazlı sayı panolarının ortak kaynağı.
--
-- c_n     sıralanan değer (büyük = iyi). "En iyi maç skoru" düşük skorun iyi
--         olduğu bir ölçüttür (LEAST ile tutuluyor), bu yüzden İŞARET TERSİNE
--         çevrilerek verilir; get_leaderboard gösterirken geri çevirir.
-- c_extra eşitlikte ikinci ölçüt ve ikinci satır bilgisi (kazanma oranında
--         oynanan maç sayısı).
--
-- Okey kartları yalnız GERÇEK oyuncuları okur (`okey_stats`, `okey_wallets`).
-- Okey içindeki skor tablosu botları TÜRETİLMİŞ sayılarla listeliyor
-- (okey_bot_public_stats); onlar burada YOK: uydurma 60-400 maçlık sayılar
-- gerçek oyuncuları listeden silerdi ve diğer tüm kartlar botları zaten hariç
-- tutuyor.
DROP FUNCTION IF EXISTS public.leaderboard_user_counts(text, timestamptz);

CREATE FUNCTION public.leaderboard_user_counts(p_board text, p_since timestamptz)
RETURNS TABLE (c_uid uuid, c_n numeric, c_extra numeric)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT f.following_id, count(*)::numeric, NULL::numeric
  FROM public.follows f
  WHERE p_board = 'top_followed'
  GROUP BY f.following_id
  UNION ALL
  SELECT o.o_user_id, count(*)::numeric, NULL::numeric
  FROM public.leaderboard_completed_orders(p_since) o
  WHERE p_board = 'top_customers'
  GROUP BY o.o_user_id
  UNION ALL
  SELECT o.o_courier_id, count(*)::numeric, NULL::numeric
  FROM public.leaderboard_completed_orders(p_since) o
  WHERE p_board = 'top_couriers' AND o.o_courier_id IS NOT NULL
  GROUP BY o.o_courier_id
  UNION ALL
  SELECT x.user_id, count(*)::numeric, NULL::numeric
  FROM public.posts x
  WHERE p_board = 'top_posters' AND x.is_active IS NOT FALSE AND x.created_at >= p_since
  GROUP BY x.user_id
  UNION ALL
  SELECT x.user_id, sum(COALESCE(x.likes_count, 0))::numeric, NULL::numeric
  FROM public.posts x
  WHERE p_board = 'most_liked' AND x.is_active IS NOT FALSE AND x.created_at >= p_since
  GROUP BY x.user_id
  UNION ALL
  SELECT l.user_id, count(*)::numeric, NULL::numeric
  FROM public.user_activity_logs l
  WHERE p_board = 'top_logins' AND l.action = 'login' AND l.user_id IS NOT NULL
    AND l.created_at >= p_since
  GROUP BY l.user_id
  UNION ALL
  -- 101 Okey (tüm zamanlar; `okey_stats` birikimli sayaçlardır)
  SELECT s.user_id, s.matches_played::numeric, NULL::numeric
  FROM public.okey_stats s
  WHERE p_board = 'okey_most_played'
  UNION ALL
  SELECT s.user_id, s.matches_won::numeric, NULL::numeric
  FROM public.okey_stats s
  WHERE p_board = 'okey_most_wins'
  UNION ALL
  -- Mağlubiyet = oynanan - kazanılan (her maçın tek galibi var).
  SELECT s.user_id, (s.matches_played - s.matches_won)::numeric, NULL::numeric
  FROM public.okey_stats s
  WHERE p_board = 'okey_most_losses'
  UNION ALL
  -- Kazanma oranı yüzde; 1-2 maçlık %100'lerin listeyi doldurmaması için en az
  -- 5 maç. Eşitlikte çok maç oynayan önde.
  SELECT s.user_id,
         round(100.0 * s.matches_won / s.matches_played, 1),
         s.matches_played::numeric
  FROM public.okey_stats s
  WHERE p_board = 'okey_win_rate' AND s.matches_played >= 5
  UNION ALL
  SELECT w.user_id, w.points::numeric, NULL::numeric
  FROM public.okey_wallets w
  WHERE p_board = 'okey_richest'
  UNION ALL
  SELECT s.user_id, s.total_points_won::numeric, NULL::numeric
  FROM public.okey_stats s
  WHERE p_board = 'okey_points_won'
  UNION ALL
  SELECT s.user_id, s.hands_won::numeric, NULL::numeric
  FROM public.okey_stats s
  WHERE p_board = 'okey_hands_won'
  UNION ALL
  -- En iyi maç skoru = EN DÜŞÜK skor (okey_stats'ta LEAST ile tutulur); büyük=iyi
  -- sıralamaya sokmak için işareti tersine çevrilir.
  SELECT s.user_id, (-s.best_match_score)::numeric, NULL::numeric
  FROM public.okey_stats s
  WHERE p_board = 'okey_best_score'
    AND s.matches_played > 0 AND s.best_match_score IS NOT NULL;
$fn$;

REVOKE ALL ON FUNCTION public.leaderboard_name(text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.leaderboard_handle(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.leaderboard_card_keys() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.leaderboard_order() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.leaderboard_owner_ok(uuid) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.leaderboard_eligible_users() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.leaderboard_user_counts(text, timestamptz) FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 4) Sayaçlar
--
-- ÜYE / ÜYESİZ AYRIMI: misafir girişi Supabase anonim kullanıcısıdır
-- (`auth.users.is_anonymous`) ve `profiles`ta `misafir_xxxx` adıyla bir satırı
-- olur. Bunlar üye DEĞİLDİR: "Toplam üye" onları saymaz, "Üyesiz kullanıcı"
-- yalnız onları sayar. (Misafirler zaten hiçbir sıralamaya girmez: profilleri
-- gizli.) Hesap açmadan ve misafir oturumu bile başlatmadan gezenler HİÇBİR YERDE
-- izlenmiyor — `app_analytics_events`in her satırında user_id var.
--
-- ZİYARETÇİ: bugün (İstanbul takvim günü) herhangi bir iz bırakan kişi — profilde
-- last_seen, eylem günlüğü ya da analitik olayı. Misafirler dahil; bot hariç.
-- "Bugün aktif üye" aynı kümenin üyesiz olmayan kısmıdır.
--
-- ÇEVRİMİÇİ: son 3 dakikada iz bırakan (kalp atışı 2 dk, uygulamadaki
-- `activeThreshold` ile aynı). Hayalet mod kullanıcıları da sayılır — toplam bir
-- sayı kimseyi açığa çıkarmaz; hayalet modu kişinin görünürlüğünü gizler,
-- toplamı değil. (set_my_presence hayalet için is_online=false yazar ama
-- last_seen'i günceller.) `profiles.is_online` bayrağı bayat kalabiliyor
-- (canlıda 32 "çevrimiçi", son 5 dakikada 0 kişi), o yüzden kullanılmıyor.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.leaderboard_today_start()
RETURNS timestamptz
LANGUAGE sql
STABLE
SET search_path = ''
AS $fn$
  SELECT date_trunc('day', now() AT TIME ZONE 'Europe/Istanbul') AT TIME ZONE 'Europe/Istanbul';
$fn$;

CREATE OR REPLACE FUNCTION public.leaderboard_seen_users(p_since timestamptz)
RETURNS TABLE (s_id uuid, s_guest boolean)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  WITH seen AS (
    SELECT p.id AS uid FROM public.profiles p WHERE p.last_seen >= p_since
    UNION
    SELECT l.user_id FROM public.user_activity_logs l
      WHERE l.created_at >= p_since AND l.user_id IS NOT NULL
    UNION
    SELECT e.user_id FROM public.app_analytics_events e
      WHERE e.created_at >= p_since AND e.user_id IS NOT NULL
  )
  SELECT p.id,
         EXISTS (SELECT 1 FROM auth.users a WHERE a.id = p.id AND a.is_anonymous)
  FROM seen
  JOIN public.profiles p ON p.id = seen.uid
  WHERE NOT COALESCE(p.is_bot, false) AND p.status::text = 'active';
$fn$;

CREATE OR REPLACE FUNCTION public.leaderboard_stats()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  -- Kapalı sayaç NULL döner, jsonb_strip_nulls çıkarır: istemci yalnız açık
  -- olanları alır. CASE tembel çalışır: kapalı sayacın sorgusu hiç yürümez.
  SELECT jsonb_strip_nulls(jsonb_build_object(
    -- ---- Genel ("Rakamlarla Cizre") ----
    'members', CASE WHEN public.leaderboard_flag('leaderboard_stat_members', true) THEN
      (SELECT count(*) FROM public.profiles p
        WHERE NOT COALESCE(p.is_bot, false) AND p.status::text = 'active'
          AND NOT EXISTS (SELECT 1 FROM auth.users a WHERE a.id = p.id AND a.is_anonymous)) END,
    'guests', CASE WHEN public.leaderboard_flag('leaderboard_stat_guests', true) THEN
      (SELECT count(*) FROM public.profiles p
        JOIN auth.users a ON a.id = p.id
        WHERE a.is_anonymous
          AND NOT COALESCE(p.is_bot, false) AND p.status::text = 'active') END,
    'ghosts', CASE WHEN public.leaderboard_flag('leaderboard_stat_ghosts', true) THEN
      (SELECT count(*) FROM public.profiles p
        WHERE COALESCE(p.is_ghost_mode, false)
          AND NOT COALESCE(p.is_bot, false) AND p.status::text = 'active'
          AND NOT EXISTS (SELECT 1 FROM auth.users a WHERE a.id = p.id AND a.is_anonymous)) END,
    'orders', CASE WHEN public.leaderboard_flag('leaderboard_stat_orders', true) THEN
      (SELECT count(*) FROM public.leaderboard_completed_orders('-infinity'::timestamptz)) END,
    'shops', CASE WHEN public.leaderboard_flag('leaderboard_stat_shops', true) THEN
      (SELECT count(*) FROM public.shops s
        WHERE s.is_active AND COALESCE(s.is_approved, true)
          AND public.leaderboard_owner_ok(s.owner_id)) END,
    'products', CASE WHEN public.leaderboard_flag('leaderboard_stat_products', true) THEN
      (SELECT count(*) FROM public.products pr
        JOIN public.shops s ON s.id = pr.shop_id
        WHERE COALESCE(pr.is_active, true)
          AND s.is_active AND COALESCE(s.is_approved, true)
          AND public.leaderboard_owner_ok(s.owner_id)) END,
    'posts', CASE WHEN public.leaderboard_flag('leaderboard_stat_posts', true) THEN
      (SELECT count(*) FROM public.posts x
        JOIN public.profiles p ON p.id = x.user_id
        WHERE x.is_active IS NOT FALSE AND NOT COALESCE(p.is_bot, false)) END,
    'okey_matches', CASE WHEN public.leaderboard_flag('leaderboard_stat_okey_matches', true) THEN
      (SELECT count(*) FROM public.okey_matches m WHERE m.status = 'finished') END,

    -- ---- Bugün ("Bugün Cizre'de") ----
    'visitors_today', CASE WHEN public.leaderboard_flag('leaderboard_stat_visitors_today', true) THEN
      (SELECT count(*) FROM public.leaderboard_seen_users(public.leaderboard_today_start())) END,
    'active_today', CASE WHEN public.leaderboard_flag('leaderboard_stat_active_today', true) THEN
      (SELECT count(*) FROM public.leaderboard_seen_users(public.leaderboard_today_start()) v
        WHERE NOT v.s_guest) END,
    'guests_today', CASE WHEN public.leaderboard_flag('leaderboard_stat_guests_today', true) THEN
      (SELECT count(*) FROM public.leaderboard_seen_users(public.leaderboard_today_start()) v
        WHERE v.s_guest) END,
    'online_now', CASE WHEN public.leaderboard_flag('leaderboard_stat_online_now', true) THEN
      (SELECT count(*) FROM public.leaderboard_seen_users(now() - interval '3 minutes')) END,
    'new_today', CASE WHEN public.leaderboard_flag('leaderboard_stat_new_today', true) THEN
      (SELECT count(*) FROM public.profiles p
        WHERE p.created_at >= public.leaderboard_today_start()
          AND NOT COALESCE(p.is_bot, false) AND p.status::text = 'active'
          AND NOT EXISTS (SELECT 1 FROM auth.users a WHERE a.id = p.id AND a.is_anonymous)) END,
    'posts_today', CASE WHEN public.leaderboard_flag('leaderboard_stat_posts_today', true) THEN
      (SELECT count(*) FROM public.posts x
        JOIN public.profiles p ON p.id = x.user_id
        WHERE x.is_active IS NOT FALSE AND NOT COALESCE(p.is_bot, false)
          AND x.created_at >= public.leaderboard_today_start()) END,
    -- "Verilen": bugün verilen ve iptal/başarısız/iade OLMAYAN siparişler
    -- (tamamlanmış olması beklenmez; tamamlananlar genel kartta).
    'orders_today', CASE WHEN public.leaderboard_flag('leaderboard_stat_orders_today', true) THEN
      (SELECT count(*) FROM public.orders o
        WHERE o.created_at >= public.leaderboard_today_start()
          AND o.status::text <> 'cancelled')
      + (SELECT count(*) FROM public.digital_orders d
        WHERE d.created_at >= public.leaderboard_today_start()
          AND d.status::text NOT IN ('canceled', 'failed', 'refunded')) END
  ));
$fn$;
REVOKE ALL ON FUNCTION public.leaderboard_today_start() FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.leaderboard_seen_users(timestamptz) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.leaderboard_stats() FROM PUBLIC, anon, authenticated;

-- -----------------------------------------------------------------------------
-- 5) Ayarlar (genişletilmiş şekil; v1 ile aynı imza)
-- -----------------------------------------------------------------------------
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
    'order', to_jsonb(public.leaderboard_order()),
    'boards', (
      SELECT jsonb_object_agg(k, public.leaderboard_flag('leaderboard_board_' || k, true))
      FROM unnest(public.leaderboard_card_keys()) AS k
    ),
    'stats', (
      SELECT jsonb_object_agg(k, public.leaderboard_flag('leaderboard_stat_' || k, true))
      FROM unnest(ARRAY['members', 'guests', 'ghosts', 'orders', 'shops', 'products', 'posts',
                   'okey_matches', 'visitors_today', 'active_today', 'guests_today',
                   'online_now', 'new_today', 'posts_today', 'orders_today']) AS k
    )
  );
$fn$;
REVOKE ALL ON FUNCTION public.leaderboard_settings() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.leaderboard_settings() TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 6) get_leaderboard — tek pano (v2: r_owner, r_me, yeni panolar, "senin sıran")
--
-- Dönüş şekli değiştiği için önce DROP.
--
--   r_type   'user' | 'shop' | 'post' | 'story'
--   r_owner  post/story için yazarın kullanıcı kimliği
--   r_me     satır çağıranın kendisi mi (kullanıcı panolarında)
--
-- Kullanıcı panolarında ilk N'e ek olarak çağıranın KENDİ satırı (sırası N'den
-- büyükse) da döner; istemci onu "Senin sıran" olarak ayırır. Gizli ya da
-- listeye uygun olmayan kullanıcının kendi satırı zaten hiç oluşmaz.
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_leaderboard(text);

CREATE FUNCTION public.get_leaderboard(p_board text)
RETURNS TABLE (
  r_rank    integer,
  r_type    text,
  r_id      uuid,
  r_name    text,
  r_handle  text,
  r_avatar  text,
  r_metric  numeric,
  r_extra   numeric,
  r_at      timestamptz,
  r_owner   uuid,
  r_me      boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_limit integer;
  v_since timestamptz;
  v_me    uuid := (SELECT auth.uid());
BEGIN
  IF v_me IS NULL THEN
    RETURN;
  END IF;
  IF NOT public.leaderboard_flag('leaderboard_enabled', true) THEN
    RETURN;
  END IF;
  IF p_board IS NULL
     OR p_board IN ('stats', 'stats_today')
     OR NOT (p_board = ANY (public.leaderboard_card_keys()))
     OR NOT public.leaderboard_flag('leaderboard_board_' || p_board, true) THEN
    RETURN;
  END IF;

  v_limit := public.leaderboard_limit_value();
  v_since := public.leaderboard_period_since();

  IF p_board = 'new_members' THEN
    RETURN QUERY
    SELECT (row_number() OVER (ORDER BY e.e_created_at DESC, e.e_id))::integer,
           'user'::text, e.e_id, e.e_name, e.e_handle, e.e_avatar,
           NULL::numeric, NULL::numeric, e.e_created_at,
           NULL::uuid, (e.e_id = v_me)
    FROM public.leaderboard_eligible_users() e
    ORDER BY e.e_created_at DESC, e.e_id
    LIMIT v_limit;

  ELSIF p_board IN ('top_followed', 'top_customers', 'top_couriers',
                    'top_posters', 'most_liked', 'top_logins',
                    'okey_most_played', 'okey_most_wins', 'okey_most_losses',
                    'okey_win_rate', 'okey_richest', 'okey_points_won',
                    'okey_hands_won', 'okey_best_score') THEN
    RETURN QUERY
    WITH ranked AS (
      SELECT (row_number() OVER (
               ORDER BY c.c_n DESC, COALESCE(c.c_extra, 0) DESC, e.e_created_at, e.e_id
             ))::integer AS rk,
             e.e_id AS pid, e.e_name AS nm, e.e_handle AS hd, e.e_avatar AS av,
             -- En iyi skor işaret tersine sıralandı; görünen değer gerçek skor.
             CASE WHEN p_board = 'okey_best_score' THEN -c.c_n ELSE c.c_n END AS n,
             c.c_extra AS ex
      FROM public.leaderboard_user_counts(p_board, v_since) c
      JOIN public.leaderboard_eligible_users() e ON e.e_id = c.c_uid
      -- En iyi skorda ters işaretli değer 0 ya da negatif olabilir (skor >= 0).
      WHERE c.c_n > 0 OR p_board = 'okey_best_score'
    )
    SELECT ranked.rk, 'user'::text, ranked.pid, ranked.nm, ranked.hd, ranked.av,
           ranked.n, ranked.ex, NULL::timestamptz, NULL::uuid,
           (ranked.pid = v_me)
    FROM ranked
    WHERE ranked.rk <= v_limit OR ranked.pid = v_me
    ORDER BY ranked.rk;

  ELSIF p_board = 'top_sellers' THEN
    RETURN QUERY
    SELECT (row_number() OVER (ORDER BY c.n DESC, s.created_at, s.id))::integer,
           'shop'::text, s.id, s.name, NULL::text, s.logo_url,
           c.n::numeric, NULL::numeric, NULL::timestamptz, NULL::uuid, false
    FROM (SELECT o.o_shop_id AS sid, count(*) AS n
            FROM public.leaderboard_completed_orders(v_since) o
            GROUP BY o.o_shop_id) c
    JOIN public.shops s ON s.id = c.sid
    WHERE s.is_active AND COALESCE(s.is_approved, true)
      AND public.leaderboard_owner_ok(s.owner_id)
    ORDER BY c.n DESC, s.created_at, s.id
    LIMIT v_limit;

  ELSIF p_board = 'top_rated_shops' THEN
    RETURN QUERY
    SELECT (row_number() OVER (ORDER BY c.a DESC, c.n DESC, s.created_at, s.id))::integer,
           'shop'::text, s.id, s.name, NULL::text, s.logo_url,
           round(c.a, 1), c.n::numeric, NULL::timestamptz, NULL::uuid, false
    FROM (SELECT r.shop_id AS sid, avg(r.rating)::numeric AS a, count(*) AS n
            FROM public.shop_reviews r
            WHERE r.rating IS NOT NULL
            GROUP BY r.shop_id) c
    JOIN public.shops s ON s.id = c.sid
    WHERE s.is_active AND COALESCE(s.is_approved, true)
      AND public.leaderboard_owner_ok(s.owner_id)
    ORDER BY c.a DESC, c.n DESC, s.created_at, s.id
    LIMIT v_limit;

  ELSIF p_board = 'top_product_sellers' THEN
    -- SMM sağlayıcısından otomatik eşitlenen ürünler "yüklenen" sayılmaz.
    RETURN QUERY
    SELECT (row_number() OVER (ORDER BY c.n DESC, s.created_at, s.id))::integer,
           'shop'::text, s.id, s.name, NULL::text, s.logo_url,
           c.n::numeric, NULL::numeric, NULL::timestamptz, NULL::uuid, false
    FROM (SELECT pr.shop_id AS sid, count(*) AS n
            FROM public.products pr
            WHERE COALESCE(pr.is_active, true)
              AND pr.smm_provider_id IS NULL
              AND pr.created_at >= v_since
            GROUP BY pr.shop_id) c
    JOIN public.shops s ON s.id = c.sid
    WHERE s.is_active AND COALESCE(s.is_approved, true)
      AND public.leaderboard_owner_ok(s.owner_id)
    ORDER BY c.n DESC, s.created_at, s.id
    LIMIT v_limit;

  ELSIF p_board = 'top_liked_posts' THEN
    RETURN QUERY
    SELECT (row_number() OVER (ORDER BY po.likes_count DESC, po.created_at DESC, po.id))::integer,
           'post'::text, po.id,
           COALESCE(NULLIF(left(regexp_replace(btrim(COALESCE(po.content, '')), '\s+', ' ', 'g'), 80), ''),
                    'Fotoğraflı gönderi'),
           e.e_handle,
           COALESCE(po.images[1], po.image_url),
           po.likes_count::numeric, NULL::numeric, po.created_at, po.user_id, false
    FROM public.posts po
    JOIN public.leaderboard_eligible_users() e ON e.e_id = po.user_id
    WHERE po.is_active IS NOT FALSE
      AND po.created_at >= v_since
      AND COALESCE(po.likes_count, 0) > 0
    ORDER BY po.likes_count DESC, po.created_at DESC, po.id
    LIMIT v_limit;

  ELSIF p_board = 'top_viewed_posts' THEN
    -- Yazarın kendi görüntülemeleri sayılmaz.
    RETURN QUERY
    SELECT (row_number() OVER (ORDER BY c.n DESC, po.created_at DESC, po.id))::integer,
           'post'::text, po.id,
           COALESCE(NULLIF(left(regexp_replace(btrim(COALESCE(po.content, '')), '\s+', ' ', 'g'), 80), ''),
                    'Fotoğraflı gönderi'),
           e.e_handle,
           COALESCE(po.images[1], po.image_url),
           c.n::numeric, NULL::numeric, po.created_at, po.user_id, false
    FROM (SELECT v.post_id AS pid, count(*) AS n
            FROM public.post_views v
            JOIN public.posts x ON x.id = v.post_id
            WHERE v.viewed_at >= v_since
              AND v.viewer_id IS DISTINCT FROM x.user_id
            GROUP BY v.post_id) c
    JOIN public.posts po ON po.id = c.pid
    JOIN public.leaderboard_eligible_users() e ON e.e_id = po.user_id
    WHERE po.is_active IS NOT FALSE
    ORDER BY c.n DESC, po.created_at DESC, po.id
    LIMIT v_limit;

  ELSIF p_board = 'top_viewed_stories' THEN
    -- Yalnız YAYINDAKİ hikayeler (bkz. dosya başı notu); dönem uygulanmaz.
    RETURN QUERY
    SELECT (row_number() OVER (ORDER BY st.views_count DESC, st.created_at DESC, st.id))::integer,
           'story'::text, st.id,
           COALESCE(NULLIF(left(regexp_replace(btrim(COALESCE(st.text_content, '')), '\s+', ' ', 'g'), 80), ''),
                    'Hikaye'),
           e.e_handle,
           COALESCE(st.thumbnail_url, st.image_url),
           st.views_count::numeric, NULL::numeric, st.created_at, st.user_id, false
    FROM public.stories st
    JOIN public.leaderboard_eligible_users() e ON e.e_id = st.user_id
    WHERE st.expires_at > now()
      AND COALESCE(st.views_count, 0) > 0
    ORDER BY st.views_count DESC, st.created_at DESC, st.id
    LIMIT v_limit;
  END IF;
END;
$fn$;

REVOKE ALL ON FUNCTION public.get_leaderboard(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_leaderboard(text) TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 7) get_leaderboards — ana sayfanın TEK çağrısı
--
-- Kartlar yandan kaydırıldığı için komşu sayfanın verisi önceden hazır olmalı;
-- pano başına ayrı istek 14 gidiş-dönüş demekti.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_leaderboards()
RETURNS jsonb
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_settings jsonb := public.leaderboard_settings();
  v_boards   jsonb := '{}'::jsonb;
  v_stats    jsonb := '{}'::jsonb;
  v_key      text;
  v_rows     jsonb;
BEGIN
  IF (SELECT auth.uid()) IS NULL OR NOT (v_settings ->> 'enabled')::boolean THEN
    RETURN jsonb_build_object(
      'settings', jsonb_set(v_settings, '{enabled}', 'false'::jsonb),
      'boards', v_boards, 'stats', v_stats);
  END IF;

  FOREACH v_key IN ARRAY public.leaderboard_card_keys() LOOP
    CONTINUE WHEN v_key IN ('stats', 'stats_today');
    CONTINUE WHEN NOT COALESCE((v_settings -> 'boards' ->> v_key)::boolean, false);

    SELECT COALESCE(jsonb_agg(to_jsonb(r) ORDER BY r.r_rank), '[]'::jsonb)
      INTO v_rows
      FROM public.get_leaderboard(v_key) r;
    v_boards := v_boards || jsonb_build_object(v_key, v_rows);
  END LOOP;

  IF COALESCE((v_settings -> 'boards' ->> 'stats')::boolean, false)
     OR COALESCE((v_settings -> 'boards' ->> 'stats_today')::boolean, false) THEN
    v_stats := public.leaderboard_stats();
  END IF;

  RETURN jsonb_build_object('settings', v_settings, 'boards', v_boards, 'stats', v_stats);
END;
$fn$;

REVOKE ALL ON FUNCTION public.get_leaderboards() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_leaderboards() TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 8) Gizleme RPC'leri
-- -----------------------------------------------------------------------------

-- Kullanıcı kendi durumunu okur.
CREATE OR REPLACE FUNCTION public.leaderboard_my_visibility()
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  SELECT jsonb_build_object(
    'self_hidden',  COALESCE(e.self_hidden, false),
    'admin_hidden', COALESCE(e.admin_hidden, false)
  )
  FROM (SELECT 1) AS x
  LEFT JOIN public.leaderboard_exclusions e ON e.user_id = (SELECT auth.uid());
$fn$;

-- Kullanıcı kendini gizler/gösterir. admin_hidden'a DOKUNMAZ.
CREATE OR REPLACE FUNCTION public.leaderboard_set_self_hidden(p_hidden boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_me uuid := (SELECT auth.uid());
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'Oturum gerekli' USING ERRCODE = '42501';
  END IF;

  INSERT INTO public.leaderboard_exclusions (user_id, self_hidden)
  VALUES (v_me, COALESCE(p_hidden, false))
  ON CONFLICT (user_id) DO UPDATE
    SET self_hidden = EXCLUDED.self_hidden, updated_at = now();

  DELETE FROM public.leaderboard_exclusions
  WHERE user_id = v_me AND NOT self_hidden AND NOT admin_hidden;

  RETURN public.leaderboard_my_visibility();
END;
$fn$;

-- Admin bir kullanıcıyı gizler/gösterir. self_hidden'a DOKUNMAZ.
CREATE OR REPLACE FUNCTION public.admin_leaderboard_set_hidden(p_user uuid, p_hidden boolean)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  IF NOT public.auth_is_admin() THEN
    RAISE EXCEPTION 'Yetkisiz' USING ERRCODE = '42501';
  END IF;
  IF p_user IS NULL THEN
    RAISE EXCEPTION 'Kullanıcı gerekli' USING ERRCODE = '22023';
  END IF;

  INSERT INTO public.leaderboard_exclusions (user_id, admin_hidden)
  VALUES (p_user, COALESCE(p_hidden, false))
  ON CONFLICT (user_id) DO UPDATE
    SET admin_hidden = EXCLUDED.admin_hidden, updated_at = now();

  DELETE FROM public.leaderboard_exclusions
  WHERE user_id = p_user AND NOT self_hidden AND NOT admin_hidden;
END;
$fn$;

-- Admin kullanıcı listesindeki rozet için: gizli olan herkes.
CREATE OR REPLACE FUNCTION public.admin_leaderboard_hidden_users()
RETURNS TABLE (h_user_id uuid, h_self boolean, h_admin boolean)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
BEGIN
  IF NOT public.auth_is_admin() THEN
    RAISE EXCEPTION 'Yetkisiz' USING ERRCODE = '42501';
  END IF;
  RETURN QUERY
  SELECT e.user_id, e.self_hidden, e.admin_hidden
  FROM public.leaderboard_exclusions e
  WHERE e.self_hidden OR e.admin_hidden;
END;
$fn$;

REVOKE ALL ON FUNCTION public.leaderboard_my_visibility() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.leaderboard_set_self_hidden(boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_leaderboard_set_hidden(uuid, boolean) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_leaderboard_hidden_users() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.leaderboard_my_visibility() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.leaderboard_set_self_hidden(boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_leaderboard_set_hidden(uuid, boolean) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_leaderboard_hidden_users() TO authenticated, service_role;

commit;
