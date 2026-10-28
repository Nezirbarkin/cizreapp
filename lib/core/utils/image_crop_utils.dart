import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui' show Rect, Size;

/// Görsel kırpma yardımcıları — kırpma editörü ve gönderi yükleme aynı
/// hesabı kullanır (Görev 2.8).

/// [imageSize] boyutundaki görselin ORTASINDAN [aspectRatio] oranında
/// alınabilecek en büyük bölge (`BoxFit.cover` karşılığı).
Rect centerCropRect(Size imageSize, double aspectRatio) {
  final w = imageSize.width;
  final h = imageSize.height;
  if (w <= 0 || h <= 0 || aspectRatio <= 0) return Rect.zero;
  if (w / h > aspectRatio) {
    // Görsel çerçeveden geniş: iki yandan kesilir.
    final cropWidth = h * aspectRatio;
    return Rect.fromLTWH((w - cropWidth) / 2, 0, cropWidth, h);
  }
  // Görsel çerçeveden uzun: üstten ve alttan kesilir.
  final cropHeight = w / aspectRatio;
  return Rect.fromLTWH(0, (h - cropHeight) / 2, w, cropHeight);
}

/// Kırpma çıktısının piksel boyutu. Genişlik [maxWidth]'i ve kaynak bölgenin
/// kendi çözünürlüğünü aşmaz: küçük bir bölgeyi büyütmek netlik kazandırmaz,
/// yalnızca dosyayı şişirir.
(int, int) cropOutputSize(Rect source, double aspectRatio, {required int maxWidth}) {
  final width = math.max(1, math.min(maxWidth, source.width.round()));
  final height = math.max(1, (width / aspectRatio).round());
  return (width, height);
}

/// Görselin ekranda çizildiği haliyle oranı (genişlik/yükseklik).
///
/// Küçültülerek çözülür (yalnızca oran gerekiyor); EXIF yönü motorun çözdüğü
/// görüntüye zaten uygulanmış olduğundan döndürülmüş telefon fotoğrafında da
/// doğru sonuç verir. Çözülemezse null.
Future<double?> readImageAspectRatio(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 256);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final ratio = image.width / image.height;
    image.dispose();
    codec.dispose();
    return ratio;
  } catch (_) {
    return null;
  }
}

/// Görselin ekranda çizildiği haliyle piksel boyutu (EXIF yönü uygulanmış);
/// çözülemezse null. Tam çözer — yalnız zaten küçültülmüş görselde kullanın.
Future<Size?> readImageSize(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final size = Size(image.width.toDouble(), image.height.toDouble());
    image.dispose();
    codec.dispose();
    return size;
  } catch (_) {
    return null;
  }
}

/// [image]'i önce yatayda aynalayıp ([mirrored]) sonra [quarterTurns] kez
/// saat yönünün TERSİNE 90° döndürerek yeni bir görsel üretir.
///
/// Dönüşüm matrisi tam sayıdır (0/±1): pikseller birebir taşınır, süzme
/// bulanıklığı olmaz. Dönen görselin sahibi çağırandır (dispose etmeli).
Future<ui.Image> renderOrientedImage(
  ui.Image image, {
  int quarterTurns = 0,
  bool mirrored = false,
}) async {
  final turns = quarterTurns % 4;
  final w = image.width.toDouble();
  final h = image.height.toDouble();
  final outWidth = turns.isOdd ? image.height : image.width;
  final outHeight = turns.isOdd ? image.width : image.height;

  // x' = a·x + b·y, y' = c·x + d·y
  var a = mirrored ? -1.0 : 1.0;
  var b = 0.0;
  var c = 0.0;
  var d = 1.0;
  for (var i = 0; i < turns; i++) {
    // Ekranda (y aşağı) saat yönünün tersine 90°: (x, y) → (y, −x).
    final na = c;
    final nb = d;
    final nc = -a;
    final nd = -b;
    a = na;
    b = nb;
    c = nc;
    d = nd;
  }
  // Kaynağın merkezi çıktının merkezine oturur.
  final tx = outWidth / 2 - (a * w / 2 + b * h / 2);
  final ty = outHeight / 2 - (c * w / 2 + d * h / 2);

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.transform(Float64List.fromList([
    a, c, 0, 0, //
    b, d, 0, 0, //
    0, 0, 1, 0, //
    tx, ty, 0, 1, //
  ]));
  canvas.drawImage(image, ui.Offset.zero, ui.Paint());
  final picture = recorder.endRecording();
  try {
    return await picture.toImage(outWidth, outHeight);
  } finally {
    picture.dispose();
  }
}

/// [image]'in [source] bölgesini [width]×[height] boyutunda PNG'ye çizer.
///
/// Zemin beyazdır: saydam bir PNG sonradan JPEG'e sıkıştırılırken saydam
/// alanlar siyaha dönmesin.
///
/// Süzme kalitesi ölçeğe göre seçilir: küçültmede (asıl durum: 1920 → 1080)
/// `medium` (mipmap), büyütmede `high` (bikübik). `high` küçültmede hem daha
/// kötü sonuç verir hem de kırpma kenarına bölgenin DIŞINDAKİ pikselleri
/// karıştırır (Flutter FilterQuality belgesi).
Future<Uint8List> renderImageRegionPng(
  ui.Image image,
  Rect source,
  int width,
  int height,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  final destination = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  final upscaling = width > source.width + 0.5 || height > source.height + 0.5;
  canvas.drawRect(destination, ui.Paint()..color = const ui.Color(0xFFFFFFFF));
  canvas.drawImageRect(
    image,
    source,
    destination,
    ui.Paint()
      ..filterQuality = upscaling ? ui.FilterQuality.high : ui.FilterQuality.medium,
  );
  final picture = recorder.endRecording();
  final output = await picture.toImage(width, height);
  picture.dispose();
  try {
    final data = await output.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('PNG kodlanamadı');
    return data.buffer.asUint8List();
  } finally {
    output.dispose();
  }
}

/// Görseli ortasından [aspectRatio] oranına kırpar (PNG döner).
///
/// Görsel zaten bu orandaysa null döner: yeniden kodlamak yalnızca kalite
/// kaybettirir, çağıran orijinal baytları kullanır. Çözülemeyen görselde
/// istisna fırlatır.
Future<Uint8List?> centerCropToAspect(
  Uint8List bytes,
  double aspectRatio, {
  int maxWidth = 1080,
}) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final frame = await codec.getNextFrame();
  final image = frame.image;
  try {
    final size = Size(image.width.toDouble(), image.height.toDouble());
    final source = centerCropRect(size, aspectRatio);
    if ((source.width - size.width).abs() < 1.5 &&
        (source.height - size.height).abs() < 1.5) {
      return null;
    }
    final (width, height) = cropOutputSize(source, aspectRatio, maxWidth: maxWidth);
    return await renderImageRegionPng(image, source, width, height);
  } finally {
    image.dispose();
    codec.dispose();
  }
}
