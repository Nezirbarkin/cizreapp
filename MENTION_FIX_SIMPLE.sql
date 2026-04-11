-- ============================================================================
-- SADECE MENTION BİLDİRİMİ DÜZELTMESİ
-- Supabase SQL Editor'da çalıştırın
-- ============================================================================

-- 1. notification_preferences tablosuna mentions sütunu ekle
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns 
    WHERE table_name = 'notification_preferences' 
    AND column_name = 'mentions'
  ) THEN
    ALTER TABLE notification_preferences 
    ADD COLUMN mentions BOOLEAN DEFAULT true;
  END IF;
END $$;

-- 2. Mevcut kullanıcılar için mention tercihini true yap
UPDATE notification_preferences
SET mentions = true
WHERE mentions IS NULL;

-- 3. Mention trigger'ını güncelle
CREATE OR REPLACE FUNCTION notify_comment_mention()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  commenter_username TEXT;
  commenter_name TEXT;
  comment_text TEXT;
  post_id_var UUID;
BEGIN
  -- Mention eden kullanıcı bilgilerini al
  SELECT username, full_name INTO commenter_username, commenter_name
  FROM profiles
  WHERE id = NEW.mentioned_by_user_id;
  
  -- Yorum metnini ve post_id'yi al
  SELECT content, post_id INTO comment_text, post_id_var
  FROM post_comments
  WHERE id = NEW.comment_id;
  
  -- Mention edilen kullanıcının mention tercihini kontrol et
  -- Eğer tercih kapalıysa bildirim gönderme
  IF EXISTS (
    SELECT 1 FROM notification_preferences 
    WHERE user_id = NEW.mentioned_user_id 
    AND mentions = false
  ) THEN
    RETURN NEW;
  END IF;
  
  -- Bildirim oluştur
  INSERT INTO notifications (
    user_id,
    type,
    title,
    content,
    actor_id,
    actor_name,
    entity_type,
    entity_id
  ) VALUES (
    NEW.mentioned_user_id,
    'mention',
    COALESCE(commenter_name, commenter_username, 'Bir kullanıcı'),
    'seni bir yorumda etiketledi: ' || LEFT(comment_text, 50) || CASE WHEN LENGTH(comment_text) > 50 THEN '...' ELSE '' END,
    NEW.mentioned_by_user_id,
    COALESCE(commenter_name, commenter_username, 'Bir kullanıcı'),
    'post',
    post_id_var
  );
  
  RETURN NEW;
END;
$$;

-- 4. Trigger'ı yeniden oluştur
DROP TRIGGER IF EXISTS comment_mention_notification_trigger ON comment_mentions;
CREATE TRIGGER comment_mention_notification_trigger
AFTER INSERT ON comment_mentions
FOR EACH ROW
EXECUTE FUNCTION notify_comment_mention();
