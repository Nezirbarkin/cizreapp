# iOS Push Bildirim Sorunları ve Çözümleri

## Tespit Edilen Sorunlar

### 1. AppDelegate.swift Güncellendi
- Firebase background handler iOS'ta kayıt edildi
- APNs token FCM'e bildirildi
- UNUserNotificationCenter delegate'si set edildi

### 2. Potansiyel Sorunlar ve Çözümler

#### A) Firebase Console APNs Yapılandırması

Firebase Console'da aşağıdaki ayarların yapıldığından emin olun:

1. **Project Settings > Cloud Messaging** sekmesine gidin
2. **iOS app configuration** bölümünde:
   - **APNs Authentication Key** VEYA
   - **APNs Certificates** (Development ve Production) yüklenmiş olmalı
   
**APNs Authentication Key nasıl alınır:**
1. Apple Developer Console'a gidin: https://developer.apple.com
2. **Certificates, Identifiers & Profiles** bölümüne gidin
3. **Keys** > **+** ile yeni key oluşturun
4. **Apple Push Notification service (APNs)** seçin
5. Key'i indirin (`.p8` dosyası)
6. Firebase Console'a yükleyin:
   - Key ID'yi girin
   - Team ID'yi girin (Apple Developer hesabı)
   - `.p8` dosyasını yükleyin

#### B) iOS Capabilities Kontrolü

Xcode'da Runner projesini açın ve şu capability'lerin aktif olduğunu kontrol edin:

1. **Push Notifications** capability'si eklenmeli
2. **Background Modes** > **Remote notifications** seçilmeli

**Xcode'da kontrol etmek için:**
```bash
open ios/Runner.xcworkspace
```

**Capabilities ekleme:**
1. Runner > Signing & Capabilities'e gidin
2. **+ Capability** > **Push Notifications** ekleyin
3. **+ Capability** > **Background Modes** > **Remote notifications** ekleyin

#### C) Info.plist Güncellemesi

Aşağıdaki key'lerin eklendiğinden emin olun (zaten varsa kontrol edin):

```xml
<!-- UIBackgroundModes - Background bildirimler için -->
<key>UIBackgroundModes</key>
<array>
    <string>remote-notification</string>
</array>
```

#### D) Podfile Güncellemesi

iOS 15.0 versiyonu yeterli, ek bir değişiklik gerekmiyor.

### 3. Debug Kontrol Listesi

#### Terminal'de log kontrolü

Uygulamayı çalıştırırken şu log'ları arayın:

```bash
# iOS Simulator'da çalıştırın
flutter run -d <simulator_id>

# Veya fiziksel cihazda (debug modda)
flutter run -d <device_id>
```

**Beklenen log'lar:**
```
✅ Bildirim izni verildi
🔑 FCM Token BAŞARIYLA ALINDI
💾 FCM token Supabase'e kaydedildi
```

**Sorunlu log'lar:**
```
❌ Bildirim izni reddedildi
❌ FCM TOKEN BOŞTUR
⚠️ Kullanıcının FCM TOKEN YOK!
```

#### Cihazda Test

1. **Simulator'da test edilmez** - Simulator push notification desteklemez
2. **Fiziksel iOS cihazı** kullanın
3. **Development mode** veya **TestFlight** ile test edin

### 4. Firebase Cloud Messaging Test

#### Test Bildirimi Gönder

1. Firebase Console > Messaging > New notification
2. iOS cihazına test bildirimi gönderin
3. Bildirim gelmiyorsa Firebase Console'daki hataları kontrol edin

### 5. AppDelegate Güncellemesi Detayları

Yapılan değişiklikler:

```swift
// 1. Firebase başlatma
FirebaseApp.configure()

// 2. UNUserNotificationCenter delegate
UNUserNotificationCenter.current().delegate = self

// 3. FCM Messaging delegate
Messaging.messaging().delegate = self

// 4. APNs token'ı FCM'e bildirme
Messaging.messaging().apnsToken = deviceToken
```

### 6. Supabase tarafında Token Kaydetme Kontrolü

`profiles` tablosunda `fcm_token` sütunu olduğundan emin olun:

```sql
-- Supabase SQL Editor'de çalıştırın
SELECT fcm_token, id, username 
FROM profiles 
WHERE fcm_token IS NOT NULL 
LIMIT 10;
```

Boş sonuç dönüyorsa, kullanıcı FCM token'ı alamıyor demektir.

### 7. Şifreleme Export Uyumluluğu

Info.plist'de:
```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

Bu doğru. Eğer `true` olsaydı, export compliance dokümantasyonu gerekirdi.

---

## Önceki AppDelegate (Referans)

```swift
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}
```

## Yeni AppDelegate (Güncel)

```swift
import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Firebase'i başlat
    FirebaseApp.configure()
    
    // Firebase Messaging background handler'ı set et
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self as UNUserNotificationCenterDelegate
      Messaging.messaging().delegate = self as MessagingDelegate
    }
    
    // Register with APNs
    let center = UNUserNotificationCenter.current()
    center.requestAuthorization(options: [.alert, .sound, .badge]) { granted, error in
      if let error = error {
        print("Notification authorization error: \(error)")
      }
      print("Notification authorization granted: \(granted)")
    }
    
    application.registerForRemoteNotifications()
    
    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // FCM APNs token'ı alındığında FCM'e bildir
  override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let tokenParts = deviceToken.map { String(format: "%02.2hhx", $0) }
    let token = tokenParts.joined()
    print("APNs Device Token: \(token)")
    
    // FCM'e APNs token'ını set et
    Messaging.messaging().apnsToken = deviceToken
  }
  
  // FCM APNs token alma hatası
  override func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("Failed to register for remote notifications: \(error)")
  }
}

// FCM Messaging Delegate
extension AppDelegate: MessagingDelegate {
  func messaging(_ messaging: Messaging, didRefreshRegistrationToken fcmToken: String) {
    print("Firebase refresh token: \(fcmToken)")
  }
}
```

---

## Sonraki Adımlar

1. **Fiziksel iOS cihazında test edin** (Simulator push bildirim desteklemez)
2. **Firebase Console'da APNs yapılandırmasını kontrol edin**
3. **Xcode'da Push Notifications capability'sinin aktif olduğunu doğrulayın**
4. **Debug log'ları kontrol edin**

## Hala Çalışmıyorsa

1. Firebase Console'da iOS app'in **Cloud Messaging** ayarlarını kontrol edin
2. Apple Developer Console'da **Push Notifications** capability'sinin aktif olduğunu doğrulayın
3. Provisioning profile'ın push notification desteği olduğunu kontrol edin
4. TestFlight veya Ad Hoc ile production build test edin
