-- Admin Paneline Sipariş Onay Kodu Açma/Kapama Özelliği Ekle
-- Bu SQL dosyası app_about_settings tablosuna order_approval_code_enabled kolonunu ekler

-- 1. Kolon ekle (varsa hata vermesin diye IF NOT EXISTS kontrolü)
DO $$ 
BEGIN
    -- order_approval_code_enabled kolonunu ekle (varsayılan true)
    IF NOT EXISTS (
        SELECT 1 
        FROM information_schema.columns 
        WHERE table_name = 'app_about_settings' 
        AND column_name = 'order_approval_code_enabled'
    ) THEN
        ALTER TABLE app_about_settings 
        ADD COLUMN order_approval_code_enabled BOOLEAN DEFAULT true;
        
        RAISE NOTICE 'order_approval_code_enabled kolonu eklendi';
    ELSE
        RAISE NOTICE 'order_approval_code_enabled kolonu zaten mevcut';
    END IF;
END $$;

-- 2. Mevcut kayıt varsa güncelle, yoksa yeni kayıt ekle
INSERT INTO app_about_settings (
    id,
    order_approval_code_enabled,
    created_at,
    updated_at
) VALUES (
    1,
    true, -- Varsayılan: onay kodu aktif
    NOW(),
    NOW()
)
ON CONFLICT (id) DO UPDATE SET
    order_approval_code_enabled = COALESCE(
        app_about_settings.order_approval_code_enabled, 
        EXCLUDED.order_approval_code_enabled
    ),
    updated_at = NOW();

-- 3. Kontrol sorgusu - kolon eklendi mi?
SELECT 
    column_name,
    data_type,
    column_default,
    is_nullable
FROM information_schema.columns
WHERE table_name = 'app_about_settings'
  AND column_name = 'order_approval_code_enabled';

-- 4. Mevcut ayarları görüntüle
SELECT 
    id,
    global_orders_enabled,
    order_approval_code_enabled,
    online_payment_enabled,
    created_at,
    updated_at
FROM app_about_settings;

-- ============================================
-- KULLANIM NOTU:
-- ============================================
-- Bu SQL dosyasını Supabase SQL Editor'de çalıştırın.
-- 
-- Admin panelinde "Ayarlar" bölümünde "Sipariş Onay Kodu" toggle'ı görünecektir.
-- 
-- Özellik Açıklaması:
-- - true: Kapıda ödeme siparişlerinde kullanıcıya SMS ile onay kodu gönderilir
-- - false: Onay kodu gönderilmez, sipariş direkt onaylanır
-- 
-- Etkilenen Ekranlar:
-- 1. lib/features/admin/screens/admin_dashboard_screen.dart (toggle ekranda görünür)
-- 2. lib/features/shop/screens/checkout_screen.dart (tek dükkan checkout)
-- 3. lib/features/market/screens/checkout_screen.dart (market checkout)
-- 4. lib/features/market/screens/multi_shop_checkout_screen.dart (çoklu dükkan checkout)
