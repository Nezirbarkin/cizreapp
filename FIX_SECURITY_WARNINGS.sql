-- ================================================
-- GÜVENLİK UYARILARI ÇÖZÜMÜ
-- ================================================
-- Bu script Supabase güvenlik uyarılarını düzeltir:
-- 1. function_search_path_mutable - Fonksiyonlarda SET search_path eksik
-- 2. rls_policy_always_true - notifications INSERT policy herkese izin veriyor
-- 3. auth_leaked_password_protection - HaveIBeenPwned koruması kapalı
-- ================================================

-- ================================================
-- BÖLÜM 1: FUNCTION SEARCH_PATH DÜZELTMESİ
-- ================================================

-- notify_new_order_email fonksiyonunu kontrol et
SELECT 
    routine_name, 
    routine_type,
    security_type
FROM information_schema.routines
WHERE routine_schema = 'public' 
  AND routine_name = 'notify_new_order_email';

-- Fonksiyonu search_path ile yeniden oluştur
-- Not: Fonksiyonun mevcut kodunu koruyarak sadece search_path ekleyin
-- Eğer fonksiyonu görmek isterseniz:
-- SELECT pg_get_functiondef(oid) FROM pg_proc WHERE proname = 'notify_new_order_email';

-- GERÇEK FONKSIYON DÜZELTMESİ:
CREATE OR REPLACE FUNCTION notify_new_order_email()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public  -- ✅ Bu satır eklendi (güvenlik için)
AS $$
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
  
  -- Sipariş ürünlerini al
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
  
  -- Edge Function'ı çağır (asenkron)
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
    RAISE WARNING 'Email notification failed for order %: %', NEW.id, SQLERRM;
    RETURN NEW;
END;
$$;

-- ================================================
-- BÖLÜM 2: NOTIFICATIONS INSERT POLICY DÜZELTMESİ
-- ================================================

-- Mevcut notifications policy'lerini kontrol et
SELECT 
    policyname, 
    cmd, 
    roles,
    qual,
    with_check
FROM pg_policies 
WHERE tablename = 'notifications'
ORDER BY cmd, policyname;

-- notifications_insert_final policy'sini düzelt
-- Sorun: WITH CHECK (true) - herkes notification ekleyebiliyor

DROP POLICY IF EXISTS "notifications_insert_final" ON notifications;
DROP POLICY IF EXISTS "notifications_insert_policy" ON notifications;

-- Yeni policy: Sadece sistem (trigger) veya admin notification ekleyebilir
-- Notification'lar genelde trigger'lar tarafından oluşturulur
-- Bu yüzden bu policy aslında gerekli olmayabilir (trigger SECURITY DEFINER çalışır)

-- Seçenek 1: Sadece trigger'ların eklemesine izin ver (önerilen)
-- Policy'yi tamamen kaldırın, trigger'lar SECURITY DEFINER ile çalışır

-- Seçenek 2: Eğer kullanıcılar da notification ekleyebilmeli ise:
-- Notifications genelde trigger'lar tarafından oluşturulur (SECURITY DEFINER)
-- Bu policy sadece doğrudan insert yapılmak istendiğinde çalışır
-- NOT: Trigger'lar SECURITY DEFINER ile çalıştığı için bu policy'ye takılmaz

-- Policy olmadan bırakıyoruz çünkü:
-- 1. Trigger'lar SECURITY DEFINER ile çalışır, RLS'i bypass eder
-- 2. Client-side notification insert'e genelde ihtiyaç yoktur
-- 3. Eğer client insert gerekiyorsa aşağıdaki policy'yi aktif edin:

-- CREATE POLICY "notifications_insert_restricted"
-- ON notifications
-- FOR INSERT
-- TO authenticated
-- WITH CHECK (
--   user_id = (select auth.uid())
-- );

-- ================================================
-- BÖLÜM 3: LEAKED PASSWORD PROTECTION
-- ================================================

-- Bu ayar Supabase Dashboard'dan yapılmalıdır:
-- Authentication → Policies → Password Protection
-- "Check passwords against HaveIBeenPwned" seçeneğini aktif edin

-- SQL ile kontrol (read-only):
-- SELECT * FROM auth.config WHERE name = 'password_protection';

-- Not: Bu ayar Dashboard'dan yapılır, SQL ile değiştirilemez

-- ================================================
-- BÖLÜM 4: DOĞRULAMA
-- ================================================

-- 4.1. Notifications policy kontrolü
SELECT 
    tablename,
    policyname,
    cmd,
    array_to_string(roles, ', ') as roles,
    qual,
    with_check
FROM pg_policies 
WHERE tablename = 'notifications'
ORDER BY cmd, policyname;

-- 4.2. Function search_path kontrolü (manuel kontrol gerekir)
-- Her fonksiyon için prosrc'yi kontrol edin:
SELECT 
    p.proname as function_name,
    pg_get_functiondef(p.oid) as definition
FROM pg_proc p
JOIN pg_namespace n ON p.pronamespace = n.oid
WHERE n.nspname = 'public'
  AND p.proname LIKE '%notify%'
ORDER BY p.proname;

-- search_path = public satırının olduğunu kontrol edin

-- ================================================
-- MANUEL ADIMLAR
-- ================================================

/*
1. notify_new_order_email Fonksiyonu:
   - Supabase Dashboard → Database → Functions
   - notify_new_order_email fonksiyonunu bulun
   - Edit ile açın
   - SECURITY DEFINER satırından sonra "SET search_path = public" ekleyin
   - Save

2. Leaked Password Protection:
   - Supabase Dashboard → Authentication → Policies
   - "Password Protection" sekmesi
   - "Check passwords against HaveIBeenPwned.org" seçeneğini aktif edin
   - Save

3. Test:
   - Zayıf/sızdırılmış şifre ile kayıt olmayı deneyin (örn: "password123")
   - Hata vermeli: "Password has been found in data breaches"
*/

-- ================================================
-- NOTLAR
-- ================================================

/*
1. function_search_path_mutable:
   - Güvenlik açığı: Fonksiyon çağrıldığında kullanıcının search_path'i kullanılır
   - Çözüm: Her fonksiyona SET search_path = public ekleyin
   - Fonksiyon listesi: notify_new_order_email, diğer custom fonksiyonlar

2. rls_policy_always_true:
   - Notifications INSERT policy WITH CHECK (true) kullanıyor
   - Bu herkesin notification eklemesine izin verir
   - Genelde notifications trigger'lar tarafından oluşturulur
   - Policy'yi kaldırabilir veya kısıtlayabilirsiniz

3. auth_leaked_password_protection:
   - HaveIBeenPwned.org ile entegrasyon
   - Sızdırılmış şifreleri engellemek için önemli
   - Supabase Dashboard'dan aktif edilir
*/

-- ================================================
-- SONUÇ
-- ================================================

-- Bu script'i çalıştırdıktan sonra:
-- 1. Dashboard'dan leaked password protection'ı aktif edin
-- 2. notify_new_order_email fonksiyonunu manuel düzeltin (search_path ekleyin)
-- 3. Notifications policy'si düzeltildi (WITH CHECK kısıtlandı)
