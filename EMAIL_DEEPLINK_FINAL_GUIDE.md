# 📧 E-posta Doğrulama Mobil Deep Link - Son Kurulum Rehberi

## ✅ Yapılan Değişiklikler

### 1. Flutter Kod Güncellemeleri
- [`lib/main.dart`](lib/main.dart:336-382) - HTTPS Universal Links desteği eklendi
- [`lib/features/auth/screens/register_screen_v2.dart`](lib/features/auth/screens/register_screen_v2.dart:73) - `emailRedirectTo` HTTPS'e güncellendi
- [`lib/features/auth/services/auth_service.dart`](lib/features/auth/services/auth_service.dart:39) - `redirectTo` HTTPS'e güncellendi

### 2. Oluşturulan Dosyalar
- [`ios/Runner/entitlements.plist`](ios/Runner/entitlements.plist) - iOS Associated Domains
- [`web/.well-known/assetlinks.json`](web/.well-known/assetlinks.json) - Android App Links
- [`web/.well-known/apple-app-site-association`](web/.well-known/apple-app-site-association) - iOS Universal Links
- [`web/verify.html`](web/verify.html) - E-posta doğrulama yönlendirme sayfası
- [`web/recovery.html`](web/recovery.html) - Şifre sıfırlama yönlendirme sayfası
- [`email_templates/confirm_signup_universal.html`](email_templates/confirm_signup_universal.html) - Supabase e-posta şablonu
- [`email_templates/reset_password_universal.html`](email_templates/reset_password_universal.html) - Şifre sıfırlama e-posta şablonu

---

## 🔧 Yapmanız Gerekenler

### Adım 1: Sunucu Dosyalarını Yükleyin (cizreapp.com)

Aşağıdaki dosyaları `cizreapp.com` sunucunuza yükleyin:

```
cizreapp.com/
├── .well-known/
│   ├── assetlinks.json          → Android için
│   └── apple-app-site-association → iOS için
├── verify.html                  → E-posta doğrulama
└── recovery.html                → Şifre sıfırlama
```

**ÖNEMLİ:** [`assetlinks.json`](web/.well-known/assetlinks.json) dosyasında SHA256 fingerprint'lerinizi ekleyin:

```bash
# SHA256 almak için:
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey
```

**ÖNEMLİ:** [`apple-app-site-association`](web/.well-known/apple-app-site-association) dosyasında `TEAMID.com.cizreapp.app` yerine gerçek Apple Team ID'nizi yazın.

### Adım 2: Supabase Email Templates Güncelleyin

1. https://supabase.com/dashboard'a gidin
2. Projenizi seçin
3. **Authentication** > **Email Templates** > **Confirm signup**
4. [`email_templates/confirm_signup_universal.html`](email_templates/confirm_signup_universal.html) içeriğini yapıştırın
5. **Save**

**Reset Password** için de aynısını yapın:
- **Authentication** > **Email Templates** > **Reset password**
- [`email_templates/reset_password_universal.html`](email_templates/reset_password_universal.html) içeriğini yapıştırın
- **Save**

### Adım 3: Supabase Redirect URLs Ekleyin

**Authentication** > **URL Configuration** bölümüne ekleyin:

```
https://www.cizreapp.com/verify
https://www.cizreapp.com/recovery
https://www.cizreapp.com/auth/callback
```

### Adım 4: iOS Xcode'da Associated Domains Ekleyin

1. Xcode'da `ios/Runner.xcworkspace` açın
2. **Runner** target > **Signing & Capabilities**
3. **+ Capability** > **Associated Domains**
4. Şunları ekleyin:
   - `applinks:www.cizreapp.com`
   - `applinks:cizreapp.com`
   - `webcredentials:www.cizreapp.com`
   - `webcredentials:cizreapp.com`

### Adım 5: Android - App Links Zaten Yapılandırılmış

[`android/app/src/main/AndroidManifest.xml`](android/app/src/main/AndroidManifest.xml:38-51) dosyasında App Links zaten mevcut.

### Adım 6: Uygulamayı Derleyin ve Yükleyin

```bash
# Android
flutter build apk --release

# iOS
flutter build ios --release
```

---

## 🧪 Test

1. Uygulamayı telefonunuzdan silin ve yeniden yükleyin
2. Yeni bir hesap oluşturun
3. E-posta geldiğinde **"Mailimi Onaylıyorum"** butonuna tıklayın
4. **Beklenen sonuç:**
   - Tarayıcı açılır
   - `verify.html` yüklenir
   - Uygulama otomatik açılır
   - E-posta doğrulama başarılı mesajı gösterilir

---

## 📝 Hızlı Kontrol Listesi

- [ ] Sunucu dosyaları yüklendi (`assetlinks.json`, `apple-app-site-association`)
- [ ] SHA256 fingerprint'ler eklendi
- [ ] Apple Team ID eklendi
- [ ] Supabase email templates güncellendi
- [ ] Supabase redirect URLs eklendi
- [ ] iOS Associated Domains Xcode'da eklendi
- [ ] Uygulama yeniden derlendi ve yüklendi
- [ ] Test başarılı

---

## 🐛 Sorun Giderme

**"Uygulama açılmıyor"** → Sunucu dosyalarının erişilebilir olduğunu kontrol edin:
- https://cizreapp.com/.well-known/assetlinks.json
- https://cizreapp.com/.well-known/apple-app-site-association

**"Invalid token"** → Token URL'de geçtiğinden emin olun

**Gmail'de butona tıklanmıyor** → HTTPS URL kullandığınızdan emin olun (`https://www.cizreapp.com/verify`)

---

## 📄 Kullanılan Şablonlar

E-posta linkleri artık şöyle görünecek:

```
https://www.cizreapp.com/verify?token_hash=xyz&type=signup
```

Bu linke tıklandığında:
1. Tarayıcı açılır
2. `verify.html` yüklenir
3. JavaScript otomatik olarak `cizreapp://verify?token_hash=xyz&type=signup` deep link'ini çağırır
4. Mobil uygulama açılır
5. Supabase token'ı doğrular
6. Kullanıcı ana ekrana yönlendirilir

**Böylece Gmail/Outlook gibi e-posta uygulamalarında da buton çalışır!**
