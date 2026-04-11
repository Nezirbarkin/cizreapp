-- ============================================
-- SUPABASE SECURITY FIXES
-- Function Search Path Mutable Uyarılarını Düzelt
-- ============================================
-- 
-- Bu SQL dosyası 4 fonksiyonun search_path güvenlik uyarısını düzeltir.
-- 
-- Çözüm: Her fonksiyona SECURITY DEFINER ve search_path parametresi ekleyerek
-- SQL injection saldırılarına karşı koruma sağlar.
-- ============================================

-- ============================================
-- 1. get_user_liked_posts FIX
-- ============================================

-- Önce mevcut fonksiyonu drop et
DROP FUNCTION IF EXISTS get_user_liked_posts(uuid);

-- Yeni güvenli versiyonu oluştur
CREATE OR REPLACE FUNCTION get_user_liked_posts(p_user_id uuid)
RETURNS TABLE (
  id uuid,
  user_id uuid,
  content text,
  image_url text,
  created_at timestamp with time zone,
  likes_count bigint,
  comments_count bigint,
  is_liked boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  RETURN QUERY
  SELECT 
    p.id,
    p.user_id,
    p.content,
    p.image_url,
    p.created_at,
    p.likes_count,
    p.comments_count,
    EXISTS(
      SELECT 1 FROM post_likes pl 
      WHERE pl.post_id = p.id 
      AND pl.user_id = p_user_id
    ) as is_liked
  FROM posts p
  WHERE EXISTS(
    SELECT 1 FROM post_likes pl2
    WHERE pl2.post_id = p.id
    AND pl2.user_id = p_user_id
  )
  ORDER BY p.created_at DESC;
END;
$$;

-- ============================================
-- 2. send_push_on_notification FIX
-- ============================================

-- Önce mevcut trigger function'ı drop et
DROP FUNCTION IF EXISTS send_push_on_notification() CASCADE;

-- Yeni güvenli versiyonu oluştur
CREATE OR REPLACE FUNCTION send_push_on_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Supabase Edge Function çağrısı için HTTP request
  -- Not: Bu fonksiyon notification insert edildiğinde otomatik çalışır
  PERFORM net.http_post(
    url := current_setting('app.settings.edge_function_url') || '/send-push-notification',
    body := json_build_object(
      'notification_id', NEW.id,
      'user_id', NEW.user_id,
      'type', NEW.type,
      'title', NEW.title,
      'body', NEW.content
    )::text,
    headers := json_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || current_setting('app.settings.service_role_key')
    )::jsonb
  );
  
  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  -- Hata durumunda bildirimi yine de kaydet ama push notification gönderme
  RETURN NEW;
END;
$$;

-- Trigger'ı yeniden oluştur
DROP TRIGGER IF EXISTS on_notification_created ON notifications;
CREATE TRIGGER on_notification_created
  AFTER INSERT ON notifications
  FOR EACH ROW
  EXECUTE FUNCTION send_push_on_notification();

-- ============================================
-- 3. update_addresses_updated_at FIX
-- ============================================

-- Önce mevcut fonksiyonu drop et
DROP FUNCTION IF EXISTS update_addresses_updated_at() CASCADE;

-- Yeni güvenli versiyonu oluştur
CREATE OR REPLACE FUNCTION update_addresses_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

-- Trigger'ı yeniden oluştur
DROP TRIGGER IF EXISTS update_addresses_updated_at_trigger ON addresses;
CREATE TRIGGER update_addresses_updated_at_trigger
  BEFORE UPDATE ON addresses
  FOR EACH ROW
  EXECUTE FUNCTION update_addresses_updated_at();

-- ============================================
-- 4. update_notifications_updated_at FIX
-- ============================================

-- Önce mevcut fonksiyonu drop et
DROP FUNCTION IF EXISTS update_notifications_updated_at() CASCADE;

-- Yeni güvenli versiyonu oluştur
CREATE OR REPLACE FUNCTION update_notifications_updated_at()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$;

-- Trigger'ı yeniden oluştur
DROP TRIGGER IF EXISTS update_notifications_updated_at_trigger ON notifications;
CREATE TRIGGER update_notifications_updated_at_trigger
  BEFORE UPDATE ON notifications
  FOR EACH ROW
  EXECUTE FUNCTION update_notifications_updated_at();

-- ============================================
-- AUTH LEAKED PASSWORD PROTECTION
-- ============================================
-- 
-- Bu ayar Supabase Dashboard'dan yapılmalıdır:
-- 
-- 1. Supabase Dashboard → Authentication → Settings'e git
-- 2. "Password" bölümünde "Leaked Password Protection" ayarını bul
-- 3. "Enable Leaked Password Protection" seçeneğini aktif et
-- 
-- Bu özellik HaveIBeenPwned.org ile entegre olarak
-- sızdırılmış şifrelerin kullanılmasını engeller.
-- ============================================

-- ============================================
-- TEST SONRASI KONTROL
-- ============================================
-- 
-- Bu SQL'i çalıştırdıktan sonra:
-- 1. Supabase Dashboard → Database Linter'ı çalıştır
-- 2. function_search_path_mutable uyarıları gitmiş olmalı
-- 3. Kalan tek uyarı: auth_leaked_password_protection
--    (Bu dashboard'dan manuel aktif edilmeli)
-- 
-- GÜVENLİK NOTLARI:
-- - SECURITY DEFINER: Fonksiyon, onu oluşturan kullanıcının
--   yetkileriyle çalışır (owner privileges)
-- - SET search_path = public: SQL injection saldırılarına karşı
--   koruma sağlar, sadece public schema'daki objelere erişir
-- ============================================
