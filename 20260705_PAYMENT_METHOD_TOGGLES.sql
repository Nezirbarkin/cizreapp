-- ============================================================================
-- 20260705_PAYMENT_METHOD_TOGGLES.sql
-- ============================================================================
-- Amaç: Admin panelden SIPARIŞ ödeme yöntemlerinin aktif/pasif yapılabilmesi.
--       (Kapıda Nakit / Kapıda Kart / Online / Bakiye ile Ödeme)
--
-- DİKKAT — bu migration idempotenttir (birden fazla kez çalıştırılabilir).
-- VAR OLAN YAPIYA DOKUNMAZ. Yalnızca 3 yeni boolean kolon ekler.
--
-- Arka plan (PROJE_HAVIZA_SCHEMA §2.10 ile uyumlu):
-- - card_topup_enabled       → BAKİYE YÜKLEMEDE kredi/banka kartı (zaten var)
-- - balance_enabled          → BAKİYE SİSTEMİ master (zaten var)
-- - online_payment_enabled   → Online ödeme master (zaten var) — bu kolon
--                               siparişlerde online ödeme için de kullanılır
--                               (tek gerçek kaynak prensibi; yineleme yok).
-- - global_orders_enabled    → Tüm sipariş alma (zaten var)
--
-- Bu migration EK olarak sipariş ödeme yöntemi toggle'larını ekler:
-- - order_cod_enabled            → Kapıda Nakit      (PaymentMethod.cash)
-- - order_card_on_delivery_enabled → Kapıda Kart     (PaymentMethod.cardOnDelivery)
-- - order_balance_enabled        → Bakiye ile Ödeme  (PaymentMethod.balance)
--   (online için online_payment_enabled kullanılır, yeni kolon eklenmez)
--
-- Flutter tarafında checkout ekranları bu kolonları yalnızca SELECT eder;
-- RadioListTile görünürlüğü buradan filtrelenir. Sipariş/ödeme akışı
-- (iyzico, bakiye düşümü, komisyon trigger'ları) DOKUNULMAZ.
--
-- Geriye dönük uyumluluk:
-- - Yeni kolonlar NOT NULL DEFAULT TRUE → mevcut davranış değişmez.
-- - Mevcut RLS politikası dokunulmaz (admin UPDATE zaten var, anon/auth SELECT var).
-- - Eski client + yeni DB → eski davranış (tüm yöntemler görünür) devam eder.
-- - Yeni client + eski DB (migration yok) → Dart ?? true → tüm yöntemler görünür.
-- - pgrst reload çağrılır → PostgREST şema cache yenilenir (PGRST204 önlemi).
-- ============================================================================

BEGIN;

-- 1. Kapıda Nakit (cash) toggle
ALTER TABLE public.app_about_settings
  ADD COLUMN IF NOT EXISTS order_cod_enabled BOOLEAN NOT NULL DEFAULT TRUE;

-- 2. Kapıda Kart (card_on_delivery / cardOnDelivery) toggle
ALTER TABLE public.app_about_settings
  ADD COLUMN IF NOT EXISTS order_card_on_delivery_enabled BOOLEAN NOT NULL DEFAULT TRUE;

-- 3. Bakiye ile ödeme (balance) toggle
--    NOT: balance_enabled (bakiye SİSTEMİNİN master anahtarı) ayrıdır; bu kolon
--    yalnızca sipariş ödeme yöntemi olarak "bakiye ile öde" seçeneğini kontrol eder.
ALTER TABLE public.app_about_settings
  ADD COLUMN IF NOT EXISTS order_balance_enabled BOOLEAN NOT NULL DEFAULT TRUE;

-- 4. Kolon yorumları (dokümantasyon)
COMMENT ON COLUMN public.app_about_settings.order_cod_enabled
  IS 'Siparişlerde Kapıda Nakit ödeme yöntemi admin tarafından aktif mi? (true=aktif, varsayılan)';

COMMENT ON COLUMN public.app_about_settings.order_card_on_delivery_enabled
  IS 'Siparişlerde Kapıda Kart (POS ile) ödeme yöntemi admin tarafından aktif mi? (true=aktif, varsayılan)';

COMMENT ON COLUMN public.app_about_settings.order_balance_enabled
  IS 'Siparişlerde Bakiye ile Ödeme yöntemi admin tarafından aktif mi? (true=aktif, varsayılan). Bakiye SİSTEMİNİ tamamen kapatmak için balance_enabled kullanılır.';

-- 5. Mevcut satırı default değerlerle garantiye al (NOT NULL DEFAULT eklendiği için
--    otomatik dolar, ama yine de idempotent UPDATE).
UPDATE public.app_about_settings
SET
  order_cod_enabled              = COALESCE(order_cod_enabled, TRUE),
  order_card_on_delivery_enabled = COALESCE(order_card_on_delivery_enabled, TRUE),
  order_balance_enabled          = COALESCE(order_balance_enabled, TRUE)
WHERE id IS NOT NULL;

-- 6. PostgREST şema cache'ini yenile (yeni kolonlar sorgulanabilsin)
NOTIFY pgrst, 'reload schema';

COMMIT;

-- ============================================================================
-- DOĞRULAMA (manuel çalıştırılabilir, hata üretmez — yalnızca info)
-- ============================================================================
-- SELECT column_name, data_type, column_default, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema = 'public'
--   AND table_name = 'app_about_settings'
--   AND column_name IN ('order_cod_enabled', 'order_card_on_delivery_enabled',
--                       'order_balance_enabled', 'online_payment_enabled',
--                       'card_topup_enabled', 'balance_enabled');
-- ============================================================================