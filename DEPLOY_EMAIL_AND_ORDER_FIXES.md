# Email Onaylama ve Sipariş Bildirim Düzeltmeleri

## 📋 Yapılan Değişiklikler

### 1️⃣ Email Onaylama Hatası Düzeltmesi

**Sorun:** Email onaylama linkine tıklandığında uygulama açılmıyordu.

**Çözümler:**

#### A. Deep Link Yapılandırması

**iOS** ([`ios/Runner/Info.plist`](ios/Runner/Info.plist)):
- `CFBundleURLTypes` eklendi
- `cizreapp://` scheme'i tanımlandı
- Email doğrulama ve şifre yenileme linkleri artık uygulama açabilecek

**Android** ([`android/app/src/main/AndroidManifest.xml`](android/app/src/main/AndroidManifest.xml)):
- Intent-filter'lar ayrıldı ve netleştirildi
- `cizreapp://verify` path'i eklendi
- `cizreapp://recovery` path'i düzeltildi

#### B. Kayıt Ekranı ([`lib/features/auth/screens/register_screen_v2.dart`](lib/features/auth/screens/register_screen_v2.dart:72))

```dart
emailRedirectTo: 'cizreapp://verify',
```

#### C. Auth Service ([`lib/features/auth/services/auth_service.dart`](lib/features/auth/services/auth_service.dart:39))

```dart
redirectTo: 'cizreapp://recovery',
```

#### D. Main.dart Auth State Handler ([`lib/main.dart`](lib/main.dart:244))

Email doğrulama yapıldığında otomatik ana ekrana yönlendirme eklendi:
- Email onaylandıktan sonra `signedIn` eventi yakalanıyor
- `emailConfirmedAt` tarihi kontrol ediliyor
- Son 10 saniye içinde onaylanmışsa ana ekrana yönlendiriliyor

---

### 2️⃣ Sipariş Bildiriminde Ürün Detayları Eksik Hatası Düzeltmesi

**Sorun:** Yeni sipariş emailinde ürün detayları "Ürün detayları mevcut değil" olarak gösteriliyordu.

**Çözümler:**

#### A. SQL Trigger ([`supabase/migrations/20260204000000_order_email_notification_trigger.sql`](supabase/migrations/20260204000000_order_email_notification_trigger.sql:10))

Trigger'a order_items ekleme işlemi eklendi:
```sql
-- Sipariş ürünlerini al
SELECT jsonb_agg(jsonb_build_object(
  'product_name', oi.product_name,
  'quantity', oi.quantity,
  'price', oi.price
))
INTO order_items_json
FROM order_items oi
WHERE oi.order_id = NEW.id;
```

#### B. Edge Function ([`supabase/functions/send-order-email/index.ts`](supabase/functions/send-order-email/index.ts:210))

Trigger'dan gelen ürün bilgilerini kullanma:
- Önce trigger'dan gelen `order_items` kontrol ediliyor
- Yoksa veritabanından çekiliyor
- Her iki durumda da ürün listesi formatlanıyor

---

## 🚀 Deployment Adımları

### 1. Mobil Uygulama Build

```bash
# Flutter build
flutter clean
flutter pub get
flutter build apk --release  # Android
flutter build ios --release   # iOS
```

### 2. Edge Function Deploy

```bash
# Edge function'ı deploy et
supabase functions deploy send-order-email
```

### 3. SQL Migration Çalıştır

Supabase SQL Editor'da aşağıdaki migration'ı çalıştır:

```sql
-- Önce eski trigger'ı kaldır
DROP TRIGGER IF EXISTS on_order_created_send_email ON orders;

-- Yeni trigger fonksiyonunu oluştur
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
  
  -- Sipariş ürünlerini al
  SELECT jsonb_agg(jsonb_build_object(
    'product_name', oi.product_name,
    'quantity', oi.quantity,
    'price', oi.price
  ))
  INTO order_items_json
  FROM order_items oi
  WHERE oi.order_id = NEW.id;
  
  IF order_items_json IS NULL THEN
    order_items_json := '[]'::jsonb;
  END IF;
  
  -- Edge Function'ı çağır
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
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger'ı oluştur
CREATE TRIGGER on_order_created_send_email
  AFTER INSERT ON orders
  FOR EACH ROW
  EXECUTE FUNCTION notify_new_order_email();
```

---

## ✅ Test Adımları

### Email Onaylama Testi

1. **Yeni kullanıcı kaydı:**
   - Uygulamayı açın
   - Kayıt olun (yeni email ile)
   - Email gelen kutusunu kontrol edin
   - Doğrulama linkine tıklayın
   - Uygulamanın açıldığını ve ana ekrana gittiğini kontrol edin

2. **Şifre yenileme testi:**
   - "Şifremi Unuttum" seçeneğini kullanın
   - Email gelen kutusunu kontrol edin
   - Yenileme linkine tıklayın
   - Uygulamanın açıldığını ve şifre yenileme ekranına gittiğini kontrol edin

### Sipariş Bildirim Testi

1. **Yeni sipariş oluşturun:**
   - Ürün sepete ekleyin
   - Ödeme yapın

2. **Email kontrol:**
   - Satıcı email'ini kontrol edin
   - Admin email'ini kontrol edin
   - Ürün detaylarının göründüğünü doğrulayın

---

## 📝 Değiştirilen Dosyalar

| Dosya | Değişiklik |
|-------|-----------|
| `lib/features/auth/screens/register_screen_v2.dart` | emailRedirectTo eklendi |
| `lib/features/auth/services/auth_service.dart` | redirectTo güncellendi |
| `lib/main.dart` | Email doğrulama handler eklendi |
| `ios/Runner/Info.plist` | Deep link yapılandırması eklendi |
| `android/app/src/main/AndroidManifest.xml` | Intent-filter'lar düzeltildi |
| `supabase/migrations/20260204000000_order_email_notification_trigger.sql` | order_items eklendi |
| `supabase/functions/send-order-email/index.ts` | Trigger'dan ürün bilgisi kullanımı eklendi |
