import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Haritanın açık/koyu görünümünü kimin belirlediği.
///
/// [auto] uygulama temasını takip eder (eski, tek davranış). [light]/[koyu]
/// kullanıcının haritada elle seçtiği görünümdür ve uygulama teması ne olursa
/// olsun kazanır — admin panelinde gündüz açık temada çalışırken haritayı
/// koyuya almak (veya tersi) bu yüzden mümkün.
enum MapThemeChoice { auto, light, dark }

/// Harita görünümü tercihi — cihaz yereli, kalıcı (SharedPreferences).
///
/// Tercih uygulama genelinde tek kaynaktır: admin panelindeki harita
/// üzerindeki düğmeyle değiştirilir, [AppMapStyle.of] okuyan tüm haritalar
/// (şehiriçi canlı harita, kurye haritaları, adres seçici …) aynı görünümü
/// kullanır. Anlık tepki için haritayı [MapStyleBuilder] ile sarın;
/// sarılmayan haritalar bir sonraki açılışta tercihi uygular.
class MapThemePreference {
  const MapThemePreference._();

  static const String _prefsKey = 'map_theme_choice';

  /// Geçerli tercih. Dinleyen widget'lar (bkz. [MapStyleBuilder]) tercih
  /// değişince anında yeniden çizilir.
  static final ValueNotifier<MapThemeChoice> choice =
      ValueNotifier<MapThemeChoice>(MapThemeChoice.auto);

  static bool _loaded = false;
  static Future<void>? _loading;

  /// Kayıtlı tercihi bir kez okur. Tekrar tekrar çağrılabilir (idempotent);
  /// okuma bitmeden harita çizilirse varsayılan [MapThemeChoice.auto] ile
  /// çizilir, tercih gelince kendiliğinden güncellenir.
  static Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  static Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null) {
        choice.value = MapThemeChoice.values.firstWhere(
          (c) => c.name == saved,
          orElse: () => MapThemeChoice.auto,
        );
      }
    } catch (_) {
      // Tercih okunamadıysa otomatik davranışta kal.
    } finally {
      _loaded = true;
    }
  }

  static Future<void> set(MapThemeChoice value) async {
    choice.value = value;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, value.name);
    } catch (_) {
      // Kaydedilemese de oturum içinde seçim geçerli kalır.
    }
  }

  /// Otomatik → Açık → Koyu → Otomatik sırasıyla ilerler (harita üzerindeki
  /// tek düğme için).
  static Future<void> cycle() {
    final next = switch (choice.value) {
      MapThemeChoice.auto => MapThemeChoice.light,
      MapThemeChoice.light => MapThemeChoice.dark,
      MapThemeChoice.dark => MapThemeChoice.auto,
    };
    return set(next);
  }

  /// Düğme/etiket metni.
  static String labelOf(MapThemeChoice value) => switch (value) {
        MapThemeChoice.auto => 'Otomatik',
        MapThemeChoice.light => 'Açık',
        MapThemeChoice.dark => 'Koyu',
      };

  static IconData iconOf(MapThemeChoice value) => switch (value) {
        MapThemeChoice.auto => Icons.brightness_auto,
        MapThemeChoice.light => Icons.light_mode,
        MapThemeChoice.dark => Icons.dark_mode,
      };
}

/// Harita teması tercihini dinleyip güncel stil JSON'unu veren sarmalayıcı.
///
/// ```dart
/// MapStyleBuilder(
///   builder: (context, style) => GoogleMap(style: style, ...),
/// )
/// ```
class MapStyleBuilder extends StatefulWidget {
  final Widget Function(BuildContext context, String style) builder;

  const MapStyleBuilder({super.key, required this.builder});

  @override
  State<MapStyleBuilder> createState() => _MapStyleBuilderState();
}

class _MapStyleBuilderState extends State<MapStyleBuilder> {
  @override
  void initState() {
    super.initState();
    MapThemePreference.ensureLoaded();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<MapThemeChoice>(
      valueListenable: MapThemePreference.choice,
      builder: (context, _, __) => widget.builder(
        context,
        AppMapStyle.of(context),
      ),
    );
  }
}

/// Uygulama genelinde tek tip, modern harita görünümü.
///
/// Google'ın varsayılan haritası yoğun renkli ve POI ikonlarıyla kalabalıktır;
/// üzerine çizdiğimiz hat/rota polyline'ları ve marker'lar arka planda kaybolur.
/// Buradaki stiller zemini düşük doygunluklu nötr griye çeker, POI ikonlarını
/// kapatır ve yolları ince kontrastlarla ayırır — böylece asıl içerik
/// (duraklar, kuryeler, rotalar) öne çıkar.
///
/// Renkler [AppTheme] gri paletiyle uyumludur (gray400/gray500/gray200 …).
///
/// Kullanım — `GoogleMap` kurulumunda tek satır:
/// ```dart
/// GoogleMap(
///   style: AppMapStyle.of(context),
///   ...
/// )
/// ```
class AppMapStyle {
  const AppMapStyle._();

  /// Bulunulan temaya uygun stil JSON'u.
  ///
  /// Doğrudan [GoogleMap.style] parametresine verilir; harita oluşturulurken
  /// uygulandığı için stilsiz bir ilk kare görünmez ve kullanıcı açık/koyu
  /// tema arasında geçiş yaptığında harita da kendiliğinden güncellenir.
  /// Kullanıcı haritada elle bir görünüm seçtiyse ([MapThemePreference])
  /// o kazanır; seçim yoksa uygulama teması takip edilir.
  static String of(BuildContext context) => switch (MapThemePreference
          .choice.value) {
        MapThemeChoice.light => light,
        MapThemeChoice.dark => dark,
        MapThemeChoice.auto =>
          forBrightness(Theme.of(context).brightness == Brightness.dark),
      };

  /// Temaya göre stil JSON'u.
  static String forBrightness(bool isDark) => isDark ? dark : light;

  /// Modern açık stil: kırık beyaz zemin, beyaz yollar, yumuşak mavi su.
  static const String light = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#f6f7f9"}]},
  {"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#6b7280"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#ffffff"}, {"weight": 2}]},
  {"featureType": "administrative", "elementType": "geometry", "stylers": [{"color": "#e5e7eb"}]},
  {"featureType": "administrative.land_parcel", "stylers": [{"visibility": "off"}]},
  {"featureType": "administrative.neighborhood", "elementType": "labels.text.fill", "stylers": [{"color": "#9ca3af"}]},
  {"featureType": "administrative.locality", "elementType": "labels.text.fill", "stylers": [{"color": "#4b5563"}]},
  {"featureType": "landscape.man_made", "elementType": "geometry", "stylers": [{"color": "#f1f2f5"}]},
  {"featureType": "landscape.natural", "elementType": "geometry", "stylers": [{"color": "#eef1ee"}]},
  {"featureType": "poi", "elementType": "geometry", "stylers": [{"color": "#eceef1"}]},
  {"featureType": "poi", "elementType": "labels", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#e2eddf"}]},
  {"featureType": "poi.park", "elementType": "labels.text", "stylers": [{"visibility": "on"}]},
  {"featureType": "poi.park", "elementType": "labels.text.fill", "stylers": [{"color": "#8aa682"}]},
  {"featureType": "poi.medical", "elementType": "geometry", "stylers": [{"color": "#f4e7e7"}]},
  {"featureType": "road", "elementType": "geometry.fill", "stylers": [{"color": "#ffffff"}]},
  {"featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#e8eaef"}]},
  {"featureType": "road", "elementType": "labels.text.fill", "stylers": [{"color": "#9ca3af"}]},
  {"featureType": "road.local", "elementType": "geometry.stroke", "stylers": [{"color": "#eceef2"}]},
  {"featureType": "road.arterial", "elementType": "geometry.fill", "stylers": [{"color": "#ffffff"}]},
  {"featureType": "road.arterial", "elementType": "geometry.stroke", "stylers": [{"color": "#e1e4ea"}]},
  {"featureType": "road.highway", "elementType": "geometry.fill", "stylers": [{"color": "#fdfdfe"}]},
  {"featureType": "road.highway", "elementType": "geometry.stroke", "stylers": [{"color": "#d7dbe3"}]},
  {"featureType": "road.highway", "elementType": "labels.text.fill", "stylers": [{"color": "#7c8494"}]},
  {"featureType": "road.highway.controlled_access", "elementType": "geometry.fill", "stylers": [{"color": "#fbfbfd"}]},
  {"featureType": "road.highway.controlled_access", "elementType": "geometry.stroke", "stylers": [{"color": "#ccd2dc"}]},
  {"featureType": "transit", "elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"featureType": "transit.line", "elementType": "geometry", "stylers": [{"color": "#e6e8ec"}]},
  {"featureType": "transit.station", "elementType": "geometry", "stylers": [{"color": "#eceef1"}]},
  {"featureType": "transit", "elementType": "labels.text.fill", "stylers": [{"color": "#a5abb5"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#d4e4f0"}]},
  {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#7ba0bd"}]},
  {"featureType": "water", "elementType": "labels.text.stroke", "stylers": [{"color": "#d4e4f0"}]}
]
''';

  /// Modern koyu stil: mürekkep grisi zemin, ışıklı yollar.
  static const String dark = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#181a1f"}]},
  {"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#9ca3af"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#14161a"}, {"weight": 2}]},
  {"featureType": "administrative", "elementType": "geometry", "stylers": [{"color": "#2c3038"}]},
  {"featureType": "administrative.land_parcel", "stylers": [{"visibility": "off"}]},
  {"featureType": "administrative.neighborhood", "elementType": "labels.text.fill", "stylers": [{"color": "#6b7280"}]},
  {"featureType": "administrative.locality", "elementType": "labels.text.fill", "stylers": [{"color": "#d1d5db"}]},
  {"featureType": "landscape.man_made", "elementType": "geometry", "stylers": [{"color": "#1c1f25"}]},
  {"featureType": "landscape.natural", "elementType": "geometry", "stylers": [{"color": "#1a1d22"}]},
  {"featureType": "poi", "elementType": "geometry", "stylers": [{"color": "#20242a"}]},
  {"featureType": "poi", "elementType": "labels", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#1b2620"}]},
  {"featureType": "poi.park", "elementType": "labels.text", "stylers": [{"visibility": "on"}]},
  {"featureType": "poi.park", "elementType": "labels.text.fill", "stylers": [{"color": "#5d7a63"}]},
  {"featureType": "road", "elementType": "geometry.fill", "stylers": [{"color": "#2a2e36"}]},
  {"featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#1f2229"}]},
  {"featureType": "road", "elementType": "labels.text.fill", "stylers": [{"color": "#8b919c"}]},
  {"featureType": "road.local", "elementType": "geometry.fill", "stylers": [{"color": "#24282f"}]},
  {"featureType": "road.arterial", "elementType": "geometry.fill", "stylers": [{"color": "#31363f"}]},
  {"featureType": "road.highway", "elementType": "geometry.fill", "stylers": [{"color": "#3a404b"}]},
  {"featureType": "road.highway", "elementType": "geometry.stroke", "stylers": [{"color": "#22262d"}]},
  {"featureType": "road.highway", "elementType": "labels.text.fill", "stylers": [{"color": "#b6bcc7"}]},
  {"featureType": "road.highway.controlled_access", "elementType": "geometry.fill", "stylers": [{"color": "#454c58"}]},
  {"featureType": "transit", "elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"featureType": "transit.line", "elementType": "geometry", "stylers": [{"color": "#272b32"}]},
  {"featureType": "transit.station", "elementType": "geometry", "stylers": [{"color": "#20242a"}]},
  {"featureType": "transit", "elementType": "labels.text.fill", "stylers": [{"color": "#7a808b"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#0f151c"}]},
  {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#4a637a"}]},
  {"featureType": "water", "elementType": "labels.text.stroke", "stylers": [{"color": "#0f151c"}]}
]
''';
}
