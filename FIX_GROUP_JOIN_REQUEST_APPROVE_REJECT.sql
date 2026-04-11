-- =====================================================
-- GRUP İSTEKLERİ ONAYLA/REDDET TAM DÜZELTME
-- Bu dosyayı Supabase SQL Editor'de çalıştırın
-- =====================================================
-- İçerik:
-- 1. Duplicate RLS politikalarını temizle
-- 2. Optimize edilmiş yeni politikalar oluştur
-- 3. RPC fonksiyonlarını SECURITY DEFINER ile oluştur
-- =====================================================

-- =====================================================
-- BÖLÜM 1: group_join_requests - TÜM ESKİ POLİTİKALARI TEMİZLE
-- =====================================================
DROP POLICY IF EXISTS "Group join requests select policy" ON public.group_join_requests;
DROP POLICY IF EXISTS "Group join requests insert policy" ON public.group_join_requests;
DROP POLICY IF EXISTS "Group join requests update policy" ON public.group_join_requests;
DROP POLICY IF EXISTS "Anyone can view pending group join requests" ON public.group_join_requests;
DROP POLICY IF EXISTS "Users can create join requests" ON public.group_join_requests;
DROP POLICY IF EXISTS "Group admins can update join requests" ON public.group_join_requests;
DROP POLICY IF EXISTS "Users can view relevant join requests" ON public.group_join_requests;
DROP POLICY IF EXISTS "Users can view their requests and admins can view all" ON public.group_join_requests;
DROP POLICY IF EXISTS "Admins can update join requests" ON public.group_join_requests;

-- RLS etkinleştir
ALTER TABLE public.group_join_requests ENABLE ROW LEVEL SECURITY;

-- SELECT: Kullanıcılar kendi isteklerini + grup adminleri grubun isteklerini görebilir
CREATE POLICY "Users can view relevant join requests" ON public.group_join_requests
    FOR SELECT USING (
        (select auth.uid()) = user_id
        OR EXISTS (
            SELECT 1 FROM public.group_members gm
            WHERE gm.group_id = group_join_requests.group_id
            AND gm.user_id = (select auth.uid())
            AND gm.role IN ('admin', 'owner', 'moderator')
        )
    );

-- INSERT: Herkes kendi adına istek oluşturabilir
CREATE POLICY "Users can create join requests" ON public.group_join_requests
    FOR INSERT WITH CHECK (
        (select auth.uid()) = user_id
    );

-- UPDATE: Grup adminleri istek durumunu güncelleyebilir
CREATE POLICY "Group admins can update join requests" ON public.group_join_requests
    FOR UPDATE USING (
        EXISTS (
            SELECT 1 FROM public.group_members gm
            WHERE gm.group_id = group_join_requests.group_id
            AND gm.user_id = (select auth.uid())
            AND gm.role IN ('admin', 'owner', 'moderator')
        )
    );

-- =====================================================
-- BÖLÜM 2: group_members - TÜM ESKİ POLİTİKALARI TEMİZLE
-- =====================================================
DROP POLICY IF EXISTS "Group members select policy" ON public.group_members;
DROP POLICY IF EXISTS "Group members insert policy" ON public.group_members;
DROP POLICY IF EXISTS "Group members delete policy" ON public.group_members;
DROP POLICY IF EXISTS "Anyone can view group members" ON public.group_members;
DROP POLICY IF EXISTS "Group admins can add members" ON public.group_members;
DROP POLICY IF EXISTS "Members can leave groups" ON public.group_members;
DROP POLICY IF EXISTS "Users can view group members" ON public.group_members;
DROP POLICY IF EXISTS "Users can insert group members" ON public.group_members;
DROP POLICY IF EXISTS "Admins and self can delete members" ON public.group_members;

-- RLS etkinleştir
ALTER TABLE public.group_members ENABLE ROW LEVEL SECURITY;

-- SELECT: Herkes grup üyelerini görebilir
CREATE POLICY "Anyone can view group members" ON public.group_members
    FOR SELECT USING (true);

-- INSERT: Adminler üye ekleyebilir
CREATE POLICY "Group admins can add members" ON public.group_members
    FOR INSERT WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.group_members gm
            WHERE gm.group_id = group_members.group_id
            AND gm.user_id = (select auth.uid())
            AND gm.role IN ('admin', 'owner', 'moderator')
        )
    );

-- DELETE: Üyeler kendileri ayrılabilir, adminler üye çıkarabilir
CREATE POLICY "Members can leave groups" ON public.group_members
    FOR DELETE USING (
        (select auth.uid()) = user_id
        OR EXISTS (
            SELECT 1 FROM public.group_members gm
            WHERE gm.group_id = group_members.group_id
            AND gm.user_id = (select auth.uid())
            AND gm.role IN ('admin', 'owner', 'moderator')
        )
    );

-- =====================================================
-- BÖLÜM 3: RPC - approve_group_join_request
-- =====================================================
CREATE OR REPLACE FUNCTION public.approve_group_join_request(
    request_id UUID
)
RETURNS BOOLEAN 
LANGUAGE plpgsql 
SECURITY DEFINER
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
-- BÖLÜM 4: RPC - reject_group_join_request
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
-- BÖLÜM 5: Schema cache yenile
-- =====================================================
NOTIFY pgrst, 'reload schema';
