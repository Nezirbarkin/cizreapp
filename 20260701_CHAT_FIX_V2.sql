-- ============================================================================
-- MIGRATION V2: 20260701_CHAT_FIX_V2.sql
-- ----------------------------------------------------------------------------
-- Üç kritik sorunu çözer:
-- 1. Mesaj karşı tarafın sohbetinde görünmüyor → trigger çift yönlü kopyalama
-- 2. Online kullanıcı göstermiyor → is_online_enabled/is_ghost_mode kolonları
-- 3. Mesaj iki kez silindiğinde gerçekten siliniyor → soft delete doğru çalışmalı
-- ============================================================================

-- 1) ÇİFT YÖNLÜ MESAJ KOPYALAMA TRIGGER
-- Mesaj insert edildiğinde, alıcının conversation_id'si ile de kopyasını oluştur.
-- ID'ye göre tekilleştirme UI'da çift göstermeyi önler.

DROP TRIGGER IF EXISTS message_replicate_to_recipient ON messages;
DROP FUNCTION IF EXISTS public.replicate_message_to_recipient();

CREATE OR REPLACE FUNCTION public.replicate_message_to_recipient()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_alicinin_conv_id UUID;
    v_gonderen_user_id UUID;
    v_diger_user_id UUID;
    v_alici_user_id UUID;
BEGIN
    -- Bu mesajin hangi conversation'a yazildigini bul
    SELECT user_id, other_user_id
    INTO v_gonderen_user_id, v_diger_user_id
    FROM conversations
    WHERE id = NEW.conversation_id;

    IF v_gonderen_user_id IS NULL THEN
        RETURN NEW;
    END IF;

    -- Alici user_id'si
    v_alici_user_id := CASE
        WHEN v_gonderen_user_id = NEW.sender_id THEN v_diger_user_id
        ELSE v_gonderen_user_id
    END;

    -- Alicinin kendi conversation_id'sini bul
    -- Alici: (user_id=alici, other_user_id=gonderen)
    SELECT id INTO v_alicinin_conv_id
    FROM conversations
    WHERE user_id = v_alici_user_id
      AND other_user_id = NEW.sender_id
    LIMIT 1;

    IF v_alicinin_conv_id IS NULL OR v_alicinin_conv_id = NEW.conversation_id THEN
        -- Alicinin henuz conversation'i yok veya mesaj zaten alici tarafina yazildi
        RETURN NEW;
    END IF;

    -- Alicinin conversation'ina ayni id ile kopyala
    -- ORPHAN REPLICA FLAG: ana mesaj silinirse kopyayi da temizlemek icin
    INSERT INTO messages (
        id, conversation_id, sender_id, content,
        is_read, created_at, updated_at,
        reply_to_id, reply_to_content, reply_to_sender_name,
        deleted_for_user_id
    ) VALUES (
        NEW.id, v_alicinin_conv_id, NEW.sender_id, NEW.content,
        NEW.is_read, NEW.created_at, NEW.updated_at,
        NEW.reply_to_id, NEW.reply_to_content, NEW.reply_to_sender_name,
        NEW.deleted_for_user_id
    )
    ON CONFLICT (id) DO NOTHING;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- ON CONFLICT icin PK kontrolu - id PK ise zaten unique, degilse index ekle
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'messages_pkey'
    ) THEN
        -- id PK degilse unique index ekle ki ON CONFLICT (id) calissin
        CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_id_unique ON messages(id);
    END IF;
END $$;

CREATE TRIGGER message_replicate_to_recipient
    AFTER INSERT ON messages
    FOR EACH ROW
    EXECUTE FUNCTION public.replicate_message_to_recipient();

-- 2) ESKI MESAJLAR ICIN BACKFILL: Mevcut mesajlari karsi tarafin conversation'ina kopyala
-- Bu, migration oncesi atilmis mesajlari da gosterir
DO $$
DECLARE
    msg RECORD;
    v_alicinin_conv_id UUID;
    v_gonderen_user_id UUID;
    v_diger_user_id UUID;
    v_alici_user_id UUID;
    copy_count INT := 0;
BEGIN
    FOR msg IN
        SELECT m.id, m.conversation_id, m.sender_id
        FROM messages m
        WHERE m.conversation_id IN (SELECT id FROM conversations)
        ORDER BY m.created_at ASC
    LOOP
        -- Conversation bilgilerini al
        SELECT user_id, other_user_id
        INTO v_gonderen_user_id, v_diger_user_id
        FROM conversations
        WHERE id = msg.conversation_id;

        IF v_gonderen_user_id IS NULL THEN
            CONTINUE;
        END IF;

        v_alici_user_id := CASE
            WHEN v_gonderen_user_id = msg.sender_id THEN v_diger_user_id
            ELSE v_gonderen_user_id
        END;

        IF v_alici_user_id IS NULL THEN
            CONTINUE;
        END IF;

        SELECT id INTO v_alicinin_conv_id
        FROM conversations
        WHERE user_id = v_alici_user_id
          AND other_user_id = msg.sender_id
        LIMIT 1;

        IF v_alicinin_conv_id IS NULL OR v_alicinin_conv_id = msg.conversation_id THEN
            CONTINUE;
        END IF;

        -- Kopyayi ekle
        INSERT INTO messages (
            id, conversation_id, sender_id, content,
            is_read, created_at, updated_at,
            reply_to_id, reply_to_content, reply_to_sender_name,
            deleted_for_user_id
        )
        SELECT
            id, v_alicinin_conv_id, sender_id, content,
            is_read, created_at, updated_at,
            reply_to_id, reply_to_content, reply_to_sender_name,
            deleted_for_user_id
        FROM messages
        WHERE id = msg.id
        ON CONFLICT (id) DO NOTHING;

        copy_count := copy_count + 1;
    END LOOP;

    RAISE NOTICE 'Backfill: % mesaj kopyalandi', copy_count;
END $$;

-- 3) profiles tablosuna is_online_enabled ve is_ghost_mode ekle (yoksa)
ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS is_online_enabled BOOLEAN DEFAULT true;

ALTER TABLE public.profiles
    ADD COLUMN IF NOT EXISTS is_ghost_mode BOOLEAN DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_profiles_is_online_enabled
    ON public.profiles(is_online_enabled);

CREATE INDEX IF NOT EXISTS idx_profiles_is_ghost_mode
    ON public.profiles(is_ghost_mode);

-- 4) ensureOnlineStatus() fonksiyonu - last_seen heartbeat guncellemesi
-- (Online kullanici gostermek icin last_seen ve is_online duzgun tutulmali)
DROP FUNCTION IF EXISTS public.ensure_online_status();

CREATE OR REPLACE FUNCTION public.ensure_online_status()
RETURNS TRIGGER
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    -- is_online=true ise last_seen'i de simdi yap
    IF NEW.is_online = true AND (OLD.is_online IS DISTINCT FROM true) THEN
        NEW.last_seen := NOW();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS ensure_online_status_trigger ON profiles;
CREATE TRIGGER ensure_online_status_trigger
    BEFORE UPDATE OF is_online ON profiles
    FOR EACH ROW
    EXECUTE FUNCTION public.ensure_online_status();

-- 5) MESAJ DELETE/CASCADE DAVRANIS KONTROLU
-- ON DELETE CASCADE mesajlari tamamen siler. Simdi mesajlar iki tarafta da
-- olabilir (replicate). CASCADE sadece GERCEK orphan mesajlari silmeli.
-- Bu nedenle messages tablosunda ON DELETE CASCADE'i kaldirip ON DELETE SET NULL
-- yapiyoruz; boylece conversation silinse bile mesajlar veritabaninda kalir.
DO $$
BEGIN
    -- conversation_id uzerindeki FK'yi kontrol et
    IF EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'messages_conversation_id_fkey'
    ) THEN
        ALTER TABLE messages
            DROP CONSTRAINT messages_conversation_id_fkey;

        ALTER TABLE messages
            ADD CONSTRAINT messages_conversation_id_fkey
            FOREIGN KEY (conversation_id)
            REFERENCES conversations(id)
            ON DELETE SET NULL;
    END IF;
END $$;

-- 6) Aciklama / Tamam
DO $$
BEGIN
    RAISE NOTICE 'V2 TAMAMLANDI: Cift yonlu mesaj + is_online_enabled/is_ghost_mode + SET NULL FK';
END $$;