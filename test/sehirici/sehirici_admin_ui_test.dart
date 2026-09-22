// ignore_for_file: depend_on_referenced_packages, deprecated_member_use

import 'dart:convert';

import 'package:cizreapp/sehirici/admin/sehirici_admin_kit.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../helpers/sehirici_admin_harness.dart';

/// Şehiriçi yönetim paneli (kabuk + sekmeler + düzenleyici sayfalar).
///
/// Sunucu yerine SehiriciFakeBackend konuşur; harita yerine sahte platform
/// kullanılır. SEHIRICI_PREVIEW_DIR verilirse her ekranın PNG'si o klasöre
/// yazılır (görsel doğrulama için).
void main() {
  final h = SehiriciAdminHarness()..register();
  group('Kabuk', () {
    h.adminTest('başlık, şehir seçici ve sekme sayaçlarını gösterir', (tester) async {
      await h.pumpAdmin(tester);

      expect(find.text('Şehiriçi Yönetimi'), findsOneWidget);
      expect(find.text('Cizre'), findsWidgets);
      for (final tab in [0, 1, 2, 3, 4, 5, 6]) {
        expect(find.byKey(ValueKey('sehirici-nav-$tab')), findsOneWidget);
      }
      // Sayaçlar: 4 hat, 6+... durak, 10 ikon, 2 şoför, 2 şehir.
      final navText = tester
          .widgetList<Text>(find.descendant(
              of: find.byKey(const ValueKey('sehirici-nav-1')),
              matching: find.byType(Text)))
          .map((t) => t.data)
          .toList();
      expect(navText, contains('4'));
      expect(find.text('Açık'), findsOneWidget);
      await h.snapshot(tester, 'admin_00_shell_overview');
    });

    h.adminTest('modül anahtarı app_settings\'e DÜZ metin yazar ve başlığı günceller',
        (tester) async {
      await h.pumpAdmin(tester);
      expect(find.text('Açık'), findsOneWidget);

      await tester.tap(find.byType(Switch).first);
      await tester.pump();
      await h.settle(tester);

      final writes = h.backend.calls
          .where((c) => c.method == 'POST' && c.path.endsWith('/app_settings'))
          .toList();
      expect(writes, hasLength(1));
      final row = writes.single.body! as Map;
      expect(row['key'], 'sehirici_module_enabled');
      // Düz metin: '"false"' (çift tırnaklı) DEĞİL.
      expect(row['value'], 'false');
      expect(find.text('Kapalı'), findsOneWidget);
      // Genel bakışta kritik uyarı belirir.
      expect(find.text('Şehiriçi modülü kapalı'), findsOneWidget);
    });

    h.adminTest('şehir değiştirince o şehrin verisini yükler', (tester) async {
      await h.pumpAdmin(tester);
      expect(find.text('4'), findsWidgets);

      await tester.tap(find.byTooltip('Şehir değiştir'));
      // Menü animasyonu ilk karede %0'dadır; ikinci kare gerçek konumu verir.
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Silopi').last);
      await tester.pump();
      await h.settle(tester);

      // Silopi'de hat/durak yok → sayılar sıfırlanır.
      expect(find.text('0/0'), findsOneWidget);
      await h.openTab(tester, 1);
      expect(find.text('İlk hattı oluştur'), findsOneWidget);
    });
  });

  group('Genel bakış', () {
    h.adminTest('özet sayılar ve uyarılar', (tester) async {
      await h.pumpAdmin(tester, withTrips: true);

      expect(find.text('Şu an yolda'), findsOneWidget);
      // 4 hattan 4'ü aktif.
      expect(find.text('4/4'), findsOneWidget);
      expect(find.text('2 aktif hatta durak yok'), findsOneWidget);
      expect(find.text('1 hat kod veya ad içermiyor'), findsOneWidget);
      expect(find.text('1 hattın yol rotası eski'), findsOneWidget);
      expect(find.text('1 durak hiçbir hatta bağlı değil'), findsOneWidget);
      expect(find.text('1 şoföre hat atanmamış'), findsOneWidget);
      await h.snapshot(tester, 'admin_01_overview_top');

      // Sayfanın altına kaydır: harita + yolda olan araçlar.
      await tester.drag(find.byType(ListView).first, const Offset(0, -700));
      await tester.pump();
      await h.settle(tester);
      expect(find.text('Ahmet Yılmaz'), findsWidgets);
      // Başlıklar Türkçe büyük harfle yazılır (i → İ): "HARITA" değil "HARİTA".
      expect(find.text('CANLI HARİTA'), findsOneWidget);
      await h.snapshot(tester, 'admin_02_overview_bottom');
    });

    h.adminTest('uyarıdaki eylem ilgili sekmeye götürür', (tester) async {
      await h.pumpAdmin(tester);
      // "1 durak hiçbir hatta bağlı değil" → Duraklar
      await tester.ensureVisible(find.text('1 durak hiçbir hatta bağlı değil'));
      await tester.tap(find.widgetWithText(TextButton, 'Duraklar').first);
      await tester.pump();
      await h.settle(tester, rounds: 4);
      expect(find.text('Yeni Durak'), findsOneWidget);
    });
  });

  group('Hatlar', () {
    h.adminTest('liste: kod, ad, rota durumu ve şoför', (tester) async {
      await h.pumpAdmin(tester, tab: 1);
      expect(find.text('4A'), findsWidgets);
      expect(find.textContaining('Merkez – Hastane'), findsWidgets);
      expect(find.text('7B'), findsWidgets);
      expect(find.text('Yeni Hat'), findsOneWidget);
      await h.snapshot(tester, 'admin_03_lines');
    });

    h.adminTest('arama hatları süzer', (tester) async {
      await h.pumpAdmin(tester, tab: 1);
      await tester.enterText(find.byType(TextField).first, '7b');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('Çarşı – Sanayi'), findsWidgets);
      expect(find.textContaining('Merkez – Hastane'), findsNothing);
    });

    h.adminTest('Yeni Hat: boş form doğrulama hatası verir, dolu form RPC çağırır',
        (tester) async {
      await h.pumpAdmin(tester, tab: 1);
      await h.openSheet(tester, find.text('Yeni Hat'));
      expect(find.text('Hattı Oluştur'), findsOneWidget);
      await h.snapshot(tester, 'admin_04_line_editor');

      await tester.tap(find.text('Hattı Oluştur'));
      await tester.pump();
      expect(find.text('Hat kodu gerekli (ör. 4A)'), findsOneWidget);
      expect(h.backend.rpcCalls('admin_upsert_sehirici_line'), isEmpty);

      // Çakışan kod reddedilir.
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '4a');
      await tester.enterText(fields.at(1), 'Deneme');
      await tester.tap(find.text('Hattı Oluştur'));
      await tester.pump();
      expect(find.text('Bu kod bu şehirde zaten kullanılıyor'), findsOneWidget);

      await tester.enterText(fields.at(0), '12K');
      await tester.enterText(fields.at(1), 'Kuzey Hattı');
      await tester.tap(find.text('Hattı Oluştur'));
      await tester.pump();
      await h.settle(tester, rounds: 4);

      final calls = h.backend.rpcCalls('admin_upsert_sehirici_line').toList();
      expect(calls, hasLength(1));
      final params = calls.single.body! as Map;
      expect(params['p_code'], '12K');
      expect(params['p_name'], 'Kuzey Hattı');
      expect(params['p_city_id'], 'city-1');
      expect(params['p_vehicle_type'], isNotEmpty);
      // Sayfa kapandı.
      expect(find.text('Hattı Oluştur'), findsNothing);
    });

    h.adminTest('sunucu hatası sayfada gösterilir, sayfa açık kalır', (tester) async {
      await h.pumpAdmin(tester, tab: 1);
      await h.openSheet(tester, find.text('Yeni Hat'));
      h.backend
        ..failPathContaining = '/rpc/admin_upsert_sehirici_line'
        ..failMessage = 'Bu kod bu şehirde zaten kullanılıyor';
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), '99Z');
      await tester.enterText(fields.at(1), 'Sunucu Hatası');
      await tester.tap(find.text('Hattı Oluştur'));
      await tester.pump();
      await h.settle(tester, rounds: 4);
      expect(find.text('Hattı Oluştur'), findsOneWidget);
      expect(find.textContaining('zaten kullanılıyor'), findsWidgets);
    });
  });

  group('Duraklar', () {
    h.adminTest('liste, hat rozetleri ve bağlantısız durak', (tester) async {
      await h.pumpAdmin(tester, tab: 2);
      expect(find.text('Belediye'), findsWidgets);
      expect(find.text('Eski Terminal'), findsWidgets);
      expect(find.text('Yeni Durak'), findsOneWidget);
      await h.snapshot(tester, 'admin_05_stops');
    });

    h.adminTest('arama durağı adına, koduna ve adresine göre süzer', (tester) async {
      await h.pumpAdmin(tester, tab: 2);
      await tester.enterText(find.byType(TextField).first, 'terminal');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Eski Terminal'), findsWidgets);
      expect(find.text('Belediye'), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'Hastane Cd');
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Devlet Hastanesi'), findsWidgets);
      expect(find.text('Eski Terminal'), findsNothing);
    });

    h.adminTest('durak düzenleyici açılır', (tester) async {
      await h.pumpAdmin(tester, tab: 2);
      await h.openSheet(tester, find.text('Yeni Durak'));
      expect(find.text('Haritadan seç'), findsOneWidget);
      await h.snapshot(tester, 'admin_06_stop_editor');
    });
  });

  group('İkonlar', () {
    h.adminTest('araç ve durak ikonlarını listeler; özel ikon ayrı işaretlenir',
        (tester) async {
      await h.pumpAdmin(tester, tab: 3);
      expect(find.text('Minibüs'), findsWidgets);
      expect(find.text('Taksi'), findsWidgets);
      await h.snapshot(tester, 'admin_07_icons_vehicles');

      await tester.tap(find.textContaining('Duraklar ·'));
      await tester.pump();
      await h.settle(tester, rounds: 4);
      expect(find.text('Durak Levhası'), findsWidgets);
      await h.snapshot(tester, 'admin_08_icons_stops');
    });

    h.adminTest('mevcut ikon düzenleyicisi açılır', (tester) async {
      await h.pumpAdmin(tester, tab: 3);
      await h.openSheet(tester, find.text('Minibüs').first);
      expect(find.text('İkonu Düzenle'), findsOneWidget);
      expect(find.text('Yerleşik'), findsWidgets);
      await h.snapshot(tester, 'admin_09_icon_editor');
    });

    h.adminTest('yeni araç türü eklenir: ad → anahtar üretilir, RPC çağrılır',
        (tester) async {
      await h.pumpAdmin(tester, tab: 3);
      await h.openSheet(tester, find.text('Yeni araç türü / ikon ekle'));
      expect(find.text('Yeni Araç İkonu'), findsOneWidget);
      await h.snapshot(tester, 'admin_15_icon_editor_new');

      await tester.enterText(
          find.widgetWithText(TextField, 'Araç türü adı'), 'Servis Aracı');
      await tester.pump();
      await tester.tap(find.text('İkonu Ekle'));
      await tester.pump();
      await h.settle(tester, rounds: 4);

      final calls = h.backend.rpcCalls('admin_upsert_sehirici_marker_icon').toList();
      expect(calls, hasLength(1));
      final params = calls.single.body! as Map;
      expect(params['p_kind'], 'vehicle');
      expect(params['p_label'], 'Servis Aracı');
      expect(params['p_key'], isNotEmpty);
      expect(params['p_key'], matches(RegExp(r'^[a-z0-9_]+$')));
      expect(params['p_id'], isNull);
      // Sayfa kapandı.
      expect(find.text('Yeni Araç İkonu'), findsNothing);
    });
  });

  group('Şoförler', () {
    h.adminTest('liste ve atama durumu', (tester) async {
      await h.pumpAdmin(tester, tab: 4);
      expect(find.text('Ahmet Yılmaz'), findsWidgets);
      expect(find.text('Mehmet Kaya'), findsWidgets);
      await h.snapshot(tester, 'admin_10_drivers');
    });
  });

  group('Şehirler', () {
    h.adminTest('liste ve seçili şehir', (tester) async {
      await h.pumpAdmin(tester, tab: 5);
      expect(find.text('Cizre'), findsWidgets);
      expect(find.text('Silopi'), findsWidgets);
      expect(find.text('Seçili'), findsOneWidget);
      await h.snapshot(tester, 'admin_11_cities');
    });

    h.adminTest('şehir düzenleyici açılır', (tester) async {
      await h.pumpAdmin(tester, tab: 5);
      await h.openSheet(tester, find.text('Yeni Şehir'));
      expect(find.text('Şehir adı'), findsWidgets);
      await h.snapshot(tester, 'admin_12_city_editor');
    });
  });

  group('Ayarlar', () {
    h.adminTest('ayar grupları görünür', (tester) async {
      await h.pumpAdmin(tester, tab: 6);
      expect(find.text('Şehiriçi servisler açık'), findsOneWidget);
      await h.snapshot(tester, 'admin_13_settings');
      // ListView tembel kurulur: alttaki gruplar kaydırınca oluşur.
      await tester.drag(find.byType(ListView).first, const Offset(0, -900));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('HAT ROTALARI'), findsOneWidget);
      await h.snapshot(tester, 'admin_14_settings_bottom');
    });
  });

  test('sahte sunucunun oluşturduğu JSON geçerli', () {
    // Test altyapısının kendisi: satırlar JSON'a çevrilebilmeli.
    expect(() => jsonEncode(h.backend.lines), returnsNormally);
    expect(() => jsonEncode(h.backend.icons), returnsNormally);
  });
}
