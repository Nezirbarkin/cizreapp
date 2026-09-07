/// Masadaki OTURMA DÜZENİ — hangi koltuğun ekranda nereye çizileceği.
///
/// Saf hesap: ne Flutter ne Supabase bilir, doğrudan test edilebilir.
///
/// NEDEN AYRI: Bu eşleme daha önce ekranın build() gövdesinde satır içindeydi
/// ve TERSTİ — ıskartasını aldığım oyuncu ekranın SAĞINA çiziliyordu. Sonuç:
/// sıra görsel olarak ters yönde dönüyormuş gibi görünüyordu. Hesap burada
/// saf durduğu için yön artık testle sabitlenmiştir.
///
/// KURAL (RULES.md §4): Sıra saat yönünün TERSİNE ilerler; koltuk numarası
/// birer artar (0 → 1 → 2 → 3 → 0). Masaya oturmuş bir oyuncu için bu şu
/// demektir: **soldaki oyuncudan taş alınır, sağdaki oyuncuya atılır.**
/// Dolayısıyla benden ÖNCEKİ oyuncu (sıra bana ondan gelir) SOLDA,
/// benden SONRAKİ oyuncu (sıra ona benden gider) SAĞDA oturur.
class OkeySeating {
  /// Ekranın altındaki oyuncu — bendeki koltuk.
  final int mySeat;

  const OkeySeating(this.mySeat);

  static const int seatCount = 4;

  /// SOL: sırada benden ÖNCEKİ oyuncu. Onun attığı taşı ben alırım.
  int get leftSeat => (mySeat + seatCount - 1) % seatCount;

  /// KARŞI: masanın öbür ucu (eşli modda eşim).
  int get acrossSeat => (mySeat + 2) % seatCount;

  /// SAĞ: sırada benden SONRAKİ oyuncu. Benim attığım taşı o alır.
  int get rightSeat => (mySeat + 1) % seatCount;

  /// Iskartasından taş çekebileceğim koltuk — her zaman soldaki.
  int get drawSeat => leftSeat;

  /// Sıra bu koltuktan sonra kime geçer.
  int nextSeatAfter(int seat) => (seat + 1) % seatCount;
}
