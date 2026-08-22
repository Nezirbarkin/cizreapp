-- =============================================================================
-- Yeni ilan geldiğinde tüm adminlere in-app + FCM push bildirimi
-- notifications INSERT'i mevcut notification_outbox trigger'ını çalıştırır.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.notify_admin_on_new_ilan()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_owner_name text;
  v_category_name text;
  v_content text;
BEGIN
  -- Adminin kendi oluşturduğu ilan için gereksiz bildirim üretme.
  IF public.ilan_is_admin() THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(NULLIF(btrim(p.full_name), ''), NULLIF(btrim(p.username), ''), 'Bir kullanıcı')
    INTO v_owner_name
  FROM public.profiles p
  WHERE p.id = NEW.owner_id;

  SELECT c.name INTO v_category_name
  FROM public.ilan_categories c
  WHERE c.id = NEW.category_id;

  v_content := format(
    '%s, %s kategorisinde yeni ilan gönderdi: %s',
    COALESCE(v_owner_name, 'Bir kullanıcı'),
    COALESCE(v_category_name, 'İlanlar'),
    left(NEW.title, 120)
  );

  INSERT INTO public.notifications (
    user_id, type, title, content, actor_id, actor_name,
    entity_id, entity_type, metadata, is_read, created_at
  )
  SELECT
    p.id,
    'admin_notification',
    CASE WHEN NEW.status = 'pending'
      THEN 'Yeni İlan Onay Bekliyor'
      ELSE 'Yeni İlan Yayınlandı'
    END,
    v_content,
    NEW.owner_id,
    COALESCE(v_owner_name, 'Bir kullanıcı'),
    NEW.id::text,
    'ilan',
    jsonb_build_object(
      'route', '/admin',
      'admin_section', 'İlanlar & Kategoriler',
      'ilan_id', NEW.id,
      'category_id', NEW.category_id,
      'status', NEW.status
    ),
    false,
    now()
  FROM public.profiles p
  WHERE p.role::text = 'admin' OR COALESCE(p.is_admin, false);

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_admin_on_new_ilan() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.notify_admin_on_new_ilan() TO service_role;

DROP TRIGGER IF EXISTS trg_notify_admin_on_new_ilan ON public.ilanlar;
CREATE TRIGGER trg_notify_admin_on_new_ilan
AFTER INSERT ON public.ilanlar
FOR EACH ROW EXECUTE FUNCTION public.notify_admin_on_new_ilan();

COMMENT ON FUNCTION public.notify_admin_on_new_ilan() IS
  'Yeni kullanıcı ilanını tüm adminlere notifications/outbox üzerinden bildirir.';

COMMIT;
