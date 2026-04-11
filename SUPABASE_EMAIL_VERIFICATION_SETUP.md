# Supabase Email Doğrulama Kurulumu

## Sorun: "Doğrulama Başarısız" Hatası

Kayıt olduğunuzda gelen maildeki butona tıkladığınızda "doğrulama başarısız" hatası alıyorsanız, aşağıdaki adımları takip edin.

---

## 1. Supabase Dashboard Ayarları

### A. Redirect URLs (Yönlendirme URL'leri)

Supabase Dashboard'da şu ayarları yapın:

1. Supabase Dashboard'a gidin → Project'inizi seçin
2. **Authentication → URL Configuration** bölümüne gidin
3. **Redirect URLs** kısmına şu URL'leri ekleyin:

```
https://www.cizreapp.com/verify
https://www.cizreapp.com/recovery
http://localhost:3000/verify
cizreapp://login
cizreapp://recovery
```

⚠️ **ÖNEMLİ**: Her URL'i ayrı satırda ekleyin ve "Save" butonuna basın!

### B. Email Templates (Email Şablonları)

1. **Authentication → Email Templates** bölümüne gidin
2. **Confirm Signup** template'ini seçin
3. Aşağıdaki template'i kullanın:

```html
<h2>CizreApp - Kayıt Onayı</h2>
<p>CizreApp ailesine hoş geldiniz!</p>
<p>Hesabınızı aktifleştirmek için aşağıdaki butona tıklayın:</p>
<p><a href="{{ .ConfirmationURL }}">Mailimi Onaylıyorum</a></p>
<p><small>Link 1 saat içinde geçerlidir. Eğer bu işlemi siz yapmadıysanız, bu maili dikkate almayın.</small></p>
```

4. **Save** butonuna basın

### C. Email Auth Ayarları

1. **Authentication → Settings** bölümüne gidin
2. **Enable email confirmations** seçeneğinin **AÇIK** olduğundan emin olun
3. **Confirmation URL** için: `https://www.cizreapp.com/verify`
4. **Save** butonuna basın

---

## 2. Yaygın Sorunlar ve Çözümleri

### Sorun 1: "Link Süresi Dolmuş"

**Sebep**: Email doğrulama linkleri 1 saat sonra geçersiz olur.

**Çözüm**:
- Yeni bir hesap oluşturun
- Gelen maildeki linke **hemen** (1 saat içinde) tıklayın

### Sorun 2: "Access Denied" Hatası

**Sebep**: Redirect URL Supabase'de whitelist'e eklenmemiş.

**Çözüm**:
- Yukarıdaki "Redirect URLs" adımını tekrar kontrol edin
- `https://www.cizreapp.com/verify` URL'inin ekli olduğundan emin olun

### Sorun 3: Email Gelmiyor

**Çözüm**:
- Spam klasörünü kontrol edin
- Email provider'ınızın Supabase'den gelen mailleri engellemediğinden emin olun
- Supabase Dashboard → Authentication → Logs'u kontrol edin

### Sorun 4: Link Tıklandığında Sayfa Açılmıyor

**Çözüm**:
- `https://www.cizreapp.com/verify` sayfasının yayında olduğundan emin olun
- DNS kayıtlarını kontrol edin
- SSL sertifikasının geçerli olduğundan emin olun

---

## 3. Test Etme

### Manuel Test

1. Yeni bir email adresi ile kayıt olun
2. Email'in geldiğini kontrol edin (spam'e de bakın)
3. "Mailimi Onaylıyorum" butonuna tıklayın
4. `verify.html` sayfasına yönlendirilmelisiniz
5. "E-posta Doğrulandı!" mesajını görmelisiniz
6. Uygulama otomatik açılmalı

### Debug URL Parametreleri

Email linkine tıkladıktan sonra verify.html sayfasında URL'i kontrol edin:

**BAŞARILI**: 
```
https://www.cizreapp.com/verify?token=xxx&type=signup
```

**BAŞARISIZ**:
```
https://www.cizreapp.com/verify?error=access_denied
https://www.cizreapp.com/verify?error_code=otp_expired
```

---

## 4. Gelişmiş Ayarlar

### Rate Limiting

Supabase'de rate limiting var. Çok fazla kayıt denemesi yaparsanız:
- 1 dakika bekleyin
- Farklı bir email adresi deneyin

### Custom SMTP (Önerilen)

Daha güvenilir email delivery için:

1. **Authentication → Settings → SMTP Settings**
2. Kendi SMTP sunucunuzu ekleyin (Gmail, SendGrid, AWS SES, vb.)
3. Bu sayede spam filtreleri tarafından engellenmez

---

## 5. Sorun Devam Ederse

### Console Loglarını Kontrol Edin

1. Email linkine tıklayın
2. Tarayıcıda F12'ye basın
3. **Console** sekmesini açın
4. Hataları inceleyin

### Supabase Logs

1. Supabase Dashboard → **Logs**
2. **Auth Logs** sekmesine gidin
3. Hataları inceleyin

### Destek

Sorun devam ediyorsa:
- Supabase Dashboard'daki ayarların ekran görüntüsünü alın
- Console'daki hataları not edin
- Browser network sekmesindeki istekleri kontrol edin

---

## Hızlı Çözüm Checklist

✅ Redirect URLs eklenmiş mi? (`https://www.cizreapp.com/verify`)  
✅ Email confirmations açık mı?  
✅ Email template doğru mu?  
✅ Link 1 saat içinde mi tıklandı?  
✅ verify.html sayfası yayında mı?  
✅ Deep link (cizreapp://) yapılandırması tamam mı?  

---

## Sonraki Adımlar

1. Bu ayarları yaptıktan sonra **YENİ BİR HESAP** oluşturun
2. Email'i hemen kontrol edin
3. Linke 1 saat içinde tıklayın
4. Başarılı olursa, eski hesaplar için de çalışacaktır

**Not**: Eski kayıtlardaki linkler zaten expire olmuş olabilir. Yeni kayıt yapmanız önerilir.
