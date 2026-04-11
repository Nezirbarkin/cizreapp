-- =====================================================
-- MESAJ OKUNDU BİLDİRİM SİSTEMİ
-- =====================================================
-- Karşı taraf sohbeti açtığında, gönderenin mesajları otomatik okundu olur
-- =====================================================

-- messages tablosunda read_at sütunu ekle (okunma zamanı)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public'
    AND table_name = 'messages'
    AND column_name = 'read_at'
  ) THEN
    ALTER TABLE public.messages ADD COLUMN read_at TIMESTAMPTZ;
  END IF;
END $$;

-- =====================================================
-- TRIGGER: Karşı taraf sohbeti açtığında mesajları okundu yap
-- =====================================================

-- Fonksiyon: Konuşma açıldığında mesajları okundu olarak işaretle
CREATE OR REPLACE FUNCTION public.mark_conversation_read()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  other_conv_id TEXT;
BEGIN
  -- Bu konuşmanın diğer tarafının conversation_id'sini bul
  SELECT id INTO other_conv_id
  FROM public.conversations
  WHERE user_id = (SELECT other_user_id FROM public.conversations WHERE id = NEW.id)
    AND other_user_id = (SELECT user_id FROM public.conversations WHERE id = NEW.id)
  LIMIT 1;

  -- Karşı tarafın conversation_id'si varsa, o konuşmadaki okunmamış mesajları okundu yap
  IF other_conv_id IS NOT NULL THEN
    UPDATE public.messages
    SET is_read = true,
        read_at = NOW()
    WHERE conversation_id = other_conv_id
      AND is_read = false;
      
    -- Karşı tarafın conversations tablosundaki unread_count'unu güncelle
    UPDATE public.conversations
    SET unread_count = 0
    WHERE id = other_conv_id;
  END IF;

  RETURN NEW;
END;
$$;

-- Trigger: updated_at değiştiğinde (sohbet açıldığında) tetiklenir
DROP TRIGGER IF EXISTS on_conversation_open ON public.conversations;
CREATE TRIGGER on_conversation_open
  AFTER UPDATE OF updated_at ON public.conversations
  FOR EACH ROW
  WHEN (NEW.updated_at > OLD.updated_at OR NEW.updated_at IS DISTINCT FROM OLD.updated_at)
  EXECUTE FUNCTION public.mark_conversation_read();

-- =====================================================
-- REALTIME UPDATE: Konuşma açıldığında karşı tarafa bildirim
-- =====================================================
-- Bu trigger, bir kullanıcı sohbeti açtığında karşı tarafa bildirim gönderir
-- Böylece karşı tarafın ekranında ✓✓ mavi ikon görünür

-- =====================================================
-- ALTERNATIF: RPC Fonksiyonu ile manuel okundu yapma
-- =====================================================
-- Uygulama tarafında sohbet açıldığında çağrılabilir

CREATE OR REPLACE FUNCTION public.mark_sender_messages_read(p_conversation_id TEXT, p_reader_id UUID)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  conv_data RECORD;
  other_conv_id TEXT;
  updated_count INT;
BEGIN
  -- Konuşma bilgilerini al
  SELECT * INTO conv_data
  FROM public.conversations
  WHERE id = p_conversation_id
  LIMIT 1;

  -- Diğer tarafın conversation_id'sini bul
  SELECT id INTO other_conv_id
  FROM public.conversations
  WHERE user_id = conv_data.other_user_id
    AND other_user_id = conv_data.user_id
  LIMIT 1;

  -- Diğer tarafın conversation_id'sindeki okunmamış mesajları okundu yap
  -- (Bu mesajlar okuyanın gönderdiği mesajlar)
  IF other_conv_id IS NOT NULL THEN
    UPDATE public.messages
    SET is_read = true,
        read_at = NOW()
    WHERE conversation_id = other_conv_id
      AND sender_id = p_reader_id
      AND is_read = false;

    GET DIAGNOSTICS updated_count = ROW_COUNT;

    -- Okunmamış mesaj sayısı 0 ise okundu sayacı da güncelle
    IF updated_count > 0 THEN
      UPDATE public.conversations
      SET unread_count = 0
      WHERE id = other_conv_id;
    END IF;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'updated_count', updated_count
  );
END;
$$;

-- =====================================================
-- KONTROL
-- =====================================================
SELECT 'Messages read status system enabled' as sonuc;
