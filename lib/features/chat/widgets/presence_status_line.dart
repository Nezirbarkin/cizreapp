import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/chat_presence.dart';
import '../services/presence_tracker.dart';

/// [PresenceStatusLine]'ın renk takımı.
enum PresenceLineStyle {
  /// Renkli AppBar üstünde (sohbet başlığı): beyaz tonları.
  onDark,

  /// Beyaz zeminde (profil): yeşil "çevrimiçi", gri "son görülme".
  onLight,
}

/// "çevrimiçi" / "son görülme dün 21:10" / "yazıyor…" satırı.
///
/// Neyin gösterileceğine SUNUCU karar verir (bkz. [PresenceTracker]); satır
/// gösterilecek bir şey yoksa hiç yer kaplamaz. [typing] verilir ve true olursa
/// diğer her şeyin önüne geçer.
class PresenceStatusLine extends StatefulWidget {
  const PresenceStatusLine({
    super.key,
    required this.userId,
    this.presenceContext = PresenceContext.chat,
    this.typing,
    this.style = PresenceLineStyle.onDark,
    this.fontSize = 12,
    this.showClockIcon = false,
    this.tracker,
  });

  final String userId;
  final PresenceContext presenceContext;

  /// true iken "yazıyor…" gösterilir.
  final ValueListenable<bool>? typing;

  final PresenceLineStyle style;
  final double fontSize;

  /// Son görülmenin önünde küçük saat simgesi.
  final bool showClockIcon;

  /// Dışarıdan verilirse kullanılır ve ÇAĞIRAN yönetir (start/dispose). Test ve
  /// aynı durumu birden çok yerde göstermek içindir.
  final PresenceTracker? tracker;

  @override
  State<PresenceStatusLine> createState() => _PresenceStatusLineState();
}

class _PresenceStatusLineState extends State<PresenceStatusLine> {
  late PresenceTracker _tracker;
  bool _ownsTracker = false;

  @override
  void initState() {
    super.initState();
    _attach();
  }

  void _attach() {
    final external = widget.tracker;
    if (external != null) {
      _tracker = external;
      _ownsTracker = false;
      return;
    }
    _tracker = PresenceTracker(
      widget.userId,
      context: widget.presenceContext,
    );
    _ownsTracker = true;
    _tracker.start();
  }

  void _detach() {
    if (_ownsTracker) _tracker.dispose();
  }

  @override
  void didUpdateWidget(covariant PresenceStatusLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.userId != widget.userId ||
        oldWidget.presenceContext != widget.presenceContext ||
        oldWidget.tracker != widget.tracker) {
      _detach();
      _attach();
    }
  }

  @override
  void dispose() {
    _detach();
    super.dispose();
  }

  Color get _textColor => switch (widget.style) {
    PresenceLineStyle.onDark => Colors.white.withValues(alpha: 0.82),
    PresenceLineStyle.onLight => const Color(0xFF6B7280),
  };

  Color get _onlineColor => switch (widget.style) {
    PresenceLineStyle.onDark => const Color(0xFFB9F6CA),
    PresenceLineStyle.onLight => const Color(0xFF16A34A),
  };

  Color get _dotColor => switch (widget.style) {
    PresenceLineStyle.onDark => const Color(0xFF69F0AE),
    PresenceLineStyle.onLight => const Color(0xFF22C55E),
  };

  Color get _typingColor => switch (widget.style) {
    PresenceLineStyle.onDark => Colors.white,
    PresenceLineStyle.onLight => const Color(0xFF7C3AED),
  };

  @override
  Widget build(BuildContext context) {
    final typing = widget.typing;
    return ListenableBuilder(
      listenable: typing == null
          ? _tracker
          : Listenable.merge([_tracker, typing]),
      builder: (context, _) {
        final isTyping = typing?.value ?? false;
        final label = _tracker.label;
        final Widget line;
        final String kind;

        if (isTyping) {
          kind = 'typing';
          line = TypingIndicatorText(
            text: PresenceLabels.typing,
            color: _typingColor,
            fontSize: widget.fontSize,
          );
        } else if (_tracker.isOnline) {
          kind = 'online';
          line = _statusRow(
            leading: _Dot(color: _dotColor),
            text: PresenceLabels.online,
            color: _onlineColor,
            weight: FontWeight.w600,
          );
        } else if (label != null) {
          kind = 'seen';
          line = _statusRow(
            leading: widget.showClockIcon
                ? Icon(
                    Icons.schedule_rounded,
                    size: widget.fontSize + 1,
                    color: _textColor,
                  )
                : null,
            text: label,
            color: _textColor,
          );
        } else {
          kind = 'none';
          line = const SizedBox(width: 0, height: 0);
        }

        return AnimatedSize(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          alignment: Alignment.topLeft,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: KeyedSubtree(key: ValueKey(kind), child: line),
          ),
        );
      },
    );
  }

  Widget _statusRow({
    Widget? leading,
    required String text,
    required Color color,
    FontWeight weight = FontWeight.w400,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leading != null) ...[leading, const SizedBox(width: 5)],
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: widget.fontSize,
              color: color,
              fontWeight: weight,
              height: 1.15,
            ),
          ),
        ),
      ],
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    width: 7,
    height: 7,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

/// "yazıyor" + sırayla yanıp sönen üç nokta.
class TypingIndicatorText extends StatefulWidget {
  const TypingIndicatorText({
    super.key,
    required this.text,
    required this.color,
    this.fontSize = 12,
  });

  final String text;
  final Color color;
  final double fontSize;

  @override
  State<TypingIndicatorText> createState() => _TypingIndicatorTextState();
}

class _TypingIndicatorTextState extends State<TypingIndicatorText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Üç nokta sırayla yanıp söner: her nokta bir öncekinden 0,18 devir geç.
  double _dotOpacity(int index) {
    final t = (_controller.value - index * 0.18) % 1.0;
    final triangle = t < 0.5 ? t * 2 : (1 - t) * 2; // 0 → 1 → 0
    return 0.25 + 0.75 * triangle;
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Text(
            widget.text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: widget.fontSize,
              color: widget.color,
              fontWeight: FontWeight.w600,
              height: 1.15,
            ),
          ),
        ),
        const SizedBox(width: 3),
        AnimatedBuilder(
          animation: _controller,
          builder: (context, _) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(right: 2),
                  child: Opacity(
                    opacity: _dotOpacity(i),
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: BoxDecoration(
                        color: widget.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
