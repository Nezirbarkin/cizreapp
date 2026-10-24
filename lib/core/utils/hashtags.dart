/// `#etiket` ayrıştırma. Kurallar sunucudaki `public.social_fold_tr` ve
/// `posts_by_hashtag` / `trending_hashtags` ile AYNIDIR
/// (20261024000003_comment_likes_and_hashtags):
///   * etiket: harf (Türkçe dahil), rakam, `_`; 2–40 karakter
///   * önünde harf/rakam/`_` ya da `/` olmamalı (URL'deki `#bolum` sayılmaz)
///   * karşılaştırma Türkçe katlamayla: I, İ, ı → i; sonra küçük harf
library;

const String _tagChars = r'0-9A-Za-zÇĞİÖŞÜçğıöşü_';

/// Metindeki etiketleri bulur: grup 1 = `#` hariç etiket.
final RegExp hashtagPattern = RegExp(
  '(?<![$_tagChars/])#([$_tagChars]{2,40})(?![$_tagChars])',
);

/// "IĞDIR" → "iğdir", "İzmir" → "izmir" (sunucuyla aynı katlama).
String foldHashtag(String tag) {
  final t = tag.trim().replaceFirst(RegExp(r'^#+'), '');
  return t.replaceAll(RegExp('[Iİı]'), 'i').toLowerCase();
}

/// Etiket geçerli mi (katlanmış hâliyle 2–40 izinli karakter).
bool isValidHashtag(String tag) =>
    RegExp(r'^[0-9a-zçğıöşü_]{2,40}$').hasMatch(foldHashtag(tag));

/// Metindeki etiketler (katlanmış, tekrar yok, ilk görülme sırasıyla).
List<String> extractHashtags(String? text) {
  if (text == null || text.isEmpty) return const [];
  final seen = <String>{};
  final out = <String>[];
  for (final m in hashtagPattern.allMatches(text)) {
    final tag = foldHashtag(m.group(1)!);
    if (seen.add(tag)) out.add(tag);
  }
  return out;
}
