# 🚀 CizreApp Universal Links / App Links Kurulum Rehberi

E-posta doğrulama linklerinin mobil uygulamayı açması için tam kurulum rehberi.

---

## 📋 İçindekiler

1. [Sunucu Kurulumu](#1-sunucu-kurulumu)
2. [Android Kurulumu](#2-android-kurulumu)
3. [iOS Kurulumu](#3-ios-kurulumu)
4. [Supabase Email Templates](#4-supabase-email-templates)
5. [Flutter Kod Güncellemeleri](#5-flutter-kod-güncellemeleri)
6. [Test](#6-test)

---

## 1. Sunucu Kurulumu

### 1.1 Dosyaları cizreapp.com Sunucusuna Yükleyin

Oluşturulan dosyaları sunucunuza yükleyin:

```
cizreapp.com/
├── .well-known/
│   ├── assetlinks.json          → Android App Links
│   └── apple-app-site-association → iOS Universal Links
├── verify.html                  → E-posta doğrulama sayfası
└── recovery.html                → Şifre sıfırlama sayfası
```

### 1.2 assetlinks.json Dosyasını Düzenleyin

Dosyayı sunucuya yüklemeden önce SHA256 fingerprint'lerinizi ekleyin:

**Debug SHA256 almak için:**
```bash
keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey
```

**Release SHA256 almak için:**
```bash
keytool -list -v -keystore /path/to/your/keystore.jks -alias your-key-alias
```

[`web/.well-known/assetlinks.json`](web/.well-known/assetlinks.json) dosyasında `YOUR_DEBUG_SHA256_FINGERPRINT_HERE` ve `YOUR_RELEASE_SHA256_FINGERPRINT_HERE` kısımlarını gerçek fingerprint'lerinizle değiştirin.

**Örnek:**
```json
[{
  "relation": ["delegate_permission/common.handle_all_urls"],
  "target": {
    "namespace": "android_app",
    "package_name": "com.cizreapp.app",
    "sha256_cert_fingerprints": [
      "14:6D:E9:83:C5:73:06:50:D8:EE:B9:95:2F:34:FC:64:16:A0:83:42:E6:1D:BE:A8:2A:DE:4D:F5:BD:ED:3A:E2",
      "27:51:A2:45:1B:F3:89:7C:4A:9D:56:7E:8B:92:4C:1D:5E:6F:7A:9B:3C:4D:5E:6F:7A:9B:3C:4D:5E"
    ]
  }
}]
```

### 1.3 apple-app-site-association Dosyasını Düzenleyin

[`web/.well-known/apple-app-site-association`](web/.well-known/apple-app-site-association) dosyasında `TEAMID.com.cizreapp.app` kısmını gerçek Apple Team ID ve Bundle Identifier ile değiştirin.

**Apple Team ID'nizi bulmak için:**
- Apple Developer Console'a gidin
- Account > Membership sekmesine tıklayın
- Team ID bölümündeki 10 karakterlik kodunuz

**Örnek:**
```json
{
  "applinks": {
    "apps": [],
    "details": [
      {
        "appIDs": ["ABC1234567.com.cizreapp.app"],
        "components": [
          { "/": "/verify/*" },
          { "/": "/recovery/*" },
          { "/": "/auth/callback*" }
        ]
      }
    ]
  }
}
```

### 1.4 Dosya Erişim Kontrolü

Dosyaların herkes tarafından erişilebilir olduğundan emin olun:

```bash
# Sunucuda çalıştırın
chmod 644 .well-known/assetlinks.json
chmod 644 .well-known/apple-app-site-association
```

Test URL'leri:
- https://cizreapp.com/.well-known/assetlinks.json
- https://cizreapp.com/.well-known/apple-app-site-association

Bu URL'ler 200 OK döndürmeli ve JSON içermelidir.

---

## 2. Android Kurulumu

### 2.1 AndroidManifest.xml Zaten Yapılandırılmış

[`android/app/src/main/AndroidManifest.xml`](android/app/src/main/AndroidManifest.xml:38-51) dosyasında App Links zaten mevcut:

```xml
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data
        android:scheme="https"
        android:host="cizreapp.com"
        android:pathPrefix="/recovery" />
    <data
        android:scheme="https"
        android:host="cizreapp.com"
        android:pathPrefix="/verify" />
</intent-filter>
```

### 2.2 Uygulamayı Derleyin ve Yükleyin

```bash
# Debug build
flutter build apk --debug

# Release build
flutter build apk --release
```

### 2.3 App Links Doğrulaması

Uygulamayı ilk yüklediğinizde Android otomatik olarak assetlinks.json dosyasını doğrular. Doğrulama başarısız olursa deep link çalışmaz.

**Doğrulama komutu:**
```bash
adb shell am start -a android.intent.action.VIEW \
  -c android.intent.category.BROWSABLE \
  -d "https://www.cizreapp.com/verify"
```

---

## 3. iOS Kurulumu

### 3.1 Associated Domains Entitlements Ekleyin

Oluşturulan [`ios/Runner/entitlements.plist`](ios/Runner/entitlements.plist) dosyasını projenize ekleyin.

### 3.2 Xcode'da Associated Domains'i Aktifleştirin

1. **Xcode**'da `ios/Runner.xcworkspace` dosyasını açın
2. **Runner** target'ını seçin
3. **Signing & Capabilities** sekmesine gidin
4. **+ Capability** butonuna tıklayın
5. **Associated Domains** seçin
6. Aşağıdaki domain'leri ekleyin:

```
applinks:www.cizreapp.com
applinks:cizreapp.com
webcredentials:www.cizreapp.com
webcredentials:cizreapp.com
```

### 3.3 Info.plist Güncelleme

[`ios/Runner/Info.plist`](ios/Runner/Info.plist) dosyasında URL scheme zaten mevcut.

### 3.4 iOS Uygulamasını Derleyin

```bash
cd ios
pod install
cd ..

# iOS Simulator veya gerçek cihazda derleyin
flutter run
```

---

## 4. Supabase Email Templates

### 4.1 Supabase Dashboard'a Gidin

1. https://supabase.com/dashboard
2. Projenizi seçin
3. **Authentication** > **Email Templates**

### 4.2 Confirm Signup Şablonu

**Confirm signup** şablonunu düzenleyin ve [`email_templates/confirm_signup_universal.html`](email_templates/confirm_signup_universal.html) içeriğini yapıştırın:

```html
<div style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #e0e0e0; border-radius: 10px;">
    <div style="text-align: center; margin-bottom: 30px;">
        <h1 style="color: #2c3e50; margin: 0;">CizreApp</h1>
    </div>

    <div style="background-color: #ffffff; padding: 20px;">
        <h2 style="color: #333; font-size: 20px; text-align: center;">Kayıt İşleminizi Onaylayın</h2>
        <p style="color: #666; line-height: 1.6; text-align: center;">
            CizreApp ailesine hoş geldiniz! Hesabınızı aktifleştirmek için aşağıdaki butona tıklayın.
        </p>

        <div style="text-align: center; margin-top: 30px; margin-bottom: 30px;">
            <a href="https://www.cizreapp.com/verify?token_hash={{ .TokenHash }}&type=signup" style="background-color: #007bff; color: white; padding: 16px 32px; text-decoration: none; border-radius: 8px; font-weight: bold; display: inline-block; font-size: 16px;">
                ✉️ Mailimi Onaylıyorum
            </a>
        </div>

        <p style="color: #999; font-size: 12px; text-align: center;">
            Butona tıkladığınızda mobil uygulamamız açılacaktır.
        </p>

        <div style="background-color: #f8f9fa; padding: 15px; border-radius: 8px; margin-top: 20px;">
            <p style="color: #666; font-size: 13px; margin: 0; text-align: center;">
                <strong>Neden uygulama açılmıyor?</strong><br>
                CizreApp mobil uygulamasını telefonunuza indirin:<br>
                <a href="https://apps.apple.com/app/idYOUR_APP_ID" style="color: #007bff;">App Store</a> • 
                <a href="https://play.google.com/store/apps/details?id=com.cizreapp.app" style="color: #007bff;">Google Play</a>
            </p>
        </div>
    </div>

    <div style="border-top: 1px solid #eeeeee; margin-top: 20px; padding-top: 20px; text-align: center;">
        <p style="color: #aaa; font-size: 12px; margin: 0;">
            © 2026 CizreApp. Tüm hakları saklıdır.
        </p>
    </div>
</div>
```

### 4.3 Reset Password Şablonu

**Reset password** şablonunu düzenleyin ve [`email_templates/reset_password_universal.html`](email_templates/reset_password_universal.html) içeriğini yapıştırın.

### 4.4 Supabase Redirect URLs

**Authentication** > **URL Configuration** bölümüne ekleyin:

```
https://www.cizreapp.com/verify
https://www.cizreapp.com/recovery
https://www.cizreapp.com/auth/callback
cizreapp://verify
cizreapp://recovery
cizreapp://login
```

---

## 5. Flutter Kod Güncellemeleri

### 5.1 register_screen_v2.dart - emailRedirectTo Güncelleme

Kod zaten doğru yapılandırılmış:

```dart
emailRedirectTo: 'https://www.cizreapp.com/verify',
```

Ancak güncellemek için [`lib/features/auth/screens/register_screen_v2.dart`](lib/features/auth/screens/register_screen_v2.dart:73):

```dart
emailRedirectTo: 'https://www.cizreapp.com/verify',
```

### 5.2 auth_service.dart - redirectTo Güncelleme

[`lib/features/auth/services/auth_service.dart`](lib/features/auth/services/auth_service.dart:39):

```dart
redirectTo: 'https://www.cizreapp.com/recovery',
```

---

## 6. Test

### 6.1 E-posta Doğrulama Testi

1. Uygulamayı silin ve yeniden yükleyin (yeni install)
2. Yeni bir hesap oluşturun
3. E-posta geldiğinde **"Mailimi Onaylıyorum"** butonuna tıklayın
4. **Beklenen sonuç**:
   - Tarayıcı açılır
   - `verify.html` sayfası yüklenir
   - Uygulama otomatik açılır
   - Ana ekrana yönlendirilir

### 6.2 Şifre Sıfırlama Testi

1. **"Şifremi Unuttum"** butonuna tıklayın
2. E-postanızı girin
3. E-posta geldiğinde **"Şifremi Sıfırla"** butonuna tıklayın
4. **Beklenen sonuç**:
   - Uygulama açılır
   - Şifre sıfırlama ekranı gösterilir

### 6.3 Doğrulama Komutları

**Android App Links Test:**
```bash
adb shell am start -a android.intent.action.VIEW \
  -c android.intent.category.BROWSABLE \
  -d "https://www.cizreapp.com/verify?token_hash=test&type=signup"
```

**iOS Universal Links Test:**
```bash
xcrun simctl openurl booted "https://www.cizreapp.com/verify?token_hash=test&type=signup"
```

---

## 🔧 Sorun Giderme

### "Uygulama açılmıyor" hatası

1. Uygulama telefonunuzda yüklü mü?
2. assetlinks.json ve apple-app-site-association dosyaları erişilebilir mi?
3. SHA256 fingerprint ve Team ID doğru mu?

### "Invalid link" hatası

1. Token hash'i URL'de geçtiğinden emin olun
2. Supabase redirect URLs'leri doğru yapılandırılmış mı?

### Gmail'de butona tıklanmıyor

1. HTTPS URL kullanıyor musunuz? (cizreapp:// değil, https://www.cizreapp.com)
2. Universal Links doğru yapılandırılmış mı?

---

## ✅ Kurulum Tamamlandı

Artık e-posta doğrulama linkleri Gmail/Outlook gibi uygulamalarda da çalışacak!
