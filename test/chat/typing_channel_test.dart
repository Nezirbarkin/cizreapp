import 'package:cizreapp/features/chat/services/typing_channel.dart';
import 'package:flutter_test/flutter_test.dart';

/// Ağsız taşıma: gönderilenleri kaydeder, olayları elle tetikletir.
class _FakeTransport implements TypingTransport {
  _FakeTransport({this.opens = true, this.sendAllowed = true, this.joined = true});

  bool opens;
  bool sendAllowed;
  bool joined;
  bool closed = false;
  int openCalls = 0;
  final List<Map<String, dynamic>> sent = [];
  final List<String> log = [];

  late void Function(Map<String, dynamic> payload) emit;
  late void Function(bool joined) setJoined;

  @override
  Future<bool> open({
    required void Function(Map<String, dynamic> payload) onEvent,
    required void Function(bool joined) onJoined,
  }) async {
    openCalls++;
    emit = onEvent;
    setJoined = (value) {
      joined = value;
      onJoined(value);
    };
    return opens;
  }

  @override
  bool get canSend => sendAllowed;

  @override
  bool get isJoined => joined;

  @override
  void send(Map<String, dynamic> payload) {
    sent.add(Map<String, dynamic>.from(payload));
    log.add('send:${payload['t']}');
  }

  @override
  Future<void> close() async {
    closed = true;
    log.add('close');
  }

  List<bool> get sentFlags => sent.map((p) => p['t'] as bool).toList();
}

Future<(TypingChannel, _FakeTransport)> _started({
  _FakeTransport? transport,
  String selfId = 'me',
}) async {
  final t = transport ?? _FakeTransport();
  final channel = TypingChannel(transport: t, selfId: selfId);
  await channel.start();
  return (channel, t);
}

void main() {
  group('gönderme', () {
    testWidgets('ilk tuşta HEMEN "yazıyor" gider; 3 sn içinde tekrarlanmaz', (tester) async {
      final (channel, t) = await _started();
      channel.onTextChanged('m');
      expect(t.sentFlags, [true]);
      expect(t.sent.single['u'], 'me');

      channel.onTextChanged('me');
      channel.onTextChanged('mer');
      await tester.pump(const Duration(seconds: 2));
      channel.onTextChanged('merh');
      expect(t.sentFlags, [true], reason: '3 sn dolmadan yeni ping yok');

      await tester.pump(const Duration(seconds: 1, milliseconds: 100));
      channel.onTextChanged('merha');
      expect(t.sentFlags, [true, true], reason: '3 sn sonra yeniden ping');
      await channel.dispose();
    });

    testWidgets('yazmaya ara verince 5 sn sonra bir kez "yazmıyor" gider', (tester) async {
      final (channel, t) = await _started();
      channel.onTextChanged('merhaba');
      await tester.pump(const Duration(seconds: 4));
      expect(t.sentFlags, [true]);
      await tester.pump(const Duration(seconds: 2));
      expect(t.sentFlags, [true, false]);
      await tester.pump(const Duration(seconds: 30));
      expect(t.sentFlags, [true, false], reason: 'tekrar "yazmıyor" gönderilmez');
      await channel.dispose();
    });

    testWidgets('her tuş boşta sayacını sıfırlar (yazmaya devam eden susmaz)', (tester) async {
      final (channel, t) = await _started();
      channel.onTextChanged('a');
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(seconds: 4));
        channel.onTextChanged('a' * (i + 2));
      }
      expect(t.sentFlags.contains(false), isFalse, reason: '4 sn arayla yazan hiç "yazmıyor" demez');
      await channel.dispose();
    });

    testWidgets('kutu boşalınca hemen "yazmıyor" gider ve bir sonraki tuş yeniden bildirir', (tester) async {
      final (channel, t) = await _started();
      channel.onTextChanged('merhaba');
      channel.onTextChanged('   ');
      expect(t.sentFlags, [true, false]);
      // Ping sayacı sıfırlandı: 3 sn beklemeden yeniden bildirilir
      channel.onTextChanged('s');
      expect(t.sentFlags, [true, false, true]);
      await channel.dispose();
    });

    testWidgets('yazmadıysa boş metin hiçbir şey göndermez', (tester) async {
      final (channel, t) = await _started();
      channel.onTextChanged('');
      channel.onTextChanged('  ');
      channel.stopTyping();
      expect(t.sent, isEmpty);
      await channel.dispose();
    });

    testWidgets('stopTyping (mesaj gönderildi / arka plan) bir kez "yazmıyor" der', (tester) async {
      final (channel, t) = await _started();
      channel.onTextChanged('merhaba');
      channel.stopTyping();
      channel.stopTyping();
      expect(t.sentFlags, [true, false]);
      await channel.dispose();
    });

    testWidgets('kanal henüz katılmadıysa ping gitmez ve SAYILMAZ; katılınca ilk tuş gönderir', (tester) async {
      final (channel, t) = await _started(transport: _FakeTransport(joined: false));
      channel.onTextChanged('m');
      channel.onTextChanged('me');
      expect(t.sent, isEmpty);

      t.setJoined(true);
      channel.onTextChanged('mer');
      expect(t.sentFlags, [true], reason: 'katılır katılmaz gönderilir; 3 sn kaybı yok');
      await channel.dispose();
    });

    testWidgets('kullanıcı tercihi kapalıysa (canSend=false) HİÇ gönderilmez', (tester) async {
      final (channel, t) = await _started(transport: _FakeTransport(sendAllowed: false));
      channel.onTextChanged('merhaba');
      channel.stopTyping();
      expect(t.sent, isEmpty);
      await channel.dispose();
    });

    testWidgets('gönderilen yük her seferinde yeni bir haritadır', (tester) async {
      final (channel, t) = await _started();
      channel.onTextChanged('a');
      channel.stopTyping();
      // Realtime istemcisi gönderilen haritaya type/event ekler; sahte taşıma kopya
      // aldığından burada yalnız anahtarların temiz olduğunu doğrularız.
      expect(t.sent.first.keys.toSet(), {'u', 't'});
      expect(t.sent.last.keys.toSet(), {'u', 't'});
      await channel.dispose();
    });
  });

  group('alma', () {
    testWidgets('karşı taraf yazıyor → kümeye girer, 6 sn ping gelmezse düşer', (tester) async {
      final (channel, t) = await _started();
      t.emit({'u': 'peer', 't': true});
      expect(channel.typing.value, {'peer'});

      await tester.pump(const Duration(seconds: 5));
      expect(channel.typing.value, {'peer'});
      await tester.pump(const Duration(seconds: 2));
      expect(channel.typing.value, isEmpty, reason: 'ping kesilince gösterge takılı kalmaz');
      await channel.dispose();
    });

    testWidgets('her ping süreyi uzatır', (tester) async {
      final (channel, t) = await _started();
      t.emit({'u': 'peer', 't': true});
      await tester.pump(const Duration(seconds: 4));
      t.emit({'u': 'peer', 't': true});
      await tester.pump(const Duration(seconds: 4));
      expect(channel.typing.value, {'peer'}, reason: '8. sn ama 2. pingden 4 sn sonra');
      await tester.pump(const Duration(seconds: 3));
      expect(channel.typing.value, isEmpty);
      await channel.dispose();
    });

    testWidgets('"yazmıyor" hemen kaldırır', (tester) async {
      final (channel, t) = await _started();
      t.emit({'u': 'peer', 't': true});
      t.emit({'u': 'peer', 't': false});
      expect(channel.typing.value, isEmpty);
      await tester.pump(const Duration(seconds: 10));
      expect(channel.typing.value, isEmpty);
      await channel.dispose();
    });

    testWidgets('kendi kimliğim yok sayılır', (tester) async {
      final (channel, t) = await _started(selfId: 'me');
      t.emit({'u': 'me', 't': true});
      expect(channel.typing.value, isEmpty);
      await channel.dispose();
    });

    testWidgets('bozuk yükler sessizce elenir', (tester) async {
      final (channel, t) = await _started();
      t.emit({});
      t.emit({'u': 42, 't': true});
      t.emit({'u': '', 't': true});
      t.emit({'t': true});
      t.emit({'u': 'peer'}); // t yok → yazmıyor
      expect(channel.typing.value, isEmpty);
      await channel.dispose();
    });

    testWidgets('sarmalanmış yük (payload altında) da kabul edilir', (tester) async {
      final (channel, t) = await _started();
      t.emit({
        'type': 'broadcast',
        'event': 'typing',
        'payload': {'u': 'peer', 't': true},
      });
      expect(channel.typing.value, {'peer'});
      await channel.dispose();
    });

    testWidgets('grup: birden çok kişi bağımsız yazar ve bağımsız düşer', (tester) async {
      final (channel, t) = await _started();
      t.emit({'u': 'ali', 't': true});
      await tester.pump(const Duration(seconds: 3));
      t.emit({'u': 'ayse', 't': true});
      expect(channel.typing.value, {'ali', 'ayse'});

      await tester.pump(const Duration(seconds: 4)); // ali: 7 sn → düştü; ayse: 4 sn
      expect(channel.typing.value, {'ayse'});
      await tester.pump(const Duration(seconds: 3));
      expect(channel.typing.value, isEmpty);
      await channel.dispose();
    });

    testWidgets('dinleyiciler her değişimde bildirilir', (tester) async {
      final (channel, t) = await _started();
      final seen = <Set<String>>[];
      channel.typing.addListener(() => seen.add(Set.of(channel.typing.value)));
      t.emit({'u': 'peer', 't': true});
      t.emit({'u': 'peer', 't': true}); // aynı küme: yeniden bildirim gerekmez
      t.emit({'u': 'peer', 't': false});
      expect(seen, [
        {'peer'},
        <String>{},
      ]);
      await channel.dispose();
    });

    testWidgets('kanal koparsa (joined=false) yazanlar temizlenir', (tester) async {
      final (channel, t) = await _started();
      t.emit({'u': 'peer', 't': true});
      expect(channel.typing.value, {'peer'});
      t.setJoined(false);
      expect(channel.typing.value, isEmpty);
      await channel.dispose();
    });

    testWidgets('kanal koptuğunda yazmayı da bırakırız (bağlantı yokken ping gitmez)', (tester) async {
      final (channel, t) = await _started();
      channel.onTextChanged('merhaba');
      t.setJoined(false);
      channel.onTextChanged('merhaba d');
      expect(t.sentFlags, [true], reason: 'kopukken yeni ping yok');
      await channel.dispose();
      expect(t.sentFlags, [true], reason: 'kopukken "yazmıyor" da gönderilemez, hata da vermez');
    });
  });

  group('yaşam döngüsü', () {
    testWidgets('dispose: "yazmıyor" kanal kapanmadan ÖNCE gider', (tester) async {
      final (channel, t) = await _started();
      channel.onTextChanged('merhaba');
      await channel.dispose();
      expect(t.log, ['send:true', 'send:false', 'close']);
      expect(t.closed, isTrue);
    });

    testWidgets('hiç yazmadıysa dispose yalnız kapatır', (tester) async {
      final (channel, t) = await _started();
      await channel.dispose();
      expect(t.log, ['close']);
    });

    testWidgets('dispose sonrası olaylar ve tuşlar etkisizdir, zamanlayıcı kalmaz', (tester) async {
      final (channel, t) = await _started();
      channel.onTextChanged('a');
      await channel.dispose();
      final sentBefore = t.sent.length;
      channel.onTextChanged('ab');
      t.emit({'u': 'peer', 't': true});
      await tester.pump(const Duration(seconds: 30));
      expect(t.sent.length, sentBefore);
    });

    testWidgets('iki kez dispose zararsız', (tester) async {
      final (channel, t) = await _started();
      await channel.dispose();
      await channel.dispose();
      expect(t.log.where((e) => e == 'close').length, 1);
    });

    testWidgets('özellik kapalı/yasak (open=false): kanal etkin değil, tuşlar yok sayılır', (tester) async {
      final (channel, t) = await _started(transport: _FakeTransport(opens: false));
      expect(channel.isActive, isFalse);
      channel.onTextChanged('merhaba');
      expect(t.sent, isEmpty);
      await channel.dispose();
    });

    testWidgets('start açılırken dispose edilirse kanal kapatılır', (tester) async {
      final t = _FakeTransport();
      final channel = TypingChannel(transport: t, selfId: 'me');
      final starting = channel.start();
      await channel.dispose();
      await starting;
      expect(t.closed, isTrue);
    });

    testWidgets('start ikinci kez çağrılırsa yeniden açmaz', (tester) async {
      final t = _FakeTransport();
      final channel = TypingChannel(transport: t, selfId: 'me');
      await channel.start();
      await channel.start();
      expect(t.openCalls, 1);
      expect(channel.isActive, isTrue);
      await channel.dispose();
    });
  });

  test('unwrap: düz yük aynen, sarmalanmış yük iç yük döner', () {
    expect(TypingChannel.unwrap({'u': 'a', 't': true}), {'u': 'a', 't': true});
    expect(
      TypingChannel.unwrap({
        'event': 'typing',
        'payload': {'u': 'a', 't': false},
      }),
      {'u': 'a', 't': false},
    );
  });
}
