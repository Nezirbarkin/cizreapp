# 📊 PUSH BİLDİRİM VE EMAIL SİSTEMİ ANALİZ SONUCU

## ✅ MEVCUT OLANLAR

### Tablolar:
- ✅ `email_settings` - Email ayarları tablosu (SMTP, Resend, SendGrid destekli)
- ✅ `notification_preferences` - Bildirim tercihleri
- ✅ `notification_tokens` - Bildirim token tablosu
- ✅ `notifications` - Bildirimler tablosu
- ✅ `orders` - Siparişler tablosu
- ✅ `shops` - Mağazalar tablosu

### Fonksiyonlar:
- ✅ `get_email_settings()` - Email ayarlarını getirir
- ✅ `send_push_on_notification()` - Notification trigger fonksiyonu
- ✅ `notify_new_order_email()` - Order email trigger fonksiyonu

### Trigger'lar:
- ✅ `notifications_push_trigger` - Notifications tablosunda AFTER INSERT trigger
- ✅ `on_order_created_send_email` - Orders tablosunda AFTER INSERT trigger

### Extensions:
- ✅ `http` (v1.6) - HTTP istekleri için
- ✅ `pg_net` (v0.19.5) - Async HTTP istekleri için

---

## ❌ EKSİK OLANLAR (SORUNLARIN KAYNAĞI)

### 1. 🔴 FCM TOKEN YÖNETİMİ
- **Sorun:** `fcm_tokens` tablosu YOK
- **Mevcut:** `notification_tokens` tablosu var ama bu FCM token'ları için yeterli olmayabilir
- **Gerekli:** Firebase FCM token'larını saklayan ayrı bir tablo

### 2. 🔴 PUSH NOTIFICATION GÖNDERİM FONKSİYONU
- **Sorun:** Firebase FCM HTTP v1 API ile push gönderen fonksiyon YOK
- **Mevcut:** `send_push_on_notification` trigger fonksiyonu var ama bu asıl gönderimi yapmıyor
- **Gerekli:** `send_fcm_push_notification()` fonksiyonu

### 3. 🔴 EMAIL GÖNDERİM FONKSİYONU
- **Sorun:** SMTP/Resend/SendGrid ile email gönderen fonksiyon YOK
- **Mevcut:** `notify_new_order_email` trigger fonksiyonu var ama bu asıl email gönderimini yapmıyor
- **Gerekli:** `send_email()` fonksiyonu

### 4. 🔴 NOTIFICATION TOKEN UPDATE MEKANİZMASI
- **Sorun:** Kullanıcı FCM token'ını `notification_tokens` tablosuna nasıl ekleyecek?
- **Gerekli:** Token güncelleme fonksiyonu ve API endpoint

### 5. 🔴 MAĞAZA VE ADMIN EMAIL BULMA
- **Sorun:** `shops` tablosunda email alanı olmayabilir
- **Gerekli:** Shop sahibi ve admin email'ini bulan fonksiyon

---

## 🔧 ÇÖZÜM PLANI

### Adım 1: FCM Token Tablosu Oluştur
```sql
CREATE TABLE fcm_tokens (
    id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id uuid REFERENCES auth.users(id) ON DELETE CASCADE,
    token text NOT NULL,
    platform text, -- 'ios', 'android', 'web'
    device_info jsonb,
    is_active boolean DEFAULT true,
    created_at timestamptz DEFAULT now(),
    updated_at timestamptz DEFAULT now()
);
```

### Adım 2: Send FCM Push Fonksiyonu
```sql
CREATE OR REPLACE FUNCTION send_fcm_push_notification(
    p_user_id uuid,
    p_title text,
    p_body text,
    p_data jsonb DEFAULT '{}'
) RETURNS jsonb AS $$
    -- Firebase FCM HTTP v1 API ile push gönder
$$ LANGUAGE plpgsql;
```

### Adım 3: Send Email Fonksiyonu
```sql
CREATE OR REPLACE FUNCTION send_email(
    p_to text,
    p_subject text,
    p_html_body text,
    p_text_body text DEFAULT NULL
) RETURNS jsonb AS $$
    -- SMTP/Resend/SendGrid ile email gönder
$$ LANGUAGE plpgsql;
```

### Adım 4: Trigger Fonksiyonlarını Güncelle
- `send_push_on_notification` → `send_fcm_push_notification` çağırsın
- `notify_new_order_email` → `send_email` çağırsın

### Adım 5: Firebase Secret'ı Vault'a Ekle
```sql
INSERT INTO vault.decrypted_secrets (name, secret, description)
VALUES ('firebase_service_account', '...', 'Firebase Service Account Key for FCM');
```

---

## 📝 EK BİLGİLER

### notification_tokens Tablosu Yapısı:
```
- id (uuid)
- user_id (uuid)
- token (text)
- device_type (text)
- created_at (timestamptz)
```

### email_settings Tablosu Yapısı:
```
- provider (text) -- 'smtp', 'resend', 'sendgrid', 'mailgun'
- smtp_host, smtp_port, smtp_username, smtp_password, smtp_encryption
- resend_api_key
- sendgrid_api_key
- mailgun_api_key, mailgun_domain
- from_email, from_name, reply_to_email
- notify_admin_new_order, notify_seller_new_order, notify_customer_order_status
- admin_email
- is_active
```

### orders Tablosu Yapısı:
```
- id, order_number, user_id, shop_id, status
- total, payment_method, payment_status
- delivery_address_text
- customer_phone
- created_at, updated_at
```

---

## ⚠️ KRİTİK SORUNLAR

1. **Push bildirim gitmiyor** → `send_fcm_push_notification()` fonksiyonu eksik
2. **Email gitmiyor** → `send_email()` fonksiyonu eksik
3. **Trigger'lar var ama işlevsel değil** → Trigger fonksiyonları asıl gönderim fonksiyonlarını çağırmıyor

---

## 🎯 ÖNCELİK

1. **ACİL:** `send_email()` fonksiyonu (Email için)
2. **ACİL:** `send_fcm_push_notification()` fonksiyonu (Push için)
3. **ORTA:** Trigger fonksiyonlarını güncelleme
4. **DÜŞÜK:** `fcm_tokens` tablosu (mevcut `notification_tokens` yeterli olabilir)
