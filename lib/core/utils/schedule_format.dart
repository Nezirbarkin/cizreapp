/// Randevulu sipariş saatlerini Türkiye saatiyle (UTC+3) yazar.
///
/// Uygulamanın geri kalanı da dükkan saatlerini sabit UTC+3 ile hesaplıyor
/// (bkz. `Shop.isOpen`); telefonun saat dilimi farklı olsa da satıcı ile
/// müşteri aynı saati görür. intl yerel verisine bağlı değildir (testlerde de
/// çalışır).
abstract final class ScheduleFormat {
  static const List<String> _months = [
    'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz',
    'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
  ];
  static const List<String> _days = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];

  /// Türkiye duvar saati (UTC alanları Türkiye saatini taşır).
  static DateTime tr(DateTime t) => t.toUtc().add(const Duration(hours: 3));

  /// Türkiye takvim günü (gruplama anahtarı).
  static DateTime trDay(DateTime t) {
    final x = tr(t);
    return DateTime.utc(x.year, x.month, x.day);
  }

  static String _two(int n) => n.toString().padLeft(2, '0');

  /// "14:00"
  static String time(DateTime t) {
    final x = tr(t);
    return '${_two(x.hour)}:${_two(x.minute)}';
  }

  /// "Bugün" / "Yarın" / "23 Eki Per"
  static String dayLabel(DateTime t, {DateTime? now}) {
    final day = trDay(t);
    final today = trDay(now ?? DateTime.now());
    final diff = day.difference(today).inDays;
    if (diff == 0) return 'Bugün';
    if (diff == 1) return 'Yarın';
    final x = tr(t);
    return '${x.day} ${_months[x.month - 1]} ${_days[x.weekday - 1]}';
  }

  /// "Bugün 14:00" / "23 Eki Per 14:00"
  static String full(DateTime t, {DateTime? now}) => '${dayLabel(t, now: now)} ${time(t)}';
}
