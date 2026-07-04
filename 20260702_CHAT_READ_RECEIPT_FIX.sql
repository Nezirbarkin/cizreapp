-- ============================================================================
-- MIGRATION: 20260702_CHAT_READ_RECEIPT_FIX.sql
-- -----------------------------------------------------------------------------
-- SORUN #2: A kullanicisi B'ye mesaj atiyor, A kendi mesajina "goruldu" diyor
--            ama B henuz gormedi!
-- KOK NEDEN:
--   - mark_sender_messages_read sadece tek conversation'i guncelliyordu
--   - B sohbeti actiginda sadece kendi conversation'indaki mesajlari isaretliyor
--
-- COZUM:
--   - mark_messages_as_read fonksiyonu guncelleniyor
--   - Artik TUM partner mesajlarini okundu yapiyor (her iki conversation'da)
--   - mark_sender_messages_read fonksiyonu KALDIRILIYOR (gereksiz)
-- -----------------------------------------------------------------------------
-- GERI ALMA:
--   Bu dosyadaki fonksiyonlari eski versiyonlarla degistir
-- ============================================================================

-- mark_sender_messages_read FONKSIYONUNU GUNCELLE
-- Artık sadece kendi gonderdigi mesajlari okundu YAPMA!
-- Bunun yerine, okundu bilgisi sadece ALICI tarafindan işaretlenmeli
DROP FUNCTION IF EXISTS public.mark_sender_messages_read(UUID, UUID);
DROP FUNCTION IF EXISTS public.mark_sender_messages_read(UUID);

-- YENI FONKSIYON: mark_messages_as_read
-- Bu fonksiyon SOHBETI ACIKLDIĞINDA cagrilir
-- Amac: Karsi tarafin gonderdigi MESAJLARI okundu yapmak
DROP FUNCTION IF EXISTS public.mark_messages_as_read(UUID);

CREATE OR REPLACE FUNCTION public.mark_messages_as_read(
    p_conversation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_reader UUID := auth.uid();
    v_partner_id UUID;
    v_reader_conv_id UUID;
    v_partner_conv_id UUID;
BEGIN
    IF v_reader IS NULL THEN
        RETURN;
    END IF;

    -- Bu conversation'un bilgilerini al
    SELECT user_id, other_user_id INTO v_reader_conv_id, v_partner_id
    FROM conversations
    WHERE id = p_conversation_id;

    IF v_reader_conv_id IS NULL OR v_partner_id IS NULL THEN
        RETURN;
    END IF;

    -- Sadece BU conversation'un sahibi ise devam et
    IF v_reader_conv_id != v_reader THEN
        RETURN;
    END IF;

    -- Partner'in conversation'unu bul
    SELECT id INTO v_partner_conv_id
    FROM conversations
    WHERE user_id = v_partner_id
      AND other_user_id = v_reader;

    -- 1) BU conversation'daki partner mesajlarini okundu yap
    --    (Karsi tarafin gonderdigi mesajlar)
    UPDATE messages
    SET is_read = TRUE, updated_at = NOW()
    WHERE conversation_id = p_conversation_id
      AND sender_id = v_partner_id
      AND is_read = FALSE;

    -- 2) PARTNER CONVERSATION'INDAKI MESAJLARI DA OKUNDU YAP!
    --    Cunku artik trigger mesaji her iki conversation'a da ekliyor
    --    Bu satir olmazsa okundu bilgisi yanlis gorunur
    IF v_partner_conv_id IS NOT NULL THEN
        UPDATE messages
        SET is_read = TRUE, updated_at = NOW()
        WHERE conversation_id = v_partner_conv_id
          AND sender_id = v_partner_id
          AND is_read = FALSE;
    END IF;

    -- 3) Reader'in unread_count'unu sifirla
    UPDATE conversations
    SET unread_count = 0, updated_at = NOW()
    WHERE id = p_conversation_id;

    -- 4) Partner'in unread_count'unu da guncelle (varsa)
    IF v_partner_conv_id IS NOT NULL THEN
        UPDATE conversations
        SET unread_count = 0, updated_at = NOW()
        WHERE id = v_partner_conv_id;
    END IF;
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_messages_as_read(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.mark_messages_as_read(UUID) FROM anon;

-- YENI FONKSIYON: mark_all_messages_as_read
-- Bu fonksiyon SOHBET ACILDIGINDA cagrilir
-- mark_messages_as_read'den farkli olarak sadece partner mesajlarini okundu yapar
DROP FUNCTION IF EXISTS public.mark_all_messages_read(UUID);

CREATE OR REPLACE FUNCTION public.mark_all_messages_read(
    p_conversation_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_reader UUID := auth.uid();
    v_partner_id UUID;
    v_reader_conv_id UUID;
BEGIN
    IF v_reader IS NULL THEN
        RETURN;
    END IF;

    -- Conversation bilgilerini al
    SELECT user_id, other_user_id INTO v_reader_conv_id, v_partner_id
    FROM conversations
    WHERE id = p_conversation_id;

    IF v_reader_conv_id IS NULL OR v_partner_id IS NULL THEN
        RETURN;
    END IF;

    -- Sadece bu conversation'un sahibi ise devam et
    IF v_reader_conv_id != v_reader THEN
        RETURN;
    END IF;

    -- Karsi tarafin gonderdigi mesajlari okundu yap
    -- (Kendi mesajlarimizi okundu yapmiyoruz!)
    UPDATE messages
    SET is_read = TRUE, updated_at = NOW()
    WHERE conversation_id = p_conversation_id
      AND sender_id = v_partner_id
      AND is_read = FALSE;

    -- Unread count'u sifirla
    UPDATE conversations
    SET unread_count = 0, updated_at = NOW()
    WHERE id = p_conversation_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_all_messages_read(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.mark_all_messages_read(UUID) FROM anon;

-- DOGRULAMA
DO $$
BEGIN
    RAISE NOTICE '✅ 20260702_CHAT_READ_RECEIPT_FIX.sql TAMAMLANDI';
    RAISE NOTICE '   - mark_messages_as_read artik her iki conv''daki mesajlari isaretliyor';
    RAISE NOTICE '   - mark_sender_messages_read kaldirildi (gereksiz)';
    RAISE NOTICE '   - Okundu bilgisi artik sadece alici tarafindan isaretleniyor';
END $$;
