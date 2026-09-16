// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../widgets/auth_shell.dart';

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

enum _ResetStep { emailInput, otpInput, newPassword, success }

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
  final List<FocusNode> _otpFocusNodes = List.generate(6, (_) => FocusNode());

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
          _verifiedEmail =
              sentTo ?? (rawIdentifier.contains('@') ? rawIdentifier : null);
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
        _showError('İstek işlenemedi. Lütfen bir süre sonra tekrar deneyin.');
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

  void _showSuccess(String message) => showAuthSuccess(context, message);

  void _showError(String message) => showAuthError(context, message);

  // ===========================================================================
  // Arayüz
  // ===========================================================================

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: _getTitle(),
      subtitle: _getSubtitle(),
      stepIndex: _stepIndex,
      stepCount: 3,
      onBack: _currentStep == _ResetStep.success ? null : _handleBack,
      child: _buildCurrentStep(),
    );
  }

  /// İlerleme çubuğu için 1 tabanlı adım. Başarı ekranı da son adım sayılır.
  int get _stepIndex => switch (_currentStep) {
    _ResetStep.emailInput => 1,
    _ResetStep.otpInput => 2,
    _ResetStep.newPassword => 3,
    _ResetStep.success => 3,
  };

  /// OTP adımından e-posta adımına, diğerlerinden ekrandan çıkışa döner.
  void _handleBack() {
    if (_currentStep == _ResetStep.otpInput) {
      setState(() {
        _currentStep = _ResetStep.emailInput;
        _resendTimer?.cancel();
        _resendCooldown = 0;
        for (var c in _otpControllers) {
          c.clear();
        }
      });
      return;
    }
    Navigator.of(context).pop();
  }

  String _getTitle() {
    switch (_currentStep) {
      case _ResetStep.emailInput:
        return 'Şifreni sıfırla';
      case _ResetStep.otpInput:
        return 'Kodu gir';
      case _ResetStep.newPassword:
        return 'Yeni şifre';
      case _ResetStep.success:
        return 'Şifren güncellendi';
    }
  }

  String _getSubtitle() {
    switch (_currentStep) {
      case _ResetStep.emailInput:
        return 'Adım 1 / 3 — E-posta adresine doğrulama kodu göndereceğiz';
      case _ResetStep.otpInput:
        return 'Adım 2 / 3 — E-postana gönderilen 6 haneli kodu gir';
      case _ResetStep.newPassword:
        return 'Adım 3 / 3 — Yeni şifreni belirle';
      case _ResetStep.success:
        return 'Artık yeni şifrenle giriş yapabilirsin';
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

  /// Adım 1 — e-posta / kullanıcı adı girişi.
  Widget _buildEmailForm() {
    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AuthField(
              controller: _emailController,
              hint: 'E-posta adresi',
              icon: Icons.mail_outline,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.email],
              onSubmitted: (_) => _isLoading ? null : _sendOtp(),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'E-posta adresi gerekli';
                }
                if (!value.contains('@') || !value.contains('.')) {
                  return 'Geçerli bir e-posta adresi gir';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            AuthPrimaryButton(
              label: 'Doğrulama kodu gönder',
              isLoading: _isLoading,
              onPressed: _isLoading ? null : _sendOtp,
            ),
          ],
        ),
      ),
    );
  }

  /// Adım 2 — doğrulama kodu.
  Widget _buildOtpSection() {
    final p = AuthPalette.of(context);

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
                onPressed: _isLoading ? null : _handleBack,
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
        const SizedBox(height: 24),
        AuthPrimaryButton(
          label: 'Kodu doğrula',
          isLoading: _isLoading,
          onPressed: (_isLoading || _otpCode.length != 6) ? null : _verifyOtp,
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

  /// Adım 3 — yeni şifre.
  ///
  /// Flutter tarafı minimum kontrol: 8 karakter + büyük/küçük harf + rakam.
  /// Asıl güvenlik Supabase Auth sunucu ayarındadır.
  Widget _buildNewPasswordForm() {
    final p = AuthPalette.of(context);

    return AutofillGroup(
      child: Form(
        key: _passwordFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: p.success.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Icon(Icons.verified_user_rounded, size: 20, color: p.success),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'E-postan doğrulandı',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: p.success,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            AuthField(
              controller: _newPasswordController,
              hint: 'Yeni şifre',
              icon: Icons.lock_outline,
              obscure: _obscurePassword,
              onToggleObscure: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              onChanged: (_) => setState(() {}),
              helper:
                  'En az 8 karakter; büyük harf, küçük harf ve rakam içermeli.',
              validator: _validatePassword,
            ),
            AuthPasswordStrengthBar(password: _newPasswordController.text),
            const SizedBox(height: 14),
            AuthField(
              controller: _confirmPasswordController,
              hint: 'Şifre tekrar',
              icon: Icons.lock_reset_outlined,
              obscure: _obscureConfirmPassword,
              onToggleObscure: () => setState(
                () => _obscureConfirmPassword = !_obscureConfirmPassword,
              ),
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              validator: (value) {
                if (value != _newPasswordController.text) {
                  return 'Şifreler eşleşmiyor';
                }
                return null;
              },
            ),
            const SizedBox(height: 24),
            AuthPrimaryButton(
              label: 'Şifreyi güncelle',
              isLoading: _isLoading,
              onPressed: _isLoading ? null : _updatePassword,
            ),
          ],
        ),
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
    final p = AuthPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              color: p.success.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.check_rounded, size: 40, color: p.success),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'Şifren güncellendi',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            color: p.text,
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Yeni şifrenle giriş yapabilirsin.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: p.textSoft, height: 1.5),
        ),
        const SizedBox(height: 24),
        AuthPrimaryButton(
          label: 'Giriş sayfasına git',
          onPressed: () => Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/login', (route) => false),
        ),
      ],
    );
  }
}
