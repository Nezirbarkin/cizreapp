import 'package:cizreapp/okey/engine/okey_sync.dart';
import 'package:flutter_test/flutter_test.dart';

/// Görev 1.6 — masa senkronunun saf parçaları: sunucu saati ve bayat görünüm /
/// kopan kanal kararları.
void main() {
  final t0 = DateTime.utc(2026, 9, 27, 12);

  group('OkeyServerClock', () {
    late DateTime local;
    late OkeyServerClock clock;

    setUp(() {
      local = t0;
      clock = OkeyServerClock(localNow: () => local);
    });

    test('örnek yokken cihaz saati kullanılır (eski davranış)', () {
      expect(clock.hasSample, isFalse);
      expect(clock.offset, Duration.zero);
      expect(clock.now(), t0);
    });

    test('sunucu saati isteğin ortasına denk sayılır', () {
      // İstek 200 ms sürdü; sunucu, cihazdan 60 sn ileride.
      clock.addSample(
        sentAt: t0,
        receivedAt: t0.add(const Duration(milliseconds: 200)),
        serverNow: t0.add(const Duration(seconds: 60, milliseconds: 100)),
      );

      expect(clock.offset, const Duration(seconds: 60));
      local = t0.add(const Duration(seconds: 5));
      expect(clock.now(), t0.add(const Duration(seconds: 65)));
    });

    test('daha KISA gidiş-dönüşlü örnek daha güvenilirdir; uzunu yok sayılır', () {
      clock.addSample(
        sentAt: t0,
        receivedAt: t0.add(const Duration(milliseconds: 100)),
        serverNow: t0.add(const Duration(milliseconds: 50)), // fark 0
      );
      // 2 sn süren (belirsiz) örnek: 3 sn fark öneriyor ama yok sayılmalı.
      clock.addSample(
        sentAt: t0.add(const Duration(seconds: 10)),
        receivedAt: t0.add(const Duration(seconds: 12)),
        serverNow: t0.add(const Duration(seconds: 14)),
      );
      expect(clock.offset, Duration.zero);

      // Daha kısa gidiş-dönüş: kabul edilir.
      clock.addSample(
        sentAt: t0.add(const Duration(seconds: 20)),
        receivedAt: t0.add(const Duration(seconds: 20, milliseconds: 40)),
        serverNow: t0.add(const Duration(seconds: 22, milliseconds: 20)),
      );
      expect(clock.offset, const Duration(seconds: 2));
    });

    test('en iyi örnek eskiyince yenisi her halükarda alınır (saat elle değişmiş olabilir)', () {
      clock.addSample(
        sentAt: t0,
        receivedAt: t0.add(const Duration(milliseconds: 50)),
        serverNow: t0.add(const Duration(milliseconds: 25)),
      );
      final later = t0.add(OkeyServerClock.sampleMaxAge + const Duration(seconds: 1));
      clock.addSample(
        sentAt: later,
        receivedAt: later.add(const Duration(milliseconds: 400)),
        serverNow: later.add(const Duration(seconds: 30, milliseconds: 200)),
      );
      expect(clock.offset, const Duration(seconds: 30));
    });

    test('negatif ya da çok uzun gidiş-dönüş örnek sayılmaz', () {
      clock.addSample(
        sentAt: t0,
        receivedAt: t0.subtract(const Duration(milliseconds: 1)),
        serverNow: t0.add(const Duration(minutes: 5)),
      );
      clock.addSample(
        sentAt: t0,
        receivedAt: t0.add(OkeyServerClock.maxUsefulRoundTrip + const Duration(milliseconds: 1)),
        serverNow: t0.add(const Duration(minutes: 5)),
      );
      expect(clock.hasSample, isFalse);
      expect(clock.offset, Duration.zero);
    });
  });

  group('OkeyTurnSync.shouldResync', () {
    final deadline = t0;

    test('süre yoksa ya da süre yeni dolduysa okunmaz', () {
      expect(
        OkeyTurnSync.shouldResync(
          serverNow: t0.add(const Duration(minutes: 1)),
          turnDeadline: null,
          lastRefreshAt: null,
        ),
        isFalse,
      );
      expect(
        OkeyTurnSync.shouldResync(
          serverNow: deadline.add(OkeyTurnSync.staleGrace),
          turnDeadline: deadline,
          lastRefreshAt: null,
        ),
        isFalse,
        reason: 'istemciler/sunucu sırayı ilerletmeye henüz fırsat bulmadı',
      );
    });

    test('süresi çoktan geçmiş sıra: son okuma eskiyse okunur, yeniyse beklenir', () {
      final now = deadline.add(OkeyTurnSync.staleGrace + const Duration(seconds: 1));
      expect(
        OkeyTurnSync.shouldResync(serverNow: now, turnDeadline: deadline, lastRefreshAt: null),
        isTrue,
      );
      expect(
        OkeyTurnSync.shouldResync(
          serverNow: now,
          turnDeadline: deadline,
          lastRefreshAt: now.subtract(const Duration(seconds: 2)),
        ),
        isFalse,
      );
      expect(
        OkeyTurnSync.shouldResync(
          serverNow: now,
          turnDeadline: deadline,
          lastRefreshAt: now.subtract(OkeyTurnSync.staleInterval),
        ),
        isTrue,
      );
    });

    test('yeniden kurma beklemesi giderek uzar ve 30 sn\'de sabitlenir', () {
      expect(
        [for (var i = -1; i <= 6; i++) OkeyTurnSync.resubscribeDelay(i).inSeconds],
        [2, 2, 5, 10, 20, 30, 30, 30],
      );
    });
  });
}
