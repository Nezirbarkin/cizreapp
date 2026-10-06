import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Çoklu görsel için yatay swipe carousel + nokta indikatör (Instagram tarzı).
/// Keşfet feed kartında post.images listesini gezilebilir şekilde gösterir.
/// Tek görselde carousel/nokta gösterilmez (eski tek-görsel davranışı korunur).
///
/// Görev 2.8: Görsel artık sabit 240 px'lik bir şerit değil; gönderinin
/// çerçeve oranında ([aspectRatio], bkz. `feedImageAspect`) ve verilen
/// genişliğin TAMAMINDA çizilir. Oran satırla birlikte geldiği için kart ilk
/// karede doğru boydadır — görsel inince akış zıplamaz.
class PostImageCarousel extends StatefulWidget {
  const PostImageCarousel({
    super.key,
    required this.imageUrls,
    this.onTap,
    this.aspectRatio = 1,
    this.borderRadius = BorderRadius.zero,
  });

  final List<String> imageUrls;
  final VoidCallback? onTap;

  /// Çerçeve oranı (genişlik / yükseklik). Tüm sayfalar aynı çerçevede.
  final double aspectRatio;

  final BorderRadius borderRadius;

  @override
  State<PostImageCarousel> createState() => PostImageCarouselState();
}

class PostImageCarouselState extends State<PostImageCarousel> {
  /// Görseller en fazla bu genişlikte yükleniyor; daha büyük çözmek boşa
  /// bellek harcar.
  static const int _maxDecodeWidth = 1080;

  late PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.imageUrls.where((u) => u.isNotEmpty).toList();
    if (images.isEmpty) return const SizedBox.shrink();

    final isSingle = images.length == 1;

    return ClipRRect(
      borderRadius: widget.borderRadius,
      child: AspectRatio(
        aspectRatio: widget.aspectRatio,
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Görsel ekranda çizildiği çözünürlükte çözülür: tam genişlikteki
            // kart yüksek DPI'lı telefonda ~1080 px ister, düşük DPI'da daha
            // azı yeter. Kayan akışta her görseli kaynak boyutunda çözmek
            // gereksiz bellek (ve OOM riski) demek.
            final dpr = MediaQuery.devicePixelRatioOf(context);
            final decodeWidth = (constraints.maxWidth * dpr)
                .round()
                .clamp(320, _maxDecodeWidth);

            return Stack(
              fit: StackFit.expand,
              children: [
                // PageView: tek görselde swipe'a gerek yok ama tutarlı render için kullanılır.
                PageView.builder(
                  controller: _pageController,
                  physics: isSingle
                      ? const NeverScrollableScrollPhysics() // tek görselde swipe kapalı
                      : const PageScrollPhysics(),
                  itemCount: images.length,
                  onPageChanged: (index) {
                    setState(() => _currentIndex = index);
                  },
                  itemBuilder: (context, index) {
                    return GestureDetector(
                      onTap: widget.onTap,
                      child: CachedNetworkImage(
                        imageUrl: images[index],
                        fit: BoxFit.cover,
                        memCacheWidth: decodeWidth,
                        errorWidget: (context, url, error) {
                          // Görsel yüklenemezse gri placeholder
                          return Container(
                            color: Colors.grey.shade200,
                            child: const Icon(
                              Icons.broken_image_outlined,
                              color: Colors.grey,
                              size: 40,
                            ),
                          );
                        },
                        placeholder: (context, url) {
                          return Container(
                            color: Colors.grey.shade100,
                            child: const Center(
                              child: SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
                // Çoklu görsel göstergesi (sağ üst) - "1/N"
                if (!isSingle)
                  Positioned(
                    top: 10,
                    right: 10,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.photo_library, color: Colors.white, size: 14),
                          const SizedBox(width: 4),
                          Text(
                            '${_currentIndex + 1}/${images.length}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                // Nokta indikatörleri (alt orta) - Instagram tarzı
                if (!isSingle)
                  Positioned(
                    bottom: 10,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(images.length, (index) {
                        final isActive = index == _currentIndex;
                        return AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 3),
                          width: isActive ? 8 : 6,
                          height: isActive ? 8 : 6,
                          decoration: BoxDecoration(
                            color: isActive
                                ? Colors.white
                                : Colors.white.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(color: Color(0x40000000), blurRadius: 3),
                            ],
                          ),
                        );
                      }),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
