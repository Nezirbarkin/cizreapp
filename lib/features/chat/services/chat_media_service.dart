import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/utils/image_compression_helper.dart';
import '../../../core/utils/image_crop_utils.dart';
import '../../../core/utils/image_type_sniffer.dart';

/// Gönderime hazır sohbet fotoğrafı.
class PreparedChatImage {
  const PreparedChatImage({
    required this.bytes,
    required this.width,
    required this.height,
    required this.extension,
    required this.contentType,
  });

  final Uint8List bytes;
  final int width;
  final int height;
  final String extension;
  final String contentType;
}

/// Sohbet fotoğrafları (Görev 3.1) — özel `chat_attachments` kovası.
///
/// * Yol `<gönderen>/<alıcı>/<uuid>.<uzantı>`: depo politikası yalnız
///   gönderenin kendi klasörüne yüklemesine ve yalnız iki tarafın okumasına
///   izin verir (göç 20260928000004).
/// * Kova ÖZEL: fotoğraf herkese açık bir adresle dolaşmaz. Ekranda imzalı
///   adresle gösterilir; aynı karede istenen adresler TEK istekte imzalanır ve
///   oturum boyunca saklanır. Disk önbelleği yola bağlıdır (imzalı adres
///   değişse de fotoğraf yeniden inmez).
/// * Bu cihazdan gönderilen fotoğrafın baytları bellekte tutulur: yükleme
///   sürerken ve bittikten sonra balon ağdan yeniden indirmeden çizer.
class ChatMediaService {
  ChatMediaService({SupabaseClient? client}) : _client = client;

  final SupabaseClient? _client;
  SupabaseClient get _db => _client ?? Supabase.instance.client;

  static const String bucket = 'chat_attachments';

  /// İmzalı adresin geçerlilik süresi.
  static const Duration signedUrlLifetime = Duration(hours: 24);

  /// Gönderilen fotoğrafın en uzun kenarı (px).
  static const int maxImageSide = 1600;

  static ChatMediaService? _shared;

  /// Balonların kullandığı ortak örnek (imza toplama ve önbellek paylaşılır).
  static ChatMediaService get shared => _shared ??= ChatMediaService();

  @visibleForTesting
  static set shared(ChatMediaService service) => _shared = service;

  /// Testler için bütün oturum önbelleklerini boşaltır.
  @visibleForTesting
  static void resetForTesting() {
    _shared = null;
    _localBytes.clear();
  }

  // ------------------------------------------------------------------- yol

  static const Uuid _uuid = Uuid();

  static String newImagePath({
    required String senderId,
    required String recipientId,
    required String extension,
  }) => '$senderId/$recipientId/${_uuid.v4()}.$extension';

  /// Disk önbelleği anahtarı: imzalı adres değişse de aynı kalır.
  static String cacheKeyFor(String path) => '$bucket/$path';

  // ---------------------------------------------------------- hazırlama

  /// Fotoğrafı gönderime hazırlar: en uzun kenarı [maxImageSide] px JPEG'e
  /// sıkıştırır (sıkıştırılamazsa — ör. web — olduğu gibi, gerçek türüyle)
  /// ve ekranda çizilecek boyutunu ölçer.
  static Future<PreparedChatImage> prepareImage(
    Uint8List original, {
    String fileName = 'photo',
    @visibleForTesting Future<Uint8List?> Function(Uint8List bytes)? compress,
  }) async {
    Uint8List? compressed;
    try {
      compressed = await (compress ?? _defaultCompress)(original);
    } catch (e) {
      debugPrint('⚠️ Sohbet fotoğrafı sıkıştırılamadı: $e');
    }
    final usesCompressed = compressed != null && compressed.isNotEmpty;
    final bytes = usesCompressed ? compressed : original;
    final (extension, contentType) = usesCompressed
        ? ('jpg', 'image/jpeg')
        : sniffImageType(original, fallbackName: fileName);
    final size = await readImageSize(bytes);
    return PreparedChatImage(
      bytes: bytes,
      width: size?.width.round() ?? 0,
      height: size?.height.round() ?? 0,
      extension: extension,
      contentType: contentType,
    );
  }

  static Future<Uint8List?> _defaultCompress(Uint8List bytes) =>
      ImageCompressionHelper.compressXFile(
        xFile: XFile.fromData(bytes, name: 'chat_photo'),
        quality: 82,
        maxWidth: maxImageSide,
        maxHeight: maxImageSide,
      );

  // ------------------------------------------------------------- yükleme

  /// Fotoğrafı özel kovaya yükler. Yollar benzersiz olduğundan dosya
  /// değişmez; önbellek bir yıl geçerli sayılır.
  Future<void> upload(String path, Uint8List bytes, {required String contentType}) async {
    await _db.storage.from(bucket).uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(contentType: contentType, cacheControl: '31536000'),
    );
  }

  // -------------------------------------------------------- yerel baytlar

  static final Map<String, Uint8List> _localBytes = <String, Uint8List>{};
  static const int _localBytesLimit = 24;

  /// Bu cihazdan gönderilen fotoğrafın baytlarını yola bağlar.
  static void rememberLocalBytes(String path, Uint8List bytes) {
    _localBytes.remove(path);
    _localBytes[path] = bytes;
    while (_localBytes.length > _localBytesLimit) {
      _localBytes.remove(_localBytes.keys.first);
    }
  }

  static Uint8List? localBytes(String path) => _localBytes[path];

  // ------------------------------------------------------- imzalı adres

  final Map<String, (String url, DateTime expiresAt)> _signed = {};
  final Map<String, List<Completer<String?>>> _waiting = {};
  bool _flushScheduled = false;

  /// Yolun imzalı adresi; üretilemezse (dosya yok, yetki yok, ağ) null.
  ///
  /// Aynı karede istenen bütün yollar tek `object/sign` isteğinde imzalanır.
  Future<String?> signedUrl(String path) {
    final cached = _signed[path];
    // Son beş dakikaya girmiş adres yenilenir (indirme yarıda kalmasın).
    if (cached != null &&
        cached.$2.isAfter(DateTime.now().add(const Duration(minutes: 5)))) {
      return Future<String?>.value(cached.$1);
    }
    final completer = Completer<String?>();
    (_waiting[path] ??= <Completer<String?>>[]).add(completer);
    if (!_flushScheduled) {
      _flushScheduled = true;
      scheduleMicrotask(_flush);
    }
    return completer.future;
  }

  Future<void> _flush() async {
    _flushScheduled = false;
    final batch = Map<String, List<Completer<String?>>>.of(_waiting);
    _waiting.clear();
    if (batch.isEmpty) return;
    final paths = batch.keys.toList();
    final urls = <String, String>{};
    try {
      final results = await _db.storage
          .from(bucket)
          .createSignedUrlsResult(paths, signedUrlLifetime.inSeconds);
      final expiresAt = DateTime.now().add(signedUrlLifetime);
      for (final result in results) {
        if (result is SignedUrlSuccess) {
          urls[result.path] = result.signedUrl;
          _signed[result.path] = (result.signedUrl, expiresAt);
        }
      }
    } catch (e) {
      debugPrint('⚠️ Sohbet fotoğrafı adresi imzalanamadı: $e');
    }
    for (final entry in batch.entries) {
      final url = urls[entry.key];
      for (final completer in entry.value) {
        completer.complete(url);
      }
    }
  }
}
