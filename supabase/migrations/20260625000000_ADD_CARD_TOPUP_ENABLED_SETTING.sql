-- ============================================
-- KREDİ KARTI İLE BAKİYE YÜKLEME AYARI EKLE
-- Tarih: 2026-06-25
-- Açıklama: Admin panelinden kredi kartı ile bakiye yüklemeyi 
-- aktif/pasif yapmak için yeni ayar ekleniyor
-- ============================================

-- app_about_settings tablosuna card_topup_enabled sütunu ekle
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM information_schema.columns 
        WHERE table_name = 'app_about_settings' 
        AND column_name = 'card_topup_enabled'
    ) THEN
        ALTER TABLE app_about_settings 
        ADD COLUMN card_topup_enabled BOOLEAN DEFAULT true;
        
        -- Yeni sütun için açıklama ekle
        COMMENT ON COLUMN app_about_settings.card_topup_enabled 
        IS 'Kredi kartı ile bakiye yükleme aktif mi (iYZiCo)';
    END IF;
    
    RAISE NOTICE '✅ card_topup_enabled sütunu eklendi veya zaten mevcut';
END $$;

-- Mevcut kayıtlardaki varsayılan değeri ayarla (true)
UPDATE app_about_settings 
SET card_topup_enabled = true 
WHERE card_topup_enabled IS NULL;

-- RLS politikaları zaten authenticated rolüne izin veriyor
-- Ek bir yetkilendirme gerekmiyor

-- ============================================
-- TAMAMLANDI
-- ============================================
