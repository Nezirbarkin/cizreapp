// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../theme/ai_chat_theme.dart';

/// Modern AI Mesaj Balonu - Gemini Tarzı
class AIMessageBubble extends StatelessWidget {
  final String message;
  final bool isUser;
  final bool isLoading;
  final DateTime? timestamp;
  final VoidCallback? onCopy;
  final VoidCallback? onRegenerate;

  const AIMessageBubble({
    super.key,
    required this.message,
    this.isUser = false,
    this.isLoading = false,
    this.timestamp,
    this.onCopy,
    this.onRegenerate,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AIChatTheme.paddingL,
        vertical: AIChatTheme.paddingS,
      ),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!isUser) ...[
            _buildAIAvatar(),
            const SizedBox(width: AIChatTheme.paddingS),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                if (isUser)
                  _buildUserBubble()
                else if (isLoading)
                  _buildLoadingBubble()
                else
                  _buildAIBubble(),
                if (!isUser && !isLoading && timestamp != null)
                  Padding(
                    padding: const EdgeInsets.only(
                      top: AIChatTheme.paddingXS,
                      left: AIChatTheme.paddingS,
                    ),
                    child: Text(
                      _formatTime(timestamp!),
                      style: AIChatTheme.bodySmall.copyWith(
                        fontSize: 10,
                        color: AIChatTheme.textMuted,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (isUser) ...[
            const SizedBox(width: AIChatTheme.paddingS),
            _buildUserAvatar(),
          ],
        ],
      ),
    );
  }

  Widget _buildAIAvatar() {
    return Container(
      width: AIChatTheme.aiAvatarSize,
      height: AIChatTheme.aiAvatarSize,
      decoration: BoxDecoration(
        gradient: AIChatTheme.primaryGradient,
        shape: BoxShape.circle,
        boxShadow: AIChatTheme.glowShadow(AIChatTheme.primaryGradientStart),
      ),
      child: const Icon(
        Icons.auto_awesome,
        size: AIChatTheme.iconSizeSmall,
        color: Colors.white,
      ),
    );
  }

  Widget _buildUserAvatar() {
    return Container(
      width: AIChatTheme.userAvatarSize,
      height: AIChatTheme.userAvatarSize,
      decoration: const BoxDecoration(
        color: AIChatTheme.userBubbleColor,
        shape: BoxShape.circle,
      ),
      child: const Icon(
        Icons.person,
        size: AIChatTheme.iconSizeSmall,
        color: Colors.white,
      ),
    );
  }

  Widget _buildUserBubble() {
    return Container(
      constraints: const BoxConstraints(
        maxWidth: AIChatTheme.messageMaxWidth,
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AIChatTheme.paddingL,
        vertical: AIChatTheme.paddingM,
      ),
      decoration: AIChatTheme.userBubbleDecoration,
      child: Text(
        message,
        style: AIChatTheme.bodyLarge.copyWith(
          color: Colors.white,
        ),
      ),
    );
  }

  Widget _buildAIBubble() {
    return Container(
      constraints: const BoxConstraints(
        maxWidth: AIChatTheme.messageMaxWidth + 40,
      ),
      decoration: AIChatTheme.aiBubbleDecoration,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(AIChatTheme.paddingL),
            child: MarkdownBody(
              data: message,
              styleSheet: MarkdownStyleSheet(
                p: AIChatTheme.bodyLarge,
                h1: AIChatTheme.headlineMedium,
                h2: AIChatTheme.titleLarge,
                h3: AIChatTheme.titleMedium,
                code: AIChatTheme.bodyMedium.copyWith(
                  fontFamily: 'monospace',
                  backgroundColor: AIChatTheme.cardBackgroundLight,
                ),
                codeblockDecoration: BoxDecoration(
                  color: AIChatTheme.cardBackgroundLight,
                  borderRadius: BorderRadius.circular(AIChatTheme.radiusMedium),
                ),
                blockquoteDecoration: BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: AIChatTheme.primaryGradientStart,
                      width: 3,
                    ),
                  ),
                ),
                listBullet: AIChatTheme.bodyLarge,
                a: AIChatTheme.bodyLarge.copyWith(
                  color: AIChatTheme.primaryGradientEnd,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
          // Action buttons
          Container(
            padding: const EdgeInsets.only(
              left: AIChatTheme.paddingS,
              bottom: AIChatTheme.paddingS,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (onCopy != null)
                  _buildActionButton(
                    icon: Icons.copy_rounded,
                    onTap: onCopy!,
                    tooltip: 'Kopyala',
                  ),
                if (onRegenerate != null)
                  _buildActionButton(
                    icon: Icons.refresh_rounded,
                    onTap: onRegenerate!,
                    tooltip: 'Yeniden oluştur',
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingBubble() {
    return Container(
      constraints: const BoxConstraints(
        maxWidth: AIChatTheme.messageMaxWidth,
      ),
      padding: const EdgeInsets.all(AIChatTheme.paddingXL),
      decoration: AIChatTheme.aiBubbleDecoration,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TypingIndicator(),
          const SizedBox(width: AIChatTheme.paddingM),
          Text(
            'Düşünüyor...',
            style: AIChatTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AIChatTheme.radiusSmall),
        child: Padding(
          padding: const EdgeInsets.all(AIChatTheme.paddingS),
          child: Icon(
            icon,
            size: AIChatTheme.iconSizeSmall,
            color: AIChatTheme.textMuted,
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final hour = time.hour.toString().padLeft(2, '0');
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

/// Yazıyor göstergesi animasyonu
class _TypingIndicator extends StatefulWidget {
  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with TickerProviderStateMixin {
  late List<AnimationController> _controllers;
  late List<Animation<double>> _animations;

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(
      3,
      (index) => AnimationController(
        duration: AIChatTheme.typingAnimation,
        vsync: this,
      ),
    );

    _animations = _controllers.map((controller) {
      return Tween<double>(begin: 0, end: 1).animate(
        CurvedAnimation(parent: controller, curve: Curves.easeInOut),
      );
    }).toList();

    // Başlangıç offset'leri
    for (int i = 0; i < _controllers.length; i++) {
      Future.delayed(Duration(milliseconds: i * 200), () {
        if (mounted) {
          _controllers[i].repeat(reverse: true);
        }
      });
    }
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(3, (index) {
        return AnimatedBuilder(
          animation: _animations[index],
          builder: (context, child) {
            return Container(
              margin: const EdgeInsets.symmetric(horizontal: 2),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AIChatTheme.primaryGradientStart.withOpacity(
                  0.5 + (_animations[index].value * 0.5),
                ),
                shape: BoxShape.circle,
              ),
            );
          },
        );
      }),
    );
  }
}
