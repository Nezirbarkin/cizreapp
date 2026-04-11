# 📱 CizreApp - Store Yayın Rehberi

## 🎯 Genel Bilgiler

**Uygulama Adı:** CizreApp  
**Paket Adı (Package):** `com.example.cizreapp` ⚠️ *Değiştirilmeli!*  
**Mevcut Versiyon:** 1.1.0+2  
**Açıklama:** Cizre'nin Dijital Pazarı & Sosyal Medya Ağı  

---

## 🔧 1. Teknik Hazırlıklar

### ✅ Tamamlanması Gerekenler:

#### A. Package Name Değişikliği (ÖNEMLİ!)
`com.example.cizreapp` → **`com.cizreapp.app`** veya benzeri benzersiz bir isim

**Değiştirilecek Dosyalar:**
1. `android/app/build.gradle.kts` → `applicationId`
2. `android/app/src/main/AndroidManifest.xml` → `package`
3. Klasör yapısı: `android/app/src/main/kotlin/com/example/cizreapp/` → yeni package yapısı

#### B. Signing Configuration (Release İmzası)
**Keystore oluştur:**
```bash
keytool -genkey -v -keystore ~/cizreapp-release-key.jks -keyalg RSA -keysize 2048 -validity 10000 -alias cizreapp
```

**`android/key.properties` oluştur:**
```properties
storePassword=<parola>
keyPassword=<parola>
keyAlias=cizreapp
storeFile=<path-to-keystore>
```

**`android/app/build.gradle.kts` güncelle:**
```kotlin
signingConfigs {
    create("release") {
        storeFile = file(keystoreProperties["storeFile"] as String)
        storePassword = keystoreProperties["storePassword"] as String
        keyAlias = keystoreProperties["keyAlias"] as String
        keyPassword = keystoreProperties["keyPassword"] as String
    }
}

buildTypes {
    release {
        signingConfig = signingConfigs.getByName("release")
        isMinifyEnabled = true
        isShrinkResources = true
    }
}
```

#### C. App Icon (Uygulama İkonu)
Launcher icon'ları oluştur:
- 📱 Android: `android/app/src/main/res/mipmap-*/ic_launcher.png`
- 🍎 iOS: `ios/Runner/Assets.xcassets/AppIcon.appiconset/`

**İkon Boyutları (Android):**
- mdpi: 48x48px
- hdpi: 72x72px
- xhdpi: 96x96px
- xxhdpi: 144x144px
- xxxhdpi: 192x192px

**Oluşturma Aracı:** [appicon.co](https://appicon.co) veya `flutter_launcher_icons` paketi

#### D. Privacy Policy & Terms
- Gizlilik Politikası URL'i gerekli
- Kullanım Şartları URL'i gerekli
- Web sitesinde yayınla: `https://cizreapp.com/privacy-policy`

---

## 📲 2. Google Play Store Gereksinimleri

### A. Store Listing (Mağaza Bilgileri)

**App Name:** CizreApp  
**Short Description (80 karakter):**  
"Cizre'nin dijital pazarı ve sosyal ağı. Alışveriş yap, paylaş, keşfet!"

**Full Description (4000 karakter):**
```
🌟 CizreApp - Cizre'nin Dijital Kalbi

CizreApp ile Cizre'nin dijital dünyasında yerinizi alın! Hem alışveriş yapın, hem sosyal medyanın keyfini çıkarın.

📱 ÖZELLİKLER:

🛒 DİJİTAL PAZAR
• Yerel mağazalardan online sipariş
• Kapıda ödeme veya online kart ödeme
• Hızlı teslimat ve kurye takibi
• Günlük fırsatlar ve kampanyalar

👥 SOSYAL MEDYA
• Gönderi paylaş, beğen, yorum yap
• Hikaye ekle ve takip et
• Özel mesajlaşma
• Kullanıcı profilleri ve takip sistemi

💰 SATICI PANELİ
• Kendi mağazanı aç
• Ürün ekle ve yönet
• Sipariş takibi
• Komisyon ve ödeme yönetimi

🔒 GÜVENLİK & GİZLİLİK
• Hesap doğrulama sistemi
• Güvenli ödeme altyapısı
• Şikayet ve destek sistemi

📞 DESTEK
• 7/24 destek merkezi
• Canlı sohbet desteği

İndirin ve Cizre'nin dijital dünyasına katılın!
```

### B. Grafikler (Screenshots & Assets)

#### Gerekli Görseller:
1. **App Icon** (512x512px, PNG, şeffaf arka plan)
2. **Feature Graphic** (1024x500px, JPG/PNG)
3. **Screenshots** (min 2, max 8):
   - Telefon: 1080x1920px veya benzer
   - 7-inch tablet: 1920x1200px
   - 10-inch tablet: 1920x1280px

#### Screenshot Önerileri:
- Splash ekranı
- Ana sayfa (market)
- Ürün detay
- Sepet & ödeme
- Sosyal medya feed
- Profil sayfası
- Hikayeler
- Mesajlaşma

### C. Content Rating (İçerik Derecelendirmesi)
**Kategori:** Shopping & Social  
**Yaş:** 3+ veya 12+ (içeriğe göre)  
**Şiddet, Cinsellik, Alkol vb:** Hayır

### D. App Category
**Primary:** Shopping  
**Secondary:** Social

### E. Contact Details
- **Email:** support@cizreapp.com
- **Phone:** +90 XXX XXX XX XX (isteğe bağlı)
- **Website:** https://cizreapp.com
- **Privacy Policy:** https://cizreapp.com/privacy-policy

---

## 🍎 3. Apple App Store Gereksinimleri

### A. App Store Connect Bilgileri

**App Name:** CizreApp  
**Subtitle (30 karakter):** Alışveriş & Sosyal Medya  
**Description:**
```
(Aynı Google Play açıklaması kullanılabilir, max 4000 karakter)
```

**Keywords (100 karakter):**
```
cizre, alışveriş, market, sosyal medya, e-ticaret, online sipariş, kampanya
```

**Promotional Text (170 karakter):**
```
Cizre'nin ilk dijital pazarı! Online alışveriş yapın, arkadaşlarınızla paylaşın. Günlük fırsatları kaçırmayın! 🛒✨
```

### B. Grafikler

1. **App Icon** (1024x1024px, PNG, şeffaf OLMAYAN arka plan)
2. **Screenshots:**
   - iPhone 6.7": 1290x2796px (iPhone 14 Pro Max)
   - iPhone 6.5": 1242x2688px (iPhone 11 Pro Max)
   - iPad Pro 12.9": 2048x2732px

### C. Build Ayarları

**Xcode gerekli ayarlar:**
- Bundle ID: `com.cizreapp.app`
- Version: 1.1.0
- Build: 2
- Deployment Target: iOS 13.0+

**Info.plist eklemeleri:**
```xml
<key>NSCameraUsageDescription</key>
<string>Fotoğraf çekmek için kamera erişimi gerekli</string>

<key>NSPhotoLibraryUsageDescription</key>
<string>Fotoğraf yüklemek için galeri erişimi gerekli</string>

<key>NSLocationWhenInUseUsageDescription</key>
<string>Yakındaki mağazaları görmek için konum gerekli</string>
```

---

## 🚀 4. Build & Upload Adımları

### A. Android (Google Play)

#### 1. Release APK/AAB Oluştur:
```bash
# AAB (App Bundle - önerilen)
flutter build appbundle --release

# veya APK
flutter build apk --release --split-per-abi
```

**Output:**
- AAB: `build/app/outputs/bundle/release/app-release.aab`
- APK: `build/app/outputs/flutter-apk/app-release.apk`

#### 2. Google Play Console'a Yükle:
1. [play.google.com/console](https://play.google.com/console) → Yeni uygulama oluştur
2. Production → Yeni yayın oluştur
3. AAB dosyasını yükle
4. Store listing, Content rating vb. doldur
5. İncelemeye gönder

**İlk yayın:** ~3-7 gün sürer  
**Güncellemeler:** ~1-2 gün

### B. iOS (App Store)

#### 1. Archive Oluştur (Xcode gerekli):
```bash
flutter build ios --release
```

#### 2. Xcode'da:
- Xcode'u aç → `ios/Runner.xcworkspace`
- Product → Archive
- Distribute App → App Store Connect
- Upload

#### 3. App Store Connect:
1. [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
2. My Apps → + → New App
3. App bilgilerini doldur
4. TestFlight'ta test et
5. Submit for Review

**İlk yayın:** ~1-3 gün (bazen 24 saat)  
**Güncellemeler:** ~24-48 saat

---

## 📋 5. Checklist

### Android
- [ ] Package name değiştirildi (`com.example.cizreapp` → benzersiz)
- [ ] Keystore oluşturuldu ve `key.properties` ayarlandı
- [ ] Release signing yapılandırıldı
- [ ] App icon eklendi (tüm boyutlar)
- [ ] Privacy policy URL'i hazır
- [ ] Screenshot'lar hazırlandı
- [ ] Feature graphic hazırlandı
- [ ] Store listing bilgileri dolduruldu
- [ ] AAB build alındı
- [ ] Google Play Console hesabı açıldı ($25 tek seferlik)

### iOS
- [ ] Bundle ID değiştirildi
- [ ] Apple Developer hesabı açıldı ($99/yıl)
- [ ] Info.plist izinleri eklendi
- [ ] App icon eklendi (1024x1024px)
- [ ] Screenshot'lar hazırlandı (farklı boyutlar)
- [ ] Privacy policy URL'i hazır
- [ ] Archive oluşturuldu
- [ ] TestFlight'ta test edildi
- [ ] App Store Connect bilgileri dolduruldu

---

## ⚠️ Önemli Notlar

1. **Package Name/Bundle ID:** Değiştikten sonra tekrar değiştiremezsiniz!
2. **Keystore:** Kaybederseniz uygulamayı güncelleyemezsiniz - güvenli yedekleyin!
3. **Privacy Policy:** Yasal zorunluluk - mutlaka hazırlayın
4. **Test:** Her ikisinde de beta test yapın (TestFlight, Internal Testing)
5. **İçerik:** Store'ların içerik politikalarına uygun olmalı
6. **Ödeme:** Google Play $25 (tek), Apple $99 (yıllık)

---

## 📞 Yardım Kaynakları

- [Google Play Console Yardım](https://support.google.com/googleplay/android-developer)
- [App Store Connect Yardım](https://developer.apple.com/help/app-store-connect/)
- [Flutter Deployment Docs](https://docs.flutter.dev/deployment)
