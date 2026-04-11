-- ============================================================================
-- CizreApp - Posts ve Stories RLS Privacy Fix
-- ============================================================================
-- Bu SQL, posts ve stories tablolarını profile_is_public ve follows
-- tablosuna göre doğru şekilde filtreler.
--
-- Kurallar:
-- 1. Kendi postlarını/stories'lerini her zaman görür
-- 2. Herkese açık (profile_is_public=true) hesapların postlarını/stories'lerini herkes görür
-- 3. Gizli (profile_is_public=false) hesapların postlarını/stories'lerini sadece takipçiler görür
-- ============================================================================

-- 1. Önce mevcut politikaları temizle
DROP POLICY IF EXISTS "posts_select_all" ON public.posts;
DROP POLICY IF EXISTS "posts_select_policy" ON public.posts;
DROP POLICY IF EXISTS "posts_admin_select_all" ON public.posts;
DROP POLICY IF EXISTS "stories_select_policy" ON public.stories;
DROP POLICY IF EXISTS "stories_select_all" ON public.stories;

-- 2. Posts SELECT Policy - Privacy aware
-- Gizli hesapların gönderileri sadece takipçilere, açık hesapların gönderileri herkese açık
CREATE POLICY "posts_select_policy" ON public.posts
    FOR SELECT
    TO authenticated
    USING (
        -- Kendi postlarını her zaman gör
        user_id = auth.uid()
        OR
        -- Gönderinin sahibinin profilini kontrol et
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE profiles.id = posts.user_id
            AND (
                -- Herkese açık hesap (profile_is_public=true veya null varsayılan) - herkes görebilir
                (profiles.profile_is_public IS NULL OR profiles.profile_is_public = true)
                OR
                -- Gizli hesap ama takipçilerdensin (follows tablosunda olması kabul edilmiş demek)
                (
                    profiles.profile_is_public = false
                    AND EXISTS (
                        SELECT 1 FROM public.follows
                        WHERE follows.following_id = posts.user_id
                        AND follows.follower_id = auth.uid()
                    )
                )
            )
        )
    );

-- 3. Stories SELECT Policy - Privacy aware
-- Stories zaten 24 saat sonra expire oluyor
CREATE POLICY "stories_select_policy" ON public.stories
    FOR SELECT
    TO authenticated
    USING (
        -- Kendi story'sini her zaman gör
        user_id = auth.uid()
        OR
        -- Story'nin sahibinin profilini kontrol et
        EXISTS (
            SELECT 1 FROM public.profiles
            WHERE profiles.id = stories.user_id
            AND (
                -- Herkese açık hesap - herkes görebilir
                (profiles.profile_is_public IS NULL OR profiles.profile_is_public = true)
                OR
                -- Gizli hesap ama takipçilerdensin (follows tablosunda olması kabul edilmiş demek)
                (
                    profiles.profile_is_public = false
                    AND EXISTS (
                        SELECT 1 FROM public.follows
                        WHERE follows.following_id = stories.user_id
                        AND follows.follower_id = auth.uid()
                    )
                )
            )
        )
        -- Story hala aktif (24 saat içinde)
        AND stories.expires_at > NOW()
        AND stories.created_at > NOW() - INTERVAL '24 hours'
    );

-- 4. Index optimizasyonları - performans için
-- Bu indexler sorguları hızlandıracak
CREATE INDEX IF NOT EXISTS idx_posts_user_id_created ON public.posts(user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_stories_user_id_expires ON public.stories(user_id, expires_at DESC);
CREATE INDEX IF NOT EXISTS idx_follows_follower_following ON public.follows(follower_id, following_id);
CREATE INDEX IF NOT EXISTS idx_profiles_profile_is_public ON public.profiles(profile_is_public);

-- ============================================================================
-- AÇIKLAMA
-- ============================================================================
-- profiles.profile_is_public değerleri:
-- - true veya NULL: Herkes görebilir (takip şartı yok)
-- - false: Sadece takipçiler görebilir
--
-- follows tablosu: Sadece kabul edilmiş takipleri içerir
-- follow_requests tablosu: Pending/accepted/rejected durumlarını tutar
-- Kabul edilen takip istekleri otomatik olarak follows tablosuna eklenir
-- ============================================================================
