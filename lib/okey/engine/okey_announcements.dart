/// SESLİ ANONSLARIN KARARLARI — saf hesap.
///
/// Ne Flutter ne Supabase bilir: "şimdi konuşulmalı mı" sorusunun cevabı
/// burada durur, doğrudan test edilir. Konuşmanın kendisi (metin, kuyruk,
/// TTS) `OkeyGameProvider`'da kalır.
///
/// ## Neden ayrı (kullanıcı isteği, 2026-09-21)
///
/// "Son üç taş" anonsu eskiden provider'ın içinde satır içi kararlaştırılıyordu
/// ve YANLIŞ ANDA çalıyordu: bir oyuncunun ıstakası turun ORTASINDA — taş
/// çekip perlerini indirdikten sonra, henüz atmadan — 3 taşa düşebilir. O
/// anda anons "Ahmet, son üç taş" diyordu, oysa Ahmet atışını yapınca
/// ıstakasında 2 taş kalıyordu. Karar artık yalnızca ATIŞTAN SONRAKİ duruma
/// bakar; bu da saf bir fonksiyon olarak sabitlenir.
abstract final class OkeyAnnouncements {
  /// "Son üç taş" anonsunun eşiği: atıştan sonra ıstakada TAM bu kadar taş.
  static const int lastTilesCount = 3;

  /// Bu tazelemede "son üç taş" anonsu yapılacak koltuklar (koltuk sırasıyla).
  ///
  /// [counts] koltuk → ıstakadaki taş sayısı, [turnSeat] şu an sırası olan
  /// koltuk, [announced] bu elde zaten duyurulmuş koltuklar — bu fonksiyon
  /// onu GÜNCELLER (yeni duyurulanlar eklenir, yeniden silahlananlar çıkar).
  ///
  /// ## Ne zaman duyurulur
  ///
  /// Bir koltuk için ancak ikisi BİRLİKTE doğruysa:
  ///  * ıstakasında TAM [lastTilesCount] taş var ve
  ///  * sırası ONDA DEĞİL.
  ///
  /// İkincisi "taş attıktan sonra" demektir: bir koltuğun ıstakası yalnızca
  /// KENDİ turunda değişir (çek +1, per/işle −n, at −1) ve sıra ondan ancak
  /// atışıyla çıkar. Yani sırası kendinde değilken okunan sayı turun SON
  /// halidir; sırası kendindeyken okunan sayı ise ara durumdur (çekilmiş ama
  /// atılmamış taş dahil) ve duyurulmamalıdır.
  ///
  /// ## Tam 3 (3 veya altı DEĞİL)
  ///
  /// Anonsun söylediği şey "son üç taş"tır. Bir turda 5'ten 1'e inen oyuncu
  /// için "üç taş" demek yanlış bilgi olurdu; o oyuncunun bir sonraki atışı
  /// zaten eli bitirir.
  ///
  /// ## Yeniden silahlanma
  ///
  /// Sayı 3'ün ÜSTÜNE çıkarsa (taş çekti) işaret kalkar: aynı oyuncu sonra
  /// yeniden 3'e inerse yeniden duyurulur. Sayı 3'te ya da altında kaldıkça
  /// aynı koltuk için ikinci kez konuşulmaz.
  static List<int> lastThreeTiles({
    required Map<int, int> counts,
    required int turnSeat,
    required Set<int> announced,
  }) {
    final result = <int>[];
    final seats = counts.keys.toList()..sort();
    for (final seatNo in seats) {
      final count = counts[seatNo]!;
      if (count > lastTilesCount) {
        announced.remove(seatNo);
        continue;
      }
      if (count != lastTilesCount) continue; // 0-2 taş: "üç taş" denmez
      if (seatNo == turnSeat) continue; // turun ortası: atış henüz olmadı
      if (announced.add(seatNo)) result.add(seatNo);
    }
    return result;
  }

  /// Bir elin İLK görüşünde "zaten duyurulmuş" sayılacak koltuklar.
  ///
  /// Elin ortasında masaya oturan (ya da yeniden bağlanan) oyuncu, o ana
  /// kadar olmuş bir "son üç taş"ı geriden dinlemez.
  static Set<int> alreadyLow(Map<int, int> counts) => {
    for (final e in counts.entries)
      if (e.value <= lastTilesCount) e.key,
  };
}
