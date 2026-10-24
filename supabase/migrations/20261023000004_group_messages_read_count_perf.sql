-- ============================================================================
-- Grup mesajları + okundu sayısı: verimli ve sınırlı sürüm (2026-10-23)
-- ----------------------------------------------------------------------------
-- get_group_messages_with_read_count(p_group_id) her çağrıda TÜM
-- group_message_read_receipts tablosunu (bütün gruplar) GROUP BY ile
-- topluyor, grubun tüm mesaj geçmişini sınırsız döndürüyordu; istemci de bunu
-- her realtime olayında yeniden çağırıyordu.
--
-- * Tek parametreli sürüm (eski uygulama sürümleri çağırıyor) aynı sonucu
--   döndürmeye devam eder; okundu sayısı artık yalnız o grubun mesajları için
--   indeksten (message_id) sayılır.
-- * Yeni iki parametreli aşırı yükleme: son [p_limit] mesaj (eskiden yeniye
--   sıralı döner). Yeni istemci bunu çağırır.
-- Her ikisi de INVOKER: group_messages RLS'i (üyelik) aynen geçerli.
-- ============================================================================
BEGIN;

CREATE OR REPLACE FUNCTION public.get_group_messages_with_read_count(p_group_id uuid)
RETURNS TABLE(
  id uuid, group_id uuid, sender_id uuid, content text,
  created_at timestamp with time zone, updated_at timestamp with time zone,
  reply_to_id uuid, read_by_count integer,
  reply_to_content text, reply_to_sender_name text
)
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
BEGIN
  RETURN QUERY
  SELECT
    gm.id,
    gm.group_id,
    gm.sender_id,
    gm.content,
    gm.created_at,
    gm.updated_at,
    gm.reply_to_id,
    (SELECT COUNT(*)::integer
       FROM group_message_read_receipts r
      WHERE r.message_id = gm.id) AS read_by_count,
    COALESCE(rm.content, '') AS reply_to_content,
    COALESCE(p.full_name, '') AS reply_to_sender_name
  FROM group_messages gm
  LEFT JOIN group_messages rm ON rm.id = gm.reply_to_id
  LEFT JOIN profiles p ON p.id = rm.sender_id
  WHERE gm.group_id = p_group_id
  ORDER BY gm.created_at ASC;
END;
$function$;

CREATE OR REPLACE FUNCTION public.get_group_messages_with_read_count(
  p_group_id uuid,
  p_limit integer
)
RETURNS TABLE(
  id uuid, group_id uuid, sender_id uuid, content text,
  created_at timestamp with time zone, updated_at timestamp with time zone,
  reply_to_id uuid, read_by_count integer,
  reply_to_content text, reply_to_sender_name text
)
LANGUAGE plpgsql
SET search_path TO 'public'
AS $function$
DECLARE
  v_limit integer := LEAST(GREATEST(COALESCE(p_limit, 100), 1), 500);
BEGIN
  RETURN QUERY
  SELECT
    last_n.id,
    last_n.group_id,
    last_n.sender_id,
    last_n.content,
    last_n.created_at,
    last_n.updated_at,
    last_n.reply_to_id,
    (SELECT COUNT(*)::integer
       FROM group_message_read_receipts r
      WHERE r.message_id = last_n.id) AS read_by_count,
    COALESCE(rm.content, '') AS reply_to_content,
    COALESCE(p.full_name, '') AS reply_to_sender_name
  FROM (
    -- Son N mesaj (idx_group_messages_group_id: group_id, created_at DESC)
    SELECT gm.*
      FROM group_messages gm
     WHERE gm.group_id = p_group_id
     ORDER BY gm.created_at DESC
     LIMIT v_limit
  ) last_n
  LEFT JOIN group_messages rm ON rm.id = last_n.reply_to_id
  LEFT JOIN profiles p ON p.id = rm.sender_id
  ORDER BY last_n.created_at ASC;
END;
$function$;

GRANT EXECUTE ON FUNCTION public.get_group_messages_with_read_count(uuid, integer)
  TO authenticated, service_role;

COMMIT;

NOTIFY pgrst, 'reload schema';
