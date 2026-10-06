/// Masa senkronunun saf (ağsız, test edilebilir) parçaları (Görev 1.6).
library;

/// SUNUCU SAATİNE göre "şimdi".
///
/// Sıra süresi (`okey_matches.turn_deadline`) sunucu saatiyle yazılır. Sayaç
/// ve "süre doldu, otomatik oyna" kararı eskiden CİHAZ saatiyle veriliyordu:
/// cihaz saati birkaç saniye bile kaymışsa sayaç yanlış gösteriyor, otomatik
/// oynatma çağrısı erken (sunucu reddeder) ya da geç gidiyordu.
///
/// Her masa okumasında sunucunun o anki saati (`server_now`) ile isteğin
/// gidiş-dönüşü örneklenir. Sunucu saati isteğin ortasına denk sayılır; en
/// KISA gidiş-dönüşlü örnek en güvenilir olandır ve o tutulur. Cihaz saati
/// elle değiştirilmiş olabileceği için en iyi örnek bir süre sonra eskir ve
/// yerini yenisine bırakır.
class OkeyServerClock {
  OkeyServerClock({DateTime Function()? localNow})
    : _localNow = localNow ?? DateTime.now;

  final DateTime Function() _localNow;

  /// En iyi örnek bu süreden eskiyse sıradaki örnek her halükarda alınır.
  static const Duration sampleMaxAge = Duration(minutes: 2);

  /// Bundan uzun süren istek, farkı ölçmek için fazla belirsizdir.
  static const Duration maxUsefulRoundTrip = Duration(seconds: 5);

  Duration _offset = Duration.zero;
  Duration? _bestRoundTrip;
  DateTime? _bestSampledAt;

  /// Sunucu saati − cihaz saati (henüz örnek yoksa sıfır).
  Duration get offset => _offset;

  bool get hasSample => _bestRoundTrip != null;

  /// Cihaz saati (örneklerin [addSample]'a bununla ölçülmesi gerekir).
  DateTime localNow() => _localNow();

  /// Sunucu saatine göre şimdi.
  DateTime now() => _localNow().add(_offset);

  /// [sentAt]/[receivedAt]: isteğin cihaz saatiyle başı ve sonu;
  /// [serverNow]: sunucunun o istekte okuduğu saat.
  void addSample({
    required DateTime sentAt,
    required DateTime receivedAt,
    required DateTime serverNow,
  }) {
    final roundTrip = receivedAt.difference(sentAt);
    if (roundTrip.isNegative || roundTrip > maxUsefulRoundTrip) return;
    final best = _bestRoundTrip;
    final bestAt = _bestSampledAt;
    final stale = bestAt == null || receivedAt.difference(bestAt) > sampleMaxAge;
    if (!stale && best != null && roundTrip > best) return;
    final midpoint = sentAt.add(roundTrip ~/ 2);
    _offset = serverNow.difference(midpoint);
    _bestRoundTrip = roundTrip;
    _bestSampledAt = receivedAt;
  }
}

/// Bayat masa görünümünü ve kopan realtime kanalını toparlama kararları.
abstract final class OkeyTurnSync {
  /// Sıranın süresi bu kadar geçmişken masa hâlâ aynı sırayı gösteriyorsa
  /// görünüm büyük olasılıkla bayattır: süre dolunca sıra en geç saniyeler
  /// içinde ilerler (istemcilerin "otomatik oyna" çağrısı ya da sunucunun
  /// 30 saniyelik süpürücüsü), bunu haber veren realtime olayı kaçmıştır.
  static const Duration staleGrace = Duration(seconds: 8);

  /// Bayat görünümde en fazla bu sıklıkla yeniden okunur.
  static const Duration staleInterval = Duration(seconds: 8);

  /// Masa yeniden okunmalı mı? Yalnızca süresi [staleGrace]'ten fazla geçmiş
  /// bir sıra varken ve son başarılı okuma [staleInterval]'dan eskiyse.
  static bool shouldResync({
    required DateTime serverNow,
    required DateTime? turnDeadline,
    required DateTime? lastRefreshAt,
  }) {
    if (turnDeadline == null) return false;
    if (serverNow.difference(turnDeadline) <= staleGrace) return false;
    if (lastRefreshAt == null) return true;
    return serverNow.difference(lastRefreshAt) >= staleInterval;
  }

  /// Hata veren kanalı yeniden kurmadan önce beklenecek süre
  /// ([attempt] 0'dan başlar): 2, 5, 10, 20, sonra hep 30 saniye.
  static Duration resubscribeDelay(int attempt) {
    const steps = [2, 5, 10, 20, 30];
    final i = attempt < 0 ? 0 : (attempt >= steps.length ? steps.length - 1 : attempt);
    return Duration(seconds: steps[i]);
  }

  /// "Otomatik oyna" çağrısı hata verirse (ağ vb.) aynı sıra için yeniden
  /// denemeden önce beklenecek süre. Eskiden her saniye yeniden deneniyordu.
  static const Duration autoAdvanceRetry = Duration(seconds: 3);
}
