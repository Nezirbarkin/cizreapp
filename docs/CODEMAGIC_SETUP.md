# Mac Olmadan iOS Build - Codemagic Kullanımı

## Codemagic Nedir?

Codemagic, Flutter uygulamaları için özel olarak tasarlanmış bulut tabanlı bir CI/CD platformudur. Mac satın almadan iOS build oluşturabilirsiniz.

**Ücretsiz Plan:** Aylık 500 dakika build süresi

---

## Kurulum Adımları

### 1. GitHub'a Proje Yükleme

Eğer projeniz GitHub'da yoksa:

```bash
# Proje klasörüne gidin
cd c:/Users/lenovo/cizreapp

# GitHub'da yeni repo oluşturun (github.com'dan)
# Ardından:

git init
git add .
git commit -m "CizreApp iOS build"
git branch -M main
git remote add origin https://github.com/KULLANICI_ADI/cizreapp.git
git push -u origin main
```

### 2. Codemagic'e Kayıt

1. https://codemagic.io adresine gidin
2. **Sign up with GitHub** seçin
3. GitHub hesabınızla giriş yapın
4. Repository'lerinize erişim izni verin

### 3. Uygulama Ekleme

1. Codemagic dashboard'da **Add application** seçin
2. **GitHub** seçin
3. **cizreapp** reposunu seçin
4. **Flutter app** seçin
5. **Finish** butonuna tıklayın

### 4. codemagic.yaml Oluşturma

Proje kök dizinine `codemagic.yaml` dosyası oluşturun:

```yaml
workflows:
  ios-workflow:
    name: iOS App Store
    max_build_duration: 120
    environment:
      flutter: stable
      xcode: latest
      cocoapods: default
    scripts:
      - name: Flutter dependencies
        script: |
          flutter pub get
      - name: Set up keychain
        script: |
          keychain initialize
      - name: Set up provisioning profiles
        script: |
          app-store-connect fetch-signing-files "com.cizreapp.app" --type IOS_APP_STORE
      - name: Build iOS
        script: |
          flutter build ipa --release --export-options-plist=/Users/builder/export_options.plist
    artifacts:
      - build/ios/ipa/*.ipa
    publishing:
      app_store_connect:
        api_key: $APP_STORE_CONNECT_API_KEY
        key_id: $APP_STORE_CONNECT_KEY_ID
        issuer_id: $APP_STORE_CONNECT_ISSUER_ID
```

### 5. App Store Connect API Key Oluşturma

Codemagic'in App Store'a yüklemesi için:

1. https://appstoreconnect.apple.com adresine gidin
2. **Users and Access** → **Keys** sekmesine gidin
3. **+** ile yeni API Key oluşturun
4. **App Manager** rolü seçin
5. **Key ID** ve **Issuer ID**'yi kaydedin
6. `.p8` dosyasını indirin

### 6. Codemagic Environment Variables

Codemagic'de ayarlayın:

1. **App Settings** → **Environment variables**
2. Şu değişkenleri ekleyin:

| Variable | Value |
|----------|-------|
| APP_STORE_CONNECT_API_KEY | İndirilen .p8 dosyasının içeriği |
| APP_STORE_CONNECT_KEY_ID | Key ID (örn: XXXXXXXX) |
| APP_STORE_CONNECT_ISSUER_ID | Issuer ID (örn: xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx) |

### 7. Signing Certificate Oluşturma

Codemagic'de otomatik:

1. **App Settings** → **iOS code signing**
2. **Distribution certificate** seçin
3. **Automatically** seçin
4. **Save** butonuna tıklayın

---

## App Store Connect'de API Key Oluşturma (Detaylı)

1. App Store Connect'e giriş yapın
2. Sağ üst köşedeki avatar → **Users and Access**
3. **Keys** sekmesine tıklayın
4. **App Store Connect API** altında **+** butonu
5. Ayarlar:
   - **Key Type**: App Manager
   - **Title**: Codemagic
6. **Generate** tıklayın
7. **Download** ile .p8 dosyasını indirin
8. **Key ID** ve **Issuer ID**'yi kopyalayın

⚠️ Not: Bu dosyayı sadece bir kez indirebilirsiniz!

---

## Kod Değişiklikleri

### export_options.plist

`ios/export_options.plist` dosyası oluşturun:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>strip_swift_symbols</key>
    <true/>
</dict>
</plist>
```

---

## Build Tetikleme

1. Codemagic dashboard'da uygulamanızı seçin
2. **Start new build** butonuna tıklayın
3. **Branch**: main seçin
4. **Workflow**: ios-workflow seçin
5. **Start build** tıklayın

Build tamamlandığında:
- `.ipa` dosyası otomatik olarak App Store Connect'e yüklenecek
- Veya **Artifacts** sekmesinden `.ipa` dosyasını indirebilirsiniz

---

## Troubleshooting

### "No profiles for 'com.cizreapp.app' were found"
**Çözüm:** Apple Developer Portal'da Bundle ID'yi kaydettiğinizden emin olun.

### "Export compliance" hatası
**Çözüm:** `Info.plist`'e ekleyin:
```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

### CocoaPods hatası
**Çözüm:** `codemagic.yaml`'a ekleyin:
```yaml
scripts:
  - name: Pod install
    script: |
      cd ios && pod install && cd ..
```

---

## Alternatif: MacinCloud

Eğer Codemagic işinize yaramazsa:

1. https://macincloud.com adresine gidin
2. Mac kiralayın (saatlik ~$1 veya aylık ~$30)
3. Uzak masaüstü ile bağlanın
4. Xcode ve Flutter kurun
5. Build yapın

---

## Özet

| Yöntem | Maliyet | Zorluk |
|--------|---------|--------|
| Codemagic | Ücretsiz (500dk/ay) | Kolay |
| Bitrise | Ücretsiz plan var | Orta |
| MacinCloud | ~$30/ay | Kolay |

**Başlangıç için Codemagic önerilir** - GitHub'a kod yüklemek ve 15 dakikada kurulum yapmak yeterli.
