import 'dart:async';

import 'package:cizreapp/okey/engine/okey_action_queue.dart';
import 'package:flutter_test/flutter_test.dart';

/// HAMLE KUYRUĞU — "süre bitmeden taş atamıyorum" hatasının regresyon testi.
///
/// GEÇMİŞ: Eşzamanlı hamleleri engellemek için konan koruma şöyleydi:
/// ```dart
/// if (_actionInFlight) return; // hamle DÜŞÜRÜLÜR
/// ```
/// Bu, taş çekildikten hemen sonra yapılan atma denemelerini sessizce çöpe
/// atıyordu; kullanıcı defalarca deniyor, hiçbir şey olmuyor ve süre doluyordu.
///
/// Aşağıdaki ilk test tam olarak o davranışı kovalar: SIRAYA ALINAN HİÇBİR
/// HAMLE KAYBOLMAMALI.
void main() {
  group('OkeyActionQueue', () {
    test('üst üste gelen hamlelerin HİÇBİRİ düşmez', () async {
      final queue = OkeyActionQueue();
      final ran = <int>[];

      // Üçü de neredeyse aynı anda gelir — tıpkı çek + at + at gibi
      final futures = [
        queue.add(() async {
          await Future<void>.delayed(const Duration(milliseconds: 30));
          ran.add(1);
        }),
        queue.add(() async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          ran.add(2);
        }),
        queue.add(() async {
          ran.add(3);
        }),
      ];

      await Future.wait(futures);

      expect(
        ran,
        [1, 2, 3],
        reason:
            'hamleler ya düştü ya da sıra bozuldu — '
            'kullanıcının attığı taş kaybolur',
      );
    });

    test('hamleler ÜST ÜSTE BİNMEZ', () async {
      final queue = OkeyActionQueue();
      var active = 0;
      var maxActive = 0;

      Future<void> work() async {
        active++;
        maxActive = active > maxActive ? active : maxActive;
        await Future<void>.delayed(const Duration(milliseconds: 15));
        active--;
      }

      await Future.wait([queue.add(work), queue.add(work), queue.add(work)]);

      expect(
        maxActive,
        1,
        reason: 'iki hamle aynı anda çalıştı — sunucu APP:wrong_phase döner',
      );
    });

    test('bir hamle hata verse bile SONRAKİLER çalışır', () async {
      final queue = OkeyActionQueue();
      final ran = <String>[];

      final failing = queue.add(() async {
        ran.add('patlayan');
        throw StateError('sunucu hatası');
      });

      final next = queue.add(() async {
        ran.add('sonraki');
      });

      // Hata çağırana iletilmeli
      await expectLater(failing, throwsA(isA<StateError>()));
      await next;

      expect(ran, [
        'patlayan',
        'sonraki',
      ], reason: 'bir hatadan sonra kuyruk kilitlenirse oyun oynanamaz olur');
    });

    test('hata çağırana İLETİLİR (sessizce yutulmaz)', () async {
      final queue = OkeyActionQueue();

      await expectLater(
        queue.add(() async => throw StateError('x')),
        throwsA(isA<StateError>()),
      );
    });

    test('bekleyen hamle sayısı doğru izlenir', () async {
      final queue = OkeyActionQueue();
      expect(queue.pendingCount, 0);

      final completer = Completer<void>();
      final f = queue.add(() => completer.future);
      expect(queue.pendingCount, 1);

      completer.complete();
      await f;
      // whenComplete mikro görevde çalışır
      await Future<void>.delayed(Duration.zero);
      expect(queue.pendingCount, 0);
    });
  });
}
