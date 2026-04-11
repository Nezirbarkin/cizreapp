import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

class FloatingMessageButton extends StatelessWidget {
  final VoidCallback? onTap;
  final int unreadCount;
  final bool show;

  const FloatingMessageButton({
    super.key,
    this.onTap,
    this.unreadCount = 0,
    this.show = true,
  });

  @override
  Widget build(BuildContext context) {
    if (!show) return const SizedBox.shrink();

    final primaryColor = Theme.of(context).colorScheme.primary;

    // Web ve mobil için farklı konumlandırma
    final double rightPosition = kIsWeb ? 28 : 20;
    final double bottomPosition = kIsWeb ? 100 : 140;

    return Positioned(
      right: rightPosition,
      bottom: bottomPosition,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                // ignore: deprecated_member_use
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(
                Icons.chat_bubble_outline,
                color: primaryColor,
                size: 28,
              ),
              if (unreadCount > 0)
                Positioned(
                  top: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF3D00),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: primaryColor,
                        width: 2,
                      ),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 18,
                      minHeight: 18,
                    ),
                    child: Text(
                      unreadCount > 9 ? '9+' : '$unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
