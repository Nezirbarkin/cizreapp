// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/app_logo.dart';
import '../services/auth_service.dart';
import '../../profile/services/profile_service.dart';

class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

enum RegistrationStep { credentials, personal, profile, complete }

class _RegisterScreenState extends State<RegisterScreen>
    with TickerProviderStateMixin {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _fullNameController = TextEditingController();

  final _authService = AuthService();
  final _profileService = ProfileService();

  bool _isLoading = false;
  bool _isOAuthLoading = false;
  bool _obscurePassword = true;
  bool _obscureConfirmPassword = true;
  
  // Username availability check
  String? _usernameStatus;
  bool _isCheckingUsername = false;

  // Multi-step
  RegistrationStep _currentStep = RegistrationStep.credentials;

  // Animation controllers
  late AnimationController _backgroundController;
  late AnimationController _floatingController;
  late AnimationController _progressController;
  late AnimationController _stepController;
  late AnimationController _confettiController;
  
  late Animation<double> _backgroundRotation;
  late Animation<double> _floatingAnimation;
  late List<FloatingShape> _shapes;
  late List<ConfettiParticle> _confetti = [];

  @override
  void initState() {
    super.initState();

    // Background animation
    _backgroundController = AnimationController(
      duration: const Duration(seconds: 25),
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

    // Progress animation
    _progressController = AnimationController(
      duration: const Duration(milliseconds: 500),
      vsync: this,
    );

    // Step animation
    _stepController = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    // Confetti animation
    _confettiController = AnimationController(
      duration: const Duration(seconds: 3),
      vsync: this,
    );

    // Generate floating shapes
    _shapes = List.generate(
      10,
      (index) => FloatingShape(
        position: Offset(
          math.Random().nextDouble(),
          math.Random().nextDouble(),
        ),
        size: 30 + math.Random().nextDouble() * 120,
        speed: 0.5 + math.Random().nextDouble() * 1.5,
        color: [
          Colors.pink.withOpacity(0.2),
          Colors.purple.withOpacity(0.2),
          Colors.blue.withOpacity(0.2),
          Colors.cyan.withOpacity(0.2),
        ][index % 4],
      ),
    );

    _progressController.forward();
    _stepController.forward();
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    _usernameController.dispose();
    _fullNameController.dispose();
    _backgroundController.dispose();
    _floatingController.dispose();
    _progressController.dispose();
    _stepController.dispose();
    _confettiController.dispose();
    super.dispose();
  }

  // Password strength calculation
  double get _passwordStrength {
    final password = _passwordController.text;
    if (password.isEmpty) return 0;
    
    double strength = 0;
    
    // Length
    if (password.length >= 8) strength += 0.25;
    if (password.length >= 12) strength += 0.15;
    
    // Contains lowercase
    if (password.contains(RegExp(r'[a-z]'))) strength += 0.2;
    
    // Contains uppercase
    if (password.contains(RegExp(r'[A-Z]'))) strength += 0.2;
    
    // Contains number
    if (password.contains(RegExp(r'[0-9]'))) strength += 0.2;
    
    // Contains special char
    if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) strength += 0.2;
    
    return strength.clamp(0, 1);
  }

  String get _passwordStrengthLabel {
    final strength = _passwordStrength;
    if (strength == 0) return '';
    if (strength < 0.3) return 'Zayıf';
    if (strength < 0.6) return 'Orta';
    if (strength < 0.8) return 'İyi';
    return 'Güçlü';
  }

  Color get _passwordStrengthColor {
    final strength = _passwordStrength;
    if (strength < 0.3) return Colors.red;
    if (strength < 0.6) return Colors.orange;
    if (strength < 0.8) return Colors.yellow;
    return Colors.green;
  }

  void _nextStep() {
    if (_currentStep == RegistrationStep.credentials) {
      if (_validateStep1()) {
        _progressController.forward(from: 0);
        setState(() => _currentStep = RegistrationStep.personal);
      }
    } else if (_currentStep == RegistrationStep.personal) {
      if (_validateStep2()) {
        _progressController.forward(from: 0);
        setState(() => _currentStep = RegistrationStep.profile);
      }
    } else if (_currentStep == RegistrationStep.profile) {
      _register();
    }
  }

  void _previousStep() {
    if (_currentStep == RegistrationStep.personal) {
      setState(() => _currentStep = RegistrationStep.credentials);
    } else if (_currentStep == RegistrationStep.profile) {
      setState(() => _currentStep = RegistrationStep.personal);
    }
  }

  bool _validateStep1() {
    if (_emailController.text.isEmpty) {
      _showError('Email gerekli');
      return false;
    }
    if (!_emailController.text.contains('@')) {
      _showError('Geçerli bir email girin');
      return false;
    }
    if (_passwordController.text.isEmpty) {
      _showError('Şifre gerekli');
      return false;
    }
    if (_passwordController.text.length < 6) {
      _showError('Şifre en az 6 karakter olmalı');
      return false;
    }
    if (_confirmPasswordController.text != _passwordController.text) {
      _showError('Şifreler eşleşmiyor');
      return false;
    }
    return true;
  }

  bool _validateStep2() {
    if (_fullNameController.text.isEmpty) {
      _showError('Ad soyad gerekli');
      return false;
    }
    if (_usernameController.text.isEmpty) {
      _showError('Kullanıcı adı gerekli');
      return false;
    }
    if (_usernameController.text.length < 3) {
      _showError('Kullanıcı adı en az 3 karakter');
      return false;
    }
    if (_usernameStatus == 'taken') {
      _showError('Bu kullanıcı adı alınmış');
      return false;
    }
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(_usernameController.text)) {
      _showError('Sadece harf, rakam ve _');
      return false;
    }
    return true;
  }

  Future<void> _checkUsernameAvailability() async {
    final username = _usernameController.text.trim();

    if (username.isEmpty) {
      setState(() {
        _usernameStatus = null;
        _isCheckingUsername = false;
      });
      return;
    }

    if (username.length < 3) {
      setState(() {
        _usernameStatus = 'short';
        _isCheckingUsername = false;
      });
      return;
    }

    setState(() => _isCheckingUsername = true);

    try {
      final isAvailable = await _profileService.isUsernameAvailable(username);
      if (mounted) {
        setState(() {
          _usernameStatus = isAvailable ? 'available' : 'taken';
          _isCheckingUsername = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _usernameStatus = null;
          _isCheckingUsername = false;
        });
      }
    }
  }

  Future<void> _register() async {
    setState(() => _isLoading = true);

    try {
      final response = await _authService.signUp(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        fullName: _fullNameController.text.trim(),
        username: _usernameController.text.trim(),
      );

      if (response.user != null && mounted) {
        // Generate confetti
        _generateConfetti();
        _confettiController.forward();
        
        setState(() => _currentStep = RegistrationStep.complete);
        
        // Navigate after delay
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
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

  void _generateConfetti() {
    _confetti = List.generate(
      100,
      (index) => ConfettiParticle(
        position: Offset(
          MediaQuery.of(context).size.width / 2,
          MediaQuery.of(context).size.height / 2,
        ),
        velocity: Offset(
          (math.Random().nextDouble() - 0.5) * 20,
          (math.Random().nextDouble() - 0.5) * 20,
        ),
        color: [
          Colors.pink,
          Colors.purple,
          Colors.blue,
          Colors.cyan,
          Colors.orange,
          Colors.yellow,
        ][index % 6],
        size: 5 + math.Random().nextDouble() * 10,
      ),
    );
  }

  void _showError(String message) {
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
                      Colors.pink.shade900,
                      Colors.purple.shade700,
                      Colors.blue.shade800,
                      Colors.cyan.shade700,
                      Colors.pink.shade900,
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
            child: CustomPaint(
              painter: MeshGradientPainter(
                animation: _floatingController.value,
              ),
            ),
          ),

          // Confetti overlay
          if (_currentStep == RegistrationStep.complete)
            AnimatedBuilder(
              animation: _confettiController,
              builder: (context, _) {
                return CustomPaint(
                  painter: ConfettiPainter(
                    confetti: _confetti,
                    progress: _confettiController.value,
                  ),
                );
              },
            ),

          // Content
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: AnimatedBuilder(
                  animation: _stepController,
                  builder: (context, _) {
                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const SizedBox(height: 20),
                        _buildLogoSection(),
                        const SizedBox(height: 32),
                        _buildProgressIndicator(),
                        const SizedBox(height: 24),
                        _buildStepContent(),
                      ],
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
        ) * 40;
        
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
                  blurRadius: 50,
                  spreadRadius: 15,
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
        Container(
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
        const SizedBox(height: 28),
        ShaderMask(
          shaderCallback: (bounds) => const LinearGradient(
            colors: [Colors.white, Color(0xFFF0F0F0)],
          ).createShader(bounds),
          child: const Text(
            'Hesap Oluştur',
            style: TextStyle(
              fontSize: 32,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: -1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildProgressIndicator() {
    final stepIndex = _currentStep.index.clamp(0, 2);
    
    return Column(
      children: [
        // Step indicators
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(3, (index) {
            final isActive = index <= stepIndex;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              margin: const EdgeInsets.symmetric(horizontal: 6),
              child: Container(
                width: 60,
                height: 4,
                decoration: BoxDecoration(
                  color: isActive
                      ? Colors.white
                      : Colors.white.withOpacity(0.3),
                  borderRadius: BorderRadius.circular(2),
                  boxShadow: isActive
                      ? [
                          BoxShadow(
                            color: Colors.white.withOpacity(0.5),
                            blurRadius: 8,
                          ),
                        ]
                      : [],
                ),
              ),
            );
          }),
        ),
        const SizedBox(height: 16),
        
        // Step labels
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _buildStepLabel('Bilgiler', 0),
            _buildStepLabel('Profil', 1),
            _buildStepLabel('Kullanıcı', 2),
          ],
        ),
      ],
    );
  }

  Widget _buildStepLabel(String label, int index) {
    final isActive = index == _currentStep.index.clamp(0, 2);
    final isPast = index < _currentStep.index.clamp(0, 2);
    
    return AnimatedDefaultTextStyle(
      duration: const Duration(milliseconds: 300),
      style: TextStyle(
        fontSize: isActive ? 14 : 12,
        fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
        color: isActive || isPast
            ? Colors.white
            : Colors.white.withOpacity(0.5),
      ),
      child: Text(label),
    );
  }

  Widget _buildStepContent() {
    switch (_currentStep) {
      case RegistrationStep.credentials:
        return _buildCredentialsStep();
      case RegistrationStep.personal:
        return _buildPersonalStep();
      case RegistrationStep.profile:
        return _buildProfileStep();
      case RegistrationStep.complete:
        return _buildCompleteStep();
    }
  }

  Widget _buildCredentialsStep() {
    return _buildGlassmorphicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.pink, Colors.purple],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.mail_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Adım 1/3',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          _buildModernInput(
            controller: _emailController,
            label: 'Email',
            hint: 'ornek@email.com',
            icon: Icons.email_outlined,
            keyboardType: TextInputType.emailAddress,
          ),
          const SizedBox(height: 16),

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
          ),
          
          // Password strength indicator
          if (_passwordController.text.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 12),
                Row(
                  children: [
                    Text(
                      _passwordStrengthLabel,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: _passwordStrengthColor,
                      ),
                    ),
                    const Spacer(),
                    ...List.generate(4, (index) {
                      return Container(
                        margin: const EdgeInsets.only(left: 4),
                        width: 40,
                        height: 6,
                        decoration: BoxDecoration(
                          color: index < (_passwordStrength * 4).ceil()
                              ? _passwordStrengthColor
                              : Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      );
                    }),
                  ],
                ),
              ],
            ),
          
          const SizedBox(height: 16),

          _buildModernInput(
            controller: _confirmPasswordController,
            label: 'Şifre Tekrar',
            hint: '••••••••',
            icon: Icons.lock_outline_rounded,
            obscureText: _obscureConfirmPassword,
            suffixIcon: IconButton(
              icon: Icon(
                _obscureConfirmPassword
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
                color: Colors.white.withOpacity(0.7),
                size: 22,
              ),
              onPressed: () {
                setState(() => _obscureConfirmPassword = !_obscureConfirmPassword);
              },
            ),
          ),
          const SizedBox(height: 20),

          _buildModernButton(
            text: 'Devam Et',
            onPressed: _nextStep,
            gradient: const LinearGradient(
              colors: [Colors.pink, Colors.purple],
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

          // Google Sign Up
          _buildOAuthButton(
            icon: Icons.g_mobiledata_rounded,
            label: 'Google ile Kayıt Ol',
            onPressed: _handleGoogleSignUp,
            iconColor: Colors.red.shade400,
          ),
          const SizedBox(height: 12),

          // Apple Sign Up
          _buildOAuthButton(
            icon: Icons.apple_rounded,
            label: 'Apple ile Kayıt Ol',
            onPressed: _handleAppleSignUp,
            iconColor: Colors.white,
          ),
          const SizedBox(height: 12),

          // Already have account
          Center(
            child: TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(
                'Zaten hesabım var',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.85),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.white.withOpacity(0.5),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPersonalStep() {
    return _buildGlassmorphicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.purple, Colors.blue],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.person_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Adım 2/3',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          _buildModernInput(
            controller: _fullNameController,
            label: 'Ad Soyad',
            hint: 'Ahmet Yılmaz',
            icon: Icons.person_outline_rounded,
          ),
          const SizedBox(height: 20),

          _buildModernButton(
            text: 'Devam Et',
            onPressed: _nextStep,
            gradient: const LinearGradient(
              colors: [Colors.purple, Colors.blue],
            ),
          ),
          const SizedBox(height: 12),
          
          _buildOutlineButton(
            text: 'Geri',
            onPressed: _previousStep,
          ),
        ],
      ),
    );
  }

  Widget _buildProfileStep() {
    return _buildGlassmorphicCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Colors.blue, Colors.cyan],
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.alternate_email_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              const Text(
                'Adım 3/3',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          
          _buildUsernameField(),
          const SizedBox(height: 20),

          if (_usernameStatus == 'taken')
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.orange.shade300,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange.shade200, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bu kullanıcı adı başka biri tarafından kullanılıyor.',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.orange.shade100,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          if (_usernameStatus == 'available')
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.2),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: Colors.green.shade300,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(Icons.check_circle_outline, color: Colors.green.shade200, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bu kullanıcı adı kullanılabilir!',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.green.shade100,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          const SizedBox(height: 20),

          _buildModernButton(
            text: 'Hesap Oluştur',
            onPressed: () {
              if (!_isLoading) _nextStep();
            },
            isLoading: _isLoading,
            gradient: const LinearGradient(
              colors: [Colors.blue, Colors.cyan],
            ),
          ),
          const SizedBox(height: 12),
          
          _buildOutlineButton(
            text: 'Geri',
            onPressed: _previousStep,
          ),
        ],
      ),
    );
  }

  Widget _buildCompleteStep() {
    return _buildGlassmorphicCard(
      child: Column(
        children: [
          // Success animation
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Colors.green, Colors.teal],
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.green.withOpacity(0.5),
                  blurRadius: 30,
                  spreadRadius: 10,
                ),
              ],
            ),
            child: const Icon(
              Icons.check_rounded,
              color: Colors.white,
              size: 60,
            ),
          ),
          const SizedBox(height: 32),
          
          const Text(
            'Kayıt Başarılı!',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 12),
          
          Text(
            'CizreApp ailesine hoş geldiniz! 🎉',
            style: TextStyle(
              fontSize: 16,
              color: Colors.white.withOpacity(0.85),
            ),
          ),
          const SizedBox(height: 20),
          
          Text(
            'Ana ekrana yönlendiriliyorsunuz...',
            style: TextStyle(
              fontSize: 14,
              color: Colors.white.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUsernameField() {
    return TextField(
      controller: _usernameController,
      style: const TextStyle(
        color: Colors.white,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      decoration: InputDecoration(
        labelText: 'Kullanıcı Adı',
        hintText: 'kullanici_adi',
        prefixIcon: Icon(
          Icons.alternate_email_rounded,
          color: Colors.white.withOpacity(0.8),
          size: 22,
        ),
        suffixIcon: _buildUsernameSuffixIcon(),
        filled: true,
        fillColor: Colors.white.withOpacity(0.15),
        labelStyle: TextStyle(
          color: Colors.white.withOpacity(0.85),
          fontWeight: FontWeight.w500,
        ),
        hintStyle: TextStyle(
          color: Colors.white.withOpacity(0.4),
        ),
        helperText: 'Kullanıcı adınız (değiştirilemez)',
        helperStyle: TextStyle(
          color: Colors.white.withOpacity(0.6),
          fontSize: 12,
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
      ),
      onChanged: (_) => _checkUsernameAvailability(),
    );
  }

  Widget? _buildUsernameSuffixIcon() {
    if (_isCheckingUsername) {
      return SizedBox(
        width: 20,
        height: 20,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(
              Colors.white.withOpacity(0.7),
            ),
          ),
        ),
      );
    }

    if (_usernameStatus == 'available') {
      return Icon(
        Icons.check_circle_rounded,
        color: Colors.green.shade300,
        size: 24,
      );
    }

    if (_usernameStatus == 'taken') {
      return Icon(
        Icons.cancel_rounded,
        color: Colors.orange.shade300,
        size: 24,
      );
    }

    return null;
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
  }) {
    return TextField(
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
      ),
    );
  }

  Widget _buildModernButton({
    required String text,
    required VoidCallback onPressed,
    Gradient gradient = const LinearGradient(
      colors: [Colors.pink, Colors.purple],
    ),
    bool isLoading = false,
  }) {
    return Container(
      height: 56,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        gradient: gradient,
        boxShadow: [
          BoxShadow(
            color: gradient.colors.first.withOpacity(0.5),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
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

  Widget _buildOutlineButton({
    required String text,
    required VoidCallback onPressed,
  }) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Colors.white.withOpacity(0.5),
          width: 2,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(16),
          child: Center(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _handleGoogleSignUp() async {
    setState(() => _isOAuthLoading = true);
    
    try {
      final response = await _authService.signInWithGoogle();
      if (response.user != null && mounted) {
        // Generate confetti
        _generateConfetti();
        _confettiController.forward();
        
        setState(() => _currentStep = RegistrationStep.complete);
        
        // Navigate after delay
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        _showError(_authService.translateOAuthError(e.toString()));
      }
    } finally {
      if (mounted) {
        setState(() => _isOAuthLoading = false);
      }
    }
  }

  Future<void> _handleAppleSignUp() async {
    setState(() => _isOAuthLoading = true);
    
    try {
      final response = await _authService.signInWithApple();
      if (response.user != null && mounted) {
        // Generate confetti
        _generateConfetti();
        _confettiController.forward();
        
        setState(() => _currentStep = RegistrationStep.complete);
        
        // Navigate after delay
        Future.delayed(const Duration(seconds: 3), () {
          if (mounted) {
            Navigator.of(context).pop();
          }
        });
      }
    } catch (e) {
      if (mounted) {
        _showError(_authService.translateOAuthError(e.toString()));
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

// Confetti particle model
class ConfettiParticle {
  final Offset position;
  final Offset velocity;
  final Color color;
  final double size;

  ConfettiParticle({
    required this.position,
    required this.velocity,
    required this.color,
    required this.size,
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

    paint.color = Colors.purple.withOpacity(0.15);
    canvas.drawCircle(blob1, 150, paint);

    paint.color = Colors.pink.withOpacity(0.15);
    canvas.drawCircle(blob2, 180, paint);

    paint.color = Colors.blue.withOpacity(0.15);
    canvas.drawCircle(blob3, 160, paint);
  }

  @override
  bool shouldRepaint(covariant MeshGradientPainter oldDelegate) {
    return oldDelegate.animation != animation;
  }
}

// Confetti painter
class ConfettiPainter extends CustomPainter {
  final List<ConfettiParticle> confetti;
  final double progress;

  ConfettiPainter({required this.confetti, required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    for (final particle in confetti) {
      final paint = Paint()
        ..color = particle.color.withOpacity(1 - progress)
        ..style = PaintingStyle.fill;

      final offset = Offset(
        particle.position.dx + particle.velocity.dx * progress * 10,
        particle.position.dy + particle.velocity.dy * progress * 10 + progress * 200,
      );

      canvas.drawCircle(offset, particle.size * (1 - progress * 0.5), paint);
    }
  }

  @override
  bool shouldRepaint(covariant ConfettiPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}
