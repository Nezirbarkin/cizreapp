/// Kullanıcının kendi cihazından eklediği şarkılar — "Kitaplığım".
///
/// ## Neden dosya kopyalanıyor
///
/// Android'de dosya seçici (SAF) bize kalıcı bir yol değil, uygulamanın
/// önbelleğine açılmış geçici bir kopya verir. Önbellek sistem tarafından her
/// an temizlenebilir; indekste o yolu saklasaydık kullanıcının kitaplığı
/// kendiliğinden boşalırdı. Bu yüzden dosya, uygulamanın kendi belge
/// klasöründeki `music/` altına kopyalanır ve indekste o yol tutulur.
///
/// ## Neden sunucuya hiçbir şey gitmiyor
///
/// Kitaplık tamamen cihazda kalır: ne dosya ne de dosya adı sunucuya yazılır.
/// Bunun iki sonucu var — telefon değişince kitaplık gelmez (bilinen ve
/// kabul edilmiş sınır), buna karşılık telifli bir dosyanın uygulamanın
/// sunucusunda durması diye bir durum da oluşmaz. Sunucuya yalnızca kullanıcı
/// bir parçayı gönderiye/hikayeye İLİŞTİRDİĞİNDE 15 saniyelik kesit gider.
///
/// ## Web
///
/// Web'de `dart:io` yok; dosya kopyalanamaz. [MusicLibraryService.isSupported]
/// false döner ve arayüz "Kitaplığım" sekmesini ekleme düğmesi olmadan
/// gösterir. Cizre Radyo sekmesi web'de de çalışır.
library;

import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

import '../models/music_track.dart';
import 'mp3_clipper.dart';
import 'music_settings_service.dart';

/// Kullanıcıya gösterilecek somut bir sebebi olan kitaplık hatası.
///
/// Sessizce null dönmek çoğu durumda doğru (kullanıcı seçimi iptal etti gibi),
/// ama "bu bir ses dosyası değil" gibi durumlarda sessizlik kullanıcıyı
/// düğmeye tekrar tekrar bastırır.
class MusicLibraryException implements Exception {
  final String message;
  const MusicLibraryException(this.message);
  @override
  String toString() => message;
}

/// Uygulamanın kabul ettiği ses uzantıları.
///
/// Depo kepçelerindeki `allowed_mime_types` listesiyle aynı kümeyi hedefler;
/// biri değişirse diğeri de değişmeli.
const Set<String> kAudioExtensions = {
  '.mp3',
  '.m4a',
  '.aac',
  '.mp4',
  '.ogg',
  '.oga',
  '.wav',
  '.flac',
  '.opus',
  '.weba',
  '.webm',
};

bool isAudioFileName(String name) {
  final ext = p.extension(name).toLowerCase();
  return kAudioExtensions.contains(ext);
}

class MusicLibraryService {
  MusicLibraryService._();

  static final MusicLibraryService instance = MusicLibraryService._();

  static const String _indexKey = 'music_library_index_v1';
  static const _uuid = Uuid();

  /// Cihaz kitaplığı bu platformda kullanılabilir mi?
  static bool get isSupported => !kIsWeb;

  /// Yan menüdeki plak kartının (uygulama geneli fon müziği) çalma listesine
  /// katılacak cihaz parçaları.
  ///
  /// `main.dart` bunu [OkeySoundService.localTracksProvider] kancasına bağlar.
  /// Müzik özelliği admin tarafından kapatıldıysa boş döner — kapalı bir
  /// özelliğin şarkıları arka planda çalmaya devam etmemeli. Ayar ağdan
  /// OKUNMAZ, önbellekteki değer kullanılır: fon müziği listesi her yan menü
  /// açılışında tazeleniyor ve her seferinde bir istek atmak gereksiz yük.
  static Future<List<({String url, String name})>>
  backgroundPlaylistEntries() async {
    if (!isSupported) return const [];
    if (!MusicSettingsService.cached.feature) return const [];
    final tracks = await instance.load();
    return [
      for (final t in tracks)
        if ((t.localPath ?? '').isNotEmpty) (url: t.localPath!, name: t.title),
    ];
  }

  List<MusicTrack>? _cache;

  /// Kitaplıktaki şarkılar. İlk çağrıda indeks okunur, sonrası bellekten.
  ///
  /// Dosyası artık var olmayan kayıtlar sessizce ayıklanır: kullanıcı
  /// uygulamayı yeniden kurmuş ya da veriyi temizlemiş olabilir ve olmayan bir
  /// dosyayı listede göstermek tek sonuç olarak "çalmıyor" şikâyeti üretir.
  Future<List<MusicTrack>> load({bool forceRefresh = false}) async {
    if (!isSupported) return const [];
    if (!forceRefresh && _cache != null) return _cache!;

    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_indexKey);
      if (raw == null || raw.isEmpty) {
        _cache = const [];
        return _cache!;
      }

      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        _cache = const [];
        return _cache!;
      }

      final tracks = <MusicTrack>[];
      var prunedAny = false;
      for (final item in decoded) {
        if (item is! Map) continue;
        final track = MusicTrack.fromLibraryJson(
          Map<String, dynamic>.from(item),
        );
        final path = track.localPath;
        if (track.id.isEmpty || path == null || path.isEmpty) continue;
        if (!File(path).existsSync()) {
          prunedAny = true;
          continue;
        }
        tracks.add(track);
      }

      _cache = tracks;
      if (prunedAny) await _persist(tracks);
      return tracks;
    } catch (e) {
      debugPrint('⚠️ Müzik kitaplığı okunamadı: $e');
      _cache = const [];
      return _cache!;
    }
  }

  /// Cihazdan bir ses dosyası seçtirip kitaplığa ekler.
  ///
  /// Kullanıcı seçimi iptal ederse ya da bir şey ters giderse null döner —
  /// müzik opsiyonel bir özellik, hata fırlatıp ekranı kilitlemesi anlamsız.
  Future<MusicTrack?> addFromDevice() async {
    if (!isSupported) return null;

    try {
      // TÜR SÜZGECİ BİLEREK YOK. Okey ses yüklemesinde öğrenildi (bkz.
      // okey_admin_content.dart): Android dosya seçicisi uzantıyı MIME'a
      // çevirip süzdüğü için `.m4a` dosyaları cihaza göre soluk kalıp
      // SEÇİLEMİYOR. Süzgeci kaldırıp doğrulamayı kendimiz yapınca bu cihaz
      // farkı ortadan kalkıyor.
      final result = await FilePicker.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        // Baytları burada istemiyoruz: büyük bir şarkıyı belleğe almak yerine
        // dosyayı akışla kopyalamak hem hızlı hem düşük bellekli.
        withData: false,
      );

      if (result == null || result.files.isEmpty) return null;
      final picked = result.files.first;
      final sourcePath = picked.path;
      if (sourcePath == null || sourcePath.isEmpty) return null;

      if (!isAudioFileName(picked.name) && !isAudioFileName(sourcePath)) {
        throw const MusicLibraryException('Bu bir ses dosyası değil.');
      }

      final dir = await _libraryDir();
      final id = _uuid.v4();
      // Ad uzantısız gelebiliyor (Android seçicisinde sık); o durumda geçici
      // kopyanın yolundaki uzantıya düşüyoruz.
      var ext = p.extension(picked.name).toLowerCase();
      if (ext.isEmpty) ext = p.extension(sourcePath).toLowerCase();
      final target = File(p.join(dir.path, '$id${ext.isEmpty ? '.mp3' : ext}'));

      await File(sourcePath).copy(target.path);

      final title = p.basenameWithoutExtension(picked.name).trim();
      final track = MusicTrack(
        id: id,
        title: title.isEmpty ? 'Şarkı' : title,
        localPath: target.path,
        durationMs: await _readDuration(target),
        kind: MusicSourceKind.device,
      );

      final next = [...await load(), track];
      await _persist(next);
      _cache = next;
      return track;
    } on MusicLibraryException {
      // Kullanıcıya söylenecek somut bir sebep var — yutmuyoruz.
      rethrow;
    } catch (e) {
      debugPrint('⚠️ Cihazdan müzik eklenemedi: $e');
      return null;
    }
  }

  /// Şarkıyı kitaplıktan ve diskten siler.
  Future<void> remove(String id) async {
    if (!isSupported) return;
    final current = await load();
    final target = current.where((t) => t.id == id).firstOrNull;

    final next = current.where((t) => t.id != id).toList();
    await _persist(next);
    _cache = next;

    final path = target?.localPath;
    if (path == null) return;
    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } catch (_) {
      // Dosya silinemese de kitaplıkta görünmüyor; kullanıcı açısından silindi.
    }
  }

  Future<void> rename(String id, String title) async {
    if (!isSupported) return;
    final clean = title.trim();
    if (clean.isEmpty) return;

    final next = (await load())
        .map((t) => t.id == id ? t.copyWith(title: clean) : t)
        .toList();
    await _persist(next);
    _cache = next;
  }

  /// Bir kitaplık parçasının baytları — kesme ve yükleme için.
  Future<Uint8List?> readBytes(MusicTrack track) async {
    final path = track.localPath;
    if (!isSupported || path == null) return null;
    try {
      final file = File(path);
      if (!file.existsSync()) return null;
      return await file.readAsBytes();
    } catch (e) {
      debugPrint('⚠️ Müzik dosyası okunamadı: $e');
      return null;
    }
  }

  Future<Directory> _libraryDir() async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'music'));
    if (!dir.existsSync()) await dir.create(recursive: true);
    return dir;
  }

  /// Süreyi MP3 çerçevelerinden ölçer.
  ///
  /// MP3 olmayan dosyalarda null kalır: süre yalnızca listede gösterilen bir
  /// süs ve kırpma çubuğunun ölçeği: bilinmiyorsa liste "—" gösterir, kırpma
  /// çubuğu da oynatıcıdan gelen gerçek süreyi bekler.
  Future<int?> _readDuration(File file) async {
    try {
      if (!Mp3Clipper.looksLikeMp3(file.path)) return null;
      return Mp3Clipper.durationMs(await file.readAsBytes());
    } catch (_) {
      return null;
    }
  }

  Future<void> _persist(List<MusicTrack> tracks) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _indexKey,
        jsonEncode(tracks.map((t) => t.toLibraryJson()).toList()),
      );
    } catch (e) {
      debugPrint('⚠️ Müzik kitaplığı kaydedilemedi: $e');
    }
  }
}
