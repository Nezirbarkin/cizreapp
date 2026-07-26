-- ============================================
-- HABERLER published_at OTOMATIK SET ETME
-- ============================================
-- Sorun: Haber kayıt edildiğinde veya yayınlandığında
-- published_at alanı NULL kalıyordu. Bu da ORDER BY
-- published_at DESC sıralamasını bozuyordu.
--
-- Çözüm: is_published değiştiğinde otomatik olarak
-- published_at alanını NOW() veya NULL yapacak trigger.
-- ============================================

-- 1. published_at otomatik güncelleyen trigger fonksiyonu
CREATE OR REPLACE FUNCTION set_news_published_at()
RETURNS TRIGGER AS $$
BEGIN
    -- is_published TRUE olduysa ve published_at NULL ise veya daha önce yayınlanmamışsa
    IF NEW.is_published = true AND (
        OLD.is_published IS DISTINCT FROM true OR
        NEW.published_at IS NULL
    ) THEN
        NEW.published_at = NOW();
    END IF;
    
    -- is_published FALSE olduysa (yayından kaldırıldıysa) published_at'i NULL yap
    IF NEW.is_published = false AND OLD.is_published = true THEN
        NEW.published_at = NULL;
    END IF;
    
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- 2. Trigger'ı news tablosuna ekle (varsa yeniden oluştur)
DROP TRIGGER IF EXISTS set_news_published_at_trigger ON news;
CREATE TRIGGER set_news_published_at_trigger
    BEFORE UPDATE OF is_published ON news
    FOR EACH ROW
    EXECUTE FUNCTION set_news_published_at();

-- 3. INSERT için de trigger ekle (is_published=true olarak eklenirse)
DROP TRIGGER IF EXISTS set_news_published_at_on_insert ON news;
CREATE TRIGGER set_news_published_at_on_insert
    BEFORE INSERT ON news
    FOR EACH ROW
    WHEN (NEW.is_published = true AND NEW.published_at IS NULL)
    EXECUTE FUNCTION set_news_published_at();

-- 4. Mevcut yayınlanmış haberlerin published_at'sini doldur
-- (Yayınlanmış ama published_at NULL olan haberleri güncelle)
UPDATE news
SET published_at = created_at
WHERE is_published = true AND published_at IS NULL;

-- 5. Trigger'ın düzgün çalıştığından emin olmak için search_path'i ayarla
-- (bazı durumlarda gerekli olabilir)
ALTER FUNCTION set_news_published_at() SET search_path = public, auth;

-- 6. İndeksleri kontrol et ve optimize et
-- published_at NULL olmayan kayıtlar için partial index
DROP INDEX IF EXISTS idx_news_published_not_null;
CREATE INDEX IF NOT EXISTS idx_news_published_not_null 
    ON news(published_at DESC) 
    WHERE published_at IS NOT NULL;
