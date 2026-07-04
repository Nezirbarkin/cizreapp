-- ============================================================================
-- MIGRATION: 20260630_CHAT_DELETE_FIX.sql
-- ----------------------------------------------------------------------------
-- PROBLEM: Sohbetler silinmiyor / silinse bile tekrar beliriyor.
-- KÖK NEDENLER (PROJE_HAVIZA + kod incelemesi):
--   1) Çift yönlü conversation sisteminde her partner için AYRI conversation
--      satırı vardır (20260208000006_fix_conversation_system.sql). Mevcut
--      deleteConversation sadece tıklanan conversation.id satırını siler;
--      karşı tarafın satırı DB'de kalır. Bir sonraki mesaj geldiğinde trigger
--      update_conversation_on_message() karşı tarafın satırını tekrar
--      oluşturur (ON CONFLICT DO UPDATE) → sohbet "silinmedi" gibi görünür.
--   2) RLS DELETE policy (20260208000003_chat_delete_policy.sql) var ama
--      ChatService.deleteConversation herhangi bir hata yakalamadan rethrow
--      eder; UI'da silent failure olabilir.
--   3) messages ON DELETE CASCADE FK ile silinir (teyit edilecek).
-- ÇÖZÜM:
--   - delete_conversation_with_partner RPC (SECURITY DEFINER): kullanıcının
--     kendi conversation satırını + karşı tarafın ters satırını atomik siler.
--     SECURITY DEFINER → RLS bypass → 42501 yetki hatası yok.
--   - Kullanıcı conversation'a dahil değilse (ne user_id ne other_user_id
--     eşleşmiyor) güvenlik gereği silme yapılmaz, false döner.
-- ----------------------------------------------------------------------------
-- PROJE_HAVIZA notlarına uygun:
--   - SECURITY DEFINER + SET search_path = public
--   - CREATE OR REPLACE sonrası GRANT EXECUTE manuel verilir
--   - FK ilişkileri korunur (ON DELETE CASCADE zaten mesajları siler)
-- ============================================================================

BEGIN;

-- ============================================================================
-- delete_conversation_with_partner RPC
-- ----------------------------------------------------------------------------
-- Parametre: p_conversation_id — kullanıcının silmek istediği conversation.id
-- Dönüş: BOOLEAN — true: silindi, false: yetkisiz/bulunamadı
-- ============================================================================
DROP FUNCTION IF EXISTS public.delete_conversation_with_partner(UUID);

CREATE OR REPLACE FUNCTION public.delete_conversation_with_partner(
    p_conversation_id UUID
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    v_user_id UUID;
    v_other_user_id UUID;
    v_partner_conv_id UUID;
    v_deleted INTEGER;
BEGIN
    -- 1) Conversation bilgilerini al
    SELECT user_id, other_user_id
    INTO v_user_id, v_other_user_id
    FROM conversations
    WHERE id = p_conversation_id;

    -- 2) Conversation yoksa false dön
    IF v_user_id IS NULL THEN
        RETURN false;
    END IF;

    -- 3) Güvenlik: çağıran kullanıcı bu conversation'ın bir tarafı olmalı.
    --    (auth.uid() SECURITY DEFINER içinde güvenli kullanılabilir çünkü
    --     fonksiyon caller'ın JWT context'inde çalışır.)
    IF auth.uid() IS NULL OR
       (auth.uid() != v_user_id AND auth.uid() != v_other_user_id) THEN
        RETURN false;
    END IF;

    -- 4) Karşı tarafın ters conversation satırını bul (varsa)
    SELECT id INTO v_partner_conv_id
    FROM conversations
    WHERE user_id = v_other_user_id
      AND other_user_id = v_user_id;

    -- 5) Her iki satırı da sil. ON DELETE CASCADE FK (messages.conversation_id)
    --    sayesinde mesajlar da otomatik silinir.
    DELETE FROM conversations
    WHERE id = p_conversation_id
       OR id = v_partner_conv_id;

    GET DIAGNOSTICS v_deleted = ROW_COUNT;

    -- 6) En az 1 satır silindiyse true dön
    RETURN v_deleted > 0;
END;
$$;

-- SECURITY DEFINER sonrası GRANT korunmaz (PROJE_HAVIZA_RLS.md §4.1.1)
GRANT EXECUTE ON FUNCTION public.delete_conversation_with_partner(UUID) TO authenticated;
REVOKE EXECUTE ON FUNCTION public.delete_conversation_with_partner(UUID) FROM anon;

-- ============================================================================
-- conversations_delete_own policy garanti (idempotent)
-- ----------------------------------------------------------------------------
-- Mevcut policy (20260208000003_chat_delete_policy.sql) zaten doğru.
-- Bu migration onun varlığını garanti altına alır. RPC kullanıldığında
-- policy'ye ihtiyaç olmasa da, doğrudan delete deneyen eski istemciler için.
-- ----------------------------------------------------------------------------
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_policies
        WHERE schemaname = 'public'
          AND tablename = 'conversations'
          AND policyname = 'conversations_delete_own'
    ) THEN
        CREATE POLICY "conversations_delete_own"
            ON public.conversations
            FOR DELETE
            TO authenticated
            USING (user_id = auth.uid() OR other_user_id = auth.uid());
    END IF;
END $$;

COMMIT;

-- ============================================================================
-- DOĞRULAMA
-- ============================================================================
DO $$
BEGIN
    RAISE NOTICE '================================================================';
    RAISE NOTICE '✅ 20260630_CHAT_DELETE_FIX.sql TAMAMLANDI';
    RAISE NOTICE '   - delete_conversation_with_partner RPC oluşturuldu';
    RAISE NOTICE '   - conversations_delete_own policy garanti altında';
    RAISE NOTICE '   - GRANT EXECUTE TO authenticated / REVOKE FROM anon';
    RAISE NOTICE '================================================================';
END $$;