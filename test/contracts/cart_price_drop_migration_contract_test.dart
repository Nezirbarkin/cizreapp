import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Sepet takibi + indirim bildirimi göçünün (Görev 3.3) YAPISAL kararları.
/// Davranış canlıda `supabase/tests/manual/cart_price_drop_notifications_test.sql`
/// (10 kontrol) ile kanıtlanır.
void main() {
  late String code;

  String read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');
  String stripComments(String s) =>
      s.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

  setUpAll(() {
    code = stripComments(read('supabase/migrations/20260928000007_cart_price_drop_notifications.sql'));
  });

  String fn(String name, String end) => RegExp(
    'CREATE OR REPLACE FUNCTION ${RegExp.escape(name)}\\(.*?${RegExp.escape(end)};',
    dotAll: true,
  ).firstMatch(code)!.group(0)!;

  test('tek işlem; şema yenilenir', () {
    expect(code, contains('\nBEGIN;\n'));
    expect(code, contains('\nCOMMIT;\n'));
    expect(code, contains("NOTIFY pgrst, 'reload schema';"));
  });

  group('fiyat alarmı hata düzeltmesi', () {
    test('format() yalnız %s kullanır (%.2f 22023 veriyordu)', () {
      final def = fn('public.notify_price_drops', r'$function$');
      expect(def, isNot(contains('%.2f')));
      expect(def, contains('private.format_try(v_new_price)'));
    });

    test('bildirim hatası ürün güncellemesini geri almaz', () {
      expect(fn('public.notify_price_drops', r'$function$'), contains('EXCEPTION WHEN OTHERS THEN'));
      expect(fn('public.notify_cart_price_drop', r'$fn$'), contains('EXCEPTION WHEN OTHERS THEN'));
    });
  });

  group('sepet bildirimi', () {
    test('yalnız gerçek düşüş: geçerli fiyat, %1 / 1 TL eşiği, satışta ürün, aktif mağaza', () {
      final def = fn('public.notify_cart_price_drop', r'$fn$');
      expect(def, contains('THEN NEW.discount_price ELSE NEW.price END'));
      expect(def, contains('(v_old - v_new) < LEAST(1, v_old * 0.01)'));
      expect(def, contains('NOT COALESCE(NEW.is_available, false)'));
      expect(def, contains('COALESCE(s.is_active, false)'));
    });

    test('müşteri tercihi, 24 saat sınırı ve satıcının kendi sepeti', () {
      final def = fn('public.notify_cart_price_drop', r'$fn$');
      expect(def, contains('np.cart_price_drop_enabled = false'));
      expect(def, contains("l.notified_at > now() - interval '24 hours'"));
      expect(def, contains('c.user_id IS DISTINCT FROM v_shop.owner_id'));
      expect(def, contains("'cart_price_drop'"));
    });

    test('tetikleyici yalnız fiyat/indirim değişince', () {
      expect(code, contains(
          'WHEN (OLD.price IS DISTINCT FROM NEW.price OR OLD.discount_price IS DISTINCT FROM NEW.discount_price)'));
      expect(code, contains('EXECUTE FUNCTION public.notify_cart_price_drop();'));
    });

    test('tercih varsayılan açık; bildirim günlüğü istemciye kapalı', () {
      expect(code, contains('ADD COLUMN IF NOT EXISTS cart_price_drop_enabled boolean NOT NULL DEFAULT true;'));
      expect(code, contains('REVOKE ALL ON public.cart_price_drop_notifications FROM PUBLIC, anon, authenticated;'));
      expect(code, contains('PRIMARY KEY (user_id, product_id)'));
    });
  });

  group('satıcı istatistiği', () {
    test('DEFINER, yalnız mağaza sahibi ya da admin; anon çağıramaz', () {
      final def = fn('public.get_shop_cart_stats', r'$fn$');
      expect(def, contains('SECURITY DEFINER'));
      expect(def, contains("SET search_path = ''"));
      expect(def, contains('v_owner <> v_uid AND NOT public.auth_is_admin()'));
      expect(code, contains('REVOKE ALL ON FUNCTION public.get_shop_cart_stats(uuid) FROM PUBLIC, anon;'));
      expect(code, contains('GRANT EXECUTE ON FUNCTION public.get_shop_cart_stats(uuid) TO authenticated;'));
    });

    test('müşteri kimliği dönmez; satıcının kendi sepeti sayılmaz', () {
      final def = fn('public.get_shop_cart_stats', r'$fn$');
      final output = def.substring(def.indexOf("SELECT jsonb_build_object("));
      expect(output, isNot(contains("'user_id'")));
      expect(def, contains('c.user_id IS DISTINCT FROM v_owner'));
    });
  });

  test('bildirime dokunma ürünü açar: /p/<id> rotası ve push yönlendirmesi', () {
    expect(read('lib/main.dart'), contains("if (routeName.startsWith('/p/')) {"));
    final push = read('lib/core/services/push_notification_service.dart');
    expect(push, contains("case 'cart_price_drop':"));
    expect(push, contains(r"navigator.pushNamed('/p/$productId');"));
  });

  test('canlı doğrulama betiği repoda ve her grubu kapsar', () {
    final live = read('supabase/tests/manual/cart_price_drop_notifications_test.sql');
    for (var i = 1; i <= 10; i++) {
      expect(live, contains('[$i]'), reason: 'canlı testte [$i] yok');
    }
    expect(live, contains('TESTS_PASSED'));
  });
}
