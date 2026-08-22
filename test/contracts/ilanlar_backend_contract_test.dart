import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String sql;
  late String notificationSql;
  late String guestVisibilitySql;
  late String anonPolicySql;
  late String defaultApprovalSql;
  late String ownerNotifySql;
  late String publishFeeTypeSql;
  late String publishFeeSql;

  setUpAll(() {
    sql = File(
      'supabase/migrations/20260817000006_ilanlar_system.sql',
    ).readAsStringSync();
    notificationSql = File(
      'supabase/migrations/20260817000009_notify_admin_on_new_ilan.sql',
    ).readAsStringSync();
    guestVisibilitySql = File(
      'supabase/migrations/20260817000010_fix_guest_ilan_visibility.sql',
    ).readAsStringSync();
    anonPolicySql = File(
      'supabase/migrations/20260817000011_fix_anon_ilan_policy_function_permissions.sql',
    ).readAsStringSync();
    defaultApprovalSql = File(
      'supabase/migrations/20260817000022_default_ilan_require_approval_false.sql',
    ).readAsStringSync();
    ownerNotifySql = File(
      'supabase/migrations/20260817000023_notify_owner_on_ilan_status_change.sql',
    ).readAsStringSync();
    publishFeeTypeSql = File(
      'supabase/migrations/20260817000024_ilan_publish_fee_balance_type.sql',
    ).readAsStringSync();
    publishFeeSql = File(
      'supabase/migrations/20260817000025_ilan_category_publish_fee.sql',
    ).readAsStringSync();
  });

  test('ilan tabloları ve RLS açık şekilde tanımlıdır', () {
    for (final table in [
      'ilan_settings',
      'ilan_categories',
      'ilanlar',
      'ilan_images',
      'ilan_favorites',
    ]) {
      expect(sql, contains('CREATE TABLE IF NOT EXISTS public.$table'));
      expect(
        sql,
        contains('ALTER TABLE public.$table ENABLE ROW LEVEL SECURITY'),
      );
    }
  });

  test('kayıp kategorisi fiyatı DB seviyesinde yasaklar', () {
    expect(sql, contains("v_pricing_mode = 'forbidden'"));
    expect(sql, contains('NEW.price := NULL'));
    expect(sql, contains("'lost', 'forbidden'"));
  });

  test('kullanıcı paylaşımı ve moderasyon ayarları sunucuda uygulanır', () {
    expect(sql, contains('allow_user_create'));
    expect(sql, contains('require_approval'));
    expect(sql, contains("THEN 'pending' ELSE 'published'"));
    expect(sql, contains('max_active_per_user'));
  });

  test('ilan storage yazma politikası kullanıcı klasörünü zorunlu tutar', () {
    expect(sql, contains("bucket_id = 'ilan-images'"));
    expect(
      sql,
      contains("(storage.foldername(name))[1] = (SELECT auth.uid())::text"),
    );
  });

  test('yeni ilan tüm adminlere güvenli push kuyruğu üzerinden bildirilir', () {
    expect(notificationSql, contains('notify_admin_on_new_ilan'));
    expect(notificationSql, contains('AFTER INSERT ON public.ilanlar'));
    expect(notificationSql, contains("'admin_notification'"));
    expect(notificationSql, contains("p.role::text = 'admin'"));
    expect(
      notificationSql,
      contains("'admin_section', 'İlanlar & Kategoriler'"),
    );
    expect(notificationSql, contains('INSERT INTO public.notifications'));
  });

  test('yayındaki ilanlar ayar açıkken misafirlere okunabilir', () {
    expect(
      guestVisibilitySql,
      contains('GRANT SELECT ON public.ilanlar TO anon'),
    );
    expect(guestVisibilitySql, contains("status = 'published'"));
    expect(guestVisibilitySql, contains('s.allow_guest_view'));
    expect(guestVisibilitySql, contains('(SELECT auth.uid()) IS NOT NULL'));
  });

  test('anon politikaları admin helper çağırmadan çalışır', () {
    final anonCategoryPolicy = RegExp(
      r'CREATE POLICY ilan_categories_anon_read[\s\S]*?;',
    ).firstMatch(anonPolicySql)!.group(0)!;
    final anonIlanPolicy = RegExp(
      r'CREATE POLICY ilanlar_anon_read[\s\S]*?;',
    ).firstMatch(anonPolicySql)!.group(0)!;
    final anonImagePolicy = RegExp(
      r'CREATE POLICY ilan_images_anon_read[\s\S]*?;',
    ).firstMatch(anonPolicySql)!.group(0)!;

    expect(anonCategoryPolicy, isNot(contains('ilan_is_admin')));
    expect(anonIlanPolicy, isNot(contains('ilan_is_admin')));
    expect(anonImagePolicy, isNot(contains('ilan_is_admin')));
    expect(anonIlanPolicy, contains("status = 'published'"));
    expect(anonIlanPolicy, contains('s.allow_guest_view'));
  });

  test('yeni ilanlar varsayılan olarak onay beklemeden yayınlanır', () {
    expect(defaultApprovalSql, contains('ALTER TABLE public.ilan_settings'));
    expect(defaultApprovalSql, contains('SET DEFAULT false'));
    expect(defaultApprovalSql, contains('SET require_approval = false'));
  });

  test('ilan sahibi moderasyon kararında bildirim alır', () {
    expect(ownerNotifySql, contains('notify_owner_on_ilan_status_change'));
    expect(ownerNotifySql, contains('AFTER UPDATE ON public.ilanlar'));
    expect(
      ownerNotifySql,
      contains('NEW.moderated_at IS NOT DISTINCT FROM OLD.moderated_at'),
    );
    expect(
      ownerNotifySql,
      contains("NEW.status NOT IN ('published', 'rejected', 'archived')"),
    );
    expect(ownerNotifySql, contains("'ilan_status_change'"));
    expect(ownerNotifySql, contains('INSERT INTO public.notifications'));
  });

  test(
    'ilan yayınlama ücreti işlem tipleri ayrı bir migration ile eklenir',
    () {
      expect(
        publishFeeTypeSql,
        contains("add value if not exists 'ilan_publish_fee'"),
      );
      expect(
        publishFeeTypeSql,
        contains("add value if not exists 'ilan_publish_refund'"),
      );
    },
  );

  test(
    'kategori yayınlama ücreti gönderim anında bakiyeden düşülür ve reddedilirse iade edilir',
    () {
      expect(
        publishFeeSql,
        contains(
          'ADD COLUMN IF NOT EXISTS publish_fee numeric(10,2) NOT NULL DEFAULT 0',
        ),
      );
      expect(
        publishFeeSql,
        contains('ADD COLUMN IF NOT EXISTS paid_fee numeric(10,2)'),
      );
      expect(
        publishFeeSql,
        contains('ADD COLUMN IF NOT EXISTS fee_refunded boolean'),
      );
      expect(publishFeeSql, contains('c.publish_fee'));
      expect(publishFeeSql, contains('FOR UPDATE'));
      expect(
        publishFeeSql,
        contains("'ilan_publish_fee'::public.balance_transaction_type"),
      );
      expect(
        publishFeeSql,
        contains(
          "NEW.status = 'rejected' AND OLD.paid_fee > 0 AND NOT COALESCE(OLD.fee_refunded, false)",
        ),
      );
      expect(
        publishFeeSql,
        contains("'ilan_publish_refund'::public.balance_transaction_type"),
      );
      expect(publishFeeSql, contains('NEW.paid_fee := OLD.paid_fee;'));
    },
  );
}
