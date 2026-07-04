-- ============================================================================
-- MIGRATION: 20260630_CHAT_P0_P1_FIX.sql
-- ----------------------------------------------------------------------------
-- PROJE_HAVIZA notlarına uyglu olarak:
--   - SECURITY DEFINER fonksiyonlarda SET search_path = public
--   - CREATE OR REPLACE sonrası GRANT EXECUTE manuel verilir
--   - Mevcut tablo/kolon adları korunur
--   - FK ilişkileri bozulmaz
--   - Idempotent (IF EXISTS / OR REPLACE)
-- ----------------------------------------------------------------------------
-- DÜZELTME KAPSAMI:
--   P0-1: mark_sender_messages_read RPC (hiç yok) — oluşturulur
--   P0-2: conversations_insert_own policy RLS güvencesi
--   P0-3: messages.updated_at default NOW() — NULL güvenliği
--   P1-1: group_members.is_muted kolonu (yoksa eklenir)
--   P1-2: group_message_read_receipts tablosu (yoksa oluşturulur)
-- ============================================================================

BEGIN;

-- ============================================================================
-- P0-1: mark_sender_messages_read RPC
-- ----------------------------------------------------------------------------
-- PROJE_HAVIZA_RLS.md §4.1.3 notu: policy içinde helper fn yerine subquery.
-- Bu fonksiyon SECURITY DEFINER olduğu için RLS'yi bypass eder ve auth.uid()
-- zincirine düşmez. Sadece NEW.sender_id eşleşmesini günceller.
-- ----------------------------------------------------------------------------
-- Parametreler:
--   p_conversation_id: okuyan kullanıcının conversation_id'si
--   p_reader_id: okuyan kullanıcının id'si (auth.uid client'tan gelir ama
--                SECURITY DEFINER içinde auth.uid() güvenli olmadığından
--                parametre olarak alınır)
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.mark_sender_messages_read(UUID, UUID);
DROP FUNCTION IF EXISTS public.mark_sender_messages_read(UUID);

CREATE OR REPLACE FUNCTION public.mark_sender_messages_read(
    p_conversation_id UUID,
    p_reader_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_other_user_id UUID;
    v_other_conv_id UUID;
BEGIN
    -- Okuyan kullanıcı yoksa çık
    IF p_reader_id IS NULL THEN
        RETURN;
    END IF;

    -- Bu conversation'ın diğer tarafını bul
    SELECT
        CASE
            WHEN user_id = p_reader_id THEN other_user_id
            WHEN other_user_id = p_reader_id THEN user_id
            ELSE NULL
        END
    INTO v_other_user_id
    FROM conversations
    WHERE id = p_conversation_id;

    -- Okuyan kullanıcı bu conversation'ın parçası değilse çık (güvenlik)
    IF v_other_user_id IS NULL THEN
        RETURN;
    END IF;

    -- Benim conversation'ımdaki, benim gönderdiğim mesajları okundu yap
    UPDATE messages
    SET is_read = TRUE, updated_at = NOW()
    WHERE conversation_id = p_conversation_id
      AND sender_id = p_reader_id
      AND is_read = FALSE;

    -- Karşı tarafın conversation'ını bul (çift yönlü sistem)
    SELECT id INTO v_other_conv_id
    FROM conversations
    WHERE user_id = v_other_user_id
      AND other_user_id = p_reader_id;

    -- Karşı tarafın conversation'ındaki benim mesajlarımı da okundu yap
    IF v_other_conv_id IS NOT NULL THEN
        UPDATE messages
        SET is_read = TRUE, updated_at = NOW()
        WHERE conversation_id = v_other_conv_id
          AND sender_id = p_reader_id
          AND is_read = FALSE;
    END IF;
END;
$$;

-- SECURITY DEFINER sonrası GRANT korunmaz (PROJE_HAVIZA_RLS.md §4.1.1)
GRANT EXECUTE ON FUNCTION public.mark_sender_messages_read(UUID, UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.mark_sender_messages_read(UUID, UUID) FROM anon;

-- ============================================================================
-- P0-2: conversations_insert_own policy güvencesi
-- ----------------------------------------------------------------------------
-- Mevcut policy (20260210000001_fix_chat_conversation_rls.sql) zaten
-- user_id=auth.uid() OR other_user_id=auth.uid() kullanıyor.
-- Bu migration o policy'nin varlığını garanti altına alır (idempotent).
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'conversations'
          AND policyname = 'conversations_insert_own'
    ) THEN
        CREATE POLICY "conversations_insert_own"
            ON public.conversations
            FOR INSERT
            TO authenticated
            WITH CHECK (
                user_id = auth.uid()
                OR other_user_id = auth.uid()
            );
    END IF;
END $$;

-- ============================================================================
-- P0-3: messages.updated_at default NOW()
-- ----------------------------------------------------------------------------
-- message_model.dart DateTime.parse(map['updated_at']) çağırıyor.
-- Eski kayıtlarda updated_at NULL olabilir → Flutter parse exception.
-- Default garantisi ile yeni INSERT'lerde hep dolu olur.
-- ----------------------------------------------------------------------------
ALTER TABLE public.messages
    ALTER COLUMN updated_at SET DEFAULT NOW();

-- ============================================================================
-- P1-1: group_members.is_muted kolonu
-- ----------------------------------------------------------------------------
-- group_model.dart'da isMuted alanı var, FIX_CHAT_AND_GROUP_MUTE_PUSH.sql
-- notify_group_message trigger'ı COALESCE(is_muted, false) kullanıyor.
-- Ama GROUP_CHAT_SETUP.sql'de bu kolon YOK. Idempotent ekleme.
-- ----------------------------------------------------------------------------
ALTER TABLE public.group_members
    ADD COLUMN IF NOT EXISTS is_muted BOOLEAN NOT NULL DEFAULT FALSE;

-- ============================================================================
-- P1-2: group_message_read_receipts tablosu
-- ----------------------------------------------------------------------------
-- PROJE_HAVIZASI.md §2.10 ve PROJE_HAVIZA_SCHEMA.md §2.3'te listeleniyor.
-- group_chat_service.dart:1062 mark_group_messages_read_receipts RPC'sini
-- çağırıyor. Tablo ve RPC yoksa oluşturulur.
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.group_message_read_receipts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID NOT NULL REFERENCES public.group_messages(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    read_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE(message_id, user_id)
);

CREATE INDEX IF NOT EXISTS idx_group_message_read_receipts_message_id
    ON public.group_message_read_receipts(message_id);
CREATE INDEX IF NOT EXISTS idx_group_message_read_receipts_user_id
    ON public.group_message_read_receipts(user_id);

ALTER TABLE public.group_message_read_receipts ENABLE ROW LEVEL SECURITY;

-- Herkes kendi read receipt'ini görebilir
DROP POLICY IF EXISTS "Users can view their own group read receipts"
    ON public.group_message_read_receipts;
CREATE POLICY "Users can view their own group read receipts"
    ON public.group_message_read_receipts
    FOR SELECT
    TO authenticated
    USING (user_id = auth.uid());

-- Herkes kendi read receipt'ini ekleyebilir
DROP POLICY IF EXISTS "Users can insert their own group read receipts"
    ON public.group_message_read_receipts;
CREATE POLICY "Users can insert their own group read receipts"
    ON public.group_message_read_receipts
    FOR INSERT
    TO authenticated
    WITH CHECK (user_id = auth.uid());

-- Realtime için yayına ekle (zaten ekliyse hata vermez)
DO $$
BEGIN
    BEGIN
        ALTER PUBLICATION supabase_realtime ADD TABLE public.group_message_read_receipts;
    EXCEPTION
        WHEN duplicate_object THEN NULL;
        WHEN others THEN NULL;
    END;
END $$;

-- ----------------------------------------------------------------------------
-- mark_group_messages_read_receipts RPC (group_chat_service.dart:1062)
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.mark_group_messages_read_receipts(UUID);

CREATE OR REPLACE FUNCTION public.mark_group_messages_read_receipts(
    p_group_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID := auth.uid();
BEGIN
    IF v_user_id IS NULL THEN
        RETURN;
    END IF;

    -- Kullanıcının okunmamış mesajlarını bul ve read receipt ekle
    INSERT INTO public.group_message_read_receipts (message_id, user_id)
    SELECT gm.id, v_user_id
    FROM public.group_messages gm
    WHERE gm.group_id = p_group_id
      AND gm.sender_id != v_user_id
      AND NOT EXISTS (
          SELECT 1 FROM public.group_message_read_receipts gmr
          WHERE gmr.message_id = gm.id
            AND gmr.user_id = v_user_id
      )
    ON CONFLICT (message_id, user_id) DO NOTHING;

    -- Kullanıcının unread_count'unu sıfırla
    UPDATE public.group_members
    SET unread_count = 0
    WHERE group_id = p_group_id
      AND user_id = v_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.mark_group_messages_read_receipts(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.mark_group_messages_read_receipts(UUID) FROM anon;

-- ----------------------------------------------------------------------------
-- get_message_read_receipts RPC (group_chat_service.dart:1085)
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_message_read_receipts(UUID);

CREATE OR REPLACE FUNCTION public.get_message_read_receipts(
    p_message_id UUID
)
RETURNS TABLE (
    user_id UUID,
    read_at TIMESTAMPTZ,
    full_name TEXT,
    avatar_url TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    RETURN QUERY
    SELECT
        gmr.user_id,
        gmr.read_at,
        p.full_name,
        p.avatar_url
    FROM public.group_message_read_receipts gmr
    LEFT JOIN public.profiles p ON p.id = gmr.user_id
    WHERE gmr.message_id = p_message_id
    ORDER BY gmr.read_at ASC;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_message_read_receipts(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.get_message_read_receipts(UUID) FROM anon;

-- ----------------------------------------------------------------------------
-- get_message_read_count RPC (group_chat_service.dart:1140)
-- ----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.get_message_read_count(UUID);

CREATE OR REPLACE FUNCTION public.get_message_read_count(
    p_message_id UUID
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_count
    FROM public.group_message_read_receipts
    WHERE message_id = p_message_id;

    RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.get_message_read_count(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.get_message_read_count(UUID) FROM anon;

COMMIT;

-- ============================================================================
-- DOĞRULAMA
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '================================================================';
    RAISE NOTICE '✅ 20260630_CHAT_P0_P1_FIX.sql TAMAMLANDI';
    RAISE NOTICE '   - mark_sender_messages_read RPC oluşturuldu';
    RAISE NOTICE '   - conversations_insert_own policy garanti altında';
    RAISE NOTICE '   - messages.updated_at default NOW()';
    RAISE NOTICE '   - group_members.is_muted kolonu eklendi';
    RAISE NOTICE '   - group_message_read_receipts tablosu oluşturuldu';
    RAISE NOTICE '   - 3 grup read receipt RPCsi oluşturuldu';
    RAISE NOTICE '================================================================';
END $$;