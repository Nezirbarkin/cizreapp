-- =====================================================
-- AI CHAT SYSTEM - GÜVENLİK DÜZELTMELERİ
-- =====================================================
-- search_path ve EXECUTE yetkisi düzeltmeleri
-- =====================================================

-- 1. search_path ayarla (security definer fonksiyonlar için)
-- Bu, SQL injection riskini önler

ALTER FUNCTION public.ai_on_message_insert() SET search_path = public;
ALTER FUNCTION public.ai_set_updated_at() SET search_path = public;
ALTER FUNCTION public.ai_increment_usage(UUID, INT, BOOLEAN) SET search_path = public;
ALTER FUNCTION public.ai_get_admin_stats(INT) SET search_path = public;
ALTER FUNCTION public.is_admin() SET search_path = public;

-- 2. anon rolünden EXECUTE yetkisini kaldır (sadece authenticated ve service_role çağırabilsin)
-- ai_increment_usage: sadece authenticated ve service_role çağırmalı
REVOKE EXECUTE ON FUNCTION public.ai_increment_usage(UUID, INT, BOOLEAN) FROM anon;
REVOKE EXECUTE ON FUNCTION public.ai_get_admin_stats(INT) FROM anon;
REVOKE EXECUTE ON FUNCTION public.is_admin() FROM anon;
REVOKE EXECUTE ON FUNCTION public.ai_on_message_insert() FROM anon;

-- ai_on_message_insert bir trigger fonksiyonu, doğrudan çağrılmamalı
-- ama yine de anon erişimini kaldıralım
REVOKE EXECUTE ON FUNCTION public.ai_set_updated_at() FROM anon;