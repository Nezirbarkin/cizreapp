-- Fix Function Search Path Warnings
-- Supabase Linter uyarılarını düzelt: function_search_path_mutable
-- Fonksiyonlar varsa search_path ayarla, yoksa hata verme

DO $$
BEGIN
    -- calculate_order_commission fonksiyonunu düzelt (2 parametre: UUID, DECIMAL)
    BEGIN
        ALTER FUNCTION public.calculate_order_commission(UUID, DECIMAL) SET search_path = public;
        RAISE NOTICE 'calculate_order_commission(UUID, DECIMAL) fonksiyonu güncellendi';
    EXCEPTION WHEN undefined_function THEN
        RAISE NOTICE 'calculate_order_commission fonksiyonu henüz oluşturulmamış';
    END;

    -- get_admin_commission_report fonksiyonunu düzelt (2 parametre: TIMESTAMPTZ, TIMESTAMPTZ)
    BEGIN
        ALTER FUNCTION public.get_admin_commission_report(TIMESTAMPTZ, TIMESTAMPTZ) SET search_path = public;
        RAISE NOTICE 'get_admin_commission_report(TIMESTAMPTZ, TIMESTAMPTZ) fonksiyonu güncellendi';
    EXCEPTION WHEN undefined_function THEN
        RAISE NOTICE 'get_admin_commission_report fonksiyonu henüz oluşturulmamış';
    END;

    -- get_seller_commission_summary fonksiyonunu düzelt (3 parametre: UUID, TIMESTAMPTZ, TIMESTAMPTZ)
    BEGIN
        ALTER FUNCTION public.get_seller_commission_summary(UUID, TIMESTAMPTZ, TIMESTAMPTZ) SET search_path = public;
        RAISE NOTICE 'get_seller_commission_summary(UUID, TIMESTAMPTZ, TIMESTAMPTZ) fonksiyonu güncellendi';
    EXCEPTION WHEN undefined_function THEN
        RAISE NOTICE 'get_seller_commission_summary fonksiyonu henüz oluşturulmamış';
    END;
END $$;

-- Not: Bu migration, komisyon sistemi migration'ından (20260131000002_commission_system.sql) 
-- sonra çalışmalıdır. Fonksiyonlar oluşturulduktan sonra search_path ayarlanır.
