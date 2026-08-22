-- AI Chat tabloları ve izinleri kontrol et/düzelt
-- NOT: Eğer tablolar yoksa oluşturur, varsa atlar

-- AI Konuşmaları tablosu (yoksa oluştur)
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_tables WHERE tablename = 'ai_conversations') THEN
    CREATE TABLE public.ai_conversations (
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
  END IF;
END $$;

-- AI Mesajları tablosu (yoksa oluştur)
DO $$
BEGIN
  IF NOT EXISTS (SELECT FROM pg_tables WHERE tablename = 'ai_messages') THEN
    CREATE TABLE public.ai_messages (
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
  END IF;
END $$;

-- Indexler
CREATE INDEX IF NOT EXISTS idx_ai_conversations_user_id ON public.ai_conversations(user_id);
CREATE INDEX IF NOT EXISTS idx_ai_conversations_created_at ON public.ai_conversations(created_at DESC);
CREATE INDEX IF NOT EXISTS idx_ai_messages_conversation_id ON public.ai_messages(conversation_id);
CREATE INDEX IF NOT EXISTS idx_ai_messages_created_at ON public.ai_messages(created_at);

-- RLS etkinleştir
ALTER TABLE public.ai_conversations ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_messages ENABLE ROW LEVEL SECURITY;

-- Policies (varsa yeniden oluştur)
DROP POLICY IF EXISTS "Users can view own ai conversations" ON public.ai_conversations;
DROP POLICY IF EXISTS "Users can insert ai conversations" ON public.ai_conversations;
DROP POLICY IF EXISTS "Users can update own ai conversations" ON public.ai_conversations;
DROP POLICY IF EXISTS "Users can delete own ai conversations" ON public.ai_conversations;
DROP POLICY IF EXISTS "Users can view own ai messages" ON public.ai_messages;
DROP POLICY IF EXISTS "Users can insert ai messages" ON public.ai_messages;

CREATE POLICY "Users can view own ai conversations" ON public.ai_conversations FOR SELECT USING (auth.uid() = user_id);
CREATE POLICY "Users can insert ai conversations" ON public.ai_conversations FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY "Users can update own ai conversations" ON public.ai_conversations FOR UPDATE USING (auth.uid() = user_id);
CREATE POLICY "Users can delete own ai conversations" ON public.ai_conversations FOR DELETE USING (auth.uid() = user_id);
CREATE POLICY "Users can view own ai messages" ON public.ai_messages FOR SELECT USING (EXISTS (SELECT 1 FROM public.ai_conversations WHERE id = conversation_id AND user_id = auth.uid()));
CREATE POLICY "Users can insert ai messages" ON public.ai_messages FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM public.ai_conversations WHERE id = conversation_id AND user_id = auth.uid()));

-- AI Settings RLS
ALTER TABLE public.ai_settings ENABLE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS "Admins can manage ai settings" ON public.ai_settings;
DROP POLICY IF EXISTS "Anyone can read ai settings" ON public.ai_settings;
CREATE POLICY "Admins can manage ai settings" ON public.ai_settings FOR ALL USING (EXISTS (SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'admin'));
CREATE POLICY "Anyone can read ai settings" ON public.ai_settings FOR SELECT USING (true);

-- AI Settings için API anahtarı kolonları (yoksa ekle)
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS gemini_api_key TEXT;
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS groq_api_key TEXT;
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS openrouter_api_key TEXT;
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS openai_api_key TEXT;
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS gemini_key_set BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS groq_key_set BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS openrouter_key_set BOOLEAN NOT NULL DEFAULT false;
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS openai_key_set BOOLEAN NOT NULL DEFAULT false;

-- Yeni model kolonları
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS groq_text_model TEXT DEFAULT 'llama-3.3-70b-versatile';
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS groq_vision_model TEXT DEFAULT 'llama-3.2-90b-vision-preview';
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS openrouter_text_model TEXT DEFAULT 'google/gemini-2.0-flash-exp:free';
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS openrouter_vision_model TEXT DEFAULT 'google/gemini-2.0-flash-exp:free';
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS openrouter_image_model TEXT DEFAULT 'stable-diffusion-xl';
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS openai_text_model TEXT DEFAULT 'gpt-4o-mini';
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS openai_vision_model TEXT DEFAULT 'gpt-4o-mini';
ALTER TABLE public.ai_settings ADD COLUMN IF NOT EXISTS openai_image_model TEXT DEFAULT 'dall-e-3';

-- updated_at trigger
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

-- AI Settings'de bir satır olduğundan emin ol
INSERT INTO public.ai_settings (id, enabled, system_prompt, temperature, max_output_tokens)
VALUES (1, true, 'Sen CizreApp kullanıcılarına yardımcı olan bir Türkçe yapay zeka asistanısın.', '0.7', 2048)
ON CONFLICT (id) DO NOTHING;
