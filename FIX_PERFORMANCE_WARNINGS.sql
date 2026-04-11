-- Supabase Linter Performans Uyarılarını Düzelt
-- 1. auth_rls_initplan: auth.uid() her satır için tekrar değerlendirilmesin
-- 2. multiple_permissive_policies: Çoklu permissive policy'leri birleştir

-- ============================================
-- 1. NOTIFICATION_PREFERENCES PERFORMANS İYİLEŞTİRMELERİ
-- ============================================

-- Eski policy'leri sil
DROP POLICY IF EXISTS "Users can insert their own notification preferences" ON public.notification_preferences;
DROP POLICY IF EXISTS "Users can update their own notification preferences" ON public.notification_preferences;
DROP POLICY IF EXISTS "Users can view their own notification preferences" ON public.notification_preferences;

-- Yeni optimize edilmiş policy'ler oluştur (SELECT ile sarmalanmış auth.uid())
CREATE POLICY "Users can insert their own notification preferences"
ON public.notification_preferences
FOR INSERT
TO authenticated
WITH CHECK (user_id = (SELECT auth.uid()));

CREATE POLICY "Users can update their own notification preferences"
ON public.notification_preferences
FOR UPDATE
TO authenticated
USING (user_id = (SELECT auth.uid()));

CREATE POLICY "Users can view their own notification preferences"
ON public.notification_preferences
FOR SELECT
TO authenticated
USING (user_id = (SELECT auth.uid()));

-- ============================================
-- 2. COMMENT_MENTIONS PERFORMANS İYİLEŞTİRMELERİ
-- ============================================

-- Eski policy'leri sil
DROP POLICY IF EXISTS "Comment author can delete their mentions" ON public.comment_mentions;
DROP POLICY IF EXISTS "Comment author can insert mentions" ON public.comment_mentions;
DROP POLICY IF EXISTS "Users can view their own mentions" ON public.comment_mentions;

-- Yeni optimize edilmiş policy'ler oluştur
CREATE POLICY "Comment author can delete their mentions"
ON public.comment_mentions
FOR DELETE
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM post_comments 
    WHERE post_comments.id = comment_mentions.comment_id 
    AND post_comments.user_id = (SELECT auth.uid())
  )
);

CREATE POLICY "Comment author can insert mentions"
ON public.comment_mentions
FOR INSERT
TO authenticated
WITH CHECK (
  EXISTS (
    SELECT 1 FROM post_comments 
    WHERE post_comments.id = comment_mentions.comment_id 
    AND post_comments.user_id = (SELECT auth.uid())
  )
);

CREATE POLICY "Users can view their own mentions"
ON public.comment_mentions
FOR SELECT
TO authenticated
USING (mentioned_user_id = (SELECT auth.uid()));

-- ============================================
-- 3. PROFILE_VIEWS PERFORMANS İYİLEŞTİRMELERİ
-- ============================================

-- Eski policy'leri sil (multiple permissive policies sorununu düzelt)
DROP POLICY IF EXISTS "Profile owners can view their profile views" ON public.profile_views;
DROP POLICY IF EXISTS "Users can view their own viewing history" ON public.profile_views;
DROP POLICY IF EXISTS "Users can view their profile views" ON public.profile_views;
DROP POLICY IF EXISTS "Users can insert their own profile views" ON public.profile_views;

-- INSERT policy - optimize edilmiş
CREATE POLICY "Users can insert their own profile views"
ON public.profile_views
FOR INSERT
TO authenticated
WITH CHECK (viewer_id = (SELECT auth.uid()));

-- SELECT policy - birleştirilmiş ve optimize edilmiş (multiple permissive policies yerine tek policy)
CREATE POLICY "Users can view profile views"
ON public.profile_views
FOR SELECT
TO authenticated
USING (
  profile_id = (SELECT auth.uid()) OR viewer_id = (SELECT auth.uid())
);

-- ============================================
-- 4. POST_VIEWS PERFORMANS İYİLEŞTİRMELERİ
-- ============================================

-- Eski policy'leri sil (multiple permissive policies sorununu düzelt)
DROP POLICY IF EXISTS "Post owners can view their post views" ON public.post_views;
DROP POLICY IF EXISTS "Users can view their own viewing history" ON public.post_views;
DROP POLICY IF EXISTS "Users can insert their own post views" ON public.post_views;

-- INSERT policy - optimize edilmiş
CREATE POLICY "Users can insert their own post views"
ON public.post_views
FOR INSERT
TO authenticated
WITH CHECK (viewer_id = (SELECT auth.uid()));

-- SELECT policy - birleştirilmiş ve optimize edilmiş (multiple permissive policies yerine tek policy)
CREATE POLICY "Users can view post views"
ON public.post_views
FOR SELECT
TO authenticated
USING (
  EXISTS (
    SELECT 1 FROM posts 
    WHERE posts.id = post_views.post_id 
    AND posts.user_id = (SELECT auth.uid())
  ) OR viewer_id = (SELECT auth.uid())
);

-- ============================================
-- NOTLAR
-- ============================================
-- 1. auth_rls_initplan düzeltmesi:
--    auth.uid() → (SELECT auth.uid()) ile sarmalandı
--    Bu, auth.uid()'nin sadece bir kez değerlendirilmesini sağlar
--
-- 2. multiple_permissive_policies düzeltmesi:
--    Birden fazla SELECT policy tek bir policy'de OR ile birleştirildi
--    Bu, performansı önemli ölçüde iyileştirir
--
-- 3. Her iki düzeltme de güvenlik seviyesini korurken performansı artırır
