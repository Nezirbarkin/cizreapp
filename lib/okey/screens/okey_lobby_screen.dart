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
import '../theme/okey_ui.dart';
import '../widgets/okey_appearance_sheet.dart';
import '../widgets/okey_coin_rain.dart';
import '../widgets/okey_leaderboard_view.dart';
import '../widgets/okey_profile_sheet.dart';
import 'okey_create_room_screen.dart';
import 'okey_game_screen.dart';
import 'okey_points_screen.dart';
import 'okey_room_screen.dart';

/// 101 Okey lobisi ("ana sayfa"): kimlik, hızlı oyun, çip kazanma ve masalar.
///
/// ## Tasarım Sistemi v6 (2026-10-05) — ÜÇ DÜZEN
///
/// Lobi artık aktif tasarımın DÜZENİNE göre üç farklı biçimde kurulur (bkz.
/// [OkeyLobbyLayout]); yönetici düzeni tasarımdan bağımsız da seçebilir
/// (Admin › 101 Okey › Tasarım):
///
///  * **Salon** — dikey akış: büyük "Hemen oyna" kartı, altında liste.
///  * **Arena** — vitrin: istatistikli afiş, hızlı eylem kutuları, canlı
///    masalar şeridi, açık masalar ızgarada.
///  * **Kompakt** — hız: sekmeli sıkı liste; "Hemen oyna" ekranın altında
///    SABİT, kaydırınca kaybolmaz.
///
/// Üçü de aynı veriyi ve aynı eylemleri kullanır (bu dosyadaki
/// `_OkeyLobbyViewState` metodları); yalnızca YERLEŞİM farklıdır. Gövde her
/// düzende [OkeyScreen]in kaydırılabilir alanıdır — dikey taşma yapısal
/// olarak imkânsızdır.
class OkeyLobbyScreen extends StatelessWidget {
  const OkeyLobbyScreen({super.key});

  @override
  Widget build(BuildContext context) {
    // OTURUM KAPISI, provider'lardan ÖNCE gelir. Sağlayıcılar kurulur
    // kurulmaz Supabase'e sorgu atar; oturum yokken bu sorgular RLS
    // yüzünden boş döner ve lobi "hiç masa yok" diye yalan söylerdi.
    //
    // TASARIM KAPSAMI en dışta: tasarım değişince (oyuncu Görünüm'den seçti
    // ya da yönetici ayarı geldi) lobi baştan, yeni değerlerle kurulur.
    return const OkeyDesignScope(
      child: _OkeySessionGate(child: _OkeyLobbyProviders()),
    );
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
                const OkeySeatMini(occupied: 4, size: 96),
                const SizedBox(height: OkeyUI.gapLg),
                Text(
                  'Masaya oturmak ya da izlemek için bir kimlik gerekiyor.',
                  textAlign: TextAlign.center,
                  style: OkeyUI.title,
                ),
                const SizedBox(height: OkeyUI.gapSm),
                Text(
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
                    style: TextStyle(color: OkeyUI.errorText, fontSize: 13),
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

/// Kompakt düzenin sekmesi.
enum _CompactTab { open, live }

class _OkeyLobbyViewState extends State<_OkeyLobbyView> {
  /// Reklam yükleniyor/gösteriliyor — düğme iki kez tetiklenmesin.
  bool _adBusy = false;

  /// Kendi profil kartım (başlıktaki ad/avatar için).
  OkeyProfileCard? _me;

  /// Masa listesi filtresi.
  _TableFilter _filter = _TableFilter.all;

  /// Kompakt düzende hangi liste açık.
  _CompactTab _compactTab = _CompactTab.open;

  /// "Masalar" başlığı — alt çubuktaki Masalar öğesi buraya kaydırır.
  final GlobalKey _tablesKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    // Tasarım + masa + ıstaka tercihleri masaya oturmadan da okunur ki
    // Görünüm sayfası ilk açılışta kayıtlı seçimi göstersin (ikinci
    // çağrılarda kendini kısa devre yapar).
    unawaited(OkeyDesignPrefs.instance.load());
    unawaited(_loadMe());
  }

  /// Görünüm sayfası: tasarım (yönetici izin veriyorsa), masa teması, ıstaka.
  void _openAppearance() => OkeyAppearanceSheet.show(context);

  Future<void> _watchAd() async {
    final provider = context.read<OkeyPointsProvider>();
    setState(() => _adBusy = true);
    try {
      await okeyWatchRewardedAd(context: context, provider: provider);
    } finally {
      if (mounted) setState(() => _adBusy = false);
    }
  }

  /// Skor tablosu.
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
  /// düşük giriş) ile eşleştirir. Ayarını seçmek isteyen MASA KUR'u
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(OkeyUI.radiusLg),
          side: BorderSide(color: OkeyUI.cardBorder),
        ),
        title: Text('Davet koduyla katıl', style: OkeyUI.title),
        content: TextField(
          controller: controller,
          autofocus: true,
          textCapitalization: TextCapitalization.characters,
          style: TextStyle(color: OkeyUI.text),
          decoration: InputDecoration(
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
            style: FilledButton.styleFrom(
              backgroundColor: OkeyUI.brass,
              foregroundColor: OkeyUI.onGold,
            ),
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

  /// Oturumdaki kullanıcının kimliği; Supabase hazır değilse (widget testleri)
  /// ya da oturum yoksa null.
  static String? _myUserId() {
    try {
      return Supabase.instance.client.auth.currentUser?.id;
    } catch (_) {
      return null;
    }
  }

  /// Kendi ad/avatarım: başlık satırı için. Okunamazsa "Oyuncu" görünür —
  /// kimlik süstür, lobi bu yüzden beklemez ya da hata göstermez.
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

  void _openRoom(BuildContext context, OkeyRoom room, {required bool live}) =>
      live ? _watchRoom(context, room) : _joinRoom(context, room);

  // ===========================================================================
  // ORTAK PARÇALAR — üç düzen de bunları kendi sırasıyla dizer.
  // ===========================================================================

  Widget _pad(Widget child, {double top = 0, double bottom = OkeyUI.gap}) =>
      Padding(padding: EdgeInsets.fromLTRB(14, top, 14, bottom), child: child);

  Widget _header(OkeyPointsProvider points, {bool compact = false}) =>
      SliverToBoxAdapter(
        child: _pad(
          _LobbyHeader(
            me: _me,
            points: points,
            compact: compact,
            onAppearanceTap: _openAppearance,
            onPointsTap: _openPoints,
            onProfileTap: _openMyProfile,
          ),
        ),
      );

  List<Widget> _resumeAndInviteSlivers(
    BuildContext context,
    OkeyLobbyProvider lobby,
  ) {
    return [
      if (lobby.activeRoom != null)
        SliverToBoxAdapter(child: _pad(_ResumeCard(room: lobby.activeRoom!))),

      // ARKADAŞ DAVETLERİ — bildirimi kaçıranın daveti görebileceği yer.
      // Üstte durur: davet, lobideki her şeyden daha zaman duyarlıdır
      // (masa dolar ya da oyun başlar, davet düşer).
      if (lobby.pendingInvites.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: _pad(
            const OkeySectionHeader(label: 'Seni davet edenler'),
            bottom: 0,
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
    ];
  }

  _EarnData _earnData(OkeyPointsProvider points) => _EarnData(
    giftSubtitle: points.canClaimGift
        ? '${points.wallet.hourlyGiftPoints} çip hazır'
        : points.giftCountdownText,
    giftEnabled: points.canClaimGift && !points.isBusy,
    giftBusy: points.isBusy,
    onGift: points.claimHourlyGift,
    adSubtitle: '+${points.wallet.adRewardPoints} çip',
    adEnabled: !_adBusy && !points.isBusy,
    adBusy: _adBusy,
    onAd: _watchAd,
  );

  /// PUAN KAZAN — hediye ve reklam HER ZAMAN lobide (puanı biten oyuncunun
  /// yapabileceği iki şey başka bir ekranın arkasında kalmasın). Hazır
  /// olmayan kart gizlenmez, ne zaman hazır olacağını yazar.
  Widget _earnRow(_EarnData e) => Row(
    children: [
      Expanded(
        child: _EarnCard(
          icon: Icons.card_giftcard,
          color: OkeyUI.giftColor,
          title: 'Saatlik hediye',
          subtitle: e.giftSubtitle,
          enabled: e.giftEnabled,
          busy: e.giftBusy,
          onTap: e.onGift,
        ),
      ),
      const SizedBox(width: OkeyUI.gapSm),
      Expanded(
        child: _EarnCard(
          icon: Icons.play_arrow_rounded,
          color: OkeyUI.adColor,
          title: 'Reklam izle',
          subtitle: e.adSubtitle,
          enabled: e.adEnabled,
          busy: e.adBusy,
          onTap: e.onAd,
        ),
      ),
    ],
  );

  Widget _tablesHeader(int live, int open, {String label = 'Masalar'}) =>
      Padding(
        key: _tablesKey,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: OkeySectionHeader(
          label: label,
          trailing: (live + open) == 0
              ? null
              : OkeyPill(text: '$live canlı · $open açık'),
        ),
      );

  Widget _filterChips() => _FilterChips(
    selected: _filter,
    onSelect: (f) => setState(() => _filter = f),
  );

  Widget _loadingOrEmpty(BuildContext context, {required bool loading}) {
    if (loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(child: CircularProgressIndicator(color: OkeyUI.brass)),
      );
    }
    return OkeyEmptyState(
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
    );
  }

  /// Sıralı giriş; gecikme 6 karttan sonra tavan yapar ki uzun listelerde
  /// son kartlar dakikalarca beklemesin.
  Widget _animateIn(Widget child, int i) => child
      .animate(delay: (40 * i.clamp(0, 6)).ms)
      .fadeIn(duration: 250.ms)
      .slideY(begin: 0.06, end: 0, curve: Curves.easeOut);

  // ===========================================================================
  // DÜZEN 1 — SALON
  // ===========================================================================

  List<Widget> _salonSlivers(BuildContext context, _LobbyState s) {
    return [
      _header(s.points),
      ..._resumeAndInviteSlivers(context, s.lobby),

      // BİRİNCİL EYLEM — "Hemen oyna". Oyuncuların çoğu oynamak istiyor,
      // masa kurmak değil (kullanıcı isteği, 2026-09-07); hangi masa ve
      // kaç kişi bekleneceği sorusu hiç sorulmaz. Masa kurmak ve kodla
      // katılmak ikincil, hemen altında.
      SliverToBoxAdapter(
        child: _pad(
          Column(
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
          bottom: 0,
        ),
      ),
      SliverToBoxAdapter(
        child: _pad(_earnRow(_earnData(s.points)), top: OkeyUI.gap, bottom: 0),
      ),

      // MASALAR — canlı (izlenebilir) ve açık (oturulabilir) tek listede,
      // tek filtreyle. Canlı masalar üstte: oyun başlamış bir masayı
      // izlemek anında mümkün, açık masada üç kişi daha beklenir.
      SliverToBoxAdapter(
        child: _tablesHeader(s.liveRooms.length, s.openRooms.length),
      ),
      SliverToBoxAdapter(child: _filterChips()),
      const SliverToBoxAdapter(child: SizedBox(height: OkeyUI.gapSm)),
      if (s.loading || (s.liveRooms.isEmpty && s.openRooms.isEmpty))
        SliverToBoxAdapter(child: _loadingOrEmpty(context, loading: s.loading))
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          sliver: SliverList.separated(
            itemCount: s.liveRooms.length + s.openRooms.length,
            separatorBuilder: (_, _) => const SizedBox(height: OkeyUI.gapSm),
            itemBuilder: (context, i) {
              final live = i < s.liveRooms.length;
              final room = live
                  ? s.liveRooms[i]
                  : s.openRooms[i - s.liveRooms.length];
              return _animateIn(
                _TableCard(
                  room: room,
                  live: live,
                  onTap: () => _openRoom(context, room, live: live),
                ),
                i,
              );
            },
          ),
        ),
    ];
  }

  // ===========================================================================
  // DÜZEN 2 — ARENA
  // ===========================================================================

  List<Widget> _arenaSlivers(BuildContext context, _LobbyState s) {
    return [
      _header(s.points),
      ..._resumeAndInviteSlivers(context, s.lobby),
      SliverToBoxAdapter(
        child: _pad(
          _ArenaBanner(
            me: _me,
            points: s.points.points,
            liveCount: s.lobby.liveRooms.length,
            openCount: s.lobby.rooms.length,
            onQuickMatch: () => _quickMatch(context),
          ),
        ),
      ),
      // HIZLI EYLEM KUTULARI — üçü eşit, ikon üstte.
      SliverToBoxAdapter(
        child: _pad(
          _ActionTiles(
            tiles: [
              _ActionTileData(
                icon: Icons.add_circle_outline,
                label: 'Masa kur',
                onTap: () => _createRoom(context),
              ),
              _ActionTileData(
                icon: Icons.vpn_key_outlined,
                label: 'Kodla katıl',
                onTap: () => _joinByCode(context),
              ),
              _ActionTileData(
                icon: Icons.savings_outlined,
                label: 'Çiplerim',
                onTap: _openPoints,
                dot: s.points.canClaimGift,
              ),
            ],
          ),
          bottom: 0,
        ),
      ),
      SliverToBoxAdapter(
        child: _pad(_earnRow(_earnData(s.points)), top: OkeyUI.gap, bottom: 0),
      ),

      // CANLI MASALAR ŞERİDİ — yalnızca canlı masa varsa.
      if (s.liveRooms.isNotEmpty) ...[
        SliverToBoxAdapter(
          child: _pad(
            OkeySectionHeader(
              label: 'Şu an oynananlar',
              trailing: _LiveDot(count: s.liveRooms.length),
            ),
            bottom: 0,
          ),
        ),
        SliverToBoxAdapter(
          child: _LiveStrip(
            rooms: s.liveRooms,
            onWatch: (room) => _watchRoom(context, room),
          ),
        ),
      ],

      // AÇIK MASALAR — ızgara.
      SliverToBoxAdapter(
        child: _tablesHeader(
          s.liveRooms.length,
          s.openRooms.length,
          label: 'Açık masalar',
        ),
      ),
      SliverToBoxAdapter(child: _filterChips()),
      const SliverToBoxAdapter(child: SizedBox(height: OkeyUI.gapSm)),
      if (s.loading || s.openRooms.isEmpty)
        SliverToBoxAdapter(
          child: s.loading || s.liveRooms.isEmpty
              ? _loadingOrEmpty(context, loading: s.loading)
              : _pad(
                  _InlineNotice(
                    icon: Icons.event_seat_outlined,
                    text: 'Boş koltuklu masa yok — ilk masayı sen kur.',
                    actionLabel: 'MASA KUR',
                    onAction: () => _createRoom(context),
                  ),
                ),
        )
      else
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          sliver: SliverLayoutBuilder(
            builder: (context, constraints) {
              final w = constraints.crossAxisExtent;
              final cols = w >= 640 ? 3 : (w >= 340 ? 2 : 1);
              final rows = (s.openRooms.length / cols).ceil();
              return SliverList.separated(
                itemCount: rows,
                separatorBuilder: (_, _) =>
                    const SizedBox(height: OkeyUI.gapSm),
                itemBuilder: (context, r) {
                  final cells = <Widget>[];
                  for (var c = 0; c < cols; c++) {
                    final i = r * cols + c;
                    if (c > 0) cells.add(const SizedBox(width: OkeyUI.gapSm));
                    cells.add(
                      Expanded(
                        child: i < s.openRooms.length
                            ? _GridTableCard(
                                room: s.openRooms[i],
                                onTap: () => _joinRoom(context, s.openRooms[i]),
                              )
                            : const SizedBox.shrink(),
                      ),
                    );
                  }
                  // IntrinsicHeight: yan yana kartlar AYNI boyda — biri uzun
                  // ad yüzünden iki satır olunca diğeri kısa kalmasın.
                  return _animateIn(
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: cells,
                      ),
                    ),
                    r,
                  );
                },
              );
            },
          ),
        ),
    ];
  }

  // ===========================================================================
  // DÜZEN 3 — KOMPAKT
  // ===========================================================================

  List<Widget> _compactSlivers(BuildContext context, _LobbyState s) {
    final showLive = _compactTab == _CompactTab.live;
    final list = showLive ? s.liveRooms : s.openRooms;
    return [
      _header(s.points, compact: true),
      ..._resumeAndInviteSlivers(context, s.lobby),
      SliverToBoxAdapter(child: _pad(_EarnStrip(data: _earnData(s.points)))),
      SliverToBoxAdapter(
        child: Padding(
          key: _tablesKey,
          padding: const EdgeInsets.fromLTRB(14, 0, 14, OkeyUI.gapSm),
          child: _Segmented(
            items: [
              ('Açık masalar', s.openRooms.length),
              ('Canlı', s.liveRooms.length),
            ],
            selected: showLive ? 1 : 0,
            onSelect: (i) => setState(
              () => _compactTab = i == 1 ? _CompactTab.live : _CompactTab.open,
            ),
          ),
        ),
      ),
      SliverToBoxAdapter(child: _filterChips()),
      const SliverToBoxAdapter(child: SizedBox(height: OkeyUI.gapSm)),
      if (s.loading || list.isEmpty)
        SliverToBoxAdapter(
          child: s.loading || !showLive
              ? _loadingOrEmpty(context, loading: s.loading)
              : const OkeyEmptyState(
                  icon: Icons.visibility_outlined,
                  title: 'Şu an canlı masa yok',
                  message: 'Bir masa başladığında burada izleyebilirsin.',
                ),
        )
      else
        SliverToBoxAdapter(
          child: _pad(
            OkeyCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < list.length; i++) ...[
                    if (i > 0)
                      Divider(
                        height: 1,
                        thickness: 1,
                        indent: 62,
                        color: OkeyUI.cardBorder,
                      ),
                    _CompactTableRow(
                      room: list[i],
                      live: showLive,
                      onTap: () => _openRoom(context, list[i], live: showLive),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final lobby = context.watch<OkeyLobbyProvider>();
    final points = context.watch<OkeyPointsProvider>();
    final s = _LobbyState(
      lobby: lobby,
      points: points,
      liveRooms: lobby.liveRooms.where(_filter.matches).toList(),
      openRooms: lobby.rooms.where(_filter.matches).toList(),
      loading:
          lobby.isLoading && lobby.rooms.isEmpty && lobby.liveRooms.isEmpty,
    );
    final layout = OkeyUI.layout;

    final slivers = switch (layout) {
      OkeyLobbyLayout.salon => _salonSlivers(context, s),
      OkeyLobbyLayout.arena => _arenaSlivers(context, s),
      OkeyLobbyLayout.kompakt => _compactSlivers(context, s),
    };

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
        // KOMPAKT: "Hemen oyna" kaydırma alanının DIŞINDA, hep görünür.
        bottomBar: layout == OkeyLobbyLayout.kompakt
            ? _QuickPlayBar(
                onQuickMatch: () => _quickMatch(context),
                onCreate: () => _createRoom(context),
                onCode: () => _joinByCode(context),
              )
            : null,
        // GEZİNME ÇUBUĞU — eskiden üst çubukta dört ikon vardı (puan, tema,
        // skor, yenile). "Yenile" aşağı çekmede zaten var; skor tablosu ve
        // profil burada, görünüm başlıktaki tek ikonda.
        bottomNav: OkeyBottomNav(
          items: [
            OkeyNavItem(
              icon: Icons.casino_outlined,
              label: 'Lobi',
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
        slivers: slivers,
      ),
    );
  }
}

/// Bir build boyunca üç düzenin paylaştığı veri.
class _LobbyState {
  final OkeyLobbyProvider lobby;
  final OkeyPointsProvider points;
  final List<OkeyRoom> liveRooms;
  final List<OkeyRoom> openRooms;
  final bool loading;

  const _LobbyState({
    required this.lobby,
    required this.points,
    required this.liveRooms,
    required this.openRooms,
    required this.loading,
  });
}

/// Kazanç kartlarının verisi — düzenler aynı veriyi farklı biçimde çizer.
class _EarnData {
  final String giftSubtitle;
  final bool giftEnabled;
  final bool giftBusy;
  final VoidCallback onGift;
  final String adSubtitle;
  final bool adEnabled;
  final bool adBusy;
  final VoidCallback onAd;

  const _EarnData({
    required this.giftSubtitle,
    required this.giftEnabled,
    required this.giftBusy,
    required this.onGift,
    required this.adSubtitle,
    required this.adEnabled,
    required this.adBusy,
    required this.onAd,
  });
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

/// Masanın kısa adı ve alt satırı — üç kart biçimi aynı metni kullanır.
({String title, String sub}) _roomTexts(OkeyRoom room, {required bool live}) {
  final team = room.teamMode == 'esli';
  final title = '${team ? 'Eşli' : 'Klasik'} 101 · ${room.totalHands} el';
  final folding = room.gameMode == 'katlamali' ? 'Katlamalı' : 'Katlamasız';
  final who = room.creatorName ?? 'Oyuncu';
  final sub = live
      ? 'Canlı · $folding'
            '${room.spectatorCount > 0 ? ' · ${room.spectatorCount} izleyici' : ''}'
      : '$who · $folding · '
            '${room.assistMode == 'yardimsiz' ? 'Yardımsız' : 'Yardımlı'}';
  return (title: title, sub: sub);
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

/// Lobinin ilk satırı: kim olduğun, görünüm ve çip bakiyen.
///
/// Kimlik solda; görünüm ikonu ve çip hapı sağda; skor tablosu alt çubukta.
/// Görünüm ikonu yalnızca yönetici oyuncu seçimine izin verdiyse çizilir —
/// kilitliyken açılacak sayfada seçilebilir hiçbir şey olmaz.
class _LobbyHeader extends StatelessWidget {
  final OkeyProfileCard? me;
  final OkeyPointsProvider points;
  final bool compact;
  final VoidCallback onAppearanceTap;
  final VoidCallback onPointsTap;
  final VoidCallback onProfileTap;

  const _LobbyHeader({
    required this.me,
    required this.points,
    required this.compact,
    required this.onAppearanceTap,
    required this.onPointsTap,
    required this.onProfileTap,
  });

  @override
  Widget build(BuildContext context) {
    final played = me?.matchesPlayed ?? 0;
    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          GestureDetector(
            onTap: onProfileTap,
            child: OkeyAvatar(
              url: me?.avatarUrl,
              size: compact ? 40 : 46,
              highlighted: true,
            ),
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
                  style: OkeyUI.display(size: compact ? 16 : 18),
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
          if (OkeyDesignPrefs.instance.userChoiceAllowed)
            IconButton(
              icon: const Icon(Icons.palette_outlined),
              color: OkeyUI.textDim,
              tooltip: 'Görünüm',
              onPressed: onAppearanceTap,
            ),
          // ÇİP HAPI genişliğin %42'siyle sınırlı: 7 haneli bakiye 320 px'de
          // satırı taşırıyordu. Hap içindeki FittedBox sayıyı küçültür.
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.42),
            child: OkeyChipsPill(
              points: points.points,
              onTap: onPointsTap,
              showDot: points.canClaimGift,
            ),
          ),
        ],
      ),
    );
  }
}

/// "Devam eden oyunun var" şeridi.
class _ResumeCard extends StatelessWidget {
  final OkeyRoom room;

  const _ResumeCard({required this.room});

  void _open(BuildContext context) {
    final matchId = room.currentMatchId;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => room.status == 'in_progress' && matchId != null
            ? OkeyGameScreen(matchId: matchId)
            : OkeyRoomScreen(roomId: room.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OkeyCard(
      highlighted: true,
      padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
      onTap: () => _open(context),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: OkeyUI.brass,
              shape: BoxShape.circle,
              boxShadow: [BoxShadow(color: OkeyUI.brass, blurRadius: 8)],
            ),
          ),
          const SizedBox(width: OkeyUI.gap),
          Expanded(
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
          OkeyButton(
            label: 'DEVAM ET',
            tone: OkeyButtonTone.primary,
            dense: true,
            expand: false,
            onPressed: () => _open(context),
          ),
        ],
      ),
    );
  }
}

/// "Hemen oyna" kartı (Salon) — lobinin tek büyük, tek vurgulu düğmesi.
class _HeroCard extends StatelessWidget {
  final VoidCallback onQuickMatch;

  const _HeroCard({required this.onQuickMatch});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(OkeyUI.heroRadius),
        gradient: RadialGradient(
          center: const Alignment(0.7, -0.9),
          radius: 1.5,
          colors: OkeyUI.heroGradient,
          stops: const [0, 0.6, 1],
        ),
        border: Border.all(color: OkeyUI.cardBorder),
        boxShadow: [
          BoxShadow(
            color: OkeyUI.isLight ? OkeyUI.shadow : const Color(0x66000000),
            blurRadius: 24,
            offset: const Offset(0, 12),
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
                    Text(
                      'Hemen oyna',
                      style: OkeyUI.display(size: 30, color: OkeyUI.onHero),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Ayar sormadan sana uygun masaya oturtur.',
                      style: OkeyUI.body.copyWith(
                        color: OkeyUI.onHeroDim,
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

/// ARENA afişi — kimlik değil OYUN odaklı: çip, maç, galibiyet sayaçları ve
/// salonun canlılığı (kaç masa oynanıyor), altında tam genişlikte büyük
/// "Hemen oyna".
class _ArenaBanner extends StatelessWidget {
  final OkeyProfileCard? me;
  final int points;
  final int liveCount;
  final int openCount;
  final VoidCallback onQuickMatch;

  const _ArenaBanner({
    required this.me,
    required this.points,
    required this.liveCount,
    required this.openCount,
    required this.onQuickMatch,
  });

  @override
  Widget build(BuildContext context) {
    final played = me?.matchesPlayed ?? 0;
    final won = me?.matchesWon ?? 0;
    final rate = played == 0 ? null : (won * 100 / played).round();
    final d = OkeyUI.design;

    Widget stat(String value, String label) => Expanded(
      child: Column(
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              value,
              maxLines: 1,
              style: OkeyUI.display(size: 20, color: OkeyUI.onHero),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            OkeyUI.heading(label),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: OkeyUI.onHeroDim,
              fontSize: 10.5,
              fontWeight: FontWeight.w700,
              letterSpacing: d.uppercase ? 0.8 : 0,
            ),
          ),
        ],
      ),
    );

    Widget divider() => Container(
      width: 1,
      height: 28,
      color: OkeyUI.onHero.withValues(alpha: 0.18),
    );

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(OkeyUI.heroRadius),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: OkeyUI.heroGradient,
        ),
        border: Border.all(
          color: d.glow
              ? OkeyUI.brass.withValues(alpha: 0.6)
              : OkeyUI.cardBorder,
        ),
        boxShadow: [
          BoxShadow(
            color: d.glow
                ? OkeyUI.brass.withValues(alpha: 0.25)
                : (OkeyUI.isLight ? OkeyUI.shadow : const Color(0x66000000)),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Stack(
        children: [
          // Sağ üstte büyük, yarı saydam kuş bakışı masa — afişin imzası.
          const Positioned(
            right: -28,
            top: -28,
            child: Opacity(
              opacity: 0.22,
              child: OkeySeatMini(occupied: 4, size: 150),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(
                        color: OkeyUI.live,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '$liveCount masa oynanıyor · $openCount masa bekliyor',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: OkeyUI.onHeroDim,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Masaya otur,\nelini aç.',
                  style: OkeyUI.display(size: 28, color: OkeyUI.onHero),
                ),
                const SizedBox(height: OkeyUI.gap),
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(OkeyUI.radius),
                    border: Border.all(
                      color: OkeyUI.onHero.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Row(
                    children: [
                      stat(OkeyChipsPill.format(points), 'Çip'),
                      divider(),
                      stat('$played', 'Maç'),
                      divider(),
                      stat(rate == null ? '—' : '%$rate', 'Galibiyet'),
                    ],
                  ),
                ),
                const SizedBox(height: OkeyUI.gap),
                OkeyButton(
                  label: 'HEMEN OYNA',
                  icon: Icons.bolt,
                  tone: OkeyButtonTone.primary,
                  height: 54,
                  onPressed: onQuickMatch,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTileData {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool dot;

  const _ActionTileData({
    required this.icon,
    required this.label,
    required this.onTap,
    this.dot = false,
  });
}

/// ARENA hızlı eylem kutuları — eşit genişlik, eşit yükseklik.
class _ActionTiles extends StatelessWidget {
  final List<_ActionTileData> tiles;

  const _ActionTiles({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < tiles.length; i++) ...[
            if (i > 0) const SizedBox(width: OkeyUI.gapSm),
            Expanded(child: _ActionTile(data: tiles[i])),
          ],
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final _ActionTileData data;

  const _ActionTile({required this.data});

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: data.label,
      child: OkeyCard(
        onTap: data.onTap,
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 12),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: OkeyUI.brass.withValues(
                      alpha: OkeyUI.isLight ? 0.12 : 0.16,
                    ),
                    borderRadius: BorderRadius.circular(
                      OkeyUI.design.buttonShape == OkeyButtonShape.sharp
                          ? 6
                          : 20,
                    ),
                  ),
                  child: Icon(data.icon, size: 21, color: OkeyUI.accentInk),
                ),
                if (data.dot)
                  const Positioned(
                    right: -1,
                    top: -1,
                    child: SizedBox(
                      width: 9,
                      height: 9,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: OkeyUI.live,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 7),
            Text(
              OkeyUI.label(data.label),
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: OkeyUI.text,
                fontSize: 12,
                height: 1.15,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Kırmızı "canlı" noktası + sayı.
class _LiveDot extends StatelessWidget {
  final int count;

  const _LiveDot({required this.count});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: const BoxDecoration(
            color: OkeyUI.live,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 5),
        Text(
          '$count',
          style: TextStyle(
            color: OkeyUI.textDim,
            fontSize: 12,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }
}

/// ARENA canlı masa şeridi — yatay kaydırılan kartlar.
///
/// Yatay listenin yüksekliği sabit olmak ZORUNDA; içerik yazı ölçeğiyle
/// büyüdüğü için yükseklik de ölçekle birlikte hesaplanır (1.5× yazıda
/// kart kendi içinde taşmasın).
class _LiveStrip extends StatelessWidget {
  final List<OkeyRoom> rooms;
  final ValueChanged<OkeyRoom> onWatch;

  const _LiveStrip({required this.rooms, required this.onWatch});

  @override
  Widget build(BuildContext context) {
    final ts = MediaQuery.textScalerOf(context).scale(14) / 14;
    final height = 124 + 46 * ts;
    return SizedBox(
      height: height,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: rooms.length,
        separatorBuilder: (_, _) => const SizedBox(width: OkeyUI.gapSm),
        itemBuilder: (context, i) {
          final room = rooms[i];
          final t = _roomTexts(room, live: true);
          return SizedBox(
            width: 210,
            child: OkeyCard(
              onTap: () => onWatch(room),
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      OkeySeatMini(occupied: room.occupiedSeats, size: 40),
                      const Spacer(),
                      const _LiveBadge(),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OkeyUI.title.copyWith(fontSize: 14),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    t.sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: OkeyUI.caption.copyWith(color: OkeyUI.textDim),
                  ),
                  const Spacer(),
                  OkeyButton(
                    label: 'İZLE',
                    icon: Icons.visibility_outlined,
                    tone: OkeyButtonTone.ghost,
                    dense: true,
                    onPressed: () => onWatch(room),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LiveBadge extends StatelessWidget {
  const _LiveBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: OkeyUI.live.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: OkeyUI.live.withValues(alpha: 0.5)),
      ),
      child: Text(
        OkeyUI.heading('Canlı'),
        style: const TextStyle(
          color: OkeyUI.live,
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// ARENA ızgara kartı — açık masa, dikey yerleşim.
class _GridTableCard extends StatelessWidget {
  final OkeyRoom room;
  final VoidCallback onTap;

  const _GridTableCard({required this.room, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final t = _roomTexts(room, live: false);
    return OkeyCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              OkeySeatMini(occupied: room.occupiedSeats, size: 44),
              const SizedBox(width: OkeyUI.gapSm),
              if (room.tableStake > 0)
                Expanded(
                  child: Align(
                    alignment: Alignment.topRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.topRight,
                      child: _StakeLabel(stake: room.tableStake),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            t.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: OkeyUI.title.copyWith(fontSize: 14),
          ),
          const SizedBox(height: 3),
          Text(
            t.sub,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: OkeyUI.caption.copyWith(color: OkeyUI.textDim),
          ),
          const Spacer(),
          const SizedBox(height: 10),
          OkeyButton(
            label: 'OTUR',
            tone: OkeyButtonTone.primary,
            dense: true,
            onPressed: onTap,
          ),
        ],
      ),
    );
  }
}

class _StakeLabel extends StatelessWidget {
  final int stake;

  const _StakeLabel({required this.stake});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const OkeyCoin(size: 13),
        const SizedBox(width: 5),
        Text(
          OkeyChipsPill.format(stake),
          style: OkeyUI.display(size: 14, color: OkeyUI.chipText),
        ),
      ],
    );
  }
}

/// Satır içi bilgi + eylem (boş ızgara yerine).
class _InlineNotice extends StatelessWidget {
  final IconData icon;
  final String text;
  final String actionLabel;
  final VoidCallback onAction;

  const _InlineNotice({
    required this.icon,
    required this.text,
    required this.actionLabel,
    required this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return OkeyCard(
      child: Row(
        children: [
          Icon(icon, color: OkeyUI.textFaint),
          const SizedBox(width: OkeyUI.gap),
          Expanded(
            child: Text(
              text,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: OkeyUI.body,
            ),
          ),
          const SizedBox(width: OkeyUI.gapSm),
          OkeyButton(
            label: actionLabel,
            tone: OkeyButtonTone.primary,
            dense: true,
            expand: false,
            onPressed: onAction,
          ),
        ],
      ),
    );
  }
}

/// KOMPAKT kazanç şeridi — iki yarısı olan tek kart.
class _EarnStrip extends StatelessWidget {
  final _EarnData data;

  const _EarnStrip({required this.data});

  Widget _half({
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool enabled,
    required bool busy,
    required VoidCallback onTap,
  }) {
    final fg = enabled ? color : OkeyUI.textFaint;
    return Expanded(
      child: InkWell(
        onTap: enabled ? withOkeyTapSound(onTap) : null,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 22,
                height: 22,
                child: busy
                    ? CircularProgressIndicator(strokeWidth: 2, color: fg)
                    : Icon(icon, size: 20, color: fg),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OkeyUI.title.copyWith(fontSize: 12),
                    ),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OkeyUI.caption.copyWith(
                        color: enabled ? OkeyUI.chipText : OkeyUI.textDim,
                        fontWeight: enabled ? FontWeight.w800 : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return OkeyCard(
      padding: EdgeInsets.zero,
      highlighted: data.giftEnabled,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(OkeyUI.radius),
        child: Material(
          color: Colors.transparent,
          child: IntrinsicHeight(
            child: Row(
              children: [
                _half(
                  icon: Icons.card_giftcard,
                  color: OkeyUI.giftColor,
                  title: 'Saatlik hediye',
                  subtitle: data.giftSubtitle,
                  enabled: data.giftEnabled,
                  busy: data.giftBusy,
                  onTap: data.onGift,
                ),
                VerticalDivider(width: 1, color: OkeyUI.cardBorder),
                _half(
                  icon: Icons.play_arrow_rounded,
                  color: OkeyUI.adColor,
                  title: 'Reklam izle',
                  subtitle: data.adSubtitle,
                  enabled: data.adEnabled,
                  busy: data.adBusy,
                  onTap: data.onAd,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// KOMPAKT sekme seçici.
class _Segmented extends StatelessWidget {
  final List<(String, int)> items;
  final int selected;
  final ValueChanged<int> onSelect;

  const _Segmented({
    required this.items,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final r = OkeyUI.design.buttonShape == OkeyButtonShape.pill
        ? 999.0
        : OkeyUI.radius;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: OkeyUI.wash,
        borderRadius: BorderRadius.circular(r),
        border: Border.all(color: OkeyUI.cardBorder),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == selected,
                label: items[i].$1,
                child: GestureDetector(
                  onTap: withOkeyTapSound(() => onSelect(i)),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    constraints: const BoxConstraints(minHeight: 38),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 6,
                    ),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == selected
                          ? OkeyUI.cardFill
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(r),
                      boxShadow: i == selected ? OkeyUI.cardShadow : null,
                    ),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            items[i].$1,
                            maxLines: 1,
                            style: TextStyle(
                              color: i == selected
                                  ? OkeyUI.text
                                  : OkeyUI.textDim,
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 1,
                            ),
                            decoration: BoxDecoration(
                              color: i == selected
                                  ? OkeyUI.brass
                                  : OkeyUI.textFaint.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${items[i].$2}',
                              style: TextStyle(
                                color: i == selected
                                    ? OkeyUI.onGold
                                    : OkeyUI.textDim,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// KOMPAKT liste satırı.
class _CompactTableRow extends StatelessWidget {
  final OkeyRoom room;
  final bool live;
  final VoidCallback onTap;

  const _CompactTableRow({
    required this.room,
    required this.live,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final t = _roomTexts(room, live: live);
    return Semantics(
      button: true,
      label: '${t.title}, ${live ? 'izle' : 'otur'}',
      child: InkWell(
        onTap: withOkeyTapSound(onTap),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
          child: Row(
            children: [
              OkeySeatMini(occupied: room.occupiedSeats, size: 38),
              const SizedBox(width: OkeyUI.gap),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OkeyUI.title.copyWith(fontSize: 14),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t.sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: OkeyUI.caption.copyWith(color: OkeyUI.textDim),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: OkeyUI.gapSm),
              if (live)
                const _LiveBadge()
              else if (room.tableStake > 0)
                _StakeLabel(stake: room.tableStake),
              Icon(Icons.chevron_right, color: OkeyUI.textFaint),
            ],
          ),
        ),
      ),
    );
  }
}

/// KOMPAKT sabit alt çubuk: büyük "Hemen oyna" + iki kare ikon düğme.
class _QuickPlayBar extends StatelessWidget {
  final VoidCallback onQuickMatch;
  final VoidCallback onCreate;
  final VoidCallback onCode;

  const _QuickPlayBar({
    required this.onQuickMatch,
    required this.onCreate,
    required this.onCode,
  });

  Widget _square(IconData icon, String tooltip, VoidCallback onTap) {
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(OkeyUI.buttonRadius),
      side: BorderSide(color: OkeyUI.secondaryBorder),
    );
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          color: OkeyUI.secondaryFill,
          shape: shape,
          child: InkWell(
            customBorder: shape,
            onTap: withOkeyTapSound(onTap),
            child: SizedBox(
              width: 50,
              height: 50,
              child: Icon(icon, color: OkeyUI.text, size: 22),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OkeyButton(
            label: 'HEMEN OYNA',
            icon: Icons.bolt,
            tone: OkeyButtonTone.primary,
            onPressed: onQuickMatch,
          ),
        ),
        const SizedBox(width: OkeyUI.gapSm),
        _square(Icons.add, 'Masa kur', onCreate),
        const SizedBox(width: OkeyUI.gapSm),
        _square(Icons.vpn_key_outlined, 'Kodla katıl', onCode),
      ],
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
    // Yatay liste sabit yükseklik ister; büyük yazıda çip metni kesilmesin
    // diye yükseklik yazı ölçeğiyle (tavanlı) büyür.
    final ts = MediaQuery.textScalerOf(context).scale(12.5) / 12.5;
    return SizedBox(
      height: 34 * ts.clamp(1.0, 1.4),
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
                  color: on ? OkeyUI.brass : Colors.transparent,
                  borderRadius: BorderRadius.circular(
                    OkeyUI.design.buttonShape == OkeyButtonShape.sharp ? 6 : 17,
                  ),
                  border: Border.all(
                    color: on ? OkeyUI.brass : OkeyUI.ghostBorder,
                  ),
                ),
                child: Text(
                  f.label,
                  maxLines: 1,
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

/// SALON masa kartı — hem açık (OTUR) hem canlı (İZLE) masa için.
///
/// İkisi aynı kartı paylaşır ama okunuşu bilerek farklıdır: canlı kartın
/// alt satırı "Canlı" diye başlar ve birincil eylem "İZLE"dir (vurgulu değil
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
    final t = _roomTexts(room, live: live);

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
                  t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OkeyUI.title.copyWith(fontSize: 14.5),
                ),
                const SizedBox(height: 3),
                Text(
                  t.sub,
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
              if (room.tableStake > 0) _StakeLabel(stake: room.tableStake),
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
/// kart vurgulu çerçeveyle öne çıkar.
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
                ? Padding(
                    padding: const EdgeInsets.all(9),
                    child: CircularProgressIndicator(strokeWidth: 2, color: fg),
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
