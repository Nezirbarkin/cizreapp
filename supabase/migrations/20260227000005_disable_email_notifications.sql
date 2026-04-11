-- ============================================================================
-- ENABLE EMAIL NOTIFICATIONS (Admin için)
-- Sipariş geldiğinde admine email gider, push notification da çalışır
-- ============================================================================

-- pg_net extension'ı aktifleştir
CREATE EXTENSION IF NOT EXISTS pg_net;

-- Edge Function'ı çağırmak için HTTP request fonksiyonu
CREATE OR REPLACE FUNCTION notify_new_order_email()
RETURNS TRIGGER AS $$
DECLARE
  customer_info RECORD;
BEGIN
  -- Müşteri bilgilerini al
  SELECT
    full_name,
    username
  INTO customer_info
  FROM profiles
  WHERE id = NEW.user_id;
  
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
      'delivery_address', NEW.delivery_address_text
    )
  );
  
  RETURN NEW;
EXCEPTION
  WHEN OTHERS THEN
    -- Hata durumunda log'la ama transaction'ı durdurma (sipariş oluşturulmasını engelleme)
    RAISE WARNING 'Email notification failed for order %: %', NEW.id, SQLERRM;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public;

-- Trigger'ı oluştur
DROP TRIGGER IF EXISTS on_order_created_send_email ON public.orders;

CREATE TRIGGER on_order_created_send_email
  AFTER INSERT ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION notify_new_order_email();

SELECT '✅ Email bildirimleri aktif - admine sipariş bildirimi gider' AS result;
