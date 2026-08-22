import 'package:flutter_test/flutter_test.dart';
import 'package:cizreapp/sehirici/sehirici.dart';

/// Tracker testleri: Singleton + state machine testleri.
/// Geolocator platform kanalı bu testlerde mock'lanmaz — yalnızca
/// izleme state'i (isTracking, lastPosition, lastWriteAt) doğrulanır.
void main() {
  group('SehiriciLocationTracker başlangıç state', () {
    test('yeni instance izlemiyor ve trip null', () {
      final tracker = SehiriciLocationTracker();
      // Singleton — birden fazla factory çağrısı aynı instance'ı döner
      expect(identical(tracker, SehiriciLocationTracker()), true);
      expect(tracker.isTracking, false);
      expect(tracker.currentTripId, isNull);
      expect(tracker.lastPosition, isNull);
      expect(tracker.lastWriteAt, isNull);
    });
  });

  group('SehiriciLocationTracker stop', () {
    test('stop sonrası tüm state sıfırlanır', () async {
      final tracker = SehiriciLocationTracker();
      // stop() henüz başlatılmamış tracker için idempotent olmalı
      await tracker.stop();
      expect(tracker.isTracking, false);
      expect(tracker.currentTripId, isNull);
      expect(tracker.lastWriteAt, isNull);
    });
  });
}
