# E-posta Doğrulama ve Şifre Yenileme Düzeltmeleri - Deployment Rehberi

## 📋 Özet

Bu güncelleme ile şu iki sorun düzeltildi:
1. **E-posta doğrulama butonu tıklanmıyor** - Gmail ve diğer e-posta istemcileri custom scheme linklerini (`cizreapp://`) engelliyordu
2. **Şifre yenileme ekranı çıkmıyor** - Redirect URL doğrudan ana sayfaya gidiyordu, auth callback sayfasına değil

## 🔧 Yapılan Değişiklikler

### 1. Yeni Auth Callback Sayfası
**Dosya**: `public/auth-callback.html`

Bu sayfa Supabase auth callback'lerini işler ve uygulamayı doğru deep link ile açar:
- Email doğrulama için: `cizreapp://verify`
- Şifre yenileme için: `cizreapp://reset-password`

### 2. E-posta Şablonları
**Dosyalar**: 
- `email_templates/confirm_signup_universal.html`
- `email_templates/reset_password_universal.html`

Her iki şablon da artık `{{ .ConfirmationURL }}` kullanıyor (Supabise tarafından sağlanan URL).

### 3. Kod Güncellemeleri

#### auth_service.dart
```dart
await _supabase.auth.resetPasswordForEmail(
  email,
  redirectTo: 'https://www.cizreapp.com/auth-callback.html',
);
```

#### login_screen_v2.dart
```dart
await Supabase.instance.client.auth.resend(
  type: OtpType.signup,
  email: email,
  emailRedirectTo: 'https://www.cizreapp.com/auth-callback.html',
);
```

#### register_screen_v2.dart
```dart
await Supabase.instance.client.auth.signUp(
  email: _emailController.text.trim(),
  password: _passwordController.text,
  data: {...},
  emailRedirectTo: 'https://www.cizreapp.com/auth-callback.html',
);
```

### 4. Android Manifest Güncellemesi
**Dosya**: `android/app/src/main/AndroidManifest.xml`

`/auth/v1/verify` path'i için intent-filter eklendi.

## 🚀 Deployment Adımları

### Adım 1: Web Dosyalarını Deploy Edin

`public/auth-callback.html` dosyasını web sunucunuza yükleyin:
- Hedef: `https://www.cizreapp.com/auth-callback.html`

Bu dosyanın erişilebilir olduğunu test edin:
```bash
curl https://www.cizreapp.com/auth-callback.html
```

### Adım 2: Supabase E-posta Şablonlarını Güncelleyin

1. [Supabase Dashboard](https://supabase.com/dashboard)'a gidin
2. Projenizi seçin
3. **Authentication** > **Email Templates** sayfasına gidin

#### Confirm Signup Şablonu
`email_templates/confirm_signup_universal.html` dosyasının içeriğini **Confirm Signup** şablonuna yapıştırın.

#### Reset Password Şablonu
`email_templates/reset_password_universal.html` dosyasının içeriğini **Reset Password** şablonuna yapıştırın.

### Adım 3: Site URL'ini Doğrulayın

Supabase Dashboard > **Authentication** > **URL Configuration**:

- **Site URL**: `https://www.cizreapp.com`
- **Redirect URLs**: `https://www.cizreapp.com/auth-callback.html`'yi ekleyin

### Adım 4: Mobil Uygulamayı Build Edin

```bash
# Android
flutter build apk --release

# iOS (Mac'te)
flutter build ios --release
```

## 🧪 Test Senaryoları

### Test 1: Email Doğrulama
1. Yeni bir kullanıcı kaydı yapın
2. E-posta kutunuzu kontrol edin
3. "E-postamı Doğrula" butonuna tıklayın
4. Tarayıcı açılmalı ve auth-callback.html sayfası görüntülenmeli
5. Otomatik olarak CizreApp uygulaması açılmalı

### Test 2: Şifre Yenileme
1. "Şifremi Unuttum" ekranına gidin
2. E-posta adresinizi girin
3. Şifre sıfırlama e-postasındaki butona tıklayın
4. Tarayıcı açılmalı ve auth-callback.html sayfası görüntülenmeli
5. Otomatik olarak CizreApp uygulaması şifre yenileme ekranıyla açılmalı

## 📝 Notlar

- Gmail gibi e-posta istemcileri `{{ .ConfirmationURL }}` linklerini güvenli olarak işler
- Custom scheme linkleri (`cizreapp://`) Gmail tarafından engellenir
- auth-callback.html sayfası tarayıcıda çalışır, ardından uygulamayı açar

## 🔍 Sorun Giderme

### Sorun: auth-callback.html açılmıyor
**Çözüm**: Web sunucunuzda dosyanın doğru yolda olduğunu doğrulayın

### Sorun: Uygulama açılmıyor
**Çözüm**: 
- Android'de intent-filter'ların doğru yapılandırıldığını kontrol edin
- iOS'te associated domains'in doğru yapılandırıldığını kontrol edin

### Sorun: Token hatası
**Çözüm**: Supabase redirect URL'lerinin doğru yapılandırıldığını kontrol edin
