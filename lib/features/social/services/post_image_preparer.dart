import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/utils/image_compression_helper.dart';
import '../../../core/utils/image_crop_utils.dart';
import '../../../core/utils/image_type_sniffer.dart';
import '../models/post_image_format.dart';

/// Yüklemeye hazır gönderi fotoğrafı.
class PreparedPostImage {
  const PreparedPostImage({
    required this.bytes,
    required this.extension,
    required this.contentType,
  });

  final Uint8List bytes;

  /// Dosya adı uzantısı (`jpg`, `png`...) — içerikle UYUMLU. Depolama
  /// istemcisi içerik türünü uzantıdan da çıkarır.
  final String extension;
  final String contentType;
}

/// Gönderi fotoğrafını yüklemeye hazırlar (Görev 2.8):
///
/// 1. Çerçeveye oturtur: kullanıcı bu çerçeveye elle kırptıysa onun sonucu,
///    kırpmadıysa fotoğrafın ORTASI (önizleme de `cover` ile ortayı
///    gösteriyordu — yüklenen görüntü önizlemeyle aynı olur).
/// 2. En fazla 1080 px genişlikte JPEG'e sıkıştırır.
///
/// Hiçbir adım paylaşımı engellemez: çözülemeyen bir biçim kırpılmadan,
/// sıkıştırılamayan (ör. web'de sıkıştırıcı yok) fotoğraf olduğu gibi
/// yüklenir; akış yine de çerçeveye `cover` ile oturtur.
class PostImagePreparer {
  const PostImagePreparer({
    this.centerCrop = _defaultCenterCrop,
    this.compress = _defaultCompress,
  });

  /// Ortadan kırpma; görsel zaten bu orandaysa null.
  final Future<Uint8List?> Function(Uint8List bytes, double aspectRatio) centerCrop;

  /// JPEG sıkıştırma; başarısızsa null.
  final Future<Uint8List?> Function(Uint8List bytes) compress;

  static Future<Uint8List?> _defaultCenterCrop(Uint8List bytes, double aspectRatio) =>
      centerCropToAspect(bytes, aspectRatio, maxWidth: 1080);

  static Future<Uint8List?> _defaultCompress(Uint8List bytes) =>
      ImageCompressionHelper.compressXFile(
        xFile: XFile.fromData(bytes, name: 'post_image'),
        quality: 85,
        maxWidth: 1080,
        maxHeight: 1920,
      );

  Future<PreparedPostImage> prepare(PostDraftImage draft, double aspectRatio) async {
    Uint8List framed;
    if (draft.isCroppedFor(aspectRatio)) {
      framed = draft.croppedBytes!;
    } else {
      try {
        framed = await centerCrop(draft.bytes, aspectRatio) ?? draft.bytes;
      } catch (e) {
        debugPrint('⚠️ Gönderi fotoğrafı çerçeveye kırpılamadı, olduğu gibi yüklenecek: $e');
        framed = draft.bytes;
      }
    }

    final compressed = await compress(framed);
    if (compressed != null && compressed.isNotEmpty) {
      return PreparedPostImage(bytes: compressed, extension: 'jpg', contentType: 'image/jpeg');
    }

    final (extension, contentType) = sniffImageType(framed, fallbackName: draft.file.name);
    return PreparedPostImage(bytes: framed, extension: extension, contentType: contentType);
  }
}
