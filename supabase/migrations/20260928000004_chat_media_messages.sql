-- =============================================================================
-- 20260928000004_chat_media_messages.sql
-- -----------------------------------------------------------------------------
-- Görev 3.1 — Sohbette fotoğraf ve konum mesajları.
--
-- ## Veri
--
-- `messages.message_type` ('text' | 'image' | 'location', varsayılan 'text')
-- ve türe özgü `messages.attachment` (jsonb):
--   image    → {"path": "<gönderen>/<alıcı>/<uuid>.jpg", "w": 1080, "h": 1440, "caption": "..."}
--   location → {"lat": 37.3256, "lng": 42.1920, "label": "Ali Bey, Temiz Sk. ..."}
-- Tür/ek uyumu tablo CHECK'iyle korunur (NULL'a düşen ifade CHECK'i GEÇER; bu
-- yüzden her dal COALESCE(..., false) içinde).
--
-- `content` NOT NULL kalır ve ÖNİZLEME METNİDİR: sohbet listesi, bildirim ve
-- henüz güncellenmemiş uygulama sürümleri bunu gösterir ("📷 Fotoğraf",
-- "📍 Konum: <adres>"). Paylaşılan gönderi/ilan kartları eskisi gibi 'text'
-- türünde içerik önekiyle (SHARED_POST: / SHARED_ILAN:) gelir.
--
-- ## Fotoğraflar: özel `chat_attachments` kovası
--
-- Kova zaten vardı (özel, politikasız, kullanılmıyordu). Yol
-- `<gönderen>/<alıcı>/<uuid>.<uzantı>`: yalnız GÖNDEREN kendi klasörüne
-- yükler; yalnız iki TARAF okur (istemci imzalı adresle gösterir). Herkese
-- açık adres YOK — sohbet fotoğrafı bağlantıyla dolaşamaz.
--
-- ## Gönderim RPC'si
--
-- `send_message_with_recipient` iki yeni isteğe bağlı parametre alır
-- (`p_message_type`, `p_attachment`). İmza değiştiği için DROP + CREATE;
-- eski sürüm istemcilerin 6 adlı parametreli çağrısı varsayılanlarla aynen
-- çalışır. "Gönderen = çağıran" denetimi (20260927000001) korunur. Fotoğrafta
-- yolun gönderen/alıcı klasörü ve dosyanın gerçekten yüklenmiş olması
-- sunucuda denetlenir: başkasının dosyasına işaret eden mesaj üretilemez.
-- =============================================================================

BEGIN;

SET LOCAL lock_timeout = '10s';

-- -----------------------------------------------------------------------------
-- 1) Mesaj türü ve ek veri
-- -----------------------------------------------------------------------------
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS message_type text NOT NULL DEFAULT 'text';
ALTER TABLE public.messages
  ADD COLUMN IF NOT EXISTS attachment jsonb;

COMMENT ON COLUMN public.messages.message_type IS
  'Mesaj türü: text | image | location (Görev 3.1). content her türde önizleme metnidir.';
COMMENT ON COLUMN public.messages.attachment IS
  'Türe özgü veri. image: {path, w, h, caption?} (chat_attachments kovası); '
  'location: {lat, lng, label?}. text: NULL.';

ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_message_type_check;
ALTER TABLE public.messages ADD CONSTRAINT messages_message_type_check
  CHECK (message_type IN ('text', 'image', 'location'));

ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_attachment_shape_check;
ALTER TABLE public.messages ADD CONSTRAINT messages_attachment_shape_check
  CHECK (
    COALESCE(
      CASE message_type
        WHEN 'text' THEN attachment IS NULL
        WHEN 'image' THEN
          jsonb_typeof(attachment -> 'path') = 'string'
          AND (attachment ->> 'path')
              ~ '^[0-9a-f-]{36}/[0-9a-f-]{36}/[0-9a-f-]{36}[.](jpg|png|webp|gif)$'
        WHEN 'location' THEN
          CASE
            WHEN jsonb_typeof(attachment -> 'lat') = 'number'
             AND jsonb_typeof(attachment -> 'lng') = 'number'
            THEN (attachment ->> 'lat')::double precision BETWEEN -90 AND 90
             AND (attachment ->> 'lng')::double precision BETWEEN -180 AND 180
            ELSE false
          END
        ELSE false
      END,
      false
    )
  );

-- Ek veri küçük kalır (başlık/adres metni dahil); tabloya blob gömülemez.
ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_attachment_size_check;
ALTER TABLE public.messages ADD CONSTRAINT messages_attachment_size_check
  CHECK (attachment IS NULL OR octet_length(attachment::text) <= 2048);

-- -----------------------------------------------------------------------------
-- 2) Gönderim RPC'si — tür ve ek veri
-- -----------------------------------------------------------------------------
DROP FUNCTION IF EXISTS public.send_message_with_recipient(uuid, text, uuid, uuid, text, text);

CREATE OR REPLACE FUNCTION public.send_message_with_recipient(
  p_conversation_id uuid,
  p_content text,
  p_sender_id uuid,
  p_reply_to_id uuid DEFAULT NULL::uuid,
  p_reply_to_content text DEFAULT NULL::text,
  p_reply_to_sender_name text DEFAULT NULL::text,
  p_message_type text DEFAULT 'text'::text,
  p_attachment jsonb DEFAULT NULL::jsonb
)
RETURNS TABLE(
  message_id uuid,
  sender_id uuid,
  recipient_id uuid,
  recipient_message_id uuid,
  content text,
  conversation_id uuid,
  created_at timestamp with time zone,
  updated_at timestamp with time zone,
  is_read boolean,
  reply_to_id uuid,
  reply_to_content text,
  reply_to_sender_name text,
  message_type text,
  attachment jsonb
)
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

    -- Alıcı conv'u yoksa oluştur (unread=0; trigger row2'de +1 yapacak)
    IF v_recipient_conv_id IS NULL THEN
        INSERT INTO conversations (user_id, other_user_id, unread_count, created_at, updated_at)
        VALUES (v_recipient_id, p_sender_id, 0, v_now, v_now)
        RETURNING id INTO v_recipient_conv_id;
    END IF;

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

REVOKE ALL ON FUNCTION public.send_message_with_recipient(uuid, text, uuid, uuid, text, text, text, jsonb)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.send_message_with_recipient(uuid, text, uuid, uuid, text, text, text, jsonb)
  TO authenticated, service_role;

-- -----------------------------------------------------------------------------
-- 3) Fotoğraf kovası: özel, 10 MB, yalnız görsel
-- -----------------------------------------------------------------------------
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'chat_attachments', 'chat_attachments', false, 10485760,
  ARRAY['image/jpeg', 'image/png', 'image/webp', 'image/gif']
)
ON CONFLICT (id) DO UPDATE
  SET public = EXCLUDED.public,
      file_size_limit = EXCLUDED.file_size_limit,
      allowed_mime_types = EXCLUDED.allowed_mime_types;

-- Yükleme: yalnız kendi klasörüne ve tam iki klasör derinliğinde
-- (<ben>/<alıcı>/<dosya>).
DROP POLICY IF EXISTS "chat_attachments_insert_own_folder" ON storage.objects;
CREATE POLICY "chat_attachments_insert_own_folder" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'chat_attachments'
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
    AND array_length(storage.foldername(name), 1) = 2
  );

-- Okuma (imzalı adres üretmek dahil): yalnız iki taraf.
DROP POLICY IF EXISTS "chat_attachments_select_participants" ON storage.objects;
CREATE POLICY "chat_attachments_select_participants" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'chat_attachments'
    AND (SELECT auth.uid())::text IN (
      (storage.foldername(name))[1],
      (storage.foldername(name))[2]
    )
  );

-- Silme: yalnız gönderen kendi dosyasını.
DROP POLICY IF EXISTS "chat_attachments_delete_own" ON storage.objects;
CREATE POLICY "chat_attachments_delete_own" ON storage.objects
  FOR DELETE TO authenticated
  USING (
    bucket_id = 'chat_attachments'
    AND (storage.foldername(name))[1] = (SELECT auth.uid())::text
  );

NOTIFY pgrst, 'reload schema';

COMMIT;
