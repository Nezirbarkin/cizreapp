-- =====================================================
-- Grup tabloları RLS politika temizliği ve optimizasyonu
-- 1. Duplicate (çift) politikaları temizle
-- 2. auth.uid() -> (select auth.uid()) optimizasyonu
-- =====================================================

-- =====================================================
-- 1. group_join_requests - TUM ESKI POLITIKALARI TEMIZLE
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

-- Yeni temiz politikalar (auth.uid() -> (select auth.uid()) ile)

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
-- 2. group_members - TUM ESKI POLITIKALARI TEMIZLE
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

-- Yeni temiz politikalar (auth.uid() -> (select auth.uid()) ile)

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
-- 3. Schema cache yenile
-- =====================================================
NOTIFY pgrst, 'reload schema';
