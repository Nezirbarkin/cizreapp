-- ============================================================================
-- ÇİFT BİLDİRİM SORUNU ÇÖZÜMÜ
-- Dart kodu zaten bildirim gönderiyor, SQL trigger'lar tekrar gönderiyor
-- Bu yüzden çift bildirim oluşuyor
-- ============================================================================

-- Sipariş bildirim trigger'larını kaldır (Dart kodu zaten gönderiyor)
DROP TRIGGER IF EXISTS notify_new_order_trigger ON public.orders;
DROP TRIGGER IF EXISTS notify_order_status_trigger ON public.orders;

-- Trigger fonksiyonlarını da kaldır
DROP FUNCTION IF EXISTS public.send_new_order_notification_trigger() CASCADE;
DROP FUNCTION IF EXISTS public.send_order_notification_trigger() CASCADE;

-- Doğrulama: kalan trigger'ları kontrol et
SELECT tgname, tgenabled 
FROM pg_trigger 
WHERE tgrelid IN (SELECT oid FROM pg_class WHERE relname = 'orders')
AND tgname LIKE '%notif%';