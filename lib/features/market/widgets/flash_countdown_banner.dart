// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Flash satış için canlı geri sayım banner'ı.
/// "03:45:12" formatında saat:dakika:saniye gösterir, süre dolunca "SÜRE DOLDU".
class FlashCountdownBanner extends StatefulWidget {
  final DateTime endAt;
  final String? title;
  final VoidCallback? onTap;

  const FlashCountdownBanner({
    super.key,
    required this.endAt,
    this.title = '⚡ Flash Satış',
    this.onTap,
  });

  @override
  State<FlashCountdownBanner> createState() => _FlashCountdownBannerState();
}

class _FlashCountdownBannerState extends State<FlashCountdownBanner> {
  Timer? _timer;
  Duration _remaining = Duration.zero;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _updateRemaining();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (_disposed) return;
      _updateRemaining();
    });
  }

  void _updateRemaining() {
    final now = DateTime.now();
    final diff = widget.endAt.difference(now);
    if (diff.isNegative) {
      setState(() => _remaining = Duration.zero);
      _timer?.cancel();
    } else {
      setState(() => _remaining = diff);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    super.dispose();
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final isOver = _remaining == Duration.zero;
    final hours = _remaining.inHours;
    final minutes = _remaining.inMinutes.remainder(60);
    final seconds = _remaining.inSeconds.remainder(60);

    return GestureDetector(
      onTap: isOver ? null : widget.onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: isOver
                ? [Colors.grey.shade600, Colors.grey.shade700]
                : [const Color(0xFFFF5252), const Color(0xFFE53935)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.3),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              isOver ? Icons.timer_off : Icons.bolt,
              color: Colors.white,
              size: 20,
            )
                .animate(onPlay: (c) => c.repeat(reverse: true))
                .fadeIn(duration: 300.ms)
                .then()
                .shimmer(duration: 700.ms, color: Colors.white54),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.title!,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                  Text(
                    isOver ? 'Süre doldu' : 'Fırsat bitmesine:',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.9),
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            ),
            if (!isOver)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _timeBox(_twoDigits(hours)),
                  const _Colon(),
                  _timeBox(_twoDigits(minutes)),
                  const _Colon(),
                  _timeBox(_twoDigits(seconds)),
                ],
              )
            else
              const Text(
                'BİTTİ',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _timeBox(String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.35),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        value,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 13,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _Colon extends StatelessWidget {
  const _Colon();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: Text(
        ':',
        style: TextStyle(
          color: Colors.white.withOpacity(0.9),
          fontWeight: FontWeight.bold,
          fontSize: 13,
        ),
      ),
    );
  }
}