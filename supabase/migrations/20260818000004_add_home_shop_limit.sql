-- ============================================
-- ANASAYFA DÜKKAN SAYISI LİMİTİ EKLE
-- Tarih: 2026-08-18
-- Açıklama: Admin panelinden anasayfada gösterilecek
-- dükkan (mağaza) sayısını ayarlamak için yeni sütun.
-- home_category_limit / home_news_limit ile aynı desen.
-- ============================================

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns
        WHERE table_name = 'app_about_settings'
        AND column_name = 'home_shop_limit'
    ) THEN
        ALTER TABLE app_about_settings
        ADD COLUMN home_shop_limit INTEGER DEFAULT 8;

        COMMENT ON COLUMN app_about_settings.home_shop_limit
        IS 'Anasayfada gösterilecek dükkan (mağaza) sayısı (admin panelinden ayarlanır)';
    END IF;

    RAISE NOTICE '✅ home_shop_limit sütunu eklendi veya zaten mevcut';
END $$;

-- Mevcut kayıtlardaki varsayılan değeri ayarla (8)
UPDATE app_about_settings
SET home_shop_limit = 8
WHERE home_shop_limit IS NULL;

NOTIFY pgrst, 'reload schema';

-- ============================================
-- TAMAMLANDI
-- ============================================
