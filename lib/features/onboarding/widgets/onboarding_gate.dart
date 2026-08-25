import 'package:flutter/material.dart';

import '../../../core/services/onboarding_service.dart';
import '../screens/onboarding_screen.dart';

/// Uygulama ilk açıldığında tanıtım ekranını, daha sonraki açılışlarda
/// doğrudan [child] ekranını gösterir.
class OnboardingGate extends StatefulWidget {
  final Widget child;

  const OnboardingGate({super.key, required this.child});

  @override
  State<OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<OnboardingGate> {
  bool? _showOnboarding;

  @override
  void initState() {
    super.initState();
    OnboardingService.hasSeenOnboarding().then((seen) {
      if (mounted) setState(() => _showOnboarding = !seen);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_showOnboarding == null) {
      // Tercih okunurken kısa bir an için boş bir yüzey göster; MainScreen
      // altta hazırlanıyor olsa da tanıtım/ana ekran "zıplaması" önlenir.
      return const Scaffold(body: SizedBox.shrink());
    }

    if (_showOnboarding == true) {
      return OnboardingScreen(
        onFinished: () => setState(() => _showOnboarding = false),
      );
    }

    return widget.child;
  }
}
