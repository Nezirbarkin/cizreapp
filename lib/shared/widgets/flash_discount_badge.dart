// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

/// "2 al biri bakiye" kampanyalı ürünlerde gösterilen küçük rozet
class CampaignBadge extends StatelessWidget {
  const CampaignBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.green.shade600,
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Text(
        '2 Al 1 Bakiye',
        style: TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.bold),
      ),
    );
  }
}

/// Ürün kartlarında gösterilen animasyonlu "flaş indirim" rozeti.
/// Hafif nabız (pulse) ve parlama efektiyle dikkat çeker.
class FlashDiscountBadge extends StatefulWidget {
  final int percentage;
  final bool compact;

  const FlashDiscountBadge({
    super.key,
    required this.percentage,
    this.compact = false,
  });

  @override
  State<FlashDiscountBadge> createState() => _FlashDiscountBadgeState();
}

class _FlashDiscountBadgeState extends State<FlashDiscountBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);
  }

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
        final t = _controller.value;
        final scale = 1.0 + (t * 0.08);
        final glow = 0.25 + (t * 0.35);
        return Transform.scale(
          scale: scale,
          child: Container(
            padding: EdgeInsets.symmetric(
              horizontal: widget.compact ? 5 : 8,
              vertical: widget.compact ? 2 : 4,
            ),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF5252), Color(0xFFE53935)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(widget.compact ? 4 : 6),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(glow),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.bolt, color: Colors.white, size: widget.compact ? 9 : 12),
                const SizedBox(width: 2),
                Text(
                  widget.compact ? '%${widget.percentage}' : '%${widget.percentage} İndirim',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: widget.compact ? 8 : 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
