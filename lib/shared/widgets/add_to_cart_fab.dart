// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

/// Ürün kartlarında kullanılan, dikkat çekici dairesel "sepete ekle" (+) butonu.
/// Basılınca kısa bir "sıçrama" animasyonu yapar.
class AddToCartFab extends StatefulWidget {
  final VoidCallback? onPressed;
  final bool isLoading;
  final double size;

  const AddToCartFab({
    super.key,
    required this.onPressed,
    this.isLoading = false,
    this.size = 32,
  });

  @override
  State<AddToCartFab> createState() => _AddToCartFabState();
}

class _AddToCartFabState extends State<AddToCartFab> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
      lowerBound: 0.85,
      upperBound: 1.0,
      value: 1.0,
    );
    _scale = _controller;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDisabled = widget.onPressed == null;

    return GestureDetector(
      onTapDown: isDisabled ? null : (_) => _controller.reverse(),
      onTapUp: isDisabled ? null : (_) => _controller.forward(),
      onTapCancel: isDisabled ? null : () => _controller.forward(),
      onTap: widget.onPressed,
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: widget.size,
          height: widget.size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: isDisabled
                ? null
                : LinearGradient(
                    colors: [theme.colorScheme.primary, theme.colorScheme.primary.withOpacity(0.75)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            color: isDisabled ? Colors.grey.shade300 : null,
            boxShadow: isDisabled
                ? null
                : [
                    BoxShadow(
                      color: theme.colorScheme.primary.withOpacity(0.4),
                      blurRadius: 8,
                      offset: const Offset(0, 3),
                    ),
                  ],
          ),
          child: widget.isLoading
              ? Padding(
                  padding: EdgeInsets.all(widget.size * 0.26),
                  child: const CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Icon(Icons.add, color: Colors.white, size: widget.size * 0.6),
        ),
      ),
    );
  }
}
