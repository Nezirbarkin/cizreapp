import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Görev 3.7 — satıcı telefon + haritadan konum zorunluluğu. Davranış canlıda
/// `supabase/tests/manual/shop_contact_requirements_test.sql` (5 kontrol) ile
/// kanıtlanır; burada göçün ve ekran bağlantılarının yapısal kararları.
void main() {
  String read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');
  String stripComments(String s) => s.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

  test('göç: kural sunucuda, INVOKER tetikleyici, yalnız bu üç sütunda çalışır', () {
    final sql = stripComments(read('supabase/migrations/20260928000010_shop_contact_requirements.sql'));
    expect(sql, contains("BETWEEN 10 AND 13"));
    expect(sql, contains('BEFORE INSERT OR UPDATE OF phone, latitude, longitude ON public.shops'));
    final guard = RegExp(r'CREATE OR REPLACE FUNCTION public\.guard_shop_contact_info\(\).*?\$fn\$;', dotAll: true)
        .firstMatch(sql)!
        .group(0)!;
    expect(guard, isNot(contains('SECURITY DEFINER')), reason: 'DEFINER olursa yönetici/oturum ayrımı bozulur');
    expect(guard, contains('auth.uid() IS NULL OR public.auth_is_admin()'));
    expect(guard, contains("HINT = 'SHOP_PHONE_REQUIRED'"));
    expect(guard, contains("HINT = 'SHOP_LOCATION_REQUIRED'"));
    expect(guard, contains('NEW.phone IS DISTINCT FROM OLD.phone'));
  });

  test('panel: Genel Bakış en üstte kalıcı şerit; mağaza sorgusu telefon/konumu getirir', () {
    final overview = read('lib/features/seller/widgets/dashboard/seller_overview_tab.dart');
    final banner = overview.indexOf('ShopMissingInfoBanner(');
    final announcements = overview.indexOf('SellerAnnouncementsSection(');
    expect(banner, greaterThan(0));
    expect(banner, lessThan(announcements), reason: 'şerit duyuruların da üstünde');
    expect(overview, contains('ShopContactRequirements.missingFromShop(shopInfo)'));

    final dashboard = read('lib/features/seller/screens/seller_dashboard_screen.dart');
    expect(dashboard, contains(".select('id, name, phone, latitude, longitude,"));
    expect(dashboard, contains('onCompleteShopInfo: _openShopSettingsForContact,'));
  });

  test('mağaza oluşturma ve ayarlar: telefon biçimi + haritadan konum zorunlu', () {
    final dashboard = read('lib/features/seller/screens/seller_dashboard_screen.dart');
    final create = dashboard.substring(dashboard.indexOf('void _showCreateShopDialog()'));
    expect(create, contains('ShopContactRequirements.phoneError(phone)'));
    expect(create, contains("'latitude': latitude,"));
    expect(create, contains('Haritadan Konum Seç *'));

    final settings = read('lib/features/seller/screens/shop_settings_screen.dart');
    expect(settings, contains('validator: ShopContactRequirements.phoneError,'));
    expect(settings, isNot(contains('if (_pickupEnabled && (_latitude == null || _longitude == null))')),
        reason: 'konum artık yalnız Gel Al için değil, her zaman zorunlu');
    expect(settings, contains('if (_latitude == null || _longitude == null) {'));
  });

  test('canlı doğrulama betiği repoda ve her grubu kapsar', () {
    final live = read('supabase/tests/manual/shop_contact_requirements_test.sql');
    for (var i = 1; i <= 5; i++) {
      expect(live, contains('[$i]'), reason: 'canlı testte [$i] yok');
    }
    expect(live, contains('TESTS_PASSED'));
  });
}
