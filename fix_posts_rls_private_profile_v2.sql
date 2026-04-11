-- ============================================================
-- GİZLİ PROFİL - POSTS RLS POLİSY FİX (v2 - düzeltilmiş)
-- ============================================================
-- Gizli hesapların gönderilerinin feed'de görünmemesi için RLS policy

-- 1. Mevcut posts RLS durumunu kontrol et
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE tablename = 'posts';

-- 2. Mevcut posts policy'lerini gör
SELECT policyname, cmd, qual
FROM pg_policies 
WHERE tablename = 'posts';

-- 3. Posts SELECT policy güncelleme (status kolonu olmadan)
DROP POLICY IF EXISTS "posts_select_policy" ON posts;
DROP POLICY IF EXISTS "Enable read for all users" ON posts;
DROP POLICY IF EXISTS "Enable read for authenticated" ON posts;
DROP POLICY IF EXISTS "posts_select" ON posts;

CREATE POLICY "posts_select_policy" ON posts
FOR SELECT
TO authenticated
USING (
    is_active = true
    AND (
        -- Public hesapların gönderileri herkese görünür
        EXISTS (
            SELECT 1 FROM profiles p
            WHERE p.id = posts.user_id
              AND p.profile_is_public = true
        )
        OR
        -- Gizli hesapların gönderileri sadece takipçilerine görünür
        EXISTS (
            SELECT 1 FROM follows f
            WHERE f.following_id = posts.user_id
              AND f.follower_id = auth.uid()
        )
        OR
        -- Kendi gönderileri her zaman görünür
        posts.user_id = auth.uid()
    )
);

-- 4. Doğrulama - Kaç tane gizli hesap var?
SELECT COUNT(DISTINCT user_id) as private_users_with_posts
FROM posts p
WHERE EXISTS (
    SELECT 1 FROM profiles pr
    WHERE pr.id = p.user_id
      AND pr.profile_is_public = false
);

-- 5. Policy kontrolü
SELECT policyname, cmd, qual
FROM pg_policies 
WHERE tablename = 'posts';
