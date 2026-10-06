import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Okey senkron göçünün (Görev 1.6) YAPISAL kararları.
///
/// Davranış canlı veritabanında `supabase/tests/manual/okey_sync_fixes_test.sql`
/// ile kanıtlanır (26 kontrol). Bu test, geri alınması sayacı yeniden cihaz
/// saatine bağlayacak ya da izleyicilerin canlı maç satırını kilitlemesini
/// geri getirecek kararları sabitler.
void main() {
  const fileName = '20260927000003_okey_sync_fixes.sql';
  late String sql;

  String read(File f) => f.readAsStringSync().replaceAll('\r\n', '\n');

  String stripComments(String s) => s
      .split('\n')
      .where((l) => !l.trimLeft().startsWith('--'))
      .join('\n');

  String fn(String name) => RegExp(
    'CREATE OR REPLACE FUNCTION public\\.$name\\(.*?\\\$function\\\$;',
    dotAll: true,
  ).firstMatch(sql)!.group(0)!;

  setUpAll(() {
    sql = read(File('supabase/migrations/$fileName'));
  });

  test('tek işlemde çalışır ve PostgREST şemasını yeniler', () {
    final code = stripComments(sql);
    expect(RegExp(r'^BEGIN;', multiLine: true).hasMatch(code), isTrue);
    expect(RegExp(r'^COMMIT;', multiLine: true).hasMatch(code), isTrue);
    expect(code, contains("NOTIFY pgrst, 'reload schema';"));
  });

  test('masa okuması eski anahtarların HEPSİNİ ve sunucu saatini döndürür', () {
    final snapshot = fn('okey_match_snapshot');
    for (final key in [
      "'match', v_match",
      "'hand', v_hand",
      "'melds', v_melds",
      "'counts', v_counts",
      "'moves', v_moves",
      "'barajs', v_barajs",
      "'required_opening', v_required",
      "'can_undo_side_draw', public.okey_can_undo_side_draw(p_match_id)",
      "'server_now', now()",
    ]) {
      expect(snapshot, contains(key), reason: 'eksik: $key');
    }
    // Yetki modeli değişmedi: RLS'e tabi (INVOKER), boş search_path.
    expect(snapshot, isNot(contains('SECURITY DEFINER')));
    expect(snapshot, contains("SET search_path TO ''"));
  });

  test('otomatik oynatma: koltuk kontrolü satır kilidinden ÖNCE', () {
    final auto = fn('okey_auto_advance');
    expect(auto, contains('SECURITY DEFINER'));
    expect(auto, contains("SET search_path TO ''"));
    final seated = auto.indexOf("'APP:not_seated'");
    final lock = auto.indexOf('FOR UPDATE');
    expect(seated, greaterThan(0));
    expect(lock, greaterThan(seated), reason: 'izleyici kilit almadan reddedilmeli');
    // Süreyi hâlâ SUNUCU doğrular.
    expect(auto, contains('now() < v_match.turn_deadline'));
    expect(auto, contains('PERFORM public.okey_auto_advance_body(p_match_id);'));
  });

  test('yetkilere dokunmaz (CREATE OR REPLACE mevcut GRANT\'ları korur)', () {
    final code = stripComments(sql);
    expect(code, isNot(contains('GRANT ')));
    expect(code, isNot(contains('REVOKE ')));
  });
}
