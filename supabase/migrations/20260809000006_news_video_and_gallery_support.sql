-- Haberler ve haberci paneli için tanıtım videosu + çoklu görsel desteği.
ALTER TABLE public.news
ADD COLUMN IF NOT EXISTS video_url TEXT;

COMMENT ON COLUMN public.news.video_url IS
  'Haberde gösterilecek isteğe bağlı tanıtım videosunun herkese açık URL adresi.';

-- Mevcut news-images bucket aynı zamanda haber videolarını da barındırır.
-- 100 MB sınırı istemci tarafındaki doğrulama ile de eşleşir.
UPDATE storage.buckets
SET file_size_limit = 104857600,
    allowed_mime_types = ARRAY[
      'image/jpeg',
      'image/png',
      'image/webp',
      'image/gif',
      'video/mp4',
      'video/quicktime',
      'video/webm'
    ]::text[]
WHERE id = 'news-images';

