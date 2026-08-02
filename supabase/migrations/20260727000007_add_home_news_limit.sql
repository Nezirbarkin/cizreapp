-- ============================================
-- ANASAYFA HABER KARTI SAYISI LİMİTİ EKLE
-- Tarih: 2026-07-27
-- Açıklama: Admin panelinden anasayfada gösterilecek
-- haber kartı sayısını ayarlamak için yeni sütun
-- ============================================

-- app_about_settings tablosuna home_news_limit sütunu ekle
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'app_about_settings'
        AND column_name = 'home_news_limit'
    ) THEN
        ALTER TABLE app_about_settings
        ADD COLUMN home_news_limit INTEGER DEFAULT 3;

        COMMENT ON COLUMN app_about_settings.home_news_limit
        IS 'Anasayfada gösterilecek haber kartı sayısı (admin panelinden ayarlanır)';
    END IF;

    RAISE NOTICE '✅ home_news_limit sütunu eklendi veya zaten mevcut';
END $$;

-- Mevcut kayıtlardaki varsayılan değeri ayarla (3)
UPDATE app_about_settings
SET home_news_limit = 3
WHERE home_news_limit IS NULL;

-- ============================================
-- TAMAMLANDI
-- ============================================
