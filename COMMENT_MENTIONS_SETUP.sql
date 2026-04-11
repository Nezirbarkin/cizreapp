-- ============================================================================
-- COMMENT MENTIONS SETUP - Yorumlarda @kullaniciadi etiketleme
-- ============================================================================
-- Kullanım: Supabase SQL Editor'da çalıştırın
-- ============================================================================

-- Comment mentions tablosu oluştur
CREATE TABLE IF NOT EXISTS comment_mentions (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  comment_id UUID NOT NULL REFERENCES post_comments(id) ON DELETE CASCADE,
  mentioned_user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  mentioned_by_user_id UUID NOT NULL REFERENCES profiles(id) ON DELETE CASCADE,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  
  -- Aynı yorumda aynı kullanıcı birden fazla mention edilemez
  UNIQUE(comment_id, mentioned_user_id)
);

-- Index'ler
CREATE INDEX IF NOT EXISTS idx_comment_mentions_comment ON comment_mentions(comment_id);
CREATE INDEX IF NOT EXISTS idx_comment_mentions_mentioned_user ON comment_mentions(mentioned_user_id);
CREATE INDEX IF NOT EXISTS idx_comment_mentions_mentioned_by ON comment_mentions(mentioned_by_user_id);

-- RLS Politikaları
ALTER TABLE comment_mentions ENABLE ROW LEVEL SECURITY;

-- Önce mevcut policy'leri sil (varsa)
DROP POLICY IF EXISTS "Users can view their own mentions" ON comment_mentions;
DROP POLICY IF EXISTS "Comment author can insert mentions" ON comment_mentions;
DROP POLICY IF EXISTS "Comment author can delete their mentions" ON comment_mentions;

-- Herkes kendi mention'larını görebilir
CREATE POLICY "Users can view their own mentions"
  ON comment_mentions FOR SELECT
  USING (mentioned_user_id = auth.uid() OR mentioned_by_user_id = auth.uid());

-- Yorum sahibi mention ekleyebilir
CREATE POLICY "Comment author can insert mentions"
  ON comment_mentions FOR INSERT
  WITH CHECK (
    mentioned_by_user_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM post_comments
      WHERE id = comment_id AND user_id = auth.uid()
    )
  );

-- Yorum sahibi kendi mention'larını silebilir
CREATE POLICY "Comment author can delete their mentions"
  ON comment_mentions FOR DELETE
  USING (
    mentioned_by_user_id = auth.uid() AND
    EXISTS (
      SELECT 1 FROM post_comments
      WHERE id = comment_id AND user_id = auth.uid()
    )
  );

-- ============================================================================
-- TRIGGER: Mention edildiğinde bildirim gönder
-- ============================================================================

CREATE OR REPLACE FUNCTION notify_comment_mention()
RETURNS TRIGGER AS $$
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger oluştur
DROP TRIGGER IF EXISTS comment_mention_notification_trigger ON comment_mentions;
CREATE TRIGGER comment_mention_notification_trigger
AFTER INSERT ON comment_mentions
FOR EACH ROW
EXECUTE FUNCTION notify_comment_mention();

-- ============================================================================
-- NOTIFICATION TYPE ENUM'a 'mention' ekle
-- ============================================================================

-- Notification type enum'unu kontrol et ve mention yoksa ekle
DO $$ 
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_enum 
    WHERE enumlabel = 'mention' 
    AND enumtypid = 'notification_type'::regtype
  ) THEN
    ALTER TYPE notification_type ADD VALUE 'mention';
  END IF;
END $$;

-- ============================================================================
-- NOTIFICATION PREFERENCES'a mention tercihi ekle
-- ============================================================================

-- Notification preferences tablosuna mention column'u ekle (yoksa)
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

-- Mevcut kullanıcılar için mention tercihini true yap
UPDATE notification_preferences
SET mentions = true
WHERE mentions IS NULL;

COMMENT ON TABLE comment_mentions IS 'Yorumlarda @kullaniciadi mention (etiketleme) sistemi';
COMMENT ON COLUMN comment_mentions.comment_id IS 'Mention yapılan yorum ID';
COMMENT ON COLUMN comment_mentions.mentioned_user_id IS 'Mention edilen kullanıcı ID';
COMMENT ON COLUMN comment_mentions.mentioned_by_user_id IS 'Mention eden kullanıcı ID';
