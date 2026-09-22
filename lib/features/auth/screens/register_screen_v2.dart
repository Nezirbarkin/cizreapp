// ignore_for_file: deprecated_member_use, curly_braces_in_flow_control_structures

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/auth_service.dart';
import '../widgets/auth_shell.dart';
import 'choose_username_screen.dart';
import '../../../core/services/verification_service.dart';

class RegisterScreenV2 extends StatefulWidget {
  const RegisterScreenV2({super.key});

  @override
  State<RegisterScreenV2> createState() => _RegisterScreenV2State();
}

class _RegisterScreenV2State extends State<RegisterScreenV2> {
  static const _privacyPolicyUrl = 'https://cizreapp.com/privacy.html';

  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _fullNameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  // OTP controllers - 6 haneli kod için
  final List<TextEditingController> _otpControllers = List.generate(
    6,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());

  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isCheckingUsername = false;
  bool _isUsernameAvailable = true;
  bool _kvkkAccepted = false;
  bool _termsAccepted = false; // EULA/Kullanım Koşulları kabul

  /// Kayıt akışı üç adıma bölündü: 0 = bilgiler, 1 = şifre ve onaylar,
  /// 2 = e-posta doğrulama kodu. Eski tek sayfalık form kullanıcıyı beş alan
  /// ve iki büyük onay kartıyla aynı anda karşılıyordu.
  int _step = 0;

  /// Birinci adımın kendi doğrulaması. İkinci adım mevcut [_formKey]'i
  /// kullanmaya devam eder, böylece [_validateForm] değişmeden çalışır.
  final _stepOneFormKey = GlobalKey<FormState>();

  final _fullNameFocus = FocusNode();
  final _emailFocus = FocusNode();
  final _confirmPasswordFocus = FocusNode();

  // OTP state
  int _remainingSeconds = 0;
  int _resendCooldown = 0;
  Timer? _timer;
  Timer? _resendTimer;
  String? _verifiedEmail;

  final _verificationService = VerificationService();
  final _authService = AuthService();

  @override
  void dispose() {
    _usernameController.dispose();
    _fullNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _fullNameFocus.dispose();
    _emailFocus.dispose();
    _confirmPasswordFocus.dispose();
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _otpFocusNodes) {
      node.dispose();
    }
    _timer?.cancel();
    _resendTimer?.cancel();
    super.dispose();
  }

  // İzin verilen kullanıcı adı karakterleri: harf, rakam, nokta, alt çizgi, tire
  static final RegExp _usernameAllowedChars = RegExp(r'^[a-zA-Z0-9._-]+$');

  /// Kullanıcı adını kurallara göre temizler: boşluk ve izin verilmeyen
  /// karakterleri kaldırır. Bu, yapıştırma durumunda da geçerlidir.
  String _sanitizeUsername(String value) {
    final buf = StringBuffer();
    for (final ch in value.characters) {
      if (RegExp(r'[a-zA-Z0-9._-]').hasMatch(ch)) {
        buf.write(ch);
      }
    }
    return buf.toString();
  }

  Future<void> _checkUsername(String username) async {
    // Boşluk/özel karakter barındırıyorsa müsaitlik kontrolü yapma
    if (!_usernameAllowedChars.hasMatch(username)) {
      if (mounted) setState(() => _isUsernameAvailable = false);
      return;
    }
    if (username.length < 3) return;
    setState(() => _isCheckingUsername = true);

    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('username')
          .eq('username', username.toLowerCase())
          .maybeSingle();

      if (mounted)
        setState(() {
          _isUsernameAvailable = response == null;
          _isCheckingUsername = false;
        });
    } catch (e) {
      if (mounted) setState(() => _isCheckingUsername = false);
    }
  }

  /// OTP kodunu al
  String get _otpCode => _otpControllers.map((c) => c.text).join();

  /// Form doğrulama
  bool _validateForm() {
    if (!_formKey.currentState!.validate()) return false;
    if (!_kvkkAccepted) {
      _showError('KVKK aydınlatma metnini kabul etmeniz gerekiyor');
      return false;
    }
    if (!_termsAccepted) {
      _showError('Kullanım Koşullarını kabul etmeniz gerekiyor');
      return false;
    }
    return true;
  }

  /// OTP gönder
  Future<void> _sendOtp() async {
    if (!_validateForm()) return;

    setState(() => _isLoading = true);

    try {
      final result = await _verificationService.sendRegistrationOtp(
        email: _emailController.text.trim(),
      );

      if (mounted) {
        setState(() {
          _step = 2;
          _remainingSeconds = result['expires_in_seconds'] ?? 300;
          _resendCooldown = 60; // 60 saniye yeniden gönderme cooldown
          _verifiedEmail = _emailController.text.trim();
        });

        _startTimer();
        _startResendTimer();

        _showSuccess(
          result['message'] ?? 'Doğrulama kodu e-posta adresinize gönderildi',
        );

        // İlk OTP kutusuna odaklan. İstek ilk kareden sonraya ertelenir;
        // aksi halde FocusNode henüz ağaca bağlanmadığı için odak kaybolur.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _otpFocusNodes[0].requestFocus();
        });
      }
    } catch (e) {
      if (mounted) {
        _showError(_authService.translateAuthError(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// OTP doğrula ve kayıt ol
  Future<void> _verifyOtpAndRegister() async {
    final code = _otpCode;
    if (code.length != 6) {
      _showError('Lütfen 6 haneli kodu girin');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // 1. OTP'yi doğrula
      debugPrint('🔐 REGISTER: OTP doğrulanıyor...');
      final verifyResult = await _verificationService.verifyRegistrationOtp(
        email: _verifiedEmail!,
        code: code,
      );

      if (!verifyResult['success']) {
        if (mounted) {
          _showError(verifyResult['message'] ?? 'Geçersiz doğrulama kodu');
        }
        return;
      }

      debugPrint('✅ REGISTER: OTP doğrulandı, kayıt yapılıyor...');

      // 2. Supabase kaydı yap
      final email = _emailController.text.trim();
      final password = _passwordController.text;
      final username = _usernameController.text.trim().toLowerCase();
      final fullName = _fullNameController.text.trim();

      final authResponse = await Supabase.instance.client.auth.signUp(
        email: email,
        password: password,
        data: {
          'username': username,
          'full_name': fullName,
          'email_verified': true, // OTP ile doğrulandı
        },
      );

      debugPrint(
        '📋 REGISTER: signUp response - user: ${authResponse.user?.id}, session: ${authResponse.session != null}',
      );

      if (authResponse.user == null) {
        throw Exception('Kayıt oluşturulamadı');
      }

      // 3. Session yoksa otomatik giriş yap
      if (authResponse.session == null) {
        debugPrint('🔑 REGISTER: Session yok, otomatik giriş yapılıyor...');
        await Supabase.instance.client.auth.signInWithPassword(
          email: email,
          password: password,
        );
        debugPrint('✅ REGISTER: Otomatik giriş başarılı');
      }

      // Profil SQL trigger tarafından otomatik oluşturulur (handle_new_user fonksiyonu)
      // Fallback: Trigger çalışmazsa profili güvenli varsayılanlarla oluştur.
      // Not: profiles INSERT grant'i REVOKE edildi. Doğrudan INSERT yerine
      // SECURITY DEFINER ensure_my_profile() RPC'si çağrılır; rol/is_admin
      // her zaman güvenli varsayılanlar (customer/false) olur.
      try {
        final userId = authResponse.user!.id;
        await Future.delayed(const Duration(seconds: 1));
        // RPC idempotent: mevcutsa dokunmaz.
        await Supabase.instance.client.rpc('ensure_my_profile');
        // Username/full_name gibi public alanlar update_my_public_profile
        // ile yazılabilir; ancak register akışında username/full_name
        // auth metadata'dan zaten trigger tarafından alınır, bu nedenle
        // ek bir UPDATE yapmıyoruz.
        debugPrint('✅ REGISTER: Profil hazır (id=$userId)');
      } catch (profileError) {
        debugPrint(
          '⚠️ REGISTER: Profil oluşturma hatası (kayıt başarılı): $profileError',
        );
      }

      if (mounted) {
        _timer?.cancel();
        _resendTimer?.cancel();
        _showSuccessDialog();
      }
    } on AuthException catch (e) {
      debugPrint('❌ REGISTER: AuthException - ${e.message}');
      if (mounted) {
        _showError(_authService.translateAuthError(e.message));
      }
    } catch (e) {
      debugPrint('❌ REGISTER: Exception - $e');
      if (mounted) {
        _showError(_authService.translateAuthError(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// OTP yeniden gönder
  Future<void> _resendOtp() async {
    if (_resendCooldown > 0) return;

    setState(() => _isLoading = true);

    try {
      // Önceki timer'ları iptal et
      _timer?.cancel();
      _resendTimer?.cancel();

      final result = await _verificationService.sendRegistrationOtp(
        email: _verifiedEmail!,
      );

      if (mounted) {
        setState(() {
          _remainingSeconds = result['expires_in_seconds'] ?? 300;
          _resendCooldown = 60;
        });

        _startTimer();
        _startResendTimer();

        // OTP alanlarını temizle
        for (var controller in _otpControllers) {
          controller.clear();
        }
        _otpFocusNodes[0].requestFocus();

        _showSuccess('Yeni doğrulama kodu gönderildi');
      }
    } catch (e) {
      if (mounted) {
        _showError(_authService.translateAuthError(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Süre sayacını başlat
  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_remainingSeconds > 0) {
        setState(() => _remainingSeconds--);
      } else {
        timer.cancel();
      }
    });
  }

  /// Yeniden gönderme cooldown sayacını başlat
  void _startResendTimer() {
    _resendTimer?.cancel();
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_resendCooldown > 0) {
        setState(() => _resendCooldown--);
      } else {
        timer.cancel();
      }
    });
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        final p = AuthPalette.of(ctx);
        return AlertDialog(
          backgroundColor: p.sheet,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: p.success.withValues(alpha: 0.14),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.check_rounded, size: 40, color: p.success),
              ),
              const SizedBox(height: 20),
              Text(
                'Kayıt tamamlandı',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: p.text,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'CizreApp\'e hoş geldin!',
                style: TextStyle(color: p.textSoft),
              ),
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: AuthPrimaryButton(
                label: 'Başla',
                onPressed: () {
                  // Navigator diyalogun bağlamından alınır: doğrulama
                  // sonrası oturum açılınca kök widget bu ekranı değiştirmiş
                  // olabilir; dispose olmuş State'in `context`'i "Null check
                  // operator used on a null value" ile patlıyordu.
                  final navigator = Navigator.of(ctx);
                  navigator.pop();
                  navigator.pushReplacementNamed('/main');
                },
              ),
            ),
          ],
        );
      },
    );
  }

  void _showKvkkDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        // Yasal metinlerin gövde renkleri sabit koyu lacivert; yüzey de açık
        // sabitlenmezse koyu temada okunmaz hale gelirler.
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(
              Icons.privacy_tip_outlined,
              color: Color(0xFF3498DB),
              size: 26,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Kişisel Verilerin Korunması',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2C3E50),
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Giriş
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F4F8),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '6698 sayılı Kişisel Verilerin Korunması Kanunu (KVKK) kapsamında, kişisel verilerinizin işlenmesi hakkında sizi bilgilendirmek isteriz.',
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.5,
                    color: Color(0xFF2C3E50),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // 1. Veri Sorumlusu
              _buildKvkkSection(
                '1. Veri Sorumlusu',
                'CizreApp platformunun sahibi olarak veri sorumlusuyuz. Kişisel verilerinizin işlenmesi süreçlerinden sorumludur.',
                Icons.business_outlined,
              ),
              const SizedBox(height: 16),

              // 2. İşlenen Kişisel Veriler
              _buildKvkkSection(
                '2. İşlenen Kişisel Veriler',
                '• Kimlik Bilgileri: Ad, soyad, kullanıcı adı, profil fotoğrafı\n'
                    '• İletişim Bilgileri: E-posta adresi, telefon numarası (opsiyonel)\n'
                    '• Konum Bilgileri: Adres bilgileri (sipariş teslimatı için)\n'
                    '• İşlem Güvenliği Bilgileri: IP adresi, cihaz bilgileri, giriş kayıtları\n'
                    '• Kullanım Verileri: Platform kullanım geçmişi, tercihler, sepet bilgileri\n'
                    '• Finansal Bilgiler: Ödeme yöntemi tercihleri (kredi kartı bilgileri depolanmaz)',
                Icons.folder_outlined,
              ),
              const SizedBox(height: 16),

              // 3. Verilerin İşlenme Amaçları
              _buildKvkkSection(
                '3. Verilerin İşlenme Amaçları',
                '• Platform üyeliğinizin oluşturulması ve yönetilmesi\n'
                    '• Alışveriş ve sipariş işlemlerinin gerçekleştirilmesi\n'
                    '• Ödeme ve teslimat süreçlerinin yürütülmesi\n'
                    '• Müşteri hizmetleri ve destek sağlanması\n'
                    '• Platformun güvenliğinin sağlanması ve dolandırıcılık tespiti\n'
                    '• Yasal yükümlülüklerin yerine getirilmesi\n'
                    '• Kullanıcı deneyiminin iyileştirilmesi (anonim analizler)',
                Icons.settings_outlined,
              ),
              const SizedBox(height: 16),

              // 4. Verilerin Aktarımı
              _buildKvkkSection(
                '4. Kişisel Verilerin Aktarılması',
                'Verileriniz aşağıdaki durumlarda üçüncü taraflarla paylaşılabilir:\n\n'
                    '• Satıcılar: Siparişlerinizin hazırlanması ve teslimatı için\n'
                    '• Ödeme Kuruluşları: Güvenli ödeme işlemleri için\n'
                    '• Kargo/Kurye Şirketleri: Teslimat için gerekli adres bilgileri\n'
                    '• Bulut Hizmet Sağlayıcıları: Veri depolama ve altyapı hizmetleri için\n'
                    '• Yasal Merciler: Kanuni yükümlülükler çerçevesinde\n\n'
                    'Tüm veri aktarımları KVKK ve ilgili mevzuata uygun olarak gerçekleştirilir.',
                Icons.share_outlined,
              ),
              const SizedBox(height: 16),

              // 5. Veri Toplama Yöntemleri
              _buildKvkkSection(
                '5. Verilerin Toplanma Yöntemi',
                'Kişisel verileriniz otomatik ve otomatik olmayan yöntemlerle toplanır:\n\n'
                    '• Kayıt formları ve profil ayarlarınız\n'
                    '• Platform kullanımınız sırasında otomatik toplanan veriler\n'
                    '• Sipariş ve ödeme işlemleri\n'
                    '• Müşteri hizmetleri ile iletişimleriniz\n'
                    '• Çerezler (cookies) ve benzer teknolojiler',
                Icons.file_download_outlined,
              ),
              const SizedBox(height: 16),

              // 6. Saklama Süresi
              _buildKvkkSection(
                '6. Verilerin Saklanma Süresi',
                'Kişisel verileriniz, işleme amacının gerektirdiği süre boyunca ve yasal saklama yükümlülükleri çerçevesinde saklanır:\n\n'
                    '• Hesap Bilgileri: Hesabınız aktif olduğu süre boyunca\n'
                    '• İşlem Kayıtları: Vergi ve ticari mevzuat gereği 10 yıl\n'
                    '• İletişim Kayıtları: Hizmet kalitesi için 3 yıl\n'
                    '• Log Kayıtları: Güvenlik amacıyla 2 yıl\n\n'
                    'Hesap silme talebiniz durumunda, yasal yükümlülükler hariç tüm verileriniz kalıcı olarak silinir.',
                Icons.schedule_outlined,
              ),
              const SizedBox(height: 16),

              // 7. Haklarınız
              _buildKvkkSection(
                '7. KVKK Kapsamındaki Haklarınız',
                'KVKK\'nın 11. maddesi uyarınca aşağıdaki haklara sahipsiniz:\n\n'
                    '✓ Kişisel verilerinizin işlenip işlenmediğini öğrenme\n'
                    '✓ İşlenen verileriniz hakkında bilgi talep etme\n'
                    '✓ Verilerin işlenme amacını ve amaca uygun kullanılıp kullanılmadığını öğrenme\n'
                    '✓ Yurt içinde veya yurt dışında aktarıldığı üçüncü kişileri bilme\n'
                    '✓ Eksik veya yanlış işlenmiş verilerin düzeltilmesini isteme\n'
                    '✓ Verilerin silinmesini veya yok edilmesini talep etme\n'
                    '✓ Düzeltme/silme/yok etme işlemlerinin aktarıldığı taraflara bildirilmesini isteme\n'
                    '✓ Münhasıran otomatik sistemlerle analiz edilmesi nedeniyle aleyhinize bir sonuç doğmasına itiraz etme\n'
                    '✓ Kanuna aykırı veri işleme nedeniyle zararınızın giderilmesini talep etme',
                Icons.verified_user_outlined,
              ),
              const SizedBox(height: 16),

              // 8. Başvuru Yöntemi
              _buildKvkkSection(
                '8. Haklarınızı Kullanma ve İletişim',
                'KVKK kapsamındaki haklarınızı kullanmak için:\n\n'
                    '📧 E-posta: destek@cizreapp.com\n'
                    '📱 Uygulama: Hesap Ayarları > Destek Merkezi\n\n'
                    'Başvurularınız en geç 30 gün içinde değerlendirilir ve size bilgi verilir. Başvurunuzda kimlik teyidi için gerekli bilgileri (T.C. kimlik numarası, ad-soyad) belirtiniz.\n\n'
                    'Kişisel Verileri Koruma Kurulu\'na şikayette bulunma hakkınız saklıdır.',
                Icons.contact_support_outlined,
              ),
              const SizedBox(height: 20),

              // Güncelleme Tarihi
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFF8F9FA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE0E0E0)),
                ),
                child: Row(
                  children: const [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: Color(0xFF7F8C8D),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Son Güncelleme: Mart 2026\nBu metin güncellenebilir, değişiklikler uygulama üzerinden duyurulur.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF7F8C8D),
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(ctx).pop(),
            icon: const Icon(Icons.check_circle_outline, size: 20),
            label: const Text(
              'Anladım',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF3498DB),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  // KVKK bölüm widget'ı
  Widget _buildKvkkSection(String title, String content, IconData icon) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 20, color: const Color(0xFF3498DB)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2C3E50),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          content,
          style: const TextStyle(
            fontSize: 12.5,
            height: 1.6,
            color: Color(0xFF34495E),
          ),
        ),
      ],
    );
  }

  void _showSuccess(String message) => showAuthSuccess(context, message);

  Future<void> _openPrivacyPolicy() async {
    final opened = await launchUrl(
      Uri.parse(_privacyPolicyUrl),
      mode: kIsWeb
          ? LaunchMode.platformDefault
          : LaunchMode.externalApplication,
    );
    if (!opened && mounted) {
      _showError('Gizlilik Politikası açılamadı: $_privacyPolicyUrl');
    }
  }

  /// Kullanım Koşulları ve Gizlilik Politikası Dialog - Apple Guideline 1.2
  void _showTermsDialog() async {
    // Kayıt yüzeyi kısa özeti. Uygulama içi tam metin ayrıca
    // app_about_settings üzerinden admin tarafından yönetilir.
    String termsContent =
        '''
CizreApp Kullanım Koşulları

Son Güncelleme: 30 Temmuz 2026

1. Kabul
CizreApp uygulamasını kullanarak bu kullanım koşullarını kabul etmiş sayılırsınız.

2. Hizmet Açıklaması
CizreApp, Cizre bölgesinde faaliyet gösteren bir sosyal medya ve pazar yeri platformudur. Platform üzerinden:
- Mağaza ve ürün satışı
- Gönderi paylaşımı ve sosyal etkileşim
- Grup sohbeti ve mesajlaşma
- Hikaye ve canlı yayın özellikleri
sunulmaktadır.

3. Kullanıcı Yükümlülükleri
- 18 yaşından büyük olmalısınız
- Geçerli bir e-posta adresi kullanmalısınız
- Hesabınızı başkalarıyla paylaşmamalısınız
- Yasa dışı veya zararlı içerik paylaşmamalısınız

4. İçerik Kuralları
Aşağıdaki içerikler yasaktır:
- Uygunsuz veya taciz içerikli paylaşımlar
- Spam ve reklam içeriği
- Yanlış bilgi ve aldatıcı içerik
- Şiddet içeren paylaşımlar
- Telif hakkı ihlali

5. Hesap Güvenliği
- Şifrenizi güvenli tutun
- Hesabınızdaki tüm aktivitelerden siz sorumlusunuz
- Yetkisiz erişimi derhal bildirin

6. Platform Hakları
CizreApp, aşağıdaki durumlarda hesabınızı askıya alabilir veya kapatabilir:
- Kullanım koşullarının ihlali
- Yasadışı içerik tespiti
- Dolandırıcılık faaliyetleri
- Diğer kullanıcılardan gelen şikayetler

7. Sorumluluk Sınırlaması
CizreApp, platform üzerindeki kullanıcı etkileşimlerinden sorumlu değildir. Kullanıcılar arasındaki anlaşmazlıklarda platform arabuluculuk yapabilir.

8. Gizlilik
Kişisel verilerinizin nasıl toplandığı ve kullanıldığı hakkında detaylı bilgi için Gizlilik Politikamızı inceleyebilirsiniz:
$_privacyPolicyUrl

9. İsteğe Bağlı Ödüllü Reklam ve Puan
- Ödüllü AdMob reklamı izlemek zorunlu değildir; izlememek yalnız puan kazanılmaması sonucunu doğurur.
- Mobil reklam callback'i tek başına puan vermez; Google SSV sunucu doğrulaması başarısızsa puan oluşturulmaz.
- Puan nakit veya çekilebilir bakiye değildir; IBAN'a çekilemez, transfer edilemez ve fiziksel ürünlerde kullanılamaz.
- Yalnız sunucunun uygun gördüğü dijital üründe önce puan, sonra kalan TL bakiyesi kullanılır. İade puanı puana, TL'yi TL bakiyesine döndürür.
- Geçmişte TL bakiyeye işlenmiş reklam ödülleri puana kopyalanmaz ve yeni puan doğurmaz.

10. Değişiklikler
Bu kullanım koşulları güncellenebilir. Önemli değişiklikler uygulama üzerinden duyurulacaktır.

11. İletişim
Sorularınız için support@cizreapp.com adresinden bize ulaşabilirsiniz.
''';

    String privacyContent =
        '''
CizreApp Gizlilik Politikası

Son Güncelleme: 30 Temmuz 2026

1. Veri Sorumlusu
CizreApp platformunun işletmecisi veri sorumlusudur.

2. Toplanan Veriler
- Kimlik bilgileri (ad, soyad, kullanıcı adı)
- İletişim bilgileri (e-posta)
- Profil bilgileri (fotoğraf, bio)
- Konum bilgileri (adres, konum)
- Kullanım verileri (aktiviteler, tercihler)
- İşlem güvenliği (IP, cihaz bilgileri)
- İsteğe bağlı AdMob/SSV doğrulama metadata'sı. İşlem ve varsa sağlayıcı kullanıcı kimliği HMAC takma değeridir; custom data ham olarak saklanmaz. Ödül kayıtlarında ham IP/cihaz kimliği kolonu yoktur.

3. Veri Kullanım Amaçları
- Hizmet sunumu
- Hesap güvenliği
- Ödül doğrulama, sahtecilik ve tekrar kredi önleme, limit/bütçe uygulama
- Yasal yükümlülükler
- Platform iyileştirmesi

4. Veri Paylaşımı
Ödüllü reklamı seçerseniz Google AdMob reklamı sunar ve verileri kendi politikası kapsamında işler. Diğer aktarımlar hizmet sunumu, açık rıza veya yasal gerekliliklerle sınırlıdır.

5. Veri Saklama
Veriler amaç ve uygulanabilir yükümlülükler için gereken süreyle saklanır. Ödül doğrulamasındaki belirli sağlayıcı-kullanıcı/cihaz/ağ takma değerleri için başlangıç teknik saklama ayarı 30 gündür; işlem HMAC'ı ve ledger/audit kayıtları idempotency, güvenlik ve uyuşmazlık amaçlarıyla daha uzun tutulabilir.

6. Haklarınız
KVKK kapsamında aşağıdaki haklara sahipsiniz:
- Veri erişim hakkı
- Veri düzeltme hakkı
- Veri silme hakkı
- Veri işlemeye itiraz hakkı

7. İletişim
Gizlilik ile ilgili sorularınız için: privacy@cizreapp.com

Tam ve güncel metin: $_privacyPolicyUrl
''';

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        // Yasal metinlerin gövde renkleri sabit koyu lacivert; yüzey de açık
        // sabitlenmezse koyu temada okunmaz hale gelirler.
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(
              Icons.description_outlined,
              color: Color(0xFF3498DB),
              size: 26,
            ),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Kullanım Koşulları ve Gizlilik Politikası',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF2C3E50),
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Kullanım Koşulları
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F4FC),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '📋 Kullanım Koşulları',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      termsContent,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        color: Color(0xFF34495E),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Gizlilik Politikası
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F8F0),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '🔒 Gizlilik Politikası',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: Color(0xFF2C3E50),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      privacyContent,
                      style: const TextStyle(
                        fontSize: 11,
                        height: 1.5,
                        color: Color(0xFF34495E),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3E0),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: Color(0xFFE65100),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Kayıt olarak bu koşulları kabul etmiş sayılırsınız.',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFFE65100),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: _openPrivacyPolicy,
            icon: const Icon(Icons.open_in_new, size: 18),
            label: const Text('Güncel Gizlilik Politikası'),
          ),
          TextButton.icon(
            onPressed: () {
              Navigator.of(ctx).pop();
              setState(() => _termsAccepted = true);
            },
            icon: const Icon(Icons.check_circle_outline, size: 20),
            label: const Text(
              'Kabul Ediyorum',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF27AE60),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('İptal'),
          ),
        ],
      ),
    );
  }

  void _showError(String message) => showAuthError(context, message);

  // ===========================================================================
  // Adım geçişleri
  // ===========================================================================

  /// Birinci adımı doğrulayıp ikinci adıma geçer.
  void _goToSecurityStep() {
    if (!(_stepOneFormKey.currentState?.validate() ?? false)) return;
    FocusScope.of(context).unfocus();
    setState(() => _step = 1);
  }

  /// Bandın sol üstündeki geri oku.
  void _goBackStep() {
    if (_step == 2) {
      _resetOtpState();
      setState(() => _step = 1);
      return;
    }
    setState(() => _step = 0);
  }

  /// OTP adımındaki "Değiştir": e-postayı düzeltmek için ilk adıma döner.
  void _changeEmail() {
    _resetOtpState();
    setState(() => _step = 0);
  }

  /// Sayaçları durdurur ve girilmiş kodu temizler.
  void _resetOtpState() {
    _timer?.cancel();
    _resendTimer?.cancel();
    for (final controller in _otpControllers) {
      controller.clear();
    }
    _remainingSeconds = 0;
    _resendCooldown = 0;
  }

  // ===========================================================================
  // Sosyal kayıt
  // ===========================================================================

  Future<void> _handleGoogleSignUp() async {
    setState(() => _isLoading = true);
    try {
      final response = await _authService.signInWithGoogle();
      if (response.user != null && mounted) {
        await _completeSocialSignUp();
      }
    } catch (e) {
      if (mounted) _showError(_authService.translateOAuthError(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleAppleSignUp() async {
    setState(() => _isLoading = true);
    try {
      final response = await _authService.signInWithApple();
      if (response.user != null && mounted) {
        await _completeSocialSignUp();
      }
    } catch (e) {
      if (mounted) _showError(_authService.translateOAuthError(e.toString()));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Google/Apple ile kayıttan sonra ortak devam noktası. `handle_new_user`
  /// tetikleyicisi bu hesaba (OAuth username göndermediği için) geçici bir
  /// misafir_ adı verdiyse, ana ekrana geçmeden önce kullanıcıdan gerçek
  /// kullanıcı adını istiyoruz; kayıt ancak o adım tamamlanınca biter.
  Future<void> _completeSocialSignUp() async {
    final needsUsername = await needsUsernameSetup();
    if (!mounted) return;
    if (needsUsername) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const ChooseUsernameScreen()));
    } else {
      Navigator.of(context).pushReplacementNamed('/main');
    }
  }

  // ===========================================================================
  // Arayüz
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: switch (_step) {
        0 => 'Hesap oluştur',
        1 => 'Şifreni belirle',
        _ => 'E-postanı doğrula',
      },
      subtitle: switch (_step) {
        0 => 'Adım 1 / 3 — Bilgilerin',
        1 => 'Adım 2 / 3 — Şifre ve onaylar',
        _ => 'Adım 3 / 3 — Doğrulama kodu',
      },
      stepIndex: _step + 1,
      stepCount: 3,
      onBack: _step == 0 ? null : _goBackStep,
      footer: _step == 0
          ? AuthFooterLink(
              question: 'Zaten hesabın var mı?',
              action: 'Giriş yap',
              onPressed: () =>
                  Navigator.of(context).pushReplacementNamed('/login'),
            )
          : null,
      child: switch (_step) {
        0 => _buildIdentityStep(),
        1 => _buildSecurityStep(),
        _ => _buildOtpStep(),
      },
    );
  }

  /// Adım 1 — kullanıcı adı, ad soyad, e-posta.
  Widget _buildIdentityStep() {
    final p = AuthPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuthSocialButton(
          label: 'Google ile kayıt ol',
          icon: Icons.g_mobiledata_rounded,
          iconColor: const Color(0xFFEA4335),
          onPressed: _isLoading ? null : _handleGoogleSignUp,
        ),
        if (authAppleSignInAvailable) ...[
          const SizedBox(height: 10),
          AuthSocialButton(
            label: 'Apple ile kayıt ol',
            icon: Icons.apple_rounded,
            onPressed: _isLoading ? null : _handleAppleSignUp,
          ),
        ],
        const SizedBox(height: 10),
        _buildSocialConsentNote(p),
        const SizedBox(height: 16),
        const AuthDivider(label: 'veya e-posta ile'),
        const SizedBox(height: 18),
        AutofillGroup(
          child: Form(
            key: _stepOneFormKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AuthField(
                  controller: _usernameController,
                  hint: 'Kullanıcı adı',
                  icon: Icons.alternate_email,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.newUsername],
                  onSubmitted: (_) => _fullNameFocus.requestFocus(),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(
                      RegExp(r'[a-zA-Z0-9._-]'),
                    ),
                  ],
                  onChanged: (v) {
                    // Giriş anında boşluk/özel karakterleri otomatik temizle
                    final sanitized = _sanitizeUsername(v);
                    if (sanitized != v) {
                      _usernameController.value = TextEditingValue(
                        text: sanitized,
                        selection: TextSelection.collapsed(
                          offset: sanitized.length,
                        ),
                      );
                    }
                    setState(() {});
                    _checkUsername(sanitized);
                  },
                  suffix: _buildUsernameSuffix(p),
                  helper: 'Sadece harf, rakam, nokta, _ ve - (3-20 karakter).',
                  validator: (v) {
                    if (v?.isEmpty ?? true) return 'Kullanıcı adı gerekli';
                    if (!_usernameAllowedChars.hasMatch(v!)) {
                      return 'Sadece harf, rakam, nokta, _ ve - kullan';
                    }
                    if (v.length < 3) return 'En az 3 karakter';
                    if (v.length > 20) return 'En fazla 20 karakter';
                    if (!_isUsernameAvailable) return 'Bu ad kullanımda';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                AuthField(
                  controller: _fullNameController,
                  focusNode: _fullNameFocus,
                  hint: 'Ad soyad',
                  icon: Icons.person_outline,
                  textInputAction: TextInputAction.next,
                  autofillHints: const [AutofillHints.name],
                  onSubmitted: (_) => _emailFocus.requestFocus(),
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? 'Ad soyad gerekli' : null,
                ),
                const SizedBox(height: 16),
                AuthField(
                  controller: _emailController,
                  focusNode: _emailFocus,
                  hint: 'E-posta',
                  icon: Icons.mail_outline,
                  keyboardType: TextInputType.emailAddress,
                  textInputAction: TextInputAction.done,
                  autofillHints: const [AutofillHints.email],
                  onSubmitted: (_) => _goToSecurityStep(),
                  helper: 'Bu adrese 6 haneli doğrulama kodu göndereceğiz.',
                  validator: (v) => (v?.trim().isEmpty ?? true)
                      ? 'E-posta gerekli'
                      : (v!.contains('@') ? null : 'Geçerli e-posta'),
                ),
                const SizedBox(height: 24),
                AuthPrimaryButton(
                  label: 'Devam et',
                  onPressed: _isLoading ? null : _goToSecurityStep,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Kullanıcı adı alanının sağındaki müsaitlik göstergesi.
  Widget? _buildUsernameSuffix(AuthPalette p) {
    if (_isCheckingUsername) {
      return const Padding(
        padding: EdgeInsets.all(15),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_usernameController.text.length < 3) return null;
    return Icon(
      _isUsernameAvailable ? Icons.check_circle_rounded : Icons.cancel_rounded,
      color: _isUsernameAvailable ? p.success : p.danger,
      size: 20,
    );
  }

  /// Google/Apple ile kayıtta onay kutuları gösterilmediği için, kabulün
  /// devam etmekle verildiğini belirten not.
  Widget _buildSocialConsentNote(AuthPalette p) {
    final noteStyle = TextStyle(fontSize: 11.5, color: p.textMuted);
    final linkStyle = TextButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      minimumSize: Size.zero,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      foregroundColor: p.accent,
      textStyle: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600),
    );

    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('Sosyal hesapla devam edersen', style: noteStyle),
        TextButton(
          onPressed: _showTermsDialog,
          style: linkStyle,
          child: const Text('Kullanım Koşulları'),
        ),
        Text('ve', style: noteStyle),
        TextButton(
          onPressed: _showKvkkDialog,
          style: linkStyle,
          child: const Text('KVKK Aydınlatma Metni'),
        ),
        Text('kabul edilmiş sayılır.', style: noteStyle),
      ],
    );
  }

  /// Adım 2 — şifre ve yasal onaylar.
  Widget _buildSecurityStep() {
    final p = AuthPalette.of(context);
    final allAccepted = _kvkkAccepted && _termsAccepted;

    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthField(
              controller: _passwordController,
              hint: 'Şifre',
              icon: Icons.lock_outline,
              obscure: _obscurePassword,
              onToggleObscure: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) => _confirmPasswordFocus.requestFocus(),
              validator: (v) => (v?.isEmpty ?? true)
                  ? 'Şifre gerekli'
                  : (v!.length < 6 ? 'En az 6 karakter' : null),
            ),
            AuthPasswordStrengthBar(password: _passwordController.text),
            const SizedBox(height: 14),
            AuthField(
              controller: _confirmPasswordController,
              focusNode: _confirmPasswordFocus,
              hint: 'Şifre tekrar',
              icon: Icons.lock_reset_outlined,
              obscure: _obscureConfirmPassword,
              onToggleObscure: () => setState(
                () => _obscureConfirmPassword = !_obscureConfirmPassword,
              ),
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              validator: (v) =>
                  v != _passwordController.text ? 'Şifreler eşleşmiyor' : null,
            ),
            const SizedBox(height: 20),

            // Eski tasarımdaki iki ayrı onay kartı tek kartta birleştirildi;
            // o iki kart ekranın yaklaşık yarısını kaplıyordu.
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              decoration: BoxDecoration(
                color: p.field,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: allAccepted ? p.success : p.border,
                  width: allAccepted ? 1.4 : 1,
                ),
              ),
              child: Column(
                children: [
                  AuthConsentRow(
                    value: _kvkkAccepted,
                    onChanged: (v) => setState(() => _kvkkAccepted = v),
                    linkText: 'KVKK Aydınlatma Metni',
                    restText:
                        '\'ni okudum, kişisel verilerimin işlenmesini kabul ediyorum.',
                    onLinkTap: _showKvkkDialog,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Divider(height: 1, color: p.border),
                  ),
                  AuthConsentRow(
                    value: _termsAccepted,
                    onChanged: (v) => setState(() => _termsAccepted = v),
                    linkText: 'Kullanım Koşulları ve Gizlilik Politikası',
                    restText: '\'nı okudum, anladım ve kabul ediyorum.',
                    onLinkTap: _showTermsDialog,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            AuthPrimaryButton(
              label: 'Doğrulama kodu gönder',
              isLoading: _isLoading,
              onPressed: (_isLoading || !allAccepted) ? null : _sendOtp,
            ),
            if (!allAccepted) ...[
              const SizedBox(height: 10),
              Text(
                'Devam etmek için her iki onayı da işaretle.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, color: p.textMuted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Adım 3 — e-posta doğrulama kodu.
  Widget _buildOtpStep() {
    final p = AuthPalette.of(context);
    final expired = _remainingSeconds <= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 4, 6, 4),
          decoration: BoxDecoration(
            color: p.field,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              Icon(Icons.mail_outline, color: p.accent, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _verifiedEmail ?? '',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: p.text,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              TextButton(
                onPressed: _isLoading ? null : _changeEmail,
                style: TextButton.styleFrom(foregroundColor: p.accent),
                child: const Text(
                  'Değiştir',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 26),
        Text(
          '6 haneli kodu gir',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: p.textSoft),
        ),
        const SizedBox(height: 14),
        AuthOtpInput(
          controllers: _otpControllers,
          focusNodes: _otpFocusNodes,
          onChanged: () => setState(() {}),
        ),
        const SizedBox(height: 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.schedule_rounded,
              size: 15,
              color: expired ? p.danger : p.textMuted,
            ),
            const SizedBox(width: 6),
            Text(
              expired
                  ? 'Kodun süresi doldu'
                  : 'Kod ${_formatTime(_remainingSeconds)} içinde geçersiz olacak',
              style: TextStyle(
                fontSize: 12.5,
                color: expired ? p.danger : p.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        AuthPrimaryButton(
          label: 'Doğrula ve kayıt ol',
          isLoading: _isLoading,
          onPressed: (_isLoading || _otpCode.length != 6 || expired)
              ? null
              : _verifyOtpAndRegister,
        ),
        const SizedBox(height: 6),
        TextButton(
          onPressed: (_resendCooldown > 0 || _isLoading) ? null : _resendOtp,
          style: TextButton.styleFrom(
            foregroundColor: p.accent,
            disabledForegroundColor: p.textMuted,
          ),
          child: Text(
            _resendCooldown > 0
                ? 'Kodu yeniden gönder ($_resendCooldown sn)'
                : 'Kodu yeniden gönder',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
        ),
      ],
    );
  }

  /// Süreyi formatla (MM:SS)
  String _formatTime(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }
}
