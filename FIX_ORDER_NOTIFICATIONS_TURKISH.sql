-- ============================================================================
-- SİPARİŞ BİLDİRİMLERİNİ DÜZELT
-- ============================================================================
-- 1. Push notification mesajları Türkçe olsun
-- 2. Duplike bildirimler olmasın
-- 3. Bildirimler notifications tablosuna düşsün (badge sayısı için)
-- ============================================================================

-- Önce mevcut trigger'ları kaldır
DROP TRIGGER IF EXISTS send_order_notification ON orders;
DROP TRIGGER IF EXISTS send_new_order_notification ON orders;
DROP FUNCTION IF EXISTS send_order_notification_trigger();
DROP FUNCTION IF EXISTS send_new_order_notification_trigger();

-- Yeni sipariş bildirimi (Satıcıya) - SADECE INSERT
CREATE OR REPLACE FUNCTION send_new_order_notification_trigger()
RETURNS TRIGGER AS $$
DECLARE
  v_seller_id UUID;
  v_shop_name TEXT;
  v_customer_name TEXT;
BEGIN
  -- Sadece yeni sipariş oluşturulduğunda çalışsın
  IF TG_OP != 'INSERT' THEN
    RETURN NEW;
  END IF;

  -- Satıcı ID ve mağaza adını al
  SELECT owner_id, name INTO v_seller_id, v_shop_name
  FROM shops
  WHERE id = NEW.shop_id;

  -- Müşteri adını al
  SELECT COALESCE(full_name, username, 'Müşteri') INTO v_customer_name
  FROM profiles
  WHERE id = NEW.user_id;

  -- Satıcıya bildirim gönder (notifications tablosuna ekle)
  INSERT INTO notifications (user_id, type, title, content, entity_id, actor_id, actor_name, is_read, created_at)
  VALUES (
    v_seller_id,
    'new_order',
    'Yeni Sipariş',
    v_customer_name || ' yeni bir sipariş verdi',
    NEW.id,
    NEW.user_id,
    v_customer_name,
    false,
    NOW()
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER send_new_order_notification
AFTER INSERT ON orders
FOR EACH ROW
EXECUTE FUNCTION send_new_order_notification_trigger();

-- Sipariş durumu güncellemesi (Müşteriye) - SADECE UPDATE
CREATE OR REPLACE FUNCTION send_order_notification_trigger()
RETURNS TRIGGER AS $$
DECLARE
  v_title TEXT;
  v_content TEXT;
  v_shop_name TEXT;
BEGIN
  -- Sadece durum değiştiğinde ve UPDATE olduğunda
  IF TG_OP != 'UPDATE' OR OLD.status = NEW.status THEN
    RETURN NEW;
  END IF;

  -- Mağaza adını al
  SELECT name INTO v_shop_name
  FROM shops
  WHERE id = NEW.shop_id;

  -- Duruma göre Türkçe mesaj oluştur
  CASE NEW.status
    WHEN 'confirmed' THEN
      v_title := 'Siparişiniz Onaylandı';
      v_content := v_shop_name || ' siparişinizi onayladı ve hazırlıyor';
    
    WHEN 'preparing' THEN
      -- Preparing durumunda bildirim gönderme
      RETURN NEW;
    
    WHEN 'ready' THEN
      -- Ready durumunda bildirim gönderme
      RETURN NEW;
    
    WHEN 'on_the_way' THEN
      v_title := 'Siparişiniz Yolda';
      v_content := 'Siparişiniz size teslim edilmek üzere yola çıktı';
    
    WHEN 'delivered' THEN
      v_title := 'Siparişiniz Teslim Edildi';
      v_content := 'Siparişiniz başarıyla teslim edildi. Afiyet olsun!';
    
    WHEN 'cancelled' THEN
      v_title := 'Siparişiniz İptal Edildi';
      v_content := v_shop_name || ' siparişinizi iptal etti';
    
    ELSE
      -- Diğer durumlarda bildirim gönderme
      RETURN NEW;
  END CASE;

  -- Müşteriye bildirim gönder (notifications tablosuna ekle)
  INSERT INTO notifications (user_id, type, title, content, entity_id, actor_id, actor_name, is_read, created_at)
  VALUES (
    NEW.user_id,
    'order_update',
    v_title,
    v_content,
    NEW.id,
    NULL, -- Actor yok (sistem bildirimi)
    v_shop_name,
    false,
    NOW()
  );

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE TRIGGER send_order_notification
AFTER UPDATE ON orders
FOR EACH ROW
EXECUTE FUNCTION send_order_notification_trigger();

-- Sonuç
DO $$
BEGIN
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'SİPARİŞ BİLDİRİMLERİ DÜZELTİLDİ!';
    RAISE NOTICE '================================================================';
    RAISE NOTICE '1. Push notification mesajları Türkçe';
    RAISE NOTICE '2. Duplike bildirim yok (type: new_order ve order_update)';
    RAISE NOTICE '3. Bildirimler notifications tablosuna düşüyor';
    RAISE NOTICE '4. Badge sayısı artacak';
    RAISE NOTICE '================================================================';
    RAISE NOTICE 'NOT: notification_service.dart zaten order_status ve';
    RAISE NOTICE '     new_order tiplerini filtreliyor, bu yüzden duplike yok';
    RAISE NOTICE '================================================================';
END $$;
