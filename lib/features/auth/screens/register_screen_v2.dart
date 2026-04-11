// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../../../core/services/verification_service.dart';

class RegisterScreenV2 extends StatefulWidget {
  const RegisterScreenV2({super.key});

  @override
  State<RegisterScreenV2> createState() => _RegisterScreenV2State();
}

class _RegisterScreenV2State extends State<RegisterScreenV2> {
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
  final List<FocusNode> _otpFocusNodes = List.generate(
    6,
    (_) => FocusNode(),
  );
  
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  bool _isCheckingUsername = false;
  bool _isUsernameAvailable = true;
  bool _kvkkAccepted = false;
  String? _selectedGender;
  
  // OTP state
  bool _otpSent = false;
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

  Future<void> _checkUsername(String username) async {
    if (username.length < 3) return;
    setState(() => _isCheckingUsername = true);
    
    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('username')
          .eq('username', username.toLowerCase())
          .maybeSingle();
      
      if (mounted) setState(() { _isUsernameAvailable = response == null; _isCheckingUsername = false; });
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
          _otpSent = true;
          _remainingSeconds = result['expires_in_seconds'] ?? 300;
          _resendCooldown = 60; // 60 saniye yeniden gönderme cooldown
          _verifiedEmail = _emailController.text.trim();
        });
        
        _startTimer();
        _startResendTimer();
        
        _showSuccess(result['message'] ?? 'Doğrulama kodu e-posta adresinize gönderildi');
        
        // İlk OTP kutusuna odaklan
        _otpFocusNodes[0].requestFocus();
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
          if (_selectedGender != null) 'gender': _selectedGender,
        },
      );

      debugPrint('📋 REGISTER: signUp response - user: ${authResponse.user?.id}, session: ${authResponse.session != null}');

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
      // Fallback: Trigger çalışmazsa profili manuel oluştur
      try {
        final userId = authResponse.user!.id;
        await Future.delayed(const Duration(seconds: 1));
        final existingProfile = await Supabase.instance.client
            .from('profiles')
            .select('id')
            .eq('id', userId)
            .maybeSingle();
        
        if (existingProfile == null) {
          debugPrint('⚠️ REGISTER: Trigger çalışmadı, profil manuel oluşturuluyor...');
          await Supabase.instance.client.from('profiles').upsert({
            'id': userId,
            'email': email,
            'username': username,
            'full_name': fullName,
            if (_selectedGender != null) 'gender': _selectedGender,
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          }, onConflict: 'id');
          debugPrint('✅ REGISTER: Profil manuel olarak oluşturuldu');
        } else {
          debugPrint('✅ REGISTER: Profil trigger ile oluşturulmuş');
        }
      } catch (profileError) {
        debugPrint('⚠️ REGISTER: Profil oluşturma hatası (kayıt başarılı): $profileError');
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

  /// OTP giriş değişikliği
  void _onOtpChanged(int index, String value) {
    if (value.isNotEmpty && index < 5) {
      // Sonraki kutuya geç
      _otpFocusNodes[index + 1].requestFocus();
    }
    
    // Tüm kutular doluysa otomatik doğrula
    if (_otpCode.length == 6) {
      // Klavyeyi kapat
      FocusScope.of(context).unfocus();
    }
  }

  /// OTP geri silme
  void _onOtpKeyPressed(int index, RawKeyEvent event) {
    if (event is RawKeyDownEvent && 
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _otpControllers[index].text.isEmpty &&
        index > 0) {
      // Önceki kutuya geç
      _otpFocusNodes[index - 1].requestFocus();
    }
  }

  void _showSuccessDialog() {
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
            const Text('Kayıt Başarılı!', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF2C3E50))),
            const SizedBox(height: 8),
            const Text('Hoş geldiniz!', style: TextStyle(color: Color(0xFF7F8C8D))),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                Navigator.of(context).pushReplacementNamed('/main');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1ABC9C),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('Başla', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  void _showKvkkDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: const [
            Icon(Icons.privacy_tip_outlined, color: Color(0xFF3498DB), size: 26),
            SizedBox(width: 10),
            Expanded(
              child: Text(
                'Kişisel Verilerin Korunması',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF2C3E50)),
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
                  style: TextStyle(fontSize: 13, height: 1.5, color: Color(0xFF2C3E50), fontWeight: FontWeight.w500),
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
                    Icon(Icons.info_outline, size: 18, color: Color(0xFF7F8C8D)),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Son Güncelleme: Mart 2026\nBu metin güncellenebilir, değişiklikler uygulama üzerinden duyurulur.',
                        style: TextStyle(fontSize: 11, color: Color(0xFF7F8C8D), height: 1.4),
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
            label: const Text('Anladım', style: TextStyle(fontWeight: FontWeight.w600)),
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

  void _showSuccess(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFF27AE60),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: const Color(0xFFE74C3C),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              children: [
                const SizedBox(height: 60),
                
                const Text(
                  'Kayıt Ol',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Color(0xFF2C3E50)),
                ),
                const SizedBox(height: 8),
                Text(
                  _otpSent 
                      ? 'E-postanıza kod gönderildi'
                      : 'CizreApp\'e hoşgeldiniz',
                  style: const TextStyle(fontSize: 14, color: Color(0xFF95A5A6)),
                ),
                const SizedBox(height: 32),

                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(0, 4))],
                  ),
                  child: _otpSent ? _buildOtpSection() : _buildRegisterForm(),
                ),
                const SizedBox(height: 24),

                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Zaten hesabınız var mı? ', style: TextStyle(color: Color(0xFF95A5A6))),
                    TextButton(
                      onPressed: () => Navigator.of(context).pushReplacementNamed('/login'),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: const Color(0xFF2C3E50)),
                      child: const Text('Giriş Yap', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Kayıt formu
  Widget _buildRegisterForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          _buildField(
            controller: _usernameController,
            hint: 'Kullanıcı adı',
            icon: Icons.alternate_email,
            onChanged: (v) => _checkUsername(v),
            suffixIcon: _isCheckingUsername
                ? const SizedBox(width: 20, height: 20, child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator(strokeWidth: 2)))
                : _usernameController.text.length >= 3
                    ? Icon(_isUsernameAvailable ? Icons.check_circle : Icons.cancel, color: _isUsernameAvailable ? const Color(0xFF27AE60) : const Color(0xFFE74C3C), size: 20)
                    : null,
            validator: (v) => (v?.isEmpty ?? true) ? 'Kullanıcı adı gerekli' : (v!.length < 3 ? 'En az 3 karakter' : (!_isUsernameAvailable ? 'Bu ad kullanımda' : null)),
          ),
          const SizedBox(height: 6),
          // Kullanıcı adı uyarısı
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.orange.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'Kullanıcı adınız sonradan değiştirilemez',
                    style: TextStyle(fontSize: 12, color: Colors.orange.shade700, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildField(
            controller: _fullNameController,
            hint: 'Ad Soyad',
            icon: Icons.person_outline,
            validator: (v) => (v?.isEmpty ?? true) ? 'Ad soyad gerekli' : null,
          ),
          const SizedBox(height: 14),

          // Cinsiyet seçimi
          _buildGenderSelector(),
          const SizedBox(height: 14),

          _buildField(
            controller: _emailController,
            hint: 'E-posta',
            icon: Icons.mail_outline,
            keyboardType: TextInputType.emailAddress,
            validator: (v) => (v?.isEmpty ?? true) ? 'E-posta gerekli' : (v!.contains('@') ? null : 'Geçerli e-posta'),
          ),
          const SizedBox(height: 6),
          // Email doğrulama uyarısı
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Colors.blue.shade700),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    'E-posta adresinize doğrulama kodu gönderilecektir',
                    style: TextStyle(fontSize: 12, color: Colors.blue.shade700, height: 1.3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          _buildField(
            controller: _passwordController,
            hint: 'Şifre',
            icon: Icons.lock_outline,
            obscure: _obscurePassword,
            onTap: () => setState(() => _obscurePassword = !_obscurePassword),
            validator: (v) => (v?.isEmpty ?? true) ? 'Şifre gerekli' : (v!.length < 6 ? 'En az 6 karakter' : null),
          ),
          const SizedBox(height: 14),
          _buildField(
            controller: _confirmPasswordController,
            hint: 'Şifre tekrar',
            icon: Icons.lock_outline,
            obscure: _obscureConfirmPassword,
            onTap: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
            validator: (v) => v != _passwordController.text ? 'Şifreler eşleşmiyor' : null,
          ),
          const SizedBox(height: 16),

          // KVKK Onay Kutucuğu - Modern Tasarım
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _kvkkAccepted ? const Color(0xFFE8F8F0) : const Color(0xFFF8F9FA),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: _kvkkAccepted ? const Color(0xFF27AE60) : const Color(0xFFE0E0E0),
                width: 1.2,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 22,
                      height: 22,
                      child: Checkbox(
                        value: _kvkkAccepted,
                        onChanged: (v) => setState(() => _kvkkAccepted = v ?? false),
                        activeColor: const Color(0xFF27AE60),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => _showKvkkDialog(),
                        child: RichText(
                          text: const TextSpan(
                            style: TextStyle(fontSize: 13, color: Color(0xFF34495E), height: 1.4),
                            children: [
                              TextSpan(
                                text: 'Aydınlatma Metnini ',
                                style: TextStyle(color: Color(0xFF3498DB), fontWeight: FontWeight.w700, decoration: TextDecoration.underline),
                              ),
                              TextSpan(text: 'okudum ve kişisel verilerimin KVKK kapsamında işlenmesini kabul ediyorum.'),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_kvkkAccepted) ...[
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.only(left: 32),
                    child: Row(
                      children: const [
                        Icon(Icons.check_circle, size: 14, color: Color(0xFF27AE60)),
                        SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'KVKK aydınlatma metnini okudunuz ve kabul ettiniz',
                            style: TextStyle(fontSize: 11, color: Color(0xFF27AE60), fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 20),

          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: (_isLoading || !_kvkkAccepted) ? null : _sendOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF3498DB),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Doğrulama Kodu Gönder', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
            ),
          ),
        ],
      ),
    );
  }

  /// OTP giriş bölümü
  Widget _buildOtpSection() {
    return Column(
      children: [
        // Email göster
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F9FA),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              const Icon(Icons.mail_outline, color: Color(0xFF3498DB), size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  _verifiedEmail ?? '',
                  style: const TextStyle(fontSize: 14, color: Color(0xFF2C3E50), fontWeight: FontWeight.w500),
                ),
              ),
              TextButton(
                onPressed: () {
                  setState(() {
                    _otpSent = false;
                    _timer?.cancel();
                    _resendTimer?.cancel();
                    for (var c in _otpControllers) {
                      c.clear();
                    }
                  });
                },
                child: const Text('Değiştir', style: TextStyle(color: Color(0xFF3498DB), fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        // OTP başlık
        const Text(
          'Doğrulama Kodu',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF2C3E50)),
        ),
        const SizedBox(height: 8),
        const Text(
          'E-posta adresinize 6 haneli kod gönderildi',
          style: TextStyle(fontSize: 13, color: Color(0xFF7F8C8D)),
        ),
        const SizedBox(height: 24),

        // OTP input kutuları
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(6, (index) => _buildOtpBox(index)),
        ),
        const SizedBox(height: 16),

        // Timer
        if (_remainingSeconds > 0)
          Text(
            'Kod ${_formatTime(_remainingSeconds)} içinde sona erecek',
            style: const TextStyle(fontSize: 13, color: Color(0xFF95A5A6)),
          )
        else
          const Text(
            'Kodun süresi doldu',
            style: TextStyle(fontSize: 13, color: Color(0xFFE74C3C)),
          ),
        const SizedBox(height: 24),

        // Doğrula butonu
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: (_isLoading || _otpCode.length != 6 || _remainingSeconds <= 0) ? null : _verifyOtpAndRegister,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF3498DB),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Kodu Doğrula ve Kayıt Ol', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
          ),
        ),
        const SizedBox(height: 16),

        // Yeniden gönder butonu
        TextButton(
          onPressed: (_resendCooldown > 0 || _isLoading) ? null : _resendOtp,
          child: Text(
            _resendCooldown > 0 
                ? 'Yeniden gönder (${_resendCooldown}s)' 
                : 'Kodu Yeniden Gönder',
            style: TextStyle(
              color: _resendCooldown > 0 ? const Color(0xFFBDC3C7) : const Color(0xFF3498DB),
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }

  /// OTP kutusu
  Widget _buildOtpBox(int index) {
    return Container(
      width: 45,
      height: 55,
      decoration: BoxDecoration(
        color: const Color(0xFFF8F9FA),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _otpFocusNodes[index].hasFocus 
              ? const Color(0xFF3498DB) 
              : Colors.transparent,
          width: 2,
        ),
      ),
      child: RawKeyboardListener(
        focusNode: FocusNode(),
        onKey: (event) => _onOtpKeyPressed(index, event),
        child: TextField(
          controller: _otpControllers[index],
          focusNode: _otpFocusNodes[index],
          textAlign: TextAlign.center,
          textAlignVertical: TextAlignVertical.center,
          keyboardType: TextInputType.number,
          maxLength: 1,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
          ],
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: Color(0xFF2C3E50),
          ),
          decoration: const InputDecoration(
            counterText: '',
            border: InputBorder.none,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: (value) => _onOtpChanged(index, value),
        ),
      ),
    );
  }

  /// Süreyi formatla (MM:SS)
  String _formatTime(int seconds) {
    final min = seconds ~/ 60;
    final sec = seconds % 60;
    return '${min.toString().padLeft(2, '0')}:${sec.toString().padLeft(2, '0')}';
  }

  /// Cinsiyet seçici widget
  Widget _buildGenderSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Text(
            'Cinsiyet',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: Color(0xFF2C3E50),
            ),
          ),
        ),
        Row(
          children: [
            Expanded(
              child: _buildGenderOption(
                label: 'Erkek',
                icon: Icons.male,
                value: 'male',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildGenderOption(
                label: 'Kadın',
                icon: Icons.female,
                value: 'female',
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildGenderOption(
                label: 'Diğer',
                icon: Icons.person_outline,
                value: 'other',
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Cinsiyet seçeneği
  Widget _buildGenderOption({
    required String label,
    required IconData icon,
    required String value,
  }) {
    final isSelected = _selectedGender == value;
    // Web'de icon tree-shaking sorununu önlemek için emoji kullan
    final genderEmoji = value == 'male'
        ? '♂'
        : value == 'female'
            ? '♀'
            : '○';
    return InkWell(
      onTap: () => setState(() => _selectedGender = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFFE8F4F8) : const Color(0xFFF8F9FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF3498DB) : const Color(0xFFE0E0E0),
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              genderEmoji,
              style: TextStyle(
                fontSize: 28,
                color: isSelected ? const Color(0xFF3498DB) : const Color(0xFF7F8C8D),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? const Color(0xFF3498DB) : const Color(0xFF7F8C8D),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    void Function(String)? onChanged,
    bool obscure = false,
    VoidCallback? onTap,
    Widget? suffixIcon,
    TextInputType? keyboardType,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      onChanged: onChanged,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 15, color: Color(0xFF2C3E50)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFBDC3C7)),
        prefixIcon: Icon(icon, color: const Color(0xFF3498DB), size: 20),
        suffixIcon: suffixIcon ?? (onTap != null ? IconButton(icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20, color: const Color(0xFF95A5A6)), onPressed: onTap) : null),
        filled: true,
        fillColor: const Color(0xFFF8F9FA),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE74C3C), width: 1)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE74C3C), width: 1.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF3498DB), width: 1.5)),
        errorStyle: const TextStyle(color: Color(0xFFE74C3C)),
      ),
    );
  }
}
