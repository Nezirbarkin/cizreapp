import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/services/onboarding_service.dart';
import '../../../core/theme/app_theme.dart';

class _OnboardingStep {
  final IconData icon;
  final String title;
  final String description;
  final Color color;

  const _OnboardingStep({
    required this.icon,
    required this.title,
    required this.description,
    required this.color,
  });
}

const _steps = [
  _OnboardingStep(
    icon: Icons.storefront_rounded,
    title: "CizreApp'e Hoş Geldiniz",
    description:
        "Cizre'nin dijital pazarı ve sosyal ağı tek uygulamada. "
        'Birkaç adımda neler yapabileceğinizi gösterelim.',
    color: AppTheme.primaryGreen,
  ),
  _OnboardingStep(
    icon: Icons.shopping_bag_rounded,
    title: 'Dijital Sipariş Verin',
    description:
        'Şehrinizdeki mağaza ve satıcıların ürünlerine göz atın, '
        'sepetinize ekleyin ve kolayca dijital sipariş verin.',
    color: AppTheme.secondaryGreen,
  ),
  _OnboardingStep(
    icon: Icons.campaign_rounded,
    title: 'İlan Verin, İlanlara Göz Atın',
    description:
        'Alım, satım, kiralık ve iş ilanlarını inceleyin; kendi '
        'ilanınızı da dakikalar içinde yayınlayın.',
    color: AppTheme.orange,
  ),
  _OnboardingStep(
    icon: Icons.groups_rounded,
    title: 'Sosyal Ağda Paylaşın',
    description:
        'Gönderi ve hikaye paylaşın, çevrenizdekileri takip edin, '
        'beğenip yorum yaparak sohbete katılın.',
    color: AppTheme.primaryBlue,
  ),
  _OnboardingStep(
    icon: Icons.local_shipping_rounded,
    title: 'Kurye Çağırın',
    description:
        'Paketinizi göndermek için kurye çağırın, teslimatınızı '
        'haritada anlık olarak takip edin.',
    color: AppTheme.info,
  ),
  _OnboardingStep(
    icon: Icons.directions_bus_filled_rounded,
    title: 'Şehiriçi Servislerden Yararlanın',
    description:
        'Şehiriçi otobüs hatlarını inceleyin, sık kullandıklarınızı '
        'favorileyin ve araçları canlı haritada takip edin.',
    color: AppTheme.secondaryBlue,
  ),
];

/// Uygulamanın ilk açılışında tek seferlik gösterilen adım adım tanıtım
/// ekranı. Görüldükten sonra [OnboardingService] ile işaretlenir ve bir
/// daha gösterilmez.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onFinished;

  const OnboardingScreen({super.key, required this.onFinished});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _pageController = PageController();
  int _index = 0;

  bool get _isLastStep => _index == _steps.length - 1;
  Color get _accent => _steps[_index].color;

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await OnboardingService.markOnboardingSeen();
    widget.onFinished();
  }

  void _next() {
    if (_isLastStep) {
      _finish();
      return;
    }
    _pageController.nextPage(
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.bgWhite,
      body: Stack(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 450),
            curve: Curves.easeOut,
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.3, -0.6),
                radius: 1.3,
                colors: [
                  _accent.withValues(alpha: 0.16),
                  AppTheme.bgWhite,
                ],
              ),
            ),
          ),
          Positioned.fill(
            child: IgnorePointer(
              child: _FloatingBlobs(color: _accent),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Align(
                  alignment: Alignment.topRight,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 200),
                      opacity: _isLastStep ? 0 : 1,
                      child: IgnorePointer(
                        ignoring: _isLastStep,
                        child: TextButton(
                          onPressed: _finish,
                          child: const Text(
                            'Geç',
                            style: TextStyle(
                              color: AppTheme.gray500,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _steps.length,
                    onPageChanged: (i) => setState(() => _index = i),
                    itemBuilder: (context, i) {
                      return AnimatedBuilder(
                        animation: _pageController,
                        builder: (context, child) {
                          double page = i.toDouble();
                          if (_pageController.hasClients &&
                              _pageController.position.haveDimensions) {
                            page = _pageController.page ?? i.toDouble();
                          }
                          final delta = (page - i).clamp(-1.0, 1.0);
                          final scale = 1 - (delta.abs() * 0.12);
                          final opacity = 1 - (delta.abs() * 0.5);
                          return Transform.scale(
                            scale: scale,
                            child: Opacity(
                              opacity: opacity.clamp(0.0, 1.0),
                              child: child,
                            ),
                          );
                        },
                        child: _StepView(step: _steps[i]),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _steps.length,
                      (i) => AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        curve: Curves.easeOut,
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == _index ? 22 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == _index ? _accent : AppTheme.gray200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
                  child: _NextButton(
                    label: _isLastStep ? 'Başlayalım' : 'Devam Et',
                    color: _accent,
                    onTap: _next,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Yumuşak, sürekli süzülen arkaplan lekeleri. Ekranı canlı tutar,
/// dokunma olaylarını etkilemez ([IgnorePointer] ile sarmalanır).
class _FloatingBlobs extends StatefulWidget {
  final Color color;

  const _FloatingBlobs({required this.color});

  @override
  State<_FloatingBlobs> createState() => _FloatingBlobsState();
}

class _FloatingBlobsState extends State<_FloatingBlobs>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * 2 * math.pi;
        return Stack(
          children: [
            Positioned(
              top: 40 + math.sin(t) * 16,
              right: -60 + math.cos(t) * 12,
              child: _blob(220, 0.10),
            ),
            Positioned(
              bottom: 60 + math.cos(t) * 18,
              left: -70 + math.sin(t) * 14,
              child: _blob(260, 0.08),
            ),
          ],
        );
      },
    );
  }

  Widget _blob(double size, double alpha) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 450),
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: widget.color.withValues(alpha: alpha),
        shape: BoxShape.circle,
      ),
    );
  }
}

class _NextButton extends StatefulWidget {
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _NextButton({
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  State<_NextButton> createState() => _NextButtonState();
}

class _NextButtonState extends State<_NextButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        duration: const Duration(milliseconds: 120),
        scale: _pressed ? 0.96 : 1,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          width: double.infinity,
          height: 52,
          decoration: BoxDecoration(
            color: widget.color,
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          alignment: Alignment.center,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 200),
            child: Text(
              widget.label,
              key: ValueKey(widget.label),
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
}

class _StepView extends StatefulWidget {
  final _OnboardingStep step;

  const _StepView({required this.step});

  @override
  State<_StepView> createState() => _StepViewState();
}

class _StepViewState extends State<_StepView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 550),
  );
  late final Animation<double> _fade = CurvedAnimation(
    parent: _controller,
    curve: const Interval(0, 0.7, curve: Curves.easeOut),
  );
  late final Animation<Offset> _slide = Tween(
    begin: const Offset(0, 0.08),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
  late final Animation<double> _iconScale = Tween(
    begin: 0.6,
    end: 1.0,
  ).animate(
    CurvedAnimation(parent: _controller, curve: Curves.easeOutBack),
  );

  @override
  void initState() {
    super.initState();
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = widget.step;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 32),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          ScaleTransition(
            scale: _iconScale,
            child: _PulsingHalo(
              color: step.color,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  color: step.color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(step.icon, size: 64, color: step.color),
              ),
            ),
          ),
          const SizedBox(height: 40),
          FadeTransition(
            opacity: _fade,
            child: SlideTransition(
              position: _slide,
              child: Column(
                children: [
                  Text(
                    step.title,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w800,
                      color: AppTheme.gray900,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    step.description,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 15,
                      height: 1.5,
                      color: AppTheme.gray600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// İkonun arkasında yavaşça nefes alan halka; ekranı canlı tutar.
class _PulsingHalo extends StatefulWidget {
  final Color color;
  final Widget child;

  const _PulsingHalo({required this.color, required this.child});

  @override
  State<_PulsingHalo> createState() => _PulsingHaloState();
}

class _PulsingHaloState extends State<_PulsingHalo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1800),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final scale = 1 + (_controller.value * 0.12);
        return Stack(
          alignment: Alignment.center,
          children: [
            Transform.scale(
              scale: scale,
              child: Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: widget.color.withValues(
                      alpha: 0.25 * (1 - _controller.value),
                    ),
                    width: 2,
                  ),
                ),
              ),
            ),
            child!,
          ],
        );
      },
      child: widget.child,
    );
  }
}
