import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../widgets/auth_shell.dart';
import 'choose_username_screen.dart';
import '../../admin/screens/admin_dashboard_screen.dart';
import '../../seller/screens/seller_dashboard_screen.dart';

/// "Beni Hatırla" tercihi bu anahtarla saklanır. `main.dart` uygulama
/// başlangıcında bunu okuyup false ise (kullanıcı bir önceki girişte tiki
/// kaldırdıysa) kalıcı Supabase oturumunu sonlandırır.
const String kRememberMePrefsKey = 'remember_me';

class LoginScreenV2 extends StatefulWidget {
  const LoginScreenV2({super.key});

  @override
  State<LoginScreenV2> createState() => _LoginScreenV2State();
}

class _LoginScreenV2State extends State<LoginScreenV2> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _passwordFocus = FocusNode();
  bool _isLoading = false;
  bool _isOAuthLoading = false;
  bool _obscurePassword = true;
  // Varsayılan işaretli: mevcut kalıcı-oturum davranışı korunur, kullanıcı
  // bilinçli olarak kaldırmadıkça hiçbir şey değişmez.
  bool _rememberMe = true;
  final _authService = AuthService();

  bool get _busy => _isLoading || _isOAuthLoading;

  @override
  void initState() {
    super.initState();
    _loadRememberMePreference();
  }

  Future<void> _loadRememberMePreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final remembered = prefs.getBool(kRememberMePrefsKey) ?? true;
      if (mounted) setState(() => _rememberMe = remembered);
    } catch (_) {
      // Sessizce varsayılanda kal (true)
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _passwordFocus.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    final identifier = _emailController.text.trim();

    try {
      // profiles.email hassas alanı anon kullanıcılara kapalıdır. Kullanıcı
      // adı çözümlemesini doğrudan tablo sorgusuyla yapmak bu nedenle giriş
      // öncesinde RLS/kolon yetkisine takılıyordu. AuthService bu işlem için
      // yalnız e-posta döndüren dar lookup_email_by_username RPC'sini kullanır.
      await _authService.signInWithIdentifier(
        identifier: identifier,
        password: _passwordController.text,
      );

      // "Beni Hatırla" tercihini kaydet. main.dart bir sonraki soğuk açılışta
      // bunu okuyup false ise kalıcı oturumu sonlandırır (zorla tekrar giriş).
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(kRememberMePrefsKey, _rememberMe);
      } catch (e) {
        debugPrint('⚠️ Beni Hatırla tercihi kaydedilemedi: $e');
      }

      // Rol kontrolü yap ve uygun panele yönlendir
      if (mounted) {
        await _navigateBasedOnRole();
      }
    } on AuthException catch (e) {
      if (mounted) {
        // Email doğrulama hatası kontrolü
        if (e.message.contains('Email not confirmed') ||
            e.message.contains('email_not_confirmed')) {
          // Kullanıcı adıyla girişte gerçek e-postayı istemci tarafında ayrıca
          // tutmuyoruz. Dialog yeniden gönderim yapabilmek için e-posta ister.
          if (identifier.contains('@')) {
            _showEmailVerificationDialog(identifier.toLowerCase());
          } else {
            _showError(_authService.translateAuthError(e.message));
          }
        } else {
          _showError(_authService.translateAuthError(e.message));
        }
      }
    } catch (e) {
      if (mounted) {
        _showError(_authService.translateAuthError(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isOAuthLoading = true);

    try {
      final response = await _authService.signInWithGoogle();
      if (response.user != null && mounted) {
        await _continueAfterSocialSignIn();
      }
    } catch (e) {
      if (mounted) {
        _showError(_authService.translateOAuthError(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _isOAuthLoading = false);
    }
  }

  Future<void> _handleAppleSignIn() async {
    setState(() => _isOAuthLoading = true);

    try {
      final response = await _authService.signInWithApple();
      if (response.user != null && mounted) {
        await _continueAfterSocialSignIn();
      }
    } catch (e) {
      if (mounted) {
        _showError(_authService.translateOAuthError(e.toString()));
      }
    } finally {
      if (mounted) setState(() => _isOAuthLoading = false);
    }
  }

  /// Google/Apple ile giriş, hesabı ilk kez oluşturuyor olabilir (Supabase
  /// `signInWithIdToken` kullanıcı yoksa oluşturur). `handle_new_user`
  /// tetikleyicisi böyle bir hesaba geçici bir misafir_ adı verdiyse, rol
  /// bazlı yönlendirmeden önce gerçek kullanıcı adını sorup kaydı tamamlatır.
  Future<void> _continueAfterSocialSignIn() async {
    final needsUsername = await needsUsernameSetup();
    if (!mounted) return;
    if (needsUsername) {
      Navigator.of(
        context,
      ).pushReplacement(MaterialPageRoute(builder: (_) => const ChooseUsernameScreen()));
    } else {
      await _navigateBasedOnRole();
    }
  }

  /// Kullanıcı rolüne göre uygun panele yönlendir
  Future<void> _navigateBasedOnRole() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) Navigator.of(context).pushReplacementNamed('/main');
        return;
      }

      final response = await Supabase.instance.client
          .from('profiles')
          .select('role')
          .eq('id', userId)
          .maybeSingle();

      final role = response?['role'] as String? ?? 'customer';
      debugPrint('🔄 Kullanıcı rolü: $role');

      if (!mounted) return;

      switch (role) {
        case 'admin':
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => const AdminDashboardScreen(),
            ),
            (route) => false,
          );
          break;
        case 'seller':
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(
              builder: (context) => const SellerDashboardScreen(),
            ),
            (route) => false,
          );
          break;
        case 'courier':
          // Kurye normal kullanıcı gibi MainScreen'i kullanır
          // Kurye özelliklerine ayarlardan veya kurye panelinden erişir
          Navigator.of(context).pushReplacementNamed('/main');
          break;
        default:
          Navigator.of(context).pushReplacementNamed('/main');
      }
    } catch (e) {
      debugPrint('❌ Rol kontrolü hatası: $e');
      if (mounted) Navigator.of(context).pushReplacementNamed('/main');
    }
  }

  void _showEmailVerificationDialog(String email) {
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
                  color: p.accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.mark_email_read_rounded,
                  size: 38,
                  color: p.accent,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'E-posta doğrulanmadı',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: p.text,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Hesabını aktifleştirmek için e-posta adresini doğrulaman gerekiyor.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: p.textSoft, height: 1.4),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: p.field,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  email,
                  style: TextStyle(
                    fontSize: 13,
                    color: p.accent,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Spam klasörünü kontrol etmeyi unutma.',
                style: TextStyle(fontSize: 12, color: p.textMuted),
              ),
            ],
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: AuthPrimaryButton(
                label: 'Doğrulama e-postasını yeniden gönder',
                onPressed: () async {
                  Navigator.of(ctx).pop();
                  await _resendVerificationEmail(email);
                },
              ),
            ),
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                style: TextButton.styleFrom(
                  foregroundColor: p.textSoft,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Kapat'),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _resendVerificationEmail(String email) async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    // Rate limiting için retry mekanizması
    int maxRetries = 3;
    Duration delay = const Duration(seconds: 2);
    bool success = false;
    String? errorMessage;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        // Supabase resend API - auth-callback.html sayfasına yönlendirir
        await Supabase.instance.client.auth.resend(
          type: OtpType.signup,
          email: email,
          emailRedirectTo: 'https://www.cizreapp.com/auth-callback.html',
        );

        success = true;
        break; // Başarılı, döngüden çık
      } on AuthException catch (e) {
        final errorStr = e.message.toLowerCase();
        final isRateLimitError =
            errorStr.contains('rate limit') ||
            errorStr.contains('too many') ||
            errorStr.contains('overload');

        if (isRateLimitError && attempt < maxRetries) {
          debugPrint(
            '⏳ Rate limiting hatası ($attempt/$maxRetries), ${delay.inSeconds} saniye bekleniyor...',
          );
          await Future.delayed(delay);
          delay = delay * 2; // Bekleme süresini artır
          continue;
        }

        // Son deneme veya rate limiting hatası değilse
        errorMessage = e.message;
        break;
      } catch (e) {
        final errorStr = e.toString().toLowerCase();
        final isRateLimitError =
            errorStr.contains('rate limit') ||
            errorStr.contains('too many') ||
            errorStr.contains('overload');

        if (isRateLimitError && attempt < maxRetries) {
          debugPrint(
            '⏳ Rate limiting hatası ($attempt/$maxRetries), ${delay.inSeconds} saniye bekleniyor...',
          );
          await Future.delayed(delay);
          delay = delay * 2;
          continue;
        }

        errorMessage =
            'E-posta gönderilemedi. Lütfen 30 saniye bekleyip tekrar deneyin.';
        break;
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        _showSuccess(
          'Doğrulama e-postası yeniden gönderildi! Lütfen e-posta kutunu kontrol et.',
        );
      } else if (errorMessage != null) {
        _showError(errorMessage);
      }
    }
  }

  void _showError(String message) => showAuthError(context, message);

  void _showSuccess(String message) => showAuthSuccess(context, message);

  @override
  Widget build(BuildContext context) {
    final p = AuthPalette.of(context);

    return AuthScaffold(
      showLogo: true,
      title: 'Tekrar hoş geldin',
      subtitle: 'Cizre\'nin dijital pazarı ve sosyal medya ağı',
      footer: AuthFooterLink(
        question: 'Hesabın yok mu?',
        action: 'Kayıt ol',
        onPressed: () =>
            Navigator.of(context).pushReplacementNamed('/register'),
      ),
      child: AutofillGroup(
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthField(
                controller: _emailController,
                hint: 'Kullanıcı adı veya e-posta',
                icon: Icons.person_outline,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [
                  AutofillHints.username,
                  AutofillHints.email,
                ],
                onSubmitted: (_) => _passwordFocus.requestFocus(),
                validator: (v) => (v?.trim().isEmpty ?? true)
                    ? 'Kullanıcı adı veya e-posta gerekli'
                    : null,
              ),
              const SizedBox(height: 14),
              AuthField(
                controller: _passwordController,
                focusNode: _passwordFocus,
                hint: 'Şifre',
                icon: Icons.lock_outline,
                obscure: _obscurePassword,
                onToggleObscure: () =>
                    setState(() => _obscurePassword = !_obscurePassword),
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.password],
                onSubmitted: (_) => _busy ? null : _handleLogin(),
                validator: (v) => (v?.isEmpty ?? true) ? 'Şifre gerekli' : null,
              ),
              const SizedBox(height: 6),

              // "Beni hatırla" ve "Şifremi unuttum" tek satırda: eski tasarımda
              // ayrı satırlardaydı ve gereksiz dikey alan harcıyordu.
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: InkWell(
                      onTap: () => setState(() => _rememberMe = !_rememberMe),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 22,
                              height: 22,
                              child: Checkbox(
                                value: _rememberMe,
                                onChanged: (value) =>
                                    setState(() => _rememberMe = value ?? true),
                                activeColor: p.brand,
                                side: BorderSide(
                                  color: p.textMuted,
                                  width: 1.4,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(5),
                                ),
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Beni hatırla',
                              style: TextStyle(color: p.textSoft, fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        Navigator.of(context).pushNamed('/reset-password'),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor: p.accent,
                    ),
                    child: const Text(
                      'Şifremi unuttum',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              AuthPrimaryButton(
                label: 'Giriş yap',
                isLoading: _isLoading,
                onPressed: _busy ? null : _handleLogin,
              ),

              const SizedBox(height: 20),
              const AuthDivider(),
              const SizedBox(height: 16),

              AuthSocialButton(
                label: 'Google ile devam et',
                icon: Icons.g_mobiledata_rounded,
                iconColor: const Color(0xFFEA4335),
                onPressed: _busy ? null : _handleGoogleSignIn,
              ),
              if (authAppleSignInAvailable) ...[
                const SizedBox(height: 10),
                AuthSocialButton(
                  label: 'Apple ile devam et',
                  icon: Icons.apple_rounded,
                  onPressed: _busy ? null : _handleAppleSignIn,
                ),
              ],
              if (_isOAuthLoading) ...[
                const SizedBox(height: 14),
                Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: p.accent,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
