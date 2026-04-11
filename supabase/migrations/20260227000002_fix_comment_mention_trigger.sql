-- ============================================================================
-- FIX COMMENT MENTION TRIGGER
-- mentioned_user_id sütunu olmadığı için trigger'ı kaldır
-- ============================================================================

-- Trigger'ları kaldır (comment_mentions ve post_comments her ikisinden de)
DROP TRIGGER IF EXISTS notify_comment_mention_trigger ON public.comment_mentions;
DROP TRIGGER IF EXISTS notify_comment_mention_trigger ON public.post_comments;

-- Fonksiyonu CASCADE ile kaldır (bağımlı trigger'ları da siler)
DROP FUNCTION IF EXISTS public.notify_comment_mention() CASCADE;

SELECT '✅ Comment mention trigger ve fonksiyonu kaldırıldı' AS result;
