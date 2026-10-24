import 'package:shared_preferences/shared_preferences.dart';

/// Arama ekranının son aramaları (cihazda, kullanıcı başına; en yeni önce).
///
/// Her tuş vuruşunda değil, arama gönderildiğinde ya da bir sonuca
/// dokunulduğunda kaydedilir.
class RecentSearchesStore {
  RecentSearchesStore({this.maxItems = 10});

  final int maxItems;

  static String _key(String? userId) => 'recent_searches_${userId ?? 'guest'}';

  Future<List<String>> load(String? userId) async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getStringList(_key(userId)) ?? const [];
    } catch (_) {
      return const [];
    }
  }

  /// Sorguyu en başa ekler (büyük/küçük harf farkı aynı arama sayılır).
  Future<List<String>> add(String? userId, String query) async {
    final q = query.trim();
    if (q.length < 2) return load(userId);
    final p = await SharedPreferences.getInstance();
    final list = [
      q,
      ...(p.getStringList(_key(userId)) ?? const <String>[])
          .where((e) => e.toLowerCase() != q.toLowerCase()),
    ];
    final trimmed = list.length > maxItems ? list.sublist(0, maxItems) : list;
    await p.setStringList(_key(userId), trimmed);
    return trimmed;
  }

  Future<List<String>> remove(String? userId, String query) async {
    final p = await SharedPreferences.getInstance();
    final list = (p.getStringList(_key(userId)) ?? const <String>[])
        .where((e) => e != query)
        .toList();
    await p.setStringList(_key(userId), list);
    return list;
  }

  Future<void> clear(String? userId) async {
    final p = await SharedPreferences.getInstance();
    await p.remove(_key(userId));
  }
}
