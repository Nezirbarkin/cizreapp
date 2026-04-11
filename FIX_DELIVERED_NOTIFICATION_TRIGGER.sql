-- ============================================================================
-- FIX: Teslim edildi bildirimini kaldır, değerlendirme bildirimini kullan
-- ============================================================================
-- Problem: "Siparişiniz başarıyla teslim edildi. Afiyet olsun!" bildirimi
-- SQL trigger'dan geliyor. Değerlendirme bildirimi için Dart kodu kullanılacak.
-- ============================================================================

-- 1. Eski order status trigger'ını kaldır
DROP TRIGGER IF EXISTS notify_order_status_trigger ON public.orders;

-- 2. İlgili fonksiyonları temizle (artık gerekli değil)
DROP FUNCTION IF EXISTS public.notify_order_status_change() CASCADE;

-- 3. Kontrol: Trigger kaldırıldı mı?
SELECT 
    '✅ Order status trigger kaldırıldı' as status,
    'Artık teslim edildi bildirimi Dart kodundan gönderilecek (review_request)' as note;

-- ============================================================================
-- AÇIKLAMA:
-- Bu trigger kaldırıldıktan sonra:
-- 1. Sipariş teslim edildiğinde Dart kodu çalışacak
-- 2. "Siparişiniz Teslim Edildi! 🎉" + "Ürünü ve satıcıyı değerlendirmek için tıklayın"
-- 3. Tıklandığında değerlendirme dialog'u açılacak
-- ============================================================================
