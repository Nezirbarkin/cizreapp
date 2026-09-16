-- =============================================================================
-- 101 OKEY — okey_bot_public_stats: HİÇ OYNAMAMIŞ BOT 1000 PUAN GÖSTERSİN
-- -----------------------------------------------------------------------------
-- 20260913000004'teki formül `GREATEST(0, 1000 - ROUND(toplam / NULLIF(maç,0)))`
-- idi. `matches_played = 0` olduğunda `NULLIF(0,0)` NULL döner, bölüm NULL
-- olur, `1000 - NULL` NULL olur — ve Postgres'te `GREATEST(0, NULL)` NULL'u
-- YOK SAYAR, yani sonuç 1000 değil **0** çıkar (canlı testte görüldü). Yeni
-- bir bot ya da henüz kayda geçmemiş biri "0 puanlık en kötü oyuncu" gibi
-- görünüyordu — niyet tam tersiydi: hiç oynamamış oyuncu NÖTR (1000)
-- başlamalı, insan tarafındaki "cüzdan henüz hiç işlem görmedi" durumunun
-- karşılığı.
--
-- DÜZELTME: ortalamayı NULLIF yerine CASE ile hesapla — maç sayısı 0 ise
-- ortalama açıkça 0 sayılır (1000 − 0 = 1000).
-- =============================================================================

SET search_path = public, pg_temp;
SET LOCAL lock_timeout = '10s';

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
STABLE
SET search_path = ''
AS $fn$
  SELECT
    GREATEST(0, 1000 - ROUND(
      CASE WHEN COALESCE(s.matches_played, 0) = 0 THEN 0
           ELSE COALESCE(s.total_final_score, 0)::numeric / s.matches_played
      END
    ))::int,
    COALESCE(s.matches_played, 0),
    COALESCE(s.matches_won, 0),
    COALESCE(s.hands_played, 0),
    COALESCE(s.hands_won, 0),
    s.best_match_score
  FROM (SELECT 1) AS one
  LEFT JOIN public.okey_bot_stats AS s ON s.bot_profile_id = p_bot_profile_id
$fn$;

COMMENT ON FUNCTION public.okey_bot_public_stats(uuid) IS
  'Bir bot kimliğinin GERÇEK oyun istatistikleri (okey_bot_stats''tan). Puan, botun gerçek final skorlarının ortalamasından türetilir çünkü botun cüzdanı yoktur (ekonominin dışındadır); hiç oynamamışsa 1000 (nötr). Skor tablosu (okey_leaderboard) ile profil kartı (okey_profile_card) aynı sayıları göstersin diye tek kaynak burasıdır.';

REVOKE ALL ON FUNCTION public.okey_bot_public_stats(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.okey_bot_public_stats(uuid) TO authenticated;

NOTIFY pgrst, 'reload schema';
