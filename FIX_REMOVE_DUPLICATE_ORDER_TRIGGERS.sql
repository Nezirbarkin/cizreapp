-- ============================================================================
-- DUPLİKE SİPARİŞ BİLDİRİMLERİNİ KALDIR - KESİN ÇÖZÜM
-- ============================================================================
-- Problem: SQL trigger ve Dart kodu aynı anda bildirim oluşturuyor
-- Çözüm: SQL trigger'ları tamamen kaldır, Dart tek kaynak olsun
-- ============================================================================

-- 1. Mevcut tüm sipariş bildirim trigger'larını kontrol et ve kaldır
DO $$
DECLARE
    trigger_record RECORD;
BEGIN
    -- orders tablosundaki tüm trigger'ları listele ve bildirim olanları kaldır
    FOR trigger_record IN 
        SELECT trigger_name 
        FROM information_schema.triggers 
        WHERE event_object_table = 'orders' 
        AND trigger_name LIKE '%notif%'
    LOOP
        EXECUTE format('DROP TRIGGER IF EXISTS %I ON public.orders', trigger_record.trigger_name);
        RAISE NOTICE 'Kaldırıldı: %', trigger_record.trigger_name;
    END LOOP;
END $$;

-- 2. notify_order_status fonksiyonunu kaldır (birden fazla versiyon olabilir)
DROP FUNCTION IF EXISTS public.notify_order_status_change() CASCADE;
DROP FUNCTION IF EXISTS public.notify_new_order() CASCADE;
DROP FUNCTION IF EXISTS public.send_order_notification_trigger() CASCADE;
DROP FUNCTION IF EXISTS public.send_new_order_notification_trigger() CASCADE;

-- 3. Dart kodunun gönderdiği bildirimlerle eski SQL trigger bildirimlerini temizle
-- Aynı entity_id (order_id) için birden fazla order_status/order_update olanları sil
-- En yeni olanı tut, eskilerini sil
DELETE FROM public.notifications n1
WHERE n1.type IN ('order_status', 'order_update')
AND EXISTS (
    SELECT 1 FROM public.notifications n2
    WHERE n2.entity_id = n1.entity_id
    AND n2.type = n1.type
    AND n2.created_at > n1.created_at
);

SELECT '✅ Duplike sipariş bildirim triggerları kaldırıldı' as result;
SELECT 'ℹ️ Dart kodu (OrderService._sendOrderStatusNotification) tek kaynak olarak bildirim gönderiyor' as info;
