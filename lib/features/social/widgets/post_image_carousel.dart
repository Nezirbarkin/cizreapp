// ignore_for_file: use_key_in_widget_constructors, deprecated_member_use

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Çoklu görsel için yatay swipe carousel + nokta indikatör (Instagram tarzı).
/// Keşfet feed kartında post.images listesini gezilebilir şekilde gösterir.
/// Tek görselde carousel/nokta gösterilmez (eski tek-görsel davranışı korunur).
class PostImageCarousel extends StatefulWidget {
  final List<String> imageUrls;
  final VoidCallback? onTap;

  const PostImageCarousel({required this.imageUrls, this.onTap});

  @override
  State<PostImageCarousel> createState() => PostImageCarouselState();
}

class PostImageCarouselState extends State<PostImageCarousel> {
  /// Kart görselinin yüksekliği. Kart tasarımı genişledikçe 200px çok basık
  /// duruyordu; 240 hem daha modern hem de bellek açısından hâlâ güvenli.
  static const double _imageHeight = 240;

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
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          // PageView: tek görselde swipe'a gerek yok ama tutarlı render için kullanılır.
          SizedBox(
            height: _imageHeight,
            child: PageView.builder(
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
                    width: double.infinity,
                    height: _imageHeight,
                    fit: BoxFit.cover,
                    // Feed görseli tam genişlikte ~240px yüksekliğinde gösterilir;
                    // kaynak çözünürlüğünde (~1080px) decode etmek her görsel için
                    // ~8MB bitmap demek. 750px sınırı, kayan feed'de OOM riskini
                    // düşürürken görünür kaliteyi korur.
                    memCacheWidth: 750,
                    errorWidget: (context, url, error) {
                      // Görsel yüklenemezse gri placeholder
                      return Container(
                        width: double.infinity,
                        height: _imageHeight,
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
                        width: double.infinity,
                        height: _imageHeight,
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
          ),
          // Çoklu görsel göstergesi (sağ üst) - "1/N"
          if (!isSingle)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
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
              bottom: 8,
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
                      color: isActive ? Colors.white : Colors.white.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}
