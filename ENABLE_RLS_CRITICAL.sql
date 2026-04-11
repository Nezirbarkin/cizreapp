-- ================================================
-- KRİTİK GÜVENLİK DÜZELTMELERİ - RLS Enable
-- ================================================
-- ERROR: policy_exists_rls_disabled, rls_disabled_in_public

-- ADIM 1: Conversations tablosu için RLS'i aktif et
ALTER TABLE public.conversations ENABLE ROW LEVEL SECURITY;

-- ADIM 2: Messages tablosu için RLS'i aktif et
ALTER TABLE public.messages ENABLE ROW LEVEL SECURITY;

-- ADIM 3: Shops_with_products_stats view'ını SECURITY DEFINER'den kaldır
-- Mevcut view tanımını al ve SECURITY INVOKER olarak yeniden oluştur

-- Önce mevcut view tanımını kontrol et
-- SELECT definition FROM pg_views WHERE viewname = 'shops_with_products_stats';

-- View'ı SECURITY INVOKER olarak yeniden oluştur (DEFINER yerine)
ALTER VIEW IF EXISTS public.shops_with_products_stats SET (security_invoker = true);

-- ADIM 4: Sonuçları kontrol et
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE schemaname = 'public' 
AND tablename IN ('conversations', 'messages');

SELECT viewname, viewowner, definition 
FROM pg_views 
WHERE viewname = 'shops_with_products_stats';

SELECT '✅ Critical security issues fixed!' as status;
SELECT '✅ RLS enabled for conversations and messages tables' as fix_1;
SELECT '✅ shops_with_products_stats view recreated without SECURITY DEFINER' as fix_2;
