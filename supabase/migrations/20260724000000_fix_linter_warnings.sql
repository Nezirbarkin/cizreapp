-- ============================================================================
-- LINTER WARNINGS FIX (idempotent + deadlock-safe)
-- ============================================================================
-- Supabase linter uyarıları için düzeltme migration'ı. Tüm komutlar idempotent:
-- birden fazla kez çalıştırılabilir, hata vermez.
-- 1) function_search_path_mutable → SET search_path = public, pg_temp
-- 2) SECURITY DEFINER RPC'lerin EXECUTE yetkisi: anon revoke, authenticated grant
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) FUNCTION SEARCH PATH MUTABLE — idempotent
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc p
              JOIN pg_namespace n ON p.pronamespace = n.oid
              WHERE p.proname = 'trg_flash_sales_set_updated_at' AND n.nspname = 'public') THEN
    ALTER FUNCTION public.trg_flash_sales_set_updated_at()
      SET search_path = public, pg_temp;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p
              JOIN pg_namespace n ON p.pronamespace = n.oid
              WHERE p.proname = 'trg_live_sessions_set_updated_at' AND n.nspname = 'public') THEN
    ALTER FUNCTION public.trg_live_sessions_set_updated_at()
      SET search_path = public, pg_temp;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p
              JOIN pg_namespace n ON p.pronamespace = n.oid
              WHERE p.proname = 'set_updated_at' AND n.nspname = 'public') THEN
    ALTER FUNCTION public.set_updated_at()
      SET search_path = public, pg_temp;
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- 2) SECURITY DEFINER RPC: search_path + REVOKE anon + GRANT authenticated
-- ----------------------------------------------------------------------------
DO $$
BEGIN
  -- claim_flash_sale
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'claim_flash_sale') THEN
    ALTER FUNCTION public.claim_flash_sale(uuid, integer, uuid)
      SET search_path = public, pg_temp;
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.claim_flash_sale(uuid, integer, uuid) FROM anon';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.claim_flash_sale(uuid, integer, uuid) TO authenticated';
  END IF;

  -- release_flash_sale
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'release_flash_sale') THEN
    ALTER FUNCTION public.release_flash_sale(uuid, integer)
      SET search_path = public, pg_temp;
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.release_flash_sale(uuid, integer) FROM anon';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.release_flash_sale(uuid, integer) TO authenticated';
  END IF;

  -- notify_price_drops
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'notify_price_drops') THEN
    ALTER FUNCTION public.notify_price_drops()
      SET search_path = public, pg_temp;
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.notify_price_drops() FROM anon';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.notify_price_drops() TO authenticated';
  END IF;

  -- start_live_session
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'start_live_session') THEN
    ALTER FUNCTION public.start_live_session(uuid)
      SET search_path = public, pg_temp;
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.start_live_session(uuid) FROM anon';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.start_live_session(uuid) TO authenticated';
  END IF;

  -- end_live_session
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'end_live_session') THEN
    ALTER FUNCTION public.end_live_session(uuid)
      SET search_path = public, pg_temp;
    EXECUTE 'REVOKE EXECUTE ON FUNCTION public.end_live_session(uuid) FROM anon';
    EXECUTE 'GRANT EXECUTE ON FUNCTION public.end_live_session(uuid) TO authenticated';
  END IF;
END $$;

-- ----------------------------------------------------------------------------
-- TAMAMLANDI
-- ----------------------------------------------------------------------------
-- Bu script tamamen idempotent: birden fazla kez çalıştırılabilir.
-- Her adımda fonksiyon/tablonun varlığı kontrol edilir; yoksa sessizce geçer.
-- ============================================================================
