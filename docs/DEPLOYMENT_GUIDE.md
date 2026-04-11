# CizreApp - Google Play & App Store Deployment Rehberi

## Mevcut Versiyon: 1.1.4+6

---

## 1. Android - Google Play Store

### 1.1 Build Dosyası Oluşturma

AAB (Android App Bundle) dosyası Google Play için zorunludur:

```bash
# Temiz build
flutter clean
flutter pub get

# Release AAB build (Google Play Store için)
flutter build appbundle --release

# VEYA APK build (test/doğrudan dağıtım için)
flutter build apk --release

# Bölünmüş APK (daha küçük boyut)
flutter build apk --split-per-abi --release
```

**Build çıktı dosyaları:**
- AAB: `build/app/outputs/bundle/release/app-release.aab`
- APK: `build/app/outputs/flutter-apk/app-release.apk`

### 1.2 Keystore Bilgileri

Keystore dosyası: `android/cizreapp-release.jks`
Konfigürasyon: `android/key.properties`

```properties
storeFile=../cizreapp-release.jks
storePassword=<şifre>
keyAlias=cizreapp
keyPassword=<şifre>
```

**ÖNEMLİ:** Keystore dosyasını ve şifrelerini güvenli bir yerde yedekleyin! Kaybedilirse uygulama güncellenemez!

### 1.3 Google Play Console'a Yükleme

1. **Google Play Console**'a giriş: https://play.google.com/console
2. Uygulamanızı seçin (veya yeni uygulama oluşturun)
3. Sol menüden **Yayınlama → Üretim** (Production)
4. **Yeni sürüm oluştur** butonuna tıklayın
5. AAB dosyasını sürükleyip bırakın: `build/app/outputs/bundle/release/app-release.aab`
6. **Sürüm notları** girin:
   - Türkçe: Yeni özellikler ve düzeltmeler
   - İngilizce: New features and bug fixes
7. **İncele ve Yayınla** butonuna tıklayın

### 1.4 Google Play Mağaza Bilgileri

- **Uygulama Adı:** CizreApp
- **Paket Adı:** com.cizreapp.app
- **Kategori:** Sosyal / Alışveriş
- **İçerik Derecesi:** Herkese uygun (PEGI 3+)
- **Gizlilik Politikası:** https://cizreapp.com/privacy

### 1.5 Versiyon Yükseltme

`pubspec.yaml` dosyasında versiyonu güncelleyin:

```yaml
version: 1.1.5+7  # minor.bugfix+buildNumber
```

- `1.1.5` = Kullanıcıya görünen versiyon (versionName)
- `7` = Build numarası (versionCode) - her yüklemede mutlaka artırılmalı!

---

## 2. iOS - Apple App Store

### 2.1 Ön Gereksinimler

- **Mac bilgisayar** gereklidir (Xcode sadece macOS'ta çalışır)
- **Apple Developer hesabı** ($99/yıl): https://developer.apple.com
- **Xcode** (en güncel versiyon): Mac App Store'dan indirin
- **CocoaPods**: `sudo gem install cocoapods`

### 2.2 iOS Build Hazırlığı

```bash
# CocoaPods bağımlılıklarını yükle
cd ios && pod install && cd ..

# App Store için IPA build
flutter build ipa --release
```

**Build çıktı:** `build/ios/ipa/cizreapp.ipa`

### 2.3 Xcode'da Yapılandırma

1. Xcode'da `ios/Runner.xcworkspace` dosyasını açın
2. **Signing & Capabilities** sekmesinde:
   - Team: Apple Developer hesabınızı seçin
   - Bundle Identifier: `com.cizreapp.app`
3. **General** sekmesinde:
   - Version: `1.1.4`
   - Build: `6`

### 2.4 App Store Connect'e Yükleme

1. **App Store Connect**'e giriş: https://appstoreconnect.apple.com
2. **My Apps → + → New App** oluşturun
3. Platform: iOS
4. Bundle ID: `com.cizreapp.app`

**IPA Yükleme Seçenekleri:**

**Seçenek A - Transporter ile (Önerilen):**
1. Mac'te **Transporter** uygulamasını açın
2. `cizreapp.ipa` dosyasını sürükleyip bırakın
3. **Deliver** butonuna tıklayın

**Seçenek B - Xcode ile:**
```bash
xcrun altool --upload-app --type ios --file build/ios/ipa/cizreapp.ipa \
  --apiKey YOUR_API_KEY --apiIssuer YOUR_ISSUER_ID
```

**Seçenek C - Komut Satırı:**
```bash
flutter build ipa --release --export-options-plist=ios/ExportOptions.plist
```

### 2.5 App Store İnceleme Bilgileri

- **Ekran Görüntüleri:** 6.5" ve 5.5" iPhone ekran görüntüleri gerekli
- **Açıklama:** Uygulamanızın Türkçe ve İngilizce açıklaması
- **Anahtar Kelimeler:** cizre, pazar, sosyal, alışveriş, market
- **Destek URL'si:** https://cizreapp.com/support
- **Gizlilik Politikası:** https://cizreapp.com/privacy

---

## 3. Versiyon Güncelleme Adımları

Yeni bir versiyon yayınlayacağınızda:

### Adım 1: Versiyon numarasını güncelle
```yaml
# pubspec.yaml
version: 1.2.0+7  # versionCode her zaman artırılmalı!
```

### Adım 2: Changelog hazırla
- Yeni özellikler
- Düzeltmeler
- Bilinen sorunlar

### Adım 3: Build ve Test
```bash
flutter clean
flutter pub get
flutter test                    # Birim testleri çalıştır
flutter build appbundle --release   # Android
flutter build ipa --release         # iOS (Mac gerekli)
```

### Adım 4: Mağazalara Yükle
- Google Play Console → Yeni sürüm
- App Store Connect → Yeni versiyon

---

## 4. Hassas Dosyalar (.gitignore)

Bu dosyalar **ASLA** Git'e commit edilmemelidir:

```
android/key.properties
android/cizreapp-release.jks
android/local.properties
.env
.env.production
google-services.json          # Firebase (opsiyonel - private repo)
GoogleService-Info.plist      # Firebase iOS (opsiyonel)
```

---

## 5. Hızlı Referans

| İşlem | Komut |
|-------|-------|
| Android AAB Build | `flutter build appbundle --release` |
| Android APK Build | `flutter build apk --release` |
| iOS IPA Build | `flutter build ipa --release` |
| Flutter Temizle | `flutter clean` |
| Bağımlılıkları Güncelle | `flutter pub get` |
| Test Çalıştır | `flutter test` |
| Analiz | `flutter analyze` |


## 6. Sorun Giderme

### Build Hatası: "Keystore file not found"
- `android/key.properties` dosyasının var olduğunu kontrol edin
- `storeFile` yolunun doğru olduğunu doğrulayın

### Gradle Hatası: "OutOfMemoryError"
- `android/gradle.properties` dosyasında belleği artırın:
```
org.gradle.jvmargs=-Xmx8G
```

### iOS Signing Hatası
- Apple Developer hesabınızın aktif olduğunu kontrol edin
- Xcode'da doğru Team seçildiğini doğrulayın
- Certificate ve Provisioning Profile'ın geçerli olduğunu kontrol edin

### Google Play Reddi
- İçerik derecelendirmesini doldurun
- Gizlilik politikası URL'si ekleyin
- Uygulama içi satın alma açıklamalarını kontrol edin
