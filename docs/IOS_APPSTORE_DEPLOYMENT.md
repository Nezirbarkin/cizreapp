# iOS App Store'a Yükleme Rehberi - CizreApp

## Ön Koşullar

- Apple Developer Hesabı (Apple Developer Program) satın alınmış ✓
- Mac bilgisayar veya MacOS sanal makine
- Xcode kurulu (App Store'dan)
- Flutter SDK kurulu
- Apple Developer hesabınızda `com.cizreapp.app` bundle ID kayıtlı

---

## Adım 1: Apple Developer Portalında Bundle ID Kaydetme

1. **Apple Developer Console**'a giriş yapın:
   - https://developer.apple.com → Account → Sign In

2. **Certificates, Identifiers & Profiles** bölümüne gidin

3. **Identifiers** sekmesinde **+** butonuna tıklayın

4. **App IDs** seçin, ardından **App** seçin

5. Aşağıdaki bilgileri doldurun:
   - **Description**: CizreApp
   - **Bundle ID**: `com.cizreapp.app` (Explicit)
   - **Capabilities**: 
     - Push Notifications
     - Associated Domains (App Links)
     - Sign in with Apple

6. **Register** butonuna tıklayın

---

## Adım 2: App Store Connect'de Uygulama Oluşturma

1. **App Store Connect**'e gidin:
   - https://appstoreconnect.apple.com

2. **My Apps** → **+** → **New App** seçin

3. Aşağıdaki bilgileri doldurun:
   - **Platforms**: iOS
   - **Name**: CizreApp
   - **Primary Language**: Turkish
   - **Bundle ID**: com.cizreapp.app
   - **SKU**: cizreapp-001

4. Uygulama oluşturulduktan sonra:
   - **Pricing and Availability**: Ücretsiz/Ücretli seçin
   - **App Information**: Kategoriler, yaş sınıfı seçin
   - **Privacy Policy**: Gizlilik politikası URL'si ekleyin
   - **App Privacy**: Veri toplama bilgilerini doldurun

---

## Adım 3: iOS Signing ve Provisioning Ayarları

### Xcode'da Apple Hesabı Ekleme

1. Xcode'u açın
2. **Xcode** → **Settings** → **Accounts** sekmesi
3. **+** butonuna tıklayın
4. **Apple ID** seçin ve geliştirici hesabınızla giriş yapın

### Runner.xcworkspace Açma

1. Terminalde proje klasörüne gidin:
   ```bash
   cd c:/Users/lenovo/cizreapp
   ```

2. iOS klasörüne gidin:
   ```bash
   cd ios
   ```

3. Xcode ile proje dosyasını açın:
   ```bash
   open Runner.xcworkspace
   ```

### Signing Ayarları

1. Xcode'da **Runner** projesini seçin (sol panel)
2. **TARGETS** altında **Runner** seçin
3. **Signing & Capabilities** sekmesine gidin
4. Ayarları yapın:
   - ✓ **Automatically manage signing** işaretli olsun
   - **Team**: Geliştirici hesabınızı seçin
   - **Bundle Identifier**: `com.cizreapp.app`
   - **Status**: "Signing Complete" görmelisiniz

---

## Adım 4: App Store'a Build Etme

### Flutter ile iOS Build

1. Terminalde proje klasörüne gidin:
   ```bash
   cd c:/Users/lenovo/cizreapp
   ```

2. iOS simulator için build (test için):
   ```bash
   flutter build ios --simulator --no-codesign
   ```

3. App Store Distribution için build:
   ```bash
   flutter build ios --release
   ```
   
   Bu komut `build/ios/iphones/Runner.ipa` dosyası oluşturur.

### Alternatif: Xcode ile Archive

1. Xcode'da **Product** → **Archive** seçin
2. Organizer penceresi açılacak
3. Uygulamanızı seçin
4. **Distribute App** → **App Store Connect** → **Upload**

---

## Adım 5: App Store Connect'e Yükleme

### Transporter Uygulaması ile (Önerilen)

1. **Transporter** uygulamasını Mac App Store'dan indirin
2. Transporter'ı açın
3. `.ipa` dosyasını sürükle-bırak ile ekleyin
4. **Deliver** butonuna tıklayın

### Manual Upload (xcrun ile)

```bash
# IPA dosyasını App Store Connect'e yükleyin
xcrun altool --upload-app -type iosapp -file build/ios/iphones/Runner.ipa -username "your@email.com" -password "app-specific-password"
```

---

## Adım 6: App Store Review Süreci

### Yükleme Sonrası

1. App Store Connect'e gidin
2. **My Apps** → CizreApp'i seçin
3. **App Store** sekmesinde uygulama bilgilerini tamamlayın:
   - **App Preview Videos**: Ekran kaydı (15-30 sn)
   - **Screenshots**: iPhone modellerine göre screenshotlar
   - **Promotional Text**: Uygulama açıklaması
   - **Description**: Detaylı açıklama
   - **Keywords**: Arama anahtar kelimeleri
   - **Support URL**: Web sitesi URL'si

### Screenshot Boyutları

| Cihaz | Boyut |
|-------|-------|
| iPhone 6.5" (Max) | 1284 x 2778 px |
| iPhone 6.7" (Pro Max) | 1290 x 2796 px |
| iPhone 5.5" (Plus) | 1242 x 2208 px |
| iPad Pro 12.9" | 2048 x 2732 px |

### Review Gönderme

1. Tüm bilgileri doldurun
2. **Add for Review** butonuna tıklayın
3. Export Compliance sorularını yanıtlayın
4. **Submit to App Review** ile gönderin

---

## Önemli Notlar

### Export Compliance (İhracat Uyumluluğu)

- Eğer HTTPS üzerinden çalışıyorsanız: **No** seçin
- Eğer ATS devre dışı ise veya HTTP kullanıyorsanız: **Yes** seçin

### Privacy Policy URL

App Store'da zorunlu. Eğer yoksa:
- `docs/PRIVACY_POLICY.html` dosyasını web sunucunuza yükleyin
- URL'yi App Store Connect'e ekleyin

### Info.plist İzinleri

Uygulamanızdaki tüm izinler (kamera, konum, galeri) Info.plist'de tanımlı:
- Kamera: Fotoğraf/video çekme
- Galeri: Medya seçme
- Mikrofon: Ses kaydı
- Konum: Yakındaki mağazalar

---

## Sık Karşılaşılan Sorunlar

### "No profiles for 'com.cizreapp.app' were found"

**Çözüm**: Apple Developer Portal'da Bundle ID'yi kaydettiğinizden emin olun.

### "Your account has been denied access to App Store Connect"

**Çözüm**: Apple Developer Program üyeliğinizin aktif olduğunu kontrol edin.

### Code Signing Hataları

**Çözüm**: 
1. Xcode → Settings → Locations → Command Line Tools ayarlayın
2. `flutter clean` çalıştırın
3. Tekrar deneyin

### Build Failed - Swift Version

**Çözüm**: iOS Deployment Target'i kontrol edin (minimum iOS 12.0 önerilir)

---

## Sonraki Adımlar

1. ✅ Apple Developer Portal → Bundle ID kaydetme
2. ✅ App Store Connect → Uygulama oluşturma
3. ⬜ Xcode → Signing ayarları
4. ⬜ Flutter build → IPA oluşturma
5. ⬜ Transporter → App Store Connect'e yükleme
6. ⬜ App Store bilgileri → Screenshots ve açıklama
7. ⬜ Review gönderimi

---

## Destek

Apple Developer Desteği: https://developer.apple.com/contact/
