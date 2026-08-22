import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cizreapp/sehirici/sehirici.dart';

/// SehiriciProvider'ın realtime aktif-sefer akışına dair davranış testleri.
///
/// Buradaki iki kural, "canlı konum haritada geç görünüyor" hatasının
/// doğrudan sebebiydi ve regresyona çok açık:
///
///  1. `activeTrips` her güncellemede YENİ bir List instance'ı olmalı.
///     SehiriciLiveMap.didUpdateWidget `identical(old, new)` ile karar
///     veriyor; liste yerinde mutasyona uğrarsa widget değişikliği hiç
///     görmüyor ve araç yalnız 30 sn'lik yedek timer'da hareket ediyordu.
///
///  2. Biten sefer listeden düşmeli. Seferler DB'den silinmediği (status
///     'completed' olduğu) için, kaldırma yolu `onTripRealtimeDelete`.
void main() {
  // SehiriciProvider kurucusunda servisleri (dolayısıyla Supabase.instance)
  // oluşturuyor. Testler ağ kullanmaz — realtime yalnız subscribe edilince
  // bağlanır ve burada hiç subscribe edilmiyor; sahte kimlik bilgileri yeterli.
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    SharedPreferences.setMockInitialValues({});
    await Supabase.initialize(
      url: 'http://localhost:54321',
      publishableKey: 'test-publishable-key',
    );
  });

  SehiriciActiveTrip tripAt(String id, double lat, double lng) =>
      SehiriciActiveTrip(
        tripId: id,
        lineId: 'line-1',
        lineCode: '1A',
        lineName: 'Hastane - Üniversite',
        lineColor: '#1976D2',
        currentLat: lat,
        currentLng: lng,
        status: SehiriciTripStatus.active,
      );

  // SehiriciProvider singleton olduğu için testler arası state sızmasın diye
  // her testin başında listeyi bilinen bir hâle getiriyoruz.
  void seed(SehiriciProvider provider, List<SehiriciActiveTrip> trips) {
    for (final t in List<SehiriciActiveTrip>.from(provider.activeTrips)) {
      provider.onTripRealtimeDelete(t.tripId);
    }
    for (final t in trips) {
      provider.onTripRealtimeUpdate(t);
    }
  }

  group('onTripRealtimeUpdate', () {
    test('mevcut seferin konumu güncellenince YENİ liste instance üretir', () {
      final provider = SehiriciProvider();
      seed(provider, [tripAt('trip-1', 37.32, 42.19)]);

      final before = provider.activeTrips;
      provider.onTripRealtimeUpdate(tripAt('trip-1', 37.33, 42.20));
      final after = provider.activeTrips;

      // Kritik: liste kimliği değişmeli (yerinde mutasyon DEĞİL).
      expect(identical(before, after), isFalse,
          reason: 'activeTrips yerinde mutasyona uğrarsa SehiriciLiveMap '
              'konum değişikliğini hiç görmez');
      expect(after.single.currentLat, 37.33);
      expect(after.single.currentLng, 42.20);
    });

    test('konum güncellemesi hattın zengin alanlarını korur', () {
      final provider = SehiriciProvider();
      seed(provider, [tripAt('trip-1', 37.32, 42.19)]);

      // Realtime satırında hat join'i yoktur: kod/ad boş gelir.
      provider.onTripRealtimeUpdate(SehiriciActiveTrip(
        tripId: 'trip-1',
        lineId: 'line-1',
        lineCode: '',
        lineName: '',
        lineColor: '#1976D2',
        currentLat: 37.40,
        currentLng: 42.25,
        status: SehiriciTripStatus.active,
      ));

      expect(provider.activeTrips.single.lineCode, '1A');
      expect(provider.activeTrips.single.lineName, 'Hastane - Üniversite');
      expect(provider.activeTrips.single.currentLat, 37.40);
    });

    test('yeni sefer listeye eklenir', () {
      final provider = SehiriciProvider();
      seed(provider, [tripAt('trip-1', 37.32, 42.19)]);

      provider.onTripRealtimeUpdate(tripAt('trip-2', 37.35, 42.22));

      expect(provider.activeTrips.map((t) => t.tripId),
          containsAll(<String>['trip-1', 'trip-2']));
    });
  });

  group('onTripRealtimeDelete', () {
    test('biten sefer listeden düşer', () {
      final provider = SehiriciProvider();
      seed(provider, [
        tripAt('trip-1', 37.32, 42.19),
        tripAt('trip-2', 37.35, 42.22),
      ]);

      provider.onTripRealtimeDelete('trip-1');

      expect(provider.activeTrips.map((t) => t.tripId), ['trip-2']);
    });

    test('bilinmeyen sefer id sessizce yok sayılır', () {
      final provider = SehiriciProvider();
      seed(provider, [tripAt('trip-1', 37.32, 42.19)]);

      provider.onTripRealtimeDelete('olmayan-trip');

      expect(provider.activeTrips.single.tripId, 'trip-1');
    });
  });
}
