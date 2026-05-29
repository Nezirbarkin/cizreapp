# Firebase APNs Authentication Key Kurulum Rehberi

## 🔴 SORUN: Firebase Console'da APNs Anahtarı Yok

Firebase Console'da iOS uygulamanız (com.cizreapp.com) için **APNs Authentication Key** veya **APNs Certificate** yüklü değil. Bu olmadan Firebase, iOS cihazlara push bildirim **GÖNDEREMEZ**.

> ⚠️ Android bildirimler çalışabilir çünkü Android FCM'i doğrudan kullanır. Ancak iOS bildirimler için APNs (Apple Push Notification service) aracılığıyla iletilmek ZORUNDADIR ve Firebase'in APNs ile iletişim kurması için bu anahtara ihtiyacı vardır.

---

## 📋 Adım Adım Kurulum

### ADIM 1: Apple Developer Console'da APNs Key Oluştur

1. **Apple Developer Console**'a giriş yapın:
   - https://developer.apple.com/account

2. Sol menüden **Certificates, Identifiers & Profiles** seçin

3. Sol taraftaki menüden **Keys** seçin

4. Sağ üstteki **+** (artı) butonuna tıklayın

5. Aşağıdaki bilgileri doldurun:
   - **Key Name**: `CizreApp FCM Key` (veya istediğiniz isim)
   - **Apple Push Notification service (APNs)** checkbox'ını ✅ işaretleyin

6. **Continue** → **Register** butonlarına tıklayın

7. ⚠️ **ÇOK ÖNEMLİ**: **Download** butonuna tıklayın:
   - `.p8` dosyası inecek (örn: `AuthKey_XXXXXXXXXX.p8`)
   - Bu dosya **SADECE BİR KEZ** indirilebilir!
   - Dosyayı güvenli bir yere kaydedin (kaybederseniz yeni anahtar oluşturmanız gerekir)

8. **Key ID**'yi not alın:
   - Sayfada görünen Key ID'yi kaydedin (örn: `ABC123DEF4`)
   - Ayrıca .p8 dosyasının adında da bu ID var: `AuthKey_XXXXXXXXXX.p8`

### ADIM 2: Team ID'yi Bulun

1. Apple Developer Console'da **Account** → **Membership** sayfasına gidin

2. **Team ID**'yi not alın (örn: `1234567890`)

### ADIM 3: Firebase Console'da APNs Key Yükle

1. **Firebase Console**'a giriş yapın:
   - https://console.firebase.google.com

2. **CizreApp** projesini seçin

3. Sol üstteki **dişli çark** → **Project settings** (Proje ayarları)

4. **Cloud Messaging** sekmesine tıklayın

5. **iOS app configuration** bölümünü bulun:
   - CizreApp İOS (com.cizreapp.com) altında

6. **APNs Authentication Key** bölümünde:
   - **Upload** butonuna tıklayın
   - İndirdiğiniz `.p8` dosyasını seçin
   - **Key ID** alanına Apple'dan aldığınız Key ID'yi girin (örn: `ABC123DEF4`)
   - **Team ID** alanına Apple Developer Team ID'yi girin (örn: `1234567890`)
   - **Save** / **Upload** butonuna tıklayın

7. ✅ "Configuration with auth keys is recommended" mesajının yanında yeşil onay işareti görünmeli

### ADIM 4: Doğrulama

Firebase Console'da artık şu mesajı görmelisiniz:

```
APNs Authentication Key
Key ID: ABC123DEF4
Team ID: 1234567890
✅ Valid
```

---

## 🧪 Test Etme

### Yöntem 1: Firebase Console Test Bildirimi

1. Firebase Console → **Messaging** → **New notification**
2. Bir başlık ve mesaj girin
3. **Send to test device** seçin
4. FCM token'ı girin (uygulamadan log'ları kontrol edin)
5. **Send** butonuna tıklayın

### Yöntem 2: Uygulama İçi Test

Uygulamayı fiziksel iOS cihazında çalıştırın ve log'ları kontrol edin:

```bash
flutter run -d <ios_cihaz_id>
```

**Beklenen log'lar:**
```
📱 APNs Device Token alındı: xxxxxx...
🔑 FCM Token BAŞARIYLA ALINDI: xxxxxx...
✅ FCM token Supabase'e kaydedildi
```

**Sorunlu log'lar:**
```
❌ APNs token alma hatası
❌ FCM TOKEN BOŞTUR
```

---

## ⚠️ ÖNEMLİ NOTLAR

### Development vs Production

| Ortam | aps-environment değeri | Açıklama |
|-------|----------------------|----------|
| **Debug/Test** | `development` | Xcode'dan çalıştırılan build'ler |
| **App Store** | `production` | App Store'dan indirilen build'ler |

Auth Key (.p8) hem development hem production için **aynı dosya** kullanılır. Tek bir yükleme yeterlidir.

### aps-environment Değeri

`ios/Runner/entitlements.plist` dosyasında şu an `development` olarak ayarlı. App Store'a gönderirken Xcode otomatik olarak `production` olarak değiştirir. Manuel build yapıyorsanız:

```xml
<!-- Development için -->
<key>aps-environment</key>
<string>development</string>

<!-- Production için -->
<key>aps-environment</key>
<string>production</string>
```

### Simulator Uyarısı

⚠️ **iOS Simulator push bildirim desteklemez!** Test için mutlaka fiziksel iOS cihaz kullanın.

---

## 🔧 Yapılan Kod Değişiklikleri

### 1. AppDelegate.swift (iOS native)
- `didRegisterForRemoteNotificationsWithDeviceToken` → APNs token FCM'e bildiriliyor
- `MessagingDelegate` extension → FCM token refresh handle ediliyor
- `UNUserNotificationCenterDelegate` → foreground bildirimler gösteriliyor
- `registerForRemoteNotifications()` → APNs kaydı yapılıyor

### 2. entitlements.plist
- `aps-environment` = `development` eklendi (push notification yetkisi)

### 3. Info.plist
- `UIBackgroundModes` > `remote-notification` eklendi (arka planda bildirim)

---

## 📱 Hızlı Kontrol Listesi

- [ ] Apple Developer Console'da APNs Key oluşturuldu
- [ ] .p8 dosyası indirildi ve kaydedildi
- [ ] Key ID not alındı
- [ ] Team ID not alındı
- [ ] Firebase Console'da APNs Key yüklendi
- [ ] Firebase Console'da yeşil onay işareti görünüyor
- [ ] Fiziksel iOS cihazda test edildi
- [ ] Log'larda "FCM Token BAŞARIYLA ALINDI" mesajı görünüyor
- [ ] Test bildirimi cihaza ulaştı