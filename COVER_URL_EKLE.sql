-- ⚠️ ÖNCELİKLİ! HEMEN ÇALIŞTIRIN!
-- Supabase Dashboard → SQL Editor'a kopyalayıp RUN yapın

-- 1. profiles tablosuna cover_url kolonu ekle
ALTER TABLE profiles 
ADD COLUMN IF NOT EXISTS cover_url TEXT;

-- 2. Kontrol et
SELECT column_name, data_type, table_name
FROM information_schema.columns 
WHERE table_name = 'profiles'
  AND column_name IN ('avatar_url', 'cover_url', 'location', 'website')
ORDER BY column_name;

-- 3. Schema cache yenile
NOTIFY pgrst, 'reload schema';

-- ========================================
-- BAŞARIYLA TAMAMLANDI!
-- Şimdi flutter run → Kapak değiştir → TEST!
-- ========================================
