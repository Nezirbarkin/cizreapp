# 🚀 PUSH BİLDİRİM VE EMAIL SİSTEMİ - KURULUM REHBERI

## 📋 ÖZET

Sistemdeki **push bildirim ve email gönderim sorunları** tespit edildi ve **tam çözüm SQL'i** hazırlandı.

### 🔴 Bulduğumuz Sorunlar:
1. **Email gitmiyor** → `send_email()` fonksiyonu eksikti
2. **Push bildirimi gitmiyor** → `send_fcm_push_notification()` fonksiyonu eksikti
3. **Trigger'lar boş** → Email ve push gönderim fonksiyonlarını çağırmıyordu
4. **Sipariş durumu bildirimi yok** → Status değişikliğinde email/push göndermiyor

### ✅ Sunulan Çözüm:
- ✅ `send_email()` - Resend/SendGrid/Mailgun ile email gönderme
- ✅ `send_fcm_push_notification()` - Firebase FCM ile push bildirimi gönderme
- ✅ `send_new_order_emails()` - Yeni sipariş email'leri
- ✅ `send_new_order_push_notifications()` - Yeni sipariş push bildirimleri
- ✅ `notify_order_status_change()` - Sipariş durumu değişikliği bildirimleri
- ✅ Güncelleme trigger'ları - Otomatik bildirim gönderme

---

## 📦 DOSYALAR

| Dosya | Açıklama |
|-------|----------|
| **FIX_PUSH_EMAIL_COMPLETE.sql** | ⭐ ANA DOSYA - Tüm fonksiyonları ve trigger'ları içerir |
| **ANALIZ_SONUCU.md** | Detaylı analiz raporu |
| **CHECK_SYSTEM_QUICK.sql** | Sistem kontrol sorgusu |

---

## 🛠️ KURULUM ADIMLARI

### ADIM 1: SQL Dosyasını Çalıştır

1. **Supabase Dashboard** açın
2. **SQL Editor**'e gidin
3. **FIX_PUSH_EMAIL_COMPLETE.sql** dosyasındaki **TÜM SQL'i** kopyalayın
4. SQL Editor'e yapıştırın
5. **RUN** butonuna basın

⚠️ **ÖNEMLİ:** SQL'i tek seferde çalıştırın, bölüp çalıştırmayın!

---

### ADIM 2: Firebase Ayarlarını Vault'a Ekle

Firebase Service Account Key'i vault'a eklemeniz gerekir:

#### 2.1. Firebase Service Account Key Oluştur
1. [Firebase Console](https://console.firebase.google.com) açın
2. Projenizi seçin
3. **Proje Ayarları** → **Hizmet Hesapları** → **Python** (veya Node.js)
4. **Yeni özel anahtar oluştur** klikla
5. JSON dosyasını indirin ve saklayın

#### 2.2. Key'i Supabase Vault'a Ekle

Aşağıdaki SQL'i çalıştırın (Firebase Service Account JSON'u yapıştırın):

```sql
INSERT INTO vault.decrypted_secrets (name, secret, description)
VALUES (
    'firebase_service_account',
    '{"server_key":"YOUR_FCM_SERVER_KEY","project_id":"YOUR_PROJECT_ID"}',
    'Firebase FCM Service Account'
);
```

---

### ADIM 3: Email Ayarlarını Güncelleyin

SQL Editor'de şu komutu çalıştırın (API key'inizi ekleyin):

#### Seçenek A: Resend Kullan (ÖNERİLEN)
```sql
UPDATE email_settings SET
    provider = 'resend',
    resend_api_key = 'YOUR_RESEND_API_KEY',
    from_email = 'noreply@yourdomain.com',
    from_name = 'CizreApp',
    admin_email = 'admin@yourdomain.com',
    is_active = true
WHERE id = (SELECT id FROM email_settings LIMIT 1);
```

#### Seçenek B: SendGrid Kullan
```sql
UPDATE email_settings SET
    provider = 'sendgrid',
    sendgrid_api_key = 'YOUR_SENDGRID_API_KEY',
    from_email = 'noreply@yourdomain.com',
    from_name = 'CizreApp',
    admin_email = 'admin@yourdomain.com',
    is_active = true
WHERE id = (SELECT id FROM email_settings LIMIT 1);
```

#### Seçenek C: Mailgun Kullan
```sql
UPDATE email_settings SET
    provider = 'mailgun',
    mailgun_api_key = 'YOUR_MAILGUN_API_KEY',
    mailgun_domain = 'your-domain.mailgun.org',
    from_email = 'noreply@yourdomain.com',
    from_name = 'CizreApp',
    admin_email = 'admin@yourdomain.com',
    is_active = true
WHERE id = (SELECT id FROM email_settings LIMIT 1);
```

---

### ADIM 4: Firebase FCM Kurulumunu Tamamla

Flutter uygulamanızda Firebase FCM setup'ını tamamladığınızdan emin olun:

```dart
// lib/services/notification_service.dart
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificationService {
  static final FirebaseMessaging _messaging = FirebaseMessaging.instance;

  static Future<void> initialize() async {
    // Token'ı al
    String? token = await _messaging.getToken();
    
    // Token'ı backend'e gönder
    if (token != null) {
      await Supabase.instance.client
        .from('notification_tokens')
        .insert({
          'user_id': currentUserId,
          'token': token,
          'device_type': Platform.isIOS ? 'ios' : 'android'
        });
    }
    
    // Token yenilenmesi
    _messaging.onTokenRefresh.listen((newToken) {
      // Yeni token'ı backend'e gönder
    });
    
    // Foreground mesajları dinle
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      // Bildirimi göster
    });
  }
}
```

---

## ✅ TEST ET

### Test 1: Email Gönderimi

```sql
SELECT send_email(
    'test@example.com',
    'Test Email',
    '<h1>Test</h1><p>Bu bir test emailidir.</p>'
);
```

**Beklenen Sonuç:**
```json
{
  "success": true,
  "provider": "resend",
  "request_id": 123
}
```

### Test 2: Push Bildirimi Gönderimi

```sql
SELECT send_fcm_push_notification(
    'USER_UUID_HERE',
    'Test Push',
    'Bu bir test push bildirimindir'
);
```

**Beklenen Sonuç:**
```json
{
  "success": true,
  "sent_count": 1,
  "error_count": 0
}
```

### Test 3: Yeni Sipariş Email'i

```sql
SELECT send_new_order_emails('ORDER_UUID_HERE');
```

### Test 4: Yeni Sipariş Push Bildirimi

```sql
SELECT send_new_order_push_notifications('ORDER_UUID_HERE');
```

---

## 🔍 SORUN GIDERME

### Email Gönderilmiyor

1. **Email ayarlarını kontrol et:**
   ```sql
   SELECT * FROM email_settings WHERE is_active = true;
   ```

2. **API key'i kontrol et:**
   - Doğru API key'i kullanıyor musun?
   - API key'in valid mi?

3. **Provider'ı kontrol et:**
   - Provider doğru mu?
   - API key o provider'a mı ait?

### Push Bildirimi Gönderilmiyor

1. **Firebase key'ini kontrol et:**
   ```sql
   SELECT decrypted_secret FROM vault.decrypted_secrets 
   WHERE name = 'firebase_service_account';
   ```

2. **Notification token'ını kontrol et:**
   ```sql
   SELECT * FROM notification_tokens WHERE user_id = 'USER_UUID';
   ```

3. **Tercihleri kontrol et:**
   ```sql
   SELECT * FROM notification_preferences WHERE user_id = 'USER_UUID';
   ```

---

## 📊 YAPISI

### Email Gönderim Akışı
```
Yeni Sipariş Oluştur
        ↓
on_order_created_notify TRIGGER
        ↓
notify_new_order_complete()
        ↓
send_new_order_emails()
        ↓
email_settings kontrol
        ↓
send_email() [Resend/SendGrid/Mailgun]
        ↓
✉️ Email Gönderildi
```

### Push Bildirim Akışı
```
Notification INSERT
        ↓
notifications_push_trigger TRIGGER
        ↓
send_push_on_notification()
        ↓
notification_preferences kontrol
        ↓
send_fcm_push_notification()
        ↓
notification_tokens kontrol
        ↓
Firebase FCM API
        ↓
📱 Push Gönderildi
```

### Sipariş Durumu Bildirimi
```
Order Status UPDATE
        ↓
on_order_status_changed TRIGGER
        ↓
notify_order_status_change()
        ↓
send_email() + send_fcm_push_notification()
        ↓
✉️ + 📱 Bildirim Gönderildi
```

---

## 🔐 GÜVENLİK

### RLS Policies
- Trigger'lar `SECURITY DEFINER` ile çalışır (database role'ü olan sistem)
- Kullanıcılar yalnızca kendi notification_tokens'larını görebilir
- Email ayarları yalnızca admin'ler güncelleyebilir

### Vault Secrets
- Firebase key vault'ta şifrelenmiş olarak saklanır
- Sadece `send_fcm_push_notification` fonksiyonu erişebilir

---

## 📝 NOTLAR

### Async İşleme
- Trigger'lar fonksiyonları async olarak çağırır
- Email/push gönderimi siparişin oluşturulmasını bloke etmez
- Sistem hızlı ve responsive kalır

### Notification Preferences
Kullanıcılar şu tercihleri ayarlayabilir:
- `push_enabled` - Push bildirimleri aç/kapat
- `email_enabled` - Email bildirimleri aç/kapat
- `order_updates` - Sipariş güncellemelerini al/alma

---

## 🎯 KONTROL LİSTESİ

- [ ] SQL dosyasını Supabase'de çalıştırdım
- [ ] Firebase Service Account Key'i vault'a ekledim
- [ ] Email ayarlarını güncelledim (API key + admin email)
- [ ] Test email gönderdim ✉️
- [ ] Test push bildirimi gönderdim 📱
- [ ] Firebase FCM'i Flutter'da setup ettim
- [ ] Yeni sipariş oluşturdum ve email/push aldım
- [ ] Sipariş durumunu değiştirdim ve bildirim aldım

---

## 💬 SORULAR VE CEVAPLAR

**S: Email hala gitmiyor, ne yapmalı?**
A: 
1. API key'i doğru mu kontrol et
2. Email ayarlarının `is_active = true` olduğunu kontrol et
3. SQL hatasını kontrol et: `SELECT send_email(...)`

**S: Push için Firebase keyi nereden bulabilirim?**
A: Firebase Console → Proje Ayarları → Hizmet Hesapları → Özel Anahtar İndir

**S: SMTP server ile email gönderbilir miyim?**
A: Şu an SMTP desteklenmez. Resend, SendGrid veya Mailgun kullanmanız gerekir.

**S: Firebase olmadan push gönderebilir miyim?**
A: Hayır. Firebase FCM sistem tarafından gereklidir. OneSignal vb. alternatifleri kullanabilirsiniz (ek kurulum gerekir).

---

## 📞 DESTEK

Sorularınız veya sorunlarınız için:
1. ANALIZ_SONUCU.md dosyasını okuyun
2. Hata mesajını kontrol edin
3. SQL test sorgularını çalıştırın

---

**Kurulum Tamamlandı! 🎉**

Başarılı email ve push bildirimleri göndermek için tüm adımları tamamlamanız gerekir.
