// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/responsive_wrapper.dart';
import '../services/auth_service.dart';

/// Şifre sıfırlama ekranı.
///
/// Supabase Auth'un yerleşik recovery OTP sistemini kullanır. Özel
/// password_reset_otps tablosu, verify_password_reset_otp RPC'si ve
/// service-role kullanan reset-password-with-otp Edge Function'ı
/// kullanımdan kaldırılmıştır. Akış:
///   1) E-posta gönderildiğinde Supabase Auth 6 haneli recovery OTP
///      üretip e-postayla gönderir.
///   2) Kullanıcı OTP'yi girer; verifyOTP(OtpType.recovery) çağrısı
///      sunucu tarafında doğrulanmış bir recovery session oluşturur.
///   3) Yeni şifre yalnız bu session geçerliyken auth.updateUser
///      üzerinden güncellenir.
///   4) Şifre güncellendikten sonra recovery session sonlandırılır ve
///      kullanıcı login ekranına yönlendirilir.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

enum _ResetStep {
  emailInput,
  otpInput,
  newPassword,
  success,
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _newPasswordController = TextEditingController();
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

  // OTP state
  _ResetStep _currentStep = _ResetStep.emailInput;
  int _resendCooldown = 0;
  Timer? _resendTimer;
  String? _verifiedEmail;

  final _authService = AuthService();

  @override
  void dispose() {
    _emailController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    for (var controller in _otpControllers) {
      controller.dispose();
    }
    for (var node in _otpFocusNodes) {
      node.dispose();
    }
    _resendTimer?.cancel();
    super.dispose();
  }

  /// OTP kodunu al
  String get _otpCode => _otpControllers.map((c) => c.text).join();

  /// Supabase'in built-in recovery OTP sistemi ile kod gönder.
  /// Kullanıcı var/yok bilgisi sızdırılmaz: her iki durumda da aynı
  /// genel mesaj gösterilir.
  /// Hem e-posta hem kullanıcı adı kabul edilir: kullanıcı adı
  /// AuthService üzerinden e-postaya çevrilir.
  Future<void> _sendOtp() async {
    if (!_formKey.currentState!.validate()) return;

    final rawIdentifier = _emailController.text.trim();

    setState(() => _isLoading = true);

    try {
      // AuthService içinde username → email dönüşümü de yapılır ve
      // koda gönderilen e-posta adresi geri döner (kullanıcı adı
      // girilmişse, ekranda göstermek için gerçek e-postayı alırız).
      // Supabase'in "Reset Password" template'i `{{ .Token }}` içeriyorsa
      // OTP kodlu mail gönderir; link istemiyorsak `{{ .ConfirmationURL }}`
      // template'ten çıkarılmalıdır.
      final sentTo = await _authService.requestPasswordReset(rawIdentifier);

      if (mounted) {
        setState(() {
          _currentStep = _ResetStep.otpInput;
          _resendCooldown = 60;
          // Eğer identifier e-posta ise onu kullan; kullanıcı adı ise
          // AuthService'in döndüğü e-postayı (sentTo) göster. Kullanıcı
          // sızıntısını önlemek için sentTo null ise identifier'ı gösterme.
          _verifiedEmail = sentTo ?? (rawIdentifier.contains('@') ? rawIdentifier : null);
        });

        _startResendTimer();

        _showSuccess(
          'Bu adres kayıtlıysa doğrulama kodu gönderildi. '
          'Lütfen e-postanızı kontrol edin.',
        );

        _otpFocusNodes[0].requestFocus();
      }
    } on AuthException catch (e) {
      // Rate limit / over_email_send_rate_limit: otomatik retry yok
      if (mounted) {
        _showError(_authService.translateAuthError(e.message));
      }
    } catch (e) {
      if (mounted) {
        // Kullanıcı var/yok bilgisi sızdırmamak için genel mesaj
        _showError(
          'İstek işlenemedi. Lütfen bir süre sonra tekrar deneyin.',
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// OTP doğrula → sunucu tarafı recovery session oluştur.
  /// Session null ise doğrulama başarısız sayılır.
  Future<void> _verifyOtp() async {
    final code = _otpCode;
    if (code.length != 6) {
      _showError('Lütfen 6 haneli kodu girin');
      return;
    }

    final email = _verifiedEmail;
    if (email == null) {
      _showError('E-posta adresi bulunamadı, lütfen baştan başlayın');
      return;
    }

    setState(() => _isLoading = true);

    try {
      final response = await Supabase.instance.client.auth.verifyOTP(
        email: email,
        token: code,
        type: OtpType.recovery,
      );

      // Session oluşmadan yeni şifre ekranına geçme
      if (response.session == null) {
        if (mounted) {
          _showError('Doğrulama başarısız. Lütfen kodu kontrol edin.');
        }
        return;
      }

      if (mounted) {
        setState(() {
          _currentStep = _ResetStep.newPassword;
          _resendTimer?.cancel();
        });

        _showSuccess('Kod doğrulandı! Yeni şifrenizi belirleyin.');
      }
    } on AuthException catch (e) {
      if (mounted) {
        _showError(_authService.translateAuthError(e.message));
      }
    } catch (e) {
      if (mounted) {
        _showError('Doğrulama başarısız. Lütfen kodu kontrol edin.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Şifreyi güncelle. Yalnız geçerli recovery session varsa çalışır.
  /// updateUser başarılı olduktan sonra recovery session sonlandırılır.
  Future<void> _updatePassword() async {
    if (!_passwordFormKey.currentState!.validate()) return;

    if (_newPasswordController.text != _confirmPasswordController.text) {
      _showError('Şifreler eşleşmiyor');
      return;
    }

    setState(() => _isLoading = true);

    try {
      // Oturumun hâlâ geçerli bir recovery session olduğunu doğrula.
      final session = Supabase.instance.client.auth.currentSession;
      if (session == null) {
        throw Exception(
          'Oturum süresi dolmuş. Lütfen kodu yeniden doğrulayın.',
        );
      }

      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _newPasswordController.text),
      );

      // Recovery session'ı sonlandır; kullanıcıyı login ekranına gönder
      await Supabase.instance.client.auth.signOut();

      if (mounted) {
        setState(() => _currentStep = _ResetStep.success);
      }
    } on AuthException catch (e) {
      if (mounted) {
        _showError(_authService.translateAuthError(e.message));
      }
    } catch (e) {
      if (mounted) {
        _showError('Şifre güncellenemedi. Lütfen tekrar deneyin.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// OTP yeniden gönder
  Future<void> _resendOtp() async {
    if (_resendCooldown > 0) return;
    final email = _verifiedEmail;
    if (email == null) return;

    setState(() => _isLoading = true);

    try {
      _resendTimer?.cancel();

      // _verifiedEmail zaten e-posta formatında (AuthService tarafından
      // username→email dönüşümü yapılmış halde). Aynı kanalı kullan.
      await _authService.requestPasswordReset(email);

      if (mounted) {
        setState(() => _resendCooldown = 60);
        _startResendTimer();

        for (var controller in _otpControllers) {
          controller.clear();
        }
        _otpFocusNodes[0].requestFocus();

        _showSuccess('Yeni doğrulama kodu gönderildi');
      }
    } on AuthException catch (e) {
      if (mounted) {
        _showError(_authService.translateAuthError(e.message));
      }
    } catch (e) {
      if (mounted) {
        _showError('Kod gönderilemedi. Lütfen bir süre sonra tekrar deneyin.');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
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
      _otpFocusNodes[index + 1].requestFocus();
    }

    if (_otpCode.length == 6) {
      FocusScope.of(context).unfocus();
    }
  }

  /// OTP geri silme
  void _onOtpKeyPressed(int index, RawKeyEvent event) {
    if (event is RawKeyDownEvent &&
        event.logicalKey == LogicalKeyboardKey.backspace &&
        _otpControllers[index].text.isEmpty &&
        index > 0) {
      _otpFocusNodes[index - 1].requestFocus();
    }
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
      backgroundColor: kIsWeb ? Colors.grey.shade100 : const Color(0xFFF8F9FA),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          onPressed: () {
            if (_currentStep == _ResetStep.otpInput) {
              setState(() {
                _currentStep = _ResetStep.emailInput;
                _resendTimer?.cancel();
                for (var c in _otpControllers) {
                  c.clear();
                }
              });
            } else {
              Navigator.of(context).pop();
            }
          },
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: Color(0xFF2C3E50), size: 20),
        ),
      ),
      body: ResponsiveWrapper(
        maxWidth: 500,
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 28),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(height: 20),

                  Text(
                    _getTitle(),
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w700, color: Color(0xFF2C3E50)),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _getSubtitle(),
                    style: const TextStyle(fontSize: 14, color: Color(0xFF95A5A6)),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),

                  Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 20,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: _buildCurrentStep(),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getTitle() {
    switch (_currentStep) {
      case _ResetStep.emailInput:
        return 'Şifremi Unuttum';
      case _ResetStep.otpInput:
        return 'Kodu Girin';
      case _ResetStep.newPassword:
        return 'Yeni Şifre';
      case _ResetStep.success:
        return 'Şifre Güncellendi';
    }
  }

  String _getSubtitle() {
    switch (_currentStep) {
      case _ResetStep.emailInput:
        return 'E-posta adresinize doğrulama kodu göndereceğiz';
      case _ResetStep.otpInput:
        return 'E-posta adresinize gönderilen 6 haneli kodu girin';
      case _ResetStep.newPassword:
        return 'Yeni şifrenizi belirleyin';
      case _ResetStep.success:
        return 'Şifreniz başarıyla güncellendi';
    }
  }

  Widget _buildCurrentStep() {
    switch (_currentStep) {
      case _ResetStep.emailInput:
        return _buildEmailForm();
      case _ResetStep.otpInput:
        return _buildOtpSection();
      case _ResetStep.newPassword:
        return _buildNewPasswordForm();
      case _ResetStep.success:
        return _buildSuccessCard();
    }
  }

  /// Email giriş formu
  Widget _buildEmailForm() {
    return Form(
      key: _formKey,
      child: Column(
        children: [
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            style: const TextStyle(fontSize: 15, color: Color(0xFF2C3E50)),
            decoration: InputDecoration(
              hintText: 'E-posta adresi',
              hintStyle: const TextStyle(color: Color(0xFFBDC3C7)),
              prefixIcon: const Icon(Icons.mail_outline, color: Color(0xFF95A5A6), size: 20),
              filled: true,
              fillColor: const Color(0xFFF8F9FA),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE74C3C), width: 1)),
              focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE74C3C), width: 1.5)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2C3E50), width: 1.5)),
              errorStyle: const TextStyle(color: Color(0xFFE74C3C)),
            ),
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'E-posta adresi gerekli';
              }
              if (!value.contains('@') || !value.contains('.')) {
                return 'Geçerli bir e-posta adresi girin';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _sendOtp,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2C3E50),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Doğrulama Kodu Gönder', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
                    _currentStep = _ResetStep.emailInput;
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
        const SizedBox(height: 24),

        // Doğrula butonu
        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: (_isLoading || _otpCode.length != 6) ? null : _verifyOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2C3E50),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: _isLoading
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                : const Text('Kodu Doğrula', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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

  /// Yeni şifre formu.
  /// Flutter tarafı minimum kontrol: 8 karakter + büyük/küçük harf + rakam.
  /// Asıl güvenlik Supabase Auth sunucu ayarındadır.
  Widget _buildNewPasswordForm() {
    return Form(
      key: _passwordFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başarı ikonu
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: Color(0xFFE8F8F5),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.verified_user_rounded, size: 28, color: Color(0xFF27AE60)),
            ),
          ),
          const SizedBox(height: 16),
          const Center(
            child: Text(
              'E-posta doğrulandı',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF27AE60)),
            ),
          ),
          const SizedBox(height: 24),

          // Yeni şifre
          TextFormField(
            controller: _newPasswordController,
            obscureText: _obscurePassword,
            style: const TextStyle(fontSize: 15, color: Color(0xFF2C3E50)),
            decoration: InputDecoration(
              hintText: 'Yeni şifre',
              hintStyle: const TextStyle(color: Color(0xFFBDC3C7)),
              prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF95A5A6), size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 20,
                  color: const Color(0xFF95A5A6),
                ),
                onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              ),
              filled: true,
              fillColor: const Color(0xFFF8F9FA),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE74C3C), width: 1)),
              focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE74C3C), width: 1.5)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2C3E50), width: 1.5)),
              errorStyle: const TextStyle(color: Color(0xFFE74C3C)),
            ),
            validator: _validatePassword,
          ),
          const SizedBox(height: 8),
          // Şifre politikası ipucu
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'En az 8 karakter; büyük harf, küçük harf ve rakam içermeli.',
              style: TextStyle(fontSize: 12, color: Color(0xFF7F8C8D)),
            ),
          ),
          const SizedBox(height: 14),

          // Şifre tekrar
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: _obscureConfirmPassword,
            style: const TextStyle(fontSize: 15, color: Color(0xFF2C3E50)),
            decoration: InputDecoration(
              hintText: 'Şifre tekrar',
              hintStyle: const TextStyle(color: Color(0xFFBDC3C7)),
              prefixIcon: const Icon(Icons.lock_outline, color: Color(0xFF95A5A6), size: 20),
              suffixIcon: IconButton(
                icon: Icon(
                  _obscureConfirmPassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                  size: 20,
                  color: const Color(0xFF95A5A6),
                ),
                onPressed: () => setState(() => _obscureConfirmPassword = !_obscureConfirmPassword),
              ),
              filled: true,
              fillColor: const Color(0xFFF8F9FA),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE74C3C), width: 1)),
              focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE74C3C), width: 1.5)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF2C3E50), width: 1.5)),
              errorStyle: const TextStyle(color: Color(0xFFE74C3C)),
            ),
            validator: (value) {
              if (value != _newPasswordController.text) return 'Şifreler eşleşmiyor';
              return null;
            },
          ),
          const SizedBox(height: 24),

          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: _isLoading ? null : _updatePassword,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2C3E50),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Şifreyi Güncelle', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }

  /// Şifre politikası: minimum 8 karakter + büyük harf + küçük harf + rakam.
  /// Sembol zorunluluğu sunucu ayarıyla tutarlı olmalı; burada sadece UI
  /// geri bildirimi sağlanır. Asıl doğrulama Supabase Auth sunucusunda yapılır.
  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return 'Şifre gerekli';
    if (value.length < 8) return 'Şifre en az 8 karakter olmalı';
    if (!RegExp(r'[A-Z]').hasMatch(value)) {
      return 'En az bir büyük harf içermeli';
    }
    if (!RegExp(r'[a-z]').hasMatch(value)) {
      return 'En az bir küçük harf içermeli';
    }
    if (!RegExp(r'\d').hasMatch(value)) {
      return 'En az bir rakam içermeli';
    }
    return null;
  }

  /// Başarı kartı
  Widget _buildSuccessCard() {
    return Column(
      children: [
        Container(
          width: 72,
          height: 72,
          decoration: const BoxDecoration(
            color: Color(0xFFE8F8F5),
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.check_rounded, size: 40, color: Color(0xFF27AE60)),
        ),
        const SizedBox(height: 20),
        const Text(
          'Şifreniz güncellendi!',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF2C3E50)),
        ),
        const SizedBox(height: 12),
        const Text(
          'Yeni şifrenizle giriş yapabilirsiniz.',
          style: TextStyle(fontSize: 14, color: Color(0xFF7F8C8D), height: 1.5),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),

        SizedBox(
          width: double.infinity,
          height: 54,
          child: ElevatedButton(
            onPressed: () {
              Navigator.of(context).pushNamedAndRemoveUntil(
                '/login',
                (route) => false,
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2C3E50),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              elevation: 0,
            ),
            child: const Text('Giriş Sayfasına Git', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
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
              ? const Color(0xFF2C3E50)
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
}
