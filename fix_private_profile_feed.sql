-- ============================================================
-- GİZLİ PROFİL SORUNU ÇÖZÜMÜ
-- ============================================================
-- Sorun: Gizli hesapların (profile_is_public = false) gönderileri feed'de görünüyor
-- Çözüm: Gizli hesapların gönderilerini filtreleyen bir view oluştur

-- 1. Profil public durumunu kontrol et
SELECT id, username, profile_is_public
FROM profiles
WHERE id = '70ab05f6-6aeb-4d32-810e-f3955c300f12';

-- 2. Gizli hesapların gönderilerini gör
SELECT p.id, p.content, p.user_id, pr.username, pr.profile_is_public
FROM posts p
JOIN profiles pr ON p.user_id = pr.id
WHERE pr.profile_is_public = false
LIMIT 5;

-- 3. Çözüm: Public feed view oluştur (sadece public hesapların gönderileri)
CREATE OR REPLACE VIEW public_feed AS
SELECT 
    p.*,
    pr.username,
    pr.full_name,
    pr.avatar_url,
    pr.profile_is_public,
    pr.is_verified,
    pr.role,
    pr.fcm_token
FROM posts p
JOIN profiles pr ON p.user_id = pr.id
WHERE p.is_active = true 
  AND pr.profile_is_public = true;

-- 4. Gizli hesaplar için izleyenlerin görebileceği view
CREATE OR REPLACE VIEW follower_feed AS
SELECT 
    p.*,
    pr.username,
    pr.full_name,
    pr.avatar_url,
    pr.profile_is_public,
    pr.is_verified,
    pr.role
FROM posts p
JOIN profiles pr ON p.user_id = pr.id
WHERE p.is_active = true 
  AND (
    -- Public hesaplar herkese açık
    pr.profile_is_public = true
    OR
    -- Gizli hesaplar sadece takipçilerine açık
    EXISTS (
      SELECT 1 FROM follows f
      WHERE f.following_id = p.user_id
        AND f.follower_id = auth.uid()
        AND f.status = 'accepted'
    )
    OR
    -- Kendi gönderileri her zaman görünür
    p.user_id = auth.uid()
  );

-- 5. Mevcut gizli hesapları listele
SELECT 
    pr.id,
    pr.username,
    pr.profile_is_public,
    COUNT(p.id) as post_count
FROM profiles pr
LEFT JOIN posts p ON p.user_id = pr.id AND p.is_active = true
WHERE pr.profile_is_public = false
GROUP BY pr.id, pr.username, pr.profile_is_public;
