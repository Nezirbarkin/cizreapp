/// 101 Okey taş renkleri. Sahte okey (false joker) taşının rengi yoktur,
/// bu yüzden [OkeyTile.color] o taş için null olur.
enum OkeyColor { red, yellow, black, blue }

/// Tek bir Okey taşı. Sahte okey taşı hariç her taşın bir [color] ve
/// [number] (1-13) değeri vardır. Bir taşın "joker" (herhangi bir taşın
/// yerine geçebilme) olup olmadığı, o elin gösterge taşına bağlı olduğu
/// için burada saklanmaz — bkz. [isJokerFor].
class OkeyTile {
  final OkeyColor? color;
  final int? number;
  final bool isFalseJoker;

  const OkeyTile.numbered(OkeyColor this.color, int this.number)
    : isFalseJoker = false,
      assert(number >= 1 && number <= 13);

  const OkeyTile.falseJoker()
    : color = null,
      number = null,
      isFalseJoker = true;

  /// Bu taş, göstergeden türeyen [okeyTile] için joker (wildcard) olarak mı
  /// kullanılabilir? Sahte okey taşı her zaman joker; gösterge-türevi okey
  /// taşı ise yalnızca aynı renk+numaraya sahip iki kopyası için jokerdir.
  /// Bu taş SERBEST JOKER mi? (her taşın yerine geçebilir)
  ///
  /// YALNIZCA okey taşının 2 kopyası jokerdir. SAHTE OKEY JOKER DEĞİLDİR —
  /// okey taşının sayı değeriyle, normal bir taş gibi oynar (RULES.md §1).
  /// Önce sahte okey de joker sayılıyordu ve istenen her yere konabiliyordu.
  bool isJokerFor(OkeyTile okeyTile) {
    if (isFalseJoker) return false;
    return color == okeyTile.color && number == okeyTile.number;
  }

  /// Bu taş, kural denetiminde HANGİ TAŞ sayılır?
  ///
  /// Sahte okey, okey taşının kimliğini (renk + sayı) alır. Diğer taşlar
  /// kendileri sayılır.
  ///
  /// DİKKAT: Bu, [isJokerFor] ile BİRLEŞTİRİLEMEZ. Sahte okeyi doğrudan okey
  /// taşına çevirseydik yine joker sayılırdı ve hiçbir şey değişmezdi
  /// (döngüsel tanım). Bu yüzden "joker mi?" ve "hangi taş sayılır?"
  /// AYRI sorulardır.
  OkeyColor? resolvedColor(OkeyTile okeyTile) =>
      isFalseJoker ? okeyTile.color : color;

  int? resolvedNumber(OkeyTile okeyTile) =>
      isFalseJoker ? okeyTile.number : number;

  Map<String, dynamic> toMap() => {
    'color': color?.name,
    'number': number,
    'isFalseJoker': isFalseJoker,
  };

  factory OkeyTile.fromMap(Map<String, dynamic> map) {
    if (map['isFalseJoker'] == true) return const OkeyTile.falseJoker();
    final colorName = map['color'] as String;
    final color = OkeyColor.values.firstWhere((c) => c.name == colorName);
    return OkeyTile.numbered(color, map['number'] as int);
  }

  @override
  bool operator ==(Object other) =>
      other is OkeyTile &&
      other.color == color &&
      other.number == number &&
      other.isFalseJoker == isFalseJoker;

  @override
  int get hashCode => Object.hash(color, number, isFalseJoker);

  @override
  String toString() => isFalseJoker ? 'FalseJoker' : '${number}_${color!.name}';
}
