-- ============================================================
-- APP'TEKİ AUTH.UID() KONTROLÜ
-- ============================================================
-- App'te RLS hatası alıyorsunuz ama manuel INSERT çalışıyor.
-- Bu, app'teki auth.uid() ile SQL Editor'daki auth.uid() farklı olabilir.

-- 1. Şu anki auth session kontrolü
SELECT 
    auth.uid() as current_user_id,
    auth.role() as current_role,
    auth.jwt() as jwt_token;

-- 2. Bu user'ın notifications tablosuna INSERT yapabiliyor mu?
-- (SQL Editor'da çalışırken authenticated role ile çalışıyorsunuz)
-- App'te ise farklı bir auth context olabilir.

-- 3. Tüm notifications kayıtlarını kontrol edelim
SELECT id, user_id, type, title, created_at
FROM notifications
WHERE user_id = '70ab05f6-6aeb-4d32-810e-f3955c300f12'
ORDER BY created_at DESC
LIMIT 5;

-- 4. RLS'in açık olduğunu doğrulayalım
SELECT tablename, rowsecurity 
FROM pg_tables 
WHERE tablename = 'notifications';
