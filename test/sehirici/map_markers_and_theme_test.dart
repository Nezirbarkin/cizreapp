import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cizreapp/core/theme/app_map_style.dart';
import 'package:cizreapp/core/utils/map_marker_icons.dart';

/// Harita marker ikonları ve harita görünümü (Otomatik/Açık/Koyu) tercihi.
///
/// Buradaki iki kural kolay regresyona açık:
///
///  1. Araç ve etiket bitmap'leri cache'lenmeli. Marker'lar her konum
///     güncellemesinde (10 sn'de bir, her araç için) yeniden kurulduğu için
///     cache olmadan her seferinde yeni PNG çizilir — haritada gözle görülür
///     jank üretir.
///  2. Harita görünümü tercihi uygulama temasını EZMELİ. Admin açık temada
///     çalışırken haritayı koyuya alabilsin diye eklendi; `AppMapStyle.of`
///     tercihi yok sayarsa özellik sessizce çalışmaz hale gelir.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    MapMarkerIcons.clearCache();
    MapThemePreference.choice.value = MapThemeChoice.auto;
  });

  group('MapMarkerIcons', () {
    test('aynı araç tipi + renk için aynı bitmap örneği döner (cache)',
        () async {
      final first = await MapMarkerIcons.vehicle(
        shape: MapVehicleShape.minibus,
        color: const Color(0xFF1976D2),
      );
      final second = await MapMarkerIcons.vehicle(
        shape: MapVehicleShape.minibus,
        color: const Color(0xFF1976D2),
      );
      expect(identical(first, second), isTrue);
    });

    test('renk veya şekil değişince yeni bitmap üretilir', () async {
      final blueMinibus = await MapMarkerIcons.vehicle(
        shape: MapVehicleShape.minibus,
        color: const Color(0xFF1976D2),
      );
      final redMinibus = await MapMarkerIcons.vehicle(
        shape: MapVehicleShape.minibus,
        color: const Color(0xFFE53935),
      );
      final blueMotorcycle = await MapMarkerIcons.vehicle(
        shape: MapVehicleShape.motorcycle,
        color: const Color(0xFF1976D2),
      );
      expect(identical(blueMinibus, redMinibus), isFalse);
      expect(identical(blueMinibus, blueMotorcycle), isFalse);
    });

    test('etiket bitmap`i metne göre cache`lenir', () async {
      final first = await MapMarkerIcons.label(
        text: 'ŞEHİRİÇİ · 4A',
        background: const Color(0xFF1976D2),
      );
      final same = await MapMarkerIcons.label(
        text: 'ŞEHİRİÇİ · 4A',
        background: const Color(0xFF1976D2),
      );
      final other = await MapMarkerIcons.label(
        text: 'KURYE',
        background: const Color(0xFFFB8C00),
      );
      expect(identical(first, same), isTrue);
      expect(identical(first, other), isFalse);
    });

    test('etiket boşluğu pozitif ve uzun gövdede daha büyük', () {
      // Etiket, araç gövdesinin üstünde durmalı; boşluk sıfır/negatif
      // olamaz (etiket aracın üzerine biner). Gövde boyutu ayarlandıkça
      // kırılmaması için sabit piksel eşiği yerine göreli invariant'lar
      // kontrol edilir: her şekil için pozitif, ve daha uzun gövdeli araç
      // (bus) daha kısa olandan (motorcycle) daha büyük boşluk ister.
      for (final shape in MapVehicleShape.values) {
        expect(
          MapMarkerIcons.labelGapFor(shape),
          greaterThan(0),
          reason: shape.name,
        );
      }
      expect(
        MapMarkerIcons.labelGapFor(MapVehicleShape.bus),
        greaterThan(MapMarkerIcons.labelGapFor(MapVehicleShape.motorcycle)),
      );
    });
  });

  group('MapThemePreference', () {
    test('döngü Otomatik → Açık → Koyu → Otomatik', () async {
      expect(MapThemePreference.choice.value, MapThemeChoice.auto);
      await MapThemePreference.cycle();
      expect(MapThemePreference.choice.value, MapThemeChoice.light);
      await MapThemePreference.cycle();
      expect(MapThemePreference.choice.value, MapThemeChoice.dark);
      await MapThemePreference.cycle();
      expect(MapThemePreference.choice.value, MapThemeChoice.auto);
    });

    testWidgets('koyu seçimi açık temayı ezer, otomatik temayı izler',
        (tester) async {
      String? resolved;
      Future<void> pumpWithTheme(Brightness brightness) async {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(brightness: brightness),
            home: MapStyleBuilder(
              builder: (context, style) {
                resolved = style;
                return const SizedBox.shrink();
              },
            ),
          ),
        );
        // MaterialApp temayı AnimatedTheme ile 200 ms'de geçirir; tek kare
        // pump'ta hâlâ eski tema okunur.
        await tester.pump(const Duration(milliseconds: 400));
      }

      // Otomatik: tema açık → açık stil.
      await pumpWithTheme(Brightness.light);
      expect(resolved, AppMapStyle.light);

      // Koyu seçildi: tema açık olsa da koyu stil.
      await MapThemePreference.set(MapThemeChoice.dark);
      await tester.pump();
      expect(resolved, AppMapStyle.dark);

      // Açık seçildi: tema koyu olsa da açık stil.
      await MapThemePreference.set(MapThemeChoice.light);
      await pumpWithTheme(Brightness.dark);
      expect(resolved, AppMapStyle.light);

      // Otomatiğe dönüldü: tema koyu → koyu stil.
      await MapThemePreference.set(MapThemeChoice.auto);
      await tester.pump();
      expect(resolved, AppMapStyle.dark);
    });
  });
}
