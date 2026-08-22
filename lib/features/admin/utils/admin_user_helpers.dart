/// Admin "Kullanıcılar" sekmesi kartı için saf (UI'dan bağımsız) yardımcılar.
///
/// Bunlar ayrı bir dosyaya, test edilebilir bir sınıfa kondu çünkü kart
/// widget'ı `admin_dashboard_screen.dart` kütüphanesinin `part`'ı olan
/// `_part_users.dart` içinde özel (private) bir metot olarak gömülü — doğrudan
/// test edilemiyor. Saf mantık burada, birim testiyle kapsanır.
///
/// İlişkili: [[admin-user-card]] görselleştirmesi `_part_users.dart` içinde.
class AdminUserHelpers {
  AdminUserHelpers._();

  /// Bir avatar URL'sinin gösterilebilir http(s) bağlantısı olup olmadığı.
  ///
  /// Supabase Storage public URL'leri tam `https://...` biçimindedir. Göreli
  /// yol veya boş değer `false` döner; böylece kart baş harfe düşebilir.
  static bool isValidAvatarUrl(String? url) {
    if (url == null) return false;
    final s = url.trim();
    if (s.isEmpty) return false;
    return s.startsWith('http://') || s.startsWith('https://');
  }

  /// Sayaçları kompakt gösterir (TR): 999 -> "999", 1500 -> "1.5B",
  /// 1_200_000 -> "1.2Mn". "B" = bin (thousand), "Mn" = milyon (million).
  static String formatStatCount(num value) {
    if (value < 1000) return value.toInt().toString();

    if (value < 1000000) {
      return '${_oneDecimal(value / 1000)}B';
    }
    return '${_oneDecimal(value / 1000000)}Mn';
  }

  /// `thousands`/`millions` değerini bir ondalık basamakla döndürür; tam sayı
  /// ise ".0" göstermez (ör. 2.0 -> "2", 1.5 -> "1.5").
  static String _oneDecimal(num v) {
    final rounded = (v * 10).round() / 10;
    if (rounded == rounded.roundToDouble()) {
      return rounded.toInt().toString();
    }
    return rounded.toStringAsFixed(1);
  }

  /// `last_seen` için göreceli etiket üretir. `now` dışarıdan alındığı için
  /// test deterministik olur. Null/geçersiz -> "-". Gelecek tarih (saat
  /// sapması) -> "az önce".
  static String formatLastSeen(DateTime? lastSeen, {required DateTime now}) {
    if (lastSeen == null) return '-';
    final diff = now.difference(lastSeen);
    if (diff.isNegative) return 'az önce';
    if (diff.inMinutes < 1) return 'az önce';
    if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
    if (diff.inHours < 24) return '${diff.inHours} sa önce';
    if (diff.inDays < 30) return '${diff.inDays} gün önce';

    final d = lastSeen.day.toString().padLeft(2, '0');
    final m = lastSeen.month.toString().padLeft(2, '0');
    return '$d.$m.${lastSeen.year}';
  }

  /// Kullanıcının son N gün içinde kayıt olup olmadığı ("Yeni" rozeti için).
  static bool isNewMember(DateTime? createdAt, {required DateTime now, int days = 7}) {
    if (createdAt == null) return false;
    final diff = now.difference(createdAt);
    if (diff.isNegative) return true;
    return diff.inDays < days;
  }

  /// Baş harf üretir (avatar fallback). username tercih edilir, yoksa
  /// full_name. Boşsa "?".
  static String initialOf(String? username, String? fullName) {
    final source = (username?.trim().isNotEmpty == true
        ? username
        : fullName) ??
        '';
    if (source.trim().isEmpty) return '?';
    return source.trim().substring(0, 1).toUpperCase();
  }
}
