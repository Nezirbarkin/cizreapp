-- =============================================================================
-- 101 Okey — SKOR TABLOSUNDA BOTLAR DA GÖRÜNÜYOR
-- -----------------------------------------------------------------------------
-- Kullanıcı isteği (2026-09-08): "botlarında skorları göster 101 okeyde".
--
-- SORUN: `okey_leaderboard` yalnızca `okey_stats`'ı okuyordu. Botlar bilerek
-- ekonominin DIŞINDA tutuluyor (bkz. 20260908180001) — cüzdanları, masa puanı
-- ödemeleri ve istatistik satırları yok. Dolayısıyla masada dört kişiyle
-- oynayan oyuncu skor tablosunu açtığında orada neredeyse kimseyi bulamıyordu:
-- canlı projede tabloda İKİ satır vardı, masalara oturan 25 bot kimliğinin
-- hiçbiri listede değildi.
--
-- ÇÖZÜM: Botun istatistikleri profil kartında ZATEN üretiliyordu (bkz.
-- 20260905000003 — id'den türeyen sabit bir tohum). Aynı sayılar artık skor
-- tablosunda da görünüyor.
--
-- NEDEN ORTAK BİR FONKSİYON: formül iki yere kopyalansaydı, biri değiştiğinde
-- tablo "180 maç" derken kart "94 maç" derdi. Aynı bota iki farklı sayı
-- göstermek, botu ele veren en açık işaret olurdu — üstelik oyuncunun tabloda
-- görüp karta dokunarak doğruladığı ilk şey tam olarak bu sayılardır. Bu
-- yüzden tek kaynak `okey_bot_public_stats`'tır; hem tablo hem kart onu çağırır.
--
-- NEDEN BOTLAR EKONOMİYE HÂLÂ GİRMİYOR: bu sayılar TÜRETİLMİŞTİR, kayıtlı
-- değildir. Bot bir el kazandığında hiçbir yere yazılmaz; tabloda görünen sayı
-- botun kimliğinden gelir ve sabittir. Yani sıralama GÖRÜNTÜSÜ değişti,
-- ekonomi kuralları değişmedi.
--
-- NEDEN GERÇEK OYUNCU DALINDA `is_bot` FİLTRESİ: okey bot kimlikleri artık
-- sosyal taraftaki bot hesaplarından besleniyor (bkz. 20260908180001). O
-- hesapların `profiles` satırı var; ileride herhangi bir yol onlara bir
-- `okey_stats` satırı yazarsa aynı bot tabloda İKİ KEZ görünürdü.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- 1) BOT İSTATİSTİKLERİ — tek kaynak
-- -----------------------------------------------------------------------------
-- Tohum profil id'sinden gelir: aynı bot her cihazda, her ekranda, her
-- açılışta AYNI sayıları taşır. `random()` kullanılsaydı oyuncu tabloyu her
-- yenilediğinde sayılar oynardı — gerçek bir oyuncunun yapamayacağı tek şey.
--
-- `hashtext` int4 döndürür ve en küçük değeri (-2147483648) için `abs()` taşma
-- hatası verir; bu yüzden önce bigint'e çevrilir. Diğer tüm değerlerde sonuç
-- 20260905000003'teki formülle aynıdır — mevcut botların sayıları değişmez.
CREATE OR REPLACE FUNCTION public.okey_bot_public_stats(p_bot_profile_id uuid)
RETURNS TABLE(
  points int,
  matches_played int,
  matches_won int,
  hands_played int,
  hands_won int,
  best_match_score int
)
LANGUAGE sql
IMMUTABLE
SET search_path = ''
AS $fn$
  SELECT
    (500 + (s.seed % 9500))::int,                 -- puan
    s.played::int,                                -- oynanan maç
    (s.played * (42 + (s.seed % 18)) / 100)::int, -- kazanılan maç
    (s.played * 9)::int,                          -- oynanan el
    (s.played * 3)::int,                          -- kazanılan el
    (-(101 + (s.seed % 120)))::int                -- en iyi (en düşük) skor
  FROM (
    SELECT h.seed, 60 + (h.seed % 340) AS played
    FROM (SELECT abs(hashtext(p_bot_profile_id::text)::bigint) AS seed) AS h
  ) AS s;
$fn$;

COMMENT ON FUNCTION public.okey_bot_public_stats(uuid) IS
  'Bir bot kimliğinin GÖRÜNEN oyun istatistikleri. Kayıtlı değildir, profil id''sinden TÜRETİLİR ve sabittir. Skor tablosu (okey_leaderboard) ile profil kartı (okey_profile_card) aynı sayıları göstersin diye tek kaynak burasıdır.';

REVOKE ALL ON FUNCTION public.okey_bot_public_stats(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_bot_public_stats(uuid) TO authenticated;

-- -----------------------------------------------------------------------------
-- 2) SKOR TABLOSU — gerçek oyuncular + botlar
-- -----------------------------------------------------------------------------
-- `bot_profile_id` YENİ bir sütundur: istemci bir satıra dokunduğunda profil
-- kartını açabilmek için hangi kimliği soracağını bilmelidir. Bot koltuğunun
-- `user_id`'si yoktur (bkz. okey_profile_card), kart ancak bu id ile açılır.
DROP FUNCTION IF EXISTS public.okey_leaderboard(int);

CREATE FUNCTION public.okey_leaderboard(p_limit int DEFAULT 50)
RETURNS TABLE(
  user_id uuid,
  bot_profile_id uuid,
  display_name text,
  avatar_url text,
  points bigint,
  matches_played int,
  matches_won int,
  hands_won int,
  best_match_score int
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
  WITH entries AS (
    -- GERÇEK OYUNCULAR — kayıtlı istatistikler
    SELECT
      st.user_id                                              AS user_id,
      NULL::uuid                                              AS bot_profile_id,
      COALESCE(NULLIF(p.full_name, ''), p.username, 'Oyuncu') AS display_name,
      p.avatar_url                                            AS avatar_url,
      COALESCE(w.points, 0)::bigint                           AS points,
      st.matches_played                                       AS matches_played,
      st.matches_won                                          AS matches_won,
      st.hands_won                                            AS hands_won,
      st.best_match_score                                     AS best_match_score
    FROM public.okey_stats AS st
    JOIN public.profiles AS p ON p.id = st.user_id
    LEFT JOIN public.okey_wallets AS w ON w.user_id = st.user_id
    WHERE NOT COALESCE(p.is_bot, false)

    UNION ALL

    -- BOTLAR — türetilmiş istatistikler. Yalnız ETKİN kimlikler: pasif bir bot
    -- masaya da oturmaz, tabloda görünmesi "nerede bu oyuncu" sorusu olurdu.
    SELECT
      NULL::uuid,
      b.id,
      b.display_name,
      b.avatar_url,
      bs.points::bigint,
      bs.matches_played,
      bs.matches_won,
      bs.hands_won,
      bs.best_match_score
    FROM public.okey_bot_profiles AS b
    CROSS JOIN LATERAL public.okey_bot_public_stats(b.id) AS bs
    WHERE b.is_active
  )
  SELECT
    e.user_id,
    e.bot_profile_id,
    e.display_name,
    e.avatar_url,
    e.points,
    e.matches_played,
    e.matches_won,
    e.hands_won,
    e.best_match_score
  FROM entries AS e
  WHERE (SELECT auth.uid()) IS NOT NULL
  ORDER BY e.matches_won DESC, e.hands_won DESC, e.points DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
$fn$;

COMMENT ON FUNCTION public.okey_leaderboard(int) IS
  'Okey skor tablosu. Gerçek oyuncuların KAYITLI istatistikleriyle bot kimliklerinin TÜRETİLMİŞ istatistikleri (okey_bot_public_stats) tek listede birleşir. Bot satırlarında user_id NULL''dur; profil kartı bot_profile_id ile açılır.';

REVOKE ALL ON FUNCTION public.okey_leaderboard(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_leaderboard(int) TO authenticated;

-- -----------------------------------------------------------------------------
-- 3) PROFİL KARTI — botun sayıları artık ortak fonksiyondan
-- -----------------------------------------------------------------------------
-- Gövde 20260905000003'ün aynısıdır; DEĞİŞEN TEK ŞEY bot dalıdır: oyun
-- istatistikleri formülü burada tekrar yazılmaz, `okey_bot_public_stats`
-- çağrılır. Takipçi/takip/arkadaş sayıları skor tablosunda gösterilmez, o
-- yüzden onların tohumu burada kalır.
DROP FUNCTION IF EXISTS public.okey_profile_card(uuid, uuid);

CREATE FUNCTION public.okey_profile_card(
  p_user_id uuid DEFAULT NULL,
  p_bot_profile_id uuid DEFAULT NULL
)
RETURNS TABLE(
  user_id uuid,
  display_name text,
  avatar_url text,
  points int,
  matches_played int,
  matches_won int,
  hands_played int,
  hands_won int,
  best_match_score int,
  followers_count int,
  following_count int,
  friends_count int,
  is_following boolean,
  is_self boolean,
  is_follow_requested boolean,
  is_private boolean
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_me uuid := (SELECT auth.uid());
  v_seed bigint;
BEGIN
  IF v_me IS NULL THEN
    RAISE EXCEPTION 'not_authenticated';
  END IF;

  -- ---- GERÇEK KULLANICI ----------------------------------------------
  IF p_user_id IS NOT NULL THEN
    RETURN QUERY
    SELECT
      p.id,
      COALESCE(NULLIF(p.full_name, ''), p.username, 'Oyuncu'),
      p.avatar_url,
      COALESCE(w.points, 0)::int,
      COALESCE(s.matches_played, 0),
      COALESCE(s.matches_won, 0),
      COALESCE(s.hands_played, 0),
      COALESCE(s.hands_won, 0),
      s.best_match_score,
      (SELECT count(*)::int FROM public.follows f
        WHERE f.following_id = p.id),
      (SELECT count(*)::int FROM public.follows f
        WHERE f.follower_id = p.id),
      -- Arkadaş = karşılıklı takip.
      (SELECT count(*)::int FROM public.follows a
        JOIN public.follows b
          ON b.follower_id = a.following_id AND b.following_id = a.follower_id
        WHERE a.follower_id = p.id),
      EXISTS (
        SELECT 1 FROM public.follows f
        WHERE f.follower_id = v_me AND f.following_id = p.id
      ),
      p.id = v_me,
      EXISTS (
        SELECT 1 FROM public.follow_requests r
        WHERE r.follower_id = v_me AND r.following_id = p.id
          AND r.status = 'pending'
      ),
      NOT COALESCE(p.profile_is_public, true)
    FROM public.profiles AS p
    LEFT JOIN public.okey_stats AS s ON s.user_id = p.id
    LEFT JOIN public.okey_wallets AS w ON w.user_id = p.id
    WHERE p.id = p_user_id;
    RETURN;
  END IF;

  -- ---- BOT -------------------------------------------------------------
  -- Bot koltuğunun kullanıcı kimliği yoktur; kart takip düğmesini hiç
  -- göstermez (user_id NULL). Oyun istatistikleri ORTAK fonksiyondan gelir —
  -- skor tablosundaki satırla birebir aynı sayılar.
  IF p_bot_profile_id IS NOT NULL THEN
    v_seed := abs(hashtext(p_bot_profile_id::text)::bigint);

    RETURN QUERY
    SELECT
      NULL::uuid,
      b.display_name,
      b.avatar_url,
      bs.points,
      bs.matches_played,
      bs.matches_won,
      bs.hands_played,
      bs.hands_won,
      bs.best_match_score,
      (5 + (v_seed % 240))::int,                           -- takipçi
      (5 + (v_seed % 180))::int,                           -- takip
      (2 + (v_seed % 60))::int,                            -- arkadaş
      false,
      false,
      false,
      false
    FROM public.okey_bot_profiles AS b
    CROSS JOIN LATERAL public.okey_bot_public_stats(b.id) AS bs
    WHERE b.id = p_bot_profile_id;
    RETURN;
  END IF;

  RAISE EXCEPTION 'user_or_bot_required';
END;
$fn$;
REVOKE ALL ON FUNCTION public.okey_profile_card(uuid, uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_profile_card(uuid, uuid) TO authenticated;

COMMENT ON FUNCTION public.okey_profile_card(uuid, uuid) IS
  'Masada/skor tablosunda bir oyuncuya dokununca açılan profil kartı. Ad, avatar, okey puanı, maç istatistikleri, takip SAYILARI ve TAKİP DURUMU döner. Bot profillerinin oyun istatistikleri okey_bot_public_stats''ten gelir — skor tablosuyla aynı sayılar.';

NOTIFY pgrst, 'reload schema';
