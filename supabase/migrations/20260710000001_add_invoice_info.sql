-- ============================================================
-- Migration: Siparişlere Müşteri Fatura Bilgileri Ekleme
-- Tarih: 2026-07-10
-- Açıklama: profiles ve orders tablolarına fatura bilgileri alanları eklenir.
-- Geriye uyumlu: Tüm kolonlar NULLABLE.
-- ============================================================

-- ============================================================
-- 1. profiles tablosuna kayıtlı fatura bilgileri ekle
--    (tekrar kullanılabilir, müşteri bir kez girer, sonraki siparişlerde otomatik gelir)
-- ============================================================

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS invoice_type TEXT DEFAULT 'individual'
CHECK (invoice_type IN ('individual', 'corporate'));

ALTER TABLE profiles ADD COLUMN IF NOT EXISTS invoice_full_name TEXT;
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS invoice_tax_number TEXT;
-- T.C. kimlik no (bireysel fatura için)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS invoice_tc_no TEXT;
-- Vergi dairesi (kurumsal fatura için)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS invoice_tax_office TEXT;
-- Şirket adresi (kurumsal fatura için)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS invoice_address TEXT;
-- Fatura e-postası (opsiyonel)
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS invoice_email TEXT;
-- Kayıt tarihi
ALTER TABLE profiles ADD COLUMN IF NOT EXISTS invoice_saved_at TIMESTAMPTZ;

-- ============================================================
-- 2. orders tablosuna sipariş anındaki snapshot ekle
--    (siparişle birlikte donar, sonradan değiştirilemez)
-- ============================================================

ALTER TABLE orders ADD COLUMN IF NOT EXISTS invoice_type TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS invoice_full_name TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS invoice_tax_number TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS invoice_tc_no TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS invoice_tax_office TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS invoice_address TEXT;
ALTER TABLE orders ADD COLUMN IF NOT EXISTS invoice_email TEXT;

-- ============================================================
-- NOTLAR:
--
-- * RLS politikaları: Mevcut policies zaten user_id bazlı çalıştığı için
--   yeni kolonlar otomatik olarak korunur.
--
-- * Geriye uyumluluk: Tüm kolonlar NULLABLE olduğu için mevcut siparişler
--   ve profiller etkilenmez.
--
-- * Sipariş snapshot deseni: orders tablosundaki bilgiler sipariş anında
--   profiles'dan kopyalanır. Müşteri sonradan profilini güncellese bile
--   eski siparişlerdeki fatura bilgisi korunur.
--
-- * Fatura zorunluluğu: Bu migration fatura bilgisini zorunlu yapmaz.
--   Frontend'de opsiyonel olarak işlenir.
-- ============================================================

SELECT 'Fatura bilgileri migration''ı başarıyla tamamlandı!' AS status;
