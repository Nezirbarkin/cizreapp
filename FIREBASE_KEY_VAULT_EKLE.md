# 🔑 FIREBASE FCM KEY - VAULT'A EKLEME REHBERI

## 📝 ÖZET

Firebase Service Account Key'i zaten oluşturmuşsunuz. Şimdi bunu Supabase Vault'a eklemeniz gerekli.

---

## 🔍 ADIM 1: Firebase Service Account Key'i Bulun

### Eğer daha önce indirdiyseniz:
1. Bilgisayarınızda `cizreapp-*.json` dosyasını bulun
2. Notepad/VS Code ile açın
3. İçeriğini kopyalayın

### Eğer kaybettiyseniz - Yeniden İndirin:
1. [Firebase Console](https://console.firebase.google.com) açın
2. **CizreApp** projesini seçin
3. **⚙️ Proje Ayarları** → **Hizmet Hesapları**
4. **Python** tab'ını seçin
5. **Yeni özel anahtar oluştur** butonuna tıklayın
6. JSON dosyası indirilecek, kaydedin

---

## 📋 ADIM 2: Supabase Vault'a Ekle

JSON dosyasının içeriği bu şekilde görünecek:

```json
{
  "type": "service_account",
  "project_id": "cizreapp-xxxxx",
  "private_key_id": "...",
  "private_key": "-----BEGIN PRIVATE KEY-----\n...",
  "client_email": "firebase-adminsdk-xxxxx@cizreapp.iam.gserviceaccount.com",
  "client_id": "...",
  "auth_uri": "https://accounts.google.com/o/oauth2/auth",
  "token_uri": "https://oauth2.googleapis.com/token",
  ...
}
```

### Supabase'e Ekleme SQL'i:

Supabase SQL Editor'da şu komutu çalıştırın:

```sql
-- Firebase Service Account'ı Vault'a ekle
INSERT INTO vault.decrypted_secrets (name, secret, description)
VALUES (
    'firebase_service_account',
    '{"type":"service_account","project_id":"cizreapp-xxxxx","private_key_id":"...","private_key":"-----BEGIN PRIVATE KEY-----\n...","client_email":"firebase-adminsdk-xxxxx@cizreapp.iam.gserviceaccount.com","client_id":"...","auth_uri":"https://accounts.google.com/o/oauth2/auth","token_uri":"https://oauth2.googleapis.com/token","...":"..."}'::jsonb,
    'Firebase FCM Service Account Key'
)
ON CONFLICT (name) DO UPDATE SET 
    secret = EXCLUDED.secret,
    updated_at = NOW();
```

**ÖNEMLİ:** 
- JSON içeriğinin tamamını `'` arasına koyun
- `"` işaretleri JSON içinde olacak
- `::jsonb` son kısımda bırakın

---

## ✅ TEST ET

Firebase key eklendikten sonra, push notification çalışacak!

Test:
```sql
SELECT send_fcm_push_notification(
    'USER_UUID_HERE',
    'Test Push',
    'Bu bir test bildirimidir'
);
```

---

## 🎯 ÖZETLEMESİ:

1. Firebase JSON'u bulun (veya yeniden indirin)
2. Vault SQL'ini çalıştırın
3. Push bildirimler çalışmaya başlar

**Kolay mı? İşte bu kadar!** 🚀
