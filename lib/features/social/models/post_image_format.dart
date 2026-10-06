import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

/// Gönderi fotoğraflarının çerçevesi (Görev 2.8).
///
/// Bir gönderideki TÜM fotoğraflar aynı çerçevede gösterilir (akış kartı
/// kaydırmalı olduğu için sayfalar arasında boy değişmesin). Oran
/// `posts.image_aspect_ratio` kolonunda saklanır; akış kartı ve detay ekranı
/// fotoğrafı bu oranda, kart genişliğinde çizer.
enum PostImageFormat {
  portrait('Dikey', '4:5', 4 / 5),
  square('Kare', '1:1', 1),
  landscape('Yatay', '4:3', 4 / 3);

  const PostImageFormat(this.label, this.ratioLabel, this.aspectRatio);

  final String label;
  final String ratioLabel;

  /// Genişlik / yükseklik.
  final double aspectRatio;

  /// İlk fotoğrafın boyutuna göre önerilen çerçeve: belirgin dikey fotoğraf
  /// Dikey'e, belirgin yatay fotoğraf Yatay'a, kareye yakın olan Kare'ye
  /// oturur — böylece kullanıcı hiçbir şeye dokunmadan paylaşsa bile
  /// fotoğrafı en az kırpılır.
  static PostImageFormat suggestFor(int width, int height) {
    if (width <= 0 || height <= 0) return PostImageFormat.square;
    return suggestForAspect(width / height);
  }

  /// [suggestFor]'un oran (genişlik/yükseklik) alan hali.
  static PostImageFormat suggestForAspect(double ratio) {
    if (!ratio.isFinite || ratio <= 0) return PostImageFormat.square;
    if (ratio <= 0.9) return PostImageFormat.portrait;
    if (ratio >= 1.15) return PostImageFormat.landscape;
    return PostImageFormat.square;
  }

  /// Kayıtlı orana karşılık gelen çerçeve (DB `real` olduğu için küçük
  /// yuvarlama farkları tolere edilir); eşleşmezse null.
  static PostImageFormat? fromAspectRatio(double? ratio) {
    if (ratio == null) return null;
    for (final format in values) {
      if ((format.aspectRatio - ratio).abs() < 0.01) return format;
    }
    return null;
  }
}

/// Akışta çizilen en dar (en uzun) çerçeve: 4:5.
const double kFeedImageMinAspect = 0.8;

/// Akışta çizilen en geniş (en basık) çerçeve: 1.91:1.
const double kFeedImageMaxAspect = 1.91;

/// Gönderinin fotoğrafının akışta çizileceği oran.
///
/// Kayıtlı oran [kFeedImageMinAspect]–[kFeedImageMaxAspect] aralığına
/// sıkıştırılır (çok uzun bir ekran görüntüsü akışı kaplamasın, çok basık bir
/// panorama şerit gibi kalmasın). Oran bilinmiyorsa (eski sürüm istemcilerin,
/// adminin, botların gönderileri) kare çizilir.
double feedImageAspect(double? stored) {
  if (stored == null || !stored.isFinite || stored <= 0) return 1;
  return stored.clamp(kFeedImageMinAspect, kFeedImageMaxAspect).toDouble();
}

/// Oluşturma ekranında seçilmiş, henüz yüklenmemiş fotoğraf.
///
/// Orijinal baytlar SAKLANIR: kullanıcı çerçeveyi değiştirince ya da yeniden
/// kırpınca kırpma her zaman orijinalden yapılır (kırpılmışın kırpılması
/// fotoğrafı her seferinde biraz daha küçültürdü).
class PostDraftImage {
  PostDraftImage({required this.file, required this.bytes});

  final XFile file;

  /// Orijinal (kırpılmamış) baytlar.
  final Uint8List bytes;

  /// Kullanıcının kırpma editöründe onayladığı sonuç.
  Uint8List? croppedBytes;

  /// [croppedBytes]'ın kırpıldığı çerçeve oranı.
  double? croppedAspect;

  /// Bu fotoğraf [aspectRatio] çerçevesine elle kırpıldı mı? Çerçeve sonradan
  /// değiştiyse eski kırpma geçersizdir (fotoğraf yeni çerçeveye ortadan
  /// oturtulur); kullanıcı eski çerçeveye dönerse kırpması geri gelir.
  bool isCroppedFor(double aspectRatio) =>
      croppedBytes != null &&
      croppedAspect != null &&
      (croppedAspect! - aspectRatio).abs() < 0.001;

  /// Önizlemede/yüklemede kullanılacak baytlar: çerçeveye elle kırpıldıysa
  /// kırpılmış hali, değilse orijinal (önizleme onu çerçeveye `cover` ile
  /// oturtur, yükleme ortadan kırpar — ikisi aynı görüntüyü verir).
  Uint8List displayBytesFor(double aspectRatio) =>
      isCroppedFor(aspectRatio) ? croppedBytes! : bytes;

  void setCrop(Uint8List cropped, double aspectRatio) {
    croppedBytes = cropped;
    croppedAspect = aspectRatio;
  }
}
