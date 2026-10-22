import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'shared_tts.dart';
import 'voice_announce_settings_service.dart';

/// Konuşma motoru soyutlaması (testlerde sahtesi verilir).
abstract class VoiceEngine {
  /// Bir kez: dil, hız, iOS ses kategorisi, geri çağrılar.
  Future<void> prepare({required VoidCallback onDone});
  Future<List<Map<String, String>>> voices();
  Future<void> setVoice(Map<String, String> voice);
  Future<void> clearVoice();
  Future<void> setPitch(double pitch);
  Future<void> speak(String text);
  Future<void> stop();
}

/// Gerçek motor: uygulamadaki ortak [FlutterTts] örneği.
class FlutterTtsVoiceEngine implements VoiceEngine {
  bool _prepared = false;

  FlutterTts get _tts => sharedFlutterTts();

  @override
  Future<void> prepare({required VoidCallback onDone}) async {
    if (_prepared) return;
    final tts = _tts;
    // iOS: Okey masasıyla aynı kategori — telefon sessizdeyse okumaz, çalan
    // müziği kesmez, yalnız kısar.
    if (!kIsWeb && Platform.isIOS) {
      await tts.setSharedInstance(true);
      await tts.setIosAudioCategory(
        IosTextToSpeechAudioCategory.ambient,
        [
          IosTextToSpeechAudioCategoryOptions.mixWithOthers,
          IosTextToSpeechAudioCategoryOptions.duckOthers,
        ],
        IosTextToSpeechAudioMode.voicePrompt,
      );
    }
    await tts.setLanguage('tr-TR');
    await tts.setSpeechRate(0.5);
    await tts.setVolume(1.0);
    await tts.awaitSpeakCompletion(false);
    tts.setCompletionHandler(onDone);
    tts.setErrorHandler((_) => onDone());
    _prepared = true;
  }

  @override
  Future<List<Map<String, String>>> voices() async {
    final raw = await _tts.getVoices;
    if (raw is! List) return const [];
    return [
      for (final v in raw)
        if (v is Map)
          {
            for (final e in v.entries)
              if (e.key != null && e.value != null) '${e.key}': '${e.value}',
          },
    ];
  }

  @override
  Future<void> setVoice(Map<String, String> voice) async {
    await _tts.setVoice({
      'name': voice['name'] ?? '',
      'locale': voice['locale'] ?? '',
      if (voice['identifier'] != null) 'identifier': voice['identifier']!,
    });
  }

  @override
  Future<void> clearVoice() async => _tts.clearVoice();

  @override
  Future<void> setPitch(double pitch) async => _tts.setPitch(pitch);

  @override
  Future<void> speak(String text) async => _tts.speak(text);

  @override
  Future<void> stop() async => _tts.stop();
}

/// Yönetici duyurularını telefonun Türkçe sesiyle okur.
///
/// * Otomatik okuma ([announce]): admin ana anahtarı + bölüm açık + kullanıcının
///   "Sesli duyurular" tercihi açık + Okey masasında değil + bu duyuru daha önce
///   okunmamış olmalı.
/// * "Dinle" ([toggleListen]): kullanıcının açık eylemi; yalnız admin ana
///   anahtarına bakar (kullanıcı otomatik okumayı kapatmış olsa da çalışır).
/// * Kişiye özel: "Merhaba Ahmet, …" (admin karşılamayı kapatabilir); admin
///   sesli metne `{ad}` yazarsa ad oraya konur.
/// * Ses: kampanyanın sesi, yoksa admin varsayılanı. Telefonda o cinsiyette
///   Türkçe ses yoksa ton ile yaklaşılır (birçok iPhone'da erkek ses yok).
///
/// ASLA hata fırlatmaz: ses tamamen opsiyoneldir.
class AnnouncementVoiceService {
  AnnouncementVoiceService({
    VoiceEngine? engine,
    Future<VoiceAnnounceSettings> Function()? settingsLoader,
    Future<String?> Function()? firstNameLoader,
    Future<bool> Function()? userAutoLoader,
    Future<SharedPreferences> Function()? prefs,
  })  : _engine = engine ?? FlutterTtsVoiceEngine(),
        _settingsLoader = settingsLoader ?? VoiceAnnounceSettingsService.fetch,
        _firstNameLoader = firstNameLoader,
        _userAutoLoader = userAutoLoader,
        _prefs = prefs ?? SharedPreferences.getInstance;

  static final AnnouncementVoiceService instance = AnnouncementVoiceService();

  static const String _spokenKeysPref = 'voice_spoken_keys_v1';
  static const String _userAutoPrefPrefix = 'voice_auto_enabled_';
  static const int _spokenKeysMax = 200;

  /// Erkek ses bulunamazsa / kadın ses bulunamazsa kullanılan ton.
  static const double malePitchFallback = 0.8;
  static const double femalePitchFallback = 1.1;

  final VoiceEngine _engine;
  final Future<VoiceAnnounceSettings> Function() _settingsLoader;
  final Future<String?> Function()? _firstNameLoader;
  final Future<bool> Function()? _userAutoLoader;
  final Future<SharedPreferences> Function() _prefs;

  /// Şu an okunan içeriğin anahtarı (Dinle düğmeleri "Durdur" gösterir).
  final ValueNotifier<String?> speakingKey = ValueNotifier<String?>(null);

  bool _unavailable = false;
  bool _engineDirty = false;
  Timer? _fallbackTimer;
  List<Map<String, String>>? _voicesCache;
  final Map<String, String?> _nameCache = {};

  // --- Sessiz bölge (Okey masası) ---------------------------------------------

  static int _quietDepth = 0;

  /// Okey masası gibi kendi sesli anonsu olan ekranlar açıkken otomatik
  /// okuma susar ("Dinle" yine çalışır).
  static void enterQuietZone() => _quietDepth++;

  static void exitQuietZone() {
    if (_quietDepth > 0) _quietDepth--;
  }

  static bool get isQuiet => _quietDepth > 0;

  @visibleForTesting
  static void debugResetQuietZone() => _quietDepth = 0;

  // --- Kullanıcı tercihi (yerel önbellek) -----------------------------------

  /// Bildirim Ayarları ekranı değiştirince/yükleyince çağırır.
  static Future<void> cacheUserAutoEnabled(String userId, bool enabled) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setBool('$_userAutoPrefPrefix$userId', enabled);
    } catch (_) {}
  }

  // --- Saf yardımcılar --------------------------------------------------------

  /// "Ayşe Nur Kaya" → "Ayşe"; ad yoksa kullanıcı adı; ikisi de yoksa null.
  @visibleForTesting
  static String? firstNameOf(String? fullName, String? username) {
    final full = fullName?.trim() ?? '';
    if (full.isNotEmpty) {
      final first = full.split(RegExp(r'\s+')).first;
      if (first.isNotEmpty) return first;
    }
    final u = username?.trim() ?? '';
    return u.isEmpty ? null : u;
  }

  /// Okunacak metni kurar.
  @visibleForTesting
  static String composeText({
    String? title,
    String? body,
    String? voiceText,
    String? firstName,
    bool greeting = true,
  }) {
    final name = firstName?.trim();
    final hasName = name != null && name.isNotEmpty;
    final custom = voiceText?.trim() ?? '';

    String core;
    var nameUsed = false;
    if (custom.isNotEmpty) {
      if (custom.contains('{ad}')) {
        nameUsed = true;
        core = hasName
            ? custom.replaceAll('{ad}', name)
            // Ad bilinmiyorsa yer tutucu ve ona yapışık virgül/boşluk silinir.
            : custom
                .replaceAll(RegExp(r'\s*\{ad\}\s*,?'), ' ')
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim();
      } else {
        core = custom;
      }
    } else {
      final t = title?.trim() ?? '';
      final b = body?.trim() ?? '';
      if (t.isEmpty) {
        core = b;
      } else if (b.isEmpty) {
        core = t;
      } else {
        final sep = RegExp(r'[.!?…:]$').hasMatch(t) ? ' ' : '. ';
        core = '$t$sep$b';
      }
    }
    if (greeting && hasName && !nameUsed && core.isNotEmpty) {
      return 'Merhaba $name, $core';
    }
    return core;
  }

  // Google TTS yerel Türkçe ses kodları (tr-tr-x-<kod>-local/network).
  static const Map<String, VoiceGender> _googleVoiceCodes = {
    'cfs': VoiceGender.female,
    'efs': VoiceGender.female,
    'ama': VoiceGender.female,
    'mfm': VoiceGender.male,
    'tmc': VoiceGender.male,
  };

  /// Bir sesin cinsiyeti; bilinmiyorsa null.
  @visibleForTesting
  static VoiceGender? genderOfVoice(Map<String, String> voice) {
    final g = voice['gender']?.toLowerCase();
    if (g == 'male') return VoiceGender.male;
    if (g == 'female') return VoiceGender.female;

    final name = (voice['name'] ?? '').toLowerCase();
    if (RegExp(r'(^|[^a-z])female([^a-z]|$)').hasMatch(name)) return VoiceGender.female;
    if (RegExp(r'(^|[^a-z])male([^a-z]|$)').hasMatch(name)) return VoiceGender.male;
    // Samsung: tr-TR-SMTf00 / SMTm00
    final smt = RegExp(r'smt([fm])\d').firstMatch(name);
    if (smt != null) {
      return smt.group(1) == 'm' ? VoiceGender.male : VoiceGender.female;
    }
    // Google: tr-tr-x-mfm-local
    final g2 = RegExp(r'-x-([a-z]{3})(-|$)').firstMatch(name);
    if (g2 != null) return _googleVoiceCodes[g2.group(1)];
    return null;
  }

  /// İstenen cinsiyette Türkçe ses; yerel (indirilmiş) ses tercih edilir.
  @visibleForTesting
  static Map<String, String>? pickVoice(
    List<Map<String, String>> voices,
    VoiceGender gender,
  ) {
    bool isTurkish(Map<String, String> v) =>
        (v['locale'] ?? '').toLowerCase().replaceAll('_', '-').startsWith('tr');
    bool notInstalled(Map<String, String> v) =>
        (v['features'] ?? '').contains('notInstalled');
    int score(Map<String, String> v) {
      var s = 0;
      if ((v['network_required'] ?? '0') == '0') s += 2;
      final q = (v['quality'] ?? '').toLowerCase();
      if (q.contains('enhanced') || q.contains('premium') || q.contains('high')) s += 1;
      return s;
    }

    final matches = voices
        .where((v) => isTurkish(v) && !notInstalled(v) && genderOfVoice(v) == gender)
        .toList()
      ..sort((a, b) => score(b).compareTo(score(a)));
    return matches.isEmpty ? null : matches.first;
  }

  // --- Okuma ------------------------------------------------------------------

  /// Otomatik okuma. Okunduysa true.
  Future<bool> announce({
    required VoiceArea area,
    String? title,
    String? body,
    String? voiceText,
    String? gender,
    String? dedupKey,
  }) async {
    try {
      if (_unavailable || isQuiet) return false;
      final settings = await _settingsLoader();
      if (!settings.allowsAuto(area)) return false;
      if (!await _userAutoEnabled()) return false;
      if (dedupKey != null && !await _markSpokenOnce(dedupKey)) return false;
      return await _speak(
        key: dedupKey ?? 'auto:${area.key}',
        settings: settings,
        title: title,
        body: body,
        voiceText: voiceText,
        gender: gender,
      );
    } catch (e) {
      debugPrint('⚠️ Sesli duyuru okunamadı: $e');
      return false;
    }
  }

  /// Kurye duyuruları (`courier_service_notices` satırları, öncelik sırasıyla):
  /// daha önce okunmamış İLK duyuru bir kez okunur. Duyuru düzenlenirse
  /// (updated_at değişir) yeniden okunur.
  Future<bool> announceCourierNotices(List<Map<String, dynamic>> notices) async {
    try {
      if (notices.isEmpty) return false;
      final p = await _prefs();
      final spoken = p.getStringList(_spokenKeysPref) ?? const <String>[];
      for (final n in notices) {
        final id = n['id'];
        if (id == null) continue;
        final stamp = n['updated_at'] ?? n['created_at'] ?? '';
        final key = 'courier:$id:$stamp';
        if (spoken.contains(key)) continue;
        return announce(
          area: VoiceArea.courier,
          title: n['title'] as String?,
          body: n['message'] as String?,
          dedupKey: key,
        );
      }
    } catch (e) {
      debugPrint('⚠️ Kurye duyurusu okunamadı: $e');
    }
    return false;
  }

  /// "Dinle" düğmesi: aynı içerik okunuyorsa durdurur, değilse okur.
  Future<bool> toggleListen({
    required String key,
    String? title,
    String? body,
    String? voiceText,
    String? gender,
  }) async {
    try {
      if (speakingKey.value == key) {
        await stop();
        return false;
      }
      if (_unavailable) return false;
      final settings = await _settingsLoader();
      if (!settings.enabled) return false;
      if (key.isNotEmpty) await _rememberSpoken(key);
      return await _speak(
        key: key,
        settings: settings,
        title: title,
        body: body,
        voiceText: voiceText,
        gender: gender,
      );
    } catch (e) {
      debugPrint('⚠️ Duyuru dinletilemedi: $e');
      return false;
    }
  }

  Future<void> stop() async {
    _fallbackTimer?.cancel();
    speakingKey.value = null;
    try {
      await _engine.stop();
    } catch (_) {}
    await _restoreEngine();
  }

  Future<bool> _speak({
    required String key,
    required VoiceAnnounceSettings settings,
    String? title,
    String? body,
    String? voiceText,
    String? gender,
  }) async {
    final firstName = settings.greeting || (voiceText?.contains('{ad}') ?? false)
        ? await _firstName()
        : null;
    final text = composeText(
      title: title,
      body: body,
      voiceText: voiceText,
      firstName: firstName,
      greeting: settings.greeting,
    );
    if (text.isEmpty) return false;

    try {
      await _engine.prepare(onDone: _onEngineDone);
      // Önceki okuma (duyuru ya da Okey anonsu) kesilir.
      await _engine.stop();
      await _applyVoice(VoiceGender.tryParse(gender) ?? settings.gender);
      speakingKey.value = key;
      _armFallback(text);
      await _engine.speak(text);
      return true;
    } catch (e) {
      _unavailable = true;
      speakingKey.value = null;
      debugPrint('⚠️ TTS kullanılamıyor, sesli duyurular kapalı: $e');
      return false;
    }
  }

  Future<void> _applyVoice(VoiceGender gender) async {
    Map<String, String>? voice;
    try {
      _voicesCache ??= await _engine.voices();
      voice = pickVoice(_voicesCache!, gender);
    } catch (_) {
      voice = null;
    }
    _engineDirty = true;
    if (voice != null) {
      await _engine.setVoice(voice);
      await _engine.setPitch(1.0);
    } else {
      await _engine.clearVoice();
      await _engine.setPitch(
        gender == VoiceGender.male ? malePitchFallback : femalePitchFallback,
      );
    }
  }

  /// Okey anonsları ortak motoru varsayılan sesle kullanır: bitince geri al.
  Future<void> _restoreEngine() async {
    if (!_engineDirty) return;
    _engineDirty = false;
    try {
      await _engine.clearVoice();
      await _engine.setPitch(1.0);
    } catch (_) {}
  }

  void _onEngineDone() {
    if (speakingKey.value == null) return;
    _fallbackTimer?.cancel();
    speakingKey.value = null;
    unawaited(_restoreEngine());
  }

  // Bitti olayı gelmezse (ör. motor başka yerden durduruldu) düğme takılı kalmasın.
  void _armFallback(String text) {
    _fallbackTimer?.cancel();
    final ms = (2000 + text.length * 90).clamp(2000, 180000);
    _fallbackTimer = Timer(Duration(milliseconds: ms), _onEngineDone);
  }

  // --- Kapılar ----------------------------------------------------------------

  Future<bool> _userAutoEnabled() async {
    final loader = _userAutoLoader;
    if (loader != null) return loader();
    final uid = _currentUserId();
    if (uid == null) return true; // misafir: admin ayarı yeter
    final p = await _prefs();
    final cached = p.getBool('$_userAutoPrefPrefix$uid');
    if (cached != null) return cached;
    try {
      final row = await Supabase.instance.client
          .from('notification_preferences')
          .select('voice_announcements_enabled')
          .eq('user_id', uid)
          .maybeSingle();
      final enabled = row?['voice_announcements_enabled'] as bool? ?? true;
      await p.setBool('$_userAutoPrefPrefix$uid', enabled);
      return enabled;
    } catch (_) {
      return true;
    }
  }

  /// İlk kez görülüyorsa kaydeder ve true döner.
  Future<bool> _markSpokenOnce(String key) async {
    final p = await _prefs();
    final list = p.getStringList(_spokenKeysPref) ?? const <String>[];
    if (list.contains(key)) return false;
    await _store(p, list, key);
    return true;
  }

  Future<void> _rememberSpoken(String key) async {
    final p = await _prefs();
    final list = p.getStringList(_spokenKeysPref) ?? const <String>[];
    if (list.contains(key)) return;
    await _store(p, list, key);
  }

  Future<void> _store(SharedPreferences p, List<String> list, String key) async {
    final next = [...list, key];
    final trimmed = next.length > _spokenKeysMax
        ? next.sublist(next.length - _spokenKeysMax)
        : next;
    await p.setStringList(_spokenKeysPref, trimmed);
  }

  Future<String?> _firstName() async {
    final loader = _firstNameLoader;
    if (loader != null) return loader();
    final uid = _currentUserId();
    if (uid == null) return null;
    if (_nameCache.containsKey(uid)) return _nameCache[uid];
    String? name;
    try {
      final row = await Supabase.instance.client
          .from('profiles')
          .select('full_name, username')
          .eq('id', uid)
          .maybeSingle();
      name = firstNameOf(row?['full_name'] as String?, row?['username'] as String?);
    } catch (_) {
      final meta = Supabase.instance.client.auth.currentUser?.userMetadata;
      name = firstNameOf(meta?['full_name'] as String?, meta?['username'] as String?);
    }
    _nameCache[uid] = name;
    return name;
  }

  String? _currentUserId() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }
}
