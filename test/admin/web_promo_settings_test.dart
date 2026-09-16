import 'package:cizreapp/features/admin/services/web_promo_service.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tanıtım (promo) ekranı ayarlarının okuma/yazma biçimi.
///
/// NEDEN TEST EDİLİYOR: dönen tanıtım maddeleri TEK bir `app_settings`
/// satırında, satır sonlarıyla ayrılmış olarak saklanıyor. Bu biçim
/// bozulursa hata sessizdir — admin maddeleri kaydeder, tanıtım ekranı
/// hiçbir şey göstermez ya da tek bir dev madde gösterir. Aynı biçimi
/// `web/index.html` içindeki `splitLines()` de uyguluyor.
void main() {
  group('splitLines', () {
    test('her satır bir madde olur', () {
      expect(
        WebPromoSettings.splitLines('İlan ver\nAlışveriş yap\nKurye çağır'),
        ['İlan ver', 'Alışveriş yap', 'Kurye çağır'],
      );
    });

    test('Windows satır sonu (CRLF) da bölünür', () {
      // Admin panelindeki metin kutusuna kopyala-yapıştır yapılan metin
      // sıklıkla CRLF taşır; bölünmezse tek madde gibi görünürdü.
      expect(
        WebPromoSettings.splitLines('Bir\r\nİki\r\nÜç'),
        ['Bir', 'İki', 'Üç'],
      );
    });

    test('boş satırlar ve baştaki/sondaki boşluklar atılır', () {
      expect(
        WebPromoSettings.splitLines('\n  İlan ver  \n\n\nAlışveriş yap\n  \n'),
        ['İlan ver', 'Alışveriş yap'],
      );
    });

    test('tamamen boş metin boş liste verir (şerit hiç gösterilmez)', () {
      expect(WebPromoSettings.splitLines('   \n \n'), isEmpty);
    });
  });

  group('app_settings gidiş-dönüşü', () {
    /// `toSettingsMap()` çıktısını, tablodan okunmuş satırlar biçimine çevirir.
    List<Map<String, dynamic>> asRows(WebPromoSettings s) {
      return s
          .toSettingsMap()
          .entries
          .map(
            (e) => <String, dynamic>{
              'key': '${WebPromoService.keyPrefix}${e.key}',
              'value': e.value,
            },
          )
          .toList();
    }

    test('maddeler yazılıp okununca aynen geri gelir', () {
      const lines = [
        'İlan ver, alıcını bul',
        'Alışveriş yap, kapına gelsin',
        'Kurye çağır, paketin yola çıksın',
      ];
      final saved = WebPromoSettings.defaults.copyWith(rotatingLines: lines);

      final loaded = WebPromoSettings.fromRows(asRows(saved));

      expect(loaded.rotatingLines, lines);
    });

    test('tüm alanlar gidiş-dönüşte korunur', () {
      final saved = WebPromoSettings.defaults.copyWith(
        enabled: false,
        videoUrl: 'https://ornek/video.mp4',
        posterUrl: 'https://ornek/kapak.jpg',
        headline: 'CizreApp',
        tagline: 'Her an, her kapıda!',
        appStoreUrl: 'https://apps.apple.com/app/id123',
        continueText: 'Webte devam et',
        continueEnabled: false,
        rotateMs: 4200,
        showAlways: true,
        version: 7,
      );

      final loaded = WebPromoSettings.fromRows(asRows(saved));

      expect(loaded.enabled, isFalse);
      expect(loaded.videoUrl, 'https://ornek/video.mp4');
      expect(loaded.posterUrl, 'https://ornek/kapak.jpg');
      expect(loaded.appStoreUrl, 'https://apps.apple.com/app/id123');
      expect(loaded.continueEnabled, isFalse);
      expect(loaded.rotateMs, 4200);
      expect(loaded.showAlways, isTrue);
      expect(loaded.version, 7);
    });

    test('maddeler BİLEREK boşaltılmışsa varsayılana dönmez', () {
      // Anahtar var ama boş: admin maddeleri kaldırmış demektir. Burada
      // varsayılan listeye düşseydik silinen maddeler geri gelirdi.
      final saved = WebPromoSettings.defaults.copyWith(rotatingLines: const []);

      final loaded = WebPromoSettings.fromRows(asRows(saved));

      expect(loaded.rotatingLines, isEmpty);
    });

    test('anahtar HİÇ yoksa varsayılan maddeler kullanılır', () {
      // Migration uygulanmamış bir ortam: ekran boş kalmamalı.
      final loaded = WebPromoSettings.fromRows([
        {'key': 'web_promo_headline', 'value': 'CizreApp'},
      ]);

      expect(loaded.rotatingLines, WebPromoSettings.defaults.rotatingLines);
    });
  });

  group('geçiş süresi sınırlanır', () {
    int savedRotateMs(int value) {
      final map = WebPromoSettings.defaults
          .copyWith(rotateMs: value)
          .toSettingsMap();
      return int.parse(map['rotate_ms']!);
    }

    test('çok kısa süre alt sınıra çekilir (madde okunmadan geçmesin)', () {
      expect(savedRotateMs(0), 1200);
      expect(savedRotateMs(300), 1200);
    });

    test('çok uzun süre üst sınıra çekilir (şerit durmuş görünmesin)', () {
      expect(savedRotateMs(99999), 10000);
    });

    test('aradaki değerlere dokunulmaz', () {
      expect(savedRotateMs(2600), 2600);
    });
  });
}
