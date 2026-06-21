// ignore_for_file: deprecated_member_use

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../features/ai_chat/screens/ai_chat_meta_screen.dart';

/// Animasyonlu yapay zeka sohbet floating button.
///
/// MarketScreen'deki mesaj butonunun hemen üstüne yerleştirilir.
/// Pulse + glow + dönen gradient animasyonu ile dikkat çeker.
class FloatingAIChatButton extends StatefulWidget {
  final VoidCallback? onTap;
  final bool show;

  const FloatingAIChatButton({
    super.key,
    this.onTap,
    this.show = true,
  });

  @override
  State<FloatingAIChatButton> createState() => _FloatingAIChatButtonState();
}

class _FloatingAIChatButtonState extends State<FloatingAIChatButton>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _glowController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();

    // Pulse: ölçek 1.0 ↔ 1.08
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.08).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    // Glow: dış parıltı
    _glowController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);
    _glowAnimation = Tween<double>(begin: 0.35, end: 0.7).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _glowController.dispose();
    super.dispose();
  }

  void _openNewChat() {
    // Direkt yeni sohbet ekranına git - Meta AI tarzı
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const AIMetaScreen(conversationId: null),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.show) return const SizedBox.shrink();

    // FloatingMessageButton ile hizalı konum: mesaj butonunun üstünde
    final double rightPosition = kIsWeb ? 28 : 20;
    // Mesaj butonu 56px + aralık (mesaj butonu bottom 140/100, AI butonu ~76px üstte)
    final double bottomPosition = kIsWeb ? 172 : 212;

    return Positioned(
      right: rightPosition,
      bottom: bottomPosition,
      child: AnimatedBuilder(
        animation: Listenable.merge([_pulseAnimation, _glowAnimation]),
        builder: (context, child) {
          return Transform.scale(
            scale: _pulseAnimation.value,
            child: GestureDetector(
              onTap: widget.onTap ?? _openNewChat,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  // Dış glow halkası
                  Positioned.fill(
                    child: Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: const RadialGradient(
                          colors: [
                            Color(0xFF6C5CE7),
                            Color(0x006C5CE7),
                          ],
                          stops: [0.5, 1.0],
                        ),
                        // ignore: deprecated_member_use
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFF6C5CE7)
                                // ignore: deprecated_member_use
                                .withOpacity(_glowAnimation.value),
                            blurRadius: 18,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Ana buton gövdesi (gradient)
                  Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          Color(0xFF6C5CE7), // mor
                          Color(0xFF00CEC9), // turkuaz
                        ],
                      ),
                      border: Border.all(color: Colors.white, width: 2.5),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: const Stack(
                      alignment: Alignment.center,
                      children: [
                        // Yapay zeka yıldız ikonu
                        Icon(
                          Icons.auto_awesome,
                          color: Colors.white,
                          size: 24,
                        ),
                        // Küçük parıltı noktası (sağ üst)
                        Positioned(
                          top: 10,
                          right: 11,
                          child: Icon(
                            Icons.brightness_1,
                            color: Colors.white,
                            size: 6,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}