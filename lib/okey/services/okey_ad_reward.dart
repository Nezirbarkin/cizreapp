import 'package:flutter/material.dart';

import '../../core/services/rewarded_ad_service.dart';
import '../providers/okey_points_provider.dart';

/// Ödüllü reklamı gösterir; SUNUCU doğrulaması geçerse okey puanı verir.
///
/// ## Neden ekranların dışında
///
/// Bu akış önce yalnızca puan ekranının içinde bir metottu. Kullanıcı
/// "reklam izle"nin masa açma ekranında DA doğrudan görünmesini istedi;
/// aynı 40 satırı ikinci bir ekrana kopyalamak, ileride doğrulama kuralı
/// değiştiğinde bir kopyanın geride kalması demekti.
///
/// ## Değişmeyen kural
///
/// Puanı ASLA istemci vermez. `showAndVerify()` yalnızca sunucu tarafında
/// doğrulanıp kredilendirilmiş bir oturum kimliği döndürdüğünde
/// [OkeyPointsProvider.claimAdReward] çağrılır; test reklamı ya da
/// doğrulanmamış oturum puan kazandırmaz.
Future<void> okeyWatchRewardedAd({
  required BuildContext context,
  required OkeyPointsProvider provider,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  // Reklam yükleme + gösterim + SSV doğrulaması saniyeler sürebilir; kullanıcı
  // bu arada ekrandan çıkarsa widget "deactivated" olur ve SnackBar göstermek
  // yakalanmamış async hata fırlatır. Her await'ten sonra context.mounted ile
  // korunur.
  void snack(String message) {
    if (!context.mounted) return;
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  try {
    final ads = RewardedAdService();
    final ready = await ads.preload();
    if (!ready) {
      snack('Şu an gösterilecek reklam yok.');
      return;
    }

    final result = await ads.showAndVerify();

    if (!result.isSuccess) {
      snack(
        result.isPending
            ? 'Reklam doğrulaması sürüyor, birazdan tekrar dene.'
            : (result.errorMessage ?? 'Reklam tamamlanmadı.'),
      );
      return;
    }

    final sessionId = result.rewardSessionId;
    if (sessionId.isEmpty || sessionId == 'test') {
      snack('Test reklamı — puan yalnızca gerçek reklamda verilir.');
      return;
    }

    await provider.claimAdReward(sessionId);
  } catch (e) {
    snack('Reklam hatası: $e');
  }
}
