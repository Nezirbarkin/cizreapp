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

/// Haritanın altındaki zemin: çizilmiş standart harita ya da uydu görüntüsü.
enum MapBaseType { standard, satellite }

/// Harita türü tercihi (Standart / Uydu) — cihaz yereli, kalıcı.
///
/// Uydu görüntüsü gerçek binaları/yolları gösterir; durak ve güzergâh
/// çizgileri üstünde aynen görünür. Şehiriçi haritası bu tercihi kullanır.
class MapTypePreference {
  const MapTypePreference._();

  static const String _prefsKey = 'map_base_type';

  static final ValueNotifier<MapBaseType> choice =
      ValueNotifier<MapBaseType>(MapBaseType.standard);

  static bool _loaded = false;
  static Future<void>? _loading;

  static Future<void> ensureLoaded() {
    if (_loaded) return Future<void>.value();
    return _loading ??= _load();
  }

  static Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_prefsKey);
      if (saved != null) {
        choice.value = MapBaseType.values.firstWhere(
          (c) => c.name == saved,
          orElse: () => MapBaseType.standard,
        );
      }
    } catch (_) {
      // Okunamadıysa standart harita.
    } finally {
      _loaded = true;
    }
  }

  static Future<void> set(MapBaseType value) async {
    choice.value = value;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_prefsKey, value.name);
    } catch (_) {
      // Kaydedilemese de oturum içinde geçerli kalır.
    }
  }

  static Future<void> toggle() => set(
        choice.value == MapBaseType.standard
            ? MapBaseType.satellite
            : MapBaseType.standard,
      );

  static String labelOf(MapBaseType value) => switch (value) {
        MapBaseType.standard => 'Standart',
        MapBaseType.satellite => 'Uydu',
      };

  static IconData iconOf(MapBaseType value) => switch (value) {
        MapBaseType.standard => Icons.layers_outlined,
        MapBaseType.satellite => Icons.satellite_alt,
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

/// Uygulama genelinde tek tip, modern ve gerçekçi harita görünümü.
///
/// Google'ın varsayılan haritası yoğun renkli ve POI ikonlarıyla kalabalıktır;
/// üzerine çizdiğimiz hat/rota polyline'ları ve marker'lar arka planda kaybolur.
/// Buradaki stiller zemini sıcak, düşük doygunluklu bir "kâğıt" tonuna çeker,
/// yolları beyaz gövde + ince kenarlıkla ayırır, bina izlerini belli belirsiz
/// gösterir (yakın zoom'da gerçek şehir dokusu), park ve suyu yumuşak renkle
/// verir. POI ikonları kapalıdır; yalnızca yön bulmaya yarayan yerlerin
/// (okul, hastane, cami, kamu binası, park) YAZISI kalır. Google'ın kendi
/// toplu taşıma durakları gizlenir — durakları biz çiziyoruz, ikiye
/// katlanmasınlar.
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

  /// Modern açık stil: sıcak kâğıt zemin, beyaz yollar, belirgin bina izleri,
  /// yumuşak yeşil park ve mavi su.
  static const String light = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#f2f1ed"}]},
  {"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#616875"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#ffffff"}, {"weight": 3}]},
  {"featureType": "administrative", "elementType": "geometry.stroke", "stylers": [{"color": "#d6d3cb"}]},
  {"featureType": "administrative.land_parcel", "stylers": [{"visibility": "off"}]},
  {"featureType": "administrative.neighborhood", "elementType": "labels.text.fill", "stylers": [{"color": "#8f95a1"}]},
  {"featureType": "administrative.locality", "elementType": "labels.text.fill", "stylers": [{"color": "#3b4250"}]},
  {"featureType": "landscape.man_made", "elementType": "geometry.fill", "stylers": [{"color": "#e7e5dd"}]},
  {"featureType": "landscape.man_made", "elementType": "geometry.stroke", "stylers": [{"color": "#d3d0c6"}]},
  {"featureType": "landscape.natural", "elementType": "geometry.fill", "stylers": [{"color": "#eeede8"}]},
  {"featureType": "poi", "elementType": "geometry", "stylers": [{"color": "#e9eae3"}]},
  {"featureType": "poi", "elementType": "labels.text", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi.school", "elementType": "labels.text", "stylers": [{"visibility": "on"}]},
  {"featureType": "poi.medical", "elementType": "labels.text", "stylers": [{"visibility": "on"}]},
  {"featureType": "poi.government", "elementType": "labels.text", "stylers": [{"visibility": "on"}]},
  {"featureType": "poi.place_of_worship", "elementType": "labels.text", "stylers": [{"visibility": "on"}]},
  {"featureType": "poi.school", "elementType": "geometry", "stylers": [{"color": "#e5e3da"}]},
  {"featureType": "poi.medical", "elementType": "geometry", "stylers": [{"color": "#f0e0de"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#d7e8cb"}]},
  {"featureType": "poi.park", "elementType": "labels.text", "stylers": [{"visibility": "on"}]},
  {"featureType": "poi.park", "elementType": "labels.text.fill", "stylers": [{"color": "#6b915f"}]},
  {"featureType": "road", "elementType": "geometry.fill", "stylers": [{"color": "#ffffff"}]},
  {"featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#dedbd2"}]},
  {"featureType": "road", "elementType": "labels.text.fill", "stylers": [{"color": "#8b909b"}]},
  {"featureType": "road.local", "elementType": "geometry.stroke", "stylers": [{"color": "#e6e3da"}]},
  {"featureType": "road.arterial", "elementType": "geometry.stroke", "stylers": [{"color": "#dad7cd"}]},
  {"featureType": "road.highway", "elementType": "geometry.fill", "stylers": [{"color": "#fde6b0"}]},
  {"featureType": "road.highway", "elementType": "geometry.stroke", "stylers": [{"color": "#efca7d"}]},
  {"featureType": "road.highway", "elementType": "labels.text.fill", "stylers": [{"color": "#7a6a42"}]},
  {"featureType": "transit", "stylers": [{"visibility": "off"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#b9d8ef"}]},
  {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#5f8fb4"}]},
  {"featureType": "water", "elementType": "labels.text.stroke", "stylers": [{"color": "#e3f0fa"}]}
]
''';

  /// Modern koyu stil: mürekkep grisi zemin, seçilebilir bina izleri, ışıklı yollar.
  static const String dark = '''
[
  {"elementType": "geometry", "stylers": [{"color": "#1a1d23"}]},
  {"elementType": "labels.icon", "stylers": [{"visibility": "off"}]},
  {"elementType": "labels.text.fill", "stylers": [{"color": "#9aa1ad"}]},
  {"elementType": "labels.text.stroke", "stylers": [{"color": "#14161a"}, {"weight": 3}]},
  {"featureType": "administrative", "elementType": "geometry.stroke", "stylers": [{"color": "#2d323b"}]},
  {"featureType": "administrative.land_parcel", "stylers": [{"visibility": "off"}]},
  {"featureType": "administrative.neighborhood", "elementType": "labels.text.fill", "stylers": [{"color": "#6b7280"}]},
  {"featureType": "administrative.locality", "elementType": "labels.text.fill", "stylers": [{"color": "#d1d5db"}]},
  {"featureType": "landscape.man_made", "elementType": "geometry.fill", "stylers": [{"color": "#22262d"}]},
  {"featureType": "landscape.man_made", "elementType": "geometry.stroke", "stylers": [{"color": "#2e333c"}]},
  {"featureType": "landscape.natural", "elementType": "geometry.fill", "stylers": [{"color": "#1c1f25"}]},
  {"featureType": "poi", "elementType": "geometry", "stylers": [{"color": "#20242a"}]},
  {"featureType": "poi", "elementType": "labels.text", "stylers": [{"visibility": "off"}]},
  {"featureType": "poi.school", "elementType": "labels.text", "stylers": [{"visibility": "on"}]},
  {"featureType": "poi.medical", "elementType": "labels.text", "stylers": [{"visibility": "on"}]},
  {"featureType": "poi.government", "elementType": "labels.text", "stylers": [{"visibility": "on"}]},
  {"featureType": "poi.place_of_worship", "elementType": "labels.text", "stylers": [{"visibility": "on"}]},
  {"featureType": "poi.park", "elementType": "geometry", "stylers": [{"color": "#1b2820"}]},
  {"featureType": "poi.park", "elementType": "labels.text", "stylers": [{"visibility": "on"}]},
  {"featureType": "poi.park", "elementType": "labels.text.fill", "stylers": [{"color": "#5d7a63"}]},
  {"featureType": "road", "elementType": "geometry.fill", "stylers": [{"color": "#2f343d"}]},
  {"featureType": "road", "elementType": "geometry.stroke", "stylers": [{"color": "#1e2126"}]},
  {"featureType": "road", "elementType": "labels.text.fill", "stylers": [{"color": "#8b919c"}]},
  {"featureType": "road.local", "elementType": "geometry.fill", "stylers": [{"color": "#292d35"}]},
  {"featureType": "road.arterial", "elementType": "geometry.fill", "stylers": [{"color": "#373d47"}]},
  {"featureType": "road.highway", "elementType": "geometry.fill", "stylers": [{"color": "#4a4536"}]},
  {"featureType": "road.highway", "elementType": "geometry.stroke", "stylers": [{"color": "#2b281f"}]},
  {"featureType": "road.highway", "elementType": "labels.text.fill", "stylers": [{"color": "#c9bea0"}]},
  {"featureType": "transit", "stylers": [{"visibility": "off"}]},
  {"featureType": "water", "elementType": "geometry", "stylers": [{"color": "#0e1a26"}]},
  {"featureType": "water", "elementType": "labels.text.fill", "stylers": [{"color": "#4a637a"}]},
  {"featureType": "water", "elementType": "labels.text.stroke", "stylers": [{"color": "#0e1a26"}]}
]
''';
}
