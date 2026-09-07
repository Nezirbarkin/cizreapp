import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/okey_sound_service.dart';
import 'okey_admin_bots_tab.dart';
import 'okey_admin_gifts_tab.dart';
import 'okey_admin_points_tab.dart';
import 'okey_admin_settings_tab.dart';
import 'okey_admin_service.dart';
import 'okey_admin_widgets.dart';

/// Admin panelindeki "101 Okey Yönetimi" bölümü.
/// Altı sekme: Masalar (izleme/moderasyon) · Puanlar · Hediyeler · Botlar ·
/// Ayarlar · Sesler.
class OkeyAdminContent extends StatelessWidget {
  const OkeyAdminContent({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.purple.shade700, Colors.purple.shade900],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: const SafeArea(
              bottom: false,
              child: TabBar(
                isScrollable: true,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                tabs: [
                  Tab(text: 'Masalar', icon: Icon(Icons.table_bar)),
                  Tab(text: 'Çipler', icon: Icon(Icons.stars)),
                  Tab(text: 'Hediyeler', icon: Icon(Icons.card_giftcard)),
                  Tab(text: 'Botlar', icon: Icon(Icons.smart_toy)),
                  Tab(text: 'Ayarlar', icon: Icon(Icons.settings)),
                  Tab(text: 'Sesler', icon: Icon(Icons.volume_up)),
                ],
              ),
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _OkeyRoomsTab(),
                OkeyAdminPointsTab(),
                OkeyAdminGiftsTab(),
                OkeyAdminBotsTab(),
                OkeyAdminSettingsTab(),
                _OkeySoundsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ===========================================================================
// MASALAR
// ===========================================================================

class _OkeyRoomsTab extends StatefulWidget {
  const _OkeyRoomsTab();

  @override
  State<_OkeyRoomsTab> createState() => _OkeyRoomsTabState();
}

class _OkeyRoomsTabState extends State<_OkeyRoomsTab> {
  final _service = OkeyAdminService();
  late Future<List<OkeyAdminRoom>> _future;

  /// Terk edilmiş masalar da listelensin mi (varsayılan: HAYIR).
  ///
  /// Panel eskiden `status IN ('waiting','in_progress')` olan HER masayı
  /// gösteriyordu. Terk edilmiş masaları kapatan bir kural olmadığı için
  /// canlıda 40 masa birikmişti; en eskisi 5 günlük ve son hamlesi günler
  /// öncesine ait. Liste böylece kullanışsızdı — gerçekten oynanan masa
  /// ölülerin arasında kayboluyordu.
  bool _includeIdle = false;

  bool _cleaning = false;

  @override
  void initState() {
    super.initState();
    _future = _service.listActiveRooms(includeIdle: _includeIdle);
  }

  void _reload() => setState(
    () => _future = _service.listActiveRooms(includeIdle: _includeIdle),
  );

  /// Ölü masaları kapatır (maçı bitmiş, boş bekleyen ve 30 dk etkinliksiz).
  Future<void> _cleanup() async {
    setState(() => _cleaning = true);
    try {
      final closed = await _service.cleanupStaleRooms();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            closed == 0 ? 'Kapatılacak ölü masa yok' : '$closed masa kapatıldı',
          ),
        ),
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(OkeyAdminService.describeError(e))),
      );
    } finally {
      if (mounted) setState(() => _cleaning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  _includeIdle
                      ? 'Tüm masalar (terk edilmişler dahil)'
                      : 'Aktif masalar',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                icon: _cleaning
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cleaning_services_outlined),
                tooltip: 'Ölü masaları kapat',
                onPressed: _cleaning ? null : _cleanup,
              ),
              IconButton(
                icon: const Icon(Icons.refresh),
                tooltip: 'Yenile',
                onPressed: _reload,
              ),
            ],
          ),
        ),
        // Anahtar KAPALI başlar: adminin görmek istediği şey neredeyse her
        // zaman "şu an ne oynanıyor"dur. Ölüleri görmek isteyen açar ve
        // yanındaki süpürgeyle temizler.
        SwitchListTile(
          dense: true,
          value: _includeIdle,
          onChanged: (v) => setState(() {
            _includeIdle = v;
            _future = _service.listActiveRooms(includeIdle: v);
          }),
          title: const Text('Terk edilmiş masaları da göster'),
          subtitle: const Text(
            '30 dakikadır hiçbir hamle ve bağlantı yok',
            style: TextStyle(fontSize: 11),
          ),
        ),
        Expanded(
          child: FutureBuilder<List<OkeyAdminRoom>>(
            future: _future,
            builder: (context, snap) {
              if (snap.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snap.hasError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Masalar alınamadı: '
                      '${OkeyAdminService.describeError(snap.error!)}',
                      textAlign: TextAlign.center,
                    ),
                  ),
                );
              }
              final rooms = snap.data ?? [];
              if (rooms.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      _includeIdle
                          ? 'Hiç açık masa yok.'
                          : 'Şu an oynanan masa yok.\n'
                                'Terk edilmiş masaları görmek için yukarıdaki '
                                'anahtarı aç.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: Colors.grey),
                    ),
                  ),
                );
              }
              return ListView.builder(
                itemCount: rooms.length,
                itemBuilder: (context, i) {
                  final card = _RoomCard(room: rooms[i], onChanged: _reload);
                  return card
                      .animate()
                      .fadeIn(duration: 220.ms, delay: (i * 30).ms)
                      .slideY(begin: 0.04, end: 0, duration: 220.ms);
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

class _RoomCard extends StatefulWidget {
  final OkeyAdminRoom room;
  final VoidCallback onChanged;

  const _RoomCard({required this.room, required this.onChanged});

  @override
  State<_RoomCard> createState() => _RoomCardState();
}

class _RoomCardState extends State<_RoomCard> {
  final _service = OkeyAdminService();

  /// Koltuk listesi SADECE BİR KEZ istenir ve saklanır.
  ///
  /// HATA: bu future eskiden doğrudan `build()` içinde kuruluyordu
  /// (`future: service.listRoomPlayers(...)`). Her yeniden çizimde — liste
  /// animasyonunun her karesi, sekme değişimi, üstteki herhangi bir
  /// setState — YENİ bir RPC ateşleniyordu. Bir masa kartı açıkken panel
  /// sunucuya sürekli istek yağdırıyor, gelen cevaplar da FutureBuilder'ı
  /// baştan "yükleniyor" durumuna düşürüp listeyi titretiyordu.
  Future<List<OkeyAdminSeat>>? _seatsFuture;

  bool get _isPlaying => widget.room.status == 'in_progress';

  void _loadSeats() {
    setState(() => _seatsFuture = _service.listRoomPlayers(widget.room.roomId));
  }

  /// "3 dk önce" — masanın gerçekten canlı olup olmadığını gösteren tek sayı.
  String get _activityLabel {
    final d = DateTime.now().difference(widget.room.lastActivity);
    if (d.inSeconds < 60) return 'az önce';
    if (d.inMinutes < 60) return '${d.inMinutes} dk önce';
    if (d.inHours < 24) return '${d.inHours} sa önce';
    return '${d.inDays} gün önce';
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final idle = room.isIdle;
    final statusColor = idle
        ? Colors.grey
        : (_isPlaying ? Colors.green : Colors.orange);
    final shortLabel = room.roomId.length >= 6
        ? room.roomId.substring(0, 6).toUpperCase()
        : room.roomId.toUpperCase();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      elevation: 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: statusColor.withValues(alpha: 0.35), width: 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: statusColor),
            Expanded(
              child: ExpansionTile(
                // Koltuk listesi ancak kart AÇILINCA istenir; kapalı 20
                // masanın hepsi için peşinen RPC atmanın anlamı yok.
                onExpansionChanged: (open) {
                  if (open && _seatsFuture == null) _loadSeats();
                },
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: statusColor.withValues(alpha: 0.15),
                  child: Icon(
                    _isPlaying ? Icons.play_arrow : Icons.hourglass_top,
                    color: statusColor,
                    size: 18,
                  ),
                ),
                title: Row(
                  children: [
                    // Masa etiketi ESNER: ExpansionTile'ın başlık alanı
                    // ikon + ok tuşundan artan yerdir ve dar bir admin
                    // panelinde (ya da büyütülmüş yazı tipinde) sabit
                    // genişlikli iki öğe satırı taşırıyordu.
                    Flexible(
                      child: Text(
                        'Masa #$shortLabel',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: OkeyBadgeChip(
                        icon: _isPlaying
                            ? Icons.play_circle_outline
                            : Icons.hourglass_top,
                        label: _isPlaying ? 'Oynanıyor' : 'Bekliyor',
                        color: statusColor,
                      ),
                    ),
                  ],
                ),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 2),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      OkeyBadgeChip(
                        icon: Icons.style,
                        label: room.gameMode == 'katlamali'
                            ? 'Katlamalı'
                            : 'Katlamasız',
                        color: Colors.deepPurple,
                      ),
                      OkeyBadgeChip(
                        icon: Icons.groups,
                        label: room.teamMode == 'esli' ? 'Eşli' : 'Eşsiz',
                        color: Colors.indigo,
                      ),
                      OkeyBadgeChip(
                        icon: Icons.support_agent,
                        label: room.assistMode == 'yardimsiz'
                            ? 'Yardımsız'
                            : 'Yardımlı',
                        color: Colors.teal,
                      ),
                      if (room.isPrivate)
                        const OkeyBadgeChip(
                          icon: Icons.lock,
                          label: 'Özel',
                          color: Colors.brown,
                        ),
                      OkeyBadgeChip(
                        icon: Icons.person,
                        label: '${room.seatedCount} oyuncu',
                        color: Colors.blue,
                      ),
                      if (room.botCount > 0)
                        OkeyBadgeChip(
                          icon: Icons.smart_toy,
                          label: '${room.botCount} bot',
                          color: Colors.blueGrey,
                        ),
                      if (room.handNo > 0)
                        OkeyBadgeChip(
                          icon: Icons.filter_9_plus,
                          label: '${room.handNo}. el',
                          color: Colors.orange,
                        ),
                      if (room.spectatorCount > 0)
                        OkeyBadgeChip(
                          icon: Icons.visibility,
                          label: '${room.spectatorCount} izleyici',
                          color: Colors.green,
                        ),
                      // SON ETKİNLİK: masanın canlı olup olmadığını söyleyen
                      // tek sayı. Bu rozet olmadan "oynanıyor" etiketi, beş
                      // gündür kimsenin dokunmadığı bir masada da yeşil
                      // yanıyordu.
                      OkeyBadgeChip(
                        icon: idle ? Icons.bedtime : Icons.bolt,
                        label: idle
                            ? 'terk edilmiş · $_activityLabel'
                            : _activityLabel,
                        color: idle ? Colors.grey : Colors.lightGreen,
                      ),
                    ],
                  ),
                ),
                children: [
                  FutureBuilder<List<OkeyAdminSeat>>(
                    future: _seatsFuture,
                    builder: (context, snap) {
                      if (snap.connectionState == ConnectionState.waiting ||
                          _seatsFuture == null) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Center(child: CircularProgressIndicator()),
                        );
                      }
                      // HATA DALI: eskiden yalnızca `!snap.hasData`
                      // kontrol ediliyordu, yani çağrı hata verdiğinde kart
                      // sonsuza kadar dönen bir çemberle kalıyordu.
                      if (snap.hasError) {
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            children: [
                              Text(
                                'Koltuklar alınamadı: '
                                '${OkeyAdminService.describeError(snap.error!)}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: Colors.red,
                                ),
                              ),
                              const SizedBox(height: 8),
                              OutlinedButton.icon(
                                onPressed: _loadSeats,
                                icon: const Icon(Icons.refresh, size: 16),
                                label: const Text('Tekrar dene'),
                              ),
                            ],
                          ),
                        );
                      }
                      final seats = snap.data ?? const <OkeyAdminSeat>[];
                      if (seats.isEmpty) {
                        return const Padding(
                          padding: EdgeInsets.all(16),
                          child: Text('Bu masada koltuk kaydı yok.'),
                        );
                      }
                      return Column(
                        children: [
                          for (final s in seats)
                            _SeatRow(
                              room: room,
                              seat: s,
                              onChanged: () {
                                _loadSeats();
                                widget.onChanged();
                              },
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SeatRow extends StatefulWidget {
  final OkeyAdminRoom room;
  final OkeyAdminSeat seat;
  final VoidCallback onChanged;

  const _SeatRow({
    required this.room,
    required this.seat,
    required this.onChanged,
  });

  @override
  State<_SeatRow> createState() => _SeatRowState();
}

class _SeatRowState extends State<_SeatRow> {
  Future<bool>? _banFuture;

  bool get _isHuman => widget.seat.userId != null && !widget.seat.isBot;

  @override
  void initState() {
    super.initState();
    if (_isHuman) {
      _banFuture = _checkBanned(widget.seat.userId!);
    }
  }

  /// Koltuk BAŞKA bir oyuncuya geçtiyse yasak durumu yeniden sorulmalı.
  ///
  /// Bu satırlar liste içinde konuma göre yeniden kullanılıyor: bir oyuncu
  /// masadan atılıp yerine başkası (ya da bot) geldiğinde State aynı kalır.
  /// didUpdateWidget olmadan menü, ARTIK O KOLTUKTA OLMAYAN oyuncunun yasak
  /// durumunu gösteriyordu.
  @override
  void didUpdateWidget(_SeatRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.seat.userId != widget.seat.userId) {
      setState(
        () => _banFuture = _isHuman ? _checkBanned(widget.seat.userId!) : null,
      );
    }
  }

  /// Bu koltuktaki insan oyuncunun Okey'de yasaklı olup olmadığını
  /// GERÇEK olarak yalnız `okey_is_banned` RPC'sinden öğreniriz — hata
  /// olursa "yasaklı değil" varsayılır (menü hâlâ kullanılabilir kalsın).
  Future<bool> _checkBanned(String userId) async {
    try {
      final r = await Supabase.instance.client.rpc(
        'okey_is_banned',
        params: {'p_user_id': userId},
      );
      return r as bool? ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Yasakla/yasağı kaldır işleminden sonra bu koltuğun yasak durumunu
  /// tazeler ki menü doğru aksiyonu göstermeye devam etsin.
  void _refreshBanStatus() {
    if (!mounted) return;
    setState(() => _banFuture = _checkBanned(widget.seat.userId!));
  }

  Future<void> _confirmAndRun(
    BuildContext context, {
    required String title,
    required String message,
    required Future<void> Function() action,
    required String successText,
  }) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Onayla'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await action();
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(successText)));
      widget.onChanged();
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(OkeyAdminService.describeError(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final service = OkeyAdminService();
    final seat = widget.seat;
    final room = widget.room;

    Widget trailing;
    if (!_isHuman) {
      trailing = const SizedBox.shrink();
    } else {
      trailing = FutureBuilder<bool>(
        future: _banFuture,
        builder: (context, banSnap) {
          if (banSnap.connectionState == ConnectionState.waiting) {
            return const SizedBox(
              width: 20,
              height: 20,
              child: Padding(
                padding: EdgeInsets.all(2),
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          final isBanned = banSnap.data ?? false;
          return PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'kick') {
                _confirmAndRun(
                  context,
                  title: 'Masadan çıkar',
                  message:
                      '${seat.displayName} masadan çıkarılacak. Koltuk bota '
                      'devredilecek (masa kilitlenmesin diye).',
                  action: () => service.kickPlayer(room.roomId, seat.seatNo),
                  successText: 'Oyuncu masadan çıkarıldı',
                );
              } else if (v == 'ban') {
                _confirmAndRun(
                  context,
                  title: 'Okey\'den yasakla',
                  message:
                      '${seat.displayName} artık Okey odası kuramayacak ve '
                      'odalara katılamayacak.',
                  action: () =>
                      service.banUser(seat.userId!, reason: 'Admin paneli'),
                  successText: 'Oyuncu yasaklandı',
                ).then((_) => _refreshBanStatus());
              } else if (v == 'unban') {
                _confirmAndRun(
                  context,
                  title: 'Yasağı kaldır',
                  message: '${seat.displayName} tekrar oynayabilecek.',
                  action: () => service.removeBan(seat.userId!),
                  successText: 'Yasak kaldırıldı',
                ).then((_) => _refreshBanStatus());
              }
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'kick',
                child: Row(
                  children: [
                    Icon(Icons.exit_to_app, size: 18),
                    SizedBox(width: 8),
                    Text('Masadan çıkar'),
                  ],
                ),
              ),
              if (isBanned)
                const PopupMenuItem(
                  value: 'unban',
                  child: Row(
                    children: [
                      Icon(Icons.lock_open, size: 18, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Yasağı kaldır'),
                    ],
                  ),
                )
              else
                const PopupMenuItem(
                  value: 'ban',
                  child: Row(
                    children: [
                      Icon(Icons.block, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Okey\'den yasakla'),
                    ],
                  ),
                ),
            ],
          );
        },
      );
    }

    return ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 14,
        backgroundColor: seat.isBot ? Colors.blueGrey : Colors.deepPurple,
        child: Icon(
          seat.isBot ? Icons.smart_toy : Icons.person,
          size: 14,
          color: Colors.white,
        ),
      ),
      title: Row(
        children: [
          // Görünen ad 25+ karakter olabiliyor; Expanded olmadan satır
          // taşıyordu (ListTile başlığı sabit genişlikte değildir).
          Expanded(
            child: Text(
              'K${seat.seatNo + 1}: ${seat.displayName}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (seat.isDisconnected)
            const Padding(
              padding: EdgeInsets.only(left: 6),
              child: Icon(Icons.wifi_off, size: 14, color: Colors.red),
            ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Wrap(
          spacing: 6,
          runSpacing: 4,
          children: [
            OkeyBadgeChip(
              icon: Icons.style,
              label: '${seat.tileCount} taş',
              color: Colors.grey.shade700,
            ),
            if (seat.isReady)
              const OkeyBadgeChip(
                icon: Icons.check_circle_outline,
                label: 'Hazır',
                color: Colors.green,
              ),
            if (seat.isDisconnected)
              const OkeyBadgeChip(
                icon: Icons.wifi_off,
                label: 'Bağlantı yok',
                color: Colors.red,
              ),
          ],
        ),
      ),
      trailing: trailing,
    );
  }
}

// ===========================================================================
// AYARLAR
// ===========================================================================

// ===========================================================================
// SESLER
// ===========================================================================

/// Ses olayı kategorisi — küçük gruplar halinde göstermek için.
enum _SoundCategory { gameplay, feedback, social }

/// Her ses olayının admin panelinde görünen adı, açıklaması ve kategorisi.
const _soundLabels =
    <OkeySound, ({String title, String desc, _SoundCategory category})>{
      OkeySound.drawTile: (
        title: 'Taş çekme',
        desc: 'Desteden/ıskartadan taş alınca',
        category: _SoundCategory.gameplay,
      ),
      OkeySound.discardTile: (
        title: 'Taş atma',
        desc: 'Taş ıskartaya atılınca',
        category: _SoundCategory.gameplay,
      ),
      OkeySound.layMeld: (
        title: 'Per açma',
        desc: 'Masaya per/grup açılınca',
        category: _SoundCategory.gameplay,
      ),
      OkeySound.processTile: (
        title: 'Taş işleme',
        desc: 'Masadaki pere taş eklenince',
        category: _SoundCategory.gameplay,
      ),
      OkeySound.yourTurn: (
        title: 'Sıra sende',
        desc: 'Sıra oyuncuya gelince',
        category: _SoundCategory.feedback,
      ),
      OkeySound.timeWarning: (
        title: 'Süre uyarısı',
        desc: 'Son 5 saniyede',
        category: _SoundCategory.feedback,
      ),
      OkeySound.win: (
        title: 'Kazanma',
        desc: 'Eli oyuncu kazanınca',
        category: _SoundCategory.feedback,
      ),
      OkeySound.lose: (
        title: 'Kaybetme',
        desc: 'Eli rakip kazanınca',
        category: _SoundCategory.feedback,
      ),
      OkeySound.laugh: (
        title: 'Gülme (alay)',
        desc: 'Rakip "işlek" taş atınca',
        category: _SoundCategory.social,
      ),
      OkeySound.error: (
        title: 'Hata',
        desc: 'Geçersiz hamlede',
        category: _SoundCategory.social,
      ),
    };

const _categoryLabels = <_SoundCategory, ({String title, IconData icon})>{
  _SoundCategory.gameplay: (title: 'Oynanış Sesleri', icon: Icons.style),
  _SoundCategory.feedback: (title: 'Bildirim Sesleri', icon: Icons.campaign),
  _SoundCategory.social: (title: 'Tepki Sesleri', icon: Icons.emoji_emotions),
};

class _OkeySoundsTab extends StatefulWidget {
  const _OkeySoundsTab();

  @override
  State<_OkeySoundsTab> createState() => _OkeySoundsTabState();
}

class _OkeySoundsTabState extends State<_OkeySoundsTab> {
  final _service = OkeyAdminService();
  final _preview = AudioPlayer();

  /// Önizleme oynatıcısının "bitti" aboneliği.
  ///
  /// Alanda TUTULUR ve dispose'da iptal edilir. Eskiden `listen(...)`
  /// sonucu atılıyordu: abonelik State'ten uzun yaşayıp setState çağırmaya
  /// çalışabilecek tek nesneydi.
  StreamSubscription<void>? _previewDone;

  Map<String, String> _sounds = {};
  List<({String key, String name, String url})> _music = [];
  bool _loading = true;
  String? _busyKey;

  /// Liste alınamadıysa sebebi. Eskiden hata sessizce yutuluyor, sekme
  /// "hiç ses yok" diyordu — oysa sorun ağ/izin olabilir.
  String? _loadError;

  /// Çalma listesinde şu an dinlenen parçanın anahtarı — kart üstündeki
  /// play/pause ikonunu ve vurgu rengini bu belirler.
  String? _playingTrackKey;

  /// "Tüm örnekleri dinle" turu sürüyor mu? (Turu iki kez başlatmamak için.)
  bool _sampleTourRunning = false;

  @override
  void initState() {
    super.initState();
    _load();
    _previewDone = _preview.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playingTrackKey = null);
    });
  }

  @override
  void dispose() {
    _previewDone?.cancel();
    _preview.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final s = await _service.listSounds();
      if (mounted) setState(() => _sounds = s);
      final m = await _service.listMusic();
      if (mounted) {
        setState(() {
          _music = m;
          _loadError = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loadError = OkeyAdminService.describeError(e));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Arka plan şarkısı, efektlerden AYRI bir anahtarda tutulur ve boyut
  /// sınırı daha yüksektir (şarkılar doğal olarak daha büyük).
  /// Sunucudaki bucket sınırıyla AYNI olmalı (10 MB).
  /// Arayüzde 8 MB yazıp sunucunun 2 MB'da kesmesi gibi bir tutarsızlık,
  /// kullanıcıya sebebi anlaşılmayan bir hata olarak yansıyordu.
  static const int _musicMaxBytes = 10 * 1024 * 1024;

  /// Kısa efektler için makul sınır.
  static const int _effectMaxBytes = 2 * 1024 * 1024;

  Future<void> _uploadKey(String key, {int maxBytes = _effectMaxBytes}) async {
    // TÜM DOSYALAR gösterilir, doğrulamayı BİZ yaparız.
    //
    // FileType.custom + allowedExtensions kullanıldığında Android uzantıyı
    // MIME türüne çevirip filtreliyor; `.m4a` dosyaları cihaza göre farklı
    // MIME raporladığı için seçicide soluk kalıp SEÇİLEMİYORDU. Filtreyi
    // kaldırıp kontrolü kendimiz yapınca bu cihaz farkı ortadan kalkıyor.
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;

    final bytes = file.bytes;
    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Dosya okunamadı')));
      return;
    }
    // Doğrulama ADA DEĞİL İÇERİĞE de bakar: Android'de dosya seçiciden
    // gelen ad çoğu zaman uzantısız oluyor ve geçerli bir mp3
    // "Desteklenmeyen dosya" diye reddediliyordu.
    final ext = OkeyAdminService.resolveAudioExtension(file.name, bytes);
    if (ext == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bu dosya bir ses kaydı değil: ${file.name}\n'
            'Desteklenen formatlar: ${OkeyAdminService.supportedAudioLabel}',
          ),
        ),
      );
      return;
    }
    if (bytes.length > maxBytes) {
      if (!mounted) return;
      final mb = (maxBytes / (1024 * 1024)).toStringAsFixed(0);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Dosya $mb MB\'dan küçük olmalı')));
      return;
    }

    setState(() => _busyKey = key);
    try {
      final url = await _service.uploadSound(
        soundKey: key,
        // Uzantı ADA EKLENİR: depodaki yol ve MIME türü buradan türetiliyor.
        fileName: OkeyAdminService.extensionOf(file.name) == ext
            ? file.name
            : '${file.name}.$ext',
        bytes: bytes,
      );
      if (!mounted) return;
      setState(() => _sounds[key] = url);
      await OkeySoundService.instance.refreshRemoteSounds();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Yüklendi')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(OkeyAdminService.describeError(e))),
      );
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  /// Silme geri alınamaz (dosya depodan da kaldırılır), bu yüzden onay alınır.
  Future<void> _confirmClear(String key, String label) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('$label kaldırılsın mı?'),
        content: const Text(
          'Dosya depodan da silinecek ve bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Kaldır'),
          ),
        ],
      ),
    );
    if (ok == true) await _clearKey(key);
  }

  Future<void> _clearKey(String key) async {
    setState(() => _busyKey = key);
    try {
      await _service.clearSound(key);
      if (!mounted) return;
      setState(() => _sounds.remove(key));
      await OkeySoundService.instance.refreshRemoteSounds();
      await OkeySoundService.instance.refreshPlaylist();
      if (key.startsWith('music:') || key == OkeySoundService.musicKey) {
        await _load();
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(OkeyAdminService.describeError(e))),
      );
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  // Efekt yükleme/silme, arka plan şarkısıyla AYNI kod yolunu kullanır.
  // Önce iki ayrı kopya vardı; uzantı listesi ve boyut sınırı gibi kurallar
  // ikisinde ayrı ayrı yazılıydı ve biri güncellenip diğeri unutulabiliyordu.
  /// Çalma listesine şarkı EKLER (mevcut şarkıların üzerine yazmaz).
  Future<void> _addMusic() async {
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.first;

    final bytes = file.bytes;
    if (bytes == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Dosya okunamadı')));
      return;
    }
    final ext = OkeyAdminService.resolveAudioExtension(file.name, bytes);
    if (ext == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Bu dosya bir ses kaydı değil: ${file.name}\n'
            'Desteklenen formatlar: ${OkeyAdminService.supportedAudioLabel}',
          ),
        ),
      );
      return;
    }
    if (bytes.length > _musicMaxBytes) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Şarkı 10 MB\'dan küçük olmalı')),
      );
      return;
    }

    setState(() => _busyKey = 'music:add');
    try {
      await _service.addMusic(
        fileName: OkeyAdminService.extensionOf(file.name) == ext
            ? file.name
            : '${file.name}.$ext',
        bytes: bytes,
      );
      await OkeySoundService.instance.refreshPlaylist();
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('${file.name} eklendi')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(OkeyAdminService.describeError(e))),
      );
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  Future<void> _upload(OkeySound sound) => _uploadKey(sound.name);

  Future<void> _clear(OkeySound sound) =>
      _confirmClear(sound.name, _soundLabels[sound]!.title);

  Future<void> _playPreview(String url) async {
    try {
      await _preview.stop();
      await _preview.play(UrlSource(url));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Çalınamadı: ${OkeyAdminService.describeError(e)}'),
        ),
      );
    }
  }

  /// Uygulama paketiyle GELEN örnek sesi çalar.
  ///
  /// Bu, hiçbir dosya yüklenmediğinde oyunda duyulan sesin ta kendisidir —
  /// admin "neyin yerine ne yüklüyorum?" sorusunu önce dinleyerek
  /// yanıtlayabilsin diye.
  Future<void> _playSample(OkeySound sound) async {
    try {
      await _preview.stop();
      await _preview.play(AssetSource(sound.assetPath));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Örnek çalınamadı: ${OkeyAdminService.describeError(e)}',
          ),
        ),
      );
    }
  }

  /// Bütün örnekleri sırayla çalar — kısa bir "ses seti turu".
  Future<void> _playAllSamples() async {
    if (_sampleTourRunning) return;
    setState(() => _sampleTourRunning = true);
    try {
      for (final sound in OkeySound.values) {
        if (!mounted) return;
        try {
          await _preview.stop();
          await _preview.play(AssetSource(sound.assetPath));
        } catch (_) {
          // tek bir örnek çalınamazsa tur devam etsin
        }
        // Örnekler 0.2–1.2 sn arası; üst üste binmesinler diye bekleme.
        await Future<void>.delayed(const Duration(milliseconds: 1300));
      }
    } finally {
      if (mounted) setState(() => _sampleTourRunning = false);
    }
  }

  /// Çalma listesindeki bir parçanın play/pause durumunu değiştirir.
  /// Aynı parçaya tekrar basılırsa durdurur; başka bir parçaya basılırsa
  /// öncekini kesip yenisini başlatır.
  Future<void> _toggleMusicPreview(String key, String url) async {
    if (_playingTrackKey == key) {
      await _preview.stop();
      if (mounted) setState(() => _playingTrackKey = null);
      return;
    }
    try {
      await _preview.stop();
      await _preview.play(UrlSource(url));
      if (mounted) setState(() => _playingTrackKey = key);
    } catch (e) {
      if (!mounted) return;
      setState(() => _playingTrackKey = null);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Çalınamadı: ${OkeyAdminService.describeError(e)}'),
        ),
      );
    }
  }

  /// Çalma listesindeki tek bir parça için modern kart — play/pause
  /// düğmesi, istendiği gibi isminin HEMEN ÜSTÜNDE durur.
  Widget _musicTile(({String key, String name, String url}) t, int index) {
    final playing = _playingTrackKey == t.key;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: playing
              ? Colors.deepPurple.withValues(alpha: 0.5)
              : Colors.grey.withValues(alpha: 0.2),
        ),
        boxShadow: playing
            ? [
                BoxShadow(
                  color: Colors.deepPurple.withValues(alpha: 0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 3),
                ),
              ]
            : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Material(
                color: playing ? Colors.deepPurple : Colors.deepPurple.shade50,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => _toggleMusicPreview(t.key, t.url),
                  child: Padding(
                    padding: const EdgeInsets.all(9),
                    child: Icon(
                      playing ? Icons.pause : Icons.play_arrow,
                      size: 20,
                      color: playing ? Colors.white : Colors.deepPurple,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              IconButton(
                visualDensity: VisualDensity.compact,
                icon: const Icon(
                  Icons.delete_outline,
                  size: 20,
                  color: Colors.red,
                ),
                tooltip: 'Kaldır',
                onPressed: () => _confirmClear(t.key, t.name),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            t.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          const SizedBox(height: 2),
          Text(
            playing
                ? 'Şimdi çalıyor · Parça ${index + 1}'
                : 'Parça ${index + 1}',
            style: TextStyle(
              fontSize: 10.5,
              color: playing ? Colors.deepPurple : Colors.grey.shade600,
              fontWeight: playing ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  /// Tek bir ses olayı için kompakt kart (2 sütunlu grid içinde kullanılır).
  Widget _soundTile(OkeySound sound) {
    final label = _soundLabels[sound]!;
    final url = _sounds[sound.name];
    final busy = _busyKey == sound.name;
    final hasSound = url != null;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: hasSound
              ? Colors.green.withValues(alpha: 0.3)
              : Colors.grey.withValues(alpha: 0.25),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasSound ? Icons.volume_up : Icons.graphic_eq,
                size: 16,
                color: hasSound ? Colors.green : Colors.deepPurple,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            label.desc,
            style: TextStyle(fontSize: 10.5, color: Colors.grey.shade600),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          // Oyuncunun ŞU AN hangi sesi duyduğunu açıkça söyler. Eskiden
          // dosya yüklenmemiş kart "sessiz" gibi görünüyordu; oysa oyun
          // paketle gelen örneği çalıyor.
          Text(
            hasSound ? 'Yüklenen ses çalıyor' : 'Örnek ses çalıyor',
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: hasSound ? Colors.green.shade700 : Colors.deepPurple,
            ),
          ),
          const SizedBox(height: 6),
          if (busy)
            const Align(
              alignment: Alignment.centerRight,
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                // ÖRNEK her zaman dinlenebilir — yüklü ses olsa bile, admin
                // ikisini karşılaştırabilsin diye.
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(
                    Icons.graphic_eq,
                    size: 20,
                    color: Colors.deepPurple,
                  ),
                  tooltip: 'Örneği dinle',
                  onPressed: () => _playSample(sound),
                ),
                if (hasSound)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(Icons.play_arrow, size: 20),
                    tooltip: 'Yüklenen sesi dinle',
                    onPressed: () => _playPreview(url),
                  ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  icon: Icon(
                    hasSound ? Icons.change_circle : Icons.upload_file,
                    size: 20,
                  ),
                  tooltip: hasSound ? 'Değiştir' : 'Ses yükle',
                  onPressed: () => _upload(sound),
                ),
                if (hasSound)
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: Colors.red,
                    ),
                    tooltip: 'Kaldır',
                    onPressed: () => _clear(sound),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          color: Colors.blue.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Buraya yüklenen sesler tüm oyunculara anında uygulanır.\n'
                  'Ses yüklenmemiş olaylarda oyun, uygulamayla birlikte gelen '
                  'ÖRNEK sesi çalar; o da çalınamazsa titreşime düşer — oyun '
                  'her durumda çalışır.\n'
                  'Öneri: kısa (0.3–1.5 sn), 2 MB altı.\n'
                  'Desteklenen formatlar: mp3, m4a, wav, ogg, aac.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _sampleTourRunning ? null : _playAllSamples,
                    icon: Icon(
                      _sampleTourRunning
                          ? Icons.hourglass_top
                          : Icons.playlist_play,
                      size: 20,
                    ),
                    label: Text(
                      _sampleTourRunning
                          ? 'Örnekler çalıyor...'
                          : 'Tüm örnekleri dinle',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Liste alınamadıysa SÖYLENİR. Eskiden hata sessizce yutuluyordu ve
        // sekme "yüklü ses yok" gibi görünüyordu — oysa sorun ağ ya da izin
        // olabilir ve admin ikisini ayırt edemiyordu.
        if (_loadError != null)
          Card(
            color: Colors.red.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Ses listesi alınamadı: $_loadError',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton(
                    onPressed: _load,
                    child: const Text('Tekrar dene'),
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),

        // ÇALMA LİSTESİ — admin birden çok şarkı yükleyebilir.
        // Oyun bunları karışık sırayla çalar; oyuncu ayardan kapatabilir.
        Card(
          margin: const EdgeInsets.symmetric(vertical: 4),
          color: Colors.amber.shade50,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Icon(Icons.queue_music, color: Colors.deepPurple),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Arka Plan Şarkıları',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (_busyKey == 'music:add')
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    else
                      TextButton.icon(
                        onPressed: _addMusic,
                        icon: const Icon(Icons.add),
                        label: const Text('Şarkı Ekle'),
                      ),
                  ],
                ),
                Text(
                  _music.isEmpty
                      ? 'Henüz şarkı yok · en fazla 10 MB · '
                            'mp3, m4a, wav, ogg, aac'
                      : '${_music.length} şarkı · oyunda karışık sırayla çalar '
                            '(oyuncu ayardan kapatabilir)',
                  style: const TextStyle(fontSize: 11),
                ),
                const SizedBox(height: 4),
                ..._music.asMap().entries.map(
                  (e) => _musicTile(e.value, e.key),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),

        // Ses olayları, kategoriye göre gruplanmış katlanır bölümler halinde
        // — 10 tam genişlikte kart yerine kompakt 2 sütunlu ızgaralar.
        ..._SoundCategory.values.map((category) {
          final soundsInCategory = OkeySound.values
              .where((s) => _soundLabels[s]!.category == category)
              .toList();
          if (soundsInCategory.isEmpty) return const SizedBox.shrink();
          final catLabel = _categoryLabels[category]!;
          final loadedCount = soundsInCategory
              .where((s) => _sounds[s.name] != null)
              .length;

          return Card(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: Theme(
              data: Theme.of(
                context,
              ).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                initiallyExpanded: true,
                leading: Icon(catLabel.icon, color: Colors.deepPurple),
                title: Text(
                  catLabel.title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  loadedCount == soundsInCategory.length
                      ? '$loadedCount / ${soundsInCategory.length} ses yüklü'
                      : '$loadedCount / ${soundsInCategory.length} ses yüklü · '
                            'kalanlarda örnek ses çalıyor',
                  style: const TextStyle(fontSize: 11),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final columns = constraints.maxWidth > 480 ? 2 : 1;
                        return GridView.count(
                          crossAxisCount: columns,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          // Kartlarda artık bir de "hangi ses çalıyor"
                          // satırı var; oran biraz düşerek ona yer açar.
                          childAspectRatio: columns == 2 ? 1.75 : 2.2,
                          children: soundsInCategory
                              .map((s) => _soundTile(s))
                              .toList(),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ],
    );
  }
}
