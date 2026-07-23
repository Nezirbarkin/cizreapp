import 'package:flutter/material.dart';

class AnimatedCourierFab extends StatelessWidget {
  final VoidCallback onTap;

  const AnimatedCourierFab({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      backgroundColor: const Color(0xFFFF6B00),
      elevation: 8,
      onPressed: onTap,
      tooltip: 'Kargo Gönder',
      heroTag: 'courier_fab',
      child: const Icon(
        Icons.two_wheeler,
        color: Colors.white,
        size: 28,
      ),
    );
  }
}
