-- Story tablosuna thumbnail_url alanı ekle
-- Video story'ler için thumbnail resim URL'ini tutar

-- 1. thumbnail_url kolonu ekle
ALTER TABLE stories
ADD COLUMN IF NOT EXISTS thumbnail_url TEXT;

-- 2. Index ekle (performans için)
CREATE INDEX IF NOT EXISTS idx_stories_thumbnail_url ON stories(thumbnail_url);

-- 3. Verification query
SELECT 
    column_name, 
    data_type, 
    is_nullable, 
    column_default
FROM information_schema.columns
WHERE table_name = 'stories' AND column_name = 'thumbnail_url';
