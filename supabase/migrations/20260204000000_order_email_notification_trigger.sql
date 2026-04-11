-- Sipariş oluşturulduğunda e-posta bildirimi gönderen trigger
-- Bu migration dosyası orders tablosuna trigger ekler

-- pg_net extension'ı aktifleştir (Supabase'de varsayılan olarak yüklüdür)
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Edge Function'ı çağırmak için HTTP request fonksiyonu
CREATE OR REPLACE FUNCTION notify_new_order_email()
RETURNS TRIGGER AS $$
DECLARE
  customer_info RECORD;
  order_items_json JSONB;
BEGIN
  -- Müşteri bilgilerini al
  SELECT
    full_name,
    username
  INTO customer_info
  FROM profiles
  WHERE id = NEW.user_id;
  
  -- Sipariş ürünlerini al (trigger'dan hemen sonra order_items hazır olmalı)
  SELECT jsonb_agg(jsonb_build_object(
    'product_name', oi.product_name,
    'quantity', oi.quantity,
    'price', oi.price
  ))
  INTO order_items_json
  FROM order_items oi
  WHERE oi.order_id = NEW.id;
  
  -- Eğer order_items henüz yoksa boş array kullan
  IF order_items_json IS NULL THEN
    order_items_json := '[]'::jsonb;
  END IF;
  
  -- Edge Function'ı çağır (asenkron - sonucu beklemeden)
  -- pg_net extension kullanılıyor
  PERFORM net.http_post(
    url := 'https://xsbukxkgtmdyickknqzf.supabase.co/functions/v1/send-order-email',
    headers := '{"Content-Type": "application/json", "Authorization": "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhzYnVreGtndG1keWlja2tucXpmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg5MzI3MzgsImV4cCI6MjA4NDUwODczOH0.UqycLmPhsjpVQbD0706gp-FVPQ3aCyCs-m9S5rcO2pc"}'::jsonb,
    body := jsonb_build_object(
      'order_id', NEW.id,
      'shop_id', NEW.shop_id,
      'total', NEW.total,
      'order_number', NEW.order_number,
      'customer_name', COALESCE(customer_info.full_name, customer_info.username, 'Müşteri'),
      'delivery_address', NEW.delivery_address_text,
      'order_items', order_items_json
    )
  );
  
  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- Hata durumunda log'la ama transaction'ı durdurma (sipariş oluşturulmasını engelleme)
    RAISE WARNING 'Email notification failed for order %: %', NEW.id, SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger'ı oluştur
DROP TRIGGER IF EXISTS on_order_created_send_email ON orders;

CREATE TRIGGER on_order_created_send_email
  AFTER INSERT ON orders
  FOR EACH ROW
  EXECUTE FUNCTION notify_new_order_email();

-- Trigger'ı devre dışı bırakmak için (gerekirse):
-- ALTER TABLE orders DISABLE TRIGGER on_order_created_send_email;

-- Trigger'ı tekrar aktif etmek için (gerekirse):
-- ALTER TABLE orders ENABLE TRIGGER on_order_created_send_email;

COMMENT ON FUNCTION notify_new_order_email() IS 
'Yeni sipariş oluşturulduğunda admin ve satıcıya e-posta bildirimi gönderir. Edge Function (send-order-email) kullanır.';

COMMENT ON TRIGGER on_order_created_send_email ON orders IS
'Yeni sipariş oluşturulduğunda e-posta bildirimi trigger''ı';
