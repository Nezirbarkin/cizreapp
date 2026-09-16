import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../widgets/auth_shell.dart';

/// NOT: Bu ekran artık ana akışta kullanılmıyor. Yeni akış OTP tabanlı
/// (`ResetPasswordScreen` → e-posta OTP → yeni şifre). Bu ekran yalnızca
/// eski link tıklamalarından gelen (nadir) durumlarda Supabase'in oluşturduğu
/// recovery session ile şifre güncellemek için fallback olarak tutuluyor.
class ResetPasswordConfirmScreen extends StatefulWidget {
  const ResetPasswordConfirmScreen({super.key});

  @override
  State<ResetPasswordConfirmScreen> createState() =>
      _ResetPasswordConfirmScreenState();
}

class _ResetPasswordConfirmScreenState
    extends State<ResetPasswordConfirmScreen> {
  bool _isCheckingSession = true;

  @override
  void initState() {
    super.initState();
    // Eğer Supabase'in oluşturduğu bir recovery session yoksa, kullanıcıyı
    // yeni OTP akışına yönlendir. Aksi halde eski akış çalışır.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkSession());
  }

  Future<void> _checkSession() async {
    try {
      final session = Supabase.instance.client.auth.currentSession;
      final isRecovery =
          Supabase.instance.client.auth.currentUser != null && session != null;
      if (!isRecovery) {
        if (kDebugMode) {
          debugPrint('ℹ️ Recovery session yok; OTP akışına yönlendiriliyor.');
        }
        if (mounted) {
          Navigator.of(
            context,
          ).pushNamedAndRemoveUntil('/reset-password', (route) => false);
        }
      } else {
        if (mounted) setState(() => _isCheckingSession = false);
      }
    } catch (e) {
      if (kDebugMode) debugPrint('Session check error: $e');
      if (mounted) {
        Navigator.of(
          context,
        ).pushNamedAndRemoveUntil('/reset-password', (route) => false);
      }
    }
  }

  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  final _authService = AuthService();

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _updatePassword() async {
    if (!_formKey.currentState!.validate()) return;

    // Şifrelerin eşleştiğini kontrol et
    if (_passwordController.text != _confirmPasswordController.text) {
      _showErrorSnackbar('Şifreler eşleşmiyor');
      return;
    }

    setState(() => _isLoading = true);

    try {
      await _authService.updatePassword(_passwordController.text);

      if (mounted) {
        // Başarı mesajı göster ve login'e yönlendir
        _showSuccessAndNavigate();
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackbar(_authService.translateAuthError(e.toString()));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSuccessAndNavigate() {
    showAuthSuccess(context, 'Şifren başarıyla güncellendi!');

    // NavigatorState'i şimdi yakala; 2 sn sonra `Navigator.of(context)` demek
    // ekran bu arada kapanmışsa deactive element üzerinden ancestor araması
    // yapar ve "Looking up a deactivated widget's ancestor is unsafe" atar.
    final navigator = Navigator.of(context);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) {
        navigator.pushNamedAndRemoveUntil('/login', (route) => false);
      }
    });
  }

  void _showErrorSnackbar(String message) => showAuthError(context, message);

  @override
  Widget build(BuildContext context) {
    return AuthScaffold(
      title: 'Yeni şifre belirle',
      subtitle: 'Hesabını korumak için güçlü bir şifre seç',
      onBack: () => Navigator.of(context).pop(),
      child: _isCheckingSession
          // Session kontrol edilirken yükleme göster; aksi halde form.
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 56),
              child: Center(child: CircularProgressIndicator()),
            )
          : _buildForm(),
    );
  }

  Widget _buildForm() {
    final p = AuthPalette.of(context);

    return AutofillGroup(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: p.accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.key_outlined, size: 34, color: p.accent),
              ),
            ),
            const SizedBox(height: 28),
            AuthField(
              controller: _passwordController,
              hint: 'Yeni şifre',
              icon: Icons.lock_outline,
              obscure: _obscurePassword,
              onToggleObscure: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.newPassword],
              onChanged: (_) => setState(() {}),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return 'Şifre gerekli';
                }
                if (value.length < 6) {
                  return 'Şifre en az 6 karakter olmalı';
                }
                return null;
              },
            ),
            AuthPasswordStrengthBar(password: _passwordController.text),
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
                if (value == null || value.isEmpty) {
                  return 'Şifre tekrarı gerekli';
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
}
