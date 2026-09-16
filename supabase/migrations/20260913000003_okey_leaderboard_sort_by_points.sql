-- =============================================================================
-- 101 OKEY — SKOR TABLOSU PUANA GÖRE SIRALANSIN (kullanıcı isteği, 2026-09-13)
-- -----------------------------------------------------------------------------
-- okey_leaderboard, satırları `matches_won DESC, hands_won DESC, points DESC`
-- sırasıyla döndürüyordu — yani asıl sıralama ölçütü galibiyet sayısıydı,
-- PUAN yalnızca üçüncü eşitlik bozanıydı. Tablonun sağ sütununda (ve
-- OkeyRankBadge'in yanında) gösterilen büyük rakam PUAN olduğu için bu iki
-- şey ayrışıyordu: bir satır listede 5. sırada dururken üstündeki satırdan
-- daha yüksek puana sahip olabiliyordu (canlı veride görüldü, bkz.
-- PROJE_HAVIZA_CHANGELOG).
--
-- Gövde 20260908200001'den taşındı; TEK FARK son ORDER BY satırıdır.
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

CREATE OR REPLACE FUNCTION public.okey_leaderboard(p_limit int DEFAULT 50)
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

    -- BOTLAR — türetilmiş istatistikler. Yalnız ETKİN kimlikler.
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
  -- DEĞİŞEN SATIR: PUAN artık birincil ölçüt. Galibiyet/el galibiyeti yalnızca
  -- puan eşitse devreye girer (ör. iki taze hesap 0 puanda başladığında).
  ORDER BY e.points DESC, e.matches_won DESC, e.hands_won DESC
  LIMIT LEAST(GREATEST(COALESCE(p_limit, 50), 1), 200);
$fn$;

COMMENT ON FUNCTION public.okey_leaderboard(int) IS
  'Okey skor tablosu, PUANA göre sıralı (eşitlikte galibiyet/el galibiyeti). Gerçek oyuncuların KAYITLI istatistikleriyle bot kimliklerinin TÜRETİLMİŞ istatistikleri (okey_bot_public_stats) tek listede birleşir. Bot satırlarında user_id NULL''dur; profil kartı bot_profile_id ile açılır.';

REVOKE ALL ON FUNCTION public.okey_leaderboard(int) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_leaderboard(int) TO authenticated;

NOTIFY pgrst, 'reload schema';
