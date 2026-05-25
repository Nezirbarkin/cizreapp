-- =====================================================
-- GRUP ÜYELERİ RLS DÜZELTME - SON VERSİYON
-- Bu dosyayı Supabase SQL Editor'de çalıştırın
-- =====================================================
-- Sorun: approve_group_join_request fonksiyonu SECURITY DEFINER değil
--        ve group_members INSERT politikası sadece kullanıcının kendini eklemesine izin veriyor
-- Çözüm: 1. Fonksiyonu SECURITY DEFINER ile yeniden oluştur
--         2. INSERT politikasını adminlerin üye eklemesine izin verecek şekilde güncelle
-- =====================================================

-- =====================================================
-- 1. ADIM: approve_group_join_request fonksiyonunu SECURITY DEFINER ile yeniden oluştur
-- =====================================================
CREATE OR REPLACE FUNCTION public.approve_group_join_request(
    request_id UUID
)
RETURNS BOOLEAN 
LANGUAGE plpgsql 
SECURITY DEFINER  -- Bu önemli! RLS'yi bypass eder
SET search_path = public
AS $$
DECLARE
    v_group_id UUID;
    v_user_id UUID;
    v_status TEXT;
    v_requester_id UUID := auth.uid();
    v_is_admin BOOLEAN;
BEGIN
    -- İstek bilgilerini al
    SELECT group_id, user_id, status
    INTO v_group_id, v_user_id, v_status
    FROM public.group_join_requests
    WHERE id = request_id;
    
    IF v_group_id IS NULL THEN
        RETURN false;
    END IF;

    IF v_status != 'pending' THEN
        RETURN false;
    END IF;

    -- Çağıran kişinin bu grupta admin/moderator olduğunu doğrula
    SELECT EXISTS (
        SELECT 1 FROM public.group_members
        WHERE group_id = v_group_id
        AND user_id = v_requester_id
        AND role IN ('admin', 'owner', 'moderator')
    ) INTO v_is_admin;

    IF NOT v_is_admin THEN
        RETURN false;
    END IF;
    
    -- Üye ekle
    INSERT INTO public.group_members (group_id, user_id, role)
    VALUES (v_group_id, v_user_id, 'member')
    ON CONFLICT (group_id, user_id) DO NOTHING;
    
    -- İstek durumunu güncelle
    UPDATE public.group_join_requests
    SET status = 'approved', updated_at = now()
    WHERE id = request_id;
    
    -- Grup üye sayısını güncelle
    UPDATE public.groups
    SET member_count = (
        SELECT count(*) FROM public.group_members WHERE group_id = v_group_id
    )
    WHERE id = v_group_id;
    
    RETURN true;
END;
$$;

-- =====================================================
-- 2. ADIM: reject_group_join_request fonksiyonunu da güncelle
-- =====================================================
CREATE OR REPLACE FUNCTION public.reject_group_join_request(
    request_id UUID
)
RETURNS BOOLEAN 
LANGUAGE plpgsql 
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_group_id UUID;
    v_requester_id UUID := auth.uid();
    v_is_admin BOOLEAN;
BEGIN
    -- İstek bilgilerini al
    SELECT group_id INTO v_group_id
    FROM public.group_join_requests
    WHERE id = request_id AND status = 'pending';

    IF v_group_id IS NULL THEN
        RETURN false;
    END IF;

    -- Admin/moderator kontrolü
    SELECT EXISTS (
        SELECT 1 FROM public.group_members
        WHERE group_id = v_group_id
        AND user_id = v_requester_id
        AND role IN ('admin', 'owner', 'moderator')
    ) INTO v_is_admin;

    IF NOT v_is_admin THEN
        RETURN false;
    END IF;

    UPDATE public.group_join_requests
    SET status = 'rejected', updated_at = now()
    WHERE id = request_id AND status = 'pending';
    
    RETURN FOUND;
END;
$$;

-- =====================================================
-- 3. ADIM: group_members INSERT politikasını güncelle
-- Adminlerin başkalarını gruba eklemesine izin ver
-- =====================================================

-- Mevcut politikayı kaldır
DROP POLICY IF EXISTS "Unified group members insert" ON public.group_members;

-- Yeni politika: Kullanıcı kendini ekleyebilir VEYA admin üye ekleyebilir
CREATE POLICY "Admins can insert group members" ON public.group_members
    FOR INSERT WITH CHECK (
        -- Kullanıcı kendini ekliyor (açık gruplar için)
        (( SELECT auth.uid() AS uid) = user_id)
        OR
        -- Admin başkasını ekliyor
        (EXISTS (
            SELECT 1 FROM public.group_members gm
            WHERE gm.group_id = group_members.group_id
            AND gm.user_id = (SELECT auth.uid())
            AND gm.role IN ('admin', 'owner', 'moderator')
        ))
    );

-- =====================================================
-- 4. ADIM: Schema cache yenile
-- =====================================================
NOTIFY pgrst, 'reload schema';

-- =====================================================
-- 5. ADIM: Doğrulama sorguları
-- =====================================================
-- Fonksiyonun SECURITY DEFINER olup olmadığını kontrol et:
-- SELECT prosecdef, proname FROM pg_proc WHERE proname IN ('approve_group_join_request', 'reject_group_join_request');
-- 
-- INSERT politikasını kontrol et:
-- SELECT policyname, cmd, with_check FROM pg_policies WHERE tablename = 'group_members' AND cmd = 'INSERT';
