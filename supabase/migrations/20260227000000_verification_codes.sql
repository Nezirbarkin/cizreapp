-- ============================================================================
-- EMAIL ONAY KODU SİSTEMİ
-- ============================================================================
-- Kapıda nakit ve kapıda kart ödemelerinde sipariş oluşturmadan önce
-- email ile onay kodu gönderilmesini sağlar
-- ============================================================================

-- verification_codes tablosu oluştur
CREATE TABLE IF NOT EXISTS public.verification_codes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  code TEXT NOT NULL,
  code_type TEXT NOT NULL CHECK (code_type IN ('order_verification', 'order_confirmation', 'email_verification', 'password_reset')),
  expires_at TIMESTAMPTZ NOT NULL,
  used_at TIMESTAMPTZ,
  metadata JSONB DEFAULT '{}',
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- İndeksler
CREATE INDEX IF NOT EXISTS idx_verification_codes_user_id ON public.verification_codes(user_id);
CREATE INDEX IF NOT EXISTS idx_verification_codes_code_type ON public.verification_codes(code_type);
CREATE INDEX IF NOT EXISTS idx_verification_codes_expires_at ON public.verification_codes(expires_at);

-- Kullanım amaçlı fonksiyonlar

-- Onay kodu oluştur ve gönder
CREATE OR REPLACE FUNCTION public.create_verification_code(
  p_user_id UUID,
  p_code_type TEXT,
  p_expires_minutes INT DEFAULT 5
) RETURNS UUID AS $$
DECLARE
  v_code TEXT;
  v_verification_id UUID;
BEGIN
  -- 6 haneli kod oluştur
  v_code := LPAD(FLOOR(RANDOM() * 1000000)::TEXT, 6, '0');
  
  -- Kod kaydı oluştur
  INSERT INTO public.verification_codes (
    user_id,
    code,
    code_type,
    expires_at,
    metadata
  ) VALUES (
    p_user_id,
    v_code,
    p_code_type,
    NOW() + (p_expires_minutes || ' minutes')::INTERVAL,
    '{}'::JSONB
  ) RETURNING id INTO v_verification_id;
  
  RETURN v_verification_id;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public';

-- Onay kodunu doğrula
CREATE OR REPLACE FUNCTION public.verify_code(
  p_user_id UUID,
  p_code TEXT,
  p_code_type TEXT DEFAULT 'order_confirmation'
) RETURNS JSONB AS $$
DECLARE
  v_verification_record RECORD;
BEGIN
  -- Kodu bul (kullanılmamış, süresi geçmemiş)
  SELECT * INTO v_verification_record
  FROM public.verification_codes
  WHERE user_id = p_user_id
    AND code = p_code
    AND code_type = p_code_type
    AND used_at IS NULL
    AND expires_at > NOW()
  ORDER BY created_at DESC
  LIMIT 1;
  
  -- Kod bulunamazsa
  IF NOT FOUND THEN
    RETURN jsonb_build_object(
      'success', false,
      'message', 'Geçersiz veya süresi geçmiş kod'
    );
  END IF;
  
  -- Kodu kullanılmış olarak işaretle
  UPDATE public.verification_codes
  SET used_at = NOW(),
      updated_at = NOW()
  WHERE id = v_verification_record.id;
  
  RETURN jsonb_build_object(
    'success', true,
    'message', 'Kod doğrulandı',
    'verification_id', v_verification_record.id
  );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public';

-- Eski kodları temizle (cron job için)
CREATE OR REPLACE FUNCTION public.cleanup_old_verification_codes()
RETURNS INT AS $$
DECLARE
  v_deleted_count INT;
BEGIN
  DELETE FROM public.verification_codes
  WHERE (expires_at < NOW() - INTERVAL '7 days')
     OR (used_at IS NOT NULL AND used_at < NOW() - INTERVAL '30 days');
  
  GET DIAGNOSTICS v_deleted_count = ROW_COUNT;
  
  RETURN v_deleted_count;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER SET search_path = 'public';

-- RLS Politikaları
ALTER TABLE public.verification_codes ENABLE ROW LEVEL SECURITY;

-- Kullanıcı sadece kendi kodlarını görebilir
CREATE POLICY "Users can view own verification codes"
  ON public.verification_codes
  FOR SELECT
  USING (user_id = auth.uid());

-- Kullanıcı kendi kodlarını oluşturabilir (trigger ile)
CREATE POLICY "Users can insert own verification codes"
  ON public.verification_codes
  FOR INSERT
  WITH CHECK (user_id = auth.uid());

-- Sonuç
DO $$
BEGIN
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'EMAIL ONAY KODU SİSTEMİ OLUŞTURULDU!';
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'verification_codes tablosu oluşturuldu';
    RAISE NOTICE 'create_verification_code() fonksiyonu eklendi';
    RAISE NOTICE 'verify_code() fonksiyonu eklendi';
    RAISE NOTICE 'cleanup_old_verification_codes() fonksiyonu eklendi';
    RAISE NOTICE '================================================================';
END $$;
