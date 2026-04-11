# Firebase Cloud Messaging HTTP v1 API Kurulum Rehberi

Firebase Legacy API devre dışı bırakıldığı için yeni **FCM HTTP v1 API**'sine geçiş yaptık.

## ✅ Yapılanlar

1. Edge Function güncellendi (`supabase/functions/send-push-notification/index.ts`)
2. OAuth 2.0 authentication eklendi
3. Yeni FCM HTTP v1 endpoint kullanılıyor

---

## 📋 Kurulum Adımları

### 1. Firebase Console'da API'yi Aktifleştir

1. Firebase Console'a git: https://console.firebase.google.com
2. Projenizi seçin: **cizreapp-3b9a4**
3. Sol menüden **Project Settings** (⚙️ Ayarlar)
4. **Cloud Messaging** sekmesine tıklayın
5. **Cloud Messaging API (V1)** bölümünde **Enable** butonuna tıklayın

### 2. Service Account JSON Key İndir

1. Firebase Console'da: **Project Settings** → **Service Accounts** sekmesi
2. En altta **Generate new private key** butonuna tıklayın
3. Açılan pop-up'ta **Generate key** butonuna tıklayın
4. İndirilen JSON dosyası (örnek: `cizreapp-3b9a4-firebase-adminsdk-xxxxx.json`)

JSON dosyası şu formatta olacak:
```json
{
  "type": "service_account",
  "project_id": "cizreapp-3b9a4",
  "private_key_id": "...",
  "private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
  "client_email": "firebase-adminsdk-xxxxx@cizreapp-3b9a4.iam.gserviceaccount.com",
  "client_id": "...",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  "auth_provider_x509_cert_url": "https://www.googleapis.com/oauth2/v1/certs",
  "client_x509_cert_url": "..."
}
```

⚠️ **ÖNEMLİ**: Bu dosyayı güvenli bir yerde saklayın, kimseyle paylaşmayın!

### 3. Supabase CLI Kurulumu

Windows'ta Scoop ile:
```bash
scoop install supabase
```

veya manuel indirme: https://github.com/supabase/cli/releases

### 4. Supabase CLI ile Giriş

```bash
supabase login
```

Tarayıcı açılacak, Supabase hesabınızla giriş yapın.

### 5. Projeyi Bağla

```bash
supabase link --project-ref xsbukxkgtmdyickknqzf
```

### 6. Service Account JSON'ı Secret Olarak Ekle

İndirdiğiniz JSON dosyasının tüm içeriğini tek satır olarak secret'a ekleyin:

**Windows CMD:**
```cmd
supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON="{\"type\":\"service_account\",\"project_id\":\"cizreapp-3b9a4\",...}"
```

**veya PowerShell:**
```powershell
$json = Get-Content "C:\path\to\cizreapp-3b9a4-firebase-adminsdk-xxxxx.json" -Raw
$json = $json -replace "`n", "" -replace "`r", ""
supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON="$json"
```

**veya Linux/Mac:**
```bash
supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON="$(cat cizreapp-3b9a4-firebase-adminsdk-xxxxx.json | tr -d '\n')"
```

### 7. Edge Function'ı Deploy Et

```bash
supabase functions deploy send-push-notification
```

Deploy başarılı olursa şöyle bir çıktı göreceksiniz:
```
Deploying function send-push-notification...
Function URL: https://xsbukxkgtmdyickknqzf.supabase.co/functions/v1/send-push-notification
Deployed!
```

### 8. Database Trigger'ı Çalıştır

Supabase Dashboard → SQL Editor'da `supabase/push_notification_trigger.sql` dosyasını çalıştırın.

---

## 🧪 Test Etme

### Manuel Test

Supabase Dashboard → Database → notifications tablosuna yeni bir kayıt ekleyin:

```sql
INSERT INTO notifications (
  user_id,
  type,
  title,
  content,
  actor_id,
  entity_id
) VALUES (
  'KULLANICI_ID_BURAYA', -- FCM token'ı olan kullanıcı ID'si
  'post_like',
  'Test Bildirim',
  'x kullanıcısı gönderini beğendi',
  'ACTOR_ID_BURAYA',
  'POST_ID_BURAYA'
);
```

Eğer her şey doğru yapıldıysa:
1. Database'e notification kaydı eklenecek
2. Trigger otomatik çalışacak
3. Edge Function çağrılacak
4. FCM token'ına push notification gönderilecek
5. Cihazda bildirim görünecek

### Logs Kontrolü

Supabase Dashboard → Edge Functions → send-push-notification → Logs

Burada şunları göreceksiniz:
```
📤 Push bildirim gönderiliyor (HTTP v1)
🔑 OAuth access token alınıyor...
🚀 FCM HTTP v1 isteği gönderiliyor...
✅ Push notification gönderildi
```

---

## 🔧 Sorun Giderme

### "FIREBASE_SERVICE_ACCOUNT_JSON tanımlı değil" hatası

Secret doğru eklenmemiş. Tekrar ekleyin:
```bash
supabase secrets list
supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON="..."
```

### "OAuth token alınamadı" hatası

- Service Account JSON formatı yanlış olabilir
- JSON'da `private_key` ve `client_email` alanları eksik olabilir
- Firebase Console'da Service Account aktif değil

### "FCM send failed" hatası

- FCM API aktif değil (Firebase Console → Cloud Messaging API → Enable)
- project_id yanlış (Edge Function'da `cizreapp-3b9a4` olmalı)
- FCM token geçersiz veya süresi dolmuş

### Bildirim gelmiyor

1. Flutter uygulamasında FCM token kayıtlı mı kontrol edin:
   ```sql
   SELECT id, username, fcm_token FROM profiles WHERE fcm_token IS NOT NULL;
   ```

2. Edge Function loglarını kontrol edin
3. Telefonda bildirim izinleri açık mı kontrol edin
4. Uygulamayı yeniden başlatın

---

## 📱 Flutter Tarafında Kontrol

FCM token kayıtlı mı görmek için [`PushNotificationService`](lib/core/services/push_notification_service.dart):

```dart
// Token'ı al
String? token = await FirebaseMessaging.instance.getToken();
print('FCM Token: $token');

// Token profilde kayıtlı mı kontrol et
final user = supabase.auth.currentUser;
final profile = await supabase
  .from('profiles')
  .select('fcm_token')
  .eq('id', user!.id)
  .single();
print('Database\'de kayıtlı token: ${profile['fcm_token']}');
```

---

## 🎯 Özet

**Legacy API (Eski):**
- Endpoint: `https://fcm.googleapis.com/fcm/send`
- Auth: `Authorization: key=SERVER_KEY`
- ❌ Devre dışı (deprecated 6/20/2023)

**HTTP v1 API (Yeni):**
- Endpoint: `https://fcm.googleapis.com/v1/projects/cizreapp-3b9a4/messages:send`
- Auth: `Authorization: Bearer OAUTH_ACCESS_TOKEN`
- ✅ Aktif ve güncel

---

## ✅ Başarı Kriterleri

- [ ] Firebase Cloud Messaging API aktif
- [ ] Service Account JSON indirildi
- [ ] Supabase CLI kuruldu
- [ ] Secret eklendi
- [ ] Edge Function deploy edildi
- [ ] Database trigger çalıştırıldı
- [ ] Test bildirimi cihaza ulaştı

Hepsi tamamlandığında, artık uygulama içinde yapılan her eylem (beğeni, yorum, takip vb.) otomatik olarak push notification gönderecek! 🎉
