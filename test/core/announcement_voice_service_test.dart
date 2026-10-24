import 'package:cizreapp/core/services/announcement_voice_service.dart';
import 'package:cizreapp/core/services/voice_announce_settings_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeEngine implements VoiceEngine {
  final List<String> calls = [];
  List<Map<String, String>> voiceList = const [];
  VoidCallback? onDone;

  List<String> get spoken =>
      calls.where((c) => c.startsWith('speak:')).map((c) => c.substring(6)).toList();

  @override
  Future<void> prepare({required VoidCallback onDone}) async {
    this.onDone = onDone;
  }

  @override
  Future<List<Map<String, String>>> voices() async => voiceList;

  @override
  Future<void> setVoice(Map<String, String> voice) async => calls.add('voice:${voice['name']}');

  @override
  Future<void> clearVoice() async => calls.add('clearVoice');

  @override
  Future<void> setPitch(double pitch) async => calls.add('pitch:$pitch');

  @override
  Future<void> speak(String text) async => calls.add('speak:$text');

  @override
  Future<void> stop() async => calls.add('stop');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('composeText', () {
    test('karşılama + başlık + içerik', () {
      expect(
        AnnouncementVoiceService.composeText(
          title: 'Yeni kampanya',
          body: 'Bugün indirim var',
          firstName: 'Ahmet',
        ),
        'Merhaba Ahmet, Yeni kampanya. Bugün indirim var',
      );
    });

    test('başlık noktalama ile bitiyorsa ikinci nokta eklenmez', () {
      expect(
        AnnouncementVoiceService.composeText(title: 'Duyuru!', body: 'Metin', greeting: false),
        'Duyuru! Metin',
      );
    });

    test('sesli metin başlık ve içeriğin yerine okunur', () {
      expect(
        AnnouncementVoiceService.composeText(
          title: 'T',
          body: 'B',
          voiceText: 'Özel sesli metin',
          firstName: 'Ayşe',
        ),
        'Merhaba Ayşe, Özel sesli metin',
      );
    });

    test('{ad} yer tutucusu adla değişir, ayrıca karşılama eklenmez', () {
      expect(
        AnnouncementVoiceService.composeText(
          voiceText: 'Sevgili {ad}, siparişin yolda',
          firstName: 'Can',
        ),
        'Sevgili Can, siparişin yolda',
      );
    });

    test('ad bilinmiyorsa {ad} ve virgülü silinir', () {
      expect(
        AnnouncementVoiceService.composeText(voiceText: '{ad}, siparişin yolda'),
        'siparişin yolda',
      );
    });

    test('karşılama kapalı ya da ad yoksa düz metin', () {
      expect(
        AnnouncementVoiceService.composeText(title: 'T', body: 'B', firstName: 'X', greeting: false),
        'T. B',
      );
      expect(AnnouncementVoiceService.composeText(title: 'T', body: 'B'), 'T. B');
      expect(AnnouncementVoiceService.composeText(), '');
    });
  });

  test('firstNameOf', () {
    expect(AnnouncementVoiceService.firstNameOf('Ayşe Nur Kaya', 'ayse'), 'Ayşe');
    expect(AnnouncementVoiceService.firstNameOf('  ', 'kullanici'), 'kullanici');
    expect(AnnouncementVoiceService.firstNameOf(null, null), isNull);
    // Kayıtta verilen geçici kullanıcı adı okunmaz ("Merhaba misafir_ab12" olmasın).
    expect(AnnouncementVoiceService.firstNameOf(null, 'misafir_ab12'), isNull);
  });

  group('ses seçimi', () {
    test('cinsiyet: iOS anahtarı, Samsung ve Google adları', () {
      expect(AnnouncementVoiceService.genderOfVoice({'name': 'Yelda', 'gender': 'female'}),
          VoiceGender.female);
      expect(AnnouncementVoiceService.genderOfVoice({'name': 'tr-TR-SMTm00'}), VoiceGender.male);
      expect(AnnouncementVoiceService.genderOfVoice({'name': 'tr-TR-SMTf00'}), VoiceGender.female);
      expect(AnnouncementVoiceService.genderOfVoice({'name': 'tr-tr-x-mfm-local'}),
          VoiceGender.male);
      expect(AnnouncementVoiceService.genderOfVoice({'name': 'tr-tr-x-efs-network'}),
          VoiceGender.female);
      expect(AnnouncementVoiceService.genderOfVoice({'name': 'tr-tr-language'}), isNull);
    });

    test('Türkçe, kurulu ve yerel ses tercih edilir', () {
      final voices = [
        {'name': 'en-us-x-iom-local', 'locale': 'en-US'},
        {'name': 'tr-tr-x-mfm-network', 'locale': 'tr-TR', 'network_required': '1'},
        {'name': 'tr-tr-x-tmc-local', 'locale': 'tr-TR', 'network_required': '0'},
        {'name': 'tr-tr-x-cfs-local', 'locale': 'tr-TR', 'features': 'notInstalled'},
      ];
      expect(AnnouncementVoiceService.pickVoice(voices, VoiceGender.male)?['name'],
          'tr-tr-x-tmc-local');
      expect(AnnouncementVoiceService.pickVoice(voices, VoiceGender.female), isNull);
    });
  });

  group('VoiceAnnounceSettings', () {
    test('fromJson alanları ve tırnaklı değerleri okur', () {
      final s = VoiceAnnounceSettings.fromJson({
        'enabled': 'true',
        'gender': 'male',
        'areas': 'startup, courier,bilinmeyen',
        'greeting': false,
      });
      expect(s.enabled, isTrue);
      expect(s.gender, VoiceGender.male);
      expect(s.areas, {VoiceArea.startup, VoiceArea.courier});
      expect(s.greeting, isFalse);
      expect(s.areasValue, 'startup,courier');
    });

    test('boş alan listesi "none" yazılır, eksik alanlar varsayılan', () {
      final none = VoiceAnnounceSettings.fromJson({'areas': ''});
      expect(none.areas, isEmpty);
      expect(none.areasValue, 'none');
      expect(VoiceAnnounceSettings.fromJson(const {}), VoiceAnnounceSettings.defaults);
    });
  });

  group('okuma kapıları', () {
    late _FakeEngine engine;
    late VoiceAnnounceSettings settings;
    late bool userAuto;

    AnnouncementVoiceService make() => AnnouncementVoiceService(
          engine: engine,
          settingsLoader: () async => settings,
          firstNameLoader: () async => 'Ahmet',
          userAutoLoader: () async => userAuto,
        );

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      AnnouncementVoiceService.debugResetQuietZone();
      engine = _FakeEngine();
      settings = VoiceAnnounceSettings.defaults;
      userAuto = true;
    });

    test('her şey açıksa kişiye özel okur, aynı duyuru ikinci kez okunmaz', () async {
      final s = make();
      expect(
        await s.announce(area: VoiceArea.adminNotifications, title: 'T', body: 'B', dedupKey: 'admin:1'),
        isTrue,
      );
      expect(engine.spoken, ['Merhaba Ahmet, T. B']);
      expect(s.speakingKey.value, 'admin:1');
      expect(
        await s.announce(area: VoiceArea.adminNotifications, title: 'T', body: 'B', dedupKey: 'admin:1'),
        isFalse,
      );
      expect(engine.spoken, hasLength(1));
      await s.stop();
    });

    test('admin kapattıysa, bölüm kapalıysa ya da kullanıcı kapattıysa okumaz', () async {
      final s = make();
      settings = const VoiceAnnounceSettings(enabled: false);
      expect(await s.announce(area: VoiceArea.startup, title: 'T', dedupKey: 'a'), isFalse);
      settings = const VoiceAnnounceSettings(areas: {VoiceArea.courier});
      expect(await s.announce(area: VoiceArea.startup, title: 'T', dedupKey: 'b'), isFalse);
      settings = VoiceAnnounceSettings.defaults;
      userAuto = false;
      expect(await s.announce(area: VoiceArea.startup, title: 'T', dedupKey: 'c'), isFalse);
      expect(engine.spoken, isEmpty);
    });

    test('Okey masasında (sessiz bölge) otomatik okumaz, Dinle çalışır', () async {
      final s = make();
      AnnouncementVoiceService.enterQuietZone();
      expect(await s.announce(area: VoiceArea.adminNotifications, title: 'T', dedupKey: 'q'), isFalse);
      expect(await s.toggleListen(key: 'q', title: 'T'), isTrue);
      AnnouncementVoiceService.exitQuietZone();
      expect(engine.spoken, ['Merhaba Ahmet, T']);
      await s.stop();
    });

    test('Dinle kullanıcı otomatik okumayı kapatmış olsa da okur; ikinci basış durdurur', () async {
      final s = make();
      userAuto = false;
      expect(await s.toggleListen(key: 'k', title: 'Başlık', body: 'Metin'), isTrue);
      expect(s.speakingKey.value, 'k');
      expect(await s.toggleListen(key: 'k'), isFalse);
      expect(s.speakingKey.value, isNull);
      expect(engine.calls.last, 'pitch:1.0');
    });

    test('Dinle, admin ana anahtarı kapalıysa okumaz', () async {
      final s = make();
      settings = const VoiceAnnounceSettings(enabled: false);
      expect(await s.toggleListen(key: 'k', title: 'T'), isFalse);
      expect(engine.spoken, isEmpty);
    });

    test('istenen cinsiyette ses varsa seçilir, yoksa ton ayarlanır; bitince geri alınır', () async {
      final s = make();
      engine.voiceList = [
        {'name': 'tr-tr-x-mfm-local', 'locale': 'tr-TR', 'network_required': '0'},
      ];
      await s.toggleListen(key: 'm', title: 'T', gender: 'male');
      expect(engine.calls, containsAllInOrder(['voice:tr-tr-x-mfm-local', 'pitch:1.0', 'speak:Merhaba Ahmet, T']));

      engine.onDone!();
      expect(s.speakingKey.value, isNull);
      await Future<void>.delayed(Duration.zero);
      expect(engine.calls.sublist(engine.calls.length - 2), ['clearVoice', 'pitch:1.0']);

      engine.calls.clear();
      await s.toggleListen(key: 'f', title: 'T', gender: 'female');
      expect(
        engine.calls,
        containsAllInOrder([
          'clearVoice',
          'pitch:${AnnouncementVoiceService.femalePitchFallback}',
          'speak:Merhaba Ahmet, T',
        ]),
      );
      await s.stop();
    });

    test('kurye duyuruları: okunmamış ilk duyuru okunur, düzenlenince tekrar', () async {
      final s = make();
      final notices = [
        {'id': 'n1', 'title': 'Yağmur', 'message': 'Gecikme olabilir', 'updated_at': 'u1'},
        {'id': 'n2', 'title': 'Bayram', 'message': 'Kapalıyız', 'updated_at': 'u1'},
      ];
      expect(await s.announceCourierNotices(notices), isTrue);
      expect(await s.announceCourierNotices(notices), isTrue); // ikinci duyuru
      expect(await s.announceCourierNotices(notices), isFalse);
      expect(engine.spoken, [
        'Merhaba Ahmet, Yağmur. Gecikme olabilir',
        'Merhaba Ahmet, Bayram. Kapalıyız',
      ]);
      notices[0]['updated_at'] = 'u2';
      expect(await s.announceCourierNotices(notices), isTrue);
      await s.stop();
    });
  });
}
