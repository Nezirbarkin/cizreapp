import 'package:flutter/widgets.dart';

import '../models/profile_feature.dart';
import '../services/profile_feature_service.dart';

/// Profil özelliği efektlerinin (avatar / kapak / profil katmanı) animasyonunu
/// YALNIZCA kullanıcının gerçekten o türde bir efekti varsa çalıştırır.
///
/// Eskiden bu bileşenlerin hepsi `initState`'te sonsuz bir
/// `AnimationController..repeat()` başlatıyordu — efekt olmasa bile. Dinleyicisi
/// olmayan çalışan bir ticker bile her vsync'te yeni kare ister: profil
/// sayfaları ve akış boştayken saniyede ~120 boş kare çiziliyordu (profile
/// ölçümü 2026-10-06). Canlıda efekti olan kullanıcı çok az.
///
/// Kullanım: `with SingleTickerProviderStateMixin, FeatureEffectTickerMixin`;
/// [effectLoopDuration] ve [needsEffectTicker] tanımlanır, özellikler
/// [loadFeaturesAndSyncTicker] ile yüklenir, build'de [effectController]
/// `null` ise efekt çizilmez.
mixin FeatureEffectTickerMixin<T extends StatefulWidget>
    on State<T>, SingleTickerProviderStateMixin<T> {
  AnimationController? _effectController;
  Future<List<ProfileFeature>>? _effectLoad;

  /// Efekt animasyonunun bir tur süresi.
  Duration get effectLoopDuration;

  /// Bu özellik listesi animasyonlu bir efekt içeriyor mu?
  bool needsEffectTicker(List<ProfileFeature> features);

  /// Efekt animasyonu; efekt yoksa `null` (hiç yaratılmamış ya da durmuş
  /// olabilir — build'de efekti yalnız bu `null` değilken çizin).
  AnimationController? get effectController => _effectController;

  /// Özellikleri yükler ve sonuca göre ticker'ı açar/kapatır. Önbellek doluysa
  /// ticker hemen (ilk karede) ayarlanır.
  Future<List<ProfileFeature>> loadFeaturesAndSyncTicker(String userId) {
    final cached = ProfileFeatureService.peekUserFeatures(userId);
    _syncEffectTicker(cached != null && needsEffectTicker(cached));
    final future = ProfileFeatureService().getUserFeatures(userId);
    _effectLoad = future;
    future.then((features) {
      // Bu arada kullanıcı değiştiyse (didUpdateWidget) eski sonucu yok say.
      if (!mounted || !identical(_effectLoad, future)) return;
      final needed = needsEffectTicker(features);
      if (needed != (_effectController?.isAnimating ?? false)) {
        // Controller ilk kez yaratılıyorsa build'in onu görmesi gerekir.
        setState(() => _syncEffectTicker(needed));
      }
    }, onError: (Object _) {});
    return future;
  }

  void _syncEffectTicker(bool needed) {
    if (needed) {
      final controller = _effectController ??= AnimationController(
        vsync: this,
        duration: effectLoopDuration,
      );
      if (!controller.isAnimating) controller.repeat();
    } else {
      _effectController?.stop();
    }
  }

  @override
  void dispose() {
    _effectController?.dispose();
    super.dispose();
  }
}
