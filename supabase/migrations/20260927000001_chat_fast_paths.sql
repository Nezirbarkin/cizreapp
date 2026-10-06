-- =============================================================================
-- Sohbet hızlı yolları (Görev 1.2) + mesaj gönderme kimlik doğrulaması
--
-- SORUN: Sohbet listesi 4, konuşma ekranı 3 ARDIŞIK HTTP isteğiyle açılıyordu
-- (her tur mobilde 250–500 ms). Liste yalnızca son mesajı bulmak için tüm
-- konuşmaların TÜM mesajlarını çekiyor, konuşma ekranı tüm geçmişi (posta kutusu
-- modelinde her mesaj İKİ satır) sayfalamasız indiriyordu. Sunucu sorguları ise
-- hızlıydı (canlıda en yoğun kullanıcı: 3–24 ms) — darboğaz tur sayısıydı.
--
-- ÇÖZÜM: İki okuma RPC'si, her ekran TEK turda:
--   * get_my_conversations()        → ChatService.getConversations'ın birebir
--                                      sunucu karşılığı (liste satırları)
--   * get_conversation_messages(...) → ChatService.getMessages'ın sayfalı
--                                      karşılığı (en yeniden eskiye)
-- İkisi de SECURITY INVOKER: mevcut RLS (conversations_select_merged,
-- messages_select_merged) aynen geçerli; yeni bir yetki yüzeyi açılmaz.
--
-- GÜVENLİK (aynı göçte, kullanıcı kararı):
--   * send_message_with_recipient SECURITY DEFINER olduğu hâlde gönderen
--     kimliğini (p_sender_id) istemciden alıp doğrulamıyordu: bir konuşmanın
--     tarafı, karşı taraf ADINA mesaj üretebiliyordu. Gövde aynen korunup başa
--     "gönderen = çağıran" kontrolü eklendi. Uygulama onu zaten kendi
--     auth.uid()'siyle çağırıyor (SQL/cron/edge çağıranı yok) → davranış aynı.
--   * mark_sender_messages_read(uuid, uuid): okuyucu kimliğini istemciden
--     alıyordu ve uygulamada artık hiç çağrılmıyor → istemci yetkisi kaldırıldı.
--
-- Uygulama: supabase db query --linked --file <bu dosya>  (db push KULLANMA)
-- Test:     supabase db query --linked --file supabase/tests/manual/chat_fast_paths_test.sql
-- =============================================================================

BEGIN;

-- -----------------------------------------------------------------------------
-- 1) Sohbet listesi — tek tur
--
-- Mantık (ChatService.getConversations ile aynı):
--   * Görünür satırlar: benim satırlarım + karşı tarafın bana dönük satırları;
--     yumuşak silme yalnız BENİM için süzülür.
--   * Partner başına tek satır: kendi satırım varsa o, yoksa karşı tarafınki
--     (kimlik alanları her zaman user_id=ben, other_user_id=partner).
--   * Son mesaj iki satırın (benimki + partnerinki) mesajlarının en yenisi.
--     Son mesaj BENİMSE "okundu" bilgisi yalnız partner kopyasından gelir
--     (kendi kopyamda is_read hep true'dur, anlamsızdır). Gelen mesajda true.
--   * Profil public_profiles_chat'ten (çevrimiçi/son görülme sunucuda maskeli).
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_my_conversations()
RETURNS TABLE (
  id                 uuid,
  user_id            uuid,
  other_user_id      uuid,
  last_message       text,
  last_message_time  timestamptz,
  unread_count       integer,
  created_at         timestamptz,
  updated_at         timestamptz,
  other_user         jsonb,
  last_message_by_me boolean,
  last_message_read  boolean
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH visible AS (
    SELECT c.id, c.last_message, c.last_message_time, c.unread_count,
           c.created_at, c.updated_at,
           c.user_id = v_uid AS is_mine,
           CASE WHEN c.user_id = v_uid THEN c.other_user_id ELSE c.user_id END
             AS partner_id
      FROM public.conversations c
     WHERE (c.user_id = v_uid OR c.other_user_id = v_uid)
       AND (c.deleted_for_user_id IS NULL OR c.deleted_for_user_id <> v_uid)
  ),
  chosen AS (
    SELECT DISTINCT ON (v.partner_id) v.*
      FROM visible v
     ORDER BY v.partner_id, v.is_mine DESC
  ),
  reverse_conv AS (
    SELECT v.partner_id, v.id AS conv_id
      FROM visible v
     WHERE NOT v.is_mine
  ),
  newest AS (
    SELECT DISTINCT ON (ch.partner_id)
           ch.partner_id, m.sender_id, m.content, m.created_at
      FROM chosen ch
      LEFT JOIN reverse_conv rc ON rc.partner_id = ch.partner_id
      JOIN public.messages m
        ON m.conversation_id IN (ch.id, rc.conv_id)
       AND (m.deleted_for_user_id IS NULL OR m.deleted_for_user_id <> v_uid)
     ORDER BY ch.partner_id, m.created_at DESC
  )
  SELECT ch.id,
         v_uid,
         ch.partner_id,
         COALESCE(n.content, ch.last_message),
         COALESCE(n.created_at, ch.last_message_time),
         COALESCE(ch.unread_count, 0),
         ch.created_at,
         ch.updated_at,
         (SELECT to_jsonb(p)
            FROM (SELECT pp.id, pp.full_name, pp.username, pp.avatar_url,
                         pp.is_online, pp.last_seen
                    FROM public.public_profiles_chat pp
                   WHERE pp.id = ch.partner_id) p),
         COALESCE(n.sender_id = v_uid, false),
         CASE
           WHEN n.sender_id IS NULL THEN false
           WHEN n.sender_id <> v_uid THEN true
           ELSE COALESCE((
             SELECT pm.is_read
               FROM reverse_conv rc2
               JOIN public.messages pm ON pm.conversation_id = rc2.conv_id
              WHERE rc2.partner_id = ch.partner_id
                AND rc2.conv_id <> ch.id
                AND pm.sender_id = v_uid
                AND pm.content IS NOT DISTINCT FROM n.content
                AND pm.created_at = n.created_at
                AND (pm.deleted_for_user_id IS NULL
                     OR pm.deleted_for_user_id <> v_uid)
              LIMIT 1), false)
         END
    FROM chosen ch
    LEFT JOIN newest n ON n.partner_id = ch.partner_id
   ORDER BY ch.updated_at DESC;
END;
$$;

-- -----------------------------------------------------------------------------
-- 2) Konuşma mesajları — tek tur, sayfalı (en yeniden eskiye)
--
-- Mantık (ChatService.getMessages ile aynı):
--   * Posta kutusu modelinde her mesaj iki satırdır (benim konuşmamda +
--     partnerinkinde; aynı sender_id|content|created_at, FARKLI id). İki kopya
--     tek mesaja indirgenir; temel alınan satır benim kopyamdır (id sabit kalır,
--     realtime INSERT ile eşleşir).
--   * Benim mesajım: "okundu" yalnız partner kopyasından. Gelen mesaj: benim
--     kopyam, yoksa eldeki kopya.
--   * p_before verilirse yalnız ondan ESKİ mesajlar (önceki sayfa).
--   * Satırlar to_jsonb(mesaj): messages'a eklenecek yeni sütunlar (ör. Görev
--     3.1'deki message_type) otomatik taşınır.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.get_conversation_messages(
  p_conversation_id uuid,
  p_before          timestamptz DEFAULT NULL,
  p_limit           integer     DEFAULT 40
)
RETURNS SETOF jsonb
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
SET search_path = ''
AS $$
DECLARE
  v_uid          uuid := auth.uid();
  v_owner        uuid;
  v_other        uuid;
  v_partner_conv uuid;
  v_limit        integer := LEAST(GREATEST(COALESCE(p_limit, 40), 1), 100);
BEGIN
  IF v_uid IS NULL OR p_conversation_id IS NULL THEN
    RETURN;
  END IF;

  SELECT c.user_id, c.other_user_id INTO v_owner, v_other
    FROM public.conversations c
   WHERE c.id = p_conversation_id;
  IF v_owner IS NULL THEN
    RETURN;  -- yok ya da RLS gereği bu kullanıcıya görünmüyor
  END IF;

  SELECT c.id INTO v_partner_conv
    FROM public.conversations c
   WHERE c.user_id = v_other
     AND c.other_user_id = v_owner
   LIMIT 1;

  RETURN QUERY
  WITH copies AS (
    SELECT m.*, (m.conversation_id = p_conversation_id) AS is_my_copy
      FROM public.messages m
     WHERE m.conversation_id IN (p_conversation_id, v_partner_conv)
       AND (m.deleted_for_user_id IS NULL OR m.deleted_for_user_id <> v_uid)
       AND (p_before IS NULL OR m.created_at < p_before)
  ),
  logical AS (
    SELECT c.sender_id, c.content, c.created_at,
           bool_or(c.is_read) FILTER (WHERE c.is_my_copy)     AS my_read,
           bool_or(c.is_read) FILTER (WHERE NOT c.is_my_copy) AS partner_read
      FROM copies c
     GROUP BY c.sender_id, c.content, c.created_at
     ORDER BY c.created_at DESC
     LIMIT v_limit
  ),
  base AS (
    SELECT DISTINCT ON (c.sender_id, c.content, c.created_at)
           c.*, l.my_read, l.partner_read
      FROM copies c
      JOIN logical l
        ON l.sender_id = c.sender_id
       AND l.content IS NOT DISTINCT FROM c.content
       AND l.created_at = c.created_at
     ORDER BY c.sender_id, c.content, c.created_at, c.is_my_copy DESC
  )
  SELECT (to_jsonb(b) - 'is_my_copy' - 'my_read' - 'partner_read')
         || jsonb_build_object(
              'is_read',
              CASE WHEN b.sender_id = v_uid
                   THEN COALESCE(b.partner_read, false)
                   ELSE COALESCE(b.my_read, b.is_read, false)
              END)
    FROM base b
   ORDER BY b.created_at DESC;
END;
$$;

-- Sayfalı okuma için: konuşma içinde tarihe göre ters sıralı erişim.
CREATE INDEX IF NOT EXISTS idx_messages_conversation_created
  ON public.messages (conversation_id, created_at DESC);

REVOKE ALL ON FUNCTION public.get_my_conversations() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.get_conversation_messages(uuid, timestamptz, integer)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.get_my_conversations() TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_conversation_messages(uuid, timestamptz, integer)
  TO authenticated;

-- -----------------------------------------------------------------------------
-- 3) Güvenlik: gönderen = çağıran
--
-- Gövde canlıdaki tanımla birebir aynıdır; yalnızca en baştaki kontrol eklendi.
-- service_role (sunucu tarafı araçlar) muaf tutulur.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.send_message_with_recipient(
  p_conversation_id uuid,
  p_content text,
  p_sender_id uuid,
  p_reply_to_id uuid DEFAULT NULL::uuid,
  p_reply_to_content text DEFAULT NULL::text,
  p_reply_to_sender_name text DEFAULT NULL::text
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
  reply_to_sender_name text
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
    INSERT INTO messages (conversation_id, sender_id, content, is_read, created_at, updated_at, reply_to_id, reply_to_content, reply_to_sender_name)
    VALUES (p_conversation_id, p_sender_id, p_content, TRUE, v_now, v_now, p_reply_to_id, p_reply_to_content, p_reply_to_sender_name)
    RETURNING id INTO v_new_message_id;

    -- 2) Alıcının kopyası (is_read=FALSE) → trigger: alıcı conv unread += 1
    INSERT INTO messages (conversation_id, sender_id, content, is_read, created_at, updated_at, reply_to_id, reply_to_content, reply_to_sender_name)
    VALUES (v_recipient_conv_id, p_sender_id, p_content, FALSE, v_now, v_now, p_reply_to_id, p_reply_to_content, p_reply_to_sender_name)
    RETURNING id INTO v_recipient_message_id;

    RETURN QUERY
    SELECT
        v_new_message_id,
        p_sender_id,
        v_recipient_id,
        v_recipient_message_id,
        p_content,
        p_conversation_id,
        v_now,
        v_now,
        FALSE,
        p_reply_to_id,
        p_reply_to_content,
        p_reply_to_sender_name;
END;
$function$;

-- Okuyucu kimliğini istemciden alıyordu; uygulamada artık çağrılmıyor.
REVOKE ALL ON FUNCTION public.mark_sender_messages_read(uuid, uuid)
  FROM PUBLIC, anon, authenticated;

COMMIT;

NOTIFY pgrst, 'reload schema';
