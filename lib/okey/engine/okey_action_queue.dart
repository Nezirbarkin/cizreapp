import 'dart:async';

/// Oyun hamlelerini SIRAYA ALIR — hiçbirini düşürmez.
///
/// NEDEN VAR (gerçek bir hatanın ardından):
/// Eşzamanlı hamleleri engellemek için önce şöyle bir koruma konmuştu:
/// ```dart
/// if (_actionInFlight) return; // hamle düşürülür
/// ```
/// Bu, iki ayrı sebeple kullanıcıyı oyundan koparıyordu:
///
///   1) Hamle SESSİZCE ÇÖPE ATILIYORDU. Kullanıcı taşı atmaya çalışıyor,
///      hiçbir şey olmuyor, hiçbir uyarı da çıkmıyordu.
///   2) Kilit, sunucu çağrısından SONRAKİ tazeleme (refresh) boyunca da
///      tutuluyordu. Tazeleme birkaç ağ turu sürdüğü için, taş çektikten
///      sonra yüzlerce milisaniye boyunca ATMA İMKÂNSIZ hale geliyordu.
///      Kullanıcının şikâyeti tam olarak buydu: "süre bitmeden taş atamıyor".
///
/// Doğru davranış: hamleler ÜST ÜSTE BİNMEZ ama KAYBOLMAZ da. Sıradaki hamle
/// bir öncekinin bitmesini bekler ve sonra çalışır — o an durum güncel olduğu
/// için doğru sonucu verir.
class OkeyActionQueue {
  Future<void> _tail = Future<void>.value();

  /// Şu anda çalışan/bekleyen hamle var mı? (yalnızca teşhis/test için)
  int _pending = 0;
  int get pendingCount => _pending;

  /// [action]'ı sıraya ekler ve bittiğinde tamamlanan bir Future döner.
  ///
  /// [action] hata fırlatırsa sıra BOZULMAZ: hata çağırana iletilir ama
  /// sıradaki hamleler yine çalışır.
  Future<void> add(Future<void> Function() action) {
    _pending++;
    final result = _tail.then((_) => action());

    // Kuyruğun kendisi hatayı yutar; aksi halde bir hamlenin hatası
    // sonraki TÜM hamleleri zincirleme iptal ederdi.
    _tail = result.catchError((_) {}).whenComplete(() => _pending--);

    return result;
  }
}
