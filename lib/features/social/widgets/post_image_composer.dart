import 'package:flutter/material.dart';

import '../../profile/widgets/immersive_crop_screen.dart' show AspectFrameIcon;
import '../models/post_image_format.dart';

/// Gönderi oluşturma ekranının fotoğraf alanı (Görev 2.8).
///
/// ÖNİZLEME SÖZLEŞMESİ: Fotoğraflar seçili çerçevede ve `cover` ile, yani
/// akışta görünecekleri haliyle gösterilir; yükleme de aynı ortayı kırpar
/// (bkz. PostImagePreparer). "Ne görüyorsan onu paylaşırsın."
///
/// İçerik: kaydırmalı büyük önizleme (+ "Kırp" düğmesi, sayfa göstergesi),
/// çerçeve seçici (Dikey / Kare / Yatay), açıklama alanı ve küçük resim
/// şeridi (seç, kaldır, ekle).
class PostImageComposer extends StatefulWidget {
  const PostImageComposer({
    super.key,
    required this.images,
    required this.format,
    required this.onFormatChanged,
    required this.onCrop,
    required this.onRemove,
    this.onAdd,
    this.enabled = true,
    this.caption,
  });

  final List<PostDraftImage> images;
  final PostImageFormat format;
  final ValueChanged<PostImageFormat> onFormatChanged;

  /// Önizlemedeki fotoğrafın sırası ile kırpma istenir.
  final ValueChanged<int> onCrop;
  final ValueChanged<int> onRemove;

  /// Şeridin sonundaki "+" kutusu; null ise gösterilmez.
  final VoidCallback? onAdd;

  /// Paylaşım sürerken düğmeler kapalı.
  final bool enabled;

  /// Önizlemenin altındaki açıklama alanı.
  final Widget? caption;

  @override
  State<PostImageComposer> createState() => _PostImageComposerState();
}

class _PostImageComposerState extends State<PostImageComposer> {
  static const Color _panelBg = Color(0xFF161B22);
  static const double _thumbSize = 88;

  final PageController _pageController = PageController();
  int _index = 0;

  @override
  void didUpdateWidget(covariant PostImageComposer oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Fotoğraf kaldırılınca gösterilen sıra listenin dışında kalmasın.
    final last = widget.images.length - 1;
    if (last >= 0 && _index > last) {
      _index = last;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _pageController.hasClients) {
          _pageController.jumpToPage(_index);
        }
      });
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _select(int index) {
    if (index == _index) return;
    setState(() => _index = index);
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.images;
    if (images.isEmpty) return const SizedBox.shrink();
    final index = _index.clamp(0, images.length - 1);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          decoration: BoxDecoration(
            color: _panelBg,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: Colors.white12),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              _preview(images, index),
              const SizedBox(height: 12),
              _formatSelector(),
              if (widget.caption != null) ...[
                const SizedBox(height: 6),
                widget.caption!,
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),
        _thumbnailStrip(images, index),
      ],
    );
  }

  // ------------------------------------------------------------- önizleme

  Widget _preview(List<PostDraftImage> images, int index) {
    final isSingle = images.length == 1;
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: widget.format.aspectRatio,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final dpr = MediaQuery.devicePixelRatioOf(context);
            final decodeWidth = (constraints.maxWidth * dpr).round().clamp(320, 1440);
            return Stack(
              fit: StackFit.expand,
              children: [
                PageView.builder(
                  key: const ValueKey('post-image-preview'),
                  controller: _pageController,
                  itemCount: images.length,
                  onPageChanged: (i) => setState(() => _index = i),
                  itemBuilder: (context, i) {
                    final draft = images[i];
                    return Image.memory(
                      draft.displayBytesFor(widget.format.aspectRatio),
                      key: ObjectKey(draft),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      cacheWidth: decodeWidth,
                    );
                  },
                ),
                Positioned(
                  top: 10,
                  right: 10,
                  child: _CropPill(
                    cropped: images[index].isCroppedFor(widget.format.aspectRatio),
                    onTap: widget.enabled ? () => widget.onCrop(index) : null,
                  ),
                ),
                if (!isSingle)
                  Positioned(
                    top: 10,
                    left: 10,
                    child: _Pill(child: Text('${index + 1}/${images.length}', style: _pillText)),
                  ),
                if (!isSingle)
                  Positioned(
                    bottom: 10,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        for (var i = 0; i < images.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.symmetric(horizontal: 3),
                            width: i == index ? 8 : 6,
                            height: i == index ? 8 : 6,
                            decoration: BoxDecoration(
                              color: i == index ? Colors.white : Colors.white.withValues(alpha: 0.5),
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  static const TextStyle _pillText = TextStyle(
    color: Colors.white,
    fontSize: 12,
    fontWeight: FontWeight.w700,
  );

  // ------------------------------------------------------ çerçeve seçici

  Widget _formatSelector() {
    final primary = Theme.of(context).colorScheme.primary;
    return Row(
      children: [
        for (final format in PostImageFormat.values) ...[
          if (format != PostImageFormat.values.first) const SizedBox(width: 8),
          Expanded(
            child: _FormatOption(
              format: format,
              selected: format == widget.format,
              accent: primary,
              onTap: widget.enabled && format != widget.format
                  ? () => widget.onFormatChanged(format)
                  : null,
            ),
          ),
        ],
      ],
    );
  }

  // ------------------------------------------------------- küçük resimler

  Widget _thumbnailStrip(List<PostDraftImage> images, int index) {
    final primary = Theme.of(context).colorScheme.primary;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final thumbDecodeWidth = (_thumbSize * dpr).round();
    final showAdd = widget.onAdd != null;

    return SizedBox(
      height: _thumbSize,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: images.length + (showAdd ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          if (i == images.length) {
            return Semantics(
              button: true,
              label: 'Fotoğraf ekle',
              child: GestureDetector(
                onTap: widget.enabled ? widget.onAdd : null,
                child: Container(
                  width: _thumbSize,
                  decoration: BoxDecoration(
                    color: _panelBg,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: const Icon(Icons.add, color: Colors.white70),
                ),
              ),
            );
          }

          final draft = images[i];
          final selected = i == index;
          return SizedBox(
            key: ObjectKey(draft),
            width: _thumbSize,
            height: _thumbSize,
            child: Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => _select(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: selected ? primary : Colors.transparent,
                          width: 2.5,
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(11.5),
                        child: Image.memory(
                          draft.displayBytesFor(widget.format.aspectRatio),
                          fit: BoxFit.cover,
                          gaplessPlayback: true,
                          cacheWidth: thumbDecodeWidth,
                        ),
                      ),
                    ),
                  ),
                ),
                if (draft.isCroppedFor(widget.format.aspectRatio))
                  const Positioned(
                    left: 6,
                    bottom: 6,
                    child: _Pill(
                      padding: EdgeInsets.all(3),
                      child: Icon(Icons.crop, size: 12, color: Colors.white),
                    ),
                  ),
                Positioned(
                  top: 4,
                  right: 4,
                  child: Tooltip(
                    message: 'Fotoğrafı kaldır',
                    child: GestureDetector(
                      onTap: widget.enabled ? () => widget.onRemove(i) : null,
                      child: Container(
                        padding: const EdgeInsets.all(3),
                        decoration: const BoxDecoration(
                          color: Colors.black54,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.close, size: 14, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Önizlemenin köşesindeki "Kırp" düğmesi.
class _CropPill extends StatelessWidget {
  const _CropPill({required this.cropped, required this.onTap});

  final bool cropped;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: 'Fotoğrafı kırp',
      excludeSemantics: true,
      child: Material(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(cropped ? Icons.check_circle : Icons.crop, size: 16, color: Colors.white),
                const SizedBox(width: 6),
                Text(
                  cropped ? 'Kırpıldı' : 'Kırp',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Çerçeve seçeneği: oran simgesi + ad + oran.
class _FormatOption extends StatelessWidget {
  const _FormatOption({
    required this.format,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final PostImageFormat format;
  final bool selected;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = selected ? Colors.white : Colors.white70;
    return Semantics(
      button: true,
      selected: selected,
      label: '${format.label} ${format.ratioLabel}',
      excludeSemantics: true,
      child: Material(
        color: selected ? accent.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.05),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: selected ? accent : Colors.white12, width: selected ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 9),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AspectFrameIcon(ratio: format.aspectRatio, color: foreground, size: 15),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    format.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: foreground, fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  format.ratioLabel,
                  style: TextStyle(
                    color: foreground.withValues(alpha: 0.65),
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.child, this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 4)});

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: child,
    );
  }
}
