-- =============================================================================
-- Yeni havale (banka transferi) bildirimi geldiğinde tüm adminlere
-- in-app + FCM push bildirimi. notifications INSERT'i mevcut
-- notification_outbox trigger'ını çalıştırır (bkz. notify_admin_on_new_ilan
-- ile aynı desen).
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.notify_admin_on_new_transfer_confirmation()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_owner_name text;
  v_content text;
BEGIN
  SELECT COALESCE(NULLIF(btrim(p.full_name), ''), NULLIF(btrim(p.username), ''), 'Bir kullanıcı')
    INTO v_owner_name
  FROM public.profiles p
  WHERE p.id = NEW.user_id;

  v_content := format(
    '%s, ₺%s tutarında havale bildirimi gönderdi (gönderen: %s)',
    COALESCE(v_owner_name, 'Bir kullanıcı'),
    to_char(NEW.amount, 'FM999999990.00'),
    COALESCE(NULLIF(btrim(NEW.sender_full_name), ''), v_owner_name, 'Bilinmiyor')
  );

  INSERT INTO public.notifications (
    user_id, type, title, content, actor_id, actor_name,
    entity_id, entity_type, metadata, is_read, created_at
  )
  SELECT
    p.id,
    'admin_notification',
    'Yeni Havale Bildirimi 💸',
    v_content,
    NEW.user_id,
    COALESCE(v_owner_name, 'Bir kullanıcı'),
    NEW.id::text,
    'transfer_confirmation',
    jsonb_build_object(
      'route', '/admin',
      'admin_section', 'Bakiye Onayları',
      'transfer_confirmation_id', NEW.id,
      'amount', NEW.amount,
      'bank_account_id', NEW.bank_account_id,
      'status', NEW.status
    ),
    false,
    now()
  FROM public.profiles p
  WHERE p.role::text = 'admin' OR COALESCE(p.is_admin, false);

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_admin_on_new_transfer_confirmation() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.notify_admin_on_new_transfer_confirmation() TO service_role;

DROP TRIGGER IF EXISTS trg_notify_admin_on_new_transfer_confirmation ON public.transfer_confirmations;
CREATE TRIGGER trg_notify_admin_on_new_transfer_confirmation
AFTER INSERT ON public.transfer_confirmations
FOR EACH ROW
WHEN (NEW.status = 'pending')
EXECUTE FUNCTION public.notify_admin_on_new_transfer_confirmation();

COMMENT ON FUNCTION public.notify_admin_on_new_transfer_confirmation() IS
  'Yeni havale (banka transferi) bildirimini tüm adminlere notifications/outbox üzerinden bildirir.';

COMMIT;
