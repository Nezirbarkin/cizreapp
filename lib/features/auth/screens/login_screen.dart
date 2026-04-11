// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/app_logo.dart';
import '../services/auth_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with TickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _identifierController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  bool _isOAuthLoading = false;
  final _authService = AuthService();

  // Animation controllers
  late AnimationController _backgroundController;
  late AnimationController _floatingController;
  late AnimationController _slideController;
  late AnimationController _pulseController;
  
  late Animation<double> _backgroundRotation;
  late Animation<double> _floatingAnimation;
  late List<FloatingShape> _shapes;

  @override
  void initState() {
    super.initState();

    // Background animation
    _backgroundController = AnimationController(
      duration: const Duration(seconds: 20),
      vsync: this,
    )..repeat();
    _backgroundRotation = Tween<double>(begin: 0, end: 2 * math.pi)
        .animate(_backgroundController);

    // Floating shapes animation
    _floatingController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    )..repeat(reverse: true);
    _floatingAnimation = CurvedAnimation(
      parent: _floatingController,
      curve: Curves.easeInOut,
    );

    // Slide animation
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    );

    // Pulse animation
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1500),
      vsync: this,
    )..repeat(reverse: true);

    // Generate floating shapes
    _shapes = List.generate(
      8,
      (index) => FloatingShape(
        position: Offset(
          math.Random().nextDouble(),
          math.Random().nextDouble(),
        ),
        size: 40 + math.Random().nextDouble() * 100,
        speed: 0.5 + math.Random().nextDouble() * 1.5,
        color: [
          Colors.orange.withOpacity(0.15),
          Colors.pink.withOpacity(0.15),
          Colors.purple.withOpacity(0.15),
          Colors.blue.withOpacity(0.15),
        ][index % 4],
      ),
    );

    _slideController.forward();
  }

  @override
  void dispose() {
    _identifierController.dispose();
    _passwordController.dispose();
    _backgroundController.dispose();
    _floatingController.dispose();
    _slideController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final response = await _authService.signInWithIdentifier(
        identifier: _identifierController.text.trim(),
        password: _passwordController.text,
      );

      if (response.session != null && mounted) {
        final userId = response.user?.id;
        if (userId != null) {
          try {
            final profile = await Supabase.instance.client
                .from('profiles')
                .select('role')
                .eq('id', userId)
                .single();

            final role = profile['role'] as String?;

            if (role == 'admin') {
              Navigator.of(context).pushReplacementNamed('/admin');
            } else {
              Navigator.of(context).pushReplacementNamed('/main');
            }
          } catch (e) {
            Navigator.of(context).pushReplacementNamed('/main');
          }
        } else {
          Navigator.of(context).pushReplacementNamed('/main');
        }
      }
    } on AuthException catch (e) {
      if (mounted) {
        _showErrorSnackBar(_authService.translateAuthError(e.message));
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar(_authService.translateAuthError(e.toString()));
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white, size: 20),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.red.shade600,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Animated gradient background
          AnimatedBuilder(
            animation: _backgroundController,
            builder: (context, _) {
              return Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.orange.shade900,
                      Colors.deepOrange.shade700,
                      Colors.pink.shade600,
                      Colors.purple.shade700,
                      Colors.blue.shade800,
                    ],
                    stops: const [0.0, 0.25, 0.5, 0.75, 1.0],
                    transform: GradientRotation(_backgroundRotation.value),
                  ),
                ),
              );
            },
          ),

          // Floating shapes
          ...(_shapes.map((shape) => _buildFloatingShape(shape))),

          // Mesh gradient overlay
          Positioned.fill(
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                return CustomPaint(
                  painter: MeshGradientPainter(
                    animation: _pulseController.value,
                  ),
                );
              },
            ),
          ),

          // Content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: AnimatedBuilder(
                  animation: _slideController,
                  builder: (context, _) {
                    final slideValue = Curves.easeOutCubic.transform(
                      _slideController.value,
                    );
                    return Opacity(
                      opacity: slideValue,
                      child: Transform.translate(
                        offset: Offset(0, 50 * (1 - slideValue)),
                        child: Form(
                          key: _formKey,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(height: 20),
                              _buildLogoSection(),
                              const SizedBox(height: 48),
                              _buildBentoGrid(),
                              const SizedBox(height: 20),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFloatingShape(FloatingShape shape) {
    return AnimatedBuilder(
      animation: _floatingAnimation,
      builder: (context, _) {
        final screenHeight = MediaQuery.of(context).size.height;
        final screenWidth = MediaQuery.of(context).size.width;
        
        final yOffset = math.sin(
          _floatingAnimation.value * 2 * math.pi * shape.speed,
        ) * 30;
        
        return Positioned(
          left: shape.position.dx * screenWidth - shape.size / 2,
          top: shape.position.dy * screenHeight + yOffset - shape.size / 2,
          child: Container(
            width: shape.size,
            height: shape.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: shape.color,
              boxShadow: [
                BoxShadow(
                  color: shape.color.withOpacity(0.3),
                  blurRadius: 40,
                  spreadRadius: 10,
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildLogoSection() {
    return Column(
      children: [
        // 3D Logo effect
        AnimatedBuilder(
          animation: _pulseController,
          builder: (context, _) {
            final scale = 1.0 + (_pulseController.value * 0.05);
            return Transform.scale(
              scale: scale,
              child: Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [
                      Colors.white.withOpacity(0.25),
                      Colors.white.withOpacity(0.1),
                      Colors.transparent,
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.white.withOpacity(0.2),
                      blurRadius: 60,
                      spreadRadius: 20,
                    ),
                  ],
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withOpacity(0.3),
                      width: 2,
                    ),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0.2),
                        Colors.white.withOpacity(0.05),
                      ],
                    ),
                  ),
                  child: AppLogo.white(
                    width: 80,
                    height: 80,
                  ),
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 28),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [
              Colors.white,
              Color(0xFFF0F0F0),
            ],
          ).createShader(bounds),
          child: const Text(
            'CizreApp',
            style: TextStyle(
              fontSize: 42,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -1,
              height: 1,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'Geleceğe Hoş Geldiniz',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w500,
            color: Colors.white.withOpacity(0.85),
            letterSpacing: 2,
          ),
        ),
      ],
    );
  }

  Widget _buildBentoGrid() {
    return Column(
      children: [
        // Main login card
        _buildGlassmorphicCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF6B35), Color(0xFFF7931E)],
                      ),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.login_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Giriş Yap',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              
              // Email / Username field
              _buildModernInput(
                controller: _identifierController,
                label: 'Email veya Kullanıcı Adı',
                hint: 'ornek@email.com',
                icon: Icons.person_outline_rounded,
                keyboardType: TextInputType.emailAddress,
                validator: (value) {
                  if (value == null || value.isEmpty) {
                    return 'Bu alan gerekli';
                  }
                  if (value.length < 3) {
                    return 'En az 3 karakter girin';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Password field
              _buildModernInput(
                controller: _passwordController,
                label: 'Şifre',
                hint: '••••••••',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscurePassword,
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: Colors.white.withOpacity(0.7),
                    size: 22,
                  ),
                  onPressed: () {
                    setState(() => _obscurePassword = !_obscurePassword);
                  },
                ),
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
              const SizedBox(height: 12),

              // Forgot password
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () =>
                      Navigator.of(context).pushNamed('/reset-password'),
                  child: Text(
                    'Şifremi Unuttum?',
                    style: TextStyle(
                      color: Colors.orange.shade200,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),

              // Login button with 3D effect
              _buildModernButton(
                text: 'Giriş Yap',
                onPressed: _login,
                isLoading: _isLoading,
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFFF6B35),
                    Color(0xFFF7931E),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // Divider
              Row(
                children: [
                  Expanded(
                    child: Container(
                      height: 1,
                      color: Colors.white.withOpacity(0.2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'veya',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.7),
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Container(
                      height: 1,
                      color: Colors.white.withOpacity(0.2),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Google Sign In
              _buildOAuthButton(
                icon: Icons.g_mobiledata_rounded,
                label: 'Google ile Devam Et',
                onPressed: _handleGoogleSignIn,
                iconColor: Colors.red.shade400,
              ),
              const SizedBox(height: 12),

              // Apple Sign In
              _buildOAuthButton(
                icon: Icons.apple_rounded,
                label: 'Apple ile Devam Et',
                onPressed: _handleAppleSignIn,
                iconColor: Colors.white,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // Bottom cards row
        Row(
          children: [
            // Register card
            Expanded(
              child: _buildGlassmorphicCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.green.shade400,
                            Colors.teal.shade500,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.person_add_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Yeni Misin?',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () =>
                            Navigator.of(context).pushNamed('/register'),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Kayıt Ol',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),

            // Guest card
            Expanded(
              child: _buildGlassmorphicCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.purple.shade400,
                            Colors.pink.shade500,
                          ],
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(
                        Icons.explore_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Keşfet',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.of(context)
                            .pushReplacementNamed('/main'),
                        borderRadius: BorderRadius.circular(8),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(
                              color: Colors.white.withOpacity(0.3),
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Text(
                            'Misafir',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGlassmorphicCard({required Widget child}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withOpacity(0.25),
                Colors.white.withOpacity(0.1),
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withOpacity(0.3),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 30,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _buildModernInput({
    required TextEditingController controller,
    required String label,
    required String hint,
    required IconData icon,
    bool obscureText = false,
    Widget? suffixIcon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      obscureText: obscureText,
      keyboardType: keyboardType,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: Icon(icon, color: Colors.white.withOpacity(0.8), size: 22),
        suffixIcon: suffixIcon,
        filled: true,
        fillColor: Colors.white.withOpacity(0.15),
        labelStyle: TextStyle(
          color: Colors.white.withOpacity(0.85),
          fontWeight: FontWeight.w500,
        ),
        hintStyle: TextStyle(
          color: Colors.white.withOpacity(0.4),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Colors.white.withOpacity(0.3),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Colors.white.withOpacity(0.3),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(
            color: Colors.white,
            width: 2,
          ),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Colors.orange.shade300,
            width: 1.5,
          ),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: Colors.orange.shade300,
            width: 2,
          ),
        ),
        errorStyle: TextStyle(
          color: Colors.orange.shade200,
          fontWeight: FontWeight.w600,
          fontSize: 12,
        ),
      ),
      validator: validator,
    );
  }

  Widget _buildModernButton({
    required String text,
    required VoidCallback onPressed,
    required bool isLoading,
    required Gradient gradient,
  }) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: gradient,
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.5),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: isLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: isLoading
                ? const SizedBox(
                    height: 24,
                    width: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : Text(
                    text,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                      letterSpacing: 0.5,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleGoogleSignIn() async {
    setState(() => _isOAuthLoading = true);
    
    try {
      final response = await _authService.signInWithGoogle();
      if (response.user != null && mounted) {
        Navigator.of(context).pushReplacementNamed('/main');
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar(_authService.translateOAuthError(e.toString()));
      }
    } finally {
      if (mounted) {
        setState(() => _isOAuthLoading = false);
      }
    }
  }

  Future<void> _handleAppleSignIn() async {
    setState(() => _isOAuthLoading = true);
    
    try {
      final response = await _authService.signInWithApple();
      if (response.user != null && mounted) {
        Navigator.of(context).pushReplacementNamed('/main');
      }
    } catch (e) {
      if (mounted) {
        _showErrorSnackBar(_authService.translateOAuthError(e.toString()));
      }
    } finally {
      if (mounted) {
        setState(() => _isOAuthLoading = false);
      }
    }
  }

  Widget _buildOAuthButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required Color iconColor,
  }) {
    return Container(
      height: 50,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withOpacity(0.15),
        border: Border.all(
          color: Colors.white.withOpacity(0.3),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: _isOAuthLoading ? null : onPressed,
          borderRadius: BorderRadius.circular(14),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _isOAuthLoading
                ? const Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    ),
                  )
                : Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon, color: iconColor, size: 26),
                      const SizedBox(width: 12),
                      Text(
                        label,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

// Floating shape model
class FloatingShape {
  final Offset position;
  final double size;
  final double speed;
  final Color color;

  FloatingShape({
    required this.position,
    required this.size,
    required this.speed,
    required this.color,
  });
}

// Custom painter for mesh gradient
class MeshGradientPainter extends CustomPainter {
  final double animation;

  MeshGradientPainter({required this.animation});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 100);

    // Animated gradient blobs
    final blob1 = Offset(
      size.width * 0.2 + math.sin(animation * 2 * math.pi) * 50,
      size.height * 0.3 + math.cos(animation * 2 * math.pi) * 50,
    );
    final blob2 = Offset(
      size.width * 0.8 + math.cos(animation * 2 * math.pi) * 50,
      size.height * 0.6 + math.sin(animation * 2 * math.pi) * 50,
    );
    final blob3 = Offset(
      size.width * 0.5 + math.sin(animation * math.pi) * 30,
      size.height * 0.8 + math.cos(animation * math.pi) * 30,
    );

    paint.color = Colors.purple.withOpacity(0.1);
    canvas.drawCircle(blob1, 150, paint);

    paint.color = Colors.blue.withOpacity(0.1);
    canvas.drawCircle(blob2, 180, paint);

    paint.color = Colors.pink.withOpacity(0.1);
    canvas.drawCircle(blob3, 160, paint);
  }

  @override
  bool shouldRepaint(covariant MeshGradientPainter oldDelegate) {
    return oldDelegate.animation != animation;
  }
}
