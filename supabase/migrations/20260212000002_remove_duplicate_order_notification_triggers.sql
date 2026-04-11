-- ============================================================================
-- DUPLİKE BİLDİRİM TRIGGER'LARINI KALDIR
-- ============================================================================
-- Sorun: SQL trigger ve Dart kodu aynı anda bildirim oluşturuyor
--   1. SQL trigger → order_status tipi (generic "Sipariş: #xxx")
--   2. Dart kodu → order_update tipi (açıklamalı "Siparişiniz teslim edildi")
-- Çözüm: Dart kodu yeterli olduğu için SQL trigger'ları kaldır

-- 1. Sipariş durum değişikliği trigger'ını kaldır (müşteriye giden bildirim)
-- Dart: OrderService._sendOrderStatusNotification() zaten gönderiyor
DROP TRIGGER IF EXISTS notify_order_status_trigger ON public.orders;

-- 2. Yeni sipariş trigger'ını kaldır (satıcıya giden bildirim)
-- Dart: OrderService.createOrder() zaten gönderiyor (type: 'new_order')
DROP TRIGGER IF EXISTS notify_new_order_trigger ON public.orders;

-- 3. İlgili fonksiyonları temizle (trigger kalmadığı için gerekli değil)
DROP FUNCTION IF EXISTS notify_order_status_change() CASCADE;
DROP FUNCTION IF EXISTS notify_new_order() CASCADE;

-- Mevcut duplike bildirimleri temizle (isteğe bağlı)
-- DELETE FROM public.notifications WHERE type = 'order_status';

DO $$
BEGIN
    RAISE NOTICE 'Duplicate order notification triggers removed successfully!';
    RAISE NOTICE 'Dart code will handle all order notifications from now on.';
END $$;
