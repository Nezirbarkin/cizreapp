-- Story timestamp timezone kontrolü ve düzeltme

-- 1. Mevcut timezone ayarını kontrol et
SHOW timezone;

-- 2. Son eklenen story'nin timestamp değerlerini görüntüle
SELECT 
    id,
    user_id,
    media_type,
    created_at,
    expires_at,
    -- Şu anki zaman
    NOW() as su_an,
    -- Kaç saat kaldı/kaldı mı?
    EXTRACT(EPOCH FROM (expires_at - NOW()))/3600 as kalan_saat,
    CASE 
        WHEN expires_at > NOW() THEN '✅ AKTİF'
        ELSE '❌ SÜRESİ DOLMUŞ'
    END as durum
FROM stories
ORDER BY created_at DESC
LIMIT 5;

-- 3. Eğer timezone sorunu varsa tüm story'leri UTC olarak düzelt
-- DİKKAT: Bu sorgu sadece test amaçlıdır, production'da dikkatli kullanın
/*
UPDATE stories
SET 
    created_at = created_at AT TIME ZONE 'UTC' AT TIME ZONE 'Europe/Istanbul',
    expires_at = expires_at AT TIME ZONE 'UTC' AT TIME ZONE 'Europe/Istanbul'
WHERE true;
*/

-- 4. Story tablosunun timezone kolon tiplerini kontrol et
SELECT 
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns
WHERE table_name = 'stories'
    AND column_name IN ('created_at', 'expires_at');

-- 5. Test için yeni bir story ekleyip kontrol et (manuel)
/*
INSERT INTO stories (user_id, image_url, media_type, views_count, created_at, expires_at)
VALUES (
    'TEST_USER_ID',
    'https://test.com/test.jpg',
    'image',
    0,
    NOW() AT TIME ZONE 'UTC',
    (NOW() AT TIME ZONE 'UTC') + INTERVAL '24 hours'
)
RETURNING *;
*/

-- 6. Timestamp karşılaştırma testi
SELECT 
    NOW() as local_now,
    NOW() AT TIME ZONE 'UTC' as utc_now,
    created_at,
    expires_at,
    -- Local time ile karşılaştırma
    expires_at > NOW() as local_check,
    -- UTC ile karşılaştırma
    expires_at > (NOW() AT TIME ZONE 'UTC') as utc_check
FROM stories
ORDER BY created_at DESC
LIMIT 3;
