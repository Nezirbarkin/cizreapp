# OTP E-Posta Doğrulama Sistemi - Deployment Rehberi

Bu rehber, CizreApp için geliştirilen OTP (One-Time Password) tabanlı e-posta doğrulama ve şifre sıfırlama sisteminin production ortamına alınması için gerekli tüm adımları içerir.

---

## İçindekiler

1. [Genel Bakış](#1-genel-bakis)
2. [Supabase Dashboard Adımları](#2-supabase-dashboard-adimlari)
3. [Edge Function Deploy Komutları](#3-edge-function-deploy-komutlari)
4. [Flutter Build Komutları](#4-flutter-build-komutlari)
5. [Test Senaryoları](#5-test-senaryolari)
6. [Sorun Giderme](#6-sorun-giderme)

---

## 1. Genel Bakış

### Sistem Nedir?

OTP (One-Time Password) sistemi, kullanıcıların e-posta adreslerini doğrulamak ve şifrelerini sıfırlamak için 6 haneli tek kullanımlık kodlar kullanmasını sağlar.

### Neden OTP Kullanılıyor?

**Gmail Link Prefetching Sorunu:** Gmail, e-postalardaki linkleri otomatik olarak ziyaret eder (prefetch). Bu durum, geleneksel "doğrulama linki" sistemlerinde linkin kullanıcı tıklamadan işaretlenmesine neden olur. OTP sistemi bu sorunu çözer çünkü kod sadece kullanıcının gördüğü e-postada yer alır ve manuel olarak girilmesi gerekir.

### Avantajlar

- **Güvenilir Doğrulama:** Link prefetching'den etkilenmez
- **Kullanıcı Dostu:** 6 haneli kodu girmek link tıklamak kadar kolay
- **Güvenli:** Kod 5 dakika sonra geçersiz olur
- **Rate Limiting:** 1 dakikada sadece 1 kod gönderilebilir

### Sistem Bileşenleri

| Bileşen | Açıklama |
|---------|----------|
| `registration_otps` | Kayıt doğrulama kodlarını tutan tablo |
| `password_reset_otps` | Şifre sıfırlama kodlarını tutan tablo |
| `send-registration-otp` | Kayıt OTP'si gönderen Edge Function |
| `send-password-reset-otp` | Şifre sıfırlama OTP'si gönderen Edge Function |
| `reset-password-with-otp` | OTP ile şifre güncelleyen Edge Function |
| `verify_registration_otp()` | Kayıt OTP'sini doğrulayan RPC fonksiyonu |
| `verify_password_reset_otp()` | Şifre sıfırlama OTP'sini doğrulayan RPC fonksiyonu |

---

## 2. Supabase Dashboard Adımları

### 2.1 SQL Migration'ı Çalıştırma

1. Supabase Dashboard'a gidin: https://supabase.com/dashboard
2. Projenizi seçin (CizreApp)
3. Sol menüden **SQL Editor**'e tıklayın
4. **New query** butonuna tıklayın
5. [`supabase/migrations/20260319000000_registration_otp_system.sql`](../supabase/migrations/20260319000000_registration_otp_system.sql) dosyasının içeriğini kopyalayıp yapıştırın
6. **Run** butonuna tıklayın

**Doğrulama:**

```sql
-- Tabloların oluşturulduğunu kontrol edin
SELECT table_name FROM information_schema.tables 
WHERE table_schema = 'public' 
AND table_name IN ('registration_otps', 'password_reset_otps');

-- Fonksiyonların oluşturulduğunu kontrol edin
SELECT routine_name FROM information_schema.routines 
WHERE routine_schema = 'public' 
AND routine_name IN ('verify_registration_otp', 'verify_password_reset_otp');
```

### 2.2 Confirm Email'i DISABLE Etme

Bu adım kritiktir! OTP sistemi kendi doğrulama mekanizmasını kullandığından, Supabase'in varsayılan e-posta doğrulaması devre dışı bırakılmalıdır.

1. Sol menüden **Authentication** > **Providers**'a gidin
2. **Email** provider'ına tıklayın
3. **Confirm email** seçeneğini **OFF** konumuna getirin
4. **Save** butonuna tıklayın

> ⚠️ **Önemli:** Bu ayar değişikliği yapılmazsa, kullanıcılar kayıt olduktan sonra Supabase'in doğrulama e-postasını da alır ve karmaşaya neden olur.

### 2.3 Service Role Key'i Vault'a Ekleme

Edge Function'lar service role key kullanarak veritabanına erişir. Bu anahtarın Vault'ta saklanması gerekir.

**Yöntem 1: SQL ile (Önerilen)**

SQL Editor'de şu komutu çalıştırın:

```sql
-- Service Role Key'i Vault'a ekle
SELECT vault.insert_secret(
  'SUPABASE_SERVICE_ROLE_KEY',
  'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...', -- Gerçek key'i buraya yapıştırın
  'Service role key for Edge Functions'
);
```

**Yöntem 2: Dashboard ile**

1. Sol menüden **Project Settings** > **API**'ye gidin
2. **Project API keys** bölümünden `service_role` key'i kopyalayın (⚠️ Gizli!)
3. Sol menüden **Project Settings** > **Edge Functions**'a gidin
4. **Environment Variables** bölümüne:
   - `SUPABASE_SERVICE_ROLE_KEY` = [kopyaladığınız key]
5. **Save** butonuna tıklayın

### 2.4 RESEND API Key'i Ekleme

E-posta gönderimi için Resend API key gerekir.

1. https://resend.com adresinden API key alın
2. **Project Settings** > **Edge Functions** > **Environment Variables**'a gidin
3. Şu değişkeni ekleyin:
   - `RESEND_API_KEY` = [Resend API key]
4. **Save** butonuna tıklayın

### 2.5 Diğer Environment Variables

Aşağıdaki değişkenlerin de tanımlı olduğundan emin olun:

| Değişken | Değer | Açıklama |
|----------|-------|----------|
| `SUPABASE_URL` | `https://xxxxx.supabase.co` | Otomatik tanımlı |
| `SUPABASE_SERVICE_ROLE_KEY` | `eyJ...` | 2.3'te eklendi |
| `RESEND_API_KEY` | `re_...` | 2.4'te eklendi |
| `APP_NAME` | `CizreApp` | Opsiyonel, varsayılan: CizreApp |

---

## 3. Edge Function Deploy Komutları

### 3.1 Supabase CLI Kurulumu

Henüz kurulu değilse:

```bash
# Windows (PowerShell)
winget install Supabase.CLI

# macOS
brew install supabase/tap/supabase

# Linux
brew install supabase/tap/supabase
# veya
npx supabase
```

### 3.2 Giriş Yapma

```bash
supabase login
```

Tarayıcıda açılan sayfada Supabase hesabınızla giriş yapın.

### 3.3 Proje Bağlantısı

```bash
# Proje ID'nizi öğrenin (Dashboard > Project Settings > General)
supabase link --project-ref your-project-id
```

### 3.4 Edge Function'ları Deploy Etme

```bash
# Kayıt OTP gönderme fonksiyonu
supabase functions deploy send-registration-otp

# Şifre sıfırlama OTP gönderme fonksiyonu
supabase functions deploy send-password-reset-otp

# OTP ile şifre güncelleme fonksiyonu
supabase functions deploy reset-password-with-otp
```

**Alternatif: Tek komutla tüm fonksiyonları deploy etme**

```bash
# Windows (PowerShell)
Get-ChildItem -Directory supabase\functions | ForEach-Object { supabase functions deploy $_.Name }

# macOS/Linux
for dir in supabase/functions/*/; do
  func_name=$(basename "$dir")
  supabase functions deploy "$func_name"
done
```

### 3.5 Deploy Doğrulama

```bash
# Fonksiyonların durumunu kontrol edin
supabase functions list
```

Dashboard'dan da kontrol edebilirsiniz:
1. **Edge Functions** menüsüne gidin
2. Fonksiyonların listelendiğini görün
3. Her fonksiyonun logs sekmesinden çalıştığını doğrulayın

---

## 4. Flutter Build Komutları

### 4.1 Bağımlılıkları Güncelleme

```bash
flutter pub get
```

### 4.2 Development Build

```bash
# Android (APK)
flutter build apk --debug

# iOS (Simulator)
flutter build ios --debug

# Web
flutter build web --dart-define=FLUTTER_WEB_USE_SKIA=true
```

### 4.3 Production Build

**Android:**

```bash
# Uygulama imzalama için key.properties dosyasını hazırlayın
# android/key.properties dosyası oluşturun (örnek: android/key.properties.example)

# Release APK
flutter build apk --release

# Release App Bundle (Play Store için)
flutter build appbundle --release
```

**iOS:**

```bash
# Release build
flutter build ios --release

# Xcode'da imzalama ayarlarını yapılandırdıktan sonra
cd ios && pod install && cd ..
flutter build ios --release
```

**Web:**

```bash
flutter build web --release
```

### 4.4 Build Sonrası Dosya Konumları

| Platform | Dosya Konumu |
|----------|--------------|
| Android APK | `build/app/outputs/flutter-apk/app-release.apk` |
| Android App Bundle | `build/app/outputs/bundle/release/app-release.aab` |
| iOS | `build/ios/iphoneos/Runner.app` |
| Web | `build/web/` |

---

## 5. Test Senaryoları

### 5.1 Kayıt OTP Testi

**Senaryo 1: Yeni Kullanıcı Kaydı**

1. Uygulamayı açın ve "Kayıt Ol" ekranına gidin
2. Geçerli bir e-posta adresi girin
3. "Doğrulama Kodu Gönder" butonuna tıklayın
4. E-posta kutusunu kontrol edin (6 haneli kod gelmeli)
5. Kodu uygulama girin
6. Kaydı tamamlayın

**Beklenen Sonuçlar:**
- ✅ E-posta 30 saniye içinde gelmeli
- ✅ Kod 6 haneli olmalı
- ✅ Kod girildiğinde doğrulama başarılı olmalı
- ✅ Kullanıcı kaydı tamamlanmalı

**Senaryo 2: Rate Limiting Testi**

1. Kayıt ekranında "Doğrulama Kodu Gönder" butonuna tıklayın
2. Hemen tekrar tıklayın

**Beklenen Sonuç:**
- ✅ İkinci tıklamada "1 dakika bekleyin" hatası görünmeli

**Senaryo 3: Süresi Dolmuş Kod**

1. Kod isteyin
2. 6 dakika bekleyin
3. Kodu girmeyi deneyin

**Beklenen Sonuç:**
- ✅ "Geçersiz veya süresi dolmuş kod" hatası görünmeli

### 5.2 Şifre Sıfırlama OTP Testi

**Senaryo 1: Geçerli Şifre Sıfırlama**

1. Giriş ekranından "Şifremi Unuttum" linkine tıklayın
2. Kayıtlı bir e-posta adresi girin
3. "Kod Gönder" butonuna tıklayın
4. E-postadaki kodu girin
5. Yeni şifrenizi belirleyin

**Beklenen Sonuçlar:**
- ✅ E-posta 30 saniye içinde gelmeli
- ✅ Kod doğrulandığında yeni şifre ekranı görünmeli
- ✅ Yeni şifre ile giriş yapılabilmeli

**Senaryo 2: Kayıtlı Olmayan E-posta**

1. Şifre sıfırlama ekranında kayıtlı olmayan bir e-posta girin
2. "Kod Gönder" butonuna tıklayın

**Beklenen Sonuç:**
- ✅ Güvenlik nedeniyle yine de "başarılı" mesajı görünmeli (email enumeration önleme)
- ✅ E-posta gönderilmemeli

### 5.3 Edge Function Testleri

**Postman/cURL ile test:**

```bash
# Kayıt OTP gönderme
curl -X POST https://your-project.supabase.co/functions/v1/send-registration-otp \
  -H "Content-Type: application/json" \
  -d '{"email": "test@example.com"}'

# Şifre sıfırlama OTP gönderme
curl -X POST https://your-project.supabase.co/functions/v1/send-password-reset-otp \
  -H "Content-Type: application/json" \
  -d '{"email": "existing-user@example.com"}'

# OTP doğrulama (RPC)
curl -X POST https://your-project.supabase.co/rest/v1/rpc/verify_registration_otp \
  -H "Content-Type: application/json" \
  -H "apikey: your-anon-key" \
  -d '{"p_email": "test@example.com", "p_code": "123456"}'
```

---

## 6. Sorun Giderme

### 6.1 OTP E-postası Gelmiyor

**Olası Nedenler:**

1. **RESEND_API_KEY tanımlı değil**
   - Dashboard > Edge Functions > Environment Variables kontrol edin
   - Değişken adının tam olarak `RESEND_API_KEY` olduğundan emin olun

2. **Resend API key geçersiz**
   - https://resend.com/api-keys adresinden key'in aktif olduğunu kontrol edin

3. **E-posta spam'e düşüyor**
   - Spam klasörünü kontrol edin
   - Resend dashboard'dan delivery durumunu kontrol edin

**Çözüm:**

```bash
# Edge Function logs kontrol
supabase functions logs send-registration-otp

# Environment variables kontrol
supabase functions list
```

### 6.2 "Kod oluşturulamadı" Hatası

**Olası Nedenler:**

1. **Tablo oluşturulmamış**
   - Migration SQL'ini tekrar çalıştırın

2. **RLS politikası sorunu**
   - Service role key'in doğru tanımlandığını kontrol edin

**Çözüm:**

```sql
-- Tablo var mı kontrol et
SELECT * FROM registration_otps LIMIT 1;

-- RLS politikası var mı kontrol et
SELECT * FROM pg_policies WHERE tablename = 'registration_otps';
```

### 6.3 OTP Doğrulama Başarısız

**Olası Nedenler:**

1. **Kod süresi dolmuş** (5 dakika)
   - Yeni kod isteyin

2. **Yanlış kod girildi**
   - E-postadaki kodu dikkatlice kontrol edin

3. **Farklı e-posta adresi**
   - Kodun gönderildiği e-posta ile aynı kullanılıyor mu?

**Çözüm:**

```sql
-- OTP kayıtlarını kontrol et
SELECT * FROM registration_otps 
WHERE email = 'test@example.com' 
ORDER BY created_at DESC;
```

### 6.4 Edge Function Deploy Hatası

**Hata: "Function not found"**

```bash
# Proje bağlantısını kontrol edin
supabase projects list

# Yeniden bağlayın
supabase link --project-ref your-project-id
```

**Hata: "Insufficient permissions"**

```bash
# Giriş durumunu kontrol edin
supabase login

# Veya token ile
supabase login --token your-access-token
```

### 6.5 Flutter Build Hatası

**Hata: "CocoaPods could not find compatible versions"**

```bash
cd ios
pod deintegrate
pod install
cd ..
flutter clean
flutter pub get
flutter build ios
```

**Hata: "Gradle build failed"**

```bash
cd android
./gradlew clean
cd ..
flutter clean
flutter pub get
flutter build apk
```

### 6.6 Yaygın Hata Kodları

| Hata Kodu | Anlamı | Çözüm |
|-----------|--------|-------|
| 400 | Geçersiz istek | E-posta formatını kontrol edin |
| 429 | Rate limit aşıldı | 1 dakika bekleyin |
| 500 | Sunucu hatası | Edge Function logs kontrol edin |
| 403 | OTP doğrulanmamış | Önce kodu doğrulayın |

---

## Ek Kaynaklar

- [Supabase Edge Functions Dokümantasyonu](https://supabase.com/docs/guides/functions)
- [Resend API Dokümantasyonu](https://resend.com/docs)
- [Flutter Deployment Rehberi](https://docs.flutter.dev/deployment)

---

## İletişim ve Destek

Deployment sırasında karşılaştığınız sorunlar için:
1. Bu rehberin Sorun Giderme bölümünü inceleyin
2. Supabase Dashboard'dan Edge Function logs kontrol edin
3. Proje ekibiyle iletişime geçin

---

*Son güncelleme: Mart 2026*
