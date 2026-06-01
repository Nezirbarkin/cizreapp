import Flutter
import UIKit
import FirebaseCore
import FirebaseMessaging
import UserNotifications
import GoogleMaps

@main
@objc class AppDelegate: FlutterAppDelegate {
  
  // iOS PERFORMANCE: Uygulama performansı için cache temizliği
  private var pendingNotificationLaunch: Bool = false
  
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    
    // Google Maps API Key
    GMSServices.provideAPIKey("AIzaSyBi120_sBg5IEgzaugQ-FgRAbZaW18267I")
    
    // iOS PERFORMANCE: Uygulama başlatma optimizasyonu
    // Arka plan bildirimleri için kontrol
    if let remoteNotification = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
      pendingNotificationLaunch = true
      // Push notification ile açıldıysa bildirimi işle
      self.application(application, didReceiveRemoteNotification: remoteNotification)
    }
    
    // UNUserNotificationCenter delegate'sini ayarla
    // Bu, foreground bildirimlerin iOS tarafında düzgün gösterilmesi için gerekli
    if #available(iOS 10.0, *) {
      UNUserNotificationCenter.current().delegate = self
    }
    
    // Firebase Messaging delegate'si - FCM token refresh için gerekli
    Messaging.messaging().delegate = self
    
    GeneratedPluginRegistrant.register(with: self)
    
    // Remote notification'a kayıt ol - APNs token almak için ZORUNLU
    // Bu çağrı olmadan iOS cihazına APNs token üretilmez ve FCM token alınamaz
    application.registerForRemoteNotifications()
    
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  
  // APNs token başarıyla alındığında - FCM'e bildir
  override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let tokenParts = deviceToken.map { String(format: "%02.2hhx", $0) }
    let token = tokenParts.joined()
    print("📱 APNs Device Token alındı: \(token.prefix(20))...")
    
    // APNs token'ını Firebase Messaging'e set et
    // Bu olmadan FCM, iOS için token üretemez ve bildirim gönderilemez
    Messaging.messaging().apnsToken = deviceToken
    
    // Firebase Messaging plugin'e de bildir (Flutter tarafı için)
    super.application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
  }
  
  // APNs token alma hatası
  override func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("❌ APNs token alma hatası: \(error.localizedDescription)")
    // Simulator'da bu hata normal - fiziksel cihazda hata ise sorun var
    #if targetEnvironment(simulator)
    print("ℹ️ Simulator'da push notification desteklenmez, bu hata beklenir")
    #endif
  }
}

// MARK: - MessagingDelegate
extension AppDelegate: MessagingDelegate {
  // FCM token yenilendiğinde
  func messaging(_ messaging: Messaging, didRefreshRegistrationToken fcmToken: String) {
    print("🔄 FCM Token yenilendi: \(fcmToken.prefix(30))...")
    // Flutter firebase_messaging plugin'i bu eventi otomatik handle eder
    // Ekstra bir şey yapmaya gerek yok
  }
}

// MARK: - UNUserNotificationCenterDelegate
extension AppDelegate {
  // Foreground'ta bildirim geldiğinde - iOS 10+
  @available(iOS 10.0, *)
  override func userNotificationCenter(_ center: UNUserNotificationCenter,
                                        willPresent notification: UNNotification,
                                        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
    // Bildirimi foreground'ta da göster (alert, badge, sound)
    completionHandler([.alert, .badge, .sound])
  }
  
  // Bildirime tıklandığında - iOS 10+
  @available(iOS 10.0, *)
  override func userNotificationCenter(_ center: UNUserNotificationCenter,
                                        didReceive response: UNNotificationResponse,
                                        withCompletionHandler completionHandler: @escaping () -> Void) {
    let userInfo = response.notification.request.content.userInfo
    print("📲 Bildirime tıklandı: \(userInfo)")
    
    // Firebase Messaging plugin'e bildir
    completionHandler()
  }
}
