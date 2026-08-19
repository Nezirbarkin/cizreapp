-- ============================================================================
-- Sohbet push'unu outbox pipeline'ına bağla (2026-08-14)
-- ----------------------------------------------------------------------------
-- SORUN: enqueue_notification_outbox_trigger (20260802000003) 'message' ve
-- 'chat' tiplerini outbox'a ALMIYORDU; bu tiplerin push'u
-- notify_direct_message trigger'ının send-push-notification edge function
-- çağrısına emanetti. O edge function aynı migration içinde
-- "decommissioned" edildi (410 Gone) — yani sohbet bildirimleri in-app
-- görünürken cihaz push'u Hİ�� gitmiyordu (her mesajta pg_net 410).

-- ÇÖZÜM:
--   1) enqueue_notification_outbox_trigger artık TÜM tipleri outbox'a alır.
--      Sohbet bildirimi de diğerleri gibi anlık poke + worker ile FCM'ye
--      gider (kullanıcı bildirim tercihi haricinde hiçbir filtre yok;
--      'message' tipi tercih haritasında yok → varsayılan açık).
--   2) Ölü notify_direct_message trigger + fonksiyonu kaldırılır. Fonksiyon
--      gövdesinde gömülü anon key de (pg_proc'dan) temizlenmiş olur.
--      notify_new_message_push (notifications satırını üreten) kalır.
--
-- NOT: trg_dedup_notification aynı konuşmadaki eski okunmamış 'message'
-- kaydını siler; outbox satırlarına dokunmadığı için her mesaj yine push
-- olur, in-app listede tek güncel kayıt kalır.
-- ============================================================================

-- 1) Outbox enqueue trigger'ı: tip istisnası yok
CREATE OR REPLACE FUNCTION public.enqueue_notification_outbox_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public.enqueue_notification_outbox(NEW.id);
  RETURN NEW;
END;
$$;

-- 2) Ölü sohbet push yolu (410'e çağıran trigger + gövdesinde anon key
--    taşıyan fonksiyon)
DROP TRIGGER IF EXISTS notify_direct_message_trigger ON public.messages;
DROP FUNCTION IF EXISTS public.notify_direct_message();
