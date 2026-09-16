import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Kupon düzeltme migration'ının sözleşmesi.
///
/// Canlı veritabanında doğrulanan beş hata bu migration ile kapatıldı; burada
/// migration metninin o düzeltmeleri **hâlâ içerdiği** garanti ediliyor
/// (davranış testleri: `supabase/tests/database/015_coupon_flow_behavior.test.sql`).
void main() {
  late String sql;
  late String code;

  setUpAll(() {
    sql = File(
      'supabase/migrations/20260913100002_fix_coupons_end_to_end.sql',
    ).readAsStringSync();
    // Migration başlığı hatalı desenleri (örn. `WHERE id = p_coupon_id`)
    // belgelemek için alıntılıyor; olumsuz kontroller yalnız SQL'e bakmalı.
    code = sql
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('--'))
        .join('\n');
  });

  /// `CREATE POLICY <ad> ...;` gövdesini döndürür (politika içinde `;` yok).
  String policyBlock(String name) {
    final start = sql.indexOf('CREATE POLICY $name ON');
    expect(start, greaterThan(-1), reason: '$name politikası migration\'da yok');
    final end = sql.indexOf(';', start);
    return sql.substring(start, end == -1 ? sql.length : end);
  }

  /// prepare_checkout_session yamasının `DO $mig$ ... $mig$;` bloğu.
  String patchBlock() {
    final start = sql.indexOf('DO \$mig\$');
    expect(start, greaterThan(-1), reason: 'yama bloğu migration\'da yok');
    final end = sql.indexOf('\$mig\$;', start);
    return sql.substring(start, end == -1 ? sql.length : end);
  }

  test('private.validate_coupon 42702 için nitelenmiş kolon kullanır', () {
    expect(sql, contains('CREATE OR REPLACE FUNCTION private.validate_coupon'));
    expect(sql, contains('FROM public.shop_coupons sc'));
    expect(sql, contains('WHERE sc.id = p_coupon_id'));

    // RETURNS TABLE kolon adları PL/pgSQL değişkeni olduğu için nitelenmemiş
    // `id`/`code` atıfı 42702 verir.
    expect(code, isNot(contains('WHERE id = p_coupon_id')));
    expect(code, isNot(contains('AND user_id = p_user_id')));
    expect(sql, contains('WHERE cu.coupon_id = v_coupon.id'));
  });

  test('indirim tipi enum değeri fixed_amount ile karşılaştırılır', () {
    // Hem validate_coupon içinde hem prepare_checkout_session yamasında.
    expect(
      RegExp(r"IN \('fixed_amount', 'fixed'\)").allMatches(sql).length,
      greaterThanOrEqualTo(1),
      reason: 'validate_coupon fixed_amount kabul etmeli',
    );
    expect(
      sql,
      contains("IN (''fixed_amount'', ''fixed'')"),
      reason: 'prepare_checkout_session yaması fixed_amount eklemeli',
    );
  });

  test('prepare_checkout_session yaması sessizce atlanmaz', () {
    final patch = patchBlock();
    expect(patch, contains('pg_get_functiondef'));
    expect(patch, contains('EXECUTE replace(v_def, v_old, v_new)'));
    // Yama noktası bulunamazsa migration hata vermeli, no-op geçmemeli.
    expect(patch, contains('RAISE EXCEPTION'));
  });

  test('müşteri ve misafir aktif kuponları görebilir', () {
    final customer = policyBlock('shop_coupons_select');
    expect(customer, contains('is_active = true'));
    expect(customer, contains('s.is_approved = true'));
    expect(customer, contains('public.auth_is_admin()'));
  });

  test('anon kupon politikası auth_is_admin() çağırmaz (42501 tuzağı)', () {
    final anon = policyBlock('shop_coupons_select_anon');
    expect(anon, contains('TO anon'));
    expect(anon, contains('is_active = true'));
    expect(
      anon,
      isNot(contains('auth_is_admin')),
      reason: 'anon rolü profiles okuyamaz; admin kontrolü 42501 verir',
    );
  });

  test('satıcı kendi kuponunun kullanımlarını görebilir', () {
    final usages = policyBlock('coupon_usages_select');
    expect(usages, contains('FROM public.shop_coupons sc'));
    expect(usages, contains('JOIN public.shops s ON s.id = sc.shop_id'));
    expect(usages, contains('s.owner_id = (SELECT auth.uid())'));
  });

  test('kupon ekleme normalize trigger\'ı kurulur', () {
    expect(sql, contains('CREATE OR REPLACE FUNCTION public.shop_coupons_normalize'));
    expect(sql, contains('NEW.code := upper(btrim(COALESCE(NEW.code, \'\')))'));
    expect(sql, contains('CREATE TRIGGER shop_coupons_normalize_trigger'));
    expect(sql, contains('BEFORE INSERT OR UPDATE ON public.shop_coupons'));

    // shop_id fallback: min(uuid) diye bir aggregate yok — sayım ve seçim ayrı.
    expect(sql, isNot(contains('min(s.id)')));
    expect(sql, contains('SELECT count(*) INTO v_shop_count'));

    // Anlaşılır Türkçe hatalar
    expect(sql, contains('Bu kupon kodu magazanizda zaten kayitli'));
    expect(sql, contains('Kupon olusturabilmek icin once magaza olusturmalisiniz'));
    expect(sql, contains('Yuzde indirim 100 uzerinde olamaz'));
  });

  test('usage_count çift artışı kaldırılır ve geçmiş sayaçlar düzeltilir', () {
    expect(
      sql,
      contains('DROP TRIGGER IF EXISTS trigger_record_coupon_usage ON public.coupon_usages'),
    );
    expect(sql, contains('UPDATE public.shop_coupons sc'));
    expect(sql, contains('SET usage_count = sub.cnt'));
  });

  test('migration yıkıcı işlem içermez', () {
    final lower = sql.toLowerCase();
    expect(lower, isNot(contains('drop table')));
    expect(lower, isNot(contains('drop type')));
    expect(lower, isNot(contains('delete from public.shop_coupons')));
    expect(lower, isNot(contains('disable row level security')));
  });
}
