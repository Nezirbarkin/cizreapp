import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

/// Konum verisinin hangi özellik için toplandığı.
///
/// Her amacın kendi açıklama metni vardır çünkü Google Play'in Prominent
/// Disclosure şartı "hangi veri, hangi özellik için, kiminle paylaşılıyor"
/// sorularının **o bağlamda** yanıtlanmasını ister. Tek bir genel metin
/// (ör. yalnız "yakındaki mağazalar") kurye/şoför takibini kapsamaz.
enum LocationPurpose {
  /// Yakındaki mağaza/ürün listeleme, teslimat adresi seçimi, haritada
  /// kendi konumunu görme. Yalnız uygulama ekranda açıkken, tek seferlik.
  nearby,

  /// Kurye teslimat sırasında canlı konum paylaşımı. Sürekli akış, ekran
  /// kapalıyken foreground service bildirimi ile devam eder, konum
  /// müşteriyle paylaşılır.
  courierTracking,

  /// Şehiriçi şoför sefer takibi (manuel veya otomatik sefer). Sürekli akış,
  /// ekran kapalıyken bildirim ile devam eder, konum yolcularla paylaşılır.
  driverTrip,
}

/// Google Play "Prominent Disclosure and Consent" şartını karşılayan merkezi
/// konum izni kapısı.
///
/// Play politikası, konum verisi toplanmadan **önce** uygulamanın kendi
/// arayüzünde; hangi verinin toplandığını, hangi özellik için kullanıldığını,
/// arka planda toplanıp toplanmadığını ve kiminle paylaşıldığını açıklayan
/// bir ekran gösterilmesini ister. Sistem izin dialogu bunun yerine geçmez —
/// o Google'ın dialogudur, uygulamanın açıklaması değildir.
///
/// Bu yüzden `Geolocator.requestPermission()` **doğrudan çağrılmamalıdır**;
/// tüm çağrılar [LocationDisclosureService.ensure] üzerinden geçer.
///
/// Akış:
///   1. Bu amaç için daha önce açık onay verildi mi + izin hâlâ duruyor mu?
///      → evet ise hiçbir şey gösterme, doğrudan devam et.
///   2. Değilse uygulama içi açıklama ekranını göster (kapatılamaz,
///      "Kabul Et" / "Vazgeç" seçenekli).
///   3. Kabul → onayı kaydet → ancak o zaman sistem izin dialogunu aç.
///   4. Ret → hiçbir konum API'si çağrılmaz.
class LocationDisclosureService {
  LocationDisclosureService._();

  static const _privacyPolicyUrl = 'https://cizreapp.com/privacy.html';

  /// Onay kaydı anahtarı. Açıklama metni **anlamlı biçimde değişirse** bu
  /// sürüm artırılmalı; eski onaylar geçersiz olur ve kullanıcıya yeni metin
  /// tekrar gösterilir. (Play politikası, kullanımı genişleyen bir özellik
  /// için onayın yenilenmesini şart koşar.)
  static const _consentVersion = 1;

  static String _consentKey(LocationPurpose purpose) =>
      'location_disclosure_v${_consentVersion}_${purpose.name}';

  /// Konum kullanılmadan önce çağrılır. `true` dönerse hem kullanıcı onayı
  /// hem sistem izni alınmıştır ve konum API'leri güvenle çağrılabilir.
  ///
  /// [context] mounted değilse veya kullanıcı reddederse `false` döner —
  /// çağıran taraf bu durumda **hiçbir konum isteği yapmamalıdır**.
  static Future<bool> ensure(
    BuildContext context,
    LocationPurpose purpose,
  ) async {
    // Web'de tarayıcı kendi izin akışını yürütür ve Play politikası
    // kapsamı dışındadır; yine de açıklama gösterilir (aşağıda), çünkü
    // kullanıcı beklentisi platformdan bağımsızdır.
    final alreadyConsented = await _hasConsent(purpose);
    final hasPermission = await _hasSystemPermission();

    if (alreadyConsented && hasPermission) return true;

    if (!context.mounted) return false;

    final accepted = await _showDisclosure(context, purpose);
    if (!accepted) return false;

    await _saveConsent(purpose);
    if (!context.mounted) return false;

    return _requestSystemPermission(context);
  }

  /// Onay ve izin durumunu, kullanıcıya hiçbir şey göstermeden kontrol eder.
  /// Ekran açılışında "konum kapalı" rozeti göstermek gibi pasif kullanımlar
  /// içindir; izin istemez.
  static Future<bool> isReady(LocationPurpose purpose) async {
    return await _hasConsent(purpose) && await _hasSystemPermission();
  }

  // ───────────────────────────────────────────────────────────────────
  // İzin / onay durumu
  // ───────────────────────────────────────────────────────────────────

  static Future<bool> _hasSystemPermission() async {
    try {
      final p = await Geolocator.checkPermission();
      return p == LocationPermission.always ||
          p == LocationPermission.whileInUse;
    } catch (e) {
      debugPrint('Konum izni durumu okunamadı: $e');
      return false;
    }
  }

  static Future<bool> _hasConsent(LocationPurpose purpose) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_consentKey(purpose)) ?? false;
    } catch (e) {
      // Onay kaydı okunamıyorsa güvenli taraf: onay yok say, açıklamayı
      // tekrar göster. (Fazladan gösterim politikaya aykırı değil; eksik
      // gösterim aykırı.)
      debugPrint('Konum onayı okunamadı: $e');
      return false;
    }
  }

  static Future<void> _saveConsent(LocationPurpose purpose) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_consentKey(purpose), true);
    } catch (e) {
      debugPrint('Konum onayı kaydedilemedi: $e');
    }
  }

  /// Kullanıcı onayından **sonra** sistem izin dialogunu açar.
  static Future<bool> _requestSystemPermission(BuildContext context) async {
    try {
      var permission = await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.deniedForever) {
        if (context.mounted) await _showSettingsPrompt(context);
        return false;
      }

      return permission == LocationPermission.always ||
          permission == LocationPermission.whileInUse;
    } catch (e) {
      debugPrint('Konum izni istenirken hata: $e');
      return false;
    }
  }

  // ───────────────────────────────────────────────────────────────────
  // Açıklama metinleri
  // ───────────────────────────────────────────────────────────────────

  static _DisclosureContent _contentFor(LocationPurpose purpose) {
    switch (purpose) {
      case LocationPurpose.nearby:
        return const _DisclosureContent(
          icon: Icons.place_outlined,
          title: 'CizreApp konumunuzu kullanmak için izin istiyor',
          lead:
              'CizreApp, size yakındaki mağazaları ve ürünleri gösterebilmek '
              've teslimat adresinizi haritada doğru işaretleyebilmek için '
              'cihazınızın konum verisini (GPS koordinatlarınızı) toplar.',
          bullets: [
            _DisclosureBullet(
              icon: Icons.storefront_outlined,
              text:
                  'Konumunuz, çevrenizdeki satıcıları ve fırsatları mesafeye '
                  'göre sıralamak için kullanılır.',
            ),
            _DisclosureBullet(
              icon: Icons.local_shipping_outlined,
              text:
                  'Sipariş verirken seçtiğiniz teslimat adresinin koordinatı, '
                  'siparişi taşıyacak satıcı ve kurye ile paylaşılır.',
            ),
            _DisclosureBullet(
              icon: Icons.visibility_off_outlined,
              text:
                  'Konumunuz yalnızca uygulamayı kullandığınız sırada alınır. '
                  'Arka planda toplanmaz ve reklam amacıyla kullanılmaz.',
            ),
          ],
        );

      case LocationPurpose.courierTracking:
        return const _DisclosureContent(
          icon: Icons.delivery_dining_outlined,
          title: 'Kurye konum paylaşımı için izin gerekiyor',
          lead:
              'Kurye olarak konum paylaşımını açtığınızda CizreApp, teslimatı '
              'bekleyen müşterinin siparişini canlı takip edebilmesi için '
              'cihazınızın konum verisini (GPS koordinatlarınızı) düzenli '
              'aralıklarla toplar.',
          bullets: [
            _DisclosureBullet(
              icon: Icons.share_location_outlined,
              text:
                  'Konumunuz, aktif teslimatınızı bekleyen müşteriye haritada '
                  'canlı olarak gösterilir.',
            ),
            _DisclosureBullet(
              icon: Icons.notifications_active_outlined,
              text:
                  'Telefonunuz cebinizdeyken veya ekranınız kapalıyken de '
                  'konum toplanmaya devam eder. Bu sırada bildirim çubuğunda '
                  '"Konumunuz müşterilerle paylaşılıyor" bildirimi sürekli '
                  'görünür.',
            ),
            _DisclosureBullet(
              icon: Icons.stop_circle_outlined,
              text:
                  'Konum paylaşımını kurye panelinden istediğiniz an '
                  'kapatabilirsiniz; kapattığınızda toplama anında durur.',
            ),
          ],
        );

      case LocationPurpose.driverTrip:
        return const _DisclosureContent(
          icon: Icons.directions_bus_outlined,
          title: 'Sefer takibi için konum izni gerekiyor',
          lead:
              'Şoför olarak sefer başlattığınızda CizreApp, durakta bekleyen '
              'yolcuların aracınızın nerede olduğunu görebilmesi için '
              'cihazınızın konum verisini (GPS koordinatlarınızı) sefer '
              'boyunca düzenli aralıklarla toplar.',
          bullets: [
            _DisclosureBullet(
              icon: Icons.groups_outlined,
              text:
                  'Konumunuz, hattınızı takip eden yolculara haritada canlı '
                  'olarak gösterilir ve seferin rota kaydını oluşturur.',
            ),
            _DisclosureBullet(
              icon: Icons.notifications_active_outlined,
              text:
                  'Telefonunuz cebinizdeyken veya ekranınız kapalıyken de '
                  'konum toplanmaya devam eder. Bu sırada bildirim çubuğunda '
                  '"Sefer takibi devam ediyor" bildirimi sürekli görünür.',
            ),
            _DisclosureBullet(
              icon: Icons.schedule_outlined,
              text:
                  '"Otomatik Sefer" özelliğini açarsanız, yalnız belirlediğiniz '
                  'çalışma saatleri içinde konumunuz hat bölgenizle '
                  'karşılaştırılarak sefer kendiliğinden başlatılıp bitirilir. '
                  'Toplama, sefer bitince veya seferi elle durdurduğunuzda sona '
                  'erer.',
            ),
          ],
        );
    }
  }

  // ───────────────────────────────────────────────────────────────────
  // Arayüz
  // ───────────────────────────────────────────────────────────────────

  /// Açıklama ekranı. Play politikası gereği:
  ///   • sistem izin dialogundan önce gösterilir,
  ///   • geri tuşu veya dışına dokunarak kapatılamaz,
  ///   • net bir kabul ve net bir ret seçeneği sunar ("Tamam" tek başına
  ///     onay sayılmaz),
  ///   • gizlilik politikasına bağlantı verir (politika metni bunun yerine
  ///     geçmez, ona ek olarak sunulur).
  static Future<bool> _showDisclosure(
    BuildContext context,
    LocationPurpose purpose,
  ) async {
    final content = _contentFor(purpose);
    final theme = Theme.of(context);
    final accent = theme.colorScheme.primary;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => PopScope(
        canPop: false,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 24,
            vertical: 32,
          ),
          contentPadding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(content.icon, size: 32, color: accent),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  content.title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    height: 1.3,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  content.lead,
                  style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
                ),
                const SizedBox(height: 16),
                ...content.bullets.map(
                  (b) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(b.icon, size: 20, color: accent),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            b.text,
                            style: theme.textTheme.bodySmall?.copyWith(
                              height: 1.45,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                InkWell(
                  onTap: _openPrivacyPolicy,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.open_in_new, size: 16, color: accent),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            'Konum verinizin nasıl saklandığını Gizlilik '
                            'Politikamızda okuyabilirsiniz.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: accent,
                              decoration: TextDecoration.underline,
                              decorationColor: accent,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Kabul Ediyorum'),
            ),
          ],
        ),
      ),
    );

    return result ?? false;
  }

  /// Kullanıcı izni "bir daha sorma" ile reddettiyse sistem dialogu artık
  /// açılmaz; tek yol ayarlar ekranıdır.
  static Future<void> _showSettingsPrompt(BuildContext context) async {
    final open = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text('Konum izni kapalı'),
        content: const Text(
          'Konum izni daha önce kalıcı olarak reddedildiği için uygulama '
          'içinden tekrar sorulamıyor. Bu özelliği kullanmak isterseniz '
          'telefon ayarlarından CizreApp için konum iznini açabilirsiniz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Ayarları Aç'),
          ),
        ],
      ),
    );

    if (open == true) {
      try {
        await Geolocator.openAppSettings();
      } catch (e) {
        debugPrint('Ayarlar açılamadı: $e');
      }
    }
  }

  static Future<void> _openPrivacyPolicy() async {
    try {
      await launchUrl(
        Uri.parse(_privacyPolicyUrl),
        mode: kIsWeb
            ? LaunchMode.platformDefault
            : LaunchMode.externalApplication,
      );
    } catch (e) {
      debugPrint('Gizlilik politikası açılamadı: $e');
    }
  }
}

class _DisclosureContent {
  final IconData icon;
  final String title;
  final String lead;
  final List<_DisclosureBullet> bullets;

  const _DisclosureContent({
    required this.icon,
    required this.title,
    required this.lead,
    required this.bullets,
  });
}

class _DisclosureBullet {
  final IconData icon;
  final String text;

  const _DisclosureBullet({required this.icon, required this.text});
}
