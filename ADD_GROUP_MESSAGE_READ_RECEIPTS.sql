-- ============================================
-- GRUP MESAJI OKUNDU BİLGİSİ (READ RECEIPTS) + REPLY TABLOSU
-- ============================================

-- 0) Önce var olan politikaları temizle (yeniden çalıştırma için)
DROP POLICY IF EXISTS "Grup üyeleri okuma bilgilerini görebilir" ON group_message_read_receipts;
DROP POLICY IF EXISTS "Kullanıcılar kendi okuma bilgilerini ekleyebilir" ON group_message_read_receipts;

-- 1) Reply desteği için group_messages tablosuna sütun ekle
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_name = 'group_messages' AND column_name = 'reply_to_id'
  ) THEN
    ALTER TABLE group_messages ADD COLUMN reply_to_id UUID REFERENCES group_messages(id) ON DELETE SET NULL;
  END IF;
END $$;

-- 1) Tablo oluştur
CREATE TABLE IF NOT EXISTS group_message_read_receipts (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  message_id UUID NOT NULL REFERENCES group_messages(id) ON DELETE CASCADE,
  group_id UUID NOT NULL REFERENCES groups(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  read_at TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  
  -- Her kullanıcı bir mesajı yalnızca bir kez okuyabilir
  UNIQUE(message_id, user_id)
);

-- 2) İndeksler
CREATE INDEX IF NOT EXISTS idx_gmrr_message_id ON group_message_read_receipts(message_id);
CREATE INDEX IF NOT EXISTS idx_gmrr_group_id ON group_message_read_receipts(group_id);
CREATE INDEX IF NOT EXISTS idx_gmrr_user_id ON group_message_read_receipts(user_id);
CREATE INDEX IF NOT EXISTS idx_gmrr_message_user ON group_message_read_receipts(message_id, user_id);

-- 3) RLS Politikaları
ALTER TABLE group_message_read_receipts ENABLE ROW LEVEL SECURITY;

-- Grup üyeleri okuma bilgilerini görebilir (performans optimized: select auth.uid())
CREATE POLICY "Grup üyeleri okuma bilgilerini görebilir"
  ON group_message_read_receipts
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM group_members
      WHERE group_members.group_id = group_message_read_receipts.group_id
        AND group_members.user_id = (select auth.uid())
    )
  );

-- Kullanıcılar kendi okuma bilgilerini ekleyebilir (performans optimized: select auth.uid())
CREATE POLICY "Kullanıcılar kendi okuma bilgilerini ekleyebilir"
  ON group_message_read_receipts
  FOR INSERT
  WITH CHECK (
    (select auth.uid()) = user_id
    AND EXISTS (
      SELECT 1 FROM group_members
      WHERE group_members.group_id = group_message_read_receipts.group_id
        AND group_members.user_id = (select auth.uid())
    )
  );

-- 4) Belirli bir mesajı okuyan kişileri getiren fonksiyon
CREATE OR REPLACE FUNCTION get_message_read_receipts(p_message_id UUID)
RETURNS TABLE (
  user_id UUID,
  full_name TEXT,
  username TEXT,
  avatar_url TEXT,
  read_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    r.user_id,
    p.full_name,
    p.username,
    p.avatar_url,
    r.read_at
  FROM group_message_read_receipts r
  LEFT JOIN profiles p ON p.id = r.user_id
  WHERE r.message_id = p_message_id
  ORDER BY r.read_at ASC;
END;
$$;

-- 5) Gruptaki mesajları okundu olarak işaretleyen fonksiyon (toplu, performans optimized)
CREATE OR REPLACE FUNCTION mark_group_messages_read_receipts(
  p_group_id UUID,
  p_last_message_id UUID DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_user_id UUID := auth.uid();
BEGIN
  -- Kullanıcının grup üyesi olduğunu kontrol et
  IF NOT EXISTS (
    SELECT 1 FROM group_members
    WHERE group_id = p_group_id AND user_id = v_user_id
  ) THEN
    RETURN;
  END IF;

  -- Henüz okunmamış tüm mesajları okundu olarak işaretle
  -- (gönderenin kendi mesajlarını hariç tut)
  INSERT INTO group_message_read_receipts (message_id, group_id, user_id)
  SELECT gm.id, gm.group_id, v_user_id
  FROM group_messages gm
  WHERE gm.group_id = p_group_id
    AND gm.sender_id != v_user_id
    AND NOT EXISTS (
      SELECT 1 FROM group_message_read_receipts r
      WHERE r.message_id = gm.id AND r.user_id = v_user_id
    )
  ON CONFLICT (message_id, user_id) DO NOTHING;

  -- Okunmamış sayısını sıfırla
  UPDATE group_members
  SET unread_count = 0
  WHERE group_id = p_group_id AND user_id = v_user_id;
END;
$$;

-- 6) Belirli bir mesajı kaç kişinin okuduğunu getiren fonksiyon
CREATE OR REPLACE FUNCTION get_message_read_count(p_message_id UUID)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count INTEGER;
BEGIN
  SELECT COUNT(*)::INTEGER INTO v_count
  FROM group_message_read_receipts
  WHERE message_id = p_message_id;
  
  RETURN v_count;
END;
$$;

-- 7) Realtime aktif et (idempotent)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime'
      AND schemaname = 'public'
      AND tablename = 'group_message_read_receipts'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE group_message_read_receipts;
  END IF;
END $$;

-- 8) Önce var olan fonksiyonu drop et (return type değişikliği için)
DROP FUNCTION IF EXISTS get_group_messages_with_read_count(UUID);

-- 9) Mesaj getirmek için optimized fonksiyon (read_by_count ile)
CREATE OR REPLACE FUNCTION get_group_messages_with_read_count(p_group_id UUID)
RETURNS TABLE (
  id UUID,
  group_id UUID,
  sender_id UUID,
  content TEXT,
  created_at TIMESTAMPTZ,
  updated_at TIMESTAMPTZ,
  reply_to_id UUID,
  read_by_count INTEGER,
  reply_to_content TEXT,
  reply_to_sender_name TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT
    gm.id,
    gm.group_id,
    gm.sender_id,
    gm.content,
    gm.created_at,
    gm.updated_at,
    gm.reply_to_id,
    COALESCE(rrr.read_count, 0)::INTEGER as read_by_count,
    COALESCE(rm.content, '') as reply_to_content,
    COALESCE(p.full_name, '') as reply_to_sender_name
  FROM group_messages gm
  LEFT JOIN (
    SELECT message_id, COUNT(*)::INTEGER as read_count
    FROM group_message_read_receipts
    GROUP BY message_id
  ) rrr ON rrr.message_id = gm.id
  LEFT JOIN group_messages rm ON rm.id = gm.reply_to_id
  LEFT JOIN profiles p ON p.id = rm.sender_id
  WHERE gm.group_id = p_group_id
  ORDER BY gm.created_at ASC;
END;
$$;
