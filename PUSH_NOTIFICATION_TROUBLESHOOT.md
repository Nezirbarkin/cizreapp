# 🔧 Push Notification Sorun Giderme

Bildirim gelmiyor? Adım adım kontrol et:

---

## ✅ Kontrol Listesi

### 1. SQL Trigger'ı Doğru Çalıştırdın mı?

**❌ HATA:** SQL Editor'dan markdown blokları ile yapıştırmak:
```sql
-- Bu HATA! Markdown blokları ile yapıştırma
CREATE EXTENSION IF NOT EXISTS http...
```

**✅ DOĞRU:** Sadece SQL kodunu kopyala (``` işaretleri HARITA):

```
Supabase Dashboard → SQL Editor
→ Yeni Query
→ supabase/push_notification_trigger.sql dosyasını aç
→ Tüm SQL'i (``` işaretleri HARİÇ) kopyala
→ SQL Editor'a yapıştır
→ ▶️ Execute butonuna tıkla
```

Başarılıysa şu çıktıyı göreceksin:
```
Query successful
```

---

### 2. Firebase Cloud Messaging API Aktif mi?

```
https://console.firebase.google.com/project/cizreapp-3b9a4
→ Project Settings (⚙️)
→ Cloud Messaging sekmesi
→ "Cloud Messaging API (V1)" bölümünü bul
→ Durum: "Enabled" (✅ Yeşil) olmalı
```

Eğer "DISABLED" yazıyorsa:
1. **Enable** butonuna tıkla
2. Birkaç saniye bekle
3. Sayfayı yenile

---

### 3. Service Account JSON Secret Eklendi mi?

Supabase Dashboard → Project Settings → Secrets

```
FIREBASE_SERVICE_ACCOUNT_JSON = çok uzun JSON metni
```

Kontrol:
```bash
supabase secrets list
```

Çıktısında `FIREBASE_SERVICE_ACCOUNT_JSON` görünmeli.

Eğer yoksa:
```bash
supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON="{JSON_METNI}"
```

---

### 4. Edge Function Deployed mi?

Supabase Dashboard → Edge Functions

```
send-push-notification → Status: "Deployed" ✅
```

Veya terminal ile:
```bash
supabase functions list
```

`send-push-notification` görünmeli.

Deploy değilse:
```bash
supabase functions deploy send-push-notification
```

---

### 5. FCM Token Kayıtlı mı?

Supabase Dashboard → SQL Editor → Yeni Query:

```sql
SELECT id, username, fcm_token 
FROM profiles 
WHERE fcm_token IS NOT NULL
LIMIT 5;
```

Sonuç:
- **FCM token'lar görsem:** Sistem hazır, teste geç ↓
- **Hiçbir sonuç yoksa:** Flutter uygulamasında FCM token kaydedilmemiş

---

## 🧪 Test Et

### Test 1: Manual Bildirim Gönder

Supabase SQL Editor → Yeni Query:

```sql
-- FCM token'ı olan kullanıcı bul
SELECT id, username, fcm_token 
FROM profiles 
WHERE fcm_token IS NOT NULL 
LIMIT 1;
```

Çıktıdan `id` ve `fcm_token` al, sonra:

```sql
-- Test bildirimi gönder
INSERT INTO notifications (
  user_id,
  type,
  title,
  content,
  actor_id
) VALUES (
  'BURAYA_USER_ID_YAZ',
  'post_like',
  '🔔 Test Bildirim',
  'Push notification sistemi çalışıyor!',
  'BURAYA_USER_ID_YAZ'
);
```

**Beklenen Sonuç:**
- Supabase Logs → Edge Functions → send-push-notification:
  ```
  📤 Push bildirim gönderiliyor (HTTP v1)
  🔑 OAuth access token alınıyor...
  🚀 FCM HTTP v1 isteği gönderiliyor...
  ✅ Push notification gönderildi
  ```
- Telefonda push notification gelecek

---

## 🐛 Sık Hatalar

### "ERROR: 42601: syntax error at or near ```"
**Nedeni:** Markdown code block işaretlerini (```) kopyaladın
**Çözüm:** Sadece SQL kodunu kopyala, ``` işaretleri hariç

### "FIREBASE_SERVICE_ACCOUNT_JSON tanımlı değil"
**Nedeni:** Secret eklenmemiş
**Çözüm:** 
```bash
supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON="..."
```

### "Cloud Messaging API is disabled"
**Nedeni:** Firebase'de API aktif değil
**Çözüm:** Firebase Console → Cloud Messaging API → Enable

### "FCM Token Not Found"
**Nedeni:** Flutter uygulamasında FCM token kaydedilmemiş
**Çözüm:** [`lib/core/services/push_notification_service.dart`](lib/core/services/push_notification_service.dart) kontrol et, initialize() çalışıyor mu?

### Logs'ta hiçbir şey yok
**Nedeni:** Edge Function çağrılmıyor, trigger çalışmıyor
**Çözüm:**
1. SQL trigger'ı doğru çalıştırdığını kontrol et
2. Trigger'ı test et:
   ```sql
   SELECT * FROM information_schema.triggers 
   WHERE event_object_table = 'notifications';
   ```
   `notifications_push_trigger` görünmeli

---

## 📱 Flutter Tarafı Kontrol

[`lib/core/services/push_notification_service.dart`](lib/core/services/push_notification_service.dart) dosyasında:

```dart
// FCM Token al
String? token = await FirebaseMessaging.instance.getToken();
print('🔔 FCM Token: $token');

// Token boş mu kontrol et
if (token == null) {
  print('❌ FCM token alınamadı!');
}

// Token profilde kayıtlı mı kontrol et
final user = supabase.auth.currentUser;
if (user != null) {
  final profile = await supabase
    .from('profiles')
    .select('fcm_token')
    .eq('id', user.id)
    .single();
  print('📱 Database FCM Token: ${profile['fcm_token']}');
}
```

---

## 🎯 Başarı Kontrolü

Tüm bu adımları tamamladıktan sonra:

1. **Supabase Logs'ta başarı mesajı** görünecek
2. **Telefonda push notification** gelecek
3. **In-app bildirim** de ekleneceği için bildirimin görüneceği

---

## 📞 Hala Çalışmıyor?

Lütfen çıktıyı paylaş:
1. Supabase Edge Functions logs (send-push-notification)
2. Flutter console logs (print çıktıları)
3. SQL query sonuçları (FCM token sorgusu)
