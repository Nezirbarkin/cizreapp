-- ============================================================================
-- 20260705_TRANSFER_CONFIRMATIONS_FK_FIX.sql
-- ============================================================================
-- Amaç: TransferService.getPendingConfirmations() PGRST200 hatası veriyor:
--   "Could not find a relationship between 'transfer_confirmations' and
--    'profiles' ... using the hint 'transfer_confirmations_user_id_fkey'"
--
-- Sebep: 20260705_TRANSFER_CONFIRMATIONS.sql içinde user_id kolonu
--   `REFERENCES auth.users(id)` olarak tanımlandı. Projedeki diğer tüm
--   tablolar (orders.user_id -> profiles.id gibi) profiles'a referans verir,
--   PostgREST embedding de bunu bekler. auth.users hedefli FK ile profiles
--   join'i PostgREST şema cache'inde bulunamıyor.
--
-- Düzeltme: FK'yi public.profiles(id)'e çevir (profiles.id zaten
-- auth.users(id)'e 1:1 referans veriyor, veri kaybı/uyumsuzluk riski yok).
--
-- Idempotent: DROP CONSTRAINT IF EXISTS + yeniden ekleme.
-- ============================================================================

BEGIN;

ALTER TABLE public.transfer_confirmations
  DROP CONSTRAINT IF EXISTS transfer_confirmations_user_id_fkey;

ALTER TABLE public.transfer_confirmations
  ADD CONSTRAINT transfer_confirmations_user_id_fkey
  FOREIGN KEY (user_id) REFERENCES public.profiles(id) ON DELETE CASCADE;

NOTIFY pgrst, 'reload schema';

COMMIT;

-- ============================================================================
-- DOĞRULAMA
-- SELECT conname, confrelid::regclass
-- FROM pg_constraint
-- WHERE conname = 'transfer_confirmations_user_id_fkey';
-- confrelid 'profiles' olmalı (auth.users değil).
-- ============================================================================
