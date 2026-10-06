import 'dart:math' as math;

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../services/chat_location_service.dart';
import '../services/chat_media_service.dart';
import 'chat_bubble.dart';

/// Sohbetteki fotoğraf ve konum balonları (Görev 3.1). Metin balonuyla aynı
/// dil: [ChatBubbleShape] kuyruğu, öbekleme, sağ altta saat + [ChatStatusTicks].

// ---------------------------------------------------------------------------
// Fotoğraf
// ---------------------------------------------------------------------------

/// Özel kovadaki sohbet fotoğrafı.
///
/// Bu cihazdan gönderildiyse bellekteki baytlardan (yükleme sürerken de)
/// çizilir; değilse imzalı adresle indirilir. Disk önbelleği yola bağlıdır.
class ChatAttachmentImage extends StatefulWidget {
  const ChatAttachmentImage({
    super.key,
    required this.path,
    this.fit = BoxFit.cover,
    this.decodeWidth,
    this.media,
  });

  final String path;
  final BoxFit fit;

  /// Çözme genişliği (px); null ise kaynak çözünürlüğünde.
  final int? decodeWidth;

  final ChatMediaService? media;

  @override
  State<ChatAttachmentImage> createState() => _ChatAttachmentImageState();
}

class _ChatAttachmentImageState extends State<ChatAttachmentImage> {
  Future<String?>? _url;

  ChatMediaService get _media => widget.media ?? ChatMediaService.shared;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant ChatAttachmentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) _resolve();
  }

  void _resolve() {
    _url = ChatMediaService.localBytes(widget.path) == null
        ? _media.signedUrl(widget.path)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    final local = ChatMediaService.localBytes(widget.path);
    if (local != null) {
      return Image.memory(
        local,
        fit: widget.fit,
        gaplessPlayback: true,
        cacheWidth: widget.decodeWidth,
      );
    }
    return FutureBuilder<String?>(
      future: _url,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _ImagePlaceholder();
        }
        final url = snapshot.data;
        if (url == null) {
          return _ImageError(onRetry: () => setState(_resolve));
        }
        return CachedNetworkImage(
          imageUrl: url,
          cacheKey: ChatMediaService.cacheKeyFor(widget.path),
          fit: widget.fit,
          memCacheWidth: widget.decodeWidth,
          placeholder: (_, __) => const _ImagePlaceholder(),
          errorWidget: (_, __, ___) => _ImageError(onRetry: () => setState(_resolve)),
        );
      },
    );
  }
}

class _ImagePlaceholder extends StatelessWidget {
  const _ImagePlaceholder();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0xFFE4DEEF),
      child: Center(
        child: Icon(Icons.image_outlined, color: Color(0xFFB3A8CC), size: 34),
      ),
    );
  }
}

class _ImageError extends StatelessWidget {
  const _ImageError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onRetry,
      child: const ColoredBox(
        color: Color(0xFFE4DEEF),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.broken_image_outlined, color: Color(0xFF8E83A8), size: 30),
              SizedBox(height: 4),
              Text(
                'Görsel yüklenemedi',
                style: TextStyle(fontSize: 12, color: Color(0xFF6E6690)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fotoğraf balonu: çerçeve fotoğrafın oranında (0.6–1.8 arası), altında
/// isteğe bağlı açıklama. Açıklama yoksa saat fotoğrafın üzerinde durur.
class ChatImageBubble extends StatelessWidget {
  const ChatImageBubble({
    super.key,
    required this.path,
    required this.time,
    required this.isMine,
    this.aspectRatio,
    this.caption,
    this.status,
    this.joinsAbove = false,
    this.joinsBelow = false,
    this.replySenderName,
    this.replyContent,
    this.onTap,
    this.onRetry,
    this.media,
  });

  final String path;
  final String time;
  final bool isMine;
  final double? aspectRatio;
  final String? caption;

  /// Kendi mesajımın durumu ([Message.messageStatus]); karşınınkinde null.
  final String? status;
  final bool joinsAbove;
  final bool joinsBelow;
  final String? replySenderName;
  final String? replyContent;

  /// Fotoğrafı büyük aç.
  final VoidCallback? onTap;

  /// Gönderilemediyse yeniden dene.
  final VoidCallback? onRetry;

  final ChatMediaService? media;

  static const double maxWidth = 280;
  static const double maxWidthFactor = 0.68;

  /// Balon çerçevesinin oranı: çok uzun/çok basık fotoğraf balonu taşırmasın.
  static double frameAspect(double? ratio) {
    if (ratio == null || !ratio.isFinite || ratio <= 0) return 1;
    return ratio.clamp(0.6, 1.8).toDouble();
  }

  bool get _hasCaption => caption != null && caption!.trim().isNotEmpty;
  bool get _hasReply => replyContent != null && replyContent!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final width = math.min(MediaQuery.sizeOf(context).width * maxWidthFactor, maxWidth);
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final sending = status == 'sending';
    final failed = status == 'failed';

    final photo = ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: AspectRatio(
        aspectRatio: frameAspect(aspectRatio),
        child: Stack(
          fit: StackFit.expand,
          children: [
            ChatAttachmentImage(
              path: path,
              decodeWidth: (width * dpr).round(),
              media: media,
            ),
            if (sending)
              const ColoredBox(
                color: Color(0x66000000),
                child: Center(
                  child: SizedBox(
                    width: 30,
                    height: 30,
                    child: CircularProgressIndicator(strokeWidth: 2.6, color: Colors.white),
                  ),
                ),
              ),
            if (failed) const _FailedOverlay(),
            if (!_hasCaption)
              Positioned(
                right: 6,
                bottom: 6,
                child: _OverlayMeta(time: time, status: isMine ? status : null),
              ),
          ],
        ),
      ),
    );

    return _MediaBubbleFrame(
      isMine: isMine,
      joinsAbove: joinsAbove,
      joinsBelow: joinsBelow,
      width: width,
      semanticsLabel: _hasCaption ? 'Fotoğraf: ${caption!.trim()}' : 'Fotoğraf',
      onTap: failed ? onRetry : (sending ? null : onTap),
      children: [
        if (_hasReply) ...[
          ChatReplyQuote(
            senderName: replySenderName ?? 'Yanıt',
            content: replyContent!,
            isMine: isMine,
          ),
          const SizedBox(height: 4),
        ],
        photo,
        if (_hasCaption)
          Padding(
            padding: const EdgeInsets.fromLTRB(6, 5, 4, 1),
            child: _CaptionWithMeta(
              text: caption!.trim(),
              time: time,
              isMine: isMine,
              status: isMine ? status : null,
            ),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Konum
// ---------------------------------------------------------------------------

/// Konum balonu: çizilmiş küçük harita + iğne, altında adres ve koordinat.
/// Dokununca tam ekran harita açılır.
class ChatLocationBubble extends StatelessWidget {
  const ChatLocationBubble({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.time,
    required this.isMine,
    this.label,
    this.status,
    this.joinsAbove = false,
    this.joinsBelow = false,
    this.replySenderName,
    this.replyContent,
    this.onTap,
    this.onRetry,
  });

  final double latitude;
  final double longitude;
  final String time;
  final bool isMine;
  final String? label;
  final String? status;
  final bool joinsAbove;
  final bool joinsBelow;
  final String? replySenderName;
  final String? replyContent;
  final VoidCallback? onTap;
  final VoidCallback? onRetry;

  static const double maxWidth = 270;
  static const double mapHeight = 128;

  bool get _hasReply => replyContent != null && replyContent!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final width = math.min(
      MediaQuery.sizeOf(context).width * ChatImageBubble.maxWidthFactor,
      maxWidth,
    );
    final sending = status == 'sending';
    final failed = status == 'failed';
    final title = (label == null || label!.trim().isEmpty) ? 'Konum' : label!.trim();

    return _MediaBubbleFrame(
      isMine: isMine,
      joinsAbove: joinsAbove,
      joinsBelow: joinsBelow,
      width: width,
      semanticsLabel: 'Konum: $title',
      onTap: failed ? onRetry : (sending ? null : onTap),
      children: [
        if (_hasReply) ...[
          ChatReplyQuote(
            senderName: replySenderName ?? 'Yanıt',
            content: replyContent!,
            isMine: isMine,
          ),
          const SizedBox(height: 4),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            height: mapHeight,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ChatMapPreview(latitude: latitude, longitude: longitude),
                const Align(
                  alignment: Alignment(0, -0.18),
                  child: Icon(
                    Icons.location_on,
                    color: Color(0xFFE53935),
                    size: 42,
                    shadows: [Shadow(color: Color(0x55000000), blurRadius: 6, offset: Offset(0, 2))],
                  ),
                ),
                if (sending)
                  const ColoredBox(
                    color: Color(0x33000000),
                    child: Center(
                      child: SizedBox(
                        width: 26,
                        height: 26,
                        child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white),
                      ),
                    ),
                  ),
                if (failed) const _FailedOverlay(),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(6, 7, 4, 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(Icons.place, size: 18, color: ChatPalette.accent),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        height: 1.25,
                        fontWeight: FontWeight.w600,
                        color: ChatPalette.text,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      ChatLocationService.formatCoordinates(latitude, longitude),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isMine ? ChatPalette.mineMeta : ChatPalette.theirsMeta,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 2, 4, 1),
            child: ChatBubbleMeta(time: time, isMine: isMine, status: isMine ? status : null),
          ),
        ),
      ],
    );
  }
}

/// Konum balonundaki çizilmiş küçük harita: bej zemin, parklar, Dicle'yi
/// andıran bir nehir ve yollar. Koordinattan tohumlandığı için her konum
/// biraz farklı, aynı konum hep aynı görünür. (Statik harita API'si
/// projede açık değil; gerçek harita dokununca açılan ekranda.)
class ChatMapPreview extends StatelessWidget {
  const ChatMapPreview({super.key, required this.latitude, required this.longitude});

  final double latitude;
  final double longitude;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _MapPreviewPainter(
        seed: (latitude * 10000).round() * 31 + (longitude * 10000).round(),
      ),
    );
  }
}

class _MapPreviewPainter extends CustomPainter {
  _MapPreviewPainter({required this.seed});

  final int seed;

  @override
  void paint(Canvas canvas, Size size) {
    final random = math.Random(seed);
    final w = size.width;
    final h = size.height;

    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFF1ECE2));

    // Parklar
    final park = Paint()..color = const Color(0xFFD3E8C8);
    for (var i = 0; i < 3; i++) {
      final rect = Rect.fromLTWH(
        random.nextDouble() * w * 0.8,
        random.nextDouble() * h * 0.7,
        w * (0.12 + random.nextDouble() * 0.16),
        h * (0.16 + random.nextDouble() * 0.2),
      );
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(6)), park);
    }

    // Nehir: bir kenardan ötekine kıvrılan geniş şerit
    final riverY = h * (0.25 + random.nextDouble() * 0.5);
    final river = Path()
      ..moveTo(-10, riverY)
      ..cubicTo(
        w * 0.3,
        riverY + (random.nextDouble() - 0.5) * h * 0.6,
        w * 0.6,
        riverY + (random.nextDouble() - 0.5) * h * 0.6,
        w + 10,
        riverY + (random.nextDouble() - 0.5) * h * 0.3,
      );
    canvas.drawPath(
      river,
      Paint()
        ..color = const Color(0xFFAFD4EE)
        ..style = PaintingStyle.stroke
        ..strokeWidth = h * 0.13
        ..strokeCap = StrokeCap.round,
    );

    // Yollar: çerçeveli beyaz ara yollar + bir sarı ana yol
    final casing = Paint()
      ..color = const Color(0xFFDCD5C8)
      ..strokeWidth = 7
      ..strokeCap = StrokeCap.round;
    final street = Paint()
      ..color = Colors.white
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;
    final lines = <(Offset, Offset)>[];
    for (var i = 0; i < 3; i++) {
      final x = w * (0.12 + i * 0.32 + (random.nextDouble() - 0.5) * 0.12);
      lines.add((Offset(x, -5), Offset(x + (random.nextDouble() - 0.5) * w * 0.25, h + 5)));
    }
    for (var i = 0; i < 2; i++) {
      final y = h * (0.2 + i * 0.55 + (random.nextDouble() - 0.5) * 0.1);
      lines.add((Offset(-5, y), Offset(w + 5, y + (random.nextDouble() - 0.5) * h * 0.3)));
    }
    for (final (a, b) in lines) {
      canvas.drawLine(a, b, casing);
    }
    for (final (a, b) in lines) {
      canvas.drawLine(a, b, street);
    }
    final mainY = h * (0.45 + (random.nextDouble() - 0.5) * 0.3);
    canvas.drawLine(
      Offset(-5, mainY),
      Offset(w + 5, mainY - h * 0.2),
      Paint()
        ..color = const Color(0xFFE8C766)
        ..strokeWidth = 9
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawLine(
      Offset(-5, mainY),
      Offset(w + 5, mainY - h * 0.2),
      Paint()
        ..color = const Color(0xFFF7DE8C)
        ..strokeWidth = 6
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _MapPreviewPainter oldDelegate) => oldDelegate.seed != seed;
}

// ---------------------------------------------------------------------------
// Ortak parçalar
// ---------------------------------------------------------------------------

/// Medya balonunun kabı: kuyruklu balon, sabit genişlik, ince iç boşluk.
class _MediaBubbleFrame extends StatelessWidget {
  const _MediaBubbleFrame({
    required this.isMine,
    required this.joinsAbove,
    required this.joinsBelow,
    required this.width,
    required this.semanticsLabel,
    required this.onTap,
    required this.children,
  });

  final bool isMine;
  final bool joinsAbove;
  final bool joinsBelow;
  final double width;
  final String semanticsLabel;
  final VoidCallback? onTap;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(top: joinsAbove ? 2 : 6),
        child: Semantics(
          label: semanticsLabel,
          button: onTap != null,
          child: GestureDetector(
            onTap: onTap,
            child: DecoratedBox(
              decoration: ShapeDecoration(
                color: isMine ? ChatPalette.mineBubble : ChatPalette.theirsBubble,
                shadows: ChatPalette.bubbleShadow,
                shape: ChatBubbleShape(
                  isMine: isMine,
                  tail: !joinsBelow,
                  joinsAbove: joinsAbove,
                ),
              ),
              child: Padding(
                // Kuyruk şeridi gönderen tarafında ayrılır.
                padding: EdgeInsets.fromLTRB(
                  isMine ? 4 : 4 + ChatBubbleShape.tailWidth,
                  4,
                  isMine ? 4 + ChatBubbleShape.tailWidth : 4,
                  4,
                ),
                child: SizedBox(
                  width: width,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: children,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Fotoğrafın üzerindeki saat + tikler (koyu yarı saydam hap).
class _OverlayMeta extends StatelessWidget {
  const _OverlayMeta({required this.time, required this.status});

  final String time;
  final String? status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0x73000000),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            time,
            style: ChatBubbleMeta.timeStyle.copyWith(color: Colors.white),
          ),
          if (status != null) ...[
            const SizedBox(width: 3),
            ChatStatusTicks(status: status!, color: Colors.white, size: 15),
          ],
        ],
      ),
    );
  }
}

/// Açıklama yazısı + satır sonunda saat (metin balonuyla aynı yerleşim).
class _CaptionWithMeta extends StatelessWidget {
  const _CaptionWithMeta({
    required this.text,
    required this.time,
    required this.isMine,
    required this.status,
  });

  final String text;
  final String time;
  final bool isMine;
  final String? status;

  @override
  Widget build(BuildContext context) {
    final metaWidth = ChatBubbleMeta.reservedWidth(
      context,
      time: time,
      withTicks: isMine && status != null,
    );
    return Stack(
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: text),
              WidgetSpan(child: SizedBox(width: metaWidth, height: 14)),
            ],
          ),
          style: const TextStyle(fontSize: 15, height: 1.3, color: ChatPalette.text),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: ChatBubbleMeta(time: time, isMine: isMine, status: status),
        ),
      ],
    );
  }
}

class _FailedOverlay extends StatelessWidget {
  const _FailedOverlay();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Color(0x80000000),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.refresh_rounded, color: Colors.white, size: 30),
            SizedBox(height: 2),
            Text(
              'Gönderilemedi • Tekrar dene',
              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Ek menüsü
// ---------------------------------------------------------------------------

enum ChatAttachmentAction { gallery, camera, location }

/// Yazı kutusunun yanındaki "+" düğmesinin menüsü: Galeri, Kamera, Konum.
Future<ChatAttachmentAction?> showChatAttachmentSheet(
  BuildContext context, {
  bool cameraAvailable = true,
}) {
  return showModalBottomSheet<ChatAttachmentAction>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (sheetContext) {
      Widget option(ChatAttachmentAction action, IconData icon, String label, Color color) {
        return Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => Navigator.pop(sheetContext, action),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
                    child: Icon(icon, color: Colors.white, size: 26),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: ChatPalette.text,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: const Color(0xFFD9D4E5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  option(
                    ChatAttachmentAction.gallery,
                    Icons.photo_library_rounded,
                    'Galeri',
                    const Color(0xFF7E57C2),
                  ),
                  if (cameraAvailable)
                    option(
                      ChatAttachmentAction.camera,
                      Icons.photo_camera_rounded,
                      'Kamera',
                      const Color(0xFFEC407A),
                    ),
                  option(
                    ChatAttachmentAction.location,
                    Icons.location_on_rounded,
                    'Konum',
                    const Color(0xFF26A69A),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    },
  );
}
