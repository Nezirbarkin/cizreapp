# 🔍 Push Notification Debug Rehberi

## Adım 1: Edge Function Logs Kontrol

1. **Supabase Dashboard** aç: https://supabase.com/dashboard/project/xsbukxkgtmdyickknqzf
2. Sol menüden **Edge Functions** → **send-push-notification** → **Logs** sekmesi
3. Uygulamayı aç
4. Başka bir hesaptan kendini takip et
5. **Logs'ta yeni bir satır görmen lazım!**

**Beklenen log:**
```
📤 Push bildirim gönderiliyor (HTTP v1)
```

**Eğer log YOKSA:** Trigger çalışmıyor
**Eğer log varsa ama hata varsa:** Edge Function'da sorun var

---

## Adım 2: Flutter Uygulamasını Yeniden Başlat

**ÖNEMLİ:** FCM token uygulama başladığında üretilir!

1. Uygulamayı **tamamen kapat** (arka planda da)
2. Uygulamayı **yeniden aç**
3. Giriş yap
4. Test et: Başka hesaptan kendini takip et

---

## Adım 3: FCM Token Kontrolü

Supabase SQL Editor'da çalıştır:

```sql
SELECT id, username, 
       CASE 
         WHEN fcm_token IS NULL THEN '❌ TOKEN YOK'
         WHEN LENGTH(fcm_token) < 50 THEN '⚠️ TOKEN KISA'
         ELSE '✅ TOKEN TAMAM'
       END AS durum,
       LEFT(fcm_token, 30) || '...' AS token_basi
FROM profiles 
WHERE id = 'YOUR_USER_ID';
```

**Sonuç:**
- ❌ TOKEN YOK: Uygulamayı yeniden başlat
- ⚠️ TOKEN KISA: Uygulamayı yeniden başlat
- ✅ TOKEN TAMAM: Sistem hazır, test et

---

## Adım 4: Manuel Bildirim Test

Supabase SQL Editor'da çalıştır:

```sql
-- Önce user ID'ini bul
SELECT id, username FROM profiles LIMIT 5;

-- Sonra test bildirimi gönder
INSERT INTO notifications (
  user_id,
  type,
  title,
  content,
  actor_id
) VALUES (
  'USER_ID_BURAYA_YAZ',
  'post_like',
  '🔔 Test Bildirim',
  'Bu bir test push notification',
  'Aynı_USER_ID_BURAYA_YAZ'
);
```

Hemen ardından **Edge Function logs**'a bak!

---

## Adım 5: Firebase Console Kontrol

1. https://console.firebase.google.com/project/cizreapp-3b9a4
2. **Cloud Messaging** → **Cloud Messaging API (V1)**
3. Durum: **Enabled** olmalı

Eğer **Disabled** ise:
1. **Enable** butonuna tıkla
2. 1-2 dakika bekle
3. Tekrar test et

---

## Adım 6: Secret Kontrol

CMD'de çalıştır:

```bash
cd C:\Users\lenovo\cizreapp
supabase.exe secrets list
```

Çıktıda görmelisin:
```
FIREBASE_SERVICE_ACCOUNT_JSON  (çok uzun JSON metni)
```

**Eğer yoksa:** [`DEPLOY_NOW.sql`](DEPLOY_NOW.sql) dosyasındaki komutu çalıştır

---

## Adım 7: Test Senaryosu

1. **Uygulamayı tamamen kapat**
2. **Uygulamayı yeniden aç**
3. **Giriş yap**
4. **Başka bir hesaba geç**
5. **Kendini takip et**
6. **3 saniye bekle**
7. **Push notification gelecek!**

---

## 🐛 Sorun Giderme

### Logs'ta hiçbir şey yok
- Trigger çalışmıyor
- SQL trigger'ı tekrar çalıştır

### Logs'ta "FIREBASE_SERVICE_ACCOUNT_JSON tanımlı değil"
- Secret eklenmemiş
- `supabase.exe secrets set FIREBASE_SERVICE_ACCOUNT_JSON="..."` çalıştır

### Logs'ta "OAuth token alınamadı"
- Service Account JSON yanlış
- Firebase Console'dan yeni JSON indir

### Logs'ta "FCM send failed"
- Firebase API disabled
- Firebase Console'dan API'yi enable et

### FCM Token yok
- Uygulamayı yeniden başlat
- Notification izni ver

---

## ✅ Başarı Kontrolü

Push notification çalıştığında:
- Telefonda bildirim çıkar 🔔
- Edge Function logs'ta başarı mesajı ✅
- In-app bildirim de eklenir 📱
