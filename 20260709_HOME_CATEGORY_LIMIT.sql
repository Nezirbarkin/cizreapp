-- =============================================================================
-- 20260709_HOME_CATEGORY_LIMIT.sql
-- =============================================================================
-- Amaç:
--   1) app_about_settings tablosuna `home_category_limit` (int) kolonu ekle.
--      Anasayfadaki kategori kartı sayısı admin panelinden ayarlanabilsin.
--      Varsayılan 4 (mevcut hardcoded değer).
--   2) balance_transactions tablosuna `balance_before` (numeric) ve
--      `balance_after` (numeric) kolonları ekle (idempotent).
--      Admin işlem geçmişi kartlarında işlem yapılan kişinin eski/yeni
--      bakiyesi gösterilsin.
--   3) Mevcut kayıtlar için geriye dönük değer yazılamaz; yeni işlemlerde
--      trigger / RPC tarafından doldurulmalı (admin-add-balance,
--      admin-deduct-balance edge functions + balance RPC'leri).
--
-- Etkilenen tablolar:
--   - public.app_about_settings
--   - public.balance_transactions
--
-- Idempotent: ADD COLUMN IF NOT EXISTS, ALTER TABLE IF EXISTS guard'ları.
-- Supabase PostgREST cache'i için sona `NOTIFY pgrst, 'reload schema'`.
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) home_category_limit: anasayfa kategori kartı sayısı
-- -----------------------------------------------------------------------------
ALTER TABLE public.app_about_settings
  ADD COLUMN IF NOT EXISTS home_category_limit INTEGER NOT NULL DEFAULT 4
    CHECK (home_category_limit >= 1 AND home_category_limit <= 20);

COMMENT ON COLUMN public.app_about_settings.home_category_limit IS
  'Anasayfa kategori kartları için görüntülenecek maksimum kategori sayısı. '
  'Aralık: 1-20. Varsayılan: 4 (eski hardcoded değer).';

-- -----------------------------------------------------------------------------
-- 2) balance_before / balance_after: işlem geçmişi kartları için
--    Eski bakiye: işlemden önceki bakiye (negatif işlemde düşülen miktarın
--    çıkarılmış hali). Yeni bakiye: işlemden sonraki bakiye.
-- -----------------------------------------------------------------------------
ALTER TABLE public.balance_transactions
  ADD COLUMN IF NOT EXISTS balance_before NUMERIC(12, 2);

ALTER TABLE public.balance_transactions
  ADD COLUMN IF NOT EXISTS balance_after NUMERIC(12, 2);

COMMENT ON COLUMN public.balance_transactions.balance_before IS
  'İşlem öncesi kullanıcı bakiyesi (TL). NULL = eski işlem / geriye dönük veri.';

COMMENT ON COLUMN public.balance_transactions.balance_after IS
  'İşlem sonrası kullanıcı bakiyesi (TL). NULL = eski işlem / geriye dönük veri.';

-- -----------------------------------------------------------------------------
-- 3) Şema cache'ini yenile (PostgREST yeni kolonları görsün)
-- -----------------------------------------------------------------------------
NOTIFY pgrst, 'reload schema';

COMMIT;