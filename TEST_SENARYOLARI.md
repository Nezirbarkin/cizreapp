# 🧪 Test Senaryoları - Kayıt ve E-posta Doğrulama

## ⚠️ Önce Supabase SQL Script'i Çalıştırın!

**ÖNEMLİ:** Test etmeden önce mutlaka [`FIX_REGISTRATION_AND_EMAIL_CONFIRM.sql`](FIX_REGISTRATION_AND_EMAIL_CONFIRM.sql) dosyasını Supabase SQL Editor'de çalıştırın!

```bash
# SQL Script'i çalıştırmak için:
# 1. Supabase Dashboard → SQL Editor
# 2. FIX_REGISTRATION_AND_EMAIL_CONFIRM.sql içeriğini yapıştır
# 3. Run butonuna tıkla
```

---

## Test 1: Yeni Kullanıcı Kaydı ✅

### Adımlar:
1. Uygulamayı başlatın
2. **"Kayıt Ol"** sayfasına gidin
3. Test bilgilerini doldurun:
   ```
   Kullanıcı Adı: test_user_001
   Ad Soyad: Test Kullanıcı
   E-posta: test001@example.com
   Şifre: Test123!
   ```
4. KVKK onay kutusunu işaretleyin
5. **"Kayıt Ol"** butonuna tıklayın

### Beklenen Sonuç:
✅ **BAŞARILI:**
- RLS hatası **ALMAMALISINIZ**
- "E-posta Doğrulaması Gerekli" dialog'u görmelisiniz
- Email adresinize doğrulama maili gelmeli

❌ **BAŞARISIZ (Hata alırsanız):**
- Supabase SQL script'ini çalıştırdınız mı?
- Supabase loglarını kontrol edin (Dashboard → Logs)

### Debug:
```sql
-- Kullanıcının profili oluşturuldu mu kontrol edin
SELECT id, username, email, full_name, created_at
FROM profiles
WHERE email = 'test001@example.com';

-- Email alanı dolu mu?
-- Eğer NULL ise script çalışmamış demektir!
```

---

## Test 2: E-posta Doğrulama 📧

### Adımlar:
1. E-posta kutunuzu açın
2. "CizreApp - E-posta Doğrulama" konulu maili bulun
3. **"E-postayı Doğrula"** linkine tıklayın
4. Mobil cihazda link açılmalı (Deep link)

### Beklenen Sonuç:
✅ **BAŞARILI:**
1. Uygulama otomatik olarak açılmalı
2. **"E-posta Doğrulandı!"** dialog'u görmelisiniz (yeşil tik ikonu)
3. 1.5 saniye sonra ana ekrana yönlendirilmelisiniz
4. Giriş yapmış olarak ana sayfada olmalısınız

❌ **BAŞARISIZ - Beyaz Ekran Sorunu:**
- Hala beyaz ekran görüyorsanız konsol loglarını kontrol edin
- Android: `adb logcat | grep "Auth State"`
- iOS: Xcode Console

### Debug Logları:
Konsolda şu logları görmelisiniz:
```
🔐 Auth State Changed: signedIn
📧 Session: Active
📧 Email Confirmed: 2026-03-08T21:00:00.000Z
⏰ Time since confirmation: 5s
✅ Email just confirmed! Showing success dialog and navigating to main screen...
```

---

## Test 3: E-posta Doğrulama - Geç Tıklama

### Senaryo:
E-posta doğrulama linkine 30 saniyeden **sonra** tıklanması

### Adımlar:
1. Kayıt olun
2. E-posta doğrulama linkine 30+ saniye bekledikten sonra tıklayın

### Beklenen Sonuç:
✅ **BAŞARILI:**
- Dialog gösterilmemeli (çünkü 30 saniye geçmiş)
- Direkt ana ekrana yönlendirilmeli
- Giriş yapmış olarak görmelisiniz

---

## Test 4: Mevcut Kullanıcı Email Güncelleme

### Senaryo:
SQL script önceden kayıt olmuş kullanıcıların email'lerini günceller

### Kontrol:
```sql
-- Tüm kullanıcıların email'i dolu mu?
SELECT 
    COUNT(*) as total_users,
    COUNT(email) as users_with_email,
    COUNT(*) - COUNT(email) as users_without_email
FROM profiles;

-- users_without_email = 0 olmalı!
```

---

## Test 5: Deep Link Handling

### Adımlar:
1. Terminal'den deep link test edin:

**Android:**
```bash
adb shell am start -W -a android.intent.action.VIEW \
  -d "cizreapp://verify?access_token=test&type=signup"
```

**iOS:**
```bash
xcrun simctl openurl booted "cizreapp://verify?access_token=test&type=signup"
```

### Beklenen Sonuç:
✅ Uygulama açılmalı
✅ Konsol logunda: `🔗 Deep link detected: cizreapp://verify`

---

## Test 6: RLS Policy Doğrulama

### SQL Kontrolü:
```sql
-- INSERT policy var mı?
SELECT policyname, cmd, with_check
FROM pg_policies 
WHERE tablename = 'profiles' AND cmd = 'INSERT';

-- Sonuç:
-- policyname: "Users can insert own profile"
-- cmd: INSERT
-- with_check: (auth.uid() = id)
```

---

## Test 7: Trigger Fonksiyonu Test

### Manuel Test:
```sql
-- Test kullanıcısı oluştur (trigger otomatik çalışır)
INSERT INTO auth.users (
  id, 
  email, 
  encrypted_password,
  email_confirmed_at,
  raw_user_meta_data
)
VALUES (
  gen_random_uuid(),
  'trigger_test@example.com',
  'encrypted_test_password',
  NOW(),
  '{"username": "trigger_test", "full_name": "Trigger Test"}'::jsonb
);

-- Profil oluşturuldu mu kontrol et
SELECT id, email, username, full_name
FROM profiles
WHERE email = 'trigger_test@example.com';

-- ✅ Email alanı DOLU olmalı!
```

---

## 🐛 Sorun Giderme

### Sorun 1: RLS Hatası Hala Alıyorum

**Çözüm:**
```sql
-- 1. Trigger var mı kontrol et
SELECT trigger_name FROM information_schema.triggers
WHERE trigger_name = 'on_auth_user_created';

-- 2. Yoksa tekrar oluştur
-- FIX_REGISTRATION_AND_EMAIL_CONFIRM.sql'i çalıştır

-- 3. Fonksiyonu manuel test et
SELECT public.handle_new_user();
```

### Sorun 2: Email Alanı NULL

**Çözüm:**
```sql
-- Mevcut kullanıcıların email'lerini manuel güncelle
UPDATE profiles p
SET email = u.email, updated_at = NOW()
FROM auth.users u
WHERE p.id = u.id AND (p.email IS NULL OR p.email = '');

-- Kaç satır güncellendi?
-- "UPDATE X" şeklinde çıktı görmeli
```

### Sorun 3: Email Dialog Gösterilmiyor

**Kontrol Listesi:**
1. ✅ [`lib/main.dart`](lib/main.dart:292) güncel mi?
2. ✅ 30 saniye penceresi içinde mi tıkladınız?
3. ✅ Konsol loglarında "Email just confirmed" var mı?

**Debug:**
```dart
// main.dart satır 257'yi değiştir:
final isJustConfirmed = now.difference(confirmedAt).inSeconds < 300; // 5 dakika
```

### Sorun 4: Deep Link Çalışmıyor

**Android Kontrol:**
```bash
# Manifest'te deep link var mı?
adb shell dumpsys package com.cizreapp.app | grep -A 10 "android.intent.action.VIEW"

# Sonuç: cizreapp scheme görmelisiniz
```

**iOS Kontrol:**
```bash
# Info.plist kontrol et
cat ios/Runner/Info.plist | grep -A 5 "CFBundleURLSchemes"
```

---

## ✅ Başarı Kriterleri

Test sonunda şunlar doğrulanmalı:

- [ ] Yeni kullanıcı kaydı **RLS hatası vermeden** tamamlanıyor
- [ ] Email otomatik olarak profiles tablosuna kaydediliyor
- [ ] E-posta doğrulama maili geliyor
- [ ] Deep link (cizreapp://verify) uygulamayı açıyor
- [ ] "E-posta Doğrulandı!" dialog'u gösteriliyor
- [ ] Otomatik olarak ana ekrana yönlendiriliyor
- [ ] Mevcut kullanıcıların email alanları dolu
- [ ] Trigger fonksiyonu çalışıyor

---

## 📊 Test Sonuç Raporu

### Başarılı Test Sayısı: __/7

| Test | Durum | Notlar |
|------|-------|--------|
| 1. Yeni Kullanıcı Kaydı | ⬜ | |
| 2. E-posta Doğrulama | ⬜ | |
| 3. Geç Tıklama | ⬜ | |
| 4. Email Güncelleme | ⬜ | |
| 5. Deep Link | ⬜ | |
| 6. RLS Policy | ⬜ | |
| 7. Trigger Test | ⬜ | |

---

## 📝 Sonraki Adımlar

Testler başarılıysa:
1. Production'a deploy edin
2. Kullanıcılara duyuru yapın
3. Analytics ile kayıt başarı oranını izleyin

Testler başarısızsa:
1. Hata loglarını kaydedin
2. [`KAYIT_VE_EMAIL_DOGRULAMA_COZUM_REHBERI.md`](KAYIT_VE_EMAIL_DOGRULAMA_COZUM_REHBERI.md) dosyasına bakın
3. Supabase Dashboard → Logs → Database kısmını kontrol edin
