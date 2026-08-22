// ignore_for_file: deprecated_member_use

/// Şehir içi modülü için saat yardımcıları (pure functions, test edilebilir).
///
/// Bu dosyadaki tüm fonksiyonlar yan etkisizdir ve birim testlerle doğrulanabilir.
/// UI/state katmanından ayrılmıştır; panel ve provider sadece bunları çağırır.
library;

/// "HH:mm" string'ini saat/dakika çiftine çevirir. Geçersizse null.
({int hour, int minute})? parseHhmm(String? value) {
  if (value == null || value.isEmpty) return null;
  final parts = value.split(':');
  if (parts.length < 2) return null;
  final h = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (h == null || m == null) return null;
  if (h < 0 || h > 23 || m < 0 || m > 59) return null;
  return (hour: h, minute: m);
}

/// Saat/dakika çiftini "HH:mm" string'ine çevirir. Çıktı 24 saat, sıfır dolgulu.
String formatHhmm(int hour, int minute) {
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// Verilen saat [current] (hour, minute) aralığın [start, end] içinde mi?
///
/// Aralık inclusive-start, exclusive-end yarı-açıktır.
/// Gece yarısını geçen aralıkları (örn. 22:00 → 06:00) destekler: bu durumda
/// `end <= start` olur ve "ya start'tan büyük ya da end'ten küçük" mantığı uygulanır.
bool isTimeWithinRange({
  required int currentHour,
  required int currentMinute,
  required int startHour,
  required int startMinute,
  required int endHour,
  required int endMinute,
}) {
  final currentMinutes = currentHour * 60 + currentMinute;
  final startMinutes = startHour * 60 + startMinute;
  final endMinutes = endHour * 60 + endMinute;

  if (startMinutes < endMinutes) {
    return currentMinutes >= startMinutes && currentMinutes < endMinutes;
  } else {
    // Gece yarısını geçen aralık
    return currentMinutes >= startMinutes || currentMinutes < endMinutes;
  }
}

/// Süreyi "H:MM:SS" formatına çevirir. Örn. 3661s → "1:01:01".
String formatDurationHMS(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes % 60;
  final seconds = d.inSeconds % 60;
  return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
}

/// Mesafeye göre tahmini varış süresi (dakika). Hız varsayılan 30 km/s.
int calculateEtaMinutes(int distanceMeters, {double speedKmh = 30.0}) {
  if (distanceMeters <= 0) return 0;
  final distanceKm = distanceMeters / 1000;
  final hours = distanceKm / speedKmh;
  return (hours * 60).round();
}

/// "HH:mm" string'inin geçerli olup olmadığını doğrular.
bool isValidHhmm(String? value) {
  return parseHhmm(value) != null;
}
