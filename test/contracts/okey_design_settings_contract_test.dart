import 'dart:io';

import 'package:cizreapp/okey/theme/okey_design.dart';
import 'package:flutter_test/flutter_test.dart';

/// 101 Okey tasarım ayarı göçünün (2026-10-05) YAPISAL kararları.
///
/// Davranış canlı veritabanında
/// `supabase/tests/manual/okey_design_settings_test.sql` ile kanıtlanır
/// (7 kontrol). Bu test istemci ile sunucunun AYNI dili konuşmasını sabitler:
/// RPC'nin döndürdüğü alan adları, istemcinin yazdığı anahtarlar, okumanın
/// misafire açık olması.
void main() {
  const fileName = '20261005000020_okey_design_settings.sql';
  late String sql;
  late String service;

  String read(String path) =>
      File(path).readAsStringSync().replaceAll('\r\n', '\n');

  String stripComments(String s) =>
      s.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

  setUpAll(() {
    sql = read('supabase/migrations/$fileName');
    service = read('lib/okey/services/okey_design_service.dart');
  });

  test('tek işlemde çalışır ve PostgREST şemasını yeniler', () {
    final code = stripComments(sql);
    expect(RegExp(r'^BEGIN;', multiLine: true).hasMatch(code), isTrue);
    expect(RegExp(r'^COMMIT;', multiLine: true).hasMatch(code), isTrue);
    expect(code, contains("NOTIFY pgrst, 'reload schema';"));
  });

  test('üç ayar satırı mevcut değeri EZMEDEN eklenir', () {
    for (final key in [
      'okey_design',
      'okey_lobby_layout',
      'okey_design_user_choice',
    ]) {
      expect(sql, contains("'$key'"), reason: key);
      // İstemci de aynı anahtarları yazar.
      expect(service, contains("'key': '$key'"), reason: key);
    }
    expect(sql, contains('ON CONFLICT (key) DO NOTHING'));
    expect(sql, contains("'\"salon\"'::jsonb"));
  });

  test('okuma tek RPC, misafire açık; ham okuyucu kapalı', () {
    expect(
      sql,
      contains(
        'GRANT EXECUTE ON FUNCTION public.okey_design_config() '
        'TO anon, authenticated;',
      ),
    );
    expect(
      sql,
      contains(
        'REVOKE ALL ON FUNCTION public.okey_design_setting(text) FROM PUBLIC;',
      ),
    );
    expect(service, contains(".rpc('okey_design_config')"));
  });

  test('RPC alan adları istemcinin çözümlediği adlarla aynı', () {
    for (final field in ["'design'", "'layout'", "'user_choice'"]) {
      expect(sql, contains(field));
    }
    final parsed = OkeyDesignConfig.fromJson({
      'design': 'saray',
      'layout': 'kompakt',
      'user_choice': false,
    });
    expect(parsed.designKey, 'saray');
    expect(parsed.layout, OkeyLobbyLayout.kompakt);
    expect(parsed.userChoice, isFalse);
  });

  test('sunucunun kabul ettiği düzenler istemcideki düzenlerle aynı', () {
    for (final l in OkeyLobbyLayout.values) {
      expect(sql, contains("'${l.name}'"), reason: l.name);
    }
    expect(sql, contains("'auto'"));
  });

  test('tasarım anahtarı biçimi sınırlı; tırnaklı değerler soyulur', () {
    expect(sql, contains(r"'^[a-z0-9_]{1,32}$'"));
    expect(sql, contains(r"""btrim(s.value #>> '{}', E'" \t\r\n')"""));
    expect(sql, contains('SET search_path = '));
  });

  test('istemci düz metin yazar (tırnaklı jsonb değil)', () {
    expect(service, contains("config.userChoice ? 'true' : 'false'"));
    // Yorumlar hariç: belge yorumu yanlış biçimi örnek olarak anar.
    final code = service
        .split('\n')
        .where((l) => !l.trimLeft().startsWith('//'))
        .join('\n');
    expect(code, isNot(contains("'\"true\"'")));
  });
}
