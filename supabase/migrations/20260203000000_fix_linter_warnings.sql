-- =====================================================
-- FIX: Supabase Linter Warnings
-- =====================================================
-- 1. Function search_path mutable uyarıları
-- 2. Multiple permissive policies - shops tablosu

-- =====================================================
-- 1. search_path Düzeltmeleri
-- =====================================================

-- auto_calculate_commission fonksiyonunu search_path ile yeniden oluştur
CREATE OR REPLACE FUNCTION public.auto_calculate_commission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_shop RECORD;
    v_commission_rate NUMERIC;
    v_commission_amount NUMERIC;
BEGIN
    -- Dükkan bilgisini al
    SELECT * INTO v_shop FROM public.shops WHERE id = NEW.shop_id;
    
    IF v_shop IS NULL THEN
        RETURN NEW;
    END IF;

    -- Komisyon oranını belirle
    v_commission_rate := COALESCE(v_shop.commission_rate, 10.0);
    
    -- Komisyon hesapla
    v_commission_amount := (NEW.subtotal * v_commission_rate) / 100;
    
    -- NEW değerlerini güncelle
    NEW.commission_rate := v_commission_rate;
    NEW.commission_amount := v_commission_amount;
    NEW.seller_earning := NEW.subtotal - v_commission_amount;
    
    RETURN NEW;
END;
$$;

-- update_shop_pending_payout fonksiyonunu search_path ile yeniden oluştur
CREATE OR REPLACE FUNCTION public.update_shop_pending_payout()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- Dükkanın pending_payout değerini güncelle
    UPDATE public.shops 
    SET pending_payout = COALESCE(pending_payout, 0) + COALESCE(NEW.seller_earning, 0)
    WHERE id = NEW.shop_id;
    
    RETURN NEW;
END;
$$;

-- =====================================================
-- 2. Shops Tablosu Çoklu Policy Düzeltmesi
-- =====================================================

-- Mevcut SELECT policylerini kaldır
DROP POLICY IF EXISTS shops_select_combined ON public.shops;
DROP POLICY IF EXISTS shops_select_policy ON public.shops;

-- Tek bir birleşik SELECT policy oluştur
CREATE POLICY shops_select_unified ON public.shops
    FOR SELECT
    TO authenticated, anon
    USING (true);

-- Mevcut UPDATE policylerini kaldır
DROP POLICY IF EXISTS shops_update_combined ON public.shops;
DROP POLICY IF EXISTS shops_update_unified ON public.shops;
DROP POLICY IF EXISTS shops_update_policy ON public.shops;

-- Tek bir birleşik UPDATE policy oluştur
CREATE POLICY shops_update_single ON public.shops
    FOR UPDATE
    TO authenticated
    USING (
        owner_id = (SELECT auth.uid())
        OR EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = (SELECT auth.uid())
            AND role = 'admin'
        )
    )
    WITH CHECK (
        owner_id = (SELECT auth.uid())
        OR EXISTS (
            SELECT 1 FROM public.profiles
            WHERE id = (SELECT auth.uid())
            AND role = 'admin'
        )
    );

-- =====================================================
-- Yorum: auth_leaked_password_protection
-- =====================================================
-- Bu ayar Supabase Dashboard > Authentication > Settings 
-- kısmından aktif edilmelidir. SQL ile değiştirilemez.

COMMENT ON FUNCTION public.auto_calculate_commission IS 'Sipariş komisyonunu otomatik hesaplar - search_path güvenli';
COMMENT ON FUNCTION public.update_shop_pending_payout IS 'Dükkan bekleyen ödemeyi günceller - search_path güvenli';
