import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';

import '../models/okey_models.dart';
import '../providers/okey_lobby_provider.dart';
import '../providers/okey_points_provider.dart';
import '../services/okey_ad_reward.dart';
import '../services/okey_guest_auth.dart';
import '../services/okey_invite_service.dart';
import '../services/okey_room_service.dart';
import '../theme/okey_theme.dart';
import '../theme/okey_ui.dart';
import '../widgets/okey_leaderboard_view.dart';
import 'okey_create_room_screen.dart';
import 'okey_game_screen.dart';
import 'okey_points_screen.dart';
import 'okey_room_screen.dart';

/// 101 Okey lobisi: puan durumu, devam eden oyun ve açık masalar.
///
/// ## Yeniden tasarım (2026-09)
///
/// Ekran artık [OkeyScreen] üzerine kuruludur; gövde bir `CustomScrollView`
/// olduğu için dikey taşma yapısal olarak imkânsızdır. Eski hali sabit bir
/// `Column` + `Expanded(ListView)` idi: üstteki üç bant (devam eden oyun,
/// aksiyonlar, hediye) aynı anda göründüğünde kısa ekranlarda liste
/// eziliyordu.
class OkeyLobbyScreen extends StatelessWidget {
  const OkeyLobbyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // OTURUM KAPISI, provider'lardan ÖNCE gelir. Sağlayıcılar kurulur
    // kurulmaz Supabase'e sorgu atar; oturum yokken bu sorgular RLS
    // yüzünden boş döner ve lobi "hiç masa yok" diye yalan söylerdi.
    return const _OkeySessionGate(child: _OkeyLobbyProviders());
  }
}

/// Lobinin sağlayıcıları — kapı geçildikten SONRA kurulur.
class _OkeyLobbyProviders extends StatelessWidget {
  const _OkeyLobbyProviders();

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => OkeyLobbyProvider()),
        ChangeNotifierProvider(create: (_) => OkeyPointsProvider()),
      ],
      child: const _OkeyLobbyView(),
    );
  }
}

/// MİSAFİR KAPISI — okeye girmek için bir oturum şarttır.
///
/// ## Neden okey diğer sekmeler gibi çalışamıyor
///
/// Uygulamanın geri kalanında misafir = oturum yok; misafir herkese açık
/// içeriği okur. Okey'de böyle bir şey mümkün değil: masadaki her satır
/// RLS ile `auth.uid()`'ye bağlı, koltuklar ve izleyiciler bir kullanıcı
/// kimliğine yazılıyor, taşlar SADECE sahibine görünüyor. Oturumsuz bir
/// istemci masayı göremez — hata bile almaz, sadece boş bir liste görür ve
/// bu, hatadan daha kötüdür.
///
/// Bu yüzden okey, oturumu olmayan kullanıcıya bir SEÇİM sunar: misafir
/// olarak devam et (anonim oturum) ya da giriş yap. Sessizce anonim hesap
/// açmak yerine sorulmasının sebebi: misafir kimliği cihaza bağlıdır,
/// kazanılan puanlar giriş yapılmadığı sürece başka bir cihaza taşınmaz.
class _OkeySessionGate extends StatefulWidget {
  final Widget child;

  const _OkeySessionGate({required this.child});

  @override
  State<_OkeySessionGate> createState() => _OkeySessionGateState();
}

class _OkeySessionGateState extends State<_OkeySessionGate> {
  bool _busy = false;
  String? _error;

  Future<void> _continueAsGuest() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await OkeyGuestAuth.signInAsGuest();
      if (mounted) setState(() => _busy = false);
    } on OkeyGuestAuthException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (OkeyGuestAuth.hasSession) return widget.child;

    return OkeyScreen(
      title: '101 Okey',
      slivers: [
        SliverFillRemaining(
          hasScrollBody: false,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.casino_outlined,
                  size: 64,
                  color: OkeyColors.accentGold,
                ),
                const SizedBox(height: OkeyUI.gap),
                const Text(
                  'Masaya oturmak ya da izlemek için bir kimlik gerekiyor.',
                  textAlign: TextAlign.center,
                  style: OkeyUI.title,
                ),
                const SizedBox(height: OkeyUI.gapSm),
                const Text(
                  'Misafir olarak devam edebilirsin. Kazandığın çipler bu '
                  'cihazda saklanır; başka bir cihazda kullanmak istersen '
                  'sonradan giriş yapman yeterli.',
                  textAlign: TextAlign.center,
                  style: OkeyUI.body,
                ),
                if (_error != null) ...[
                  const SizedBox(height: OkeyUI.gap),
                  Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Color(0xFFFF9AA6),
                      fontSize: 13,
                    ),
                  ),
                ],
                const SizedBox(height: OkeyUI.gapLg),
                SizedBox(
                  width: 280,
                  child: OkeyButton(
                    label: _busy ? 'BAĞLANILIYOR...' : 'MİSAFİR OLARAK DEVAM',
                    icon: Icons.person_outline,
                    tone: OkeyButtonTone.primary,
                    onPressed: _busy ? null : _continueAsGuest,
                  ),
                ),
                const SizedBox(height: OkeyUI.gapSm),
                SizedBox(
                  width: 280,
                  child: OkeyButton(
                    label: 'GİRİŞ YAP',
                    icon: Icons.login,
                    tone: OkeyButtonTone.ghost,
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(
                            context,
                          ).pushNamed('/login').then((_) => setState(() {})),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _OkeyLobbyView extends StatefulWidget {
  const _OkeyLobbyView();

  @override
  State<_OkeyLobbyView> createState() => _OkeyLobbyViewState();
}

class _OkeyLobbyViewState extends State<_OkeyLobbyView> {
  /// Reklam yükleniyor/gösteriliyor — düğme iki kez tetiklenmesin.
  bool _adBusy = false;

  Future<void> _watchAd() async {
    final provider = context.read<OkeyPointsProvider>();
    setState(() => _adBusy = true);
    try {
      await okeyWatchRewardedAd(context: context, provider: provider);
    } finally {
      if (mounted) setState(() => _adBusy = false);
    }
  }

  /// Skor tablosu — üst bardan açılır.
  ///
  /// Sağlayıcı `.value` ile GEÇİRİLİR: lobide zaten bir cüzdan sağlayıcısı
  /// var, yeni bir tane kurmak aynı veriyi ikinci kez ağdan okumak olurdu.
  void _openLeaderboard() {
    final points = context.read<OkeyPointsProvider>();
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ChangeNotifierProvider.value(
          value: points,
          child: const OkeyLeaderboardScreen(),
        ),
      ),
    );
  }

  /// OTOMATİK EŞLEŞTİRME — masa seçtirmeden oturt.
  ///
  /// Ayar sormaz: varsayılan masa (katlamasız, eşsiz, yardımlı, 3 el, en
  /// düşük giriş) ile eşleştirir. Ayarını seçmek isteyen MASA AÇ'ı
  /// kullanır — "hızlı" bir akışın ilk adımı bir ayar ekranı olamaz.
  Future<void> _quickMatch(BuildContext context) async {
    final lobby = context.read<OkeyLobbyProvider>();
    final roomId = await lobby.quickMatch();
    if (!context.mounted) return;
    if (roomId == null) {
      _toast(context, lobby.error ?? 'Eşleştirme yapılamadı.');
      return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => OkeyRoomScreen(roomId: roomId)));
    if (context.mounted) lobby.refresh();
  }

  Future<void> _createRoom(BuildContext context) async {
    final choice = await Navigator.of(context).push<OkeyRoomOptions>(
      MaterialPageRoute(builder: (_) => const OkeyCreateRoomScreen()),
    );
    if (choice == null || !context.mounted) return;

    final lobby = context.read<OkeyLobbyProvider>();
    final points = context.read<OkeyPointsProvider>();
    final roomId = await lobby.createRoom(
      isPrivate: choice.isPrivate,
      gameMode: choice.gameMode,
      teamMode: choice.teamMode,
      assistMode: choice.assistMode,
      totalHands: choice.totalHands,
      entryFee: choice.entryFee,
    );
    if (!context.mounted) return;

    if (roomId == null) {
      final err = lobby.error ?? 'Oda kurulamadı';
      _toast(
        context,
        err.contains('insufficient_points')
            ? 'Yeterli çipin yok. Hediye al ya da reklam izle.'
            : err,
      );
      return;
    }

    points.refresh();
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => OkeyRoomScreen(roomId: roomId)));
  }

  Future<void> _joinByCode(BuildContext context) async {
    final controller = TextEditingController();
    final code = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: OkeyUI.cardFill,
        title: const Text('Davet koduyla katıl', style: OkeyUI.title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          style: const TextStyle(color: OkeyUI.text),
          decoration: const InputDecoration(
            hintText: 'Örn. A1B2C3',
            hintStyle: TextStyle(color: OkeyUI.textFaint),
            prefixIcon: Icon(Icons.vpn_key, color: OkeyUI.textDim),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Katıl'),
          ),
        ],
      ),
    );
    if (code == null || code.isEmpty || !context.mounted) return;

    final lobby = context.read<OkeyLobbyProvider>();
    final roomId = await lobby.joinRoomByCode(code);
    if (!context.mounted) return;

    if (roomId == null) {
      _toast(context, lobby.error ?? 'Odaya katılınamadı');
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => OkeyRoomScreen(roomId: roomId)));
  }

  /// Daveti kabul et = masaya OTUR ve bekleme odasını aç.
  ///
  /// Oturma sunucuda daveti işaretlemekle aynı işlemde yapılır; buradan
  /// dönen oda kimliği "gerçekten oturdum" demektir. Bu yüzden ekstra bir
  /// `joinRoom` çağrısı YOKTUR — ikinci çağrı, davet edene giden "kabul
  /// edildi" bildirimiyle gerçek durumun ayrışmasına kapı açardı.
  Future<void> _acceptInvite(
    BuildContext context,
    OkeyRoomInvite invite,
  ) async {
    final lobby = context.read<OkeyLobbyProvider>();
    final points = context.read<OkeyPointsProvider>();
    final roomId = await lobby.acceptInvite(invite.inviteId);
    if (!context.mounted) return;

    if (roomId == null) {
      _toast(context, lobby.error ?? 'Davete katılınamadı');
      return;
    }
    points.refresh();
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => OkeyRoomScreen(roomId: roomId)));
  }

  Future<void> _joinRoom(BuildContext context, OkeyRoom room) async {
    final lobby = context.read<OkeyLobbyProvider>();
    final seat = await lobby.joinRoom(roomId: room.id);
    if (!context.mounted) return;

    if (seat == null) {
      final err = lobby.error ?? 'Odaya katılınamadı';
      _toast(
        context,
        err.contains('room_full')
            ? 'Masa doldu.'
            : err.contains('insufficient_points')
            ? 'Bu masa için yeterli çipin yok '
                  '(${room.tableStake} gerekli).'
            : err,
      );
      lobby.refresh();
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => OkeyRoomScreen(roomId: room.id)));
  }

  static void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  /// Masayı İZLEMEYE başla.
  ///
  /// İzleyici kaydı ÖNCE atılır, masa ekranı SONRA açılır. Sıra tersine
  /// olsaydı ekran açılıp RLS yüzünden boş bir masa gösterirdi: izleme izni
  /// tam olarak o kayıttan doğuyor.
  Future<void> _watchRoom(BuildContext context, OkeyRoom room) async {
    final matchId = room.currentMatchId;
    if (matchId == null) {
      _toast(context, 'Bu masada şu an oynanan bir el yok.');
      return;
    }
    try {
      await OkeyRoomService().watchRoom(room.id);
    } catch (e) {
      if (!context.mounted) return;
      final raw = e.toString();
      _toast(
        context,
        raw.contains('already_seated')
            ? 'Bu masada zaten oturuyorsun.'
            : raw.contains('room_is_private')
            ? 'Özel masalar izlenemez.'
            : 'Masa izlenemedi: $raw',
      );
      return;
    }
    if (!context.mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => OkeyGameScreen(matchId: matchId, spectator: true),
      ),
    );
    if (!context.mounted) return;
    await context.read<OkeyLobbyProvider>().refresh();
  }

  @override
  Widget build(BuildContext context) {
    final lobby = context.watch<OkeyLobbyProvider>();
    final points = context.watch<OkeyPointsProvider>();

    return OkeyScreen(
      title: '101 Okey',
      onRefresh: () async {
        await lobby.refresh();
        await points.refresh();
      },
      actions: [
        _PointsChip(points: points),
        // SKOR TABLOSU üst barda: eskiden yalnızca puan ekranının ikinci
        // sekmesindeydi, yani sıralamayı görmek için iki dokunuş ve bir
        // ekran değişimi gerekiyordu.
        IconButton(
          icon: const Icon(Icons.leaderboard),
          tooltip: 'Skor tablosu',
          onPressed: _openLeaderboard,
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Yenile',
          onPressed: () {
            lobby.refresh();
            points.refresh();
          },
        ),
      ],
      slivers: [
        if (lobby.activeRoom != null)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, OkeyUI.gap),
              child: _ResumeCard(room: lobby.activeRoom!),
            ),
          ),

        // ARKADAŞ DAVETLERİ — bildirimi kaçıranın daveti görebileceği yer.
        // En üstte durur: davet, lobideki her şeyden daha zaman duyarlıdır
        // (masa dolar ya da oyun başlar, davet düşer).
        if (lobby.pendingInvites.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: const OkeySectionHeader(label: 'Seni davet edenler'),
            ),
          ),
          SliverList.separated(
            itemCount: lobby.pendingInvites.length,
            separatorBuilder: (_, _) => const SizedBox(height: OkeyUI.gapSm),
            itemBuilder: (_, i) => Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: _InviteCard(
                invite: lobby.pendingInvites[i],
                onAccept: () => _acceptInvite(context, lobby.pendingInvites[i]),
                onDecline: () =>
                    lobby.declineInvite(lobby.pendingInvites[i].inviteId),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: OkeyUI.gap)),
        ],

        // BİRİNCİL EYLEMLER — ekranın en üstünde, tek satır.
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Column(
              children: [
                // OTOMATİK EŞLEŞTİR — BİRİNCİL eylem (kullanıcı isteği,
                // 2026-09-07). "Hangi masa?" ve "kaç kişi bekleyeceğim?"
                // sorularını oyuncuya hiç sormaz: tek dokunuşla ya var olan
                // bir masaya oturur ya da yeni masa açılır ve süre dolunca
                // boş koltuklar botlarla dolar.
                //
                // MASA AÇ'ın ÜSTÜNDE ve tam genişlikte: oyuncuların çoğu
                // "oynamak" istiyor, "masa kurmak" değil. Masa kurmak artık
                // ikincil — ayarlarını kendi seçmek isteyenin yolu.
                SizedBox(
                  width: double.infinity,
                  child: OkeyButton(
                    label: 'OTOMATİK EŞLEŞTİR',
                    icon: Icons.bolt,
                    tone: OkeyButtonTone.primary,
                    onPressed: () => _quickMatch(context),
                  ),
                ),
                const SizedBox(height: OkeyUI.gapSm),
                Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: OkeyButton(
                        label: 'MASA AÇ',
                        icon: Icons.add_circle_outline,
                        tone: OkeyButtonTone.secondary,
                        onPressed: () => _createRoom(context),
                      ),
                    ),
                    const SizedBox(width: OkeyUI.gapSm),
                    Expanded(
                      flex: 2,
                      child: OkeyButton(
                        label: 'KOD',
                        icon: Icons.vpn_key,
                        tone: OkeyButtonTone.ghost,
                        onPressed: () => _joinByCode(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // PUAN KAZAN — hediye ve reklam artık HER ZAMAN burada.
        //
        // Eskiden hediye kartı yalnızca hazır olduğunda görünüyor, "reklam
        // izle" ise puan ekranının içinde saklıydı. Oyuncunun puanı bittiği
        // an yapabileceği iki şey de bir başka ekranın arkasındaydı.
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, OkeyUI.gap, 14, 0),
            child: Row(
              children: [
                Expanded(
                  child: _EarnCard(
                    icon: Icons.card_giftcard,
                    color: const Color(0xFF9CCC65),
                    title: 'Saatlik hediye',
                    subtitle: points.canClaimGift
                        ? '${points.wallet.hourlyGiftPoints} çip hazır'
                        : points.giftCountdownText,
                    actionLabel: points.canClaimGift ? 'AL' : 'BEKLE',
                    enabled: points.canClaimGift && !points.isBusy,
                    busy: points.isBusy,
                    onTap: points.claimHourlyGift,
                  ),
                ),
                const SizedBox(width: OkeyUI.gapSm),
                Expanded(
                  child: _EarnCard(
                    icon: Icons.ondemand_video,
                    color: const Color(0xFF80D8FF),
                    title: 'Reklam izle',
                    subtitle: '${points.wallet.adRewardPoints} çip',
                    actionLabel: 'İZLE',
                    enabled: !_adBusy && !points.isBusy,
                    busy: _adBusy,
                    onTap: _watchAd,
                  ),
                ),
              ],
            ),
          ),
        ),

        // İZLENEBİLİR MASALAR — oyunu SÜREN masalar. Açık masaların üstünde
        // durur çünkü oyun başlamış bir masayı izlemek anında mümkündür;
        // açık bir masada ise üç kişi daha beklemek gerekir.
        if (lobby.liveRooms.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, OkeyUI.gap, 14, 0),
              child: OkeySectionHeader(
                label: 'Canlı masalar — izle',
                trailing: OkeyPill(text: '${lobby.liveRooms.length}'),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            sliver: SliverList.separated(
              itemCount: lobby.liveRooms.length,
              separatorBuilder: (_, _) => const SizedBox(height: OkeyUI.gapSm),
              itemBuilder: (context, i) => _LiveRoomCard(
                room: lobby.liveRooms[i],
                onWatch: () => _watchRoom(context, lobby.liveRooms[i]),
              ),
            ),
          ),
        ],

        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, OkeyUI.gap, 14, 0),
            child: OkeySectionHeader(
              label: 'Açık masalar',
              trailing: lobby.rooms.isEmpty
                  ? null
                  : OkeyPill(text: '${lobby.rooms.length}'),
            ),
          ),
        ),

        if (lobby.isLoading && lobby.rooms.isEmpty)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: CircularProgressIndicator(color: OkeyColors.accentGold),
              ),
            ),
          )
        else if (lobby.rooms.isEmpty)
          SliverToBoxAdapter(
            child: OkeyEmptyState(
              icon: Icons.casino_outlined,
              title: 'Açık masa yok',
              message: 'İlk masayı sen aç, oyuncular gelsin.',
              action: SizedBox(
                width: 220,
                child: OkeyButton(
                  label: 'MASA AÇ',
                  icon: Icons.add_circle_outline,
                  tone: OkeyButtonTone.primary,
                  onPressed: () => _createRoom(context),
                ),
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            sliver: SliverList.separated(
              itemCount: lobby.rooms.length,
              separatorBuilder: (_, _) => const SizedBox(height: OkeyUI.gapSm),
              itemBuilder: (context, i) =>
                  _RoomCard(
                        room: lobby.rooms[i],
                        onJoin: () => _joinRoom(context, lobby.rooms[i]),
                      )
                      // Sıralı giriş; gecikme 6 karttan sonra tavan yapar ki
                      // uzun listelerde son kartlar dakikalarca beklemesin.
                      .animate(delay: (40 * i.clamp(0, 6)).ms)
                      .fadeIn(duration: 250.ms)
                      .slideY(begin: 0.06, end: 0, curve: Curves.easeOut),
            ),
          ),
      ],
    );
  }
}

/// AppBar'daki puan göstergesi — dokununca puan ekranına gider.
class _PointsChip extends StatelessWidget {
  final OkeyPointsProvider points;

  const _PointsChip({required this.points});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () async {
            await Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const OkeyPointsScreen()));
            if (context.mounted) points.refresh();
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: OkeyUI.goldGradient),
              borderRadius: BorderRadius.circular(20),
            ),
            // Puan 7 haneye çıkabilir; kutu büyümek yerine metin küçülür.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.stars, size: 15, color: OkeyUI.onGold),
                  const SizedBox(width: 5),
                  Text(
                    '${points.points}',
                    maxLines: 1,
                    style: const TextStyle(
                      color: OkeyUI.onGold,
                      fontWeight: FontWeight.w900,
                      fontSize: 13,
                    ),
                  ),
                  if (points.canClaimGift) ...[
                    const SizedBox(width: 5),
                    Container(
                      width: 7,
                      height: 7,
                      decoration: const BoxDecoration(
                        color: Color(0xFFD32F2F),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Devam eden oyunun var" kartı.
class _ResumeCard extends StatelessWidget {
  final OkeyRoom room;

  const _ResumeCard({required this.room});

  @override
  Widget build(BuildContext context) {
    return OkeyCard(
      highlighted: true,
      onTap: () {
        final matchId = room.currentMatchId;
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => room.status == 'in_progress' && matchId != null
                ? OkeyGameScreen(matchId: matchId)
                : OkeyRoomScreen(roomId: room.id),
          ),
        );
      },
      child: Row(
        children: [
          const Icon(
            Icons.play_circle_fill,
            color: OkeyColors.accentGold,
            size: 30,
          ),
          const SizedBox(width: OkeyUI.gap),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Devam eden oyunun var',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OkeyUI.title,
                ),
                SizedBox(height: 2),
                Text(
                  'Kaldığın yerden devam et',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OkeyUI.caption,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: OkeyUI.textDim),
        ],
      ),
    );
  }
}

/// Bana gelen bir masa daveti: kim çağırdı, masanın bedeli ne, katıl/reddet.
///
/// MASA PUANI kartın üstünde durur: kabul etmek cüzdandan puan düşürür
/// (join_okey_room tahsilatı) ve bunu ancak masaya oturduktan sonra görmek
/// kötü bir sürpriz olurdu.
class _InviteCard extends StatelessWidget {
  final OkeyRoomInvite invite;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  const _InviteCard({
    required this.invite,
    required this.onAccept,
    required this.onDecline,
  });

  @override
  Widget build(BuildContext context) {
    return OkeyCard(
      highlighted: true,
      child: Column(
        children: [
          Row(
            children: [
              OkeyAvatar(
                url: invite.inviterAvatar,
                size: 40,
                highlighted: true,
              ),
              const SizedBox(width: OkeyUI.gap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${invite.inviterName} seni davet etti',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OkeyUI.title,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${invite.seatedCount}/4 koltuk dolu · '
                      '${invite.totalHands} el · '
                      '${invite.teamMode == 'esli' ? 'Eşli' : 'Eşsiz'}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OkeyUI.caption,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: OkeyUI.gapSm),
              OkeyPill(text: '${invite.tableStake} çip', icon: Icons.toll),
            ],
          ),
          const SizedBox(height: OkeyUI.gap),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: OkeyButton(
                  label: 'KATIL',
                  icon: Icons.login,
                  tone: OkeyButtonTone.primary,
                  onPressed: onAccept,
                ),
              ),
              const SizedBox(width: OkeyUI.gapSm),
              Expanded(
                flex: 2,
                child: OkeyButton(
                  label: 'REDDET',
                  icon: Icons.close,
                  tone: OkeyButtonTone.ghost,
                  onPressed: onDecline,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoomCard extends StatelessWidget {
  final OkeyRoom room;
  final VoidCallback onJoin;

  const _RoomCard({required this.room, required this.onJoin});

  @override
  Widget build(BuildContext context) {
    return OkeyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OkeyAvatar(url: room.creatorAvatar, size: 38),
              const SizedBox(width: OkeyUI.gap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.creatorName ?? 'Oyuncu',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OkeyUI.title,
                    ),
                    const SizedBox(height: 4),
                    _SeatDots(
                      occupied: room.occupiedSeats,
                      bots: room.botCount,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: OkeyUI.gapSm),
              // MASA PUANI = el başına puan × el sayısı. Rozette ÇARPIM
              // yazar: cüzdandan düşecek olan sayı budur, el başına puan
              // değil (kullanıcı isteği, 2026-09-05).
              if (room.tableStake > 0)
                OkeyPill(text: '${room.tableStake}', icon: Icons.stars),
            ],
          ),
          const SizedBox(height: OkeyUI.gap),
          // Etiketler SARMALI akar: dört etiket dar ekranda alt satıra iner,
          // satırı taşırmaz.
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              OkeyPill(
                text: room.gameMode == 'katlamali' ? 'Katlamalı' : 'Katlamasız',
                color: const Color(0xFFFF8A80),
              ),
              OkeyPill(
                text: room.teamMode == 'esli' ? 'Eşli' : 'Eşsiz',
                color: const Color(0xFF80D8FF),
              ),
              OkeyPill(
                text: room.assistMode == 'yardimsiz' ? 'Yardımsız' : 'Yardımlı',
                color: const Color(0xFFB9F6CA),
              ),
              OkeyPill(
                text: '${room.totalHands} el',
                color: const Color(0xFFE1BEE7),
              ),
            ],
          ),
          const SizedBox(height: OkeyUI.gap),
          OkeyButton(
            label: 'KATIL',
            icon: Icons.login,
            tone: OkeyButtonTone.primary,
            onPressed: onJoin,
          ),
        ],
      ),
    );
  }
}

/// Oyunu SÜREN bir masa — oturulmaz, İZLENİR.
///
/// Açık masa kartından bilerek farklı okunur: birincil eylem "KATIL" değil
/// "İZLE"dir ve kartın üstünde canlı olduğunu söyleyen bir rozet durur.
/// İkisi aynı görünseydi, dolu bir masaya katılmaya çalışan oyuncu her
/// seferinde reddedilirdi.
class _LiveRoomCard extends StatelessWidget {
  final OkeyRoom room;
  final VoidCallback onWatch;

  const _LiveRoomCard({required this.room, required this.onWatch});

  @override
  Widget build(BuildContext context) {
    return OkeyCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              OkeyAvatar(url: room.creatorAvatar, size: 38),
              const SizedBox(width: OkeyUI.gap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      room.creatorName ?? 'Oyuncu',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OkeyUI.title,
                    ),
                    const SizedBox(height: 4),
                    _SeatDots(
                      occupied: room.occupiedSeats,
                      bots: room.botCount,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: OkeyUI.gapSm),
              const OkeyPill(
                text: 'CANLI',
                icon: Icons.play_circle_fill,
                color: Color(0xFFFF8A80),
              ),
            ],
          ),
          const SizedBox(height: OkeyUI.gap),
          Wrap(
            spacing: 5,
            runSpacing: 5,
            children: [
              OkeyPill(
                text: room.gameMode == 'katlamali' ? 'Katlamalı' : 'Katlamasız',
                color: const Color(0xFFFF8A80),
              ),
              OkeyPill(
                text: room.teamMode == 'esli' ? 'Eşli' : 'Eşsiz',
                color: const Color(0xFF80D8FF),
              ),
              if (room.spectatorCount > 0)
                OkeyPill(
                  text: '${room.spectatorCount} izleyici',
                  icon: Icons.visibility,
                  color: const Color(0xFFB9F6CA),
                ),
            ],
          ),
          const SizedBox(height: OkeyUI.gap),
          OkeyButton(
            label: 'İZLE',
            icon: Icons.visibility,
            tone: OkeyButtonTone.ghost,
            onPressed: onWatch,
          ),
        ],
      ),
    );
  }
}

/// 4 koltuğun doluluk göstergesi: dolu = yeşil, boş = soluk.
///
/// ## Neden bot ayrımı YOK (2026-09, kullanıcı isteği)
///
/// Eskiden bot koltukları gri çiziliyor ve yanına "(3 bot)" yazılıyordu.
/// Yani oyuncu masaya oturmadan önce kaç rakibinin bot olduğunu görüyordu.
/// Botlar artık masada gerçek oyuncular gibi göründüğü için lobide de
/// ayrışmazlar; [bots] parametresi yalnızca doluluk hesabında kalır.
class _SeatDots extends StatelessWidget {
  final int occupied;
  final int bots;

  const _SeatDots({required this.occupied, required this.bots});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        ...List.generate(4, (i) {
          final c = i < occupied ? const Color(0xFFB9F6CA) : OkeyUI.textFaint;
          return Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 4),
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          );
        }),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            '$occupied/4',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: OkeyUI.caption,
          ),
        ),
      ],
    );
  }
}

/// Lobideki PUAN KAZAN kartı: saatlik hediye ve reklam.
///
/// ## Neden lobide
///
/// İkisi de eskiden puan ekranının içindeydi; hediye kartı lobide yalnızca
/// hazır olduğunda beliriyordu. Yani oyuncunun puanı bittiği an yapabileceği
/// iki şey de bir başka ekranın arkasındaydı ve "puanım yok" ile "puan nasıl
/// alınır" arasında üç dokunuş vardı.
///
/// Kart hazır olmadığında GİZLENMEZ, sönükleşir ve ne zaman hazır olacağını
/// yazar: kaybolan bir düğme, bir daha ne zaman geleceğini söylemez.
class _EarnCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final String actionLabel;
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  const _EarnCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = enabled ? color : OkeyUI.textFaint;

    return OkeyCard(
      onTap: enabled ? onTap : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, color: fg, size: 20),
              const SizedBox(width: OkeyUI.gapSm),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OkeyUI.title,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: OkeyUI.caption,
          ),
          const SizedBox(height: OkeyUI.gapSm),
          SizedBox(
            width: double.infinity,
            child: busy
                ? const Center(
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    decoration: BoxDecoration(
                      color: fg.withValues(alpha: enabled ? 0.18 : 0.08),
                      borderRadius: BorderRadius.circular(OkeyUI.radiusSm),
                      border: Border.all(
                        color: fg.withValues(alpha: enabled ? 0.6 : 0.25),
                      ),
                    ),
                    child: Text(
                      actionLabel,
                      maxLines: 1,
                      style: TextStyle(
                        color: fg,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.6,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
