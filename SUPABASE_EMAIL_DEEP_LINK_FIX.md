# Supabase E-posta Deep Link Düzeltmesi

## Sorun
E-posta doğrulama linkine tıklandığında kullanıcılar web sitesine yönlendiriliyor, mobil uygulamaya yönlendirilmiyor.

## Çözüm

### 1. Supabase Dashboard'da E-posta Şablonlarını Güncelle

1. **Supabase Dashboard'a Git**: https://supabase.com/dashboard
2. **Projenizi Seçin**
3. **Authentication** > **Email Templates** bölümüne gidin
4. **Confirm Signup** şablonunu düzenleyin

### 2. E-posta Şablonu URL Yapılandırması

#### Mevcut Yapı (Yanlış):
```html
<a href="{{ .SiteURL }}/auth/confirm?token={{ .Token }}">E-postanızı Onaylayın</a>
```

#### Yeni Yapı (Doğru):
```html
<a href="{{ .RedirectTo }}?token_hash={{ .TokenHash }}&type=signup">E-postanızı Onaylayın</a>
```

veya daha detaylı:

```html
<a href="cizreapp://verify?token_hash={{ .TokenHash }}&type=signup">E-postanızı Onaylayın</a>
```

### 3. Tam E-posta Şablonu Örneği

```html
<h2>E-posta Adresinizi Onaylayın</h2>

<p>Merhaba,</p>

<p>CizreApp'e hoş geldiniz! Hesabınızı aktif hale getirmek için aşağıdaki butona tıklayın:</p>

<a href="{{ .ConfirmationURL }}" 
   style="display: inline-block; padding: 12px 24px; background-color: #1ABC9C; 
          color: white; text-decoration: none; border-radius: 6px; font-weight: bold;">
  Hesabımı Onayla
</a>

<p>Eğer buton çalışmıyorsa, aşağıdaki linki kopyalayıp tarayıcınıza yapıştırın:</p>
<p>{{ .ConfirmationURL }}</p>

<p>Bu işlemi siz yapmadıysanız, bu e-postayı görmezden gelebilirsiniz.</p>

<p>Teşekkürler,<br>CizreApp Ekibi</p>
```

### 4. Site URL Ayarları

**Authentication** > **URL Configuration** bölümünde:

- **Site URL**: `cizreapp://` (mobil için) veya `https://cizreapp.com` (web için)
- **Redirect URLs**: 
  ```
  cizreapp://verify
  cizreapp://recovery
  cizreapp://login
  https://cizreapp.com/*
  ```

### 5. Uygulama Kodunda Mevcut Durum

Kod zaten doğru yapılandırılmış:

```dart
// register_screen_v2.dart (satır 73)
emailRedirectTo: 'cizreapp://verify',

// auth_service.dart (satır 39)
redirectTo: 'cizreapp://recovery',
```

### 6. Deep Link Yapılandırması (Zaten Mevcut)

#### Android - AndroidManifest.xml
```xml
<!-- App Link (cizreapp://) - Email Doğrulama -->
<intent-filter>
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data
        android:scheme="cizreapp"
        android:host="verify" />
</intent-filter>
```

#### iOS - Info.plist
```xml
<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>cizreapp</string>
        </array>
    </dict>
</array>
```

### 7. Test Senaryosu

1. Uygulamadan yeni kullanıcı kaydı yapın
2. E-posta geldiğinde "Onaylıyorum" butonuna tıklayın
3. Mobil cihazda uygulama otomatik açılmalı
4. E-posta doğrulama success dialog gösterilmeli
5. Ana ekrana yönlendirilmeli

### 8. Alternatif Çözüm: Universal Links (Gelişmiş)

Eğer deep link çalışmazsa, Universal Links kullanabilirsiniz:

#### Android - App Links
```xml
<intent-filter android:autoVerify="true">
    <action android:name="android.intent.action.VIEW" />
    <category android:name="android.intent.category.DEFAULT" />
    <category android:name="android.intent.category.BROWSABLE" />
    <data
        android:scheme="https"
        android:host="cizreapp.com"
        android:pathPrefix="/verify" />
</intent-filter>
```

Bu durumda Supabase'de:
- **Site URL**: `https://cizreapp.com`
- **Redirect URLs**: `https://cizreapp.com/verify/*`

Ve web sunucunuzda `/.well-known/assetlinks.json` dosyası oluşturun.

## Özet

Ana sorun Supabase Dashboard'daki e-posta şablonlarında. `{{ .ConfirmationURL }}` veya `{{ .RedirectTo }}` kullanarak mobil deep link'in çalışmasını sağlayın.

**Önemli**: E-posta şablonunu değiştirdikten sonra test e-postası göndererek linkin doğru çalıştığından emin olun.
