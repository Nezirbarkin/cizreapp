# Mac Olmadan iOS App Store Build Rehberi - CizreApp

Bu rehber, Windows/Linux bilgisayardan iOS uygulamasını App Store'a yüklemek için **Codemagic** kullanımını anlatır.

---

## Ön Koşullar

- [x] Apple Developer Hesabı (yıllık $99) ✓
- [x] App Store Connect hesabı ✓
- [ ] GitHub hesabı (ücretsiz)
- [ ] App Store Connect API Key
- [ ] Codemagic hesabı (ücretsiz başlangıç)

---

## Adım 1: GitHub'a Kod Yükleme

### 1.1 Repo Bilgileri

GitHub reposu: **https://github.com/Nezirbarkin/cizreapp**

### 1.2 Kodu GitHub'a Yükleme (Zaten Repo Var!)

Repo'nuz zaten oluşturulmuş: **https://github.com/Nezirbarkin/cizreapp**

Şimdi mevcut kodu yükleyin:

1. **Git** indirin: https://git-scm.com/download/win (yüklü değilse)

2. Terminal açın ve proje klasörüne gidin:
```bash
cd c:\Users\lenovo\cizreapp
```

3. Git başlatın (zaten init yapılmışsa atlayın):
```bash
git init
```

4. Remote URL'ini güncelleyin:
```bash
git remote set-url origin https://github.com/Nezirbarkin/cizreapp.git
```

5. Tüm dosyaları ekleyin:
```bash
git add .
```

6. İlk commit yapın:
```bash
git commit -m "CizreApp iOS build"
```

7. Kodu yükleyin:
```bash
git branch -M main
git push -u origin main
```

> ⚠️ **Önemli**: GitHub'a ilk kez kod yüklerken kimlik doğrulama istenebilir. GitHub'da **Personal Access Token** oluşturun:
> 1. GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
> 2. **Generate new token** → **repo** yetkisi seçin
> 3. Token'ı kopyalayın ve şifre yerine kullanın

---

## Adım 2: App Store Connect API Key Oluşturma

### 2.1 App Store Connect'te API Key

1. https://appstoreconnect.apple.com adresine gidin
2. **Users and Access** seçin
3. **Keys** sekmesine tıklayın
4. **+** ile yeni key oluşturun:
   - **Key Name**: `Codemagic`
   - **Access**: **App Store Connect** seçin
   - **Permissions**: **App Manager** seçin
5. **Generate** tıklayın
6. **Download** ile `.p8` dosyasını indirin (ÖNEMLİ: Bir kez indirilebilir!)
7. **Issuer ID** ve **Key ID**'yi not alın

### 2.2 App Store Connect'te Uygulama Oluşturma

1. https://appstoreconnect.apple.com → **Apps** → **+**
2. Ayarlar:
   - **Platform**: iOS
   - **Name**: CizreApp
   - **Primary Language**: Turkish
   - **Bundle ID**: `com.cizreapp.app`
   - **SKU**: `cizreapp-001`
3. **Create** tıklayın

---

## Adım 3: Codemagic'e Bağlama

### 3.1 Codemagic Kayıt

1. https://codemagic.io adresine gidin
2. **Sign up with GitHub** seçin
3. GitHub reposuna erişim izni verin

### 3.2 Uygulama Ekleme

1. Codemagic'de **Add application** seçin
2. **GitHub** seçin
3. Reponuzu bulun: `cizreapp`
4. **Flutter** seçin
5. **Branch**: `main`

### 3.3 Environment Variables Ekleme

Codemagic'de **Environment variables** bölümünde şunları ekleyin:

| Variable | Değer |
|----------|-------|
| `APP_STORE_CONNECT_KEY_ID` | Key oluştururken aldığınız Key ID |
| `APP_STORE_CONNECT_ISSUER_ID` | App Store Connect Issuer ID |

### 3.4 App Store Connect Key Yükleme

1. Codemagic → **User settings** → **GitHub Apps**
2. **App Store Connect API key** bölümünde:
   - **API Key** dosyasını (.p8) yükleyin
   - **Issuer ID** ve **Key ID** girin

---

## Adım 4: Workflow Ayarları

`codemagic.yaml` dosyası zaten projede mevcut. Şu ayarları kontrol edin:

```yaml
workflows:
  ios-app-store:
    name: iOS App Store
    max_build_duration: 120
    environment:
      flutter: stable
      xcode: latest
      vars:
        BUNDLE_ID: com.cizreapp.app
        TEAM_ID: 7RY64FSMUS  # ← Apple Developer Team ID'niz
      ios_signing:
        distribution_type: app_store
        bundle_identifier: com.cizreapp.app
```

### 4.1 Team ID Bulma

1. https://developer.apple.com → Account → Membership
2. **Team ID**'yi kopyalayın

---

## Adım 5: Build Başlatma

### 5.1 Manuel Build

1. Codemagic'de uygulamanızı seçin
2. **Start new build** tıklayın
3. **Branch**: `main` seçin
4. **Workflow**: `ios-app-store` seçin
5. **Start build** tıklayın

### 5.2 Otomatik Build (Git Push)

`codemagic.yaml` dosyasında otomatik build açık:
```yaml
triggering:
  events:
    - push
  branch_patterns:
    - pattern: main
      include: true
```

Her `git push` yaptığınızda otomatik build başlar.

---

## Adım 6: Build Sonrası

### 6.1 IPA Dosyasını İndirme

1. Build başarılı olunca **Artifacts** sekmesine gidin
2. `build/ios/ipa/*.ipa` dosyasını indirin

### 6.2 Transporter ile Yükleme (Mac Gerekmez!)

Apple'ın **Transporter** uygulaması artık Windows'da da çalışıyor:

1. https://apps.apple.com/app/transporter/id1450874784?mt=12 adresinden indirin
2. `.ipa` dosyasını sürükle-bırak ile ekleyin
3. **Deliver** tıklayın

### 6.3 App Store Connect'te Yayınlama

1. https://appstoreconnect.apple.com → **My Apps** → **CizreApp**
2. **App Store** sekmesinde:
   - Screenshots yükleyin
   - Description yazın
   - Keywords ekleyin
   - **Submit for Review** tıklayın

---

## Önemli Notlar

### Bundle ID Uyumluluğu

`codemagic.yaml` ve Apple Developer Portal'daki Bundle ID aynı olmalı:
- Projede: `com.cizreapp.app`
- Apple'da kayıtlı: `com.cizreapp.app`

### Team ID

`codemagic.yaml` dosyasındaki `TEAM_ID: 7RY64FSMUS` sizin Team ID'niz olmalı. Apple Developer hesabınızdaki Team ID'yi kontrol edin.

### Versiyon Numarası

`pubspec.yaml`:
```yaml
version: 1.1.5+8
```

Her build'te `build_number` (+8, +9, vs.) artmalı.

---

## Sık Karşılaşılan Sorunlar

### "No profiles for 'com.cizreapp.app' were found"

**Çözüm**: Apple Developer Portal'da Bundle ID kayıtlı değil.
1. https://developer.apple.com → Certificates, Identifiers & Profiles
2. **Identifiers** → **+** → App ID kaydedin

### "API Key authentication failed"

**Çözüm**: 
1. API Key dosyasını doğru yüklediğinizden emin olun
2. Key ID ve Issuer ID'nin doğru olduğunu kontrol edin

### Build Başarısız

Codemagic loglarını kontrol edin:
1. Build sayfasında **Build logs** sekmesine gidin
2. Hata mesajını okuyun
3. Genellikle dependency hatası veya configuration hatasıdır

---

## Destek

- Codemagic Docs: https://docs.codemagic.io
- Apple Developer: https://developer.apple.com
