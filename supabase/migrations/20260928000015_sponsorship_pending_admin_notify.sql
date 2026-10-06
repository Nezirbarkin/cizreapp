-- =============================================================================
-- Görev 4.2 — Onay bekleyen öne çıkarma başvurusunda yöneticilere bildirim
-- =============================================================================
--
-- `sponsorship_requires_approval` açıkken satıcının satın aldığı öne çıkarma
-- 'pending' olarak bekler (ücret alınmış durumdadır). Yönetici bundan haberdar
-- olmazsa satıcı süresiz bekler; bu yüzden her yöneticiye in-app bildirim
-- (notifications INSERT'i mevcut outbox tetikleyicisiyle push'a da düşer)
-- gider. Kalıp `notify_admin_on_new_ilan` ile aynıdır ('admin_notification',
-- metadata.admin_section = admin panelindeki menü adı).
--
-- Onay gerekmeden hemen yayına giren satın alımlar bildirim üretmez.

BEGIN;

CREATE OR REPLACE FUNCTION private.notify_admins_sponsorship_pending()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = ''
AS $fn$
DECLARE
  v_shop_name text;
  v_buyer_name text;
  v_content text;
BEGIN
  IF NEW.status IS DISTINCT FROM 'pending' THEN
    RETURN NEW;
  END IF;

  SELECT s.name INTO v_shop_name FROM public.shops s WHERE s.id = NEW.shop_id;
  SELECT COALESCE(NULLIF(btrim(p.full_name), ''), NULLIF(btrim(p.username), ''))
    INTO v_buyer_name
    FROM public.profiles p
   WHERE p.id = NEW.created_by;

  v_content := format(
    '%s, %s vitrini için "%s" (%s gün, %s TL) öne çıkarma satın aldı; onayınızı bekliyor. '
    'Admin paneli › Öne Çıkarma › Başvurular.',
    COALESCE(v_shop_name, 'Bir mağaza'),
    private.sponsorship_placement_label(NEW.placement),
    NEW.package_name,
    NEW.duration_days,
    NEW.price_paid
  );

  INSERT INTO public.notifications (
    user_id, type, title, content, actor_id, actor_name,
    entity_id, entity_type, metadata, is_read, created_at
  )
  SELECT
    p.id,
    'admin_notification',
    'Öne çıkarma onay bekliyor',
    v_content,
    NEW.created_by,
    COALESCE(v_buyer_name, v_shop_name, 'Bir satıcı'),
    NEW.id::text,
    'shop_sponsorship',
    jsonb_build_object(
      'route', '/admin',
      'admin_section', 'Öne Çıkarma',
      'sponsorship_id', NEW.id,
      'shop_id', NEW.shop_id,
      'placement', NEW.placement
    ),
    false,
    now()
  FROM public.profiles p
  WHERE (p.role::text = 'admin' OR COALESCE(p.is_admin, false))
    AND p.id IS DISTINCT FROM NEW.created_by;

  RETURN NEW;
END;
$fn$;

REVOKE ALL ON FUNCTION private.notify_admins_sponsorship_pending() FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION private.notify_admins_sponsorship_pending() IS
  'Görev 4.2: onay bekleyen (pending) öne çıkarma eklenince her yöneticiye admin_notification yazar.';

DROP TRIGGER IF EXISTS trg_notify_admins_sponsorship_pending ON public.shop_sponsorships;
CREATE TRIGGER trg_notify_admins_sponsorship_pending
AFTER INSERT ON public.shop_sponsorships
FOR EACH ROW
WHEN (NEW.status = 'pending')
EXECUTE FUNCTION private.notify_admins_sponsorship_pending();

COMMIT;
