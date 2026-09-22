import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/okey_models.dart';
import '../providers/okey_lobby_provider.dart';
import '../providers/okey_points_provider.dart';
import '../services/okey_ad_reward.dart';
import '../services/okey_guest_auth.dart';
import '../services/okey_invite_service.dart';
import '../services/okey_profile_service.dart';
import '../services/okey_room_service.dart';
import '../services/okey_sound_service.dart';
import '../theme/okey_table_theme.dart';
import '../theme/okey_theme.dart';
import '../theme/okey_ui.dart';
import '../widgets/okey_coin_rain.dart';
import '../widgets/okey_leaderboard_view.dart';
import '../widgets/okey_profile_sheet.dart';
import '../widgets/okey_table_settings_dialog.dart';
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
                Icon(
                  Icons.casino_outlined,
                  size: 64,
                  color: OkeyUI.brass,
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

  /// Kendi profil kartım (başlıktaki ad/avatar için).
  OkeyProfileCard? _me;

  /// Masa listesi filtresi.
  _TableFilter _filter = _TableFilter.all;

  /// "Masalar" başlığı — alt çubuktaki Masalar öğesi buraya kaydırır.
  final GlobalKey _tablesKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // MASA TEMASI — masaya oturmadan da okunur ki lobideki "Tema" düğmesi
    // ilk açılışta kayıtlı seçimi göstersin (bkz. OkeyGameProvider._init'te
    // aynı çağrı; ikinci çağrılarda kendini kısa devre yapar).
    unawaited(OkeyTableThemePrefs.instance.load());
    unawaited(_loadMe());
  }

  /// Masaya oturmadan da tema seçilebilsin diye lobiden açılan kısayol
  /// (kullanıcı isteği, 2026-09-14: "oyuncu tema seçebilsin ayardan").
  void _openThemePicker() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: OkeyColors.screenBackground,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        title: const Text('Masa teması', style: TextStyle(color: Colors.white)),
        content: const SizedBox(width: 420, child: OkeyTableThemePicker()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

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
    // Messenger ilk await'ten ONCE yakalanir; bkz. [_toast].
    final messenger = ScaffoldMessenger.of(context);
    final lobby = context.read<OkeyLobbyProvider>();
    final roomId = await lobby.quickMatch();
    if (!context.mounted) return;
    if (roomId == null) {
      _toast(messenger, lobby.error ?? 'Eşleştirme yapılamadı.');
      return;
    }
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => OkeyRoomScreen(roomId: roomId)));
    if (context.mounted) lobby.refresh();
  }

  Future<void> _createRoom(BuildContext context) async {
    // Messenger ilk await'ten ONCE yakalanir; bkz. [_toast].
    final messenger = ScaffoldMessenger.of(context);
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
        messenger,
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
    // Messenger ilk await'ten ONCE yakalanir; bkz. [_toast].
    final messenger = ScaffoldMessenger.of(context);
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
      _toast(messenger, lobby.error ?? 'Odaya katılınamadı');
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
    // Messenger ilk await'ten ONCE yakalanir; bkz. [_toast].
    final messenger = ScaffoldMessenger.of(context);
    final lobby = context.read<OkeyLobbyProvider>();
    final points = context.read<OkeyPointsProvider>();
    final roomId = await lobby.acceptInvite(invite.inviteId);
    if (!context.mounted) return;

    if (roomId == null) {
      _toast(messenger, lobby.error ?? 'Davete katılınamadı');
      return;
    }
    points.refresh();
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => OkeyRoomScreen(roomId: roomId)));
  }

  Future<void> _joinRoom(BuildContext context, OkeyRoom room) async {
    // Messenger ilk await'ten ONCE yakalanir; bkz. [_toast].
    final messenger = ScaffoldMessenger.of(context);
    final lobby = context.read<OkeyLobbyProvider>();
    final seat = await lobby.joinRoom(roomId: room.id);
    if (!context.mounted) return;

    if (seat == null) {
      final err = lobby.error ?? 'Odaya katılınamadı';
      _toast(
        messenger,
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

  /// Mesaji, cagiran metodun BASINDA yakalanmis messenger uzerinden gosterir.
  ///
  /// Eskiden `ScaffoldMessenger.of(context)` burada, yani await'lerden SONRA
  /// cagriliyordu. Kullanici bu arada lobiden cikarsa element deactive olur;
  /// `context.mounted` o pencerede hala true dondugu icin ustteki korumalar
  /// tutmuyor ve arama "Looking up a deactivated widget's ancestor is unsafe"
  /// atiyordu.
  static void _toast(ScaffoldMessengerState messenger, String message) {
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }

  /// Masayı İZLEMEYE başla.
  ///
  /// İzleyici kaydı ÖNCE atılır, masa ekranı SONRA açılır. Sıra tersine
  /// olsaydı ekran açılıp RLS yüzünden boş bir masa gösterirdi: izleme izni
  /// tam olarak o kayıttan doğuyor.
  Future<void> _watchRoom(BuildContext context, OkeyRoom room) async {
    // Messenger ilk await'ten ONCE yakalanir; bkz. [_toast].
    final messenger = ScaffoldMessenger.of(context);
    final matchId = room.currentMatchId;
    if (matchId == null) {
      _toast(messenger, 'Bu masada şu an oynanan bir el yok.');
      return;
    }
    try {
      await OkeyRoomService().watchRoom(room.id);
    } catch (e) {
      if (!context.mounted) return;
      final raw = e.toString();
      _toast(
        messenger,
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

  /// Kendi ad/avatarım: başlık satırı için. Okunamazsa "Oyuncu" görünür —
  /// kimlik süstür, lobi bu yüzden beklemez ya da hata göstermez.
  /// Oturumdaki kullanıcının kimliği; Supabase hazır değilse (widget testleri)
  /// ya da oturum yoksa null.
  static String? _myUserId() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadMe() async {
    final uid = _myUserId();
    if (uid == null) return;
    try {
      final card = await OkeyProfileService().card(userId: uid);
      if (mounted) setState(() => _me = card);
    } catch (_) {
      // bilerek sessiz: bkz. yukarıdaki not.
    }
  }

  Future<void> _openPoints() async {
    final points = context.read<OkeyPointsProvider>();
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const OkeyPointsScreen()));
    if (mounted) points.refresh();
  }

  void _openMyProfile() {
    final uid = _myUserId();
    if (uid == null) return;
    OkeyProfileSheet.show(
      context,
      userId: uid,
      name: _me?.displayName,
      avatarUrl: _me?.avatarUrl,
    );
  }

  /// Alt çubuktaki "Masalar": masa listesinin başlığına kaydırır.
  void _scrollToTables() {
    final ctx = _tablesKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final lobby = context.watch<OkeyLobbyProvider>();
    final points = context.watch<OkeyPointsProvider>();
    final liveRooms = lobby.liveRooms.where(_filter.matches).toList();
    final openRooms = lobby.rooms.where(_filter.matches).toList();
    final nothingListed = liveRooms.isEmpty && openRooms.isEmpty;

    // BONUS lobiden de alınabiliyor; çip yağmuru masaya özel değil
    // (bkz. OkeyCoinRain).
    return OkeyCoinRain(
      child: OkeyScreen(
        title: '101 Okey',
        // Kimlik + çip hapı ekranın ilk satırıdır; sistem AppBar'ı yerine
        // slivers içinde çizilir (bkz. _LobbyHeader).
        showAppBar: false,
        onRefresh: () async {
          await lobby.refresh();
          await points.refresh();
        },
        // SALON GEZİNME ÇUBUĞU — eskiden üst çubukta dört ikon vardı
        // (puan, tema, skor, yenile). "Yenile" aşağı çekmede zaten var; skor
        // tablosu ve puan artık burada, tema başlıktaki tek ikonda.
        bottomNav: OkeyBottomNav(
          items: [
            OkeyNavItem(
              icon: Icons.casino_outlined,
              label: 'Salon',
              selected: true,
              onTap: () {},
            ),
            OkeyNavItem(
              icon: Icons.grid_view_rounded,
              label: 'Masalar',
              onTap: _scrollToTables,
            ),
            OkeyNavItem(
              icon: Icons.emoji_events_outlined,
              label: 'Sıralama',
              onTap: _openLeaderboard,
            ),
            OkeyNavItem(
              icon: Icons.person_outline,
              label: 'Ben',
              onTap: _openMyProfile,
            ),
          ],
        ),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, OkeyUI.gap),
              child: _LobbyHeader(
                me: _me,
                points: points,
                onThemeTap: _openThemePicker,
                onPointsTap: _openPoints,
                onProfileTap: _openMyProfile,
              ),
            ),
          ),

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
                  onAccept: () =>
                      _acceptInvite(context, lobby.pendingInvites[i]),
                  onDecline: () =>
                      lobby.declineInvite(lobby.pendingInvites[i].inviteId),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: OkeyUI.gap)),
          ],

          // BİRİNCİL EYLEM — "Hemen oyna". Oyuncuların çoğu oynamak istiyor,
          // masa kurmak değil (kullanıcı isteği, 2026-09-07); hangi masa ve
          // kaç kişi bekleneceği sorusu hiç sorulmaz. Masa kurmak ve kodla
          // katılmak ikincil, hemen altında.
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Column(
                children: [
                  _HeroCard(onQuickMatch: () => _quickMatch(context)),
                  const SizedBox(height: OkeyUI.gapSm),
                  Row(
                    children: [
                      Expanded(
                        flex: 3,
                        child: OkeyButton(
                          label: 'MASA KUR',
                          icon: Icons.add_circle_outline,
                          tone: OkeyButtonTone.secondary,
                          onPressed: () => _createRoom(context),
                        ),
                      ),
                      const SizedBox(width: OkeyUI.gapSm),
                      Expanded(
                        flex: 2,
                        child: OkeyButton(
                          label: 'KODLA',
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

          // PUAN KAZAN — hediye ve reklam HER ZAMAN burada (puanı biten
          // oyuncunun yapabileceği iki şey başka bir ekranın arkasında
          // kalmasın). Hazır olmayan kart gizlenmez, ne zaman hazır
          // olacağını yazar.
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
                      enabled: points.canClaimGift && !points.isBusy,
                      busy: points.isBusy,
                      onTap: points.claimHourlyGift,
                    ),
                  ),
                  const SizedBox(width: OkeyUI.gapSm),
                  Expanded(
                    child: _EarnCard(
                      icon: Icons.play_arrow_rounded,
                      color: const Color(0xFF80D8FF),
                      title: 'Reklam izle',
                      subtitle: '+${points.wallet.adRewardPoints} çip',
                      enabled: !_adBusy && !points.isBusy,
                      busy: _adBusy,
                      onTap: _watchAd,
                    ),
                  ),
                ],
              ),
            ),
          ),

          // MASALAR — canlı (izlenebilir) ve açık (oturulabilir) tek listede,
          // tek filtreyle. Canlı masalar üstte: oyun başlamış bir masayı
          // izlemek anında mümkün, açık masada üç kişi daha beklenir.
          SliverToBoxAdapter(
            child: Padding(
              key: _tablesKey,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: OkeySectionHeader(
                label: 'Masalar',
                trailing: (liveRooms.length + openRooms.length) == 0
                    ? null
                    : OkeyPill(
                        text:
                            '${liveRooms.length} canlı · ${openRooms.length} açık',
                      ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _FilterChips(
              selected: _filter,
              onSelect: (f) => setState(() => _filter = f),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: OkeyUI.gapSm)),

          if (lobby.isLoading && lobby.rooms.isEmpty && lobby.liveRooms.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Center(
                  child: CircularProgressIndicator(
                    color: OkeyUI.brass,
                  ),
                ),
              ),
            )
          else if (nothingListed)
            SliverToBoxAdapter(
              child: OkeyEmptyState(
                icon: Icons.casino_outlined,
                title: _filter == _TableFilter.all
                    ? 'Açık masa yok'
                    : 'Bu türde masa yok',
                message: 'İlk masayı sen kur, oyuncular gelsin.',
                action: SizedBox(
                  width: 220,
                  child: OkeyButton(
                    label: 'MASA KUR',
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
                itemCount: liveRooms.length + openRooms.length,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: OkeyUI.gapSm),
                itemBuilder: (context, i) {
                  final live = i < liveRooms.length;
                  final room = live
                      ? liveRooms[i]
                      : openRooms[i - liveRooms.length];
                  return _TableCard(
                        room: room,
                        live: live,
                        onTap: () => live
                            ? _watchRoom(context, room)
                            : _joinRoom(context, room),
                      )
                      // Sıralı giriş; gecikme 6 karttan sonra tavan yapar ki
                      // uzun listelerde son kartlar dakikalarca beklemesin.
                      .animate(delay: (40 * i.clamp(0, 6)).ms)
                      .fadeIn(duration: 250.ms)
                      .slideY(begin: 0.06, end: 0, curve: Curves.easeOut);
                },
              ),
            ),
        ],
      ),
    );
  }
}

/// Masa listesinin filtresi.
///
/// "Klasik" = tekli + katlamasız (varsayılan masa); "Eşli" ve "Katlamalı"
/// birbirinden bağımsız kural ekleridir (bkz. OkeyCreateRoomScreen), bu
/// yüzden eşli+katlamalı bir masa ikisinde de görünür.
enum _TableFilter {
  all('Tümü'),
  classic('Klasik'),
  team('Eşli'),
  folding('Katlamalı');

  final String label;
  const _TableFilter(this.label);

  bool matches(OkeyRoom r) => switch (this) {
    all => true,
    classic => r.gameMode != 'katlamali' && r.teamMode != 'esli',
    team => r.teamMode == 'esli',
    folding => r.gameMode == 'katlamali',
  };
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

/// Lobinin ilk satırı: kim olduğun, masa teması ve çip bakiyen.
///
/// Eskiden sistem AppBar'ında dört ikon vardı (puan, tema, skor, yenile);
/// hiçbiri "sen kimsin" sorusunu yanıtlamıyordu. Artık kimlik solda, tek
/// ikon (tema) ve çip hapı sağda; skor tablosu alt çubukta.
class _LobbyHeader extends StatelessWidget {
  final OkeyProfileCard? me;
  final OkeyPointsProvider points;
  final VoidCallback onThemeTap;
  final VoidCallback onPointsTap;
  final VoidCallback onProfileTap;

  const _LobbyHeader({
    required this.me,
    required this.points,
    required this.onThemeTap,
    required this.onPointsTap,
    required this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    final played = me?.matchesPlayed ?? 0;
    return Row(
      children: [
        GestureDetector(
          onTap: onProfileTap,
          child: OkeyAvatar(url: me?.avatarUrl, size: 46, highlighted: true),
        ),
        const SizedBox(width: OkeyUI.gap),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                me?.displayName ?? 'Oyuncu',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: OkeyUI.display(size: 18),
              ),
              const SizedBox(height: 2),
              Text(
                played == 0
                    ? 'Hazır mısın?'
                    : '$played maç · ${me?.matchesWon ?? 0} galibiyet',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: OkeyUI.body.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          icon: const Icon(Icons.palette_outlined),
          color: OkeyUI.textDim,
          tooltip: 'Masa teması',
          onPressed: onThemeTap,
        ),
        OkeyChipsPill(
          points: points.points,
          onTap: onPointsTap,
          showDot: points.canClaimGift,
        ),
      ],
    );
  }
}

/// "Devam eden oyunun var" şeridi.
class _ResumeCard extends StatelessWidget {
  final OkeyRoom room;

  const _ResumeCard({required this.room});

  @override
  Widget build(BuildContext context) {
    return OkeyCard(
      highlighted: true,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
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
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
              color: Color(0xFFFFC24B),
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: Color(0xFFFFC24B), blurRadius: 8)],
            ),
          ),
          const SizedBox(width: OkeyUI.gap),
          const Expanded(
            child: Text(
              'Masan hazır · kaldığın yerden devam et',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: OkeyUI.text,
                fontSize: 13,
                height: 1.25,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: OkeyUI.gapSm),
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: const Color(0xFFE4B04C),
              borderRadius: BorderRadius.circular(OkeyUI.radiusSm),
            ),
            child: const Text(
              'DEVAM ET',
              style: TextStyle(
                color: OkeyUI.onGold,
                fontSize: 12,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// "Hemen oyna" kartı — lobinin tek büyük, tek pirinç düğmesi.
class _HeroCard extends StatelessWidget {
  final VoidCallback onQuickMatch;

  const _HeroCard({required this.onQuickMatch});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: const RadialGradient(
          center: Alignment(0.7, -0.9),
          radius: 1.5,
          colors: [Color(0xFF1B7562), Color(0xFF0F4A45), Color(0xFF0A3532)],
          stops: [0, 0.6, 1],
        ),
        border: Border.all(color: OkeyUI.cardBorder),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            blurRadius: 24,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Hemen oyna', style: OkeyUI.display(size: 30)),
                    const SizedBox(height: 6),
                    Text(
                      'Ayar sormadan sana uygun masaya oturtur.',
                      style: OkeyUI.body.copyWith(
                        color: const Color(0xD9F5EBD8),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: OkeyUI.gapSm),
              const OkeySeatMini(occupied: 4, size: 88),
            ],
          ),
          const SizedBox(height: OkeyUI.gapLg),
          OkeyButton(
            label: 'OTOMATİK EŞLEŞ',
            icon: Icons.bolt,
            tone: OkeyButtonTone.primary,
            onPressed: onQuickMatch,
          ),
        ],
      ),
    );
  }
}

/// Masa listesi filtre çipleri.
class _FilterChips extends StatelessWidget {
  final _TableFilter selected;
  final ValueChanged<_TableFilter> onSelect;

  const _FilterChips({required this.selected, required this.onSelect});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: _TableFilter.values.length,
        separatorBuilder: (_, _) => const SizedBox(width: OkeyUI.gapSm),
        itemBuilder: (_, i) {
          final f = _TableFilter.values[i];
          final on = f == selected;
          return Semantics(
            button: true,
            selected: on,
            label: f.label,
            child: GestureDetector(
              onTap: withOkeyTapSound(() => onSelect(f)),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: on ? const Color(0xFFE4B04C) : Colors.transparent,
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(
                    color: on
                        ? const Color(0xFFE4B04C)
                        : const Color(0x38FFF0D2),
                  ),
                ),
                child: Text(
                  f.label,
                  style: TextStyle(
                    color: on ? OkeyUI.onGold : OkeyUI.text,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Lobideki masa kartı — hem açık (OTUR) hem canlı (İZLE) masa için.
///
/// İkisi aynı kartı paylaşır ama okunuşu bilerek farklıdır: canlı kartın
/// alt satırı "Canlı" diye başlar ve birincil eylem "İZLE"dir (pirinç değil
/// çerçeveli). İkisi aynı görünseydi, dolu bir masaya oturmaya çalışan
/// oyuncu her seferinde reddedilirdi.
///
/// ## Bot ayrımı YOK (2026-09, kullanıcı isteği)
///
/// Dolu koltuk sayısı bot/gerçek ayrımı yapmadan gösterilir; botlar masada
/// gerçek oyuncular gibi göründüğü için lobide de ayrışmaz.
class _TableCard extends StatelessWidget {
  final OkeyRoom room;
  final bool live;
  final VoidCallback onTap;

  const _TableCard({
    required this.room,
    required this.live,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final team = room.teamMode == 'esli';
    final title = '${team ? 'Eşli' : 'Klasik'} 101 · ${room.totalHands} el';
    final folding = room.gameMode == 'katlamali' ? 'Katlamalı' : 'Katlamasız';
    final who = room.creatorName ?? 'Oyuncu';
    final sub = live
        ? 'Canlı · $folding'
              '${room.spectatorCount > 0 ? ' · ${room.spectatorCount} izleyici' : ''}'
        : '$who · $folding · '
              '${room.assistMode == 'yardimsiz' ? 'Yardımsız' : 'Yardımlı'}';

    return OkeyCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
      child: Row(
        children: [
          OkeySeatMini(occupied: room.occupiedSeats, size: 50),
          const SizedBox(width: OkeyUI.gap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OkeyUI.title.copyWith(fontSize: 14.5),
                ),
                const SizedBox(height: 3),
                Text(
                  sub,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: OkeyUI.caption.copyWith(color: OkeyUI.textDim),
                ),
              ],
            ),
          ),
          const SizedBox(width: OkeyUI.gapSm),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              // MASA PUANI = el başına puan × el sayısı: cüzdandan düşecek
              // sayı budur (kullanıcı isteği, 2026-09-05).
              if (room.tableStake > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const OkeyCoin(size: 13),
                    const SizedBox(width: 5),
                    Text(
                      OkeyChipsPill.format(room.tableStake),
                      style: OkeyUI.display(size: 14, color: OkeyUI.chipText),
                    ),
                  ],
                ),
              const SizedBox(height: 6),
              OkeyButton(
                label: live ? 'İZLE' : 'OTUR',
                tone: live ? OkeyButtonTone.ghost : OkeyButtonTone.primary,
                dense: true,
                expand: false,
                onPressed: onTap,
              ),
            ],
          ),
        ],
      ),
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
/// yazar: kaybolan bir düğme, bir daha ne zaman geleceğini söylemez. Hazır
/// kart pirinç çerçeveyle öne çıkar.
class _EarnCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool enabled;
  final bool busy;
  final VoidCallback onTap;

  const _EarnCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = enabled ? color : OkeyUI.textFaint;

    return OkeyCard(
      onTap: enabled ? onTap : null,
      highlighted: enabled,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: fg.withValues(alpha: enabled ? 0.18 : 0.08),
            ),
            child: busy
                ? const Padding(
                    padding: EdgeInsets.all(9),
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(icon, color: fg, size: 20),
          ),
          const SizedBox(width: OkeyUI.gapSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OkeyUI.title.copyWith(fontSize: 12.5),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OkeyUI.caption.copyWith(
                    color: enabled ? OkeyUI.chipText : OkeyUI.textDim,
                    fontWeight: enabled ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
