-- ============================================================================
-- 20260825000001_admin_order_notifications.sql
-- ----------------------------------------------------------------------------
-- Sorun: Yeni sipariş oluştuğunda admin'e HİÇBİR in-app/push bildirim
-- gitmiyordu:
--   - Fiziki sipariş (orders): notify_new_order_trigger 20260212000002 ile
--     kaldırılmıştı ("Dart zaten gönderiyor" gerekçesiyle), ama Dart tarafı
--     (OrderService.createOrder) bildirimi sadece mağaza sahibine gönderiyor,
--     admin'e göndermiyor. Email trigger'ı (notify_new_order_email) var ama
--     admin panelinin Bildirimler ekranında/push olarak hiçbir iz bırakmıyor.
--   - Dijital sipariş (digital_orders, SMM): create_digital_order* RPC'leri
--     hiçbir bildirim göndermiyor; admin'in haberi bile olmuyor.
--
-- Çözüm: Her iki tabloda da AFTER INSERT trigger'ı ile public.notifications
-- tablosuna role='admin' olan TÜM kullanıcılar için satır ekle. Bu tablo
-- üzerinde zaten genel bir push trigger'ı var (notifications_push_trigger,
-- migration 20260411120004) — INSERT edilen her satır otomatik olarak
-- push notification'a da dönüşüyor, ayrıca bir şey yapmaya gerek yok.
--
-- Bu trigger'lar sipariş oluşturma yolundan bağımsız çalışır (Dart'ın
-- doğrudan insert'i veya RPC/edge function tabanlı akış fark etmez),
-- bu yüzden Dart tarafında değişiklik gerekmiyor.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1) Fiziki sipariş: orders tablosuna INSERT olunca adminlere bildirim
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_admin_new_order()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_gross NUMERIC(12, 2);
  v_customer_name TEXT;
BEGIN
  -- Brüt tutar: önce legacy 'total' (Dart'ın yazdığı), sonra 'total_amount'.
  -- Bkz. 20260708000000_FIX_SELLER_EARNINGS_TRIGGER.sql ile aynı desen.
  v_gross := COALESCE(NULLIF(NEW.total, 0), NEW.total_amount, 0);

  SELECT COALESCE(p.full_name, p.username, 'Bir müşteri')
    INTO v_customer_name
  FROM public.profiles p
  WHERE p.id = NEW.user_id;

  INSERT INTO public.notifications (user_id, type, title, content, entity_id)
  SELECT
    p.id,
    'admin_new_order',
    'Yeni Sipariş',
    COALESCE(v_customer_name, 'Bir müşteri') || ' ₺' || v_gross::text ||
      ' tutarında sipariş verdi (#' || SUBSTRING(NEW.id::text FROM 1 FOR 8) || ')',
    NEW.id::text
  FROM public.profiles p
  WHERE p.role = 'admin';

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Bildirim hatası siparişi asla engellemesin.
  RAISE LOG 'notify_admin_new_order failed for order %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS notify_admin_new_order_trigger ON public.orders;
CREATE TRIGGER notify_admin_new_order_trigger
  AFTER INSERT ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_admin_new_order();

-- ----------------------------------------------------------------------------
-- 2) Dijital sipariş (SMM): digital_orders tablosuna INSERT olunca
--    adminlere bildirim
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.notify_admin_new_digital_order()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_customer_name TEXT;
  v_product_name TEXT;
BEGIN
  SELECT COALESCE(p.full_name, p.username, 'Bir müşteri')
    INTO v_customer_name
  FROM public.profiles p
  WHERE p.id = NEW.user_id;

  SELECT pr.name INTO v_product_name
  FROM public.products pr
  WHERE pr.id = NEW.product_id;

  INSERT INTO public.notifications (user_id, type, title, content, entity_id)
  SELECT
    p.id,
    'admin_new_digital_order',
    'Yeni Dijital Sipariş',
    COALESCE(v_customer_name, 'Bir müşteri') || ' ' ||
      COALESCE(v_product_name, 'bir dijital ürün') || ' için ₺' ||
      NEW.total_price::text || ' tutarında sipariş verdi (#' ||
      SUBSTRING(NEW.id::text FROM 1 FOR 8) || ')',
    NEW.id::text
  FROM public.profiles p
  WHERE p.role = 'admin';

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE LOG 'notify_admin_new_digital_order failed for digital_order %: %', NEW.id, SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS notify_admin_new_digital_order_trigger ON public.digital_orders;
CREATE TRIGGER notify_admin_new_digital_order_trigger
  AFTER INSERT ON public.digital_orders
  FOR EACH ROW
  EXECUTE FUNCTION public.notify_admin_new_digital_order();

NOTIFY pgrst, 'reload schema';

DO $$
BEGIN
  RAISE NOTICE '✅ 20260825000001 — admin siparis bildirimleri (orders + digital_orders) eklendi';
END $$;
