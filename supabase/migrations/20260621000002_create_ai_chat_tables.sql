-- AI Chat tabloları oluştur

-- AI Konuşmaları tablosu
CREATE TABLE IF NOT EXISTS public.ai_conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  provider TEXT DEFAULT 'auto',
  model TEXT,
  title TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  archived_at TIMESTAMPTZ,
  message_count INTEGER DEFAULT 0
);

-- AI Mesajları tablosu
CREATE TABLE IF NOT EXISTS public.ai_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.ai_conversations(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
  content TEXT NOT NULL,
  provider TEXT,
  model TEXT,
  tokens INTEGER DEFAULT 0,
  attachments JSONB DEFAULT '[]',
  generated_images JSONB DEFAULT '[]',
  error TEXT,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Indexler
CREATE INDEX IF NOT EXISTS idx_ai_conversations_user_id ON public.ai_conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_ai_conversations_created_at ON public.ai_conversations(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_messages_conversation_id ON public.ai_messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_ai_messages_created_at ON public.ai_messages(created_at);

-- RLS Policies
ALTER TABLE public.ai_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_messages ENABLE ROW LEVEL SECURITY;

-- Kullanıcılar kendi sohbetlerini görebilir
DROP POLICY IF EXISTS "Users can view own ai conversations" ON public.ai_conversations;
CREATE POLICY "Users can view own ai conversations"
  ON public.ai_conversations
  FOR SELECT
  USING (auth.uid() = user_id);

-- Kullanıcılar yeni sohbet oluşturabilir
DROP POLICY IF EXISTS "Users can insert ai conversations" ON public.ai_conversations;
CREATE POLICY "Users can insert ai conversations"
  ON public.ai_conversations
  FOR INSERT
  WITH CHECK (auth.uid() = user_id);

-- Kullanıcılar kendi sohbetlerini güncelleyebilir
DROP POLICY IF EXISTS "Users can update own ai conversations" ON public.ai_conversations;
CREATE POLICY "Users can update own ai conversations"
  ON public.ai_conversations
  FOR UPDATE
  USING (auth.uid() = user_id);

-- Kullanıcılar kendi sohbetlerini silebilir
DROP POLICY IF EXISTS "Users can delete own ai conversations" ON public.ai_conversations;
CREATE POLICY "Users can delete own ai conversations"
  ON public.ai_conversations
  FOR DELETE
  USING (auth.uid() = user_id);

-- Kullanıcılar kendi mesajlarını görebilir
DROP POLICY IF EXISTS "Users can view own ai messages" ON public.ai_messages;
CREATE POLICY "Users can view own ai messages"
  ON public.ai_messages
  FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.ai_conversations
      WHERE id = conversation_id AND user_id = auth.uid()
    )
  );

-- Kullanıcılar mesaj ekleyebilir
DROP POLICY IF EXISTS "Users can insert ai messages" ON public.ai_messages;
CREATE POLICY "Users can insert ai messages"
  ON public.ai_messages
  FOR INSERT
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.ai_conversations
      WHERE id = conversation_id AND user_id = auth.uid()
    )
  );

-- AI Settings tablosu için
ALTER TABLE public.ai_settings ENABLE ROW LEVEL SECURITY;

-- Admin'ler AI ayarlarını yönetebilir
DROP POLICY IF EXISTS "Admins can manage ai settings" ON public.ai_settings;
CREATE POLICY "Admins can manage ai settings"
  ON public.ai_settings
  FOR ALL
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND role = 'admin'
    )
  );

-- Everyone can read AI settings (for checking if AI is enabled)
DROP POLICY IF EXISTS "Anyone can read ai settings" ON public.ai_settings;
CREATE POLICY "Anyone can read ai settings"
  ON public.ai_settings
  FOR SELECT
  USING (true);

-- AI konuşmaları için updated_at trigger'ı
CREATE OR REPLACE FUNCTION public.update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS update_ai_conversations_updated_at ON public.ai_conversations;
CREATE TRIGGER update_ai_conversations_updated_at
  BEFORE UPDATE ON public.ai_conversations
  FOR EACH ROW
  EXECUTE FUNCTION public.update_updated_at_column();
