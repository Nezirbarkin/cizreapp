-- ============================================================
-- GİZLİ PROFİL - STORIES RLS POLİSY FİX
-- ============================================================
-- Gizli hesapların hikayelerinin feed'de görünmemesi için RLS policy

-- 1. Mevcut stories RLS durumunu kontrol et
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE tablename = 'stories';

-- 2. Mevcut stories policy'lerini gör
SELECT policyname, cmd, qual
FROM pg_policies 
WHERE tablename = 'stories';

-- 3. Stories SELECT policy güncelleme
DROP POLICY IF EXISTS "stories_select_policy" ON stories;
DROP POLICY IF EXISTS "Enable read for all users" ON stories;
DROP POLICY IF EXISTS "Enable read for authenticated" ON stories;
DROP POLICY IF EXISTS "stories_select" ON stories;

CREATE POLICY "stories_select_policy" ON stories
FOR SELECT
TO authenticated
USING (
    expires_at > NOW()
    AND (
        -- Public hesapların hikayeleri herkese görünür
        EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id = stories.user_id
              AND p.profile_is_public = true
        )
        OR
        -- Gizli hesapların hikayeleri sadece takipçilerine görünür
        EXISTS (
            SELECT 1 FROM follows f
            WHERE f.following_id = stories.user_id
              AND f.follower_id = auth.uid()
        )
        OR
        -- Kendi hikayeleri her zaman görünür
        stories.user_id = auth.uid()
    )
);

-- 4. Policy kontrolü
SELECT policyname, cmd, qual
FROM pg_policies 
WHERE tablename = 'stories';
