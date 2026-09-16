-- ============================================================================
-- YORUM YANITLARI (reply threading) + yanıt bildirimi
-- ============================================================================
-- Şu ana kadar post_comments düz bir listeydi: kim kime yanıt verdi belli
-- değildi. parent_comment_id ile bir yorumun hangi yoruma yanıt olduğu
-- kaydediliyor; istemci bunu kullanarak yorumları ana yorum + altına
-- sıralanmış yanıtlar şeklinde gruplu gösteriyor.
--
-- Yanıt bildirimi ayrı bir olay: post sahibi zaten notify_post_comment ile
-- her yoruma bildirim alıyor, @mention notify_comment_mention ile ayrı
-- bildirim üretiyor. Burada eksik olan, "yorumuna yanıt verildi" bildirimi —
-- yanıtlanan yorumun SAHİBİ (post sahibi olmasa bile) haberdar olmalı.

ALTER TABLE public.post_comments
  ADD COLUMN IF NOT EXISTS parent_comment_id UUID
    REFERENCES public.post_comments(id) ON DELETE CASCADE;

CREATE INDEX IF NOT EXISTS idx_post_comments_parent_comment_id
  ON public.post_comments(parent_comment_id);

CREATE OR REPLACE FUNCTION public.notify_comment_reply()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.parent_comment_id IS NULL THEN
    RETURN NEW;
  END IF;

  -- Tek sorguda notification oluştur (notify_comment_mention ile aynı desen).
  -- Yanıtlanan yorumun sahibi kendisiyse (kendi yorumuna yanıt) bildirim yok.
  INSERT INTO public.notifications (
    user_id, type, title, content, actor_id, actor_name, actor_avatar, entity_id, created_at
  )
  SELECT
    parent.user_id,
    'comment_reply',
    COALESCE(p.full_name, p.username, 'Bir kullanıcı') || ' yorumuna yanıt verdi',
    COALESCE(LEFT(NEW.content, 100), 'Yanıt'),
    NEW.user_id,
    COALESCE(p.full_name, p.username, 'Bilinmeyen'),
    p.avatar_url,
    NEW.post_id,
    NOW()
  FROM public.post_comments parent
  JOIN public.profiles p ON p.id = NEW.user_id
  WHERE parent.id = NEW.parent_comment_id
    AND parent.user_id <> NEW.user_id;

  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'pg_temp';

DROP TRIGGER IF EXISTS notify_comment_reply_trigger ON public.post_comments;
CREATE TRIGGER notify_comment_reply_trigger
  AFTER INSERT ON public.post_comments
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_comment_reply();

SELECT '✅ post_comments.parent_comment_id + notify_comment_reply_trigger eklendi' AS result;
