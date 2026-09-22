import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Google SSV callback'i `ad_unit` alanında yalnız SAYISAL kimliği yollar
/// (3456629893); ad_settings ise SDK için TAM kimliği saklar
/// (ca-app-pub-XXXXXXXXXXXXXXXX/3456629893). `grant_verified_ad_points` yalnız
/// tam kimliği kabul ettiğinde AdMob onaylanıp reklam yayınlansa bile her gerçek
/// ödül AD_UNIT_NOT_ALLOWED ile düşerdi. Eski gövdeyi kopyalayan yeni bir göç bu
/// düzeltmeyi sessizce geri almasın diye, fonksiyonu SON tanımlayan göçü denetler.
void main() {
  late String latestDefinition;
  late String latestMigrationName;

  setUpAll(() {
    final files =
        Directory('supabase/migrations')
            .listSync()
            .whereType<File>()
            .where((f) => f.path.endsWith('.sql'))
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    final definers = files.where(
      (f) => RegExp(
        r'CREATE OR REPLACE FUNCTION public\.grant_verified_ad_points\(',
      ).hasMatch(f.readAsStringSync()),
    );
    expect(definers, isNotEmpty);
    latestMigrationName = definers.last.uri.pathSegments.last;
    latestDefinition = definers.last.readAsStringSync();
  });

  test('son grant_verified_ad_points tanımı sayısal ad_unit değerini kabul eder', () {
    expect(
      latestDefinition,
      contains("split_part(v_settings.admob_rewarded_unit_id_android, '/', 2)"),
      reason: '$latestMigrationName Android sayısal kimliği kabul etmiyor',
    );
    expect(
      latestDefinition,
      contains("split_part(v_settings.admob_rewarded_unit_id_ios, '/', 2)"),
      reason: '$latestMigrationName iOS sayısal kimliği kabul etmiyor',
    );
  });

  test('tam kimlik karşılaştırması geriye uyumlu olarak korunur', () {
    expect(
      latestDefinition,
      contains(
        'p_ad_unit_id IS DISTINCT FROM v_settings.admob_rewarded_unit_id_android',
      ),
    );
    expect(
      latestDefinition,
      contains(
        'p_ad_unit_id IS DISTINCT FROM v_settings.admob_rewarded_unit_id_ios',
      ),
    );
  });

  test('callback Edge Function ad_unit izin listesini virgülle ayırır', () {
    // ADMOB_SSV_PRODUCTION_AD_UNITS "3456629893,8182077031" biçiminde olmalı;
    // PowerShell'de tırnaksız `KEY=a,b` boşluklu yazıldığı için bu sözleşme
    // testle sabitlenir (bkz. reference_powershell_comma_secret_trap).
    final source = File(
      'supabase/functions/admob-ssv-callback/index.ts',
    ).readAsStringSync();
    expect(source, contains('.split(",")'));
    expect(source, contains('allowed.has(parsed.values.ad_unit)'));
  });
}
