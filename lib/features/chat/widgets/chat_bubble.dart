import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../core/models/message_model.dart';

/// Sohbet ekranının renkleri (Görev 2.3 — WhatsApp/Telegram tarzı).
///
/// Kendi balonum markanın AÇIK tonu, karşı tarafınki beyaz; ikisi de koyu
/// yazı taşır. Eskiden kendi balonum koyu mor + beyaz yazıydı: "okundu"
/// tikinin mavisi o zeminde seçilmiyordu.
abstract final class ChatPalette {
  static const Color accent = Colors.deepPurple;
  static const Color wallpaper = Color(0xFFEFEAF6);
  static const Color wallpaperGlyph = Color(0x0F5E35B1);
  static const Color mineBubble = Color(0xFFE6DCFF);
  static const Color theirsBubble = Colors.white;
  static const Color text = Color(0xFF1D1A26);
  static const Color mineMeta = Color(0xFF6E6690);
  static const Color theirsMeta = Color(0xFF8A8796);
  static const Color readTick = Color(0xFF1E9BE9);
  static const Color failed = Color(0xFFD64545);
  static const Color dayPill = Color(0xE6FFFFFF);
  static const Color dayPillText = Color(0xFF5C5670);
  /// Balonun altında 1 px'lik keskin, yarı saydam gölge çizgisi.
  ///
  /// PERFORMANS: eskiden `blurRadius: 1.5` idi. Balon özel (kuyruklu) bir yol
  /// olduğundan Impeller her balonun bulanık gölgesini ayrı bir ekran dışı
  /// katmanda iki geçişli bulanıklaştırmayla çiziyordu: ~15 balonlu bir
  /// konuşmada kare başına ~22 ms GPU kodlama, kaydırırken karelerin
  /// çoğu 33 ms'yi aşıyordu (cihaz ölçümü 2026-10-07). Bulanıklık 0 iken
  /// gölge sıradan bir dolgu olarak çizilir.
  static const List<BoxShadow> bubbleShadow = [
    BoxShadow(color: Color(0x14000000), offset: Offset(0, 1)),
  ];
}

/// Türkiye saatiyle gün ayraçları: "Bugün", "Dün", son bir hafta için gün
/// adı, bu yıl için "12 Eylül", daha eskisi için "12 Eylül 2025".
abstract final class ChatDayLabel {
  static const _offset = Duration(hours: 3);
  static const _months = [
    'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran',
    'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
  ];
  static const _weekdays = [
    'Pazartesi', 'Salı', 'Çarşamba', 'Perşembe', 'Cuma', 'Cumartesi', 'Pazar',
  ];

  /// Anın Türkiye'deki takvim günü (saat bilgisi atılmış, UTC olarak).
  static DateTime day(DateTime t) {
    final tr = t.toUtc().add(_offset);
    return DateTime.utc(tr.year, tr.month, tr.day);
  }

  /// İki an Türkiye saatiyle aynı günde mi? (Eskiden ayraç kararı UTC
  /// günüyle, etiket Türkiye günüyle veriliyordu: gece 00:00–03:00 arasında
  /// aynı gün iki kez "Bugün" ayracı çıkabiliyordu.)
  static bool sameDay(DateTime a, DateTime b) => day(a) == day(b);

  static String format(DateTime date, {DateTime? now}) {
    final d = day(date);
    final today = day(now ?? DateTime.now());
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Bugün';
    if (diff == 1) return 'Dün';
    if (diff > 1 && diff < 7) return _weekdays[d.weekday - 1];
    final base = '${d.day} ${_months[d.month - 1]}';
    return d.year == today.year ? base : '$base ${d.year}';
  }

  /// Mesaj saati (Türkiye saati, SS:DD).
  static String time(DateTime t) {
    final tr = t.toUtc().add(_offset);
    return '${tr.hour.toString().padLeft(2, '0')}:'
        '${tr.minute.toString().padLeft(2, '0')}';
  }
}

/// Aynı kişinin art arda (aynı gün, [window] içinde) gönderdiği mesajlar tek
/// öbek gibi görünür: aralarındaki boşluk daralır, yalnız öbeğin SON balonu
/// kuyruk taşır.
abstract final class ChatGrouping {
  static const Duration window = Duration(minutes: 5);

  static bool joins(Message earlier, Message later) {
    if (earlier.senderId != later.senderId) return false;
    if (_isCard(earlier) || _isCard(later)) return false;
    if (!ChatDayLabel.sameDay(earlier.createdAt, later.createdAt)) return false;
    return later.createdAt.difference(earlier.createdAt).abs() <= window;
  }

  static bool _isCard(Message m) => m.isSharedPost || m.isSharedIlan;
}

/// Balon şekli: yuvarlatılmış gövde + gönderen tarafında alt köşede küçük
/// kuyruk. Kuyruk şeridi ([tailWidth]) kuyruk olmasa da ayrılır, böylece
/// öbekteki balonların kenarları hizalı kalır.
class ChatBubbleShape extends ShapeBorder {
  const ChatBubbleShape({
    required this.isMine,
    required this.tail,
    this.joinsAbove = false,
    this.radius = 16,
    this.innerRadius = 6,
  });

  final bool isMine;

  /// Öbeğin son balonu mu (kuyruk çizilir)?
  final bool tail;

  /// Üstündeki balonla aynı öbekte mi (gönderen tarafının üst köşesi daralır)?
  final bool joinsAbove;
  final double radius;
  final double innerRadius;

  static const double tailWidth = 7;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.zero;

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) =>
      getOuterPath(rect, textDirection: textDirection);

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final path = _rightTailPath(
      Size(rect.width, rect.height),
      topSender: joinsAbove ? innerRadius : radius,
      bottomSender: tail ? 0 : innerRadius,
    );
    // Kendi balonum için olduğu gibi (kuyruk sağda); karşı tarafınki yatay
    // aynalanır (kuyruk solda).
    final matrix = isMine
        ? Matrix4.translationValues(rect.left, rect.top, 0)
        : (Matrix4.translationValues(rect.right, rect.top, 0)
            ..multiply(Matrix4.diagonal3Values(-1, 1, 1)));
    return path.transform(matrix.storage);
  }

  /// Kuyruk SAĞDA olacak şekilde, (0,0) köşeli kutuda yol.
  Path _rightTailPath(
    Size size, {
    required double topSender,
    required double bottomSender,
  }) {
    final w = size.width - tailWidth; // gövdenin sağ kenarı
    final h = size.height;
    final r = math.min(radius, math.min(w, h) / 2);
    final rTop = math.min(topSender, math.min(w, h) / 2);
    final path = Path()
      ..moveTo(r, 0)
      ..lineTo(w - rTop, 0)
      ..arcToPoint(Offset(w, rTop), radius: Radius.circular(rTop));
    if (tail) {
      // Kuyruk: gövdenin sağ kenarından aşağı-dışa kıvrılıp alt çizgide
      // sivri bir uçla biter (Telegram tarzı).
      final start = math.max(rTop, h - 10);
      path
        ..lineTo(w, start)
        ..quadraticBezierTo(w + 1, h - 1.5, w + tailWidth, h)
        ..lineTo(r, h);
    } else {
      final rb = math.min(bottomSender, math.min(w, h) / 2);
      path
        ..lineTo(w, h - rb)
        ..arcToPoint(Offset(w - rb, h), radius: Radius.circular(rb))
        ..lineTo(r, h);
    }
    path
      ..arcToPoint(Offset(0, h - r), radius: Radius.circular(r))
      ..lineTo(0, r)
      ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
      ..close();
    return path;
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {}

  @override
  ShapeBorder scale(double t) => ChatBubbleShape(
    isMine: isMine,
    tail: tail,
    joinsAbove: joinsAbove,
    radius: radius * t,
    innerRadius: innerRadius * t,
  );

  @override
  bool operator ==(Object other) =>
      other is ChatBubbleShape &&
      other.isMine == isMine &&
      other.tail == tail &&
      other.joinsAbove == joinsAbove &&
      other.radius == radius &&
      other.innerRadius == innerRadius;

  @override
  int get hashCode => Object.hash(isMine, tail, joinsAbove, radius, innerRadius);
}

/// Mesaj durumu tikleri: saat = gönderiliyor, tek tik = gönderildi,
/// MAVİ çift tik = okundu, kırmızı ünlem = gönderilemedi.
class ChatStatusTicks extends StatelessWidget {
  const ChatStatusTicks({
    super.key,
    required this.status,
    this.color = ChatPalette.mineMeta,
    this.size = 16,
  });

  /// [Message.messageStatus]: `sending`, `sent`, `read`, `failed`.
  final String status;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color tint, String label) = switch (status) {
      'failed' => (Icons.error_outline, ChatPalette.failed, 'Gönderilemedi'),
      'sending' => (Icons.schedule, color, 'Gönderiliyor'),
      'read' => (Icons.done_all, ChatPalette.readTick, 'Okundu'),
      _ => (Icons.done, color, 'Gönderildi'),
    };
    return Semantics(
      label: label,
      child: Icon(
        icon,
        size: status == 'sending' ? size - 3 : size,
        color: tint,
      ),
    );
  }
}

/// Balonun sağ altındaki saat (+ kendi mesajımda tik).
class ChatBubbleMeta extends StatelessWidget {
  const ChatBubbleMeta({
    super.key,
    required this.time,
    required this.isMine,
    this.status,
  });

  final String time;
  final bool isMine;
  final String? status;

  static const TextStyle timeStyle = TextStyle(
    fontSize: 11,
    height: 1.2,
    fontWeight: FontWeight.w500,
  );

  /// Satır sonunda meta için ayrılacak genişlik (yazı ölçeğiyle).
  static double reservedWidth(
    BuildContext context, {
    required String time,
    required bool withTicks,
  }) {
    final painter = TextPainter(
      text: TextSpan(text: time, style: timeStyle),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final width = painter.width + (withTicks ? 3 + 16 : 0) + 8;
    painter.dispose();
    return width;
  }

  @override
  Widget build(BuildContext context) {
    final color = isMine ? ChatPalette.mineMeta : ChatPalette.theirsMeta;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(time, style: timeStyle.copyWith(color: color)),
        if (isMine && status != null) ...[
          const SizedBox(width: 3),
          ChatStatusTicks(status: status!, color: color),
        ],
      ],
    );
  }
}

/// Yanıtlanan mesajın balon içindeki alıntısı (sol vurgu çizgili kutu).
class ChatReplyQuote extends StatelessWidget {
  const ChatReplyQuote({
    super.key,
    required this.senderName,
    required this.content,
    required this.isMine,
  });

  final String senderName;
  final String content;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: ColoredBox(
        color: isMine ? const Color(0x1F5E35B1) : const Color(0x125E35B1),
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const ColoredBox(
                color: ChatPalette.accent,
                child: SizedBox(width: 3),
              ),
              Flexible(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 5, 10, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        senderName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: ChatPalette.accent,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF5B5670),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// WhatsApp/Telegram tarzı metin balonu: kuyruk, öbekleme, sağ altta saat ve
/// tikler (son satırda yer varsa yazıyla AYNI satırda), balon içi alıntı.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.text,
    required this.time,
    required this.isMine,
    this.status,
    this.joinsAbove = false,
    this.joinsBelow = false,
    this.replySenderName,
    this.replyContent,
    this.maxWidthFactor = 0.78,
  });

  final String text;
  final String time;
  final bool isMine;

  /// Kendi mesajımın durumu ([Message.messageStatus]); karşınınkinde null.
  final String? status;

  /// Aynı öbekte üstte/altta başka balon var mı?
  final bool joinsAbove;
  final bool joinsBelow;

  final String? replySenderName;
  final String? replyContent;
  final double maxWidthFactor;

  bool get _hasReply => replyContent != null && replyContent!.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final tail = !joinsBelow;
    final metaWidth = ChatBubbleMeta.reservedWidth(
      context,
      time: time,
      withTicks: isMine && status != null,
    );
    const textStyle = TextStyle(
      fontSize: 15.5,
      height: 1.3,
      color: ChatPalette.text,
    );

    // Saat son satıra sığıyorsa yazının yanında, sığmıyorsa alt satırda
    // durur: satır sonuna meta genişliğinde görünmez bir boşluk eklenir,
    // meta da balonun sağ altına yerleştirilir.
    final body = Stack(
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(text: text),
              WidgetSpan(child: SizedBox(width: metaWidth, height: 14)),
            ],
          ),
          style: textStyle,
        ),
        Positioned(
          right: 0,
          bottom: 0,
          child: ChatBubbleMeta(time: time, isMine: isMine, status: status),
        ),
      ],
    );

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.only(top: joinsAbove ? 2 : 6),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: screenWidth * maxWidthFactor),
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: isMine ? ChatPalette.mineBubble : ChatPalette.theirsBubble,
              shadows: ChatPalette.bubbleShadow,
              shape: ChatBubbleShape(
                isMine: isMine,
                tail: tail,
                joinsAbove: joinsAbove,
              ),
            ),
            child: Padding(
              // Kuyruk şeridi gönderen tarafında ayrılır.
              padding: EdgeInsets.fromLTRB(
                isMine ? 10 : 10 + ChatBubbleShape.tailWidth,
                7,
                isMine ? 9 + ChatBubbleShape.tailWidth : 9,
                6,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_hasReply) ...[
                    ChatReplyQuote(
                      senderName: replySenderName ?? 'Yanıt',
                      content: replyContent!,
                      isMine: isMine,
                    ),
                    const SizedBox(height: 5),
                  ],
                  body,
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Gün ayracı: ortada yarı saydam hap ("Bugün", "Dün", "12 Eylül").
class ChatDayPill extends StatelessWidget {
  const ChatDayPill({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: ChatPalette.dayPill,
            borderRadius: BorderRadius.circular(10),
            boxShadow: ChatPalette.bubbleShadow,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: ChatPalette.dayPillText,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Sohbet zemini: açık ton + çok soluk desen (WhatsApp duvar kâğıdı gibi).
///
/// PERFORMANS: desen eskiden ekran boyunca ~650 vektör simge olarak her
/// karede çiziliyordu. RepaintBoundary Dart tarafındaki boyamayı önlese de
/// Impeller'da resim önbelleği yok — çizgiler/eğriler her karede GPU'da
/// yeniden işleniyor, sohbet ekranında kare başına ~30 ms raster sürüyordu
/// (kaydırırken her 3 kareden biri 33 ms'yi aşıyordu; cihaz ölçümü
/// 2026-10-06). Artık desen bir kez 256×256'lık bir karoya çizilir ve zemin bu
/// karonun tekrarıyla (tek bir dokulu dikdörtgen) doldurulur. Görünüm aynıdır.
class ChatWallpaper extends StatelessWidget {
  const ChatWallpaper({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return ColoredBox(
      color: ChatPalette.wallpaper,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: CustomPaint(painter: _WallpaperPainter(dpr)),
          ),
          child,
        ],
      ),
    );
  }
}

class _WallpaperPainter extends CustomPainter {
  const _WallpaperPainter(this.devicePixelRatio);

  final double devicePixelRatio;

  static const double _cell = 64;

  /// Desen 4 hücrede bir tekrar eder (glif = (satır+sütun) % 4, kayma =
  /// satırın tekliği), yani 4×4 hücrelik karo kusursuz döşenir.
  static const double _tile = _cell * 4;

  /// Cihaz piksel oranına göre bir kez üretilen karo görüntüleri.
  static final Map<double, ui.Image> _tiles = {};

  static ui.Image _tileFor(double dpr) {
    return _tiles[dpr] ??= () {
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder)..scale(dpr);
      canvas.clipRect(const Rect.fromLTWH(0, 0, _tile, _tile));
      // Kenarı aşan glifler komşu karoda da aynı yere düşer: karonun bir hücre
      // dışını da çiz, kırpma kenarları birleştirir.
      _paintGlyphs(canvas, fromRow: -1, toRow: 5, fromCol: -1, toCol: 6);
      final picture = recorder.endRecording();
      final px = (_tile * dpr).round();
      final image = picture.toImageSync(px, px);
      picture.dispose();
      return image;
    }();
  }

  @override
  void paint(Canvas canvas, Size size) {
    final dpr = devicePixelRatio <= 0 ? 1.0 : devicePixelRatio;
    final scale = 1 / dpr;
    final shader = ui.ImageShader(
      _tileFor(dpr),
      TileMode.repeated,
      TileMode.repeated,
      Float64List.fromList([
        scale, 0, 0, 0, //
        0, scale, 0, 0,
        0, 0, 1, 0,
        0, 0, 0, 1,
      ]),
      filterQuality: FilterQuality.medium,
    );
    canvas.drawRect(Offset.zero & size, Paint()..shader = shader);
  }

  /// Desen: satır/sütun ızgarası, tek satırlar yarım hücre kaydırılır.
  static void _paintGlyphs(
    Canvas canvas, {
    required int fromRow,
    required int toRow,
    required int fromCol,
    required int toCol,
  }) {
    final stroke = Paint()
      ..color = ChatPalette.wallpaperGlyph
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round;
    final fill = Paint()..color = ChatPalette.wallpaperGlyph;

    for (var row = fromRow; row < toRow; row++) {
      final y = row * _cell;
      final shift = row.isOdd ? _cell / 2 : 0.0;
      for (var col = fromCol; col < toCol; col++) {
        final x = -shift + col * _cell;
        final c = Offset(x + _cell / 2, y + _cell / 2);
        switch ((row + col) % 4) {
          case 0: // küçük konuşma balonu
            final rect = Rect.fromCenter(center: c, width: 18, height: 13);
            canvas.drawRRect(
              RRect.fromRectAndRadius(rect, const Radius.circular(5)),
              stroke,
            );
            canvas.drawLine(
              rect.bottomLeft + const Offset(4, 0),
              rect.bottomLeft + const Offset(1, 4),
              stroke,
            );
          case 1: // halka
            canvas.drawCircle(c, 5, stroke);
          case 2: // üç nokta
            for (final dx in const [-6.0, 0.0, 6.0]) {
              canvas.drawCircle(c + Offset(dx, 0), 1.6, fill);
            }
          default: // küçük kalp
            final heart = Path()
              ..moveTo(c.dx, c.dy + 5)
              ..cubicTo(c.dx - 9, c.dy - 1, c.dx - 4, c.dy - 8, c.dx, c.dy - 3)
              ..cubicTo(c.dx + 4, c.dy - 8, c.dx + 9, c.dy - 1, c.dx, c.dy + 5);
            canvas.drawPath(heart, stroke);
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WallpaperPainter oldDelegate) =>
      oldDelegate.devicePixelRatio != devicePixelRatio;
}
