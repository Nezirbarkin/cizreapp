/// Kullanıcı arama metnini PostgREST filtrelerine güvenle gömmek için
/// yardımcılar.
///
/// SORUN: `.or('name.ilike.%$query%,description.ilike.%$query%')` çağrılarında
/// kullanıcı metni filtre dizesine ham olarak yapıştırılıyordu. PostgREST'te
/// virgül koşulları, parantez ise grupları ayırdığı için "kırmızı, mavi" gibi
/// gayet normal bir arama filtreyi bozup 400 hatasına düşüyordu. Ayrıca `%`
/// ve `_` LIKE joker karakterleri olduğundan, `%` yazan bir kullanıcı tüm
/// katalogla eşleşiyordu.
///
/// ÇÖZÜM: Önce LIKE jokerleri kaçırılır, sonra değer PostgREST'in çift tırnaklı
/// değer sözdizimiyle sarmalanır. Sıra önemlidir: PostgREST önce tırnağı
/// çözer, ortaya çıkan metni Postgres LIKE kalıbı olarak yorumlar.
library;

/// LIKE kalıbındaki özel karakterleri kaçırır.
///
/// Postgres'te LIKE için varsayılan kaçış karakteri `\` olduğundan
/// `\%` literal yüzde, `\_` literal alt çizgi anlamına gelir.
String escapeLikeWildcards(String raw) {
  return raw
      .replaceAll(r'\', r'\\')
      .replaceAll('%', r'\%')
      .replaceAll('_', r'\_');
}

/// Bir PostgREST filtre değerini çift tırnak içine alır.
///
/// Tırnak içinde `\` ve `"` kaçırılmalıdır; virgül, parantez ve nokta
/// güvenle yer alabilir.
String quotePostgrestValue(String value) {
  final escaped = value.replaceAll(r'\', r'\\').replaceAll('"', r'\"');
  return '"$escaped"';
}

/// `column.ilike.<değer>` filtrelerinde kullanılmak üzere, kullanıcı metnini
/// her iki ucu joker olan güvenli bir kalıba çevirir.
///
/// Örnek: `kırmızı, mavi` -> `"%kırmızı, mavi%"`
String ilikeContainsPattern(String rawQuery) {
  return quotePostgrestValue('%${escapeLikeWildcards(rawQuery.trim())}%');
}

/// Birden çok sütunda "içerir" araması yapan bir PostgREST `or()` ifadesi kurar.
///
/// Örnek:
/// ```dart
/// .or(buildIlikeOrFilter(['name', 'description'], query))
/// ```
String buildIlikeOrFilter(List<String> columns, String rawQuery) {
  assert(columns.isNotEmpty, 'En az bir sütun gerekli');
  final pattern = ilikeContainsPattern(rawQuery);
  return columns.map((c) => '$c.ilike.$pattern').join(',');
}
