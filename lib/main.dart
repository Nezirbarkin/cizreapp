// ignore_for_file: avoid_print, deprecated_member_use, use_build_context_synchronously

import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:intl/date_symbol_data_local.dart';
import 'core/constants/app_constants.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/theme_provider.dart';
import 'core/providers/favorites_provider.dart';
import 'core/services/verification_service.dart';
import 'core/services/payment_service.dart';
import 'firebase_options.dart';
// ignore: unused_import
import 'features/market/providers/cart_provider.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/auth/screens/login_screen_v2.dart';
import 'features/auth/screens/register_screen.dart';
import 'features/auth/screens/register_screen_v2.dart';
import 'features/auth/screens/reset_password_screen.dart';
import 'features/auth/screens/reset_password_confirm_screen.dart';
import 'features/main/screens/main_screen.dart';
import 'features/admin/screens/admin_dashboard_screen.dart';
import 'features/profile/screens/user_profile_screen.dart';
import 'features/market/screens/shop_detail_screen.dart';

// Mobile/Desktop specific imports - using deferred imports
import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'core/services/push_notification_service.dart';
import 'core/services/cache_service.dart';
import 'core/services/connectivity_service.dart';
import 'core/services/analytics_service.dart';
import 'core/services/performance_monitoring_service.dart';
import 'core/services/cleanup_service.dart';
import 'core/services/storage_service.dart';
import 'core/services/permission_service.dart';
import 'core/models/cached_post_model.dart';

void main() async {
  // Web için path-based URL strategy kullan (hash # yerine clean URL)
  // Sunucu tarafında tüm route'ların index.html'e yönlendirilmesi gerekir
  usePathUrlStrategy();
  
  // Release modda da çalışan logger
  void log(String message) {
    print('🚀 CizreApp: $message');
  }

  WidgetsFlutterBinding.ensureInitialized();
  log('WidgetsFlutterBinding initialized');

  // Status bar'ı göster (mobil uygulama için)
  if (!kIsWeb) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.white, // Beyaz arka plan, status bar net görünsün
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.white,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.manual, overlays: [
      SystemUiOverlay.top,
      SystemUiOverlay.bottom,
    ]);
    log('✅ System UI overlay configured');
  }

  // Initialize date formatting for locale support
  await initializeDateFormatting('tr_TR');
  log('✅ DateFormatting initialized for tr_TR');

  // Global error handler
  FlutterError.onError = (details) {
    log('🔴 FlutterError: ${details.exception}');
    print('Stack: ${details.stack}');
  };

  // Supabase durumunu takip et
  bool supabaseInitialized = false;

  try {
    log('Starting initialization...');
    
    // Load environment variables (Web hariç) - Başarısız olsa da devam et
    if (!kIsWeb) {
      try {
        await dotenv.load(fileName: ".env");
        log('✅ Environment variables loaded');
      } catch (e) {
        log('⚠️ .env file not found or failed to load: $e');
        log('⚠️ Using hardcoded fallback values from AppConstants');
        // AppConstants'ta fallback değerler var, devam edelim
      }
    }

    // ⚡ OPTİMİZE: Servisleri paralel başlat (sıralı yerine)
    // Initialize Hive for local caching & analytics (Web hariç)
    if (!kIsWeb) {
      try {
        await Hive.initFlutter();
        Hive.registerAdapter(CachedPostAdapter());
        log('✅ Hive initialized');

        // Cache, Analytics, Cleanup ve Connectivity'yi paralel başlat
        await Future.wait([
          CacheService.initialize().catchError((e) {
            log('⚠️ Cache service initialization failed: $e');
            return null;
          }),
          AnalyticsService.initialize().catchError((e) {
            log('⚠️ Analytics service initialization failed: $e');
            return null;
          }),
          CleanupService().performStartupCleanup().catchError((e) {
            log('⚠️ Cleanup service failed: $e');
            return null;
          }),
          ConnectivityService().initialize().catchError((e) {
            log('⚠️ Connectivity service failed: $e');
            return null;
          }),
        ]);
        log('✅ All services initialized in parallel');
      } catch (e) {
        log('⚠️ Service initialization failed: $e');
        // Devam et, bu servisler olmadan da çalışabilir
      }
    } else {
      log('ℹ️ Hive & services skipped on web platform');
    }

    // ⚡ iOS PERFORMANCE: Firebase ve Supabase'i PARALEL başlat
    final supabaseUrl = AppConstants.supabaseUrl;
    final supabaseAnonKey = AppConstants.supabaseAnonKey;
    
    log('🔍 Supabase URL: ${supabaseUrl.isNotEmpty ? "AYARLI (${supabaseUrl.length} karakter)" : "BOŞ!"}');
    log('🔍 Supabase Anon Key: ${supabaseAnonKey.isNotEmpty ? "AYARLI (${supabaseAnonKey.length} karakter)" : "BOŞ!"}');
    
    // Firebase ve Supabase'i paralel başlat
    try {
      await Future.wait([
        // Firebase başlat
        Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        ).then((_) {
          log('✅ Firebase initialized');
          // Firebase background handler (Web hariç)
          if (!kIsWeb) {
            try {
              FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
              log('✅ Firebase background handler set');
            } catch (e) {
              log('⚠️ Firebase background handler failed: $e');
            }
          }
        }).catchError((e) {
          log('❌ Firebase initialization failed: $e');
        }),
        // Supabase başlat
        () async {
          if (supabaseUrl.isEmpty || supabaseAnonKey.isEmpty) {
            log('❌ Supabase başlatılamıyor: URL veya Anon Key boş!');
            supabaseInitialized = false;
          } else {
            await Supabase.initialize(
              url: supabaseUrl,
              anonKey: supabaseAnonKey,
              debug: false,
            );
            supabaseInitialized = true;
            log('✅ Supabase initialized');
          }
        }(),
      ]);
    } catch (e) {
      log('⚠️ Initialization error: $e');
    }
    
    // Supabase'e bağımlı servisleri paralel başlat
    if (!kIsWeb && supabaseInitialized) {
      await Future.wait([
        // Storage Service
        StorageService().loadS3SettingsFromDatabase().then((value) {
          final storageService = StorageService();
          log('✅ Storage service initialized (${storageService.isS3Enabled ? "S3" : "Supabase"})');
        }).catchError((e) {
          log('⚠️ Storage service initialization failed: $e');
          return null;
        }),
        // Push Notifications
        PushNotificationService.initialize().then((value) {
          log('✅ Push notification service initialized');
        }).catchError((e) {
          log('⚠️ Push notification service failed: $e');
          return null;
        }),
      ]);
      
      // ⚡ iOS PERFORMANCE: İzinleri ARKA PLANDA kontrol et (başlatmayı engellemesin)
      // İzin istemek iOS'ta system dialog gösterir ve kullanıcıyı bekletir
      // Bu yüzden uygulamayı açtıktan sonra arka planda kontrol et
      WidgetsBinding.instance.addPostFrameCallback((_) {
        try {
          final permissionService = PermissionService();
          permissionService.checkAndRequestAllPermissions().then((permissionResults) {
            log('✅ İzinler kontrol edildi: ${permissionResults.length} izin');
            for (final entry in permissionResults.entries) {
              if (entry.value.isPermanentlyDenied) {
                log('⚠️ ${entry.key} izni kalıcı olarak reddedildi - Ayarlardan açılması gerekebilir');
              }
            }
          }).catchError((e) {
            log('⚠️ İzin kontrolü hatası: $e');
          });
        } catch (e) {
          log('⚠️ İzin kontrolü hatası: $e');
        }
      });
    }
    
    log('🎉 Initialization completed, launching app...');

  } catch (e, stackTrace) {
    log('❌ FATAL ERROR during initialization: $e');
    print('Stack trace: $stackTrace');
    // Uygulama yine de başlatılsın
    log('⚠️ App will start with limited functionality');
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => FavoritesProvider()),
        // CartProvider - Auth durumuna göre dinamik olarak oluşturulacak
        // Not: Kullanıcı giriş yaptıktan sonra MainScreen'de oluşturulur
      ],
      child: CizreApp(supabaseInitialized: supabaseInitialized),
    ),
  );
}

class CizreApp extends StatefulWidget {
  const CizreApp({super.key, required this.supabaseInitialized});
  final bool supabaseInitialized;

  @override
  State<CizreApp> createState() => _CizreAppState();
}

class _CizreAppState extends State<CizreApp> {
  StreamSubscription<AuthState>? _authStateSubscription; // Nullable yap, Supabase başarısız olursa hata vermesin
  StreamSubscription<Uri>? _appLinksSubscription; // Web için nullable
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  
  /// Web'de profil/shop URL'sine doğrudan gidildiyse true
  bool get _isWebProfileRoute {
    if (!kIsWeb) return false;
    final path = Uri.base.path;
    return path.startsWith('/u/@') || path.startsWith('/s/');
  }
  
  @override
  void initState() {
    super.initState();
    
    // Deep link handling - Email doğrulama ve şifre yenileme için (Web hariç)
    if (!kIsWeb) {
      _initDeepLinkHandling();
    } else {
      // Web için URL kontrolü - şifre yenileme linki kontrolü
      _checkWebUrlForPasswordReset();
    }
    
    // Edge Function Warm-up - Cold start'ı önle
    // Kullanıcı giriş yapmışsa arka planda fonksiyonları ısıt
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.supabaseInitialized) {
        // Paralel warm-up: Hem verification hem payment fonksiyonları
        VerificationService.warmUpEdgeFunctions();
        PaymentService.warmUpEdgeFunctions();
        
        // Navigator key'i push notification servisine set et (Web hariç)
        if (!kIsWeb) {
          PushNotificationService.setNavigatorKey(_navigatorKey);
        }
        
        // Otomatik tema değişimi - uygulama her açıldığında tema otomatik değişsin
        ThemeProvider.applyAutoThemeOnLaunch().then((_) {
          // Tema değiştiğinde UI'ı güncelle
          final themeProvider = Provider.of<ThemeProvider>(context, listen: false);
          themeProvider.reloadTheme();
        });
      }
    });
    
    // Supabase Auth State Change Listener - Sadece Supabase başarılıysa
    if (widget.supabaseInitialized) {
      _authStateSubscription = Supabase.instance.client.auth.onAuthStateChange.listen((data) {
      final AuthChangeEvent event = data.event;
      // ignore: unused_local_variable
      final Session? session = data.session;
      
      print('🔐 Auth State Changed: $event');
      print('📧 Session: ${session != null ? "Active" : "None"}');
      print('📧 Email Confirmed: ${session?.user.emailConfirmedAt}');
      
      // Web'de profil/shop URL'sine gidildiyse auth yönlendirmelerini atla
      if (_isWebProfileRoute) {
        print('⚠️ Web profile route active, skipping all auth redirects');
        return;
      }
      
      // Password Recovery Event - Şifre yenileme linki tıklandığında
      if (event == AuthChangeEvent.passwordRecovery) {
        print('🔑 Password Recovery detected! Navigating to reset-confirm screen...');
        // Kısa bir gecikme ile route'ı değiştir (MaterialApp tamamen oluşması için)
        Future.delayed(const Duration(milliseconds: 500), () {
          final navigatorState = _navigatorKey.currentState;
          if (navigatorState != null && mounted) {
            navigatorState.pushReplacementNamed('/reset-password-confirm');
          }
        });
      }
      
      // Email Confirmation Event - Email doğrulama linki tıklandığında
      if (event == AuthChangeEvent.signedIn && session != null) {
        final emailConfirmedAtStr = session.user.emailConfirmedAt;
        final emailConfirmed = emailConfirmedAtStr != null;
        
        print('📧 Email Confirmed At: $emailConfirmedAtStr');
        
        if (emailConfirmed) {
          try {
            final confirmedAt = DateTime.parse(emailConfirmedAtStr);
            final now = DateTime.now();
            final isJustConfirmed = now.difference(confirmedAt).inSeconds < 60; // Son 60 saniye içinde onaylanmış
            
            print('⏰ Time since confirmation: ${now.difference(confirmedAt).inSeconds}s');
            
            if (isJustConfirmed) {
              print('✅ Email just confirmed!');
              
              // Web'de profil URL'si varsa ana sayfaya yönlendirme
              if (_isWebProfileRoute) {
                print('⚠️ Web profile route detected, skipping redirect to /main');
                return;
              }
              
              print('Navigating to main screen...');
              // Kısa gecikme ile ana ekrana git (Flutter routing hazır olsun)
              Future.delayed(const Duration(milliseconds: 800), () {
                if (mounted) {
                  final navigatorState = _navigatorKey.currentState;
                  if (navigatorState != null) {
                    navigatorState.pushNamedAndRemoveUntil('/main', (route) => false);
                  }
                }
              });
              return; // Warm-up'ı atla
            }
          } catch (e) {
            print('⚠️ Email confirmation date parse error: $e');
          }
        }
        
        // Kullanıcı giriş yaptığında warm-up yap (email doğrulama değilse)
        VerificationService.warmUpEdgeFunctions();
        PaymentService.warmUpEdgeFunctions();
      }
    });
    }
  }

  void _showEmailConfirmedDialog() {
    // Web'de profil URL'sinde bu dialogu gösterme
    if (_isWebProfileRoute) return;
    
    final context = _navigatorKey.currentContext;
    if (context == null) {
      print('⚠️ Context null, dialog gösterilemiyor');
      return;
    }
    
    // Önce mevcut tüm route'ları temizle
    Navigator.of(context).popUntil((route) => route.isFirst);
    
    // Dialog göster ve otomatik kapatıp ana ekrana git
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(color: Color(0xFFE8F8F5), shape: BoxShape.circle),
              child: const Icon(Icons.check_rounded, size: 40, color: Color(0xFF1ABC9C)),
            ),
            const SizedBox(height: 20),
            const Text('E-posta Doğrulandı!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF2C3E50))),
            const SizedBox(height: 8),
            const Text('Hesabınız başarıyla aktif edildi.', style: TextStyle(color: Color(0xFF7F8C8D))),
          ],
        ),
      ),
    ).then((_) {
      // Dialog kapandığında ana ekrana git
      if (mounted) {
        final navigatorState = _navigatorKey.currentState;
        if (navigatorState != null) {
          navigatorState.pushNamedAndRemoveUntil('/main', (route) => false);
        }
      }
    });
    
    // 2 saniye sonra otomatik kapat
    Future.delayed(const Duration(milliseconds: 2000), () {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    });
  }

  void _initDeepLinkHandling() {
    if (kIsWeb) return; // Web'de deep link gerekmez
    
    try {
      final appLinks = AppLinks();
      
      // Uygulama zaten açıkken gelen deep link
      _appLinksSubscription = appLinks.uriLinkStream.listen((uri) {
        print('🔗 Deep link alındı (app açık): $uri');
        _handleDeepLink(uri);
      }, onError: (err) {
        print('⚠️ Deep link stream hatası: $err');
      });
      
      // Uygulama kapalıyken deep link ile açılma (timeout ekli)
      appLinks.getInitialLink().timeout(
        const Duration(seconds: 2),
        onTimeout: () => null,
      ).then((uri) {
        if (uri != null && mounted) {
          print('🔗 Initial deep link alındı: $uri');
          // Kısa gecikme ile işle (uygulama tamamen başlamadan önce)
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) _handleDeepLink(uri);
          });
        }
      }).catchError((err) {
        print('⚠️ Initial deep link hatası: $err');
      });
    } catch (e) {
      print('⚠️ Deep link handling başlatılamadı: $e');
    }
  }

  // Web için şifre yenileme URL kontrolü
  void _checkWebUrlForPasswordReset() {
    // Hemen kontrol et, sonra 2 saniye sonra tekrar kontrol et
    // Supabase SDK'nın URL'yi işlemesi için zaman tanı
    Future.delayed(const Duration(milliseconds: 500), () => _checkUrl());
    Future.delayed(const Duration(seconds: 2), () => _checkUrl());
  }
  
  void _checkUrl() {
    if (!mounted) return;
    
    // URL'deki hash fragment'ını kontrol et
    // Supabase şu formatı kullanır: https://site.com#access_token=...&type=recovery
    final Uri uri = Uri.base;
    final fragment = uri.fragment;
    
    print('🔗 Web URL kontrolü:');
    print('   URL: $uri');
    print('   fragment: $fragment');
    
    if (fragment.isNotEmpty) {
      final params = Uri.splitQueryString(fragment);
      final type = params['type'];
      final accessToken = params['access_token'];
      
      print('   type: $type');
      print('   hasAccessToken: ${accessToken != null}');
      
      // Şifre yenileme linki (type=recovery)
      if (type == 'recovery' || accessToken != null) {
        print('🔑 Web şifre yenileme linki algılandı!');
        
        // Şifre yenileme onay ekranına yönlendir
        final navigatorState = _navigatorKey.currentState;
        if (navigatorState != null && mounted) {
          print('🔄 /reset-password-confirm ekranına yönlendiriliyor...');
          // Mevcut tüm route'ları temizle ve şifre sıfırlama ekranını aç
          navigatorState.pushNamedAndRemoveUntil(
            '/reset-password-confirm',
            (route) => false,
          );
        }
      }
    }
  }

  void _handleDeepLink(Uri uri) {
    print('🔗 Deep link işleniyor: $uri');
    print('   scheme: ${uri.scheme}');
    print('   host: ${uri.host}');
    print('   path: ${uri.path}');
    print('   queryParams: ${uri.queryParameters}');
    
    // Şifre sıfırlama linki - cizreapp://reset-password?token=xxx
    if (uri.scheme == 'cizreapp' && uri.host == 'reset-password') {
      final token = uri.queryParameters['token'];
      print('🔑 Şifre sıfırlama linki alındı, token: $token');
      
      // Şifre sıfırlama ekranına yönlendir
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          final navigatorState = _navigatorKey.currentState;
          if (navigatorState != null) {
            // Token varsa, şifre onay ekranına; yoksa sıfırlama ekranına
            if (token != null && token.isNotEmpty) {
              navigatorState.pushReplacementNamed('/reset-password-confirm');
            } else {
              navigatorState.pushReplacementNamed('/reset-password');
            }
          }
        }
      });
      return;
    }
    
    // Email doğrulama linki - cizreapp://verify veya https://www.cizreapp.com/verify
    final isVerifyLink = uri.host == 'verify' ||
                         uri.path.contains('/verify') ||
                         uri.host == 'recovery' ||
                         uri.path.contains('/recovery');
    
    print('   isVerifyLink: $isVerifyLink');
    
    if (!isVerifyLink) {
      print('   ⚠️ Verify link değil, atlanıyor');
      return;
    }
    
    // Token ve type parametrelerini al
    final token = uri.queryParameters['token'];
    final type = uri.queryParameters['type'];
    final accessToken = uri.fragment.isNotEmpty ? Uri.splitQueryString(uri.fragment)['access_token'] : null;
    final refreshToken = uri.fragment.isNotEmpty ? Uri.splitQueryString(uri.fragment)['refresh_token'] : null;
    final tokenHash = uri.queryParameters['token_hash'];
    
    print('   token: $token');
    print('   type: $type');
    print('   accessToken: $accessToken');
    print('   refreshToken: $refreshToken');
    print('   tokenHash: $tokenHash');
    
    // Supabase Flutter SDK deep link'i otomatik işler
    // Manuel intervention yapma, sadece log bırak
    print('✅ Deep link Supabase SDK tarafından otomatik işlenecek');
    
    // Eğer kullanıcı login değilse ve verify link geldiyse, ana ekrana yönlendir
    final currentUser = Supabase.instance.client.auth.currentUser;
    print('   Current user: ${currentUser?.id ?? "null"}');
    
    if (currentUser != null && currentUser.emailConfirmedAt != null) {
      print('✅ Kullanıcı zaten email doğrulamış, main screen\'e gidiliyor');
      Future.delayed(const Duration(milliseconds: 500), () {
        if (mounted) {
          final navigatorState = _navigatorKey.currentState;
          if (navigatorState != null) {
            navigatorState.pushNamedAndRemoveUntil('/main', (route) => false);
          }
        }
      });
    }
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    _appLinksSubscription?.cancel();
    super.dispose();
  }

  /// Web'de initial screen'i URL'ye göre belirle
  /// Splash ekranı tamamen kaldırıldı - direkt MainScreen'e gidilir
  Widget _getInitialScreen() {
    if (!kIsWeb) {
      // Mobil'de splash atlanır, direkt MainScreen'e gidilir
      return const MainScreen();
    }
    
    final path = Uri.base.path;
    print('🌐 Web URL path: $path');
    
    // Kullanıcı profili: /u/@username
    if (path.startsWith('/u/@')) {
      final username = path.replaceFirst('/u/@', '');
      if (username.isNotEmpty) {
        print('👤 Loading user profile for: @$username');
        return _UserProfileByUsernameScreen(username: username);
      }
    }
    
    // Satıcı profili: /s/:slug
    if (path.startsWith('/s/')) {
      final slug = path.replaceFirst('/s/', '');
      if (slug.isNotEmpty) {
        print('🏪 Loading shop for: $slug');
        return _ShopBySlugScreen(slug: slug);
      }
    }
    
    // Web'de MainScreen
    print('🏠 Loading main screen');
    return const MainScreen();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ThemeProvider>(
      builder: (context, themeProvider, _) {
        return MaterialApp(
          title: AppConstants.appName,
          debugShowCheckedModeBanner: false,
          navigatorKey: _navigatorKey,
          theme: themeProvider.themeData,
          // Web'de scroll davranışını özelleştir - tarayıcı scroll kaymasını önle
          scrollBehavior: kIsWeb ? const _WebScrollBehavior() : null,
          builder: (context, child) {
            // Web'de viewport kaymasını önle
            if (kIsWeb) {
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  // ViewInsets'i sıfırla (klavye açıldığında viewport kaymasını önle)
                  viewInsets: EdgeInsets.zero,
                ),
                child: child ?? const SizedBox.shrink(),
              );
            }
            return child ?? const SizedBox.shrink();
          },
          // Web'de URL'ye göre doğrudan doğru ekranı yükle
          home: _getInitialScreen(),
          onGenerateRoute: (settings) {
            // Web routing için özel route generator
            print('🔄 onGenerateRoute called: ${settings.name}');
            
            if (settings.name == null) return null;
            
            final routeName = settings.name!;
            final uri = Uri.tryParse(routeName);
            if (uri == null) return null;
            
            // Ana sayfa - MainScreen (splash kaldırıldı)
            if (routeName == '/' || routeName.isEmpty) {
              return MaterialPageRoute(
                settings: settings,
                builder: (context) => const MainScreen(),
              );
            }
            
            // Deep link handling - email doğrulama ve şifre yenileme
            // Hem cizreapp:// hem de https://www.cizreapp.com URL'lerini işle
            if (uri.scheme == 'cizreapp' &&
                (uri.host == 'verify' || uri.host == 'recovery' || uri.path.contains('verify') || uri.path.contains('recovery'))) {
              print('🔗 Deep link detected (custom scheme): ${settings.name}');
              // Supabase auth callback'i otomatik olarak işler
              return MaterialPageRoute(
                builder: (context) => const MainScreen(),
              );
            }
            
            // https://www.cizreapp.com Universal Links
            if ((uri.scheme == 'https' || uri.scheme == 'http') &&
                uri.host.contains('cizreapp.com') &&
                (uri.path.contains('/verify') || uri.path.contains('/recovery'))) {
              print('🔗 Universal Link detected: ${settings.name}');
              return MaterialPageRoute(
                builder: (context) => const MainScreen(),
              );
            }
            
            // ===== WEB PROFİL ROUTING =====
            // Kullanıcı profili: /u/@username
            if (routeName.startsWith('/u/@')) {
              final username = routeName.replaceFirst('/u/@', '');
              if (username.isNotEmpty) {
                print('👤 Kullanıcı profili: @$username');
                return MaterialPageRoute(
                  settings: settings,
                  builder: (context) => _UserProfileByUsernameScreen(username: username),
                );
              }
            }
            
            // Satıcı profili: /s/:slug
            if (routeName.startsWith('/s/')) {
              final slug = routeName.replaceFirst('/s/', '');
              if (slug.isNotEmpty) {
                print('🏪 Satıcı profili: $slug');
                return MaterialPageRoute(
                  settings: settings,
                  builder: (context) => _ShopBySlugScreen(slug: slug),
                );
              }
            }
            
            // Diğer rotalar için varsayılan davranış
            return null;
          },
          routes: {
            '/login': (context) => const LoginScreenV2(),
            '/login-v1': (context) => const LoginScreen(), // Eski sürüm yedek olarak
            '/register': (context) => const RegisterScreenV2(),
            '/register-v1': (context) => const RegisterScreen(), // Eski sürüm yedek olarak
            '/reset-password': (context) => const ResetPasswordScreen(),
            '/reset-password-confirm': (context) => const ResetPasswordConfirmScreen(),
            '/main': (context) => const MainScreen(),
            '/admin': (context) => const AdminDashboardScreen(),
          },
          showPerformanceOverlay: false,
        );
      },
    );
  }
}

// Web Demo Screen - Supabase olmadığında gösterilecek ekran
class WebDemoScreen extends StatelessWidget {
  const WebDemoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.primaryGreen,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.store,
              size: 100,
              color: AppTheme.white,
            ),
            const SizedBox(height: 24),
            Text(
              AppConstants.appName,
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.w900,
                color: AppTheme.white,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 48),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(
                'Web sürümü şu anda bakım modundadır.\nMobil uygulamayı kullanarak giriş yapabilirsiniz.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: AppTheme.white,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// SplashScreen tamamen kaldırıldı - Uygulama direkt MainScreen'den başlar

// ===== WEB PROFİL ROUTING HELPER SCREENS =====

/// Username'den kullanıcı profilini gösteren ekran
/// Kullanıcı adını alıp userId'ye çevirir ve UserProfileScreen'e yönlendirir
class _UserProfileByUsernameScreen extends StatefulWidget {
  final String username;

  const _UserProfileByUsernameScreen({required this.username});

  @override
  State<_UserProfileByUsernameScreen> createState() => _UserProfileByUsernameScreenState();
}

class _UserProfileByUsernameScreenState extends State<_UserProfileByUsernameScreen> {
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUserIdByUsername();
  }

  Future<void> _loadUserIdByUsername() async {
    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('id')
          .eq('username', widget.username)
          .maybeSingle();

      if (response == null) {
        setState(() {
          _isLoading = false;
          _error = 'Kullanıcı bulunamadı';
        });
        return;
      }

      final userId = response['id'] as String;
      if (!mounted) return;

      // UserProfileScreen'e yönlendir
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => UserProfileScreen(userId: userId),
        ),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Bir hata oluştu: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Yükleniyor...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Hata')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Geri Dön'),
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// Slug'dan satıcı profilini gösteren ekran
/// Slug'ı alıp shopId'ye çevirir ve ShopDetailScreen'e yönlendirir
class _ShopBySlugScreen extends StatefulWidget {
  final String slug;

  const _ShopBySlugScreen({required this.slug});

  @override
  State<_ShopBySlugScreen> createState() => _ShopBySlugScreenState();
}

class _ShopBySlugScreenState extends State<_ShopBySlugScreen> {
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadShopIdBySlug();
  }

  Future<void> _loadShopIdBySlug() async {
    try {
      final response = await Supabase.instance.client
          .from('shops')
          .select('id')
          .eq('slug', widget.slug)
          .maybeSingle();

      if (response == null) {
        setState(() {
          _isLoading = false;
          _error = 'Mağaza bulunamadı';
        });
        return;
      }

      final shopId = response['id'] as String;
      if (!mounted) return;

      // ShopDetailScreen'e yönlendir
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => ShopDetailScreen(shopId: shopId),
        ),
      );
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Bir hata oluştu: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(title: const Text('Yükleniyor...')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Hata')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.store_outlined, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Geri Dön'),
              ),
            ],
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// Web için özel scroll davranışı - tarayıcı seviyesinde scroll kaymasını önler
class _WebScrollBehavior extends MaterialScrollBehavior {
  const _WebScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  };
}
