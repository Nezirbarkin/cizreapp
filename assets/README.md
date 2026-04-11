# CizreApp Assets Klasörü

Bu klasör uygulama varlıklarını (assets) içerir.

## 📁 Klasör Yapısı

```
assets/
├── images/          # Genel görseller
├── icons/           # Uygulama ikonları
└── logos/           # Logo dosyaları
```

## 🎨 Logo Dosyaları Eklenecek

Aşağıdaki logo dosyalarını `logos/` klasörüne eklemeniz gerekiyor:

### Gerekli Logo Boyutları:

1. **App Logo (Ana Logo)**
   - `app_logo.png` - 512x512 px (Yüksek çözünürlük)
   - `app_logo_white.png` - 512x512 px (Beyaz arkaplan için koyu logo)
   - `app_logo_dark.png` - 512x512 px (Koyu arkaplan için beyaz logo)

2. **Splash Screen Logo**
   - `splash_logo.png` - 1024x1024 px (Splash ekranı için)

3. **Launcher Icons** (Uygulama ikonu)
   - Android: `android/app/src/main/res/` klasörlerinde
   - iOS: `ios/Runner/Assets.xcassets/AppIcon.appiconset/` klasöründe

## 📝 Kullanım Örnekleri

### Kodda Logo Kullanımı:

```dart
// Ana logo
Image.asset('assets/logos/app_logo.png', height: 100)

// Beyaz versiyonu
Image.asset('assets/logos/app_logo_white.png', height: 100)

// Koyu versiyonu  
Image.asset('assets/logos/app_logo_dark.png', height: 100)
```

## 🎯 Logo Tasarım Önerileri

- **Format**: PNG (şeffaf arkaplan) veya SVG
- **Minimum boyut**: 512x512 px
- **Renk paleti**: Yeşil tonları (AppTheme.primaryGreen ile uyumlu)
- **Stil**: Modern, minimalist
- **İçerik**: "CizreApp" veya "Cizre" yazısı + ikon

## 📱 Platform Spesifik İkonlar

### Android Launcher Icon
Boyutlar:
- xxxhdpi: 192×192 px
- xxhdpi: 144×144 px
- xhdpi: 96×96 px
- hdpi: 72×72 px
- mdpi: 48×48 px

### iOS App Icon
Boyutlar:
- 1024×1024 px (App Store)
- 180×180 px (iPhone)
- 167×167 px (iPad Pro)
- 152×152 px (iPad)
- 120×120 px (iPhone)
- 87×87 px (iPhone)
- 80×80 px (iPad)
- 76×76 px (iPad)
- 60×60 px (iPhone)
- 58×58 px (iPad)
- 40×40 px (iPhone/iPad)
- 29×29 px (iPhone/iPad)
- 20×20 px (iPhone/iPad)

## 🔧 Logo Oluşturma Araçları

Önerilen online araçlar:
- **Canva**: https://www.canva.com (Basit logo tasarımı)
- **Logo Maker**: https://www.logomaker.com
- **App Icon Generator**: https://appicon.co (Platform spesifik ikonlar)
- **Flutter Launcher Icons**: `flutter pub run flutter_launcher_icons` (Otomatik ikon oluşturma)

## ⚠️ Önemli Notlar

1. Tüm logo dosyaları **şeffaf arkaplan** (transparent) olmalı
2. Logo dosyaları **optimize edilmeli** (TinyPNG gibi araçlarla)
3. Dosya isimleri **küçük harf** ve **alt çizgi** ile yazılmalı
4. Git'e commit etmeden önce dosya boyutlarını kontrol edin

## 📚 Ek Kaynaklar

- [Flutter Assets Guide](https://docs.flutter.dev/development/ui/assets-and-images)
- [Material Design Icons](https://material.io/design/iconography)
- [Flutter Launcher Icons Package](https://pub.dev/packages/flutter_launcher_icons)
