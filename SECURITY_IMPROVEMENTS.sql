-- ====================================
-- SUPABASE GÜVENLİK İYİLEŞTİRMELERİ
-- Function search_path düzeltmeleri
-- ====================================

-- 1. Function'lara search_path ekle (Güvenlik için)
DO $$
BEGIN
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'update_profile_fields') THEN
    ALTER FUNCTION public.update_profile_fields() SET search_path = public, pg_temp;
  END IF;
  
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'update_cart_updated_at') THEN
    ALTER FUNCTION public.update_cart_updated_at() SET search_path = public, pg_temp;
  END IF;
  
  IF EXISTS (SELECT 1 FROM pg_proc WHERE proname = 'update_orders_updated_at') THEN
    ALTER FUNCTION public.update_orders_updated_at() SET search_path = public, pg_temp;
  END IF;
END $$;

-- ====================================
-- BAŞARILI!
-- ====================================
SELECT 'Güvenlik iyileştirmeleri tamamlandı!' as result;
