import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:cizreapp/okey/admin/okey_admin_service.dart';

/// 101 Okey — BOTLU MASADA KAZANAN ÇİP KAZANIR.
///
/// Bildirilen hata: "kazanan kişiye sadece masa ücreti iade ediliyor, çip
/// kazanmıyor". Sebep, potun YALNIZCA insan koltuklarından toplanmasıydı;
/// üç botla oynanan masada kaybeden insan olmadığı için pot sıfırdı.
///
/// Bu dosya sözleşmeyi SQL METNİNDEN doğrular: göç mantığı canlı veritabanında
/// yaşıyor, Dart tarafında çalıştırılamıyor. Metin testi zayıf bir güvence
/// gibi durur ama korumak istediğimiz şey tam olarak metindir — biri
/// `okey_internal_award_match`'i bir daha taşırken (bu fonksiyon 20260831'den
/// beri altı kez taşındı) bot koltuklarını sessizce düşürmesin.
void main() {
  const path =
      'supabase/migrations/20260908190001_okey_bot_seats_ante_into_pot.sql';

  late String sql;

  setUpAll(() => sql = File(path).readAsStringSync());

  group('okey_internal_award_match', () {
    test('kaybeden bot koltukları pota katılır', () {
      expect(sql, contains('v_bot_pot := v_bot_ante'));
      expect(sql, contains('+ v_bot_pot'));
    });

    test('bot payı BOŞ koltuktan değil, gerçek bot koltuğundan sayılır', () {
      // is_bot = false AND user_id IS NULL satırları oyuncu bekleyen boş
      // sandalyelerdir; oynamayan sandalye pota para koymamalı.
      expect(sql, contains('AND rp.is_bot'));
      expect(sql, contains('AND rp.user_id IS NULL'));
      expect(sql, contains('AND NOT (rp.seat_no = ANY(v_winner_seats))'));
    });

    test('kazanan botsa kasa hiç çip basmaz', () {
      // Bot payı YALNIZCA insan kazanan varken hesaplanır; aksi halde kasa,
      // hemen ardından 'unclaimed_pot' olarak geri alacağı bir tutarı basardı.
      expect(sql, contains('IF v_winner_human_count > 0 THEN'));
    });

    test('kasanın fonladığı tutar deftere EKSİ yazılır', () {
      expect(sql, contains("VALUES ('bot_stake', -v_bot_pot"));
      expect(sql, contains('IF v_bot_pot > 0 THEN'));
    });

    test('komisyon bot payından da kesilir (tek enflasyon freni)', () {
      // v_loser_pot bot payını İÇERİR ve komisyon onun üstünden hesaplanır.
      expect(sql, contains('v_commission := (v_loser_pot'));
    });

    test('masa puanı iadesi korunur', () {
      // 20260905000004 kuralı: kazanandan masa ücreti alınmaz.
      expect(sql, contains("'stake_refund'"));
    });
  });

  group('şema', () {
    test('bot payı yüzdesi ayar olarak eklenir ve 0-100 ile sınırlanır', () {
      expect(
        sql,
        contains('ADD COLUMN IF NOT EXISTS bot_stake_percent int NOT NULL '
            'DEFAULT 100'),
      );
      expect(
        sql,
        contains('CHECK (bot_stake_percent >= 0 AND bot_stake_percent <= 100)'),
      );
    });

    test('kasa defteri artık EKSİ tutar kabul eder', () {
      expect(sql, contains('CHECK (amount <> 0)'));
      expect(sql, isNot(contains('CHECK (amount > 0)')));
    });

    test("'bot_stake' geçerli bir kasa kalemidir", () {
      expect(
        sql,
        contains("CHECK (source IN ('room_fee', 'commission', "
            "'unclaimed_pot', 'gift', 'bot_stake'))"),
      );
    });
  });

  group('admin', () {
    test('bot payı okunup yazılabilir', () {
      expect(sql, contains('okey_admin_get_bot_stake_percent'));
      expect(sql, contains('okey_admin_set_bot_stake_percent'));
      expect(sql, contains("RAISE EXCEPTION 'APP:admin_only'"));
      expect(
        sql,
        contains('GRANT EXECUTE ON FUNCTION '
            'public.okey_admin_set_bot_stake_percent(int)'),
      );
    });

    test('rapor basılan çipi ayrı kalem olarak verir', () {
      expect(sql, contains('bot_stake_total bigint'));
      expect(
        sql,
        contains("SELECT -sum(amount) FROM public.okey_house_revenue "
            "WHERE source = 'bot_stake'"),
      );
    });
  });

  group('OkeyRevenueSummary', () {
    test('bot_stake_total ARTI işaretle okunur', () {
      final r = OkeyRevenueSummary.fromMap(const {
        'total_revenue': 400,
        'room_fee_total': 1000,
        'commission_total': 200,
        'today_revenue': 50,
        'total_points_in_circulation': 90000,
        'bot_stake_total': 800,
      });
      expect(r.botStakes, 800);
      // total ZATEN nettir: 1000 + 200 − 800.
      expect(r.total, 400);
    });

    test('alan yoksa sıfır — eski sunucuya karşı kart boş değil sıfır gösterir',
        () {
      final r = OkeyRevenueSummary.fromMap(const {'total_revenue': 10});
      expect(r.botStakes, 0);
    });
  });
}
