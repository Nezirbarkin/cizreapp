import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/sehirici_icon_models.dart';
import 'sehirici_icon_service.dart';

/// Şehiriçi ikon kütüphanesinin uygulama içi (bellek) kopyası.
///
/// Haritalar ve listeler ikonu buradan çözer: hattın araç türü anahtarından
/// ([resolveVehicle]) ve varsayılan durak ikonundan ([stopIcon]). Katalog
/// yüklenemezse (ağ yok, kütüphane tablosu henüz yok) yerleşik liste
/// ([SehiriciMarkerIcon.builtinDefaults]) devrede kalır — harita eskisi gibi
/// çalışmaya devam eder, asla boş/kırık ikon göstermez.
class SehiriciIconCatalog extends ChangeNotifier {
  SehiriciIconCatalog({SehiriciIconService Function()? serviceFactory})
      : _serviceFactory = serviceFactory ?? SehiriciIconService.new;

  /// Uygulama genelinde paylaşılan örnek.
  static final SehiriciIconCatalog instance = SehiriciIconCatalog();

  final SehiriciIconService Function() _serviceFactory;

  /// Katalog bu süreden eskiyse [ensureLoaded] yeniden okur.
  static const Duration _ttl = Duration(minutes: 10);

  List<SehiriciMarkerIcon> _icons = SehiriciMarkerIcon.builtinDefaults;
  DateTime? _loadedAt;
  Future<void>? _loading;

  /// Her değişiklikte artar; bitmap önbelleği tutan widget'lar bunu izler.
  int _revision = 0;
  int get revision => _revision;

  bool get isLoaded => _loadedAt != null;

  List<SehiriciMarkerIcon> get all => _icons;

  List<SehiriciMarkerIcon> get vehicles => _sorted(SehiriciIconKind.vehicle);
  List<SehiriciMarkerIcon> get stops => _sorted(SehiriciIconKind.stop);

  List<SehiriciMarkerIcon> _sorted(SehiriciIconKind kind) {
    final list = _icons.where((i) => i.kind == kind).toList()
      ..sort((a, b) {
        final byOrder = a.sortOrder.compareTo(b.sortOrder);
        return byOrder != 0 ? byOrder : a.label.compareTo(b.label);
      });
    return list;
  }

  /// Hattın araç türü anahtarına karşılık gelen ikon. Anahtar katalogda
  /// yoksa (silinmiş/bilinmeyen tür) varsayılan araç ikonuna düşer.
  SehiriciMarkerIcon resolveVehicle(String? key) {
    if (key != null) {
      for (final icon in _icons) {
        if (icon.isVehicle && icon.key == key) return icon;
      }
    }
    return defaultVehicle;
  }

  SehiriciMarkerIcon get defaultVehicle {
    for (final icon in _icons) {
      if (icon.isVehicle && icon.isDefault) return icon;
    }
    for (final icon in SehiriciMarkerIcon.builtinDefaults) {
      if (icon.isVehicle && icon.isDefault) return icon;
    }
    return SehiriciMarkerIcon.builtinDefaults.first;
  }

  /// Haritada kullanılan durak ikonu (admin'in seçtiği varsayılan).
  SehiriciMarkerIcon get stopIcon {
    for (final icon in _icons) {
      if (icon.isStop && icon.isDefault) return icon;
    }
    for (final icon in _icons) {
      if (icon.isStop && icon.isActive) return icon;
    }
    return SehiriciMarkerIcon.builtinDefaults
        .firstWhere((i) => i.isStop && i.isDefault);
  }

  /// Katalogu (gerekirse) sunucudan okur. Eşzamanlı çağrılar tek istekte
  /// birleşir. Hata ekrana yansımaz: yerleşik liste kalır.
  Future<void> ensureLoaded({bool force = false}) {
    final loadedAt = _loadedAt;
    if (!force &&
        loadedAt != null &&
        DateTime.now().difference(loadedAt) < _ttl) {
      return Future<void>.value();
    }
    return _loading ??= _load().whenComplete(() {
      _loading = null;
    });
  }

  Future<void> _load() async {
    try {
      final fetched = await _serviceFactory().fetchAll();
      if (fetched.isNotEmpty) {
        _icons = fetched;
        _loadedAt = DateTime.now();
        _revision++;
        notifyListeners();
      }
    } catch (e) {
      // Sessizce yerleşik listeyle devam. Admin ekranı kendi yüklemesinde
      // hatayı ayrıca gösterir.
      debugPrint('SehiriciIconCatalog yüklenemedi (yerleşik liste): $e');
    }
  }

  /// Sunucudaki güncel hâli hemen çeker (admin bir ikonu değiştirince).
  Future<void> refresh() => ensureLoaded(force: true);

  /// Testler / iyimser güncelleme için kataloğu doğrudan doldurur.
  @visibleForTesting
  void seed(List<SehiriciMarkerIcon> icons) {
    _icons = icons.isEmpty ? SehiriciMarkerIcon.builtinDefaults : icons;
    _loadedAt = DateTime.now();
    _revision++;
    notifyListeners();
  }
}
