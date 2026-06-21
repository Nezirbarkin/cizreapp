// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../theme/ai_chat_theme.dart';

/// Modern AI Hoşgeldin Kartı - Gemini Tarzı
/// Yarı saydam gradient kart, animasyonlu avatar
class AIWelcomeCard extends StatefulWidget {
  final String userName;
  final VoidCallback? onGetStarted;
  final List<String>? suggestedQuestions;

  const AIWelcomeCard({
    super.key,
    this.userName = '',
    this.onGetStarted,
    this.suggestedQuestions,
  });

  @override
  State<AIWelcomeCard> createState() => _AIWelcomeCardState();
}

class _AIWelcomeCardState extends State<AIWelcomeCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AIChatTheme.animationSlow,
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOut),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final greeting = widget.userName.isNotEmpty
        ? 'Merhaba ${widget.userName}! 👋'
        : 'Merhaba! 👋';

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: Container(
          margin: const EdgeInsets.all(AIChatTheme.paddingL),
          padding: const EdgeInsets.all(AIChatTheme.paddingXL),
          decoration: AIChatTheme.welcomeCardDecoration,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // AI Avatar
              _buildAIAvatar(),
              const SizedBox(height: AIChatTheme.paddingL),

              // Hoşgeldin mesajı
              Text(
                greeting,
                style: AIChatTheme.headlineMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AIChatTheme.paddingS),

              // Alt mesaj
              Text(
                'Size nasıl yardımcı olabilirim?',
                style: AIChatTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: AIChatTheme.paddingL),

              // Önerilen sorular
              if (widget.suggestedQuestions != null &&
                  widget.suggestedQuestions!.isNotEmpty)
                _buildSuggestedQuestions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAIAvatar() {
    return Container(
      width: 80,
      height: 80,
      decoration: BoxDecoration(
        gradient: AIChatTheme.primaryGradient,
        shape: BoxShape.circle,
        boxShadow: AIChatTheme.glowShadow(AIChatTheme.primaryGradientStart),
      ),
      child: const Icon(
        Icons.auto_awesome,
        size: 40,
        color: Colors.white,
      ),
    );
  }

  Widget _buildSuggestedQuestions() {
    return Wrap(
      spacing: AIChatTheme.paddingS,
      runSpacing: AIChatTheme.paddingS,
      alignment: WrapAlignment.center,
      children: widget.suggestedQuestions!.take(4).map((question) {
        return _buildSuggestionChip(question);
      }).toList(),
    );
  }

  Widget _buildSuggestionChip(String question) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onGetStarted,
        borderRadius: BorderRadius.circular(AIChatTheme.radiusRound),
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AIChatTheme.paddingM,
            vertical: AIChatTheme.paddingS,
          ),
          decoration: BoxDecoration(
            color: AIChatTheme.cardBackgroundLight,
            borderRadius: BorderRadius.circular(AIChatTheme.radiusRound),
            border: Border.all(
              color: AIChatTheme.primaryGradientStart.withOpacity(0.3),
            ),
          ),
          child: Text(
            question,
            style: AIChatTheme.bodySmall.copyWith(
              color: AIChatTheme.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Basit hoşgeldin kartı (sadece metin)
class AISimpleWelcomeCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;

  const AISimpleWelcomeCard({
    super.key,
    this.title = 'AI Asistan',
    this.subtitle = 'Size nasıl yardımcı olabilirim?',
    this.icon = Icons.auto_awesome,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(
        horizontal: AIChatTheme.paddingL,
        vertical: AIChatTheme.paddingM,
      ),
      padding: const EdgeInsets.all(AIChatTheme.paddingL),
      decoration: AIChatTheme.cardDecoration,
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: AIChatTheme.primaryGradient,
              borderRadius: BorderRadius.circular(AIChatTheme.radiusMedium),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: AIChatTheme.iconSizeMedium,
            ),
          ),
          const SizedBox(width: AIChatTheme.paddingM),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AIChatTheme.titleMedium,
                ),
                const SizedBox(height: AIChatTheme.paddingXS),
                Text(
                  subtitle,
                  style: AIChatTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
