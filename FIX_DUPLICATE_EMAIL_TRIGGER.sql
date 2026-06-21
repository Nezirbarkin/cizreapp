-- ============================================================================
-- ÇİFT EMAİL SORUNUNU ÇÖZME
-- ============================================================================
-- Sorun: Sipariş oluşturulduğunda hem Dart kodu hem SQL trigger email gönderiyor
-- Çözüm: SQL trigger'ı devre dışı bırakıyoruz (Dart kodu zaten gönderiyor)
-- ============================================================================

-- Email trigger'ını devre dışı bırak
ALTER TABLE public.orders DISABLE TRIGGER on_order_created_send_email;

-- Doğrulama: trigger'ın devre dışı olduğunu kontrol et
SELECT tgname, tgenabled 
FROM pg_trigger 
WHERE tgrelid = (SELECT oid FROM pg_class WHERE relname = 'orders')
AND tgname = 'on_order_created_send_email';

-- Beklenen sonuç: tgenabled = 'D' (Disabled)