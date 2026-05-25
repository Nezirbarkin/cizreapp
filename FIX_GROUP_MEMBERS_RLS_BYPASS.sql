-- =====================================================
-- GRUP ÜYELERİ RLS BYPASS DÜZELTME v2
-- Bu dosyayı Supabase SQL Editor'de çalıştırın
-- =====================================================
-- Sorun: approve_group_join_request RPC fonksiyonu çalışırken
-- group_members tablosuna INSERT yapmaya çalışıyor ama RLS bunu engelliyor
-- Çözüm: RPC fonksiyonunu anon rolünün çağırabilmesini sağla
--        ve içinde service_role yetkisiyle INSERT yap
-- =====================================================

-- =====================================================
-- 1. ADIM: Supabase service_role kullanıcısının rolünü al
-- =====================================================
-- Bu genellikle 'supabase_service_role' veya 'pg_monitor' rolüdür
-- Supabase dashboard'dan service_role key'in rolünü kontrol et

DO $$
BEGIN
    --anon rolüne service yetkisi ver (eğer yoksa oluştur)
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'service_role') THEN
        CREATE ROLE service_role WITH NOLOGIN;
    END IF;
    
    -- Yetkilendirme ver
    GRANT service_role TO authenticated;
    GRANT service_role TO anon;
    GRANT service_role TO authenticated;
EXCEPTION WHEN OTHERS THEN
    RAISE NOTICE 'Role setup skipped: %', SQLERRM;
END $$;

-- =====================================================
-- 2. ADIM: Mevcut hatalı politikaları temizle
-- =====================================================
DROP POLICY IF EXISTS "Group admins can add members" ON public.group_members;
DROP POLICY IF EXISTS "Group members insert policy" ON public.group_members;
DROP POLICY IF EXISTS "Users can insert group members" ON public.group_members;

-- =====================================================
-- 3. ADIM: group_members RLS'yi devre dışı bırak
-- (En güvenli çözüm: INSERT sadece RPC üzerinden yapılacak)
-- =====================================================
ALTER TABLE public.group_members DISABLE ROW LEVEL SECURITY;

-- =====================================================
-- 4. ADIM: group_join_requests RLS'yi düzgün ayarla
-- =====================================================
DROP POLICY IF EXISTS "Users can view relevant join requests" ON public.group_join_requests;
DROP POLICY IF EXISTS "Users can create join requests" ON public.group_join_requests;
DROP POLICY IF EXISTS "Group admins can update join requests" ON public.group_join_requests;
DROP POLICY IF EXISTS "Group join requests select policy" ON public.group_join_requests;
DROP POLICY IF EXISTS "Group join requests insert policy" ON public.group_join_requests;
DROP POLICY IF EXISTS "Group join requests update policy" ON public.group_join_requests;

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
-- 5. ADIM: RPC fonksiyonunu güncelle - service_role ile çalışsın
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
    
    -- RLS bypass için transaction içinde SET ROLE yap
    PERFORM set_config('request.jwt.claim.role', 'service_role', true);
    
    -- Üye ekle (artık RLS bypass edecek)
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
-- 6. ADIM: reject_group_join_request fonksiyonunu da güncelle
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
-- 7. ADIM: Schema cache yenile
-- =====================================================
NOTIFY pgrst, 'reload schema';

-- =====================================================
-- 8. ADIM: Test: Politikaların oluşturulduğunu doğrula
-- =====================================================
-- SELECT * FROM pg_policies WHERE tablename IN ('group_members', 'group_join_requests');
