// ignore_for_file: deprecated_member_use

import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';

class LoginScreenV2 extends StatefulWidget {
  const LoginScreenV2({super.key});

  @override
  State<LoginScreenV2> createState() => _LoginScreenV2State();
}

class _LoginScreenV2State extends State<LoginScreenV2> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  final _authService = AuthService();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isLoading = true);

    // emailToUse değişkenini try bloğunun dışında tanımla
    String emailToUse = '';
    
    try {
      final input = _emailController.text.trim();
      
      // Kullanıcı adı mı yoksa e-posta mı kontrol et
      final isEmail = input.contains('@');
      emailToUse = input;
      
      if (!isEmail) {
        // Kullanıcı adı ile giriş - profiles tablosundan email bul
        debugPrint('🔍 Kullanıcı adı ile giriş: $input');
        
        try {
          final profileResponse = await Supabase.instance.client
              .from('profiles')
              .select('email')
              .eq('username', input.toLowerCase())
              .maybeSingle();
          
          if (profileResponse == null || profileResponse['email'] == null) {
            throw Exception('Kullanıcı adı veya e-posta bulunamadı');
          }
          
          emailToUse = profileResponse['email'] as String;
          debugPrint('✅ Email bulundu: $emailToUse');
        } catch (e) {
          debugPrint('❌ Kullanıcı adı bulunamadı: $e');
          throw Exception('Kullanıcı adı veya şifre hatalı');
        }
      }
      
      // Giriş yap
      await Supabase.instance.client.auth.signInWithPassword(
        email: emailToUse,
        password: _passwordController.text,
      );
      
      if (mounted) Navigator.of(context).pushReplacementNamed('/main');
    } on AuthException catch (e) {
      if (mounted) {
        // Email doğrulama hatası kontrolü
        if (e.message.contains('Email not confirmed') || e.message.contains('email_not_confirmed')) {
          _showEmailVerificationDialog(emailToUse);
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

  void _showEmailVerificationDialog(String email) {
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
              child: const Icon(Icons.mark_email_read_rounded, size: 40, color: Color(0xFF3498DB)),
            ),
            const SizedBox(height: 20),
            const Text('E-posta Doğrulanmadı', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: Color(0xFF2C3E50))),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                'Hesabınızı aktifleştirmek için lütfen e-posta adresinizi doğrulayın.',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Color(0xFF7F8C8D), height: 1.4),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                email,
                style: const TextStyle(fontSize: 13, color: Color(0xFF3498DB), fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Spam klasörünü kontrol etmeyi unutmayın.',
              style: TextStyle(fontSize: 12, color: Color(0xFF95A5A6)),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.of(ctx).pop();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF95A5A6),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: const Text('Kapat', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await _resendVerificationEmail(email);
              },
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF3498DB),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('Doğrulama E-postasını Yeniden Gönder'),
            ),
          ),
        ],
      ),
    );
  }

  /// Email doğrulama redirect URL
  ///
  /// www.cizreapp.com/verify sunucusuna yüklenen verify.html sayfasını kullanır.
  /// Bu sayfa token'ı işleyip uygulamayı açar.
  String _getRedirectUrl() {
    return 'https://www.cizreapp.com/verify';
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
        final isRateLimitError = errorStr.contains('rate limit') ||
                                 errorStr.contains('too many') ||
                                 errorStr.contains('overload');
        
        if (isRateLimitError && attempt < maxRetries) {
          debugPrint('⏳ Rate limiting hatası ($attempt/$maxRetries), ${delay.inSeconds} saniye bekleniyor...');
          await Future.delayed(delay);
          delay = delay * 2; // Bekleme süresini artır
          continue;
        }
        
        // Son deneme veya rate limiting hatası değilse
        errorMessage = e.message;
        break;
      } catch (e) {
        final errorStr = e.toString().toLowerCase();
        final isRateLimitError = errorStr.contains('rate limit') ||
                                 errorStr.contains('too many') ||
                                 errorStr.contains('overload');
        
        if (isRateLimitError && attempt < maxRetries) {
          debugPrint('⏳ Rate limiting hatası ($attempt/$maxRetries), ${delay.inSeconds} saniye bekleniyor...');
          await Future.delayed(delay);
          delay = delay * 2;
          continue;
        }
        
        errorMessage = 'E-posta gönderilemedi. Lütfen 30 saniye bekleyip tekrar deneyin.';
        break;
      }
    }
    
    if (mounted) {
      setState(() => _isLoading = false);
      if (success) {
        _showSuccess('Doğrulama e-postası yeniden gönderildi! Lütfen e-posta kutunuzu kontrol edin.');
      } else if (errorMessage != null) {
        _showError(errorMessage);
      }
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 40),
                
                // Logo / App Name
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 10,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      const Text(
                        'CizreApp',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2C3E50),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Cizre\'nin Dijital Pazarı & Sosyal Medya Ağı',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey.shade600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 32),
                
                const Text(
                  'Giriş Yap',
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF2C3E50),
                  ),
                ),
                const SizedBox(height: 24),

                // Form
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        // ignore: deprecated_member_use
                        color: Colors.black.withOpacity(0.04),
                        blurRadius: 20,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      children: [
                        _buildField(
                          controller: _emailController,
                          hint: 'Kullanıcı adı veya E-posta',
                          icon: Icons.person_outline,
                          validator: (v) => (v?.isEmpty ?? true) ? 'Kullanıcı adı veya e-posta gerekli' : null,
                        ),
                        const SizedBox(height: 16),
                        _buildField(
                          controller: _passwordController,
                          hint: 'Şifre',
                          icon: Icons.lock_outline,
                          obscure: _obscurePassword,
                          onTap: () => setState(() => _obscurePassword = !_obscurePassword),
                          validator: (v) => (v?.isEmpty ?? true) ? 'Şifre gerekli' : null,
                        ),
                        const SizedBox(height: 12),
                        
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton(
                            onPressed: () => Navigator.of(context).pushNamed('/reset-password'),
                            child: const Text('Şifremi Unuttum', style: TextStyle(color: Color(0xFF1ABC9C), fontWeight: FontWeight.w600)),
                          ),
                        ),
                        const SizedBox(height: 8),

                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: ElevatedButton(
                            onPressed: _isLoading ? null : _handleLogin,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF1ABC9C),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              elevation: 0,
                            ),
                            child: _isLoading
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                                : const Text('Giriş Yap', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: 0.3)),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Alt linkler
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('Hesabınız yok mu? ', style: TextStyle(color: Color(0xFF95A5A6))),
                    TextButton(
                      onPressed: () => Navigator.of(context).pushReplacementNamed('/register'),
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, foregroundColor: const Color(0xFF2C3E50)),
                      child: const Text('Kayıt Ol', style: TextStyle(fontWeight: FontWeight.w600)),
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

  Widget _buildField({
    required TextEditingController controller,
    required String hint,
    required IconData icon,
    String? Function(String?)? validator,
    bool obscure = false,
    VoidCallback? onTap,
  }) {
    return TextFormField(
      controller: controller,
      validator: validator,
      obscureText: obscure,
      style: const TextStyle(fontSize: 15, color: Color(0xFF2C3E50)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Color(0xFFBDC3C7)),
        prefixIcon: Icon(icon, color: const Color(0xFF1ABC9C), size: 20),
        suffixIcon: onTap != null ? IconButton(icon: Icon(obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 20, color: const Color(0xFF95A5A6)), onPressed: onTap) : null,
        filled: true,
        fillColor: const Color(0xFFF8F9FA),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE74C3C), width: 1)),
        focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE74C3C), width: 1.5)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF1ABC9C), width: 1.5)),
        errorStyle: const TextStyle(color: Color(0xFFE74C3C)),
      ),
    );
  }
}
