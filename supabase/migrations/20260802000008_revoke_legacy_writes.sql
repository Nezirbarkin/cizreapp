-- 20260802000008_revoke_legacy_writes.sql
-- Tarih: 2026-08-02
-- Eski client-authoritative yüzeylerin tamamen kapatılması.
-- Bu migration geri alınamaz; geri almak için ayrı bir migration
-- oluşturulmalıdır (eski RPC'lerin yeniden GRANT'ı).

SET search_path = public, private;

-- ════════════════════════════════════════════════════════════════════════
-- public.create_order_with_items
-- (Önceki 20260728000004_order_fixes.sql tarafından yaratılmıştır)
-- ════════════════════════════════════════════════════════════════════════
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p
    JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'create_order_with_items'
  ) THEN
    REVOKE ALL ON FUNCTION public.create_order_with_items FROM PUBLIC, anon, authenticated;
    DROP FUNCTION IF EXISTS public.create_order_with_items;
  END IF;
END $$;

-- ════════════════════════════════════════════════════════════════════════
-- public.validate_coupon / public.use_coupon
-- (20260802000013 zaten private'e taşıdı, burada public olan varsa kapat)
-- ════════════════════════════════════════════════════════════════════════
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'validate_coupon'
  ) THEN
    REVOKE ALL ON FUNCTION public.validate_coupon FROM PUBLIC, anon, authenticated;
    DROP FUNCTION IF EXISTS public.validate_coupon;
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'use_coupon'
  ) THEN
    REVOKE ALL ON FUNCTION public.use_coupon FROM PUBLIC, anon, authenticated;
    DROP FUNCTION IF EXISTS public.use_coupon;
  END IF;
END $$;

-- ════════════════════════════════════════════════════════════════════════
-- public.complete_online_payment / public.atomic_finalize_payment_transaction
-- (private'e 20260802000009 ile taşındı)
-- ════════════════════════════════════════════════════════════════════════
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'complete_online_payment'
  ) THEN
    REVOKE ALL ON FUNCTION public.complete_online_payment FROM PUBLIC, anon, authenticated;
    DROP FUNCTION IF EXISTS public.complete_online_payment;
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'atomic_finalize_payment_transaction'
  ) THEN
    REVOKE ALL ON FUNCTION public.atomic_finalize_payment_transaction FROM PUBLIC, anon, authenticated;
    DROP FUNCTION IF EXISTS public.atomic_finalize_payment_transaction;
  END IF;
END $$;

-- ════════════════════════════════════════════════════════════════════════
-- public.claim_flash_sale / public.release_flash_sale
-- (private.flash_sale_reservations üzerinden)
-- ════════════════════════════════════════════════════════════════════════
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'claim_flash_sale'
  ) THEN
    REVOKE ALL ON FUNCTION public.claim_flash_sale FROM PUBLIC, anon, authenticated;
    DROP FUNCTION IF EXISTS public.claim_flash_sale;
  END IF;

  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'release_flash_sale'
  ) THEN
    REVOKE ALL ON FUNCTION public.release_flash_sale FROM PUBLIC, anon, authenticated;
    DROP FUNCTION IF EXISTS public.release_flash_sale;
  END IF;
END $$;

-- ════════════════════════════════════════════════════════════════════════
-- public.use_balance_for_order (eski edge function veya RPC)
-- ════════════════════════════════════════════════════════════════════════
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_proc p JOIN pg_namespace n ON p.pronamespace = n.oid
    WHERE n.nspname = 'public' AND p.proname = 'use_balance_for_order'
  ) THEN
    REVOKE ALL ON FUNCTION public.use_balance_for_order FROM PUBLIC, anon, authenticated;
    DROP FUNCTION IF EXISTS public.use_balance_for_order;
  END IF;
END $$;

-- ════════════════════════════════════════════════════════════════════════
-- orders / order_items doğrudan INSERT/DELETE yasağı (anon+authenticated)
-- authenticated sadece UPDATE durum (cancel_order RPC üzerinden) yapabilir
-- ════════════════════════════════════════════════════════════════════════
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'orders') THEN
    REVOKE INSERT, DELETE ON public.orders FROM anon;
    REVOKE INSERT ON public.orders FROM authenticated;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'order_items') THEN
    REVOKE INSERT, UPDATE, DELETE ON public.order_items FROM anon, authenticated;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'payment_transactions') THEN
    REVOKE INSERT, UPDATE, DELETE ON public.payment_transactions FROM anon, authenticated;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'coupon_usages') THEN
    REVOKE INSERT, UPDATE, DELETE ON public.coupon_usages FROM anon, authenticated;
  END IF;

  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_schema = 'public' AND table_name = 'user_balances') THEN
    REVOKE UPDATE ON public.user_balances FROM anon, authenticated;
  END IF;
END $$;
