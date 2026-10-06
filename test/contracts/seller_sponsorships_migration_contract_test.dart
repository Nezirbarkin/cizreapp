import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Satıcı öne çıkarma göçlerinin (Görev 3.2) YAPISAL kararları. Davranış
/// canlıda `supabase/tests/manual/seller_sponsorships_test.sql` (12 kontrol)
/// ile kanıtlanır; bu test, sessizce geri alınırsa ücretsiz sponsorluğa ya da
/// para kaybına yol açacak kararları sabitler.
void main() {
  late String enumSql;
  late String sql;
  late String code;

  String read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');
  String stripComments(String s) =>
      s.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

  setUpAll(() {
    enumSql = read('supabase/migrations/20260928000005_sponsorship_balance_type.sql');
    sql = read('supabase/migrations/20260928000006_seller_sponsorships.sql');
    code = stripComments(sql);
  });

  String fn(String name) => RegExp(
    'CREATE OR REPLACE FUNCTION ${RegExp.escape(name)}\\(.*?\\\$fn\\\$;',
    dotAll: true,
  ).firstMatch(code)!.group(0)!;

  test('işlem tipi AYRI göçte eklenir (aynı işlemde kullanılamaz)', () {
    expect(stripComments(enumSql).trim(),
        "alter type balance_transaction_type add value if not exists 'sponsorship_purchase';");
    expect(code, isNot(contains('ADD VALUE')));
  });

  test('tek işlem; şema yenilenir', () {
    expect(code, contains('\nBEGIN;\n'));
    expect(code, contains('\nCOMMIT;\n'));
    expect(code, contains("NOTIFY pgrst, 'reload schema';"));
  });

  group('vitrin sütunlarının koruması', () {
    test('tetikleyiciler SECURITY INVOKER (DEFINER olsaydı current_user hep sahip olurdu)', () {
      for (final name in ['public.guard_shop_sponsorship_columns', 'public.guard_product_sponsorship_columns']) {
        final def = fn(name);
        expect(def, isNot(contains('SECURITY DEFINER')), reason: name);
        expect(def, contains("IF current_user IN ('authenticated', 'anon') THEN"), reason: name);
        expect(def, contains(':= OLD.'), reason: '$name güncellemede eski değeri korumalı');
        expect(def, contains(':= NULL;'), reason: '$name eklemede sıfırlamalı');
      }
    });

    test('tetikleyiciler dört sütunu da kapsar', () {
      expect(code, contains('BEFORE INSERT OR UPDATE OF sponsored_list_until, sponsored_category_until ON public.shops'));
      expect(code, contains('BEFORE INSERT OR UPDATE OF sponsored_category_until, sponsored_discount_until ON public.products'));
    });
  });

  group('satın almalar tablosu', () {
    test('istemci doğrudan yazamaz: yazma politikası yok, yetki geri alınır', () {
      expect(RegExp(r'CREATE POLICY \w+ ON public\.shop_sponsorships\s+FOR (INSERT|UPDATE|DELETE|ALL)')
          .hasMatch(code), isFalse);
      expect(code, contains('REVOKE INSERT, UPDATE, DELETE ON public.shop_sponsorships FROM authenticated;'));
      expect(code, contains('REVOKE ALL ON public.shop_sponsorships FROM anon;'));
    });

    test('okuma: mağaza sahibi ya da admin', () {
      final policy = RegExp(r'CREATE POLICY shop_sponsorships_owner_read.*?;', dotAll: true)
          .firstMatch(code)!.group(0)!;
      expect(policy, contains('FOR SELECT TO authenticated'));
      expect(policy, contains('public.auth_is_admin()'));
      expect(policy, contains('s.owner_id = (SELECT auth.uid())'));
    });

    test('ürün vitrininde ürün zorunlu, mağaza vitrininde yasak; aktif satırın zaman aralığı var', () {
      expect(code, contains(
          "CHECK ((placement IN ('product_category', 'product_discount')) = (product_id IS NOT NULL))"));
      expect(code, contains("CHECK (status <> 'active' OR (starts_at IS NOT NULL AND ends_at > starts_at))"));
    });
  });

  group('satın alma RPC\'si', () {
    test('DEFINER, boş search_path; yalnız authenticated çağırır', () {
      final def = fn('public.purchase_shop_sponsorship');
      expect(def, contains('SECURITY DEFINER'));
      expect(def, contains("SET search_path = ''"));
      expect(code, contains('REVOKE ALL ON FUNCTION public.purchase_shop_sponsorship(uuid, uuid, uuid) FROM PUBLIC, anon;'));
      expect(code, contains('GRANT EXECUTE ON FUNCTION public.purchase_shop_sponsorship(uuid, uuid, uuid) TO authenticated;'));
    });

    test('mağaza sahibi denetimi ve yayındaki mağaza şartı', () {
      final def = fn('public.purchase_shop_sponsorship');
      expect(def, contains('v_shop.owner_id IS DISTINCT FROM v_uid'));
      expect(def, contains('NOT v_shop.is_active OR NOT v_shop.is_approved'));
    });

    test('bakiye satırı kilitlenir, yetmezse düşülmez', () {
      final def = fn('public.purchase_shop_sponsorship');
      final lock = def.indexOf('FROM public.user_balances ub');
      final check = def.indexOf('v_balance < v_pkg.price');
      final debit = def.indexOf('UPDATE public.user_balances');
      expect(def.substring(lock, check), contains('FOR UPDATE'));
      expect(check, lessThan(debit));
      expect(def, contains("HINT = 'insufficient_balance'"));
    });

    test('indirimsiz ürün İndirimdekiler vitrinine çıkamaz', () {
      final def = fn('public.purchase_shop_sponsorship');
      expect(def, contains("v_pkg.placement = 'product_discount' AND NOT COALESCE(v_product.discounted, false)"));
      expect(def, contains("HINT = 'product_not_discounted'"));
    });

    test('işlem kaydı yeni tiple; zincir önceki bitişten başlar', () {
      final def = fn('public.purchase_shop_sponsorship');
      expect(def, contains("'sponsorship_purchase'::public.balance_transaction_type"));
      expect(def, contains('GREATEST(now(), COALESCE(max(s.ends_at), now()))'));
      expect(def, contains('PERFORM private.refresh_sponsored_until('));
    });

    test('ayarlar: kapalıysa satılmaz, onay açıksa bekler (varsayılan açık / onaysız)', () {
      final def = fn('public.purchase_shop_sponsorship');
      expect(def, contains("s.key = 'sponsorship_enabled'"));
      expect(def, contains("s.key = 'sponsorship_requires_approval'"));
      expect(code, contains("('sponsorship_enabled', '\"true\"',"));
      expect(code, contains("('sponsorship_requires_approval', '\"false\"',"));
      expect(code, contains('ON CONFLICT (key) DO NOTHING;'));
    });
  });

  test('yardımcı sütun yazıcı dışarıya kapalı', () {
    expect(code, contains('REVOKE ALL ON FUNCTION private.refresh_sponsored_until(uuid, uuid, text) FROM PUBLIC;'));
  });

  test('varsayılan paketler: dört vitrin × günlük/haftalık; tekrar çalıştırma admin fiyatını ezmez', () {
    final rows = RegExp(r"\('(shop_list|shop_category|product_category|product_discount)',\s+'(Günlük|Haftalık)',\s+(\d+),\s+(\d+),")
        .allMatches(code)
        .toList();
    expect(rows, hasLength(8));
    expect(rows.map((m) => m.group(1)).toSet(), hasLength(4));
    expect(code, contains('ON CONFLICT (placement, duration_days) DO NOTHING;'));
  });

  test('canlı doğrulama betiği repoda ve her grubu kapsar', () {
    final live = read('supabase/tests/manual/seller_sponsorships_test.sql');
    for (var i = 1; i <= 12; i++) {
      expect(live, contains('[$i]'), reason: 'canlı testte [$i] yok');
    }
    expect(live, contains('TESTS_PASSED'));
  });
}
