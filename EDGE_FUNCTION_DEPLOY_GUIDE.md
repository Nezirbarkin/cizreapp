# 🚀 Supabase Edge Function - Deploy Rehberi

## Adım 1: Firebase Service Account JSON'u Alın

1. **Firebase Console** → https://console.firebase.google.com/
2. Proje: **cizreapp-3b9a4** seçin
3. ⚙️ **Project Settings** (Ayarlar) → **Service Accounts** sekmesi
4. **Generate New Private Key** butonuna tıklayın
5. JSON dosyasını indirin
6. JSON dosyasını açın ve tüm içeriği kopyalayın

## Adım 2: Supabase Dashboard'da Deploy (En Kolay Yöntem)

### 2.1. Edge Function Oluştur
1. [Supabase Dashboard](https://supabase.com/dashboard) → Projenizi seçin
2. Sol menüden **Edge Functions** tıklayın
3. **Create Function** butonuna tıklayın
4. Function name: **send-push**
5. Verify method: **None** (veya varsayılan bırakın)

### 2.2. Kodu Yapıştırın
1. `supabase/functions/send-push/index.ts` dosyasını açın
2. Tüm içeriği kopyalayın
3. Supabase Dashboard'daki kod editörüne yapıştırın

### 2.3. Secret Ekle
1. Edge Function sayfasında **Secrets** sekmesine tıklayın
2. **Add Secret** butonuna tıklayın
3. Şu bilgileri girin:
   - **Name:** `FIREBASE_SERVICE_ACCOUNT`
   - **Secret:** `[1. adımda indirdiğiniz JSON dosyasının tüm içeriği]`
4. **Save** tıklayın

### 2.4. Deploy
1. **Deploy** butonuna tıklayın
2. Function URL görünecek: `https://xsbukxkgtmdyickknqzf.supabase.co/functions/v1/send-push`

## Adım 3: SQL Fonksiyonunu Güncelleyin

`FIREBASE_PUSH_EDGE_FUNCTION.sql` dosyasını Supabase SQL Editor'da çalıştırın.

## Adım 4: Test Edin

```sql
-- Kendi user ID'nizle test edin
SELECT send_fcm_push_notification(
    'SIZIN_USER_ID',
    'Test Push',
    'Bu bir test bildirimidir',
    '{"type": "test"}'::jsonb
);
```

## Alternatif: Supabase CLI ile Deploy

Eğer CLI kullanmak isterseniz:

```bash
# 1. Supabase CLI'yi kurun
npm install -g supabase

# 2. Login olun
supabase login

# 3. Projenize linkleyin
supabase link --project-ref xsbukxkgtmdyickknqzf

# 4. Secret'ı ekleyin
supabase secrets set FIREBASE_SERVICE_ACCOUNT='{"type":"service_account", ...}'

# 5. Deploy edin
supabase functions deploy send-push
```

## 🔍 Debug: Edge Function Logları

1. Supabase Dashboard → Edge Functions → send-push
2. **Logs** sekmesine tıklayın
3. Gelen istekleri ve hataları görebilirsiniz

## ✅ Başarı Kontrol Listesi

- [ ] Firebase Service Account JSON indirildi
- [ ] Edge Function kodu Supabase Dashboard'a yapıştırıldı
- [ ] FIREBASE_SERVICE_ACCOUNT secret eklendi
- [ ] Edge Function deploy edildi
- [ ] SQL fonksiyonu güncellendi
- [ ] Test push bildirimi gönderildi
- [ ] Cihazda push bildirimi alındı

## 📱 Cihazda Push Kontrolü

Flutter uygulamasını açın ve logları kontrol edin:
```
📲 Foreground bildirim alındı: Test Push
```

Eğer log gelmezse:
1. FCM token'ı kontrol edin: `profiles.fcm_token` dolu mu?
2. Bildirim izinleri açık mı? (Ayarlar → Bildirimler)
3. Internet bağlantısı var mı?
