import 'dart:math' as math;

/// Durak adlarının metin kuralları: Türkçe sadeleştirme, sokak adının
/// kısaltılması ("Yafes Caddesi" → "Yafes Cad."), aynı sokaktaki durakları
/// kaldığı yerden numaralama ("Yafes Cad. 1", "Yafes Cad. 2" …) ve doğal
/// sıralama ("… 2" < "… 10").

/// Sokağı bulunamayan durakların ad tabanı ("Durak 1", "Durak 2" …).
const String kSehiriciFallbackStopBase = 'Durak';

/// Türkçe harfleri sadeleştirip küçültür ("Çarşı" ile "carsi" eşleşsin).
String sehiriciFold(String input) {
  const map = {
    'İ': 'i', 'I': 'i', 'ı': 'i', 'Ş': 's', 'ş': 's', 'Ğ': 'g', 'ğ': 'g', //
    'Ü': 'u', 'ü': 'u', 'Ö': 'o', 'ö': 'o', 'Ç': 'c', 'ç': 'c',
  };
  final b = StringBuffer();
  for (final r in input.runes) {
    final ch = String.fromCharCode(r);
    b.write(map[ch] ?? ch.toLowerCase());
  }
  return b.toString();
}

/// Numara karşılaştırması için ad anahtarı: sadeleştirilmiş, noktasız, tek
/// boşluklu. "Yafes Cad. 3", "yafes cad 3" ve "YAFES CAD.3" aynı tabana düşer.
String _nameKey(String input) => sehiriciFold(input)
    .replaceAll('.', ' ')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Yol türü son ekleri → kısa biçim. Anahtarlar [_nameKey] biçimindedir.
const Map<String, String> _kRoadSuffixes = {
  'caddesi': 'Cad.',
  'cadde': 'Cad.',
  'cad': 'Cad.',
  'cd': 'Cad.',
  'sokak': 'Sk.',
  'sokagi': 'Sk.',
  'sok': 'Sk.',
  'sk': 'Sk.',
  'bulvari': 'Blv.',
  'bulvar': 'Blv.',
  'bulv': 'Blv.',
  'blv': 'Blv.',
  'mahallesi': 'Mah.',
  'mahalle': 'Mah.',
  'mah': 'Mah.',
  'meydani': 'Mey.',
};

/// Sokak adını durak adına uygun kısa biçime çevirir:
/// "Yafes Caddesi" → "Yafes Cad.", "Barçın Sokak" → "Barçın Sk.",
/// "Mem U Zin Bulvarı" → "Mem U Zin Blv.". Tanınmayan son ek ("Yolu")
/// olduğu gibi kalır. Boş girdi boş döner.
String sehiriciAbbreviateStreet(String street) {
  final words = street.trim().split(RegExp(r'\s+'))
    ..removeWhere((w) => w.isEmpty);
  if (words.isEmpty) return '';
  final short = _kRoadSuffixes[_nameKey(words.last)];
  if (short != null && words.length > 1) {
    words[words.length - 1] = short;
  }
  return words.join(' ');
}

/// Mahalle adını ad tabanına çevirir: "Nur" → "Nur Mah.",
/// "Ali Bey Mahallesi" → "Ali Bey Mah.".
String sehiriciNeighborhoodBase(String neighborhood) {
  final trimmed = neighborhood.trim();
  if (trimmed.isEmpty) return '';
  final abbreviated = sehiriciAbbreviateStreet(trimmed);
  return abbreviated.endsWith('Mah.') ? abbreviated : '$abbreviated Mah.';
}

/// [base] tabanındaki bir sonraki numaralı ad: [taken] içinde
/// "Yafes Cad. 1" ve "Yafes Cad. 4" varsa "Yafes Cad. 5". Numarasız
/// "Yafes Cad." 1 sayılır. Boşluklar kapanmaz — numaralar kaldığı yerden
/// devam eder.
String sehiriciNextNumberedName(String base, Iterable<String> taken) {
  final cleanBase = base.trim().replaceAll(RegExp(r'\s+'), ' ');
  final key = _nameKey(cleanBase);
  final pattern = RegExp('^${RegExp.escape(key)} ?(\\d{1,6})\$');
  var max = 0;
  for (final name in taken) {
    final k = _nameKey(name);
    if (k == key) {
      max = math.max(max, 1);
      continue;
    }
    final m = pattern.firstMatch(k);
    if (m != null) max = math.max(max, int.parse(m.group(1)!));
  }
  return '$cleanBase ${max + 1}';
}

/// Doğal sıralama: metin parçaları Türkçe duyarsız, sayılar sayı olarak
/// karşılaştırılır ("Yafes Cad. 2" < "Yafes Cad. 10").
int sehiriciNaturalCompare(String a, String b) {
  final re = RegExp(r'\d+|\D+');
  final pa = re.allMatches(sehiriciFold(a)).map((m) => m.group(0)!).toList();
  final pb = re.allMatches(sehiriciFold(b)).map((m) => m.group(0)!).toList();
  for (var i = 0; i < math.min(pa.length, pb.length); i++) {
    final x = pa[i];
    final y = pb[i];
    final nx = int.tryParse(x);
    final ny = int.tryParse(y);
    final c = (nx != null && ny != null) ? nx.compareTo(ny) : x.compareTo(y);
    if (c != 0) return c;
  }
  return pa.length.compareTo(pb.length);
}
