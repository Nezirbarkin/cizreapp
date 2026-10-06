import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../leaderboard/leaderboard.dart';
import 'admin_ui.dart';

/// Admin > Liderler Tablosu.
///
/// Ana anahtar, dönem, gösterilecek kişi sayısı, kartların SIRASI (sürükle-bırak)
/// ve her kart/sayaç için ayrı anahtar. En üstte kullanıcıların ana sayfada
/// göreceği bölümün canlı önizlemesi var; her değişiklikten sonra yeniden çizilir.
/// En altta liderlik listelerinden gizlenen kullanıcılar (kendi isteğiyle ya da
/// admin tarafından) görünür.
///
/// Anahtarlar sunucuda da uygulanır (kapalı kart sunucudan hiç dönmez);
/// buradaki değişiklik istemciyi kurcalayan biri için de geçerlidir.
///
/// Sayfanın tamamı tek bir [ReorderableListView]: kartlar sürüklenirken sayfa
/// kendiliğinden kayar (iç içe kaydırılabilirde bu çalışmazdı). Üstteki ayarlar
/// `header`, alttaki sayaç/gizlenenler `footer`.
class LeaderboardManagementContent extends StatefulWidget {
  const LeaderboardManagementContent({super.key});

  @override
  State<LeaderboardManagementContent> createState() =>
      _LeaderboardManagementContentState();
}

class _HiddenUser {
  const _HiddenUser({
    required this.id,
    required this.name,
    required this.handle,
    required this.avatarUrl,
    required this.visibility,
  });

  final String id;
  final String name;
  final String? handle;
  final String? avatarUrl;
  final LeaderboardVisibility visibility;
}

class _LeaderboardManagementContentState
    extends State<LeaderboardManagementContent> {
  LeaderboardSettings? _settings;
  Object? _loadError;
  String? _busyKey;

  List<_HiddenUser> _hidden = const [];
  bool _hiddenLoading = true;

  /// Önizlemenin anahtarı: değişince bölüm sıfırdan kurulup veriyi yeniden çeker.
  int _previewRevision = 0;

  @override
  void initState() {
    super.initState();
    _load();
    _loadHidden();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      final settings = await LeaderboardService.loadSettings();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _previewRevision++;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = e);
    }
  }

  Future<void> _loadHidden() async {
    try {
      final map = await LeaderboardService.adminHiddenUsers();
      final ids = map.keys.toList();
      final profiles = <String, Map<String, dynamic>>{};
      if (ids.isNotEmpty) {
        final rows = await Supabase.instance.client
            .from('profiles')
            .select('id, full_name, username, avatar_url')
            .inFilter('id', ids);
        for (final row in rows) {
          profiles[row['id'] as String] = Map<String, dynamic>.from(row);
        }
      }
      if (!mounted) return;
      setState(() {
        _hidden = [
          for (final entry in map.entries)
            _HiddenUser(
              id: entry.key,
              name: adminDisplayName(profiles[entry.key] ?? const {}),
              handle: (profiles[entry.key]?['username'] as String?),
              avatarUrl: profiles[entry.key]?['avatar_url'] as String?,
              visibility: entry.value,
            ),
        ];
        _hiddenLoading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _hiddenLoading = false);
    }
  }

  void _snack(String message, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : null,
      ),
    );
  }

  /// Tek bir yazımı çalıştırır, ardından ayarları yeniden okur.
  Future<void> _apply(String busyKey, Future<void> Function() write) async {
    setState(() => _busyKey = busyKey);
    try {
      await write();
      final settings = await LeaderboardService.loadSettings();
      if (!mounted) return;
      setState(() {
        _settings = settings;
        _previewRevision++;
      });
    } catch (e) {
      if (!mounted) return;
      _snack('Kaydedilemedi: $e', error: true);
    } finally {
      if (mounted) setState(() => _busyKey = null);
    }
  }

  /// Kartı sürükleyip bırakınca: önce ekranda hemen sırala (takılma hissi
  /// olmasın), sonra kaydet; hata olursa eski sıraya dön.
  Future<void> _onReorder(int oldIndex, int newIndex) async {
    final current = _settings;
    if (current == null) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex == oldIndex) return;

    final order = current.orderedBoards.toList();
    final moved = order.removeAt(oldIndex);
    order.insert(newIndex, moved);

    setState(() => _settings = current.withOrder(order));
    try {
      await LeaderboardService.setOrder(order);
      if (!mounted) return;
      setState(() => _previewRevision++);
    } catch (e) {
      if (!mounted) return;
      setState(() => _settings = current);
      _snack('Sıra kaydedilemedi: $e', error: true);
    }
  }

  Future<void> _unhide(_HiddenUser user) async {
    try {
      await LeaderboardService.adminSetHidden(user.id, false);
      if (!mounted) return;
      _snack('${user.name} artık liderlik listelerinde görünebilir');
      setState(() => _previewRevision++);
      await _loadHidden();
    } catch (e) {
      _snack('Değiştirilemedi: $e', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = _settings;
    if (settings == null) {
      if (_loadError != null) {
        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, color: AdminUi.muted),
              const SizedBox(height: 8),
              const Text('Ayarlar okunamadı'),
              TextButton(onPressed: _load, child: const Text('Yeniden dene')),
            ],
          ),
        );
      }
      return const Center(child: CircularProgressIndicator());
    }

    final cards = settings.orderedBoards;
    return Container(
      color: AdminUi.page,
      child: ReorderableListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 32),
        buildDefaultDragHandles: false,
        itemCount: cards.length,
        onReorder: _onReorder,
        header: _header(settings),
        footer: _footer(settings),
        itemBuilder: (context, index) {
          final board = cards[index];
          return KeyedSubtree(
            key: ValueKey('lb-card-${board.key}'),
            child: _cardTile(board, index, settings),
          );
        },
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Üst kısım
  // ---------------------------------------------------------------------------

  Widget _header(LeaderboardSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Ana sayfada böyle görünür'),
        _preview(settings),
        const SizedBox(height: 14),
        _switchTile(
          busyKey: 'leaderboard_enabled',
          icon: Icons.emoji_events_rounded,
          color: const Color(0xFFF5B301),
          title: 'Liderler Tablosu',
          subtitle:
              'Ana sayfada İlanlar bölümünün altında görünür. Kapalıyken '
              'hiçbir kart gösterilmez ve sunucu da veri döndürmez.',
          value: settings.enabled,
          onChanged: (v) => _apply(
            'leaderboard_enabled',
            () => LeaderboardService.setEnabled(v),
          ),
        ),
        const SizedBox(height: 8),
        _periodCard(settings),
        const SizedBox(height: 8),
        _limitCard(settings),
        const SizedBox(height: 18),
        _sectionTitle('Kartlar — sürükleyerek sırala'),
        const Padding(
          padding: EdgeInsets.only(left: 4, right: 4, bottom: 10),
          child: Text(
            'Ana sayfada kartlar bu sırayla yandan kaydırılır. Sağdaki tutamaçtan '
            'tutup sürükle; anahtarla kartı göster/gizle.',
            style: TextStyle(fontSize: 12, color: AdminUi.muted, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _preview(LeaderboardSettings settings) {
    if (!settings.enabled || settings.visibleBoards.isEmpty) {
      return AdminCard(
        child: Row(
          children: [
            const Icon(Icons.visibility_off_rounded, color: AdminUi.muted),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                settings.enabled
                    ? 'Hiçbir kart açık değil — kullanıcılar bölümü görmez.'
                    : 'Liderler Tablosu kapalı — kullanıcılar bölümü görmez.',
                style: const TextStyle(color: AdminUi.muted),
              ),
            ),
          ],
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: HomeLeaderboardSection(
        key: ValueKey('leaderboard-preview-$_previewRevision'),
        // Önizlemede satırlar profile götürmesin.
        onOpenEntry: (_, __) {},
      ),
    );
  }

  Widget _periodCard(LeaderboardSettings settings) {
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Dönem',
            style: TextStyle(fontWeight: FontWeight.w700, color: AdminUi.ink),
          ),
          const SizedBox(height: 2),
          const Text(
            'Sipariş, paylaşım, beğeni, görüntülenme, giriş ve ürün kartları için. '
            'Takipçi, puan, yeni üye ve hikaye kartları dönemden etkilenmez.',
            style: TextStyle(fontSize: 12, color: AdminUi.muted, height: 1.4),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<LeaderboardPeriod>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: AdminUi.brandSoft,
                selectedForegroundColor: AdminUi.brand,
              ),
              segments: [
                for (final period in LeaderboardPeriod.values)
                  ButtonSegment(value: period, label: Text(period.label)),
              ],
              selected: {settings.period},
              onSelectionChanged: _busyKey == null
                  ? (selection) => _apply(
                      'leaderboard_period',
                      () => LeaderboardService.setPeriod(selection.first),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _limitCard(LeaderboardSettings settings) {
    const options = [3, 5, 7, 10];
    // Sunucu 3-10 arası her değeri kabul eder; seçeneklerde olmayan bir değer
    // (elle yazılmış) yine de seçili görünsün.
    final choices = {...options, settings.limit}.toList()..sort();
    return AdminCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Gösterilecek kişi sayısı',
            style: TextStyle(fontWeight: FontWeight.w700, color: AdminUi.ink),
          ),
          const SizedBox(height: 2),
          const Text(
            'Her listede kaç satır görünsün.',
            style: TextStyle(fontSize: 12, color: AdminUi.muted),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<int>(
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: AdminUi.brandSoft,
                selectedForegroundColor: AdminUi.brand,
              ),
              segments: [
                for (final n in choices)
                  ButtonSegment(value: n, label: Text('$n')),
              ],
              selected: {settings.limit},
              onSelectionChanged: _busyKey == null
                  ? (selection) => _apply(
                      'leaderboard_limit',
                      () => LeaderboardService.setLimit(selection.first),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Kart satırı (sürüklenebilir)
  // ---------------------------------------------------------------------------

  Widget _cardTile(
    LeaderboardBoard board,
    int index,
    LeaderboardSettings settings,
  ) {
    return _switchTile(
      busyKey: board.settingKey,
      icon: board.icon,
      color: board.color,
      title: board.title,
      subtitle: board.periodAware
          ? '${board.description}. Dönem ayarından etkilenir.'
          : board.description,
      value: settings.isBoardEnabled(board),
      dimmed: !settings.enabled,
      leading: ReorderableDragStartListener(
        index: index,
        child: const Padding(
          padding: EdgeInsets.only(right: 8),
          child: Icon(Icons.drag_indicator_rounded, color: AdminUi.muted),
        ),
      ),
      order: index + 1,
      onChanged: (v) => _apply(
        board.settingKey,
        () => LeaderboardService.setBoardEnabled(board, v),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Alt kısım
  // ---------------------------------------------------------------------------

  Widget _footer(LeaderboardSettings settings) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 10),
        for (final board in LeaderboardBoard.values.where((b) => b.isStats))
          ..._statSection(settings, board),
        ..._recordSection(settings),
        const SizedBox(height: 10),
        _sectionTitle('Listelerden gizlenenler (${_hidden.length})'),
        _hiddenSection(),
        const SizedBox(height: 14),
        _rulesCard(),
      ],
    );
  }

  /// Bir sayaç kartının başlığı, açıklaması ve kendi sayaç anahtarları.
  List<Widget> _statSection(
    LeaderboardSettings settings,
    LeaderboardBoard card,
  ) {
    final cardOn = settings.isBoardEnabled(card);
    final hint = switch (card.statGroup) {
      LeaderboardStatGroup.today =>
        '"Ziyaretçi" bugün (İstanbul saati) iz bırakan herkestir, '
            'misafirler dahil. Hesap açmadan ve misafir oturumu '
            'başlatmadan gezenler izlenmez.',
      LeaderboardStatGroup.personal =>
        'Her kullanıcı yalnız KENDİ sayılarını görür; misafir (üyesiz) '
            'hesaplara bu kart gösterilmez.',
      _ =>
        '"Sipariş" tamamlanan fiziksel ve dijital siparişlerdir. '
            '"Toplam üye" misafirleri (üyesiz) saymaz.',
    };
    return [
      _sectionTitle('${card.title} kartındaki sayılar'),
      Padding(
        padding: const EdgeInsets.only(left: 4, right: 4, bottom: 10),
        child: Text(
          !cardOn
              ? '"${card.title}" kartı kapalı; açılınca bu sayılar görünür.'
              : hint,
          style: const TextStyle(
            fontSize: 12,
            color: AdminUi.muted,
            height: 1.4,
          ),
        ),
      ),
      for (final stat in LeaderboardStat.values.where(
        (s) => s.group == card.statGroup,
      ))
        _switchTile(
          busyKey: stat.settingKey,
          icon: stat.icon,
          color: stat.color,
          title: stat.label,
          subtitle: _statHint(stat),
          value: settings.isStatEnabled(stat),
          dimmed: !settings.enabled || !cardOn,
          onChanged: (v) => _apply(
            stat.settingKey,
            () => LeaderboardService.setStatEnabled(stat, v),
          ),
        ),
      const SizedBox(height: 10),
    ];
  }

  String _statHint(LeaderboardStat stat) {
    switch (stat) {
      case LeaderboardStat.members:
        return 'Aktif, bot olmayan üyeler.';
      case LeaderboardStat.guests:
        return 'Misafir girişi yapmış (üyesiz) hesaplar.';
      case LeaderboardStat.ghosts:
        return 'Hayalet modunu açmış üyeler (yalnız sayı; kimse ifşa olmaz).';
      case LeaderboardStat.visitorsToday:
        return 'Bugün iz bırakan herkes: üyeler + misafirler.';
      case LeaderboardStat.activeToday:
        return 'Bugün uygulamayı kullanan üyeler (misafirler hariç).';
      case LeaderboardStat.guestsToday:
        return 'Bugün uygulamayı kullanan üyesiz (misafir) hesaplar.';
      case LeaderboardStat.onlineNow:
        return 'Son 3 dakikada aktif olanlar (hayalet mod dahil).';
      case LeaderboardStat.newToday:
        return 'Bugün kayıt olan yeni üyeler (misafirler hariç).';
      case LeaderboardStat.postsToday:
        return 'Bugün paylaşılan gönderiler.';
      case LeaderboardStat.ordersToday:
        return 'Bugün verilen, iptal/başarısız/iade olmayan siparişler.';
      case LeaderboardStat.orders:
        return 'Tamamlanan fiziksel + dijital sipariş.';
      case LeaderboardStat.shops:
        return 'Aktif ve onaylı dükkanlar.';
      case LeaderboardStat.products:
        return 'Aktif dükkanlardaki yayında ürünler.';
      case LeaderboardStat.posts:
        return 'Yayındaki gönderiler.';
      case LeaderboardStat.okeyMatches:
        return 'Bitmiş 101 Okey maçları (botlarla oynananlar dahil).';
      case LeaderboardStat.myDays:
        return 'Kayıt olduğu günden bu yana geçen gün.';
      case LeaderboardStat.myPosts:
        return 'Yayındaki gönderileri.';
      case LeaderboardStat.myLikes:
        return 'Gönderilerine gelen toplam beğeni.';
      case LeaderboardStat.myPostViews:
        return 'Gönderilerinin görüntülenmesi (kendi bakışları hariç).';
      case LeaderboardStat.myFollowers:
        return 'Takipçi sayısı.';
      case LeaderboardStat.myFollowing:
        return 'Takip ettiği kişi sayısı.';
      case LeaderboardStat.myOrders:
        return 'Müşteri olarak tamamlanan fiziksel + dijital siparişleri.';
      case LeaderboardStat.myLogins:
        return 'Giriş sayısı (eylem günlüğü 90 gün saklanır).';
      case LeaderboardStat.myOkeyMatches:
        return 'Oynadığı 101 Okey maçı.';
      case LeaderboardStat.myOkeyWins:
        return 'Kazandığı 101 Okey maçı.';
    }
  }

  /// "Rekor Skorlar" kartının rekor anahtarları (Görev 4.4).
  List<Widget> _recordSection(LeaderboardSettings settings) {
    final cardOn = settings.isBoardEnabled(LeaderboardBoard.records);
    return [
      _sectionTitle('${LeaderboardBoard.records.title} kartındaki rekorlar'),
      Padding(
        padding: const EdgeInsets.only(left: 4, right: 4, bottom: 10),
        child: Text(
          !cardOn
              ? '"${LeaderboardBoard.records.title}" kartı kapalı; açılınca bu rekorlar görünür.'
              : 'Tüm zamanların rekorları; gün İstanbul saatine göre sayılır. Kişi ve '
                    'gönderi rekorları botları, gizli hesapları ve liderlikten '
                    'gizlenenleri atlar; verisi olmayan rekor gösterilmez.',
          style: const TextStyle(
            fontSize: 12,
            color: AdminUi.muted,
            height: 1.4,
          ),
        ),
      ),
      for (final record in LeaderboardRecord.values)
        _switchTile(
          busyKey: record.settingKey,
          icon: record.icon,
          color: record.color,
          title: record.label,
          subtitle: _recordHint(record),
          value: settings.isRecordEnabled(record),
          dimmed: !settings.enabled || !cardOn,
          onChanged: (v) => _apply(
            record.settingKey,
            () => LeaderboardService.setRecordEnabled(record, v),
          ),
        ),
      const SizedBox(height: 10),
    ];
  }

  String _recordHint(LeaderboardRecord record) {
    switch (record) {
      case LeaderboardRecord.busiestDay:
        return 'En çok kişinin iz bıraktığı gün (misafirler dahil, bot hariç).';
      case LeaderboardRecord.signupDay:
        return 'En çok yeni üyenin katıldığı gün (misafirler hariç).';
      case LeaderboardRecord.ordersDay:
        return 'En çok siparişin tamamlandığı gün (fiziksel + dijital).';
      case LeaderboardRecord.postsDay:
        return 'En çok gönderinin paylaşıldığı gün.';
      case LeaderboardRecord.oldestMember:
        return 'En uzun süredir üye olan kişi (yönetici hesapları hariç).';
      case LeaderboardRecord.topPostLikes:
        return 'Tüm zamanların en çok beğenilen gönderisi.';
      case LeaderboardRecord.livePeak:
        return 'En çok eş zamanlı izleyiciye ulaşan canlı yayın.';
      case LeaderboardRecord.firstPost:
        return 'Uygulamada paylaşılan ilk gönderi.';
    }
  }

  Widget _hiddenSection() {
    if (_hiddenLoading) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (_hidden.isEmpty) {
      return const AdminCard(
        child: Text(
          'Şu an gizlenen kullanıcı yok. Bir kullanıcıyı gizlemek için '
          'Kullanıcılar > ⋮ > "Liderlikten gizle". Kullanıcılar kendilerini de '
          'Hesap Ayarları\'ndan gizleyebilir.',
          style: TextStyle(fontSize: 12, color: AdminUi.muted, height: 1.45),
        ),
      );
    }
    return Column(
      children: [
        for (final user in _hidden)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: AdminCard(
              child: Row(
                children: [
                  AdminAvatar(url: user.avatarUrl, name: user.name, radius: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: AdminUi.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            if (user.visibility.selfHidden)
                              const AdminBadge(
                                label: 'Kendisi gizledi',
                                color: Colors.blueGrey,
                                icon: Icons.visibility_off_rounded,
                              ),
                            if (user.visibility.adminHidden)
                              const AdminBadge(
                                label: 'Admin gizledi',
                                color: Colors.deepOrange,
                                icon: Icons.admin_panel_settings_rounded,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (user.visibility.adminHidden)
                    TextButton(
                      onPressed: () => _unhide(user),
                      child: const Text('Göster'),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _rulesCard() {
    return AdminCard(
      color: AdminUi.brandSoft,
      borderColor: Colors.transparent,
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline_rounded, size: 18, color: AdminUi.muted),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Listelerde bot hesaplar, gizli profiller, askıya alınmış '
              'hesaplar, gizlenen kullanıcılar ve (giriş yapan kullanıcıyla '
              'arasında) engel olan kişiler yer almaz. Gizlenen bir kullanıcının '
              'gönderileri, hikayeleri ve dükkanları da listelenmez; sayaçlara '
              'yine dahildir. Hikaye kartı yalnız hâlâ yayındaki hikayeleri '
              'gösterir. "En çok giriş" kartı giriş günlüğünden gelir (günlük '
              '90 gün saklanır). Okey kartları yalnız GERÇEK oyuncuları '
              'sayar; Okey içindeki skor tablosunda görünen botlar (türetilmiş '
              'sayılarla) burada yoktur.',
              style: TextStyle(
                fontSize: 12,
                color: AdminUi.muted,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Ortak parçalar
  // ---------------------------------------------------------------------------

  Widget _sectionTitle(String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w800,
          color: AdminUi.muted,
          letterSpacing: .2,
        ),
      ),
    );
  }

  Widget _switchTile({
    required String busyKey,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    Widget? leading,
    int? order,
    bool dimmed = false,
  }) {
    final busy = _busyKey == busyKey;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Opacity(
        opacity: dimmed ? .55 : 1,
        child: AdminCard(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: Row(
            children: [
              if (leading != null) leading,
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: .12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      order == null ? title : '$order. $title',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AdminUi.ink,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AdminUi.muted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              busy
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Switch(
                      value: value,
                      activeThumbColor: AdminUi.brand,
                      onChanged: _busyKey == null ? onChanged : null,
                    ),
            ],
          ),
        ),
      ),
    );
  }
}
