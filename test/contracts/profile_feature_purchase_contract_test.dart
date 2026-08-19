import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  late String balanceTypeSql;
  late String coverPricingSql;
  late String pointsPurchaseSql;

  setUpAll(() {
    balanceTypeSql = File(
      'supabase/migrations/20260817000026_profile_feature_purchase_balance_type.sql',
    ).readAsStringSync();
    coverPricingSql = File(
      'supabase/migrations/20260817000027_profile_feature_cover_kind_and_pricing.sql',
    ).readAsStringSync();
    pointsPurchaseSql = File(
      'supabase/migrations/20260818000006_profile_feature_points_purchase.sql',
    ).readAsStringSync();
  });

  test('yeni bakiye işlem tipi kendi tek başına migration dosyasında eklenir', () {
    expect(
      balanceTypeSql,
      contains(
        "alter type balance_transaction_type add value if not exists 'profile_feature_purchase'",
      ),
    );
    // Aynı transaction içinde kullanılamayacağı için bu dosyada RPC/insert olmamalı.
    expect(balanceTypeSql, isNot(contains('create or replace function')));
  });

  test('kind kısıtlaması cover_effect ile genişletilir', () {
    expect(
      coverPricingSql,
      contains('profile_feature_catalog_kind_check'),
    );
    expect(
      coverPricingSql,
      contains(
        "check (kind in ('effect', 'avatar_effect', 'cover_effect', 'icon', 'badge'))",
      ),
    );
  });

  test(
    'eski TL fiyat kolonları (tarihsel) negatif olamaz şekilde eklenmişti — '
    '20260818000006 bunları NULL\'a çekip yerine puan kolonu koyar',
    () {
      expect(coverPricingSql, contains('add column if not exists price_monthly'));
      expect(coverPricingSql, contains('add column if not exists price_yearly'));
      expect(coverPricingSql, contains('add column if not exists purchase_plan'));
      expect(coverPricingSql, contains('add column if not exists purchased_price'));
    },
  );

  test('avatar-only ve cover-only satın alınabilir dekorasyonlar eklenir', () {
    for (final rendererKey in [
      'snake_coil',
      'butterfly_land',
      'firefly_dance',
      'cat_paw_peek',
    ]) {
      expect(coverPricingSql, contains("'$rendererKey'"));
    }
    for (final rendererKey in [
      'butterfly_meadow_cover',
      'aurora_veil_cover',
      'petal_drift_cover',
      'firefly_dusk_cover',
    ]) {
      expect(coverPricingSql, contains("'$rendererKey'"));
    }
    // Bu satırlar ücretsiz elde edilemez, yalnız satın alınabilir.
    expect(coverPricingSql, contains('false,\n  c.price_monthly'));
  });

  // ---------------------------------------------------------------------
  // 20260818000006: TL ücreti kaldırılıp puanla satın almaya geçiş.
  // Mağaza uyum denetiminde bulunan risk — profil özellikleri artık iyzico
  // ile yüklenen gerçek bakiyeyle değil, yalnızca kazanılan (satın
  // alınamayan) puanla satın alınabilir.
  // ---------------------------------------------------------------------

  test('katalog puan fiyatı kolonları eklenir ve eski TL fiyatı NULL\'a çekilir', () {
    expect(pointsPurchaseSql, contains('add column if not exists points_price_monthly'));
    expect(pointsPurchaseSql, contains('add column if not exists points_price_yearly'));
    expect(pointsPurchaseSql, contains('add column if not exists purchased_points'));
    expect(pointsPurchaseSql, contains('price_monthly = null,'));
    expect(pointsPurchaseSql, contains('price_yearly = null,'));
    // Başlangıç puanı uydurma değil — mevcut ad_settings.points_per_try'den hesaplanır.
    expect(pointsPurchaseSql, contains('points_per_try'));
  });

  test(
    'point_ledger_entries CHECK listeleri profile_feature_debit/profile_feature '
    'ile genişletilir (type_direction eşleşmesi dahil)',
    () {
      expect(pointsPurchaseSql, contains('drop constraint if exists point_ledger_entries_entry_type_check'));
      expect(pointsPurchaseSql, contains('drop constraint if exists point_ledger_entries_reference_type_check'));
      expect(pointsPurchaseSql, contains('drop constraint if exists point_ledger_type_direction'));
      expect(pointsPurchaseSql, contains("'profile_feature_debit'"));
      expect(pointsPurchaseSql, contains("'profile_feature'"));
      // Yeni entry_type'ın direction eşleşmesi olmadan reward_points_apply_entry
      // her çağrıda point_ledger_type_direction constraint'ine takılır.
      expect(
        pointsPurchaseSql,
        contains("'expiry_debit', 'profile_feature_debit') and direction = 'debit'"),
      );
    },
  );

  test(
    'puanla satın alma RPC\'si service_role JWT\'sini doğrular ve '
    'reward_points_apply_entry üzerinden puan düşer',
    () {
      expect(pointsPurchaseSql, contains('purchase_my_profile_feature_with_points'));
      expect(pointsPurchaseSql, contains('security definer'));
      expect(pointsPurchaseSql, contains("set search_path = ''"));
      expect(pointsPurchaseSql, contains("current_setting('request.jwt.claims', true)"));
      expect(pointsPurchaseSql, contains("'SERVICE_ROLE_REQUIRED'"));
      expect(pointsPurchaseSql, contains('reward_points_spend_enabled'));
      expect(pointsPurchaseSql, contains("reward_feature_mode <> 'enabled'"));
      expect(pointsPurchaseSql, contains("'REWARD_FEATURE_DISABLED'"));
      expect(pointsPurchaseSql, contains('public.reward_points_apply_entry('));
      expect(pointsPurchaseSql, contains('insert into public.user_profile_features'));
      expect(pointsPurchaseSql, contains('on conflict (user_id, feature_id) do update'));
      // idempotent replay'de user_profile_features tekrar uzatılmamalı.
      expect(pointsPurchaseSql, contains('v_duplicate'));
    },
  );

  test(
    'puanla satın alma RPC\'si yalnızca service_role\'e açık ve '
    'reward_points_owner sahipli (authenticated\'a asla doğrudan açılmaz)',
    () {
      const signature =
          'purchase_my_profile_feature_with_points(uuid, uuid, text, text)';
      expect(
        pointsPurchaseSql,
        contains('revoke all on function public.$signature from public, anon, authenticated'),
      );
      expect(
        pointsPurchaseSql,
        contains('grant execute on function public.$signature to service_role'),
      );
      expect(
        pointsPurchaseSql,
        isNot(contains('grant execute on function public.$signature to authenticated')),
      );
      expect(
        pointsPurchaseSql,
        contains('alter function public.$signature owner to reward_points_owner'),
      );
      // reward_points_owner'ın public şemasında CREATE'i yok (sertleştirme
      // sonrası) — ALTER OWNER TO bunu şart koştuğu için yetki yalnızca bu
      // devir için geri verilip hemen sonra tekrar kaldırılmalı; kalıcı
      // olarak açık bırakılmamalı.
      final grantIndex = pointsPurchaseSql.indexOf('grant create on schema public to reward_points_owner');
      final ownerIndex = pointsPurchaseSql.indexOf('alter function public.$signature owner to reward_points_owner');
      final revokeIndex = pointsPurchaseSql.indexOf('revoke create on schema public from reward_points_owner');
      expect(grantIndex, greaterThan(-1), reason: 'geçici CREATE grant\'i bulunamadı');
      expect(revokeIndex, greaterThan(-1), reason: 'geçici CREATE grant\'inin geri alınması bulunamadı');
      expect(grantIndex, lessThan(ownerIndex), reason: 'CREATE, devirden ÖNCE verilmeli');
      expect(ownerIndex, lessThan(revokeIndex), reason: 'CREATE, devirden SONRA kaldırılmalı');
    },
  );

  test('admin puan fiyatı RPC\'si sadece admin tarafından çağrılabilir', () {
    expect(pointsPurchaseSql, contains('admin_set_profile_feature_points_pricing'));
    expect(pointsPurchaseSql, contains('private.current_user_is_admin()'));
    expect(
      pointsPurchaseSql,
      contains("case when kind = 'badge' then null else p_points_monthly end"),
    );
    expect(
      pointsPurchaseSql,
      contains(
        'grant execute on function public.admin_set_profile_feature_points_pricing(uuid, bigint, bigint) to authenticated, service_role',
      ),
    );
  });

  test(
    'kullanıcının satın alabileceği katalog artık puan fiyatı olan satırlarla sınırlıdır',
    () {
      expect(pointsPurchaseSql, contains('drop function if exists public.get_my_purchasable_profile_features()'));
      expect(pointsPurchaseSql, contains('points_price_monthly'));
      expect(pointsPurchaseSql, contains('points_price_yearly'));
      expect(
        pointsPurchaseSql,
        contains('and (c.points_price_monthly is not null or c.points_price_yearly is not null)'),
      );
    },
  );

  test('eski TL akışı (purchase_my_profile_feature, admin_set_profile_feature_pricing) kaldırılır', () {
    expect(
      pointsPurchaseSql,
      contains('drop function if exists public.purchase_my_profile_feature(uuid, text)'),
    );
    expect(
      pointsPurchaseSql,
      contains(
        'drop function if exists public.admin_set_profile_feature_pricing(uuid, numeric, numeric)',
      ),
    );
  });
}
