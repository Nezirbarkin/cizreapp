-- Comment mentions tablosuna eksik kolon ekleme

-- mentioned_by_user_id kolonunu ekle (eğer yoksa)
ALTER TABLE public.comment_mentions
  ADD COLUMN IF NOT EXISTS mentioned_by_user_id UUID REFERENCES public.profiles(id) ON DELETE CASCADE;

-- İndeks ekle
CREATE INDEX IF NOT EXISTS idx_comment_mentions_mentioned_by
  ON public.comment_mentions(mentioned_by_user_id);

-- Mevcut kayıtları güncelle (NULL olanlar için post_comments sahibini kullan)
UPDATE public.comment_mentions cm
SET mentioned_by_user_id = pc.user_id
FROM public.post_comments pc
WHERE cm.comment_id = pc.id
  AND cm.mentioned_by_user_id IS NULL;

-- Kontrol
-- SELECT * FROM comment_mentions LIMIT 5;
