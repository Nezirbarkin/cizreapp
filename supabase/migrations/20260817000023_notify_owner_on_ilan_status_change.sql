-- =============================================================================
-- İlan sahibine moderasyon kararı bildirimi (onaylandı/reddedildi/arşivlendi)
-- =============================================================================
-- KÖK NEDEN: notify_admin_on_new_ilan (20260817000008) sadece adminlere yeni
-- ilan bildirimi gönderiyor; ilan sahibi kendi ilanının admin tarafından
-- onaylandığını/reddedildiğini/arşivlendiğini öğrenmenin hiçbir yolu yoktu
-- (yalnızca ilan detayına tekrar girip status'ü kontrol edebiliyordu).
--
-- Bu trigger aynı deseni (notifications tablosuna INSERT, mevcut
-- notification_outbox trigger'ı push'u otomatik tetikler) AFTER UPDATE için
-- ve ilan sahibine bildirim gönderecek şekilde uygular.
--
-- Tetikleme sadece gerçek bir admin moderasyon kararında olur: validate_ilan_write()
-- (20260817000006_ilanlar_system.sql satır ~220-230) moderated_at/moderated_by'ı
-- SADECE admin published/rejected/archived durumuna geçiş yaptığında damgalıyor
-- — bu yüzden moderated_at değişimini güvenilir sinyal olarak kullanıyoruz.
-- =============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.notify_owner_on_ilan_status_change()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_actor_name text;
  v_title text;
  v_content text;
BEGIN
  -- Yalnızca gerçek bir admin moderasyon kararında bildir.
  IF NEW.moderated_at IS NOT DISTINCT FROM OLD.moderated_at THEN
    RETURN NEW;
  END IF;
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN
    RETURN NEW;
  END IF;
  IF NEW.status NOT IN ('published', 'rejected', 'archived') THEN
    RETURN NEW;
  END IF;
  -- Admin kendi ilanını modere ettiyse kendine bildirim üretme.
  IF NEW.moderated_by IS NOT NULL AND NEW.moderated_by = NEW.owner_id THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE(NULLIF(btrim(p.full_name), ''), NULLIF(btrim(p.username), ''), 'Yönetici')
    INTO v_actor_name
  FROM public.profiles p
  WHERE p.id = NEW.moderated_by;

  v_title := CASE NEW.status
    WHEN 'published' THEN 'İlanınız Yayınlandı'
    WHEN 'rejected' THEN 'İlanınız Reddedildi'
    WHEN 'archived' THEN 'İlanınız Arşivlendi'
  END;

  v_content := CASE NEW.status
    WHEN 'published' THEN format('"%s" ilanınız onaylanıp yayına alındı.', left(NEW.title, 120))
    WHEN 'rejected' THEN format(
      '"%s" ilanınız reddedildi.%s',
      left(NEW.title, 120),
      CASE WHEN NEW.rejection_reason IS NOT NULL AND btrim(NEW.rejection_reason) <> ''
        THEN ' Gerekçe: ' || left(NEW.rejection_reason, 300)
        ELSE ''
      END
    )
    WHEN 'archived' THEN format('"%s" ilanınız yayından kaldırılıp arşivlendi.', left(NEW.title, 120))
  END;

  INSERT INTO public.notifications (
    user_id, type, title, content, actor_id, actor_name,
    entity_id, entity_type, metadata, is_read, created_at
  ) VALUES (
    NEW.owner_id,
    'ilan_status_change',
    v_title,
    v_content,
    NEW.moderated_by,
    v_actor_name,
    NEW.id::text,
    'ilan',
    jsonb_build_object('ilan_id', NEW.id, 'status', NEW.status),
    false,
    now()
  );

  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION public.notify_owner_on_ilan_status_change() FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.notify_owner_on_ilan_status_change() TO service_role;

DROP TRIGGER IF EXISTS trg_notify_owner_on_ilan_status_change ON public.ilanlar;
CREATE TRIGGER trg_notify_owner_on_ilan_status_change
AFTER UPDATE ON public.ilanlar
FOR EACH ROW EXECUTE FUNCTION public.notify_owner_on_ilan_status_change();

COMMENT ON FUNCTION public.notify_owner_on_ilan_status_change() IS
  'Admin bir ilanı onaylayınca/reddedince/arşivleyince sahibine notifications/outbox üzerinden bildirir.';

COMMIT;

-- =============================================================================
-- DOĞRULAMA:
--   Admin panelinden bir ilanı yayınla/reddet/arşivle, ardından:
--   SELECT * FROM public.notifications
--   WHERE type = 'ilan_status_change'
--   ORDER BY created_at DESC LIMIT 1;
--   -- Beklenen: ilan sahibine ait yeni bir bildirim satırı.
--
--   SELECT tgname FROM pg_trigger WHERE tgrelid = 'public.ilanlar'::regclass;
--   -- Beklenen: trg_notify_owner_on_ilan_status_change listede görünmeli.
-- =============================================================================
