-- ============================================================================
-- 20260709_MARK_READ_PARTNER_UNREAD_FIX.sql
-- ----------------------------------------------------------------------------
-- KÖK NEDEN: mark_messages_as_read RPC'sinin 4. adimi partner conversation'inin
-- unread_count'unu 0 yapiyordu. Bu yanlis: B mesaj atip ChatDetailScreen acinca
-- markMessagesAsRead(B_conv) cagriliyor, RPC A'nin conv'unun unread_count'unu
-- 0 yapiyor → A'nin rozeti saniyesinde sönüyor.
--
-- Dogru davranis: markMessagesAsRead yalnizca READER'in (cagiran kullanicinin)
-- kendi conversation'unun unread_count'unu 0 yapar. Partner'in conv'una
-- dokunmaz — partner mesajlari okumadigi icin unread_count kalmali.
--
-- AYRICA: 2. adim (partner conv'undaki mesajlarin is_read=true yapilmasi)
-- da sorunlu: bu, partner'in (A'nin) kendi conv'unda B'nin gonderdigi
-- mesajlari is_read=true yapar. Ama A bu mesajlari HENUZ okumadi! Bu da
-- okundu tiki (mavi tik) erken gostermeye yol acar. BU da kaldirilmali:
-- partner'in conv'unda is_read yalnizca partner (A) okudugunda degismeli.
--
-- COZUM: 2 ve 4. adimlari KALDIR. Sadece:
--   1) Reader'in conv'undaki partner mesajlarini is_read=true yap (OK - reader onlari okudu)
--   3) Reader'in conv'unun unread_count=0 yap (OK)
-- ============================================================================

BEGIN;

DROP FUNCTION IF EXISTS public.mark_messages_as_read(UUID);

CREATE OR REPLACE FUNCTION public.mark_messages_as_read(p_conversation_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
    v_reader UUID := auth.uid();
    v_reader_conv_owner UUID;
    v_partner_id UUID;
BEGIN
    IF v_reader IS NULL THEN
        RETURN;
    END IF;

    -- Bu conversation'un bilgilerini al
    SELECT user_id, other_user_id INTO v_reader_conv_owner, v_partner_id
    FROM conversations
    WHERE id = p_conversation_id;

    IF v_reader_conv_owner IS NULL OR v_partner_id IS NULL THEN
        RETURN;
    END IF;

    -- Sadece BU conversation'un sahibi (reader) ise devam et
    IF v_reader_conv_owner != v_reader THEN
        RETURN;
    END IF;

    -- 1) Reader'in kendi conv'undaki PARTNER mesajlarini okundu yap
    --    (Reader bunlari sohbet ekraninda gordu → is_read=true mantikli)
    UPDATE messages
    SET is_read = TRUE, updated_at = NOW()
    WHERE conversation_id = p_conversation_id
      AND sender_id = v_partner_id
      AND is_read = FALSE;

    -- 2) Reader'in unread_count'unu sifirla
    --    (Reader okudu → kendi conv'unda okunmamis yok)
    UPDATE conversations
    SET unread_count = 0, updated_at = NOW()
    WHERE id = p_conversation_id
      AND COALESCE(unread_count, 0) > 0;

    -- NOT: Partner conversation'ina DOKUNMUYORUZ.
    --   - Partner mesajlari partner'in conv'unda is_read=false kalir
    --     (partner onlari HENUZ okumadi; reader'in gormesi onlari okundu yapmaz)
    --   - Partner conversation'inin unread_count'u degismez
    --     (trigger, partner mesaj aldikca +1 yapar; partner sohbeti acinca
    --      kendi markMessagesAsRead cagrisi onu sifirlar)
    --
    -- Bu, mailbox modelinin dogru calismasini saglar: her kullanici yalnizca
    -- KENDI conv'unda kendi okuma durumunu yonetir.
END;
$function$;

-- Yetkiler
GRANT EXECUTE ON FUNCTION public.mark_messages_as_read(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.mark_messages_as_read(UUID) FROM anon;

COMMIT;


-- ============================================================================
-- DOĞRULAMA
-- ============================================================================

-- 1) Yeni govde
SELECT p.proname, pg_get_functiondef(p.oid) AS govde
FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE p.proname = 'mark_messages_as_read' AND n.nspname='public';

-- 2) Test: B'nin conv'u ile markMessagesAsRead cagir, A'nin conv'unun
--    unread_count DEGISMEDIGINI teyit et
-- (Önce A'nin conv'una manuel +1 ver, sonra markMessagesAsRead(B_conv) cagir,
--  A'nin conv'unun hala 1 kaldigini gor)
DO $$
BEGIN
    -- A'nin conv'una manuel unread ekleyelim (test icin)
    UPDATE conversations SET unread_count = 1, updated_at = NOW()
    WHERE id = '25db3803-9843-4960-a88a-3141e1e4a018';
    RAISE NOTICE 'A conv unread_count=1 yapildi (test)';
END $$;

SELECT 'TEST ONCESI A conv' AS adim,
       id, user_id, unread_count FROM conversations
WHERE id = '25db3803-9843-4960-a88a-3141e1e4a018';

-- B'nin conv'u ile markMessagesAsRead cagir (authenticated olarak)
DO $$
BEGIN
    SET LOCAL ROLE authenticated;
    PERFORM public.mark_messages_as_read('88457d84-43db-4492-94e5-2a5857701820');
    RAISE NOTICE 'mark_messages_as_read(B conv) cagrildi';
END $$;

SELECT 'TEST SONRASI A conv (hala 1 olmali!)' AS adim,
       id, user_id, unread_count FROM conversations
WHERE id = '25db3803-9843-4960-a88a-3141e1e4a018';

-- Beklenen: TEST SONRASI A conv unread_count=1 (DEGISMEMELI)
-- Eger 0 olduysa fix calismiyor demektir.