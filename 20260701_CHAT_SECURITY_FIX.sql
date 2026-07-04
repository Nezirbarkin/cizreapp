-- ============================================================================
-- SECURITY FIX: REVOKE EXECUTE FROM anon for all SECURITY DEFINER functions
-- Supabase linter 0028 uyarilarini giderir.
-- Tüm SECURITY DEFINER fonksiyonlarina anon erisimi engellenir.
-- ============================================================================

-- 1) ESKI FONKSIYONLAR - tamamen REVOKE
REVOKE ALL ON FUNCTION public.delete_conversation_with_partner(UUID) FROM anon;
REVOKE ALL ON FUNCTION public.delete_conversation_with_partner(UUID) FROM authenticated;

-- 2) CHAT FONKSIYONLARI - authenticated disinda tum rollerden REVOKE
REVOKE ALL ON FUNCTION public.delete_conversation_for_user(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_sender_messages_read(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.mark_messages_as_read(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_conversation_on_message() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.notify_direct_message() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.replicate_message_to_recipient() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ensure_online_status() FROM PUBLIC;

-- 3) YENIDEN GRANT - sadece authenticated ve service_role icin
GRANT EXECUTE ON FUNCTION public.delete_conversation_for_user(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_sender_messages_read(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_messages_as_read(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_conversation_on_message() TO authenticated;
GRANT EXECUTE ON FUNCTION public.notify_direct_message() TO authenticated;
GRANT EXECUTE ON FUNCTION public.replicate_message_to_recipient() TO authenticated;
GRANT EXECUTE ON FUNCTION public.ensure_online_status() TO authenticated;

-- 4) OKUMA FONKSIYONLARI - (varsa) sadece okuma icin
REVOKE ALL ON FUNCTION public.get_message_read_count(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.get_message_read_receipts(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_message_read_count(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.get_message_read_receipts(UUID) TO authenticated;

-- 5) NOTIFICATION/SYNC FONKSIYONLARI
REVOKE ALL ON FUNCTION public.sync_assigned_courier_to_order() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.sync_assigned_courier_to_order() TO authenticated;

-- 6) GRUOP CHAT FONKSIYONLARI
REVOKE ALL ON FUNCTION public.mark_group_messages_read_receipts(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_group_messages_read_receipts(UUID) TO authenticated;

-- 7) AUTH/OTP FONKSIYONLARI (bunlar anon olmali - kullanici kayit/giris icin)
-- verify_password_reset_otp ve verify_registration_otp anon kalmali (sistem icin lazim)

DO $$
BEGIN
    RAISE NOTICE 'SECURITY FIX TAMAMLANDI: anon erisimi engellendi';
END $$;