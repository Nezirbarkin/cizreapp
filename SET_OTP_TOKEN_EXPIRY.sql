-- Supabase OTP Token Süresi Ayarı
-- Şifre sıfırlama ve email doğrulama linklerinin süresini uzatır
-- Varsayılan: 1 saat → 10 saat

-- Önce mevcut ayarları kontrol et
SELECT * FROM auth.config WHERE key = 'smtp';

-- Token süresini 10 saat (36000 saniye) olarak ayarla
-- Bu değer email'deki linkin ne kadar süreyle geçerli olacağını belirler
UPDATE auth.config 
SET value = jsonb_set(
    COALESCE(value::jsonb, '{}'::jsonb),
    '{smtp,max_age}',
    '36000'::jsonb
)
WHERE key = 'smtp';

-- Alternatif: Token süresini 1 gün (86400 saniye) olarak ayarla
-- UPDATE auth.config 
-- SET value = jsonb_set(
--     COALESCE(value::jsonb, '{}'::jsonb),
--     '{smtp,max_age}',
--     '86400'::jsonb
-- )
-- WHERE key = 'smtp';

-- Ayarları kontrol et
SELECT 
    value->>'smtp' as smtp_settings,
    value->'smtp'->>'max_age' as token_max_age_seconds
FROM auth.config 
WHERE key = 'smtp';

-- Not: max_age saniye cinsindendir
-- 36000 = 10 saat
-- 86400 = 24 saat (1 gün)
-- 604800 = 7 gün
