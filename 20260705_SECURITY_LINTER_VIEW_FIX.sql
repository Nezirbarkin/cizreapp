-- ============================================================================
-- 20260705_SECURITY_LINTER_VIEW_FIX.sql
-- ============================================================================
-- Amaç: Supabase Database Linter ERROR uyarısı: `security_definer_view`.
--       2 view SECURITY DEFINER olarak tanımlı → RLS bypass riski.
--
-- Düzeltme: PostgreSQL 15+ ile gelen `security_invoker = true` view attribute.
-- View'ı sorgulayan kullanıcının RLS politikaları uygulanır (view sahibinin
-- DEĞİL). Supabase PG sürümü 15+ destekliyor.
--
-- Etki:
-- - Admin hâlâ her şeyi görür (admin policy tüm kayıtları içerir)
-- - Normal kullanıcı sadece kendi kayıtlarını görür (RLS zaten filtreler)
-- - Mevcut view sorgu sonuçları admin için aynı kalır
--
-- Idempotent: ALTER VIEW ile her çalıştırmada uygulanır.
-- ============================================================================

BEGIN;

-- 1. Satıcı kazanç özeti
ALTER VIEW public.seller_earnings_summary
  SET (security_invoker = true);

-- 2. Bakiye işlem özeti
ALTER VIEW public.balance_transaction_summary
  SET (security_invoker = true);

COMMIT;

-- ============================================================================
-- DOĞRULAMA
-- SELECT viewname, pg_get_viewdef(oid) LIKE '%security_invoker%' AS has_invoker
-- FROM pg_views WHERE viewname IN
--   ('seller_earnings_summary','balance_transaction_summary')
--   AND schemaname = 'public';
-- VEYA pg_class.reloptions'ta kontrol:
-- SELECT c.relname, c.reloptions
-- FROM pg_class c JOIN pg_namespace n ON c.relnamespace = n.oid
-- WHERE n.nspname = 'public' AND c.relkind = 'v'
--   AND c.relname IN ('seller_earnings_summary','balance_transaction_summary');
-- reloptions kolonunda {security_invoker=true} görmeli.
-- ============================================================================