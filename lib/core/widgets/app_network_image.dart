// ignore_for_file: use_key_in_widget_constructors

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

/// Bellek limitli ağ görseli. [CachedNetworkImage]'ı sarmalar ve decode edilen
/// bitmap boyutunu [memCacheWidth] ile sınırlandırır.
///
/// Neden var: [CachedNetworkImage] varsayılan olarak görseli kaynak
/// çözünürlüğünde (~1080–2160px) decode edip bitmap önbelleğine koyar.
/// 1080×1920 bir post görseli ~8MB decode edilmiş bitmap demektir; kayan bir
/// feed'de 20 görsel = ~160MB — düşük RAM'li cihazlarda OOM/çökme riski.
/// [memCacheWidth] bitmap'i ~1000px genişliğe indirir (görünür kalite kaybı
/// olmadan ~4MB'a düşer).
///
/// Yeni görsel gösterimlerinde mümkünse bunu kullanın; parametreleri elle
/// eklenmiş mevcut [CachedNetworkImage] çağrılarıyla eşdeğerdir.
class AppNetworkImage extends StatelessWidget {
  const AppNetworkImage({
    super.key,
    required this.imageUrl,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.memCacheWidth = 1000,
    this.borderRadius,
    this.placeholder,
    this.errorWidget,
  });

  final String imageUrl;
  final double? width;
  final double? height;
  final BoxFit fit;

  /// Decode edilen bitmap'in piksel genişlik üst sınırı. Küçük thumbnail'lar
  /// (avatar, story ring) için ~200–300, feed görselleri için ~750–1000 verin.
  final int? memCacheWidth;

  /// İsteğe bağlı köşe yuvarlatma. Sağlandığında görsel [ClipRRect] içine alınır.
  final BorderRadius? borderRadius;

  /// Yüklenirken gösterilecek widget. Verilmezse gri bir shimmer/box gösterilir.
  final WidgetBuilder? placeholder;

  /// Hata durumunda gösterilecek widget. Verilmezse kırık-görsel ikonu gösterilir.
  final WidgetBuilder? errorWidget;

  @override
  Widget build(BuildContext context) {
    final image = CachedNetworkImage(
      imageUrl: imageUrl,
      width: width,
      height: height,
      fit: fit,
      // Decode edilen bitmap'i sınırla. Web de dâhil tüm platformlarda geçerli.
      memCacheWidth: memCacheWidth,
      placeholder: placeholder != null
          ? (_, __) => placeholder!(context)
          : (_, __) => _defaultPlaceholder(context),
      errorWidget: errorWidget != null
          ? (_, __, ___) => errorWidget!(context)
          : (_, __, ___) => _defaultError(context),
    );

    if (borderRadius != null) {
      return ClipRRect(borderRadius: borderRadius!, child: image);
    }
    return image;
  }

  Widget _defaultPlaceholder(BuildContext context) => Container(
        width: width,
        height: height,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      );

  Widget _defaultError(BuildContext context) => Container(
        width: width,
        height: height,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Icon(
          Icons.broken_image_outlined,
          color: Theme.of(context).colorScheme.outline,
        ),
      );
}
