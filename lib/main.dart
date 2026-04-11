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

    // Firebase ve Supabase'i paralel başlat - KRİTİK servisler
    // Servisleri ayrı ayrı başlat (Future.wait tipler uyumsuz)
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
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
    } catch (e) {
      log('❌ Firebase initialization failed: $e');
    }

    // Supabase başlat
    try {
      await Supabase.initialize(
        url: AppConstants.supabaseUrl,
        anonKey: AppConstants.supabaseAnonKey,
        debug: false,
      );
      supabaseInitialized = true;
      log('✅ Supabase initialized');
      
      // Supabase'e bağımlı servisleri paralel başlat
      if (!kIsWeb) {
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
            // Navigator key'i set et (bildirime tıklandığında yönlendirme için)
            // Not: navigatorKey'in build metodunda oluşturulması gerekiyor
            // Bu yüzden initState'da set edemeyiz, postFrameCallback kullanacağız
          }).catchError((e) {
            log('⚠️ Push notification service failed: $e');
            return null;
          }),
        ]);
      }
    } catch (e) {
      log('⚠️ Supabase initialization failed: $e');
      supabaseInitialized = false;
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
      if (uri != null) {
        print('🔗 Initial deep link alındı: $uri');
        // Kısa gecikme ile işle (uygulama tamamen başlamadan önce)
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) _handleDeepLink(uri);
        });
      }
    }).catchError((err) {
      print('⚠️ Initial deep link hatası: $err');
    });
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
  Widget _getInitialScreen() {
    if (!kIsWeb) {
      return SplashScreen(supabaseInitialized: widget.supabaseInitialized);
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
    
    // Ana sayfa veya bilinmeyen rotalar
    print('🏠 Loading splash/main screen');
    return SplashScreen(supabaseInitialized: widget.supabaseInitialized);
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
            
            // Ana sayfa - SplashScreen
            if (routeName == '/' || routeName.isEmpty) {
              return MaterialPageRoute(
                settings: settings,
                builder: (context) => SplashScreen(supabaseInitialized: widget.supabaseInitialized),
              );
            }
            
            // Deep link handling - email doğrulama ve şifre yenileme
            // Hem cizreapp:// hem de https://www.cizreapp.com URL'lerini işle
            if (uri.scheme == 'cizreapp' &&
                (uri.host == 'verify' || uri.host == 'recovery' || uri.path.contains('verify') || uri.path.contains('recovery'))) {
              print('🔗 Deep link detected (custom scheme): ${settings.name}');
              // Supabase auth callback'i otomatik olarak işler
              return MaterialPageRoute(
                builder: (context) => SplashScreen(supabaseInitialized: widget.supabaseInitialized),
              );
            }
            
            // https://www.cizreapp.com Universal Links
            if ((uri.scheme == 'https' || uri.scheme == 'http') &&
                uri.host.contains('cizreapp.com') &&
                (uri.path.contains('/verify') || uri.path.contains('/recovery'))) {
              print('🔗 Universal Link detected: ${settings.name}');
              return MaterialPageRoute(
                builder: (context) => SplashScreen(supabaseInitialized: widget.supabaseInitialized),
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

// Splash Screen - Başlangıç ekranı
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, required this.supabaseInitialized});
  final bool supabaseInitialized;

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _hasError = false;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  // Release modda da çalışan logger
  void _log(String message) {
    print('🚀 CizreApp: $message');
  }

  Future<void> _initialize() async {
    _log('SplashScreen: Başlatılıyor...');
    
    try {
      // Versiyon kontrolü
      await _checkVersion();
      
      // Hızlı başlangıç için süreyi kısalttık
      await Future.delayed(const Duration(milliseconds: 800));
      
      _log('SplashScreen: Gecikme tamamlandı, yönlendirilecek...');
      
      if (!mounted) {
        _log('SplashScreen: Widget mounted değil, iptal ediliyor');
        return;
      }
      
      // Mevcut route'u kontrol et - özel route varsa (profil, shop vb.) yönlendirme yapma
      final currentRoute = ModalRoute.of(context)?.settings.name;
      _log('SplashScreen: Mevcut route: $currentRoute');
      
      // Özel route'lar varsa (profil, shop gibi) ana sayfaya yönlendirme
      if (currentRoute != null && currentRoute != '/' && currentRoute != '/main') {
        _log('SplashScreen: Özel route tespit edildi ($currentRoute), yönlendirme yapılmıyor');
        return;
      }
      
      // Ana ekrana yönlendir (web'de loginsiz, mobil'de login ile)
      _log('SplashScreen: /main rotasına yönlendiriliyor...');
      
      if (mounted) {
        Navigator.of(context).pushReplacementNamed('/main');
        _log('SplashScreen: Yönlendirme tamamlandı');
      }
    } catch (e, stackTrace) {
      _log('❌ SplashScreen HATASI: $e');
      _log('Stack: $stackTrace');
      
      if (mounted) {
        setState(() {
          _hasError = true;
          _errorMessage = 'Başlatma hatası: $e';
        });
      }
    }
  }

  Future<void> _checkVersion() async {
    if (kIsWeb) {
      _log('Versiyon kontrolü web\'de atlanıyor');
      return;
    }

    try {
      final packageInfo = await PackageInfo.fromPlatform();
      final currentVersion = packageInfo.version;
      final currentBuildCode = int.tryParse(packageInfo.buildNumber) ?? 0;

      _log('📱 Mevcut Versiyon: $currentVersion (build: $currentBuildCode)');

      final result = await Supabase.instance.client.rpc(
        'check_app_version',
        params: {
          'p_current_version': currentVersion,
          'p_current_build_code': currentBuildCode,
        },
      );

      if (result == null) {
        _log('⚠️ Versiyon kontrolü başarısız, varsayılan olarak devam ediliyor');
        return;
      }

      final checkResult = result as Map<String, dynamic>;
      final needsUpdate = checkResult['needs_update'] as bool? ?? false;
      final isForced = checkResult['is_forced'] as bool? ?? false;
      final minVersion = checkResult['min_version'] as String? ?? '0.0.0';

      _log('📊 Versiyon Kontrolü: needsUpdate=$needsUpdate, isForced=$isForced');

      if (needsUpdate && mounted) {
        _showUpdateDialog(
          isForced: isForced,
          minVersion: minVersion,
          currentVersion: currentVersion,
        );
      }
    } catch (e) {
      _log('⚠️ Versiyon kontrolü hatası: $e');
    }
  }

  void _showUpdateDialog({
    required bool isForced,
    required String minVersion,
    required String currentVersion,
  }) {
    showDialog(
      context: context,
      barrierDismissible: !isForced,
      builder: (context) => WillPopScope(
        onWillPop: () async => !isForced,
        child: AlertDialog(
          title: Row(
            children: [
              Icon(Icons.system_update, color: isForced ? Colors.red : Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isForced ? 'Zorunlu Güncelleme' : 'Güncelleme Mevcut',
                  style: TextStyle(fontSize: 18),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                isForced
                    ? 'Uygulamanın yeni versiyonu çıkarılmıştır. Devam etmek için lütfen güncelleyin.'
                    : 'Yeni bir versiyon mevcut. Daha iyi deneyim için güncellemenizi öneririz.',
              ),
              const SizedBox(height: 12),
              Text(
                'Mevcut: $currentVersion',
                style: TextStyle(color: Colors.grey.shade600),
              ),
              Text(
                'Gerekli: $minVersion',
                style: TextStyle(color: Colors.grey.shade600, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          actions: [
            if (!isForced)
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text('Daha Sonra'),
              ),
            ElevatedButton(
              onPressed: () {
                // Store'a yönlendir (Google Play veya App Store)
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Lütfen uygulama mağazasından güncelleyin')),
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: isForced ? Colors.red : Colors.green,
              ),
              child: Text(isForced ? 'Şimdi Güncelle' : 'Güncelle'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Scaffold(
        backgroundColor: Colors.red.shade100,
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 80, color: Colors.red.shade700),
                const SizedBox(height: 24),
                Text('Bir hata oluştu', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 16),
                Text(_errorMessage, textAlign: TextAlign.center),
                const SizedBox(height: 32),
                ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _hasError = false;
                      _errorMessage = '';
                    });
                    _initialize();
                  },
                  child: Text('Tekrar Dene'),
                ),
              ],
            ),
          ),
        ),
      );
    }
    
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF1ABC9C), // Turkuaz
              Color(0xFF16A085), // Koyu turkuaz
              Color(0xFF2C3E50), // Koyu mavi-gri
            ],
            stops: [0.0, 0.5, 1.0],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  // CizreApp Başlığı
                  Text(
                    'CizreApp',
                    style: TextStyle(
                      fontSize: 52,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      letterSpacing: 3,
                      shadows: [
                        Shadow(
                          color: Colors.black.withOpacity(0.2),
                          offset: Offset(0, 4),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  
                  // Açıklama
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      'Cizre\'nin Dijital Pazarı & Sosyal Medya Ağı',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withOpacity(0.95),
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  const SizedBox(height: 60),
                  
                  // İkonlar Grid - 2x3
                  GridView.count(
                    shrinkWrap: true,
                    physics: NeverScrollableScrollPhysics(),
                    crossAxisCount: 3,
                    mainAxisSpacing: 20,
                    crossAxisSpacing: 20,
                    childAspectRatio: 1,
                    children: [
                      _buildModernIcon(Icons.shopping_cart_outlined, 'Pazar'),
                      _buildModernIcon(Icons.storefront_outlined, 'Mağazalar'),
                      _buildModernIcon(Icons.delivery_dining_outlined, 'Teslimat'),
                      _buildModernIcon(Icons.sentiment_satisfied_alt_outlined, 'Sosyal'),
                      _buildModernIcon(Icons.chat_bubble_outline, 'Sohbet'),
                      _buildModernIcon(Icons.card_giftcard_outlined, 'Kampanyalar'),
                    ],
                  ),
                  const SizedBox(height: 50),
                  
                  // Yükleniyor göstergesi
                  SizedBox(
                    width: 40,
                    height: 40,
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      strokeWidth: 2.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildModernIcon(IconData icon, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 65,
          height: 65,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.2),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 8,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Icon(
            icon,
            color: Colors.white,
            size: 32,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: TextStyle(
            color: Colors.white.withOpacity(0.85),
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.3,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

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
