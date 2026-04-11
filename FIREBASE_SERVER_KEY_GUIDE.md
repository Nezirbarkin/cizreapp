# 🔥 Firebase Push Notification - Server Key Kurulumu

## Mevcut Durum Özeti

✅ **Tamamlananlar:**
- Bildirimler veritabanına kaydediliyor (notifications tablosu)
- `push_notification_trigger` tetikleniyor
- FCM tokenlar `profiles.fcm_token` alanında saklanıyor
- SQL fonksiyonları doğru çalışıyor

❌ **Eksik Olan:**
- Firebase Server Key vault'a eklenmemiş
- `send_fcm_push_notification()` fonksiyonu Firebase'e HTTP çağrısı yapamıyor

---

## 🔑 Firebase Server Key Nasıl Alınır?

### Adım 1: Firebase Console'a Git
1. [Firebase Console](https://console.firebase.google.com/) adresine git
2. Proje seç: `cizreapp-3b9a4`
3. Sol menüden ⚙️ **Project Settings** (Proje Ayarları) tıkla

### Adım 2: Cloud Messaging Sekmesi
1. Üst menüden **Cloud Messaging** sekmesine geç
2. Aşağı kaydır, **Cloud Messaging API (Legacy)** bölümünü bul
3. **Server key** değerini kopyala (örnek: `AIzaSyC...` gibi başlar)

⚠️ **ÖNEMLİ:** 
- Bu key gizlidir, kimseyle paylaşma!
- Legacy API kullanıyoruz çünkü OAuth2 token'a ihtiyaç yok

### Adım 3: Supabase Vault'a Ekle

#### Yöntem 1: Supabase Dashboard (Önerilen)
1. [Supabase Dashboard](https://supabase.com/dashboard) → Projenizi seçin
2. Sol menüden **Database** → **Vault** tıklayın
3. **New Secret** butonuna tıklayın
4. Şu bilgileri girin:
   - **Name:** `firebase_server_key`
   - **Secret:** `[Firebase'den kopyaladığınız Server Key]`
   - **Description:** `Firebase Legacy Server Key for FCM`
5. **Save** tıklayın

#### Yöntem 2: SQL Editor
1. Supabase Dashboard → **SQL Editor**
2. Aşağıdaki SQL'i çalıştırın:

```sql
-- Firebase Server Key'i vault'a ekle
INSERT INTO vault.secrets (name, secret, description)
VALUES (
    'firebase_server_key',
    'BURAYA_FIREBASE_SERVER_KEY_YAPIŞTIRIN',  -- AIzaSyC... ile başlayan key
    'Firebase Legacy Server Key for FCM'
);
```

---

## 📝 SQL Fonksiyonunu Güncelleme

Server key vault'a eklendikten sonra, `send_fcm_push_notification()` fonksiyonu otomatik çalışacak.

### Kontrol SQL'i

```sql
-- 1. Vault'da server_key var mı?
SELECT name, description 
FROM vault.secrets 
WHERE name = 'firebase_server_key';

-- 2. Token var mı?
SELECT id, username, 
       SUBSTRING(fcm_token, 1, 30) as token_start
FROM profiles 
WHERE fcm_token IS NOT NULL;

-- 3. Test push gönder (kendi user ID'nizi kullanın)
SELECT send_fcm_push_notification(
    'SIZIN_USER_ID',
    'Test Push',
    'Bu bir test bildirimidir',
    '{}'::jsonb
);
```

---

## 🔍 Debug: Push Neden Gelmiyor?

### 1. Flutter Loglarını Kontrol Et
```dart
// lib/core/services/push_notification_service.dart içinde
// FCM token kaydedildi mi?
debugPrint('✅ FCM token Supabase\'e kaydedildi');
```

### 2. Supabase Logs Kontrol Et
1. Supabase Dashboard → **Logs** → **Postgres Logs**
2. `send_fcm_push_notification` fonksiyonunu ara
3. RAISE NOTICE mesajlarını kontrol et

### 3. Notification Token Kontrol
```sql
-- Mevcut kullanıcının FCM token'ı var mı?
SELECT 
    id,
    username,
    fcm_token IS NOT NULL as has_token,
    LENGTH(fcm_token) as token_length
FROM profiles
WHERE id = auth.uid();
```

### 4. Firebase Console → Cloud Messaging
1. **Notifications** sekmesinden test bildirimi gönder
2. FCM token'ı doğrudan test et
3. Token geçerliyse Supabase fonksiyonu da çalışmalı

---

## 🚨 Sık Karşılaşılan Sorunlar

### Sorun 1: "Firebase service account key not found in vault"
**Çözüm:** Server key vault'a eklenme��iş, yukarıdaki adımları takip edin

### Sorun 2: "Invalid server key"
**Çözüm:** 
- Firebase Console'dan doğru key'i kopyalayın
- Cloud Messaging API (Legacy) aktif mi kontrol edin

### Sorun 3: "Token is invalid or expired"
**Çözüm:**
- Flutter app'i yeniden başlatın
- FCM token'ı yeniden kaydedin
- `PushNotificationService.updateTokenAfterLogin()` çağrısı yapın

### Sorun 4: "Push gelmiyor ama notification DB'de var"
**Çözüm:**
- `push_notification_trigger` tetikleniyor mu?
- `send_push_on_notification()` fonksiyonu hata veriyor mu?
- Postgres Logs'u kontrol edin

---

## ✅ Başarı Kontrol Listesi

- [ ] Firebase Server Key alındı
- [ ] Server key Supabase vault'a eklendi
- [ ] FCM token `profiles.fcm_token`'da var
- [ ] `push_notification_trigger` mevcut
- [ ] Test push bildirimi gönderildi
- [ ] Cihazda push bildirimi alındı

---

## 🔄 Alternatif: Edge Function (Gelişmiş)

Eğer SQL fonksiyonu çalışmazsa, Supabase Edge Function kullanabilirsiniz:

```typescript
// supabase/functions/send-push/index.ts
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

serve(async (req) => {
  const { userId, title, body } = await req.json()
  
  // FCM token al
  const { data: profile } = await supabaseAdmin
    .from('profiles')
    .select('fcm_token')
    .eq('id', userId)
    .single()
  
  if (!profile?.fcm_token) {
    return new Response('No FCM token', { status: 400 })
  }
  
  // Firebase'e POST isteği
  const response = await fetch('https://fcm.googleapis.com/fcm/send', {
    method: 'POST',
    headers: {
      'Authorization': `key=${Deno.env.get('FIREBASE_SERVER_KEY')}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      to: profile.fcm_token,
      notification: { title, body },
    }),
  })
  
  return new Response(JSON.stringify(await response.json()))
})
```

---

## 📚 Ek Kaynaklar

- [Firebase Cloud Messaging Docs](https://firebase.google.com/docs/cloud-messaging)
- [Supabase Vault Docs](https://supabase.com/docs/guides/database/vault)
- [Flutter Firebase Messaging](https://firebase.flutter.dev/docs/messaging/overview)

---

**Son Güncelleme:** 2026-02-25
**Hazırlayan:** Claude Opus 4.6
