-- ============================================================================
-- MENTION BİLDİRİM DÜZELTMESİ - Notification Preferences Kontrolü
-- ============================================================================
-- Kullanım: Supabase SQL Editor'da çalıştırın
-- ============================================================================

-- Önce eski trigger'ı sil
DROP TRIGGER IF EXISTS comment_mention_notification_trigger ON comment_mentions;

-- Yeni trigger - notification preferences kontrolü ile
CREATE OR REPLACE FUNCTION notify_comment_mention()
RETURNS TRIGGER AS $$
DECLARE
  commenter_username TEXT;
  commenter_name TEXT;
  comment_text TEXT;
  post_id_var UUID;
  mention_pref BOOLEAN;
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
  SELECT mentions INTO mention_pref
  FROM notification_preferences
  WHERE user_id = NEW.mentioned_user_id;
  
  -- Eğer tercih kapalıysa bildirim gönderme
  IF mention_pref = false THEN
    RETURN NEW;
  END IF;
  
  -- Eğer preference yoksa (NULL), varsayılan olarak açık kabul et
  IF mention_pref IS NULL THEN
    mention_pref := true;
  END IF;
  
  -- Bildirim oluştur
  IF mention_pref = true THEN
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
  END IF;
  
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger oluştur
CREATE TRIGGER comment_mention_notification_trigger
AFTER INSERT ON comment_mentions
FOR EACH ROW
EXECUTE FUNCTION notify_comment_mention();

-- ============================================================================
-- DEBUG: Mention prefences'in doğru ayarlandığını kontrol et
-- ============================================================================

-- Tüm kullanıcılar için mention tercihini true yap (eğer NULL ise)
UPDATE notification_preferences
SET mentions = true
WHERE mentions IS NULL;

-- Varsayılan preference oluşturma trigger'ı - mention ile
CREATE OR REPLACE FUNCTION create_default_notification_preferences()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO notification_preferences (user_id, likes_enabled, comments_enabled, followers_enabled, order_updates_enabled, order_ready_enabled, delivery_enabled, promotional_enabled, mentions)
  VALUES (NEW.id, true, true, true, true, true, true, false, true)
  ON CONFLICT (user_id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger'ı oluşturun (yoksa)
DROP TRIGGER IF EXISTS create_notification_preferences_trigger ON auth.users;
CREATE TRIGGER create_notification_preferences_trigger
AFTER INSERT ON auth.users
FOR EACH ROW
EXECUTE FUNCTION create_default_notification_preferences();

-- ============================================================================
-- DEBUG SORGULARI - Test için çalıştırabilirsiniz
-- ============================================================================

-- 1. Comment mentions tablosunu kontrol et
-- SELECT * FROM comment_mentions ORDER BY created_at DESC LIMIT 10;

-- 2. Mention bildirimlerini kontrol et
-- SELECT * FROM notifications WHERE type = 'mention' ORDER BY created_at DESC LIMIT 10;

-- 3. Notification preferences'leri kontrol et
-- SELECT user_id, mentions FROM notification_preferences WHERE mentions = false OR mentions IS NULL;

COMMENT ON FUNCTION notify_comment_mention() IS 'Yorum mention edildiğinde bildirim gönderir (notification preferences kontrolü ile)';
