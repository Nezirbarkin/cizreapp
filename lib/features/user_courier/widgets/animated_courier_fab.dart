import 'package:flutter/material.dart';

class AnimatedCourierFab extends StatefulWidget {
  final VoidCallback onTap;

  const AnimatedCourierFab({super.key, required this.onTap});

  @override
  State<AnimatedCourierFab> createState() => _AnimatedCourierFabState();
}

class _AnimatedCourierFabState extends State<AnimatedCourierFab>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _floatingAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();

    _floatingAnimation = Tween<Offset>(
      begin: const Offset(0, 0),
      end: const Offset(0, -10),
    ).animate(CurvedAnimation(parent: _animationController, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _floatingAnimation,
      child: FloatingActionButton(
        backgroundColor: const Color(0xFFFF6B00),
        elevation: 8,
        onPressed: widget.onTap,
        tooltip: 'Kargo Gönder',
        child: const Icon(
          Icons.two_wheeler,
          color: Colors.white,
          size: 28,
        ),
      ),
    );
  }
}
