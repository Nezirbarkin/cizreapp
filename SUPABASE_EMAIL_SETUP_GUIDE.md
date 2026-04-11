# 📧 Supabase E-posta Doğrulama Mobil Deep Link Kurulumu

## Adım Adım Kurulum Rehberi

### 1️⃣ Supabase Dashboard'a Giriş

1. **Tarayıcınızda açın**: https://supabase.com/dashboard
2. **Giriş yapın** (kullanıcı adı/şifrenizle)
3. **Projenizi seçin**: `xsbukxkgtmdyickknqzf` (CizreApp)

---

### 2️⃣ Authentication Ayarları

**Sol menüden**:
- **Authentication** (🔐 ikonu) tıklayın
- **URL Configuration** alt sekmesine gidin

---

### 3️⃣ Redirect URLs Ekleyin

**Redirect URLs** bölümüne aşağıdaki URL'leri ekleyin:

```
cizreapp://verify
cizreapp://recovery
cizreapp://login
https://cizreapp.com/auth/callback
```

Her URL'i tek tek girin ve **Add** butonuna basın.

**✅ Kaydet**: "Save" butonuna tıklayın.

---

### 4️⃣ Email Templates - Confirm Signup Şablonu

**Sol menüden**:
- **Authentication** > **Email Templates**
- **Confirm signup** şablonunu seçin

**Mevcut şablonu silin** ve **aşağıdaki şablonu yapıştırın**:

```html
<div style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #e0e0e0; border-radius: 10px;">
    <div style="text-align: center; margin-bottom: 30px;">
        <h1 style="color: #2c3e50; margin: 0;">CizreApp</h1>
    </div>

    <div style="background-color: #ffffff; padding: 20px;">
        <h2 style="color: #333; font-size: 20px; text-align: center;">Kayıt İşleminizi Onaylayın</h2>
        <p style="color: #666; line-height: 1.6; text-align: center;">
            CizreApp ailesine hoş geldiniz! Hesabınızı aktifleştirmek ve güvenli bir şekilde giriş yapmak için lütfen aşağıdaki butona tıklayın.
        </p>

        <div style="text-align: center; margin-top: 30px; margin-bottom: 30px;">
            <!-- Mobil Uygulama Deep Link -->
            <a href="cizreapp://verify?token_hash={{ .TokenHash }}&type=signup" style="background-color: #007bff; color: white; padding: 14px 28px; text-decoration: none; border-radius: 5px; font-weight: bold; display: inline-block;">
                Mailimi Onaylıyorum
            </a>
        </div>

        <p style="color: #999; font-size: 12px; text-align: center;">
            Eğer butona tıklayamıyorsanız bu bağlantıyı tarayıcınıza yapıştırın:<br>
            <span style="color: #007bff; word-break: break-all;">cizreapp://verify?token_hash={{ .TokenHash }}&type=signup</span>
        </p>

        <p style="color: #aaa; font-size: 11px; text-align: center; margin-top: 20px;">
            Alternatif olarak web üzerinden onaylamak için:<br>
            <a href="{{ .ConfirmationURL }}" style="color: #007bff;">{{ .ConfirmationURL }}</a>
        </p>
    </div>

    <div style="border-top: 1px solid #eeeeee; margin-top: 20px; padding-top: 20px; text-align: center;">
        <p style="color: #aaa; font-size: 12px; margin: 0;">
            © 2026 CizreApp. Tüm hakları saklıdır.
        </p>
    </div>
</div>
```

**✅ Kaydet**: "Save" butonuna tıklayın.

---

### 5️⃣ Email Templates - Magic Link Şablonu (Opsiyonel)

Eğer şifresiz giriş de kullanıyorsanız:

- **Magic Link** şablonunu seçin
- Aynı şekilde `cizreapp://verify?token_hash={{ .TokenHash }}&type=magiclink` kullanın

---

### 6️⃣ Email Templates - Reset Password Şablonu

**Sol menüden**:
- **Authentication** > **Email Templates**
- **Reset password** şablonunu seçin

**Şablonu güncelleyin**:

```html
<div style="font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; max-width: 600px; margin: 0 auto; padding: 20px; border: 1px solid #e0e0e0; border-radius: 10px;">
    <div style="text-align: center; margin-bottom: 30px;">
        <h1 style="color: #2c3e50; margin: 0;">CizreApp</h1>
    </div>

    <div style="background-color: #ffffff; padding: 20px;">
        <h2 style="color: #333; font-size: 20px; text-align: center;">Şifre Sıfırlama</h2>
        <p style="color: #666; line-height: 1.6; text-align: center;">
            Şifrenizi sıfırlamak için aşağıdaki butona tıklayın. Bu işlemi siz yapmadıysanız, bu e-postayı görmezden gelebilirsiniz.
        </p>

        <div style="text-align: center; margin-top: 30px; margin-bottom: 30px;">
            <a href="cizreapp://recovery?token_hash={{ .TokenHash }}&type=recovery" style="background-color: #dc3545; color: white; padding: 14px 28px; text-decoration: none; border-radius: 5px; font-weight: bold; display: inline-block;">
                Şifremi Sıfırla
            </a>
        </div>

        <p style="color: #999; font-size: 12px; text-align: center;">
            Eğer butona tıklayamıyorsanız bu bağlantıyı tarayıcınıza yapıştırın:<br>
            <span style="color: #007bff; word-break: break-all;">cizreapp://recovery?token_hash={{ .TokenHash }}&type=recovery</span>
        </p>
    </div>

    <div style="border-top: 1px solid #eeeeee; margin-top: 20px; padding-top: 20px; text-align: center;">
        <p style="color: #aaa; font-size: 12px; margin: 0;">
            © 2026 CizreApp. Tüm hakları saklıdır.
        </p>
    </div>
</div>
```

**✅ Kaydet**: "Save" butonuna tıklayın.

---

### 7️⃣ Test Etme

#### Test 1: Yeni Kayıt
1. Uygulamayı telefonunuzda açın
2. Yeni bir hesap oluşturun (gerçek e-posta kullanın)
3. E-posta geldiğinde **"Mailimi Onaylıyorum"** butonuna tıklayın
4. **Beklenen sonuç**: 
   - Mobil cihazda uygulama otomatik açılmalı
   - E-posta doğrulama başarılı dialog gösterilmeli
   - Ana ekrana yönlendirilmeli

#### Test 2: Şifre Sıfırlama
1. Giriş ekranında **"Şifremi Unuttum"** tıklayın
2. E-postanızı girin
3. E-posta geldiğinde **"Şifremi Sıfırla"** butonuna tıklayın
4. **Beklenen sonuç**:
   - Mobil cihazda uygulama açılmalı
   - Şifre sıfırlama ekranı gösterilmeli

---

### 8️⃣ Sorun Giderme

#### ❌ "Mailimi Onaylıyorum" butonu web açıyor
**Çözüm**: 
- Supabase Email Templates'de `{{ .ConfirmationURL }}` yerine `cizreapp://verify?token_hash={{ .TokenHash }}&type=signup` kullandığınızdan emin olun
- Redirect URLs'e `cizreapp://verify` eklendiğinden emin olun

#### ❌ "This site can't be opened" hatası
**Çözüm**:
- Uygulamanın telefonunuzda yüklü olduğundan emin olun
- AndroidManifest.xml ve Info.plist dosyalarındaki deep link yapılandırmasını kontrol edin

#### ❌ Token geçersiz hatası
**Çözüm**:
- E-posta template'inde `{{ .TokenHash }}` kullandığınızdan emin olun (eski `{{ .Token }}` değil)
- Token'ın süresi dolmuş olabilir (15 dakika), yeni e-posta isteyin

---

### 9️⃣ Notlar

- **Deep Link Format**: `cizreapp://verify?token_hash={{ .TokenHash }}&type=signup`
- **Token geçerlilik süresi**: 15 dakika (Supabase default)
- **Yedek link**: Web üzerinden de onaylama yapılabilir (alt kısımda)

---

## ✅ Kurulum Tamamlandı!

Artık e-posta doğrulama linkine tıklandığında kullanıcılar web yerine doğrudan mobil uygulamaya yönlendirilecek.

**Önemli**: Her değişiklikten sonra **Save** butonuna basmayı unutmayın!
