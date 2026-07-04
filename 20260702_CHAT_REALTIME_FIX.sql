-- ============================================================================
-- MIGRATION: 20260702_CHAT_REALTIME_FIX.sql
-- STATUS: ARTIK KULLANILMIYOR - 54001 HATASI NEDENIYLE
-- YERINE: 20260702_CHAT_REALTIME_FIX_V2.sql KULLANIN
-- ============================================================================
--
-- ESKI YAPI (HATALI):
--   - Bu dosya trigger iceinde messages tablosuna INSERT yapiyordu
--   - Bu sonsuz donguye yol aciyordu (54001 stack depth limit)
--
-- DOGRU COZUM:
--   - 20260702_CHAT_REALTIME_FIX_V2.sql dosyasini calistirin
--   - Bu dosya send_message_with_recipient() RPC kullaniyor
--   - RPC tek cagrida iki mesaj olusturur (gonderen + alici icin)
--
-- ============================================================================

-- Geri alma icin eski trigger fonksiyonunu sakla (pasif)
-- Bu fonksiyon artik KULLANILMIYOR

DO $$
BEGIN
    RAISE NOTICE '===========================================';
    RAISE NOTICE 'UYARI: 20260702_CHAT_REALTIME_FIX.sql KULLANIMDAN KALDIRILDI';
    RAISE NOTICE '   Bunun yerine 20260702_CHAT_REALTIME_FIX_V2.sql calistirin';
    RAISE NOTICE '===========================================';
END $$;

-- Trigger'i TAMAMEN KALDIR (soruna neden olmasi diye)
DROP TRIGGER IF EXISTS message_insert_trigger ON messages;
DROP FUNCTION IF EXISTS public.update_conversation_on_message();
