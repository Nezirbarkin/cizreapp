import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Görev 3.10 — şehiriçi durak toplu silme + mantık düzeltmeleri. Davranış
/// canlıda `supabase/tests/manual/sehirici_stop_bulk_delete_test.sql`
/// (7 kontrol) ile kanıtlanır; burada göçün yapısal kararları.
void main() {
  String read(String path) => File(path).readAsStringSync().replaceAll('\r\n', '\n');
  String stripComments(String s) => s.split('\n').where((l) => !l.trimLeft().startsWith('--')).join('\n');

  late String sql;
  setUpAll(() {
    sql = stripComments(read('supabase/migrations/20260928000012_sehirici_stop_bulk_delete.sql'));
  });

  String fn(String name) => RegExp(
    'CREATE OR REPLACE FUNCTION ${RegExp.escape(name)}\\(.*?\\\$fn\\\$;',
    dotAll: true,
  ).firstMatch(sql)!.group(0)!;

  test('toplu silme: yönetici, sınır, etkilenen hatlar yeniden numaralanır', () {
    final bulk = fn('public.admin_delete_sehirici_stops');
    expect(bulk, contains('public.auth_sehirici_is_admin()'));
    expect(bulk, contains('cardinality(p_ids) > 500'));
    expect(bulk, contains('PERFORM private.sehirici_renumber_line(v_line);'));
    expect(bulk, contains("'affected_lines'"));
    expect(sql, contains('REVOKE ALL ON FUNCTION public.admin_delete_sehirici_stops(uuid[]) FROM PUBLIC, anon;'));
    expect(fn('public.admin_delete_sehirici_stop'), contains('public.admin_delete_sehirici_stops(ARRAY[p_id])'),
        reason: 'tek silme de aynı yoldan');
  });

  test('yeniden numaralama çakışmasız; 2\'den az durakta rota temizlenir', () {
    final renumber = fn('private.sehirici_renumber_line');
    expect(renumber, contains('stop_order = stop_order + 1000000'));
    expect(renumber, contains('row_number() OVER (ORDER BY stop_order, created_at, id) - 1'));
    expect(renumber, contains('IF v_count < 2 THEN'));
  });

  test('mantık düzeltmeleri: pasif durak kullanıcıya gitmez, şehir koruması, sıra sunucuda', () {
    expect(fn('public.get_sehirici_lines_with_stops'), contains('AND s.is_active'));
    final upsert = fn('public.admin_upsert_sehirici_stop');
    expect(upsert, contains("HINT = 'SEHIRICI_STOP_CITY_IN_USE'"));
    expect(upsert, contains("HINT = 'SEHIRICI_STOP_NAME_REQUIRED'"));
    final setStops = fn('public.admin_set_sehirici_line_stops');
    expect(setStops, contains('WITH ORDINALITY AS e(elem, ord)'));
    expect(setStops, contains("row_number() OVER (ORDER BY (e.elem ->> 'stop_order')::integer NULLS LAST, e.ord) - 1"));
  });

  test('istemci: servis tek RPC, Duraklar sekmesinde seçim modu', () {
    final service = read('lib/sehirici/services/sehirici_line_service.dart');
    expect(service, contains("'admin_delete_sehirici_stops'"));
    final tab = read('lib/sehirici/admin/sehirici_admin_stops_tab.dart');
    expect(tab, contains('c.lineService.deleteStopsOrThrow(ids)'));
    expect(tab, contains("'Tümünü seç'"));
  });

  test('canlı doğrulama betiği repoda ve her grubu kapsar', () {
    final live = read('supabase/tests/manual/sehirici_stop_bulk_delete_test.sql');
    for (var i = 1; i <= 7; i++) {
      expect(live, contains('[$i]'), reason: 'canlı testte [$i] yok');
    }
    expect(live, contains('TESTS_PASSED'));
  });
}
