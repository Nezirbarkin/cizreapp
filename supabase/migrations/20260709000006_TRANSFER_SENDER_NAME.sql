-- ============================================================================
-- 20260709000006_TRANSFER_SENDER_NAME.sql
-- ============================================================================
-- Amaç: Havale/EFT bildirimine "gönderen ad soyad" alanı eklemek.
--       Bir kullanıcı başkasının (eş, şirket, aile) hesabından havale yapabilir;
--       admin onaylarken havaleyi KİMİN yaptığını görmek ister.
--       Kullanıcı bildirimi gönderirken bu alanı zorunlu girer; admin panelinde
--       kart üzerinde "Gönderen" satırı olarak belirgin gösterilir.
--
-- Idempotent: ADD COLUMN IF NOT EXISTS. Eski kayıtlar için nullable bırakılır;
-- UI'da null ise "Belirtilmemiş" gösterilir.
-- ============================================================================

BEGIN;

-- 1. Yeni kolon: gönderen ad soyad
ALTER TABLE public.transfer_confirmations
  ADD COLUMN IF NOT EXISTS sender_full_name TEXT;

-- 2. NOT NULL kısıtı koymuyoruz: eski pending kayıtlar için geriye dönük uyum.
--    UI'da yeni gönderimlerde zorunlu tutulur; mevcut NULL kayıtlarda
--    "Belirtilmemiş" gösterilir.

-- 3. PostgREST şema cache yenileme
NOTIFY pgrst, 'reload schema';

COMMIT;

-- ============================================================================
-- DOĞRULAMA
-- ============================================================================
-- SELECT column_name, data_type, is_nullable
-- FROM information_schema.columns
-- WHERE table_schema = 'public' AND table_name = 'transfer_confirmations'
--   AND column_name = 'sender_full_name';
-- ============================================================================