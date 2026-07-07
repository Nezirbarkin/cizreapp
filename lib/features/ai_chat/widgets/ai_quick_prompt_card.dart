// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/ai_quick_prompt_model.dart';
import '../theme/ai_chat_theme.dart';

/// Modern Görsellı Prompt Kartı - Gemini Tarzı
/// Her prompt kartında thumbnail görsel veya renkli gradient gösterilir
class AIQuickPromptCard extends StatefulWidget {
  final AIQuickPrompt prompt;
  final VoidCallback onTap;
  final bool isCompact;

  const AIQuickPromptCard({
    super.key,
    required this.prompt,
    required this.onTap,
    this.isCompact = false,
  });

  @override
  State<AIQuickPromptCard> createState() => _AIQuickPromptCardState();
}

class _AIQuickPromptCardState extends State<AIQuickPromptCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: AIChatTheme.animationFast,
      vsync: this,
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.95).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onTapDown(TapDownDetails details) {
    setState(() => _isPressed = true);
    _controller.forward();
  }

  void _onTapUp(TapUpDetails details) {
    setState(() => _isPressed = false);
    _controller.reverse();
    widget.onTap();
  }

  void _onTapCancel() {
    setState(() => _isPressed = false);
    _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final baseColor = AIQuickPrompt.getColorFromString(
      widget.prompt.thumbnailColor ?? '#7B2CBF',
    );

    return GestureDetector(
      onTapDown: _onTapDown,
      onTapUp: _onTapUp,
      onTapCancel: _onTapCancel,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: Container(
              width: widget.isCompact ? 120 : AIChatTheme.promptCardWidth,
              height: widget.isCompact ? 100 : AIChatTheme.promptCardHeight,
              decoration: _buildDecoration(baseColor),
              child: Stack(
                children: [
                  // Arka plan
                  if (widget.prompt.hasImage)
                    _buildImageBackground()
                  else
                    _buildGradientBackground(baseColor),

                  // İçerik
                  _buildContent(baseColor),

                  // Hover efekti
                  if (_isPressed)
                    Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(
                          AIChatTheme.radiusLarge,
                        ),
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

  BoxDecoration _buildDecoration(Color baseColor) {
    if (widget.prompt.hasImage) {
      return BoxDecoration(
        borderRadius: BorderRadius.circular(AIChatTheme.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: baseColor.withOpacity(0.3),
            blurRadius: 8,
            offset: const Offset(0, 4),
          ),
        ],
      );
    } else {
      return BoxDecoration(
        borderRadius: BorderRadius.circular(AIChatTheme.radiusLarge),
        boxShadow: [
          BoxShadow(
            color: baseColor.withOpacity(0.4),
            blurRadius: 12,
            spreadRadius: 1,
          ),
        ],
      );
    }
  }

  Widget _buildImageBackground() {
    return ClipRRect(
      borderRadius: BorderRadius.circular(AIChatTheme.radiusLarge),
      child: Stack(
        fit: StackFit.expand,
        children: [
          CachedNetworkImage(
            imageUrl: widget.prompt.imageUrl!,
            fit: BoxFit.cover,
            errorWidget: (context, url, error) {
              return Container(
                color: AIChatTheme.cardBackground,
              );
            },
            placeholder: (context, url) {
              return Container(
                color: AIChatTheme.cardBackground,
                child: const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AIChatTheme.primaryGradientStart,
                  ),
                ),
              );
            },
          ),
          // Overlay
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.transparent,
                  Colors.black.withOpacity(0.7),
                ],
                stops: const [0.3, 1.0],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradientBackground(Color baseColor) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            baseColor,
            baseColor.withOpacity(0.7),
            HSLColor.fromColor(baseColor)
                .withLightness(
                  (HSLColor.fromColor(baseColor).lightness - 0.2)
                      .clamp(0.0, 1.0),
                )
                .toColor(),
          ],
        ),
        borderRadius: BorderRadius.circular(AIChatTheme.radiusLarge),
      ),
    );
  }

  Widget _buildContent(Color baseColor) {
    return Padding(
      padding: EdgeInsets.all(
        widget.isCompact ? AIChatTheme.paddingS : AIChatTheme.paddingM,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // İkon
          if (!widget.prompt.hasImage) ...[
            Icon(
              AIQuickPrompt.getIconData(widget.prompt.icon) ??
                  Icons.lightbulb_outline,
              color: Colors.white.withOpacity(0.9),
              size: widget.isCompact ? 20 : 24,
            ),
            const Spacer(),
          ] else ...[
            const Spacer(),
          ],

          // Başlık
          Text(
            widget.prompt.title,
            style: TextStyle(
              color: Colors.white,
              fontSize: widget.isCompact ? 11 : 13,
              fontWeight: FontWeight.w600,
              shadows: [
                Shadow(
                  color: Colors.black.withOpacity(0.5),
                  blurRadius: 4,
                ),
              ],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

/// Yatay Kaydırılabilir Prompt Listesi
class AIQuickPromptList extends StatelessWidget {
  final List<AIQuickPrompt> prompts;
  final Function(AIQuickPrompt) onPromptTap;
  final String? title;

  const AIQuickPromptList({
    super.key,
    required this.prompts,
    required this.onPromptTap,
    this.title,
  });

  @override
  Widget build(BuildContext context) {
    if (prompts.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AIChatTheme.paddingL,
              vertical: AIChatTheme.paddingS,
            ),
            child: Text(
              title!,
              style: AIChatTheme.titleMedium.copyWith(
                color: AIChatTheme.textSecondary,
              ),
            ),
          ),
        SizedBox(
          height: AIChatTheme.promptCardHeight + AIChatTheme.paddingS,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: AIChatTheme.paddingL,
            ),
            itemCount: prompts.length,
            separatorBuilder: (context, index) =>
                const SizedBox(width: AIChatTheme.paddingM),
            itemBuilder: (context, index) {
              return AIQuickPromptCard(
                prompt: prompts[index],
                onTap: () => onPromptTap(prompts[index]),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Grid Görünümü Prompt Listesi
class AIQuickPromptGrid extends StatelessWidget {
  final List<AIQuickPrompt> prompts;
  final Function(AIQuickPrompt) onPromptTap;
  final int crossAxisCount;

  const AIQuickPromptGrid({
    super.key,
    required this.prompts,
    required this.onPromptTap,
    this.crossAxisCount = 2,
  });

  @override
  Widget build(BuildContext context) {
    if (prompts.isEmpty) return const SizedBox.shrink();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AIChatTheme.paddingL),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisSpacing: AIChatTheme.paddingM,
        crossAxisSpacing: AIChatTheme.paddingM,
        childAspectRatio: 1.2,
      ),
      itemCount: prompts.length,
      itemBuilder: (context, index) {
        return AIQuickPromptCard(
          prompt: prompts[index],
          onTap: () => onPromptTap(prompts[index]),
          isCompact: true,
        );
      },
    );
  }
}

/// Admin Panel için Düzenlenebilir Prompt Kartı
class AIEditablePromptCard extends StatelessWidget {
  final AIQuickPrompt prompt;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final Function(bool) onToggleActive;

  const AIEditablePromptCard({
    super.key,
    required this.prompt,
    required this.onEdit,
    required this.onDelete,
    required this.onToggleActive,
  });

  @override
  Widget build(BuildContext context) {
    final baseColor = AIQuickPrompt.getColorFromString(
      prompt.thumbnailColor ?? '#7B2CBF',
    );

    return Card(
      color: AIChatTheme.cardBackground,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AIChatTheme.radiusLarge),
        side: BorderSide(
          color: prompt.isActive
              ? baseColor.withOpacity(0.5)
              : AIChatTheme.cardBorder,
          width: prompt.isActive ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Görsel/Gradient alanı
          Expanded(
            flex: 2,
            child: ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AIChatTheme.radiusLarge),
              ),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (prompt.hasImage)
                    CachedNetworkImage(
                      imageUrl: prompt.imageUrl!,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _buildGradientBg(baseColor),
                    )
                  else
                    _buildGradientBg(baseColor),

                  // Aktif/Pasif badge
                  Positioned(
                    top: AIChatTheme.paddingS,
                    right: AIChatTheme.paddingS,
                    child: GestureDetector(
                      onTap: () => onToggleActive(!prompt.isActive),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: AIChatTheme.paddingS,
                          vertical: AIChatTheme.paddingXS,
                        ),
                        decoration: BoxDecoration(
                          color: prompt.isActive
                              ? AIChatTheme.success.withOpacity(0.9)
                              : AIChatTheme.textMuted.withOpacity(0.9),
                          borderRadius: BorderRadius.circular(
                            AIChatTheme.radiusSmall,
                          ),
                        ),
                        child: Text(
                          prompt.isActive ? 'Aktif' : 'Pasif',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Sıra numarası
                  Positioned(
                    top: AIChatTheme.paddingS,
                    left: AIChatTheme.paddingS,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: AIChatTheme.paddingS,
                        vertical: AIChatTheme.paddingXS,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(
                          AIChatTheme.radiusSmall,
                        ),
                      ),
                      child: Text(
                        '#${prompt.sortOrder + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // İçerik alanı
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.all(AIChatTheme.paddingM),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    prompt.title,
                    style: AIChatTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const Spacer(),
                  Row(
                    children: [
                      Icon(
                        prompt.categoryIcon,
                        size: 14,
                        color: AIChatTheme.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          prompt.category ?? 'general',
                          style: AIChatTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Aksiyon butonları
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AIChatTheme.paddingS,
              vertical: AIChatTheme.paddingS,
            ),
            decoration: BoxDecoration(
              color: AIChatTheme.cardBackgroundLight,
              borderRadius: const BorderRadius.vertical(
                bottom: Radius.circular(AIChatTheme.radiusLarge),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildActionButton(
                  icon: Icons.edit_rounded,
                  onTap: onEdit,
                  color: AIChatTheme.info,
                ),
                _buildActionButton(
                  icon: Icons.delete_rounded,
                  onTap: onDelete,
                  color: AIChatTheme.error,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGradientBg(Color baseColor) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            baseColor,
            baseColor.withOpacity(0.6),
          ],
        ),
      ),
      child: Center(
        child: Icon(
          AIQuickPrompt.getIconData(prompt.icon) ?? Icons.lightbulb_outline,
          color: Colors.white.withOpacity(0.5),
          size: 40,
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
    required Color color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AIChatTheme.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.all(AIChatTheme.paddingS),
        child: Icon(
          icon,
          color: color,
          size: AIChatTheme.iconSizeMedium,
        ),
      ),
    );
  }
}
