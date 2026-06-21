-- ============================================================================
-- SİPARİŞ ÇİFT BİLDİRİM TEMİZLEME - KESİN ÇÖZÜM
-- ============================================================================
-- Sorun: Sipariş durumu değiştiğinde (onaylandı/yolda/teslim edildi) müşteriye
-- iki ayrı bildirim düşüyor:
--   1) SQL trigger (notify_order_status_trigger) → 'order_status' tipi,
--      başlık "Siparişin teslim edildi ✓"
--   2) Dart kodu (OrderService._sendOrderStatusNotification /
--      courier_notification_service.notifyCustomerOrderDelivered /
--      seller_orders_screen._sendStatusNotificationToCustomer) → farklı tipler
--
-- Çözüm: SQL trigger'ları tamamen kaldır. Artık Dart kodu tek yetkili kaynak.
-- Dart tarafı zaten 3 durumu (onaylandı, yolda, teslim edildi) tek bildirimle
-- müşteriye iletiyor. Bu migration bir kez çalıştırılınca kalıcı çözüm sağlar.
--
-- Çalıştırma: Supabase Dashboard > SQL Editor > bu dosyayı yapıştır > Run
-- ============================================================================

-- 1) Sipariş durum değişikliği trigger'ını kaldır (müşteriye giden çift bildirim)
--    Dart: OrderService._sendOrderStatusNotification() + delivered için updateOrderStatus
DROP TRIGGER IF EXISTS notify_order_status_trigger ON public.orders;

-- 2) Yeni sipariş trigger'ını kaldır (satıcıya giden çift bildirim)
--    Dart: OrderService.createOrder() ve createMultiShopOrder() 'new_order' gönderiyor
DROP TRIGGER IF EXISTS notify_new_order_trigger ON public.orders;

-- 3) İlgili fonksiyonları da temizle (trigger kalmadığı için)
DROP FUNCTION IF EXISTS public.notify_order_status_change() CASCADE;
DROP FUNCTION IF EXISTS public.notify_new_order() CASCADE;

-- 4) Önceki 'order_status' tipindeki duplike bildirimleri temizle.
--    Aynı sipariş için birden fazla order_status kaydı oluşmuş olabilir; en yeniyi
--    tut, eski olanları sil. Bu, bildirimler ekranındaki çift kayıtları da temizler.
DELETE FROM public.notifications a
USING public.notifications b
WHERE a.type = 'order_status'
  AND b.type = 'order_status'
  AND a.entity_id = b.entity_id
  AND a.created_at < b.created_at;

-- 5) 'order_delivered' ve 'order_update' için de aynı temizlik (Dart farklı tipler
--    gönderiyorsa diye). Aynı entityId + aynı başlıktan birden fazla varsa en yeniyi tut.
DELETE FROM public.notifications a
USING public.notifications b
WHERE a.type IN ('order_delivered', 'order_update', 'review_pending')
  AND b.type IN ('order_delivered', 'order_update', 'review_pending')
  AND a.entity_id = b.entity_id
  AND a.title = b.title
  AND a.created_at < b.created_at;

DO $$
BEGIN
    RAISE NOTICE '✅ Sipariş bildirim trigger''ları kaldırıldı.';
    RAISE NOTICE '✅ Duplike order_status bildirimleri temizlendi.';
    RAISE NOTICE 'ℹ️ Bundan sonra Dart kodu tek bildirim kaynağıdır.';
END $$;