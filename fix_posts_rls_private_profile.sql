-- ============================================================
-- GİZLİ PROFİL - POSTS RLS POLİCY FİX
-- ============================================================
-- Gizli hesapların gönderilerinin feed'de görünmemesi için RLS policy

-- 1. Mevcut posts RLS durumunu kontrol et
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE tablename = 'posts';

-- 2. Mevcut posts policy'lerini kontrol et
SELECT policyname, cmd, qual
FROM pg_policies 
WHERE tablename = 'posts';

-- 3. Posts SELECT policy güncelleme
-- Gizli hesapların gönderileri sadece takipçilerine görünür
DROP POLICY IF EXISTS "posts_select_policy" ON posts;

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
              AND f.status = 'accepted'
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

-- 5. Test - Şu anki kullanıcının görebileceği gönderiler
SELECT COUNT(*) as visible_posts
FROM posts
WHERE is_active = true;
