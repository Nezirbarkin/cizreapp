-- Hikaye oluştururken foreign key hatası düzeltmesi
-- Kullanıcı profili yoksa önce oluştur

-- 1. Auth kullanıcıları profiles tablosuna ekle (eksik olanları)
INSERT INTO profiles (id, email, username, full_name, role, status, created_at, updated_at)
SELECT
    au.id,
    au.email,
    COALESCE(
        au.raw_user_meta_data->>'username',
        SPLIT_PART(au.email, '@', 1)
    ) as username,
    COALESCE(
        au.raw_user_meta_data->>'full_name',
        au.raw_user_meta_data->>'name',
        SPLIT_PART(au.email, '@', 1)
    ) as full_name,
    COALESCE(
        (au.raw_user_meta_data->>'role')::user_role,
        'customer'::user_role
    ) as role,
    'active'::user_status as status,
    au.created_at,
    NOW() as updated_at
FROM auth.users au
LEFT JOIN profiles p ON p.id = au.id
WHERE p.id IS NULL
ON CONFLICT (id) DO NOTHING;

-- 2. Username boş olanları düzelt
UPDATE profiles
SET username = SPLIT_PART(email, '@', 1)
WHERE username IS NULL OR username = '';

-- 3. Full name boş olanları düzelt
UPDATE profiles
SET full_name = username
WHERE full_name IS NULL OR full_name = '';

-- 4. Kontrol: Tüm profilleri listele
SELECT id, email, username, full_name, role, status
FROM profiles
ORDER BY created_at DESC;
