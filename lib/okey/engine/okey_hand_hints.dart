import 'okey_tile.dart';

/// ISTAKA İPUÇLARI — "hangi taşım başka taşlarımla bir per/grup/çift
/// yapabilir?" sorusunun HIZLI cevabı.
///
/// ## Neden ayrı bir motor (performans, 2026-09-08)
///
/// Bu cevap eskiden provider'ın içinde KABA KUVVETLE aranıyordu: rafın tüm
/// ikili ve üçlü kombinasyonları (22 taşta 231 + 1540 = ~1771 aday), her üçlü
/// için ayrıca serinin 6 dizilişi denenerek — on binden fazla doğrulama, her
/// adayda yeni liste ayırarak. Üstelik TAM OLARAK oyuncunun taş çektiği /
/// attığı karede, yani rafın değiştiği anda.
///
/// Kombinasyon taramasına gerek yok: bir taşın per yapıp yapamayacağı, rafın
/// renk/rakam DAĞILIMINDAN doğrudan okunur. Bu sınıf dağılımı tek geçişte
/// çıkarır, sonra her taş için sabit sayıda kontrol yapar. Sonuç kaba
/// kuvvetle BİREBİR aynıdır; eşdeğerlik testle sabitlenmiştir
/// (bkz. test/okey/okey_hand_hints_test.dart).
///
/// Kurallar RULES.md §2 ile aynı ve [OkeyMeldValidator] ile aynı kaynaktan:
///   * ÇİFT — aynı renk + aynı rakam; JOKER HER TAŞLA ÇİFT OLUR.
///   * GRUP — aynı rakam, FARKLI renkler, 3 taş.
///   * SERİ — aynı renk, ardışık 3 rakam; 13'ten sonra sarma YOK.
///   * SAHTE OKEY joker DEĞİLDİR: okey taşının kimliğiyle normal taş gibi
///     oynar (bu yüzden her yerde `resolved*` okunur).
abstract final class OkeyHandHints {
  /// En büyük taş numarası (RULES.md §1).
  static const int _maxNumber = 13;

  /// Bir seri/grubun taş sayısı (ipuçları için üçlüler aranır).
  static const int _meldSize = 3;

  /// [slots] içinde, başka taşlarla geçerli bir per/grup/çift oluşturabilen
  /// taşların SLOT indeksleri.
  ///
  /// [slots] doğrudan ıstaka yerleşimidir: null slotlar boşluktur, atlanır.
  static Set<int> meldableSlots(List<OkeyTile?> slots, OkeyTile okeyTile) {
    final result = <int>{};

    // ---- RAFIN DAĞILIMI: tek geçişte ------------------------------------
    final wilds = <int>[]; // joker (okey) taşlarının slotları
    final reals = <int>[]; // joker olmayan taşların slotları
    final realColor = <int, int>{}; // slot -> renk indeksi
    final realNumber = <int, int>{}; // slot -> rakam
    // (renk, rakam) -> o kimlikten kaç taş var — ÇİFT için
    final identityCount = <int, int>{};
    // rakam -> o rakamda görülen RENKLER — GRUP için
    final colorsOfNumber = List.generate(_maxNumber + 1, (_) => <int>{});
    // renk -> o renkte görülen RAKAMLAR — SERİ için
    final numbersOfColor = List.generate(
      OkeyColor.values.length,
      (_) => <int>{},
    );

    for (var i = 0; i < slots.length; i++) {
      final tile = slots[i];
      if (tile == null) continue;
      if (tile.isJokerFor(okeyTile)) {
        wilds.add(i);
        continue;
      }
      final c = tile.resolvedColor(okeyTile)!.index;
      final n = tile.resolvedNumber(okeyTile)!;
      reals.add(i);
      realColor[i] = c;
      realNumber[i] = n;
      identityCount.update(c * 16 + n, (v) => v + 1, ifAbsent: () => 1);
      colorsOfNumber[n].add(c);
      numbersOfColor[c].add(n);
    }

    final wildCount = wilds.length;
    final tileCount = wilds.length + reals.length;
    // Tek taşla hiçbir şey kurulamaz.
    if (tileCount < 2) return result;

    // ---- JOKER VARSA HEPSİ İŞARETLENİR -----------------------------------
    //
    // Joker HER taşla geçerli bir çift yapar (RULES.md §2), dolayısıyla rafta
    // bir okey duruyorsa istisnasız her taş "bir şeyin parçası olabilir".
    // Kaba kuvvet tarama da tam olarak bunu üretiyordu; ipucu bu durumda
    // bilgi vermez ama DAVRANIŞ DEĞİŞMEMELİ.
    if (wildCount > 0) {
      result.addAll(reals);
      result.addAll(wilds);
      return result;
    }

    // ---- ÇİFT (aynı renk + aynı rakam) -----------------------------------
    for (final i in reals) {
      if ((identityCount[realColor[i]! * 16 + realNumber[i]!] ?? 0) >= 2) {
        result.add(i);
      }
    }

    // ---- GRUP (aynı rakam, farklı renkler) -------------------------------
    for (final i in reals) {
      if (result.contains(i)) continue;
      // Kendi rengi dışında o rakamda kaç FARKLI renk var?
      if (colorsOfNumber[realNumber[i]!].length - 1 >= _meldSize - 1) {
        result.add(i);
      }
    }

    // ---- SERİ (aynı renk, ardışık) ---------------------------------------
    for (final i in reals) {
      if (result.contains(i)) continue;
      final present = numbersOfColor[realColor[i]!];
      final n = realNumber[i]!;
      // Bu taşı İÇEREN üç pencereden biri dolu mu?
      for (var start = n - 2; start <= n; start++) {
        if (start < 1 || start + _meldSize - 1 > _maxNumber) continue;
        var found = 0;
        for (var k = 0; k < _meldSize; k++) {
          if (present.contains(start + k)) found++;
        }
        if (found >= _meldSize) {
          result.add(i);
          break;
        }
      }
    }

    return result;
  }
}
