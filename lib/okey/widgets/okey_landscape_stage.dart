import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Okey masasının YATAY (landscape) kalmasını isteyen kilit.
///
/// Mobilde bunu işletim sistemi yapar: [SystemChrome.setPreferredOrientations]
/// cihazı yan çevirir. WEB'DE VE MASAÜSTÜNDE O ÇAĞRI HİÇBİR ŞEY YAPMAZ —
/// tarayıcı bir sayfanın ekranı döndürmesine izin vermez (Screen Orientation
/// API yalnızca tam ekranda ve yalnızca bazı Android tarayıcılarında çalışır,
/// iOS Safari'de hiç yoktur). Masa dikey bir tarayıcı penceresinde açılınca
/// bu yüzden sıkışıp oynanamaz hale geliyordu.
///
/// Çözüm: masayı biz döndürürüz. Görüntü çeyrek tur çevrilir, oyuncu
/// telefonunu yan tutar ve masa tam ekranı yatay olarak kullanır — ekran
/// kilidi açık olmasa bile.
abstract final class OkeyLandscapeLock {
  /// Kaç ekran aynı anda yatay istiyor (iç içe geçmelere karşı sayaç).
  static final ValueNotifier<int> depth = ValueNotifier<int>(0);

  /// Bu platform ekranı KENDİ döndürebiliyor mu?
  ///
  /// Android/iOS'ta döndürebilir; orada bu sahne devreye girmez, yoksa
  /// cihaz zaten yan çevrilmişken bir de biz döndürüp masayı ters
  /// gösterirdik.
  static bool get platformRotatesItself =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  static void engage() {
    if (platformRotatesItself) return;
    depth.value = depth.value + 1;
  }

  static void release() {
    if (platformRotatesItself) return;
    final next = depth.value - 1;
    depth.value = next < 0 ? 0 : next;
  }
}

/// Uygulamanın KÖKÜNÜ saran sahne (bkz. `main.dart` > MaterialApp.builder).
///
/// NEDEN KÖKTE, oyun ekranının içinde değil: diyaloglar ve alt sayfalar
/// (el sonucu, masa ayarları, hediye sayfası) Navigator'ın ÜSTÜNDE çizilir.
/// Döndürmeyi oyun ekranının içine koysaydık masa yatay, üstüne açılan
/// diyalog dikey görünürdü.
///
/// Sarmalayıcı HER ZAMAN aynı yapıdadır (MediaQuery + RotatedBox); yalnızca
/// `quarterTurns` değişir. Döndürme açılıp kapandığında ağaca yeni bir
/// katman EKLENSEYDİ altındaki Navigator elemanı sökülüp yeniden kurulur,
/// yani masaya girip çıkarken uygulamanın tüm durumu sıfırlanırdı.
class OkeyLandscapeStage extends StatelessWidget {
  const OkeyLandscapeStage({super.key, required this.child});

  final Widget child;

  /// Ekran kenar boşluklarını çeyrek tur çevirir.
  ///
  /// Görüntü saat yönünde 90° döndüğü için çocuğun SOL kenarı ekranın ÜST
  /// kenarına denk gelir; çentik/durum çubuğu payı da bu eşlemeyle taşınır,
  /// yoksa [SafeArea] boşluğu yanlış kenarda bırakırdı.
  static EdgeInsets _rotate(EdgeInsets p) =>
      EdgeInsets.fromLTRB(p.top, p.right, p.bottom, p.left);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: OkeyLandscapeLock.depth,
      child: child,
      builder: (context, depth, child) {
        final mq = MediaQuery.of(context);
        // Pencere zaten yataysa (masaüstü tarayıcı, yan çevrilmiş telefon)
        // dokunma: döndürmek masayı ters çevirmek olurdu.
        final rotate = depth > 0 && mq.size.height > mq.size.width;
        return MediaQuery(
          data: rotate
              ? mq.copyWith(
                  size: Size(mq.size.height, mq.size.width),
                  padding: _rotate(mq.padding),
                  viewPadding: _rotate(mq.viewPadding),
                  viewInsets: _rotate(mq.viewInsets),
                )
              : mq,
          child: RotatedBox(
            quarterTurns: rotate ? 1 : 0,
            child: child ?? const SizedBox.shrink(),
          ),
        );
      },
    );
  }
}
