# App Store Gönderim Rehberi

## 1. App Store Connect'te Uygulama Bilgileri

1. [App Store Connect](https://appstoreconnect.apple.com)'e giriş yapın
2. **My Apps** → **CizreApp**'i tıklayın
3. Aşağıdaki bilgileri doldurun:

### App Information
- **Name**: CizreApp
- **Primary Language**: Turkish
- **Bundle ID**: com.cizreapp.app
- **SKU**: cizreapp

## 2. Ekran Görüntüleri

Sol menüden **Screenshots** bölümüne gidin.

### Gerekli Boyutlar:
| Cihaz | Çözünürlük | Minimum |
|-------|------------|---------|
| 6.7" (iPhone 15 Pro Max) | 1290 x 2796 px | 3 adet |
| 6.5" (iPhone 11 Pro Max) | 1284 x 2778 px | 3 adet |

### Ekran Görüntüsü Önerileri:
1. Ana sayfa / Feed ekranı
2. Mağaza / Ürün listesi
3. Ürün detay ekranı
4. Profil sayfası
5. Sipariş/Alışveriş sepeti

## 3. Metadata

### Description (Türkçe - Maks 4000 karakter)
CizreApp - Cizre'nin Dijital Pazarı & Sosyal Medya Ağı

Cizre'nin yerel işletmelerini keşfedin, ürünleri satın alın ve toplulukla bağlantı kurun.

Özellikler:
- Yerel mağazaları ve işletmeleri keşfedin
- Ürünleri online sipariş edin
- Sosyal medya özellikleri ile toplulukla etkileşim
- Kampanya ve fırsatları takip edin
- Profil yönetimi ve mesajlaşma

### Keywords (Maks 100 karakter)
cizre,pazar,alışveriş,sosyal,mağaza,ürün,sipariş

### Support URL
https://cizreapp.com/support (veya mevcut URL'niz)

### Privacy Policy URL (Zorunlu)
https://cizreapp.com/privacy (veya mevcut URL'niz)

## 4. Build Seçimi

1. Sol menüden **Build** bölümüne gidin
2. TestFlight'tan yüklenen build'i seçin
3. **What to Test** notu ekleyin: "Temel uygulama işlevleri test edildi"
4. Build'i onaylayın

## 5. Fiyatlandırma

- **Price**: Free (Ücretsiz)
- **Availability**: Tüm ülkeler veya sadece Türkiye

## 6. Review İçin Gönder

1. Tüm alanları doldurduktan sonra **Save** yapın
2. Sağ üstte **Submit for Review** butonuna tıklayın
3. Apple'ın inceleme süreci 1-3 gün sürebilir

## 7. Apple İnceleme Notları

Eğer uygulama hesap gerektiriyorsa, Apple'a test hesabı bilgilerini sağlayın:
- **Test Hesabı E-posta**: test@cizreapp.com
- **Test Hesabı Şifre**: [Test hesabı şifresi]

## Gizlilik Politikası

App Store'da yayınlayan her uygulamanın bir gizlilik politikası URL'si olmalıdır.
Bu projede `docs/PRIVACY_POLICY_APPSTORE.html` dosyası mevcuttur.
Bu dosyayı bir web sunucusuna yükleyerek URL olarak kullanabilirsiniz.

## Sorun Giderme

### Build Görünmüyorsa
- Codemagic build'inin App Store Connect'e başarıyla yüklendiğini kontrol edin
- TestFlight sekmesinde build'in işlendiğini bekleyin (5-30 dakika)

### Reddedilirse
- Apple'ın reddetme nedenini dikkatlice okuyun
- Gerekli değişiklikleri yapın
- Yeni bir build gönderin