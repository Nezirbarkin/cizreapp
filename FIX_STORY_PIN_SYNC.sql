-- =============================================
-- HİKAYE SABİTLEME DÜZELTMESİ
-- =============================================
-- Bu SQL, hikaye tablosundaki is_pinned ve admin_pinned
-- kolonlarını senkronize eder.
-- =============================================

-- 1) admin_pinned=true olan hikayelerde is_pinned=true yap
UPDATE stories
SET is_pinned = true
WHERE admin_pinned = true AND is_pinned = false;

-- 2) admin_pinned=false olan hikayelerde is_pinned=false yap
UPDATE stories
SET is_pinned = false
WHERE admin_pinned = false AND is_pinned = true;

-- 3) is_pinned=true olan hikayelerde admin_pinned=true yap
UPDATE stories
SET admin_pinned = true
WHERE is_pinned = true AND admin_pinned = false;

-- 4) is_pinned=false olan hikayelerde admin_pinned=false yap
UPDATE stories
SET admin_pinned = false
WHERE is_pinned = false AND admin_pinned = true;

-- 5) Son durumu kontrol et
SELECT id, is_pinned, admin_pinned, created_at
FROM stories
ORDER BY admin_pinned DESC, is_pinned DESC, created_at DESC
LIMIT 20;
