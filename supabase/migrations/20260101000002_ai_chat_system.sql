-- =====================================================
-- AI CHAT SYSTEM - VERİTABANI ŞEMASI
-- =====================================================
-- CizreApp yapay zeka sohbet sistemi
-- Sağlayıcılar: Google Gemini + OpenAI
-- Tarih: 2026-01-01
-- =====================================================

-- =====================================================
-- 1. YARDIMCI FONKSİYON: is_admin
-- =====================================================
-- Eğer profiles tablosunda role kolonu varsa, admin kontrolü
CREATE OR REPLACE FUNCTION public.is_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles
    WHERE id = auth.uid()
      AND (
        role = 'admin'::user_role
        OR is_admin = true
      )
  );
$$ LANGUAGE sql SECURITY DEFINER STABLE;

-- =====================================================
-- 2. TABLOLAR
-- =====================================================

-- 2.1 ai_settings: Sistem geneli tek satır ayarlar
CREATE TABLE IF NOT EXISTS public.ai_settings (
  id INT PRIMARY KEY DEFAULT 1,
  enabled BOOLEAN NOT NULL DEFAULT true,
  provider TEXT NOT NULL DEFAULT 'gemini' CHECK (provider IN ('gemini', 'openai')),

  -- Gemini modelleri
  text_model TEXT NOT NULL DEFAULT 'gemini-1.5-flash',
  vision_model TEXT NOT NULL DEFAULT 'gemini-1.5-flash',
  image_model TEXT NOT NULL DEFAULT 'imagen-3.0-generate-002',

  -- OpenAI modelleri
  openai_text_model TEXT NOT NULL DEFAULT 'gpt-4o-mini',
  openai_vision_model TEXT NOT NULL DEFAULT 'gpt-4o-mini',
  openai_image_model TEXT NOT NULL DEFAULT 'dall-e-3',

  -- Limitler
  daily_request_limit_per_user INT NOT NULL DEFAULT 50,
  daily_token_limit_per_user INT NOT NULL DEFAULT 100000,
  max_messages_per_conversation INT NOT NULL DEFAULT 100,

  -- Özellikler
  allow_image_upload BOOLEAN NOT NULL DEFAULT true,
  allow_image_generation BOOLEAN NOT NULL DEFAULT true,
  allow_camera_capture BOOLEAN NOT NULL DEFAULT true,

  -- Davranış
  system_prompt TEXT NOT NULL DEFAULT 'Sen CizreApp kullanıcılarına yardımcı olan, Türkçe konuşan, samimi ve profesyonel bir yapay zeka asistanısın. Yanıtlarında Markdown formatını kullanabilirsin. Kullanıcılara pazaryeri, dükkanlar, ürünler ve sosyal özellikler hakkında bilgi verebilirsin.',
  temperature NUMERIC(3,2) NOT NULL DEFAULT 0.7 CHECK (temperature >= 0 AND temperature <= 2),
  max_output_tokens INT NOT NULL DEFAULT 2048 CHECK (max_output_tokens > 0 AND max_output_tokens <= 8192),

  -- Meta
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,

  CONSTRAINT single_row CHECK (id = 1)
);

-- 2.2 ai_conversations: Kullanıcı konuşmaları
CREATE TABLE IF NOT EXISTS public.ai_conversations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT,
  provider TEXT NOT NULL DEFAULT 'gemini',
  message_count INT NOT NULL DEFAULT 0,
  last_message_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  is_archived BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ai_conv_user_last
  ON public.ai_conversations(user_id, last_message_at DESC);

CREATE INDEX IF NOT EXISTS idx_ai_conv_user_archived
  ON public.ai_conversations(user_id, is_archived);

CREATE INDEX IF NOT EXISTS idx_ai_conv_provider
  ON public.ai_conversations(provider);

-- 2.3 ai_messages: Mesajlar
CREATE TABLE IF NOT EXISTS public.ai_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  conversation_id UUID NOT NULL REFERENCES public.ai_conversations(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('user', 'assistant', 'system')),
  content TEXT NOT NULL,
  attachments JSONB NOT NULL DEFAULT '[]'::jsonb,
  generated_images JSONB NOT NULL DEFAULT '[]'::jsonb,
  tokens_used INT NOT NULL DEFAULT 0,
  provider TEXT,
  model TEXT,
  error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_ai_msg_conv_created
  ON public.ai_messages(conversation_id, created_at);

CREATE INDEX IF NOT EXISTS idx_ai_msg_user
  ON public.ai_messages(user_id);

-- 2.4 ai_daily_usage: Günlük kullanım sayaçları
CREATE TABLE IF NOT EXISTS public.ai_daily_usage (
  id BIGSERIAL PRIMARY KEY,
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  usage_date DATE NOT NULL DEFAULT CURRENT_DATE,
  request_count INT NOT NULL DEFAULT 0,
  token_count INT NOT NULL DEFAULT 0,
  image_generation_count INT NOT NULL DEFAULT 0,
  last_request_at TIMESTAMPTZ,
  UNIQUE (user_id, usage_date)
);

CREATE INDEX IF NOT EXISTS idx_ai_usage_date
  ON public.ai_daily_usage(usage_date);

-- =====================================================
-- 3. TRIGGER FONKSİYONLARI
-- =====================================================

-- 3.1 Yeni mesaj eklendiğinde konuşma istatistiklerini güncelle
CREATE OR REPLACE FUNCTION public.ai_on_message_insert()
RETURNS TRIGGER AS $$
BEGIN
  IF NEW.role = 'user' THEN
    -- Konuşma istatistiklerini güncelle
    UPDATE public.ai_conversations
    SET
      message_count = message_count + 1,
      last_message_at = now(),
      -- İlk user mesajı ise başlık oluştur
      title = COALESCE(
        title,
        CASE
          WHEN length(NEW.content) > 50
          THEN substring(NEW.content FROM 1 FOR 50) || '...'
          ELSE NEW.content
        END
      )
    WHERE id = NEW.conversation_id;
  ELSIF NEW.role = 'assistant' THEN
    UPDATE public.ai_conversations
    SET message_count = message_count + 1
    WHERE id = NEW.conversation_id;
  END IF;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS trg_ai_message_insert ON public.ai_messages;
CREATE TRIGGER trg_ai_message_insert
  AFTER INSERT ON public.ai_messages
  FOR EACH ROW
  EXECUTE FUNCTION public.ai_on_message_insert();

-- 3.2 updated_at otomatik güncelleme (ai_settings)
CREATE OR REPLACE FUNCTION public.ai_set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_ai_settings_updated ON public.ai_settings;
CREATE TRIGGER trg_ai_settings_updated
  BEFORE UPDATE ON public.ai_settings
  FOR EACH ROW
  EXECUTE FUNCTION public.ai_set_updated_at();

-- =====================================================
-- 4. ROW LEVEL SECURITY (RLS)
-- =====================================================

-- ai_settings
ALTER TABLE public.ai_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ai_settings_admin_all" ON public.ai_settings;
CREATE POLICY "ai_settings_admin_all" ON public.ai_settings
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- Misafir kullanıcılar enabled durumunu görebilir (feature gating için)
DROP POLICY IF EXISTS "ai_settings_read_enabled" ON public.ai_settings;
CREATE POLICY "ai_settings_read_enabled" ON public.ai_settings
  FOR SELECT TO authenticated, anon
  USING (true);

-- ai_conversations
ALTER TABLE public.ai_conversations ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ai_conv_select_own" ON public.ai_conversations;
CREATE POLICY "ai_conv_select_own" ON public.ai_conversations
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "ai_conv_insert_own" ON public.ai_conversations;
CREATE POLICY "ai_conv_insert_own" ON public.ai_conversations
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "ai_conv_update_own" ON public.ai_conversations;
CREATE POLICY "ai_conv_update_own" ON public.ai_conversations
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "ai_conv_delete_own" ON public.ai_conversations;
CREATE POLICY "ai_conv_delete_own" ON public.ai_conversations
  FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- Admin tüm konuşmaları görebilir
DROP POLICY IF EXISTS "ai_conv_admin_all" ON public.ai_conversations;
CREATE POLICY "ai_conv_admin_all" ON public.ai_conversations
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ai_messages
ALTER TABLE public.ai_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ai_msg_select_own" ON public.ai_messages;
CREATE POLICY "ai_msg_select_own" ON public.ai_messages
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS "ai_msg_insert_own" ON public.ai_messages;
CREATE POLICY "ai_msg_insert_own" ON public.ai_messages
  FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "ai_msg_update_own" ON public.ai_messages;
CREATE POLICY "ai_msg_update_own" ON public.ai_messages
  FOR UPDATE TO authenticated
  USING (user_id = auth.uid())
  WITH CHECK (user_id = auth.uid());

DROP POLICY IF EXISTS "ai_msg_delete_own" ON public.ai_messages;
CREATE POLICY "ai_msg_delete_own" ON public.ai_messages
  FOR DELETE TO authenticated
  USING (user_id = auth.uid());

-- Admin tüm mesajları görebilir
DROP POLICY IF EXISTS "ai_msg_admin_all" ON public.ai_messages;
CREATE POLICY "ai_msg_admin_all" ON public.ai_messages
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- ai_daily_usage
ALTER TABLE public.ai_daily_usage ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "ai_usage_select_own" ON public.ai_daily_usage;
CREATE POLICY "ai_usage_select_own" ON public.ai_daily_usage
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

-- Admin tüm kullanımı görebilir
DROP POLICY IF EXISTS "ai_usage_admin_all" ON public.ai_daily_usage;
CREATE POLICY "ai_usage_admin_all" ON public.ai_daily_usage
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- INSERT/UPDATE sadece service_role (Edge Function) üzerinden yapılacak
-- Kullanıcılar doğrudan yapamaz (RLS yukarıdaki politikalarla sınırlı)

-- =====================================================
-- 5. SEED DATA
-- =====================================================
INSERT INTO public.ai_settings (id, enabled, provider)
VALUES (1, true, 'gemini')
ON CONFLICT (id) DO NOTHING;

-- =====================================================
-- 6. STORAGE BUCKET
-- =====================================================
-- ai-uploads bucket (kullanıcı yüklemeleri)
INSERT INTO storage.buckets (id, name, public)
VALUES ('ai-uploads', 'ai-uploads', false)
ON CONFLICT (id) DO NOTHING;

-- ai-generated bucket (AI üretimleri)
INSERT INTO storage.buckets (id, name, public)
VALUES ('ai-generated', 'ai-generated', false)
ON CONFLICT (id) DO NOTHING;

-- ai-uploads storage policies
DROP POLICY IF EXISTS "ai_uploads_select_own" ON storage.objects;
CREATE POLICY "ai_uploads_select_own" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'ai-uploads'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "ai_uploads_insert_own" ON storage.objects;
CREATE POLICY "ai_uploads_insert_own" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'ai-uploads'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

DROP POLICY IF EXISTS "ai_uploads_delete_own" ON storage.objects;
CREATE POLICY "ai_uploads_delete_own" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'ai-uploads'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- ai-generated storage policies (kullanıcı kendi üretilenlerini okuyabilir)
DROP POLICY IF EXISTS "ai_generated_select_own" ON storage.objects;
CREATE POLICY "ai_generated_select_own" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'ai-generated'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Admin tüm AI dosyalarını görebilir
DROP POLICY IF EXISTS "ai_storage_admin_all" ON storage.objects;
CREATE POLICY "ai_storage_admin_all" ON storage.objects
  FOR ALL TO authenticated
  USING (
    bucket_id IN ('ai-uploads', 'ai-generated')
    AND public.is_admin()
  )
  WITH CHECK (
    bucket_id IN ('ai-uploads', 'ai-generated')
    AND public.is_admin()
  );

-- =====================================================
-- 7. RPC FONKSİYONLARI (Edge Function için)
-- =====================================================

-- 7.1 Günlük kullanımı atomik olarak artır ve kontrol et
CREATE OR REPLACE FUNCTION public.ai_increment_usage(
  p_user_id UUID,
  p_tokens INT DEFAULT 0,
  p_is_image_generation BOOLEAN DEFAULT false
)
RETURNS TABLE (
  success BOOLEAN,
  new_request_count INT,
  new_token_count INT,
  request_limit_exceeded BOOLEAN,
  token_limit_exceeded BOOLEAN
) AS $$
DECLARE
  v_settings RECORD;
  v_usage RECORD;
  v_req_exceeded BOOLEAN := false;
  v_tok_exceeded BOOLEAN := false;
BEGIN
  -- Ayarları al
  SELECT daily_request_limit_per_user, daily_token_limit_per_user
  INTO v_settings
  FROM public.ai_settings
  WHERE id = 1;

  -- Bugünkü kullanımı al veya oluştur
  INSERT INTO public.ai_daily_usage (user_id, usage_date, request_count, token_count, image_generation_count, last_request_at)
  VALUES (p_user_id, CURRENT_DATE, 0, 0, 0, now())
  ON CONFLICT (user_id, usage_date)
  DO NOTHING;

  SELECT request_count, token_count
  INTO v_usage
  FROM public.ai_daily_usage
  WHERE user_id = p_user_id AND usage_date = CURRENT_DATE
  FOR UPDATE;

  -- Limit kontrolü
  v_req_exceeded := v_usage.request_count >= COALESCE(v_settings.daily_request_limit_per_user, 50);
  v_tok_exceeded := (v_usage.token_count + p_tokens) > COALESCE(v_settings.daily_token_limit_per_user, 100000);

  IF v_req_exceeded OR v_tok_exceeded THEN
    RETURN QUERY SELECT
      false,
      v_usage.request_count,
      v_usage.token_count,
      v_req_exceeded,
      v_tok_exceeded;
    RETURN;
  END IF;

  -- Artır
  UPDATE public.ai_daily_usage
  SET
    request_count = request_count + 1,
    token_count = token_count + GREATEST(p_tokens, 0),
    image_generation_count = image_generation_count + (CASE WHEN p_is_image_generation THEN 1 ELSE 0 END),
    last_request_at = now()
  WHERE user_id = p_user_id AND usage_date = CURRENT_DATE
  RETURNING request_count, token_count INTO v_usage;

  RETURN QUERY SELECT
    true,
    v_usage.request_count,
    v_usage.token_count,
    false,
    false;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7.2 Admin istatistikleri
CREATE OR REPLACE FUNCTION public.ai_get_admin_stats(p_days INT DEFAULT 7)
RETURNS TABLE (
  total_conversations BIGINT,
  total_messages BIGINT,
  total_users BIGINT,
  today_requests BIGINT,
  today_tokens BIGINT,
  total_tokens BIGINT,
  provider_distribution JSONB,
  daily_breakdown JSONB
) AS $$
BEGIN
  RETURN QUERY
  WITH
    stats AS (
      SELECT
        (SELECT COUNT(*) FROM public.ai_conversations) AS total_conversations,
        (SELECT COUNT(*) FROM public.ai_messages) AS total_messages,
        (SELECT COUNT(DISTINCT user_id) FROM public.ai_conversations) AS total_users,
        (SELECT COALESCE(SUM(request_count), 0) FROM public.ai_daily_usage WHERE usage_date = CURRENT_DATE) AS today_requests,
        (SELECT COALESCE(SUM(token_count), 0) FROM public.ai_daily_usage WHERE usage_date = CURRENT_DATE) AS today_tokens,
        (SELECT COALESCE(SUM(token_count), 0) FROM public.ai_daily_usage) AS total_tokens
    ),
    prov AS (
      SELECT
        jsonb_build_object(
          'gemini', COUNT(*) FILTER (WHERE provider = 'gemini'),
          'openai', COUNT(*) FILTER (WHERE provider = 'openai')
        ) AS provider_distribution
      FROM public.ai_conversations
    ),
    days AS (
      SELECT jsonb_agg(row_to_json(d)) AS daily_breakdown
      FROM (
        SELECT
          usage_date::text AS date,
          COALESCE(SUM(request_count), 0) AS requests,
          COALESCE(SUM(token_count), 0) AS tokens,
          COALESCE(SUM(image_generation_count), 0) AS images
        FROM public.ai_daily_usage
        WHERE usage_date >= CURRENT_DATE - p_days
        GROUP BY usage_date
        ORDER BY usage_date DESC
      ) d
    )
  SELECT
    s.total_conversations,
    s.total_messages,
    s.total_users,
    s.today_requests,
    s.today_tokens,
    s.total_tokens,
    p.provider_distribution,
    COALESCE(d.daily_breakdown, '[]'::jsonb)
  FROM stats s, prov p, days d;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER STABLE;

-- RPC fonksiyonlarına erişim
GRANT EXECUTE ON FUNCTION public.ai_increment_usage TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.ai_get_admin_stats TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.is_admin TO authenticated, service_role;

-- =====================================================
-- 8. GRANT
-- =====================================================
GRANT USAGE ON SCHEMA public TO anon, authenticated, service_role;
GRANT ALL ON public.ai_settings TO authenticated, service_role;
GRANT ALL ON public.ai_conversations TO authenticated, service_role;
GRANT ALL ON public.ai_messages TO authenticated, service_role;
GRANT ALL ON public.ai_daily_usage TO authenticated, service_role;
GRANT USAGE, SELECT ON SEQUENCE public.ai_daily_usage_id_seq TO authenticated, service_role;

-- =====================================================
-- YORUM / BİLGİ
-- =====================================================
COMMENT ON TABLE public.ai_settings IS 'AI chat sistemi için global ayarlar (tek satır)';
COMMENT ON TABLE public.ai_conversations IS 'Kullanıcı yapay zeka sohbet konuşmaları';
COMMENT ON TABLE public.ai_messages IS 'Konuşma mesajları (user/assistant/system)';
COMMENT ON TABLE public.ai_daily_usage IS 'Kullanıcı bazlı günlük AI kullanım sayaçları';
COMMENT ON FUNCTION public.ai_increment_usage IS 'AI kullanımını atomik artırır ve limitleri kontrol eder';
COMMENT ON FUNCTION public.ai_get_admin_stats IS 'Admin için AI kullanım istatistiklerini döndürür';