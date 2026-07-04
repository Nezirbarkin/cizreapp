import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'notification_service.dart';

/// Android bildirim kanalı (Android 8+ için zorunlu)
const AndroidNotificationChannel _highImportanceChannel = AndroidNotificationChannel(
  'high_importance_channel', // ID
  'Önemli Bildirimler', // İsim
  description: 'Bu kanal önemli bildirimler için kullanılır.',
  importance: Importance.high,
  playSound: true,
  enableVibration: true,
  showBadge: true,
);

class PushNotificationService {
  static final FirebaseMessaging _firebaseMessaging = FirebaseMessaging.instance;
  static final NotificationService _notificationService = NotificationService();
  static final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  
  /// Navigator key - push bildirimi tıklandığında yönlendirme için
  static GlobalKey<NavigatorState>? navigatorKey;
  
  /// Bildirim geldiğinde çağrılacak callback
  static VoidCallback? onNewNotification;
  
  /// Navigator key'i set et (main.dart'tan çağrılmalı)
  static void setNavigatorKey(GlobalKey<NavigatorState> key) {
    navigatorKey = key;
    debugPrint('✅ Push notification navigator key ayarlandı');
  }
  
  /// Tüm push notification sistemini başlat
  static Future<void> initialize() async {
    try {
      debugPrint('🔥 Firebase Messaging initialize ediliyor...');

      // 1. Flutter Local Notifications'ı başlat (foreground bildirimler için)
      await _initializeLocalNotifications();

      // 2. Bildirim izinlerini iste
      if (!kIsWeb) {
        await _requestPermissions();
      } else {
        debugPrint('ℹ️ Web platformu tespit edildi, bildirim izni atlanıyor');
      }

      // 3. Foreground bildirim ayarları (iOS için)
      await _firebaseMessaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );

      // 4. Foreground message handler - Uygulama açıkken gelen bildirimler
      FirebaseMessaging.onMessage.listen((RemoteMessage message) {
        debugPrint('📲 Foreground bildirim alındı: ${message.notification?.title}');
        _showLocalNotification(message);
        // Callback çağır - bildirim sayısı güncellensin
        onNewNotification?.call();
      });

      // 5. Background message opened handler - Bildirime tıklanınca
      FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
        debugPrint('📲 Background bildirim açıldı: ${message.notification?.title}');
        _handleBackgroundMessageOpened(message);
      });
      
      // 6. App terminated state - Uygulama kapalıyken gelen bildirimleri kontrol et
      final initialMessage = await _firebaseMessaging.getInitialMessage();
      if (initialMessage != null) {
        debugPrint('📲 Uygulama kapalıyken bildirim alındı: ${initialMessage.notification?.title}');
        _handleBackgroundMessageOpened(initialMessage);
      }

      // 7. FCM token al ve kaydet (Web'de optional)
      if (!kIsWeb) {
        await _setupFCMToken();
        // 8. Firebase Topics - Tüm kullanıcılar bildirim alsın (giriş yapmış/yapmamış fark etmez)
        await _subscribeToTopics();
      } else {
        debugPrint('ℹ️ Web platformunda FCM token atlanıyor');
      }

      // 9. Auth durumunu dinle: kullanıcı giriş yapınca FCM token'ı kaydet.
      // KRİTİK: initialize() çoğu zaman kullanıcı giriş yapmadan ÖNCE çalışır,
      // bu yüzden _setupFCMToken içindeki _saveFCMToken userId=null olduğu için
      // atlanır ve profiles.fcm_token NULL kalır -> push HİÇ gelmez.
      // signedIn olayında token'ı tekrar kaydederek bunu garanti altına alıyoruz.
      if (!kIsWeb) {
        Supabase.instance.client.auth.onAuthStateChange.listen((data) {
          final event = data.event;
          if (event == AuthChangeEvent.signedIn ||
              event == AuthChangeEvent.tokenRefreshed ||
              event == AuthChangeEvent.userUpdated) {
            debugPrint('🔐 Auth olayı ($event) - FCM token güncelleniyor');
            updateTokenAfterLogin();
          }
        });
      }

      debugPrint('✅ Firebase Messaging initialize edildi');
    } catch (e) {
      debugPrint('❌ Firebase Messaging initialize hatası: $e');
    }
  }

  /// Flutter Local Notifications başlat
  static Future<void> _initializeLocalNotifications() async {
    try {
      // Android ayarları
      const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
      
      // iOS ayarları
      const iosSettings = DarwinInitializationSettings(
        requestAlertPermission: true,
        requestBadgePermission: true,
        requestSoundPermission: true,
      );

      const initSettings = InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      );

      await _localNotifications.initialize(
        initSettings,
        onDidReceiveNotificationResponse: (NotificationResponse response) {
          debugPrint('📲 Local bildirime tıklandı: ${response.payload}');
          // Burada ilgili sayfaya yönlendirme yapılabilir
        },
      );

      // Android bildirim kanalını oluştur
      if (!kIsWeb && Platform.isAndroid) {
        final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        if (androidPlugin != null) {
          await androidPlugin.createNotificationChannel(_highImportanceChannel);
          debugPrint('✅ Android bildirim kanalı oluşturuldu');
        }
      }

      debugPrint('✅ Flutter Local Notifications başlatıldı');
    } catch (e) {
      debugPrint('❌ Local Notifications başlatma hatası: $e');
    }
  }

  /// Bildirim izinlerini iste
  static Future<void> _requestPermissions() async {
    try {
      // Firebase messaging izni
      NotificationSettings settings = await _firebaseMessaging.requestPermission(
        alert: true,
        announcement: false,
        badge: true,
        carPlay: false,
        criticalAlert: false,
        provisional: false,
        sound: true,
      );

      if (settings.authorizationStatus == AuthorizationStatus.authorized) {
        debugPrint('✅ Bildirim izni verildi');
      } else if (settings.authorizationStatus == AuthorizationStatus.provisional) {
        debugPrint('⚠️ Bildirim geçici izni verildi');
      } else {
        debugPrint('❌ Bildirim izni reddedildi - PUSH NOTIFICATION ÇALIŞMAYACAK!');
        debugPrint('❌ Kullanıcıya ayarlardan izin vermesini hatırlatın.');
      }

      // Android 13+ (API 33+) için ek izin kontrolü
      if (Platform.isAndroid) {
        final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
        if (androidPlugin != null) {
          final granted = await androidPlugin.requestNotificationsPermission();
          debugPrint('🔔 Android POST_NOTIFICATIONS izni: ${granted == true ? "VERİLDİ" : "REDDEDİLDİ"}');
        }
      }
    } catch (e) {
      debugPrint('❌ İzin isteme hatası: $e');
    }
  }

  /// FCM token al ve kaydet
  static Future<void> _setupFCMToken() async {
    try {
      debugPrint('🔍 FCM Token sorgusu yapılıyor...');
      String? token = await _firebaseMessaging.getToken();

      if (token != null && token.isNotEmpty) {
        debugPrint('🔑 FCM Token BAŞARIYLA ALINDI: ${token.substring(0, 50)}...');
        await _saveFCMToken(token);
      } else {
        debugPrint('❌ FCM TOKEN BOŞTUR! Firebase yapılandırması kontrol edilmeli.');
        // Retry
        await Future.delayed(const Duration(seconds: 3));
        String? retryToken = await _firebaseMessaging.getToken();
        if (retryToken != null && retryToken.isNotEmpty) {
          debugPrint('🔄 Retry başarılı: ${retryToken.substring(0, 50)}...');
          await _saveFCMToken(retryToken);
        } else {
          debugPrint('❌ Retry de başarısız oldu! google-services.json doğru mu?');
        }
      }

      // Token yenileme dinle
      _firebaseMessaging.onTokenRefresh.listen((newToken) {
        debugPrint('🔄 FCM Token yenilendi: ${newToken.substring(0, 50)}...');
        _saveFCMToken(newToken);
      });
    } catch (e) {
      debugPrint('❌ FCM token setup hatası: $e');
    }
  }

  /// Firebase Topics'e abone ol - Admin push bildirimleri için
  /// Bu sayede giriş yapmamış kullanıcılar da bildirim alabilir
  static Future<void> _subscribeToTopics() async {
    try {
      debugPrint('🔥 Firebase Topics\'e abone olunuyor...');
      
      // Tüm kullanıcıları "all_users" topic'ine abone et
      await _firebaseMessaging.subscribeToTopic('all_users');
      debugPrint('✅ "all_users" topic\'ine abone olundu');
      
      // Giriş yapmış kullanıcıları "logged_in_users" topic'ine abone et
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId != null) {
        await _firebaseMessaging.subscribeToTopic('logged_in_users');
        debugPrint('✅ "logged_in_users" topic\'ine abone olundu');
      }
    } catch (e) {
      debugPrint('❌ Topic abonelik hatası: $e');
    }
  }

  /// Foreground bildirim göster (uygulama açıkken)
  static Future<void> _showLocalNotification(RemoteMessage message) async {
    try {
      final notification = message.notification;
      if (notification == null) {
        debugPrint('⚠️ Bildirimde notification payload yok, data-only mesaj');
        return;
      }

      debugPrint('📬 Foreground bildirim gösteriliyor: ${notification.title}');

      // icon_type'a göre özel ikon rengini al
      final iconType = message.data['icon_type'] as String?;
      final Color iconColor = _getIconColor(iconType);
      
      // İkon tipine göre küçük renk göstergesi için badge rengi ayarla
      final androidDetails = AndroidNotificationDetails(
        'high_importance_channel',
        'Önemli Bildirimler',
        channelDescription: 'Bu kanal önemli bildirimler için kullanılır.',
        importance: Importance.high,
        priority: Priority.high,
        showWhen: true,
        playSound: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
        color: iconColor,
      );

      const iosDetails = DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        threadIdentifier: 'cizreapp_notifications',
      );

      final notificationDetails = NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      );

      // Başlık ve içerik
      final String title = notification.title ?? 'Yeni Bildirim';
      final String body = notification.body ?? '';
      
      debugPrint('📱 Bildirim gösteriliyor - Başlık: $title, İkon: $iconType, Renk: $iconColor');

      await _localNotifications.show(
        notification.hashCode, // Unique ID
        title,
        body,
        notificationDetails,
        payload: message.data.toString(),
      );

      debugPrint('✅ Local bildirim gösterildi (icon_type: $iconType)');
    } catch (e) {
      debugPrint('❌ Local bildirim gösterme hatası: $e');
    }
  }

  /// İkon tipine göre bildirim rengini döndür
  static Color _getIconColor(String? iconType) {
    switch (iconType) {
      case 'announcement':
        return const Color(0xFF2196F3); // Mavi
      case 'discount':
        return const Color(0xFFF44336); // Kırmızı
      case 'campaign':
        return const Color(0xFFFF9800); // Turuncu
      case 'news':
        return const Color(0xFF009688); // Teal
      case 'event':
        return const Color(0xFF9C27B0); // Mor
      case 'update':
        return const Color(0xFF4CAF50); // Yeşil
      case 'warning':
        return const Color(0xFFFFC107); // Amber
      case 'gift':
        return const Color(0xFFE91E63); // Pembe
      case 'info':
        return const Color(0xFF3F51B5); // Indigo
      default:
        return const Color(0xFF2196F3); // Varsayılan mavi
    }
  }

  /// Background mesajı handle et - Bildirime tıklanınca
  static void _handleBackgroundMessageOpened(RemoteMessage message) {
    try {
      debugPrint('📬 Background mesaj açıldı...');
      debugPrint('Title: ${message.notification?.title}');
      debugPrint('Body: ${message.notification?.body}');
      debugPrint('Data: ${message.data}');
      
      final notificationType = message.data['type'];
      final entityId = message.data['entity_id'] ?? message.data['postId'] ?? message.data['post_id'];
      
      debugPrint('📍 Yönlendirme: type=$notificationType, entityId=$entityId');
      
      // Navigator key varsa yönlendirme yap
      if (navigatorKey?.currentState != null) {
        _navigateToNotificationPage(notificationType, entityId, message.data);
      } else {
        debugPrint('⚠️ Navigator key yok, yönlendirme yapılamıyor');
      }
    } catch (e) {
      debugPrint('❌ Background mesaj açma hatası: $e');
    }
  }
  
  /// Bildirime tıklandığında ilgili sayfaya yönlendir
  static void _navigateToNotificationPage(
    String? type,
    String? entityId,
    Map<String, dynamic> data,
  ) {
    if (navigatorKey?.currentState == null) {
      debugPrint('⚠️ Navigator state yok, yönlendirme yapılamıyor');
      return;
    }
    
    final context = navigatorKey!.currentState!.context;
    
    debugPrint('🔄 Yönlendirme yapılıyor: type=$type, entityId=$entityId');
    
    // Bildirim tipine göre yönlendirme
    switch (type) {
      case 'like':
      case 'post_like':
      case 'comment':
      case 'post_comment':
      case 'mention':
      case 'post_mention':
      case 'post':
      case 'post_share':
        // Gönderi detayına git
        if (entityId != null) {
          _navigateToMainScreenWithPost(context, entityId);
        } else {
          _navigateToMainScreen(context);
        }
        break;
        
      case 'follow':
      case 'follower':
      case 'follow_request':
      case 'follow_accepted':
        final actorId = data['actor_id'] as String?;
        if (actorId != null) {
          _navigateToMainScreenWithProfile(context, actorId);
        } else {
          _navigateToMainScreen(context);
        }
        break;
        
      case 'chat':
      case 'message':
        _navigateToMainScreen(context);
        break;
        
      case 'order':
      case 'order_update':
      case 'order_status':
      case 'order_confirmed':
      case 'new_order':
      case 'delivered':
        _navigateToMainScreen(context);
        break;
        
      case 'group_message':
        final groupId = data['group_id'] as String?;
        if (groupId != null) {
          // TODO: Grup sohbet ekranına yönlendir
          _navigateToMainScreen(context);
        } else {
          _navigateToMainScreen(context);
        }
        break;
        
      case 'group_join_request':
      case 'group_member_joined':
        _navigateToMainScreen(context);
        break;
        
      case 'review_request':
      case 'review_pending':
        // entityId sipariş ID'sidir, doğrudan değerlendirme ekranına yönlendir
        if (entityId != null && !entityId.startsWith('admin_icon:')) {
          _navigateToMainScreenWithOrderReview(context, entityId);
        } else {
          _navigateToMainScreen(context);
        }
        break;
        
      case 'admin_notification':
        _navigateToMainScreen(context);
        break;
        
      default:
        // Varsayılan: MainScreen'e git
        _navigateToMainScreen(context);
        break;
    }
  }
  
  /// MainScreen'e git (bildirimler sekmesi açık)
  static void _navigateToMainScreen(BuildContext context) {
    try {
      // Mevcut rotada olduğumuzu kontrol et
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/main',
        (route) => false,
      );
      debugPrint('✅ MainScreen\'e yönlendirildi');
    } catch (e) {
      debugPrint('❌ MainScreen\'e yönlendirme hatası: $e');
    }
  }
  
  /// MainScreen'e git ve gönderiyi aç
  static void _navigateToMainScreenWithPost(BuildContext context, String postId) {
    try {
      // Post ID'yi sakla, MainScreen'de açılacak
      _pendingPostId = postId;
      
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/main',
        (route) => false,
      );
      debugPrint('✅ MainScreen\'e yönlendirildi, post detayı açılacak: $postId');
    } catch (e) {
      debugPrint('❌ Post detayına yönlendirme hatası: $e');
      _navigateToMainScreen(context);
    }
  }
  
  /// MainScreen'e git ve profili aç
  static void _navigateToMainScreenWithProfile(BuildContext context, String userId) {
    try {
      // User ID'yi sakla, MainScreen'de açılacak
      _pendingUserId = userId;
      
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/main',
        (route) => false,
      );
      debugPrint('✅ MainScreen\'e yönlendirildi, profil açılacak: $userId');
    } catch (e) {
      debugPrint('❌ Profil açma hatası: $e');
      _navigateToMainScreen(context);
    }
  }
  
  /// Bekleyen gönderi ID'si (bildirimden gelen)
  static String? _pendingPostId;
  
  /// Bekleyen kullanıcı ID'si (bildirimden gelen)
  static String? _pendingUserId;
  
  /// Bekleyen sipariş ID'si (değerlendirme bildiriminden gelen)
  static String? _pendingOrderId;
  
  /// Bekleyen gönderi ID'sini al ve temizle
  static String? getAndClearPendingPostId() {
    final postId = _pendingPostId;
    _pendingPostId = null;
    return postId;
  }

  /// Bekleyen sipariş ID'sini al ve temizle (değerlendirme için)
  static String? getAndClearPendingOrderId() {
    final orderId = _pendingOrderId;
    _pendingOrderId = null;
    return orderId;
  }
  
  /// Bekleyen kullanıcı ID'sini al ve temizle
  static String? getAndClearPendingUserId() {
    final userId = _pendingUserId;
    _pendingUserId = null;
    return userId;
  }

  /// FCM token'ı Supabase'e kaydet
  static Future<void> _saveFCMToken(String token) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('⚠️ Kullanıcı giriş yapmamış, FCM token kaydedilmedi');
        return;
      }

      debugPrint('💾 FCM token Supabase\'e kaydediliyor... userId: $userId');
      debugPrint('📱 Token (ilk 50 karakter): ${token.substring(0, 50)}...');

      final response = await Supabase.instance.client
          .from('profiles')
          .update({'fcm_token': token})
          .eq('id', userId)
          .select('fcm_token')
          .single();

      final savedToken = response['fcm_token'] as String?;
      debugPrint('✅ FCM token Supabase\'e kaydedildi');
      debugPrint('🔍 Kaydedilen token (ilk 50 karakter): ${savedToken?.substring(0, 50)}...');
      
      // Token doğrulama
      if (savedToken == token) {
        debugPrint('✅ Token doğrulama BAŞARILI');
      } else {
        debugPrint('⚠️ Token doğrulama BAŞARISIZ - Beklenen: ${token.substring(0, 20)}, Kaydedilen: ${savedToken?.substring(0, 20)}');
      }
    } catch (e) {
      debugPrint('❌ FCM token kaydetme hatası: $e');
      debugPrint('❌ Hata detayı: ${e.toString()}');
    }
  }

  /// Kullanıcı giriş yaptıktan sonra FCM token'ı güncelle ve topic'lere abone et
  static Future<void> updateTokenAfterLogin() async {
    if (kIsWeb) return;
    
    try {
      String? token = await _firebaseMessaging.getToken();
      if (token != null && token.isNotEmpty) {
        debugPrint('🔄 Login sonrası FCM token güncelleniyor...');
        await _saveFCMToken(token);
      }
      // Giriş yapınca topic'lere tekrar abone ol
      await _subscribeToTopics();
    } catch (e) {
      debugPrint('❌ Login sonrası token güncelleme hatası: $e');
    }
  }

  /// FCM token'ı al
  static Future<String?> getFCMToken() async {
    try {
      return await _firebaseMessaging.getToken();
    } catch (e) {
      debugPrint('❌ FCM token alma hatası: $e');
      return null;
    }
  }

  /// FCM token'ı temizle (çıkış yaparken çağrılmalı)
  /// NOT: Bu metodu signOut() çağrısından ÖNCE çalıştırın!
  static Future<void> clearTokenOnLogout() async {
    if (kIsWeb) return;
    
    try {
      // Kullanıcı çıkış yaparken FCM token'ını veritabanından sil
      // Böylece bildirimler artık bu cihaza gönderilmez
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('⚠️ Kullanıcı zaten çıkış yapmış, token temizleme atlanıyor');
        return;
      }
      
      await Supabase.instance.client
          .from('profiles')
          .update({'fcm_token': null})
          .eq('id', userId);
      
      debugPrint('✅ Çıkışta FCM token temizlendi (userId: $userId)');
    } catch (e) {
      debugPrint('❌ Çıkışta FCM token temizleme hatası: $e');
    }
  }

  /// Test bildirimi gönder
  static Future<void> sendTestNotification(String userId) async {
    try {
      await _notificationService.createNotification(
        userId: userId,
        type: 'like',
        title: 'Test Push Bildirimi',
        content: 'Bu bir test push bildirimidir',
        actorName: 'System',
      );
      debugPrint('✅ Test bildirimi gönderildi');
    } catch (e) {
      debugPrint('❌ Test bildirimi gönderme hatası: $e');
    }
  }

  /// MainScreen'e git ve sipariş değerlendirme ekranını aç
  /// review_pending/review_request bildirimleri için kullanılır
  static void _navigateToMainScreenWithOrderReview(BuildContext context, String orderId) {
    try {
      // Sipariş ID'yi sakla, MainScreen'de değerlendirme dialog'u açılacak
      _pendingOrderId = orderId;
      
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/main',
        (route) => false,
      );
      debugPrint('✅ MainScreen\'e yönlendirildi, sipariş değerlendirme açılacak: $orderId');
    } catch (e) {
      debugPrint('❌ Sipariş değerlendirmeye yönlendirme hatası: $e');
      _navigateToMainScreen(context);
    }
  }
}

/// Background handler (top-level) - Uygulama kapalıyken bildirim gelme
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  debugPrint('🔥🔥🔥 BACKGROUND HANDLER ÇALIŞTI 🔥🔥🔥');
  debugPrint('Title: ${message.notification?.title}');
  debugPrint('Body: ${message.notification?.body}');
  debugPrint('Data: ${message.data}');
  debugPrint('Timestamp: ${DateTime.now().toIso8601String()}');
}
