-- Story tablosuna video desteği için media_type kolonu ekleme

-- 1. media_type kolonu ekle (varsayılan 'image')
ALTER TABLE stories
ADD COLUMN IF NOT EXISTS media_type VARCHAR(10) DEFAULT 'image' CHECK (media_type IN ('image', 'video'));

-- 2. Mevcut tüm kayıtları 'image' olarak işaretle
UPDATE stories
SET media_type = 'image'
WHERE media_type IS NULL;

-- 3. NOT NULL constraint ekle
ALTER TABLE stories
ALTER COLUMN media_type SET NOT NULL;

-- 4. Index ekle (performans için)
CREATE INDEX IF NOT EXISTS idx_stories_media_type ON stories(media_type);

-- Verification query
SELECT 
    column_name, 
    data_type, 
    is_nullable, 
    column_default
FROM information_schema.columns
WHERE table_name = 'stories'
ORDER BY ordinal_position;
