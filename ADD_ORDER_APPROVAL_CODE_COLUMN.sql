-- ================================================
-- order_approval_code_enabled Sütunu Ekleme
-- ================================================
-- Bu sütun, sipariş onay kodu özelliğinin açık/kapalı olduğunu kontrol eder

-- Sütunu ekle (mevcutsa hata verme)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'app_about_settings' 
        AND column_name = 'order_approval_code_enabled'
    ) THEN
        ALTER TABLE app_about_settings 
        ADD COLUMN order_approval_code_enabled BOOLEAN DEFAULT true;
        
        RAISE NOTICE 'order_approval_code_enabled sütunu eklendi';
    ELSE
        RAISE NOTICE 'order_approval_code_enabled sütunu zaten mevcut';
    END IF;
END $$;

-- Varsayılan değerleri ata (tablo boşsa)
UPDATE app_about_settings
SET order_approval_code_enabled = true
WHERE order_approval_code_enabled IS NULL;

-- Kontrol
SELECT 
    id,
    global_orders_enabled,
    order_approval_code_enabled
FROM app_about_settings;
