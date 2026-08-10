-- =============================================================================
-- 2026-08-07 — Çift bildirim (duplicate) kanıtı ve düzeltme sorguları
-- -----------------------------------------------------------------------------
-- AMAÇ: Mevcut veritabanında gerçekten çift bildirim üretilmiş mi tespit etmek
--       ve güvenli bir şekilde (YALNIZCA son 7 gün) temizlemek.
--
-- Bu sorgular DRY-RUN / EXECUTE modunda ikiye ayrılmıştır. Önce dry_run = true
-- ile çalıştır; çıktıyı kontrol ettikten sonra alttaki EXECUTE bloklarını
-- yorumdan çıkar.
-- =============================================================================

-- Aynı kullanıcı + entity + type + yakın zaman penceresi içinde
-- birden fazla bildirim var mı? (4 saatlik pencere = agresif dedup)
WITH dups AS (
  SELECT
    user_id, type, entity_id,
    COUNT(*) AS adet,
    array_agg(id ORDER BY created_at DESC) AS ids,
    array_agg(is_read ORDER BY created_at DESC) AS read_states
  FROM public.notifications
  WHERE created_at > NOW() - INTERVAL '7 days'
    AND entity_id IS NOT NULL
  GROUP BY user_id, type, entity_id
  HAVING COUNT(*) > 1
)
SELECT
  user_id, type, entity_id, adet,
  ids[1] AS en_yeni_id,
  ids[array_length(ids, 1)] AS en_eski_id
FROM dups
ORDER BY adet DESC
LIMIT 50;

-- Tip bazlı dağılım — hangi tipte daha çok çift var?
WITH dups AS (
  SELECT user_id, type, entity_id, COUNT(*) AS adet
  FROM public.notifications
  WHERE created_at > NOW() - INTERVAL '7 days'
    AND entity_id IS NOT NULL
  GROUP BY user_id, type, entity_id
  HAVING COUNT(*) > 1
)
SELECT type, COUNT(*) AS duplicate_grubu, SUM(adet - 1) AS fazlalik_satir
FROM dups
GROUP BY type
ORDER BY duplicate_grubu DESC;

-- ===========================================================================
-- DÜZELTME — en yeni bildirimi tut, eskileri sil
-- (EXECUTE modu — aşağıdaki blokları yorumdan çıkar)
-- ===========================================================================
-- BEGIN;
--
-- WITH dups AS (
--   SELECT
--     user_id, type, entity_id, created_at,
--     ROW_NUMBER() OVER (
--       PARTITION BY user_id, type, entity_id
--       ORDER BY created_at DESC
--     ) AS rn
--   FROM public.notifications
--   WHERE created_at > NOW() - INTERVAL '7 days'
--     AND entity_id IS NOT NULL
-- )
-- DELETE FROM public.notifications n
-- USING dups d
-- WHERE n.user_id = d.user_id
--   AND n.type = d.type
--   AND n.entity_id = d.entity_id
--   AND n.created_at = d.created_at
--   AND d.rn > 1;
--
-- COMMIT;
--
-- SELECT 'Silinen duplike sayısı: ' || COUNT(*) FROM public.notifications
-- WHERE created_at > NOW() - INTERVAL '7 days'; -- kontrol
