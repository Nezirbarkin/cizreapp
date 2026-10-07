-- =============================================================================
-- 20261007000002_send_message_lock_order.sql
-- -----------------------------------------------------------------------------
-- Admin > Loglar > "Son Hatalar": sendMessage RPC ERROR — "deadlock detected"
-- (40P01, 2026-09-30). İki kullanıcı aynı anda birbirine yazınca mesaj
-- tetikleyicisi konuşma satırlarını ters sıralarla kilitliyor, Postgres
-- gönderimlerden birini düşürüyor ve kullanıcı "mesaj gönderilemedi" görüyordu.
--
-- send_message_with_recipient artık mesajları eklemeden önce iki konuşma
-- satırını sabit (id) sırayla FOR UPDATE kilitler. Ayrıca alıcı satırı yoksa
-- oluşturulurken ON CONFLICT DO NOTHING + yeniden okuma yapılır: alıcının
-- aynı anda kendi tarafını açması 23505 (conversations_user_other_unique)
-- ile gönderimi düşürmez.
--
-- Gövde canlıdaki tanımdan (pg_get_functiondef) üretildi; yalnız bu iki
-- blok değişti. İmza aynı olduğu için mevcut GRANT'lar korunur.
-- =============================================================================

begin;

CREATE OR REPLACE FUNCTION public.send_message_with_recipient(p_conversation_id uuid, p_content text, p_sender_id uuid, p_reply_to_id uuid DEFAULT NULL::uuid, p_reply_to_content text DEFAULT NULL::text, p_reply_to_sender_name text DEFAULT NULL::text, p_message_type text DEFAULT 'text'::text, p_attachment jsonb DEFAULT NULL::jsonb)
 RETURNS TABLE(message_id uuid, sender_id uuid, recipient_id uuid, recipient_message_id uuid, content text, conversation_id uuid, created_at timestamp with time zone, updated_at timestamp with time zone, is_read boolean, reply_to_id uuid, reply_to_content text, reply_to_sender_name text, message_type text, attachment jsonb)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
    v_conv_user_id UUID;
    v_conv_other_user_id UUID;
    v_recipient_id UUID;
    v_recipient_conv_id UUID;
    v_new_message_id UUID;
    v_recipient_message_id UUID;
    v_now TIMESTAMP WITH TIME ZONE := NOW();
    v_type TEXT := COALESCE(NULLIF(btrim(p_message_type), ''), 'text');
    v_attachment JSONB := p_attachment;
    v_content TEXT := p_content;
BEGIN
    -- SECURITY DEFINER RLS'i atladığı için gönderen, çağıran kullanıcı olmak
    -- ZORUNDA; yoksa bir konuşmanın tarafı karşı taraf adına mesaj üretebilirdi.
    IF p_sender_id IS DISTINCT FROM auth.uid()
       AND COALESCE(auth.role(), '') <> 'service_role' THEN
        RAISE EXCEPTION 'send_message_with_recipient: sender must be the caller'
          USING ERRCODE = '42501';
    END IF;

    SELECT c.user_id, c.other_user_id
    INTO v_conv_user_id, v_conv_other_user_id
    FROM conversations c
    WHERE c.id = p_conversation_id;

    IF v_conv_user_id IS NULL THEN
        RAISE EXCEPTION 'Conversation not found';
    END IF;

    IF v_conv_user_id != p_sender_id THEN
        RAISE EXCEPTION 'Only conversation owner can send messages';
    END IF;

    v_recipient_id := v_conv_other_user_id;

    -- Tür ve ek veri. Tablo CHECK'i de korur; burada anlaşılır hata verilir.
    IF v_type NOT IN ('text', 'image', 'location') THEN
        RAISE EXCEPTION 'send_message_with_recipient: unknown message_type %', v_type
          USING ERRCODE = '22023';
    END IF;

    IF v_type = 'text' THEN
        v_attachment := NULL;
    ELSIF v_attachment IS NULL OR jsonb_typeof(v_attachment) <> 'object' THEN
        RAISE EXCEPTION 'send_message_with_recipient: % needs an attachment', v_type
          USING ERRCODE = '22023';
    END IF;

    IF v_type = 'image' THEN
        -- Fotoğraf GÖNDERENİN bu ALICI için açtığı klasörde olmalı ve gerçekten
        -- yüklenmiş olmalı: başka bir konuşmanın ya da kişinin dosyasına işaret
        -- eden mesaj üretilemez (alıcı o dosyayı ancak yolda adı geçtiği için
        -- okuyabilir).
        IF COALESCE(split_part(v_attachment ->> 'path', '/', 1), '') <> p_sender_id::text
           OR COALESCE(split_part(v_attachment ->> 'path', '/', 2), '') <> v_recipient_id::text THEN
            RAISE EXCEPTION 'send_message_with_recipient: image path must be <sender>/<recipient>/<file>'
              USING ERRCODE = '22023';
        END IF;
        IF NOT EXISTS (
            SELECT 1 FROM storage.objects o
             WHERE o.bucket_id = 'chat_attachments'
               AND o.name = v_attachment ->> 'path'
        ) THEN
            RAISE EXCEPTION 'send_message_with_recipient: image is not uploaded'
              USING ERRCODE = '22023';
        END IF;
    END IF;

    -- İçerik = önizleme metni (liste, bildirim, eski sürümler); boş bırakılamaz.
    IF v_type <> 'text' THEN
        v_content := COALESCE(
            NULLIF(btrim(COALESCE(p_content, '')), ''),
            CASE v_type WHEN 'image' THEN '📷 Fotoğraf' ELSE '📍 Konum' END
        );
    END IF;

    SELECT c.id INTO v_recipient_conv_id
    FROM conversations c
    WHERE c.user_id = v_recipient_id
      AND c.other_user_id = p_sender_id;

    -- Alıcı conv'u yoksa oluştur (unread=0; trigger row2'de +1 yapacak).
    -- ON CONFLICT: alıcı aynı anda kendi tarafını açıyorsa (istemcideki
    -- getOrCreateConversation INSERT'i) gönderim 23505 ile düşmesin; o
    -- satır yeniden okunur.
    IF v_recipient_conv_id IS NULL THEN
        INSERT INTO conversations (user_id, other_user_id, unread_count, created_at, updated_at)
        VALUES (v_recipient_id, p_sender_id, 0, v_now, v_now)
        ON CONFLICT (user_id, other_user_id) DO NOTHING
        RETURNING id INTO v_recipient_conv_id;

        IF v_recipient_conv_id IS NULL THEN
            SELECT c.id INTO v_recipient_conv_id
            FROM conversations c
            WHERE c.user_id = v_recipient_id
              AND c.other_user_id = p_sender_id;
        END IF;
    END IF;

    -- KİLİT SIRASI SABİT (deadlock önlemi). Mesaj tetikleyicisi
    -- (update_conversation_on_message) önce gönderenin, sonra alıcının konuşma
    -- satırını günceller. İki taraf AYNI ANDA birbirine yazınca biri A→B,
    -- diğeri B→A sırasıyla kilitliyor ve Postgres birini "deadlock detected"
    -- (40P01) ile düşürüyordu (admin Loglar, 2026-09-30). İki satır burada her
    -- çağrıda aynı (id) sırayla önceden kilitlenir; eşzamanlı gönderimler
    -- birbirini bekler, kilitlenmez.
    PERFORM 1
      FROM conversations c
     WHERE c.id IN (p_conversation_id, v_recipient_conv_id)
     ORDER BY c.id
       FOR UPDATE;

    -- 1) Gönderenin kopyası (is_read=TRUE) → trigger: gönderen conv unread=0
    INSERT INTO messages (conversation_id, sender_id, content, is_read, created_at, updated_at,
                          reply_to_id, reply_to_content, reply_to_sender_name, message_type, attachment)
    VALUES (p_conversation_id, p_sender_id, v_content, TRUE, v_now, v_now,
            p_reply_to_id, p_reply_to_content, p_reply_to_sender_name, v_type, v_attachment)
    RETURNING id INTO v_new_message_id;

    -- 2) Alıcının kopyası (is_read=FALSE) → trigger: alıcı conv unread += 1
    INSERT INTO messages (conversation_id, sender_id, content, is_read, created_at, updated_at,
                          reply_to_id, reply_to_content, reply_to_sender_name, message_type, attachment)
    VALUES (v_recipient_conv_id, p_sender_id, v_content, FALSE, v_now, v_now,
            p_reply_to_id, p_reply_to_content, p_reply_to_sender_name, v_type, v_attachment)
    RETURNING id INTO v_recipient_message_id;

    RETURN QUERY
    SELECT
        v_new_message_id,
        p_sender_id,
        v_recipient_id,
        v_recipient_message_id,
        v_content,
        p_conversation_id,
        v_now,
        v_now,
        FALSE,
        p_reply_to_id,
        p_reply_to_content,
        p_reply_to_sender_name,
        v_type,
        v_attachment;
END;
$function$;

commit;

notify pgrst, 'reload schema';
