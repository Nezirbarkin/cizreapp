/// Masadaki sürükleme işlemlerinin taşıdığı veri.
///
/// Tek bir tip kullanılır ki her bırakma hedefi (ıstaka slotu, kendi ıskarta
/// kutusu) tüm sürükleme kaynaklarını tanıyabilsin:
///   - [OkeyDragPayload.rack]     : ıstakadaki bir slottan sürükleme
///   - [OkeyDragPayload.deck]     : desteden taş çekme
///   - [OkeyDragPayload.discard]  : soldaki oyuncunun ıskartasından taş alma
enum OkeyDragSource { rack, deck, discard }

class OkeyDragPayload {
  final OkeyDragSource source;

  /// Yalnızca [OkeyDragSource.rack] için: kaynak slot indeksi.
  final int slotIndex;

  const OkeyDragPayload.rack(this.slotIndex) : source = OkeyDragSource.rack;

  const OkeyDragPayload.deck() : source = OkeyDragSource.deck, slotIndex = -1;

  const OkeyDragPayload.discard()
    : source = OkeyDragSource.discard,
      slotIndex = -1;

  bool get isFromRack => source == OkeyDragSource.rack;
  bool get isDraw =>
      source == OkeyDragSource.deck || source == OkeyDragSource.discard;
}
