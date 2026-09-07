import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/okey_models.dart';
import '../services/okey_room_service.dart';

/// Bekleme odası ekranının state'i. Gerçek realtime kanalı yok (Faz D'nin
/// maç ekranında var) — bunun yerine oda 'waiting' durumdayken hafif bir
/// polling (3sn) ile oyun başladığı an otomatik yakalanır.
class OkeyRoomProvider with ChangeNotifier {
  bool _notifyScheduled = false;
  bool _disposed = false;

  /// Bildirimler ASLA senkron yapılmaz — mevcut build/gesture çağrı yığını
  /// boşaldıktan sonra çalışır. Bkz. OkeyGameProvider._notify() açıklaması.
  void _notify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  final OkeyRoomService _service = OkeyRoomService();
  final String roomId;

  OkeyRoom? _room;
  List<OkeyRoomSeat> _seats = [];
  bool _isLoading = false;
  String? _error;
  Timer? _pollTimer;

  OkeyRoomProvider(this.roomId) {
    // KRİTİK: refresh() burada DOĞRUDAN çağrılırsa, ilk await'ten önceki
    // senkron kısmı (notifyListeners() dahil) bu constructor'ı çağıran
    // ChangeNotifierProvider'ın mount/build işlemiyle aynı senkron yığında
    // çalışır ve Flutter'ın build tutarlılığını bozar (bkz.
    // OkeyGameProvider'daki aynı düzeltmenin ayrıntılı açıklaması).
    Future.microtask(refresh);
    _pollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_room?.status != 'waiting') return;
      refresh(silent: true);
      // BOT SON TARİHİ aynı yoklamaya biner: ayrı bir zamanlayıcı, aynı işi
      // iki kez uyanan iki döngüyle yapmak olurdu.
      unawaited(_maybeAutofillBots());
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _pollTimer?.cancel();
    super.dispose();
  }

  OkeyRoom? get room => _room;
  List<OkeyRoomSeat> get seats => _seats;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Oturumdaki kullanıcı — OKUMASI ASLA ÇÖKMEZ.
  ///
  /// `Supabase.instance` başlatılmamışsa ASSERTION FIRLATIR ve bu getter
  /// build() içinden çağrıldığı için tüm ekranı kırmızı hata ekranına
  /// çeviriyordu. Kimliği okuyamamak "oturum yok" demektir; ekranın çökmesi
  /// için bir sebep değil. (Widget testlerinde de Supabase başlatılmadığı
  /// için ekranlar bu yüzden hiç kurulamıyordu.)
  String? get _myUserId {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  OkeyRoomSeat? get mySeat {
    final uid = _myUserId;
    if (uid == null) return null;
    for (final s in _seats) {
      if (s.userId == uid) return s;
    }
    return null;
  }

  bool get allSeatsReady =>
      _seats.length == 4 && _seats.every((s) => !s.isEmpty && s.isReady);

  Future<void> refresh({bool silent = false}) async {
    if (!silent) {
      _isLoading = true;
      _notify();
    }
    try {
      final results = await Future.wait([
        _service.getRoom(roomId),
        _service.getSeats(roomId),
      ]);
      _room = results[0] as OkeyRoom;
      _seats = results[1] as List<OkeyRoomSeat>;
      _error = null;
    } catch (e) {
      _error = 'Oda bilgisi alınamadı: $e';
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  Future<void> toggleReady() async {
    final my = mySeat;
    if (my == null) return;
    try {
      await _service.setReady(roomId, !my.isReady);
      await refresh();
    } catch (e) {
      _error = 'Hazır durumu güncellenemedi: $e';
      _notify();
    }
  }

  /// Test kolaylığı: boş koltukları botlarla doldurup 4/4 tamamlanınca eli başlatır.
  /// BOT SON TARİHİ GELDİ Mİ — otomatik eşleştirme masasında boş koltuklar
  /// botlarla dolar.
  ///
  /// Her yoklamada çağrılır ama karar SUNUCUNUNDUR: son tarih geçmediyse,
  /// masa elle kurulduysa ya da koltuklar insanlarla dolduysa hiçbir şey
  /// yapmaz. İstemcinin kendi saatine göre karar vermesi, saati ileri alan
  /// bir cihazın masayı erkenden botla doldurması demek olurdu.
  ///
  /// SESSİZ: ağ hatası bekleme odasını bozmaz, bir sonraki yoklamada
  /// yeniden denenir.
  Future<void> _maybeAutofillBots() async {
    try {
      if (await _service.maybeAutofillBots(roomId)) {
        await refresh(silent: true);
      }
    } catch (_) {
      // bkz. yukarıdaki gerekçe
    }
  }

  Future<void> fillWithBots() async {
    try {
      await _service.fillWithBots(roomId);
      await refresh();
    } catch (e) {
      _error = 'Botlar eklenemedi: $e';
      _notify();
    }
  }

  Future<void> leave() async {
    try {
      await _service.leaveRoom(roomId);
    } catch (e) {
      _error = 'Odadan çıkılamadı: $e';
      _notify();
    }
  }
}
