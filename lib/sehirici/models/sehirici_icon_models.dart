import '../../core/utils/map_vehicle_painters.dart';

/// Şehiriçi harita ikon kütüphanesinin türü.
enum SehiriciIconKind {
  vehicle,
  stop;

  static SehiriciIconKind fromString(String? s) =>
      s == 'stop' ? SehiriciIconKind.stop : SehiriciIconKind.vehicle;

  String get dbValue => name;

  String get label => this == SehiriciIconKind.vehicle ? 'Araç' : 'Durak';
}

/// `sehirici_marker_icons` satırı: bir araç türünün ya da durak görünümünün
/// haritadaki ikonu.
///
/// Bir ikon iki kaynaktan birini kullanır:
///  • **Hazır çizim** ([builtinShape]) — uygulamanın kendi tepeden görünüm
///    çizimi. Araçlar hattın rengiyle boyanır.
///  • **Yüklenen görsel** ([imageUrl]) — admin'in yüklediği PNG/WebP. Doluysa
///    hazır çizimin yerine geçer; kaldırılınca hazır çizime dönülür.
class SehiriciMarkerIcon {
  final String id;
  final SehiriciIconKind kind;
  final String key;
  final String label;
  final String? builtinShape;
  final String? imageUrl;
  final String? imagePath;

  /// Görselin burnu hangi yöne bakıyorsa onu YUKARI çevirmek için saat yönünde
  /// derece (0/90/180/270).
  final int imageRotation;
  final bool tintWithLineColor;
  final double scale;

  /// Yalnız yüklenen durak görselleri için: alt-orta nokta koordinata oturur.
  final bool anchorBottom;
  final bool isBuiltin;
  final bool isActive;
  final bool isDefault;
  final int sortOrder;
  final DateTime? updatedAt;

  const SehiriciMarkerIcon({
    required this.id,
    required this.kind,
    required this.key,
    required this.label,
    this.builtinShape,
    this.imageUrl,
    this.imagePath,
    this.imageRotation = 0,
    this.tintWithLineColor = true,
    this.scale = 1.0,
    this.anchorBottom = false,
    this.isBuiltin = false,
    this.isActive = true,
    this.isDefault = false,
    this.sortOrder = 0,
    this.updatedAt,
  });

  factory SehiriciMarkerIcon.fromJson(Map<String, dynamic> json) {
    return SehiriciMarkerIcon(
      id: json['id'] as String,
      kind: SehiriciIconKind.fromString(json['kind'] as String?),
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      builtinShape: json['builtin_shape'] as String?,
      imageUrl: _nonEmpty(json['image_url'] as String?),
      imagePath: _nonEmpty(json['image_path'] as String?),
      imageRotation: (json['image_rotation'] as num?)?.toInt() ?? 0,
      tintWithLineColor: json['tint_with_line_color'] as bool? ?? true,
      scale: (json['scale'] as num?)?.toDouble() ?? 1.0,
      anchorBottom: json['anchor_bottom'] as bool? ?? false,
      isBuiltin: json['is_builtin'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      isDefault: json['is_default'] as bool? ?? false,
      sortOrder: (json['sort_order'] as num?)?.toInt() ?? 0,
      updatedAt: json['updated_at'] == null
          ? null
          : DateTime.tryParse(json['updated_at'] as String),
    );
  }

  static String? _nonEmpty(String? v) =>
      (v == null || v.trim().isEmpty) ? null : v.trim();

  bool get isVehicle => kind == SehiriciIconKind.vehicle;
  bool get isStop => kind == SehiriciIconKind.stop;
  bool get hasImage => imageUrl != null;

  /// Hazır çizimin araç şekli. Bilinmiyorsa binek araç.
  MapVehicleShape get vehicleShape =>
      MapVehicleShape.fromKey(builtinShape) ?? MapVehicleShape.car;

  /// Hazır çizimin durak biçimi. Bilinmiyorsa levha.
  MapStopStyle get stopStyle =>
      MapStopStyle.fromKey(builtinShape) ?? MapStopStyle.sign;

  /// Bitmap önbellek anahtarı: görsel değişince (ya da yeniden yüklenince)
  /// eski bitmap dönmesin diye adres + sürüm birlikte kullanılır.
  String get imageCacheKey =>
      '${imageUrl ?? ''}@${updatedAt?.millisecondsSinceEpoch ?? 0}';

  SehiriciMarkerIcon copyWith({
    String? label,
    String? builtinShape,
    String? imageUrl,
    bool clearImage = false,
    String? imagePath,
    int? imageRotation,
    bool? tintWithLineColor,
    double? scale,
    bool? anchorBottom,
    bool? isActive,
    bool? isDefault,
    int? sortOrder,
  }) {
    return SehiriciMarkerIcon(
      id: id,
      kind: kind,
      key: key,
      label: label ?? this.label,
      builtinShape: builtinShape ?? this.builtinShape,
      imageUrl: clearImage ? null : (imageUrl ?? this.imageUrl),
      imagePath: clearImage ? null : (imagePath ?? this.imagePath),
      imageRotation: imageRotation ?? this.imageRotation,
      tintWithLineColor: tintWithLineColor ?? this.tintWithLineColor,
      scale: scale ?? this.scale,
      anchorBottom: anchorBottom ?? this.anchorBottom,
      isBuiltin: isBuiltin,
      isActive: isActive ?? this.isActive,
      isDefault: isDefault ?? this.isDefault,
      sortOrder: sortOrder ?? this.sortOrder,
      updatedAt: updatedAt,
    );
  }

  /// Katalog yüklenemediğinde (ağ yok, tablo henüz yok) kullanılan yerleşik
  /// liste — veritabanındaki tohum kayıtlarının aynısı. Uygulama bu sayede
  /// ikon kütüphanesi olmadan da eskisi gibi çalışır.
  static const List<SehiriciMarkerIcon> builtinDefaults = [
    SehiriciMarkerIcon(
      id: 'builtin_minibus',
      kind: SehiriciIconKind.vehicle,
      key: 'minibus',
      label: 'Minibüs',
      builtinShape: 'minibus',
      isBuiltin: true,
      sortOrder: 10,
    ),
    SehiriciMarkerIcon(
      id: 'builtin_dolmus',
      kind: SehiriciIconKind.vehicle,
      key: 'dolmus',
      label: 'Dolmuş',
      builtinShape: 'dolmus',
      isBuiltin: true,
      sortOrder: 20,
    ),
    SehiriciMarkerIcon(
      id: 'builtin_midibus',
      kind: SehiriciIconKind.vehicle,
      key: 'midibus',
      label: 'Midibüs',
      builtinShape: 'midibus',
      isBuiltin: true,
      sortOrder: 30,
    ),
    SehiriciMarkerIcon(
      id: 'builtin_bus',
      kind: SehiriciIconKind.vehicle,
      key: 'bus',
      label: 'Otobüs',
      builtinShape: 'bus',
      isBuiltin: true,
      sortOrder: 40,
    ),
    SehiriciMarkerIcon(
      id: 'builtin_tram',
      kind: SehiriciIconKind.vehicle,
      key: 'tram',
      label: 'Tramvay',
      builtinShape: 'tram',
      isBuiltin: true,
      sortOrder: 50,
    ),
    SehiriciMarkerIcon(
      id: 'builtin_other',
      kind: SehiriciIconKind.vehicle,
      key: 'other',
      label: 'Diğer',
      builtinShape: 'car',
      isBuiltin: true,
      isDefault: true,
      sortOrder: 90,
    ),
    SehiriciMarkerIcon(
      id: 'builtin_stop_sign',
      kind: SehiriciIconKind.stop,
      key: 'stop_sign',
      label: 'Durak Levhası',
      builtinShape: 'sign',
      isBuiltin: true,
      isDefault: true,
      sortOrder: 10,
    ),
    SehiriciMarkerIcon(
      id: 'builtin_stop_pin',
      kind: SehiriciIconKind.stop,
      key: 'stop_pin',
      label: 'Modern İğne',
      builtinShape: 'pin',
      isBuiltin: true,
      sortOrder: 20,
    ),
    SehiriciMarkerIcon(
      id: 'builtin_stop_dot',
      kind: SehiriciIconKind.stop,
      key: 'stop_dot',
      label: 'Sade Nokta',
      builtinShape: 'dot',
      isBuiltin: true,
      sortOrder: 30,
    ),
  ];
}

/// Admin'in ikon düzenleyicide hazırladığı, henüz kaydedilmemiş ikon.
class SehiriciMarkerIconDraft {
  /// null → yeni ikon.
  final String? id;
  final SehiriciIconKind kind;
  final String key;
  final String label;
  final String? builtinShape;
  final String? imageUrl;
  final String? imagePath;
  final int imageRotation;
  final bool tintWithLineColor;
  final double scale;
  final bool anchorBottom;
  final bool isActive;
  final int? sortOrder;

  const SehiriciMarkerIconDraft({
    this.id,
    required this.kind,
    required this.key,
    required this.label,
    this.builtinShape,
    this.imageUrl,
    this.imagePath,
    this.imageRotation = 0,
    this.tintWithLineColor = true,
    this.scale = 1.0,
    this.anchorBottom = false,
    this.isActive = true,
    this.sortOrder,
  });
}
