# Email Doğrulama Test Senaryoları

Bu dokümanda CizreApp email doğrulama sisteminin test senaryoları ve beklenen sonuçları açıklanmaktadır.

---

## Test Ortamı Hazırlığı

### Gereksinimler

- [ ] Supabase Dashboard erişimi
- [ ] Test email adresleri (en az 3 farklı)
- [ ] CizreApp mobil uygulama (iOS/Android)
- [ ] Web tarayıcı (Chrome/Safari önerilir)
- [ ] İnternet bağlantısı

### Ön Kontroller

1. **Supabase Redirect URLs Kontrolü**
   ```
   https://www.cizreapp.com/verify
   https://www.cizreapp.com/recovery
   cizreapp://login
   ```
   ✅ Tüm URL'ler eklenmiş olmalı

2. **Email Confirmations Açık mı?**
   - Authentication → Settings → Enable email confirmations: **ON**

3. **Email Template Kontrolü**
   - Authentication → Email Templates → Confirm Signup
   - Template'de `{{ .ConfirmationURL }}` var mı?

---

## Test Senaryoları

### 🧪 Test 1: Normal Kayıt ve Doğrulama Akışı

**Amaç**: Başarılı bir kayıt ve email doğrulama sürecini test etmek

**Adımlar**:
1. Uygulamayı açın
2. "Kayıt Ol" sayfasına gidin
3. Geçerli bilgilerle form doldurun:
   - Kullanıcı adı: `testuser001`
   - Ad Soyad: `Test User`
   - Email: `test1@example.com`
   - Şifre: `Test1234!`
4. KVKK kutucuğunu işaretleyin
5. "Kayıt Ol" butonuna tıklayın

**Beklenen Sonuç**:
- ✅ "E-posta Doğrulaması Gerekli" dialog'u görünür
- ✅ Email adresiniz gösterilir
- ✅ Dialog'u kapatın ve email kutunuzu kontrol edin
- ✅ "CizreApp - Kayıt Onayı" konulu mail gelir (5 dakika içinde)
- ✅ Spam klasörünü de kontrol edin

**Email'i Doğrulama**:
6. Email'deki "Mailimi Onaylıyorum" butonuna tıklayın
7. Tarayıcıda `verify.html` sayfası açılır
8. Sayfa "E-posta Doğrulandı!" mesajını gösterir
9. Uygulama otomatik açılır
10. Giriş yapabilirsiniz

**Başarı Kriterleri**:
- [ ] Email 5 dakika içinde geldi
- [ ] Link tıklandığında verify sayfası açıldı
- [ ] "E-posta Doğrulandı!" mesajı görüldü
- [ ] Uygulama otomatik açıldı
- [ ] Giriş yapabildiniz

---

### 🧪 Test 2: Süresi Dolmuş Link

**Amaç**: 1 saat sonra link'in geçersiz olduğunu test etmek

**Adımlar**:
1. Yeni bir email ile kayıt olun: `test2@example.com`
2. Gelen email'i **AÇMAYIN**
3. 1 saat 5 dakika bekleyin (veya sistem saatini 1 saat ileri alın)
4. Email'deki linke tıklayın

**Beklenen Sonuç**:
- ✅ verify.html sayfası açılır
- ✅ "⏰ Link Süresi Dolmuş" mesajı görünür
- ✅ Hata kodu: `otp_expired` veya `access_denied`
- ✅ Çözüm adımları gösterilir

**Debug Bilgileri Kontrolü**:
5. "Debug Bilgilerini Göster" butonuna tıklayın
6. URL parametrelerini kontrol edin

**Beklenen Parametreler**:
```
error: access_denied
error_code: otp_expired
error_description: Email link is invalid or has expired
```

**Başarı Kriterleri**:
- [ ] Süresi dolmuş uyarısı gösterildi
- [ ] Kullanıcı bilgilendirildi
- [ ] Debug bilgileri görüntülendi
- [ ] Çözüm adımları açık

---

### 🧪 Test 3: Email Yeniden Gönderme

**Amaç**: Doğrulama emailini yeniden gönderme özelliğini test etmek

**Adımlar**:
1. Yeni bir email ile kayıt olun: `test3@example.com`
2. "E-posta Doğrulaması Gerekli" dialog'unda
3. "Doğrulama E-postasını Yeniden Gönder" butonuna tıklayın

**Beklenen Sonuç**:
- ✅ Yeşil başarı mesajı: "Doğrulama e-postası yeniden gönderildi!"
- ✅ Yeni email 2-3 dakika içinde gelir
- ✅ Yeni email'deki link çalışır
- ✅ Eski link artık geçersizdir

**Rate Limiting Testi**:
4. "Yeniden Gönder" butonuna 5 kez arka arkaya tıklayın

**Beklenen Sonuç**:
- ✅ İlk 2-3 deneme başarılı
- ✅ Sonra rate limit hatası alınır
- ✅ Hata mesajı: "⏱️ Çok fazla işlem yaptınız. Lütfen 1 dakika bekleyip tekrar deneyin."

**Başarı Kriterleri**:
- [ ] Yeniden gönderme çalıştı
- [ ] Yeni email geldi
- [ ] Rate limiting çalışıyor
- [ ] Kullanıcı bilgilendirildi

---

### 🧪 Test 4: Birden Fazla Kayıt Denemesi

**Amaç**: Aynı email ile birden fazla kayıt yapma durumunu test etmek

**Adımlar**:
1. Email ile kayıt olun: `test4@example.com`
2. Email'i doğrulamadan, aynı email ile tekrar kayıt olmayı deneyin

**Beklenen Sonuç**:
- ✅ Hata mesajı: "Bu email adresi zaten kayıtlı"
- ✅ Kayıt işlemi engellenır
- ✅ Kullanıcıya giriş yapması önerilir

**Başarı Kriterleri**:
- [ ] Duplicate email engellendi
- [ ] Açık hata mesajı gösterildi
- [ ] Kullanıcı yönlendirildi

---

### 🧪 Test 5: Farklı Email Sağlayıcıları

**Amaç**: Farklı email sağlayıcılarıyla uyumluluğu test etmek

**Test Email Adresleri**:
1. Gmail: `testuser@gmail.com`
2. Outlook: `testuser@outlook.com`
3. Yahoo: `testuser@yahoo.com`
4. Custom domain: `testuser@cizreapp.com`

**Her biri için**:
- Kayıt olun
- Email'in geldiğini kontrol edin
- Spam klasörünü kontrol edin
- Link'e tıklayın
- Doğrulama başarılı olsun

**Başarı Kriterleri**:
- [ ] Gmail'de çalıştı
- [ ] Outlook'da çalıştı
- [ ] Yahoo'da çalıştı
- [ ] Custom domain'de çalıştı

---

### 🧪 Test 6: Mobil ve Web Uyumluluk

**Amaç**: Farklı cihazlarda email doğrulamanın çalışmasını test etmek

**Senaryolar**:

**6A. Mobilde Kayıt, Mobilde Doğrulama**
1. Mobil uygulamada kayıt olun
2. Mobil cihazda email'i açın
3. Linke tıklayın
4. Uygulama açılmalı

**6B. Mobilde Kayıt, Bilgisayarda Doğrulama**
1. Mobil uygulamada kayıt olun
2. Bilgisayarda email'i açın
3. Linke tıklayın
4. verify.html sayfası açılmalı
5. "Uygulamayı Aç" butonu çalışmalı (varsa)

**6C. Farklı Tarayıcılar**
- Chrome
- Safari
- Firefox
- Edge

**Başarı Kriterleri**:
- [ ] iOS'ta çalışıyor
- [ ] Android'de çalışıyor
- [ ] Web'de çalışıyor
- [ ] Cross-platform doğrulama çalışıyor

---

### 🧪 Test 7: Hata Durumları

**Amaç**: Olası hata senaryolarını test etmek

**7A. İnternet Bağlantısı Yok**
1. Kayıt olmayı deneyin (WiFi kapalı)
- Beklenen: "İnternet bağlantınızı kontrol edin"

**7B. Geçersiz Email Format**
1. Email: `invalidemail` (@ işareti yok)
- Beklenen: "Geçerli e-posta adresi girin"

**7C. Çok Kısa Şifre**
1. Şifre: `12345` (6 karakterden az)
- Beklenen: "Şifre en az 6 karakter olmalıdır"

**7D. Kullanıcı Adı Zaten Alınmış**
1. Daha önce kullanılan username'i deneyin
- Beklenen: "Bu kullanıcı adı zaten kullanılıyor"

**Başarı Kriterleri**:
- [ ] Tüm hatalar yakalandı
- [ ] Kullanıcı dostu mesajlar gösterildi
- [ ] Türkçe çeviriler doğru

---

### 🧪 Test 8: Performans Testi

**Amaç**: Sistemin performansını test etmek

**Metrikler**:
1. **Email Gönderme Süresi**: < 30 saniye
2. **Link Tıklama → Sayfa Açılma**: < 2 saniye
3. **Doğrulama → Uygulama Açılma**: < 3 saniye
4. **Yeniden Gönderme Süresi**: < 10 saniye

**Ölçüm Yöntemi**:
- Kronometre kullanın
- Her adımı kaydedin
- 5 test ortalaması alın

**Başarı Kriterleri**:
- [ ] Email < 30 saniye
- [ ] Sayfa açılma < 2 saniye
- [ ] Uygulama açılma < 3 saniye
- [ ] Yeniden gönderme < 10 saniye

---

## Test Sonuçları Formu

### Test Tarihi: __________
### Test Eden: __________
### Ortam: Production / Staging

| Test No | Test Adı | Durum | Notlar |
|---------|----------|-------|--------|
| Test 1 | Normal Kayıt | ✅ / ❌ | |
| Test 2 | Süresi Dolmuş Link | ✅ / ❌ | |
| Test 3 | Email Yeniden Gönderme | ✅ / ❌ | |
| Test 4 | Birden Fazla Kayıt | ✅ / ❌ | |
| Test 5 | Email Sağlayıcıları | ✅ / ❌ | |
| Test 6 | Mobil/Web Uyumluluk | ✅ / ❌ | |
| Test 7 | Hata Durumları | ✅ / ❌ | |
| Test 8 | Performans | ✅ / ❌ | |

### Genel Notlar:
```
[Buraya test sırasında karşılaşılan özel durumları not edin]
```

---

## Hata Raporlama

Bir hata bulduğunuzda, aşağıdaki bilgileri toplayın:

### Hata Rapor Şablonu

```markdown
## Hata Açıklaması
[Hatayı kısaca açıklayın]

## Adımlar
1. [İlk adım]
2. [İkinci adım]
3. [Hata oluştuğu adım]

## Beklenen Davranış
[Ne olmasını bekliyordunuz?]

## Gerçekleşen Davranış
[Ne oldu?]

## Ekran Görüntüleri
[Varsa ekleyin]

## Ortam Bilgileri
- Cihaz: [iOS/Android/Web]
- Versiyon: [Uygulama versiyonu]
- Email sağlayıcı: [Gmail/Outlook/vb.]
- Tarayıcı: [Chrome/Safari/vb.]

## Console Logları
[F12 → Console'dan kopyalayın]

## URL Parametreleri
[verify.html sayfasındaki debug bilgilerini ekleyin]
```

---

## Automation Test Script'leri

### Cypress Test Örneği (Web)

```javascript
describe('Email Verification Flow', () => {
  it('should complete registration and email verification', () => {
    // Kayıt sayfasına git
    cy.visit('/register');
    
    // Form doldur
    cy.get('input[name="username"]').type('testuser');
    cy.get('input[name="fullName"]').type('Test User');
    cy.get('input[name="email"]').type('test@example.com');
    cy.get('input[name="password"]').type('Test1234!');
    cy.get('input[name="confirmPassword"]').type('Test1234!');
    
    // KVKK kabul et
    cy.get('input[type="checkbox"]').check();
    
    // Kayıt ol
    cy.get('button').contains('Kayıt Ol').click();
    
    // Dialog'u bekle
    cy.contains('E-posta Doğrulaması Gerekli').should('be.visible');
    cy.contains('test@example.com').should('be.visible');
  });
});
```

---

## Sık Karşılaşılan Sorunlar ve Çözümleri

### Sorun 1: Email Gelmiyor
**Çözüm**:
- Spam klasörünü kontrol edin
- 5 dakika bekleyin
- Supabase Logs → Auth Logs'u kontrol edin
- Rate limiting olabilir, 1 dakika bekleyin

### Sorun 2: Link Çalışmıyor
**Çözüm**:
- Redirect URL'lerin Supabase'de kayıtlı olduğundan emin olun
- verify.html sayfasının yayında olduğunu kontrol edin
- Debug bilgilerini kontrol edin

### Sorun 3: Uygulama Açılmıyor
**Çözüm**:
- Deep link yapılandırmasını kontrol edin
- iOS: Universal Links
- Android: App Links
- Manuel "Uygulamayı Aç" butonunu kullanın

---

## Test Tamamlama Checklist

- [ ] Tüm 8 test senaryosu tamamlandı
- [ ] En az 3 farklı email sağlayıcı test edildi
- [ ] iOS ve Android'de test edildi
- [ ] Performance metrikleri kaydedildi
- [ ] Hata durumları test edildi
- [ ] Dokümantasyon güncellendi
- [ ] Takım bilgilendirildi

---

## Sonraki Adımlar

Test başarılı olduysa:
1. ✅ Production'a deploy edilebilir
2. ✅ Kullanıcılara duyurulabilir
3. ✅ Monitoring açılmalı

Test başarısız olduysa:
1. ❌ Hataları düzeltin
2. ❌ Testleri tekrarlayın
3. ❌ Production'a deploy etmeyin

---

**Son Güncelleme**: 2026-03-09
**Versiyon**: 1.0
**Hazırlayan**: CizreApp Dev Team
