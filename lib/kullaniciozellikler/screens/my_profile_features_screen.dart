import 'package:flutter/material.dart';

import '../../features/wallet/screens/wallet_screen.dart';
import '../models/profile_feature.dart';
import '../services/profile_feature_service.dart';
import '../widgets/profile_feature_preview.dart';

/// Grid'de hangi öğelerin gösterileceği.
enum _FeatureFilter { all, owned, locked }

/// Sekmede gösterilen kategoriler. Rozet en sonda: yalnız yönetici verir,
/// kullanıcı satın alamaz.
const _kTabs = <ProfileFeatureKind>[
  ProfileFeatureKind.avatarEffect,
  ProfileFeatureKind.coverEffect,
  ProfileFeatureKind.effect,
  ProfileFeatureKind.icon,
  ProfileFeatureKind.badge,
];

class MyProfileFeaturesScreen extends StatefulWidget {
  const MyProfileFeaturesScreen({super.key});

  @override
  State<MyProfileFeaturesScreen> createState() =>
      _MyProfileFeaturesScreenState();
}

class _MyProfileFeaturesScreenState extends State<MyProfileFeaturesScreen>
    with SingleTickerProviderStateMixin {
  final _service = ProfileFeatureService();

  late final TabController _tabController;

  ProfileFeatureSummary _summary = ProfileFeatureSummary.empty;
  final Map<ProfileFeatureKind, List<ProfileFeature>> _byKind = {};
  final Map<ProfileFeatureKind, String> _kindErrors = {};
  final Set<ProfileFeatureKind> _loadingKinds = {};
  final Set<String> _updating = {};

  _FeatureFilter _filter = _FeatureFilter.all;
  bool _summaryLoading = true;
  String? _summaryError;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _kTabs.length, vsync: this)
      ..addListener(_onTabChanged);
    _loadSummary();
    _loadKind(_kTabs.first);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  /// Sekmeler tembel yüklenir — 470 katalog satırını tek seferde çekmek yerine
  /// yalnız görüntülenen kategori istenir.
  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    final kind = _kTabs[_tabController.index];
    if (!_byKind.containsKey(kind) && !_loadingKinds.contains(kind)) {
      _loadKind(kind);
    }
    setState(() {});
  }

  Future<void> _loadSummary() async {
    setState(() {
      _summaryLoading = true;
      _summaryError = null;
    });
    try {
      final summary = await _service.getMySummary();
      if (!mounted) return;
      setState(() {
        _summary = summary;
        _summaryLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _summaryLoading = false;
        _summaryError = 'Özet alınamadı: $error';
      });
    }
  }

  Future<void> _loadKind(ProfileFeatureKind kind) async {
    setState(() {
      _loadingKinds.add(kind);
      _kindErrors.remove(kind);
    });
    try {
      final items = await _service.getCatalogForKind(kind);
      if (!mounted) return;
      setState(() {
        _byKind[kind] = items;
        _loadingKinds.remove(kind);
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingKinds.remove(kind);
        _kindErrors[kind] = 'Liste alınamadı: $error';
      });
    }
  }

  Future<void> _refreshCurrent() async {
    final kind = _kTabs[_tabController.index];
    await Future.wait([_loadSummary(), _loadKind(kind)]);
  }

  // ---------------------------------------------------------------------------
  // Eylemler
  // ---------------------------------------------------------------------------

  /// Ortak sarmalayıcı: aynı özellik için çift dokunuşu engeller, iş bitince
  /// hem özeti hem o kategoriyi tazeler.
  Future<void> _run(
    ProfileFeature feature,
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    if (_updating.contains(feature.id)) return;
    setState(() => _updating.add(feature.id));
    try {
      await action();
      await Future.wait([_loadSummary(), _loadKind(feature.kind)]);
      if (mounted) _snack(successMessage);
    } on ProfileFeaturePurchaseException catch (error) {
      if (mounted) _purchaseErrorSnack(error);
    } catch (error) {
      if (mounted) _snack('İşlem başarısız: $error', isError: true);
    } finally {
      if (mounted) setState(() => _updating.remove(feature.id));
    }
  }

  Future<void> _purchase(ProfileFeature feature, String plan) => _run(
    feature,
    () => _service.purchaseMyFeature(featureId: feature.id, plan: plan),
    successMessage: '${feature.name} satın alındı.',
  );

  Future<void> _claim(ProfileFeature feature) => _run(
    feature,
    () => _service.claimMyFeature(feature.id),
    successMessage: '${feature.name} profiline eklendi.',
  );

  Future<void> _release(ProfileFeature feature) => _run(
    feature,
    () => _service.releaseMyFeature(feature.id),
    successMessage: '${feature.name} profilinden kaldırıldı.',
  );

  Future<void> _toggle(ProfileFeature feature, bool enabled) => _run(
    feature,
    () => _service.setMyFeatureEnabled(
      featureId: feature.id,
      enabled: enabled,
    ),
    successMessage: enabled
        ? '${feature.name} profilinde açıldı.'
        : '${feature.name} profilinde kapatıldı.',
  );

  void _snack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red.shade700 : null,
      ),
    );
  }

  void _purchaseErrorSnack(ProfileFeaturePurchaseException error) {
    final insufficient = error.code == 'INSUFFICIENT_POINTS';
    final message = switch (error.code) {
      'INSUFFICIENT_POINTS' =>
        'Yetersiz puan. Reklam izleyerek puan kazanabilirsin.',
      'REWARD_FEATURE_DISABLED' => 'Puanla satın alma şu anda kapalı.',
      'FEATURE_NOT_PURCHASABLE' => 'Bu özellik artık satın alınabilir değil.',
      'UNAUTHORIZED' => 'Oturumun sona ermiş. Lütfen tekrar giriş yap.',
      _ => 'Satın alma başarısız. Lütfen tekrar dene.',
    };
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red.shade700,
        action: insufficient
            ? SnackBarAction(
                label: 'PUAN KAZAN',
                textColor: Colors.white,
                onPressed: _openWallet,
              )
            : null,
      ),
    );
  }

  void _openWallet() => Navigator.of(
    context,
  ).push(MaterialPageRoute(builder: (_) => const WalletScreen()));

  // ---------------------------------------------------------------------------
  // Görünüm
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profil Özelliklerim'),
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          tabAlignment: TabAlignment.start,
          tabs: [for (final kind in _kTabs) _buildTab(kind)],
        ),
      ),
      body: Column(
        children: [
          _buildSummaryHeader(),
          _buildFilterBar(),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [for (final kind in _kTabs) _buildKindView(kind)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTab(ProfileFeatureKind kind) {
    final summary = _summary.kinds[kind];
    return Tab(
      height: 58,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(_kindIcon(kind), size: 19),
          const SizedBox(height: 3),
          Text(_shortTitle(kind), style: const TextStyle(fontSize: 11.5)),
          if (summary != null)
            Text(
              '${summary.owned}/${summary.total}',
              style: const TextStyle(fontSize: 10, height: 1.2),
            ),
        ],
      ),
    );
  }

  /// Puan bakiyesi ve tamamlanmış sipariş sayısı — iki kilit açma yolunun
  /// ilerlemesi tek satırda, yan yana.
  Widget _buildSummaryHeader() {
    if (_summaryLoading) {
      return const LinearProgressIndicator(minHeight: 2);
    }
    if (_summaryError != null) {
      return Container(
        width: double.infinity,
        color: Colors.red.withValues(alpha: 0.08),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                _summaryError!,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            TextButton(onPressed: _loadSummary, child: const Text('Yenile')),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: Row(
        children: [
          Expanded(
            child: _statTile(
              icon: Icons.local_shipping_outlined,
              color: Colors.deepPurple,
              label: 'Tamamlanan sipariş',
              value: '${_summary.completedOrders}',
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _statTile(
              icon: Icons.toll_outlined,
              color: Colors.green.shade700,
              label: 'Puanın',
              value: '${_summary.balancePoints}',
              onTap: _summary.pointsEarnEnabled ? _openWallet : null,
              trailing: _summary.pointsEarnEnabled
                  ? const Text(
                      'Kazan',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                    )
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _statTile({
    required IconData icon,
    required Color color,
    required String label,
    required String value,
    VoidCallback? onTap,
    Widget? trailing,
  }) {
    return Material(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: TextStyle(
                        fontSize: 10.5,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      value,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return SizedBox(
      height: 46,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        children: [
          for (final filter in _FeatureFilter.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(_filterLabel(filter)),
                selected: _filter == filter,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() => _filter = filter),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildKindView(ProfileFeatureKind kind) {
    if (_loadingKinds.contains(kind) && !_byKind.containsKey(kind)) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _kindErrors[kind];
    if (error != null) {
      return _centeredMessage(
        icon: Icons.error_outline,
        color: Colors.red,
        text: error,
        action: FilledButton.icon(
          onPressed: () => _loadKind(kind),
          icon: const Icon(Icons.refresh),
          label: const Text('Tekrar Dene'),
        ),
      );
    }

    final all = _byKind[kind] ?? const <ProfileFeature>[];
    final items = all.where(_matchesFilter).toList(growable: false);

    if (items.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refreshCurrent,
        child: ListView(
          children: [
            const SizedBox(height: 80),
            _centeredMessage(
              icon: kind == ProfileFeatureKind.badge
                  ? Icons.verified_outlined
                  : Icons.auto_awesome_outlined,
              color: Colors.grey,
              text: kind == ProfileFeatureKind.badge
                  ? 'Tik ve rozetler yalnızca yönetici tarafından verilir.'
                  : _filter == _FeatureFilter.all
                  ? 'Bu kategoride gösterilecek özellik yok.'
                  : 'Bu filtreye uyan özellik yok.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refreshCurrent,
      child: GridView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 128,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.74,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) => _FeatureTile(
          feature: items[index],
          busy: _updating.contains(items[index].id),
          onTap: () => _openDetail(items[index]),
        ),
      ),
    );
  }

  bool _matchesFilter(ProfileFeature feature) => switch (_filter) {
    _FeatureFilter.all => true,
    _FeatureFilter.owned => feature.isOwned,
    _FeatureFilter.locked => !feature.isOwned,
  };

  Widget _centeredMessage({
    required IconData icon,
    required Color color,
    required String text,
    Widget? action,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: color),
            const SizedBox(height: 14),
            Text(text, textAlign: TextAlign.center),
            if (action != null) ...[const SizedBox(height: 14), action],
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Detay sayfası (bottom sheet)
  // ---------------------------------------------------------------------------

  void _openDetail(ProfileFeature feature) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetContext) => _FeatureDetailSheet(
        feature: feature,
        completedOrders: _summary.completedOrders,
        balancePoints: _summary.balancePoints,
        pointsSpendEnabled: _summary.pointsSpendEnabled,
        pointsEarnEnabled: _summary.pointsEarnEnabled,
        onToggle: (value) {
          Navigator.of(sheetContext).pop();
          _toggle(feature, value);
        },
        onClaim: () {
          Navigator.of(sheetContext).pop();
          _claim(feature);
        },
        onRelease: () {
          Navigator.of(sheetContext).pop();
          _release(feature);
        },
        onPurchase: (plan) {
          Navigator.of(sheetContext).pop();
          _purchase(feature, plan);
        },
        onEarnPoints: () {
          Navigator.of(sheetContext).pop();
          _openWallet();
        },
      ),
    );
  }

  String _filterLabel(_FeatureFilter filter) => switch (filter) {
    _FeatureFilter.all => 'Hepsi',
    _FeatureFilter.owned => 'Bende',
    _FeatureFilter.locked => 'Kilitli',
  };

  String _shortTitle(ProfileFeatureKind kind) => switch (kind) {
    ProfileFeatureKind.effect => 'Profil',
    ProfileFeatureKind.avatarEffect => 'Profil Resmi',
    ProfileFeatureKind.coverEffect => 'Kapak',
    ProfileFeatureKind.icon => 'İkon',
    ProfileFeatureKind.badge => 'Tik / Rozet',
  };

  IconData _kindIcon(ProfileFeatureKind kind) => switch (kind) {
    ProfileFeatureKind.effect => Icons.auto_awesome,
    ProfileFeatureKind.avatarEffect => Icons.account_circle_outlined,
    ProfileFeatureKind.coverEffect => Icons.panorama_outlined,
    ProfileFeatureKind.icon => Icons.emoji_emotions_outlined,
    ProfileFeatureKind.badge => Icons.verified_outlined,
  };
}

// =============================================================================
// Grid hücresi — önizleme + ad + tek bakışta durum rozeti.
// =============================================================================
class _FeatureTile extends StatelessWidget {
  final ProfileFeature feature;
  final bool busy;
  final VoidCallback onTap;

  const _FeatureTile({
    required this.feature,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final locked = !feature.isOwned;
    return InkWell(
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Opacity(
                    opacity: locked ? 0.45 : 1,
                    child: ProfileFeaturePreview(
                      feature: feature,
                      size: 200,
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
                if (busy)
                  const Center(
                    child: SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                else
                  Positioned(right: 4, top: 4, child: _statusBadge()),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(
            feature.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 10.5, height: 1.15),
          ),
        ],
      ),
    );
  }

  Widget _statusBadge() {
    // Sahip olunan: açık/kapalı durumu. Değilse: hangi yolla açılacağı.
    if (feature.isOwned) {
      return _pill(
        icon: feature.isEnabled ? Icons.check_circle : Icons.visibility_off,
        color: feature.isEnabled ? Colors.green : Colors.blueGrey,
      );
    }
    if (feature.isFree) {
      return _pill(icon: Icons.card_giftcard, color: Colors.teal, text: 'Ücretsiz');
    }
    if (feature.orderUnlockMet) {
      return _pill(icon: Icons.lock_open, color: Colors.orange, text: 'Hazır');
    }
    if (feature.unlockAfterOrders != null) {
      return _pill(
        icon: Icons.lock,
        color: Colors.black54,
        text: '${feature.unlockAfterOrders} 📦',
      );
    }
    return _pill(icon: Icons.lock, color: Colors.black54);
  }

  Widget _pill({required IconData icon, required Color color, String? text}) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: text == null ? 4 : 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          if (text != null) ...[
            const SizedBox(width: 3),
            Text(
              text,
              style: const TextStyle(
                fontSize: 9.5,
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// =============================================================================
// Detay sayfası — kilidin iki yolu (sipariş / puan) burada açıkça anlatılır.
// =============================================================================
class _FeatureDetailSheet extends StatelessWidget {
  final ProfileFeature feature;
  final int completedOrders;
  final int balancePoints;
  final bool pointsSpendEnabled;
  final bool pointsEarnEnabled;
  final ValueChanged<bool> onToggle;
  final VoidCallback onClaim;
  final VoidCallback onRelease;
  final ValueChanged<String> onPurchase;
  final VoidCallback onEarnPoints;

  const _FeatureDetailSheet({
    required this.feature,
    required this.completedOrders,
    required this.balancePoints,
    required this.pointsSpendEnabled,
    required this.pointsEarnEnabled,
    required this.onToggle,
    required this.onClaim,
    required this.onRelease,
    required this.onPurchase,
    required this.onEarnPoints,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ProfileFeaturePreview(feature: feature, size: 84),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        feature.name,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        feature.description,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade700,
                        ),
                      ),
                      if (feature.expiresAt != null) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Bitiş: ${_date(feature.expiresAt!)}',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            ..._buildActions(context),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildActions(BuildContext context) {
    if (feature.kind == ProfileFeatureKind.badge) {
      return [
        _infoBox(
          icon: Icons.verified_outlined,
          color: Colors.blue,
          text: 'Tik ve rozetler yalnızca yönetici tarafından verilir; '
              'kullanıcı tarafından açılıp kapatılamaz.',
        ),
      ];
    }

    // 1) Kullanıcıda var: aç/kapat, gerekiyorsa kaldır.
    if (feature.isOwned) {
      return [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Profilimde göster'),
          subtitle: Text(
            feature.isEnabled ? 'Şu an açık' : 'Şu an kapalı',
            style: const TextStyle(fontSize: 12),
          ),
          value: feature.isEnabled,
          onChanged: onToggle,
        ),
        if (feature.isAdminGranted)
          _infoBox(
            icon: Icons.admin_panel_settings_outlined,
            color: Colors.blueGrey,
            text: 'Bu özellik yönetici tarafından verildi. Kaldıramazsın, '
                'ancak profilinde gizleyebilirsin.',
          )
        else
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onRelease,
              icon: const Icon(Icons.delete_outline, size: 18),
              label: const Text('Profilimden kaldır'),
              style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
            ),
          ),
      ];
    }

    // 2) İki ücretsiz özellikten biri.
    if (feature.isFree) {
      return [
        _infoBox(
          icon: Icons.card_giftcard,
          color: Colors.teal,
          text: 'Bu özellik ücretsiz ve süresizdir.',
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onClaim,
            icon: const Icon(Icons.add),
            label: const Text('Ücretsiz ekle'),
          ),
        ),
      ];
    }

    // 3) Sipariş eşiği karşılandı — puan ödemeden alınabilir.
    if (feature.orderUnlockMet) {
      return [
        _infoBox(
          icon: Icons.lock_open,
          color: Colors.orange.shade800,
          text: '${feature.unlockAfterOrders} siparişlik hedefi tamamladın '
              '($completedOrders sipariş). Bu özelliği ücretsiz alabilirsin.',
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onClaim,
            icon: const Icon(Icons.add),
            label: const Text('Profilime ekle'),
          ),
        ),
      ];
    }

    // 4) Kilitli: sipariş yolu + puan yolu yan yana anlatılır.
    final remaining = (feature.unlockAfterOrders ?? 0) - completedOrders;
    return [
      if (feature.unlockAfterOrders != null) ...[
        _infoBox(
          icon: Icons.local_shipping_outlined,
          color: Colors.deepPurple,
          text: '${feature.unlockAfterOrders}. siparişinde ücretsiz açılır. '
              '$completedOrders sipariş tamamladın, $remaining sipariş kaldı.',
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: LinearProgressIndicator(
            value: feature.unlockAfterOrders == 0
                ? 0
                : (completedOrders / feature.unlockAfterOrders!).clamp(0.0, 1.0),
            minHeight: 7,
          ),
        ),
        const SizedBox(height: 16),
      ],
      if (feature.hasPointsPrice) ...[
        Row(
          children: [
            const Text(
              'Beklemek istemiyorsan puanla al',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            const Spacer(),
            Text(
              '$balancePoints puanın var',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (!pointsSpendEnabled)
          _infoBox(
            icon: Icons.lock_clock,
            color: Colors.blueGrey,
            text: 'Puanla satın alma şu anda kapalı. Bu özelliği sipariş '
                'vererek açabilirsin.',
          )
        else
          Row(
            children: [
              if (feature.pointsPriceMonthly != null)
                Expanded(
                  child: OutlinedButton(
                    onPressed: balancePoints >= feature.pointsPriceMonthly!
                        ? () => onPurchase('monthly')
                        : null,
                    child: Text('Aylık\n${feature.pointsPriceMonthly} puan',
                        textAlign: TextAlign.center),
                  ),
                ),
              if (feature.pointsPriceMonthly != null &&
                  feature.pointsPriceYearly != null)
                const SizedBox(width: 10),
              if (feature.pointsPriceYearly != null)
                Expanded(
                  child: FilledButton(
                    onPressed: balancePoints >= feature.pointsPriceYearly!
                        ? () => onPurchase('yearly')
                        : null,
                    child: Text('Yıllık\n${feature.pointsPriceYearly} puan',
                        textAlign: TextAlign.center),
                  ),
                ),
            ],
          ),
        if (pointsSpendEnabled && pointsEarnEnabled) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onEarnPoints,
              icon: const Icon(Icons.play_circle_outline, size: 18),
              label: const Text('Reklam izleyerek puan kazan'),
            ),
          ),
        ],
        if (pointsSpendEnabled && !pointsEarnEnabled) ...[
          const SizedBox(height: 8),
          _infoBox(
            icon: Icons.info_outline,
            color: Colors.blueGrey,
            text: 'Puan kazanma şu anda kapalı; mevcut puanınla satın '
                'alabilirsin.',
          ),
        ],
      ],
    ];
  }

  Widget _infoBox({
    required IconData icon,
    required Color color,
    required String text,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 19),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5))),
        ],
      ),
    );
  }

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.'
      '${value.month.toString().padLeft(2, '0')}.${value.year}';
}
