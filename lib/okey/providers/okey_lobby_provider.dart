import 'dart:async';
import 'package:flutter/foundation.dart';

import '../models/okey_models.dart';
import '../services/okey_invite_service.dart';
import '../services/okey_room_service.dart';

/// Lobi ekranının state'i: bekleyen oda listesi + oda kurma/katılma.
class OkeyLobbyProvider with ChangeNotifier {
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
  final OkeyInviteService _invites = OkeyInviteService();

  List<OkeyRoom> _rooms = [];
  List<OkeyRoom> _liveRooms = [];
  bool _isLoading = false;
  String? _error;

  /// Bana gelen ve hâlâ oturulabilir masa davetleri.
  ///
  /// Bildirimi kaçıran ya da bildirimi kapatmış oyuncunun daveti görmesinin
  /// İKİNCİ yolu budur — push tek başına güvenilir bir teslim kanalı değil
  /// (cihaz kaydı olmayabilir, tercih kapalı olabilir).
  List<OkeyRoomInvite> _pendingInvites = const [];
  List<OkeyRoomInvite> get pendingInvites => _pendingInvites;

  /// Devam eden oyunum (varsa) — yanlışlıkla çıkma/bağlantı kopması sonrası
  /// "Devam Et" bandıyla geri dönebilmek için.
  OkeyRoom? _activeRoom;
  OkeyRoom? get activeRoom => _activeRoom;

  OkeyLobbyProvider() {
    // KRİTİK: doğrudan refresh() çağrılırsa, ilk await'ten önceki senkron
    // kısım (notifyListeners() dahil) bu constructor'ı tetikleyen
    // ChangeNotifierProvider'ın mount/build işlemiyle aynı çağrı yığınında
    // çalışır ve Flutter'ın build tutarlılığını bozar (bkz.
    // OkeyGameProvider'daki aynı düzeltmenin ayrıntılı açıklaması).
    Future.microtask(refresh);
  }

  List<OkeyRoom> get rooms => _rooms;

  /// İZLENEBİLİR masalar: oyunu süren, herkese açık masalar.
  ///
  /// Açık masalar listesinden AYRIDIR ve olmak zorundadır: o liste tam
  /// olarak izlenemeyecek masaları (henüz başlamamış, dolmamış) döndürür.
  List<OkeyRoom> get liveRooms => _liveRooms;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> refresh() async {
    _isLoading = true;
    _error = null;
    _notify();
    try {
      // Ölü masaları önce temizle: maçı bitmiş odalar lobide "Devam Et"
      // olarak görünüp oyuncuyu boş bir masaya götürüyordu.
      try {
        await _service.cleanupStaleRooms();
      } catch (_) {
        // Temizlik başarısız olsa da lobi yüklenmeye devam eder.
      }
      _rooms = await _service.listOpenRooms();
      _activeRoom = await _service.getMyActiveRoom();
      try {
        _liveRooms = await _service.listLiveRooms();
      } catch (_) {
        // İzlenebilir masa listesi bir EK'tir; alınamazsa lobi yine çalışır.
        _liveRooms = const [];
      }
      try {
        _pendingInvites = await _invites.myInvites();
      } catch (_) {
        // Davet listesi de bir EK'tir (misafir oturumda hiç gelmez).
        _pendingInvites = const [];
      }
    } catch (e) {
      _error = 'Odalar yüklenemedi: $e';
    } finally {
      _isLoading = false;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// Yeni oda kurar, kurulan odanın id'sini döner (null ise hata [error]'da).
  /// OTOMATİK EŞLEŞTİRME — uygun masaya otur, yoksa kur.
  ///
  /// Hata mesajı ayrı tutuluyor çünkü sebepleri farklı: masa kurulamaması
  /// (çip yetmiyor) ile eşleşememek (uygun masa yok ama kurulamadı da) aynı
  /// cümleyle anlatılamaz.
  Future<String?> quickMatch({
    String gameMode = 'katlamasiz',
    String teamMode = 'essiz',
    String assistMode = 'yardimli',
    int totalHands = 3,
    int entryFee = OkeyRoomService.minEntryFee,
  }) async {
    _error = null;
    try {
      final r = await _service.quickMatch(
        gameMode: gameMode,
        teamMode: teamMode,
        assistMode: assistMode,
        totalHands: totalHands,
        entryFee: entryFee,
      );
      return r.roomId;
    } catch (e) {
      _error = '$e'.contains('insufficient_points')
          ? 'Eşleştirme için çipin yetmiyor.'
          : 'Eşleştirme yapılamadı: $e';
      _notify();
      return null;
    }
  }

  Future<String?> createRoom({
    bool isPrivate = false,
    String gameMode = 'katlamasiz',
    String teamMode = 'essiz',
    String assistMode = 'yardimli',
    int totalHands = 3,
    int entryFee = OkeyRoomService.minEntryFee,
  }) async {
    _error = null;
    try {
      final room = await _service.createRoom(
        isPrivate: isPrivate,
        gameMode: gameMode,
        teamMode: teamMode,
        assistMode: assistMode,
        totalHands: totalHands,
        entryFee: entryFee,
      );
      return room.id;
    } catch (e) {
      _error = 'Oda kurulamadı: $e';
      _notify();
      return null;
    }
  }

  /// Odaya katılır, koltuk no döner (null ise hata [error]'da).
  Future<int?> joinRoom({String? roomId, String? joinCode}) async {
    _error = null;
    try {
      return await _service.joinRoom(roomId: roomId, joinCode: joinCode);
    } catch (e) {
      _error = 'Odaya katılınamadı: $e';
      _notify();
      return null;
    }
  }

  /// Daveti kabul eder ve masaya OTURUR; girilen odanın id'sini döner
  /// (null ise sebep [error]'da, gösterilebilir bir cümle olarak).
  ///
  /// Oturma işi sunucuda aynı işlemin içinde yapılır — bu yüzden burada
  /// ayrıca `joinRoom` çağrılmaz.
  Future<String?> acceptInvite(String inviteId) async {
    _error = null;
    try {
      final roomId = await _invites.accept(inviteId);
      _pendingInvites = _pendingInvites
          .where((i) => i.inviteId != inviteId)
          .toList();
      _notify();
      return roomId;
    } catch (e) {
      _error = OkeyInviteService.friendlyError(e);
      // Davet ölmüş olabilir (masa doldu/başladı): liste tazelensin ki
      // oyuncu aynı ölü kartla ikinci kez uğraşmasın.
      unawaited(refresh());
      return null;
    }
  }

  Future<void> declineInvite(String inviteId) async {
    _error = null;
    // Kart ÖNCE gider: ret, kullanıcının anında karşılık beklediği bir
    // eylem ve sunucu yanıtı geciktiğinde kart ekranda kalıyordu.
    _pendingInvites = _pendingInvites
        .where((i) => i.inviteId != inviteId)
        .toList();
    _notify();
    try {
      await _invites.decline(inviteId);
    } catch (_) {
      // Ret başarısız olsa bile kartı geri getirmenin kullanıcıya faydası
      // yok; davet zaten kendi kendine (2 saat / masa başlayınca) düşer.
    }
  }

  /// Davet koduyla katılır ve girilen ODANIN ID'sini döner (null ise hata).
  ///
  /// Kodla katılan oyuncunun doğrudan bekleme odasına gidebilmesi için
  /// koltuk numarası değil oda kimliği gerekir.
  Future<String?> joinRoomByCode(String code) async {
    _error = null;
    try {
      final seat = await _service.joinRoom(joinCode: code);
      if (seat < 0) return null;
      // Katıldıktan sonra oda artık "benim odam" olduğu için aktif oda
      // sorgusuyla kimliğini alabiliriz.
      final room = await _service.getMyActiveRoom();
      if (room == null) {
        _error = 'Odaya katıldın ama oda bulunamadı, listeyi yenile.';
        _notify();
        return null;
      }
      return room.id;
    } catch (e) {
      _error = 'Odaya katılınamadı: $e';
      _notify();
      return null;
    }
  }
}
