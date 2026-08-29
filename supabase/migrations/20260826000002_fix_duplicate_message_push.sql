-- ============================================================================
-- Sohbette cihaza çift push gitmesi düzeltmesi
-- ----------------------------------------------------------------------------
-- KÖK NEDEN: public.conversations tablosunda aynı iki kullanıcı için
-- (user_id, other_user_id) çiftinin HER İKİ yönde de ayrı bir satırı olan
-- 36 "aynalı" (mirrored) çift tespit edildi (ör. A→B ve B→A için iki farklı
-- conversation id). Bir mesaj gönderildiğinde bu iki conversation id'sine de
-- birer public.messages satırı ekleniyor (aynı gönderen, aynı içerik, aynı
-- created_at mikrosaniyesi). notify_new_message_push() trigger'ı her
-- messages INSERT'inde bir notifications satırı ürettiği için tek mesaj
-- gönderiminde İKİ notifications satırı (farklı entity_id=conversation_id
-- taşıyan) oluşuyor. Var olan trg_dedup_notification / dedup_notification()
-- yalnızca (user_id, entity_id, type) eşleşmesinde eski kaydı sildiği için
-- bu iki satırı YAKALAMIYOR (entity_id'ler farklı). Her iki notifications
-- satırı da notification_outbox'a düşüp bağımsız FCM push'una dönüşüyor ->
-- cihaza aynı mesaj için iki push bildirimi gidiyor.
--
-- ÇÖZÜM (yalnızca veritabanı tarafı; istemci kodu değişmedi):
-- notify_new_message_push() içine, INSERT'ten önce aynı alıcı + aynı
-- gönderen + aynı içerik için son 5 saniye içinde zaten bir 'message'
-- bildirimi oluşturulup oluşturulmadığını kontrol eden bir muhafız eklendi
-- (entity_id'den bağımsız). Varsa yeni satır eklenmez; push tekrarlanmaz.
-- Kullanıcının 5 saniye arayla aynı metni iki kez elle yazıp göndermesi son
-- derece nadir olduğundan bu pencere güvenlidir (share_post_with_user'daki
-- 60 saniyelik idempotency deseniyle aynı yaklaşım).
--
-- Mesajın kendisi (public.messages) ve mevcut aynalı conversation satırları
-- bilerek DEĞİŞTİRİLMEDİ: uygulamanın sohbet listesi/okundu mantığı bu
-- ikili yapıya bağlı olabilir; burada yalnızca çift PUSH belirtisi
-- gideriliyor.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.notify_new_message_push()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
    v_sender_name TEXT;
    v_receiver_id UUID;
    v_conversation RECORD;
    v_content TEXT;
    v_recent_id UUID;
BEGIN
    -- Conversation bilgilerini al
    SELECT * INTO v_conversation
    FROM conversations
    WHERE id = NEW.conversation_id;

    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    -- Receiver ID belirle
    IF v_conversation.user_id = NEW.sender_id THEN
        v_receiver_id := v_conversation.other_user_id;
    ELSE
        v_receiver_id := v_conversation.user_id;
    END IF;

    v_content := CASE
        WHEN length(NEW.content) > 100 THEN substring(NEW.content, 1, 100) || '...'
        ELSE NEW.content
    END;

    -- Çift-yönlü (aynalı) conversation satırları yüzünden aynı mesajın iki
    -- kez INSERT edilmesi ihtimaline karşı: son 5 saniyede aynı alıcı +
    -- aynı gönderen + aynı içerikle zaten bir 'message' bildirimi
    -- oluşturulmuşsa (entity_id/conversation farklı olsa da) tekrar
    -- oluşturma; çift push'u burada durdur.
    SELECT n.id
      INTO v_recent_id
      FROM notifications n
     WHERE n.user_id = v_receiver_id
       AND n.actor_id = NEW.sender_id
       AND n.type = 'message'
       AND n.content = v_content
       AND n.created_at > NOW() - INTERVAL '5 seconds'
     LIMIT 1;

    IF v_recent_id IS NOT NULL THEN
        RETURN NEW;
    END IF;

    -- Sender ismini al
    SELECT COALESCE(full_name, username, 'Birisi') INTO v_sender_name
    FROM profiles
    WHERE id = NEW.sender_id;

    -- Notifications tablosuna ekle (outbox trigger otomatik push gonderir)
    BEGIN
        INSERT INTO notifications (
            user_id,
            type,
            title,
            content,
            actor_id,
            actor_name,
            entity_id,
            is_read
        ) VALUES (
            v_receiver_id,
            'message',
            v_sender_name,
            v_content,
            NEW.sender_id,
            v_sender_name,
            NEW.conversation_id::text,
            FALSE
        );
    EXCEPTION WHEN OTHERS THEN
        -- Notifications INSERT basarisiz olsa bile mesaj gonderimi basarili olsun
        RAISE LOG 'Notification INSERT failed: %', SQLERRM;
    END;

    RETURN NEW;
END;
$function$;
