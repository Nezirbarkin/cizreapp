import 'dart:async';

import 'package:flutter/material.dart';

import '../models/profile_feature.dart';
import '../services/profile_feature_service.dart';
import '../widgets/profile_privileges.dart';
import '../widgets/profile_feature_preview.dart';

/// Admin > Kullanıcı Özellikleri (Görev 2.5 — yeniden tasarım).
///
/// İki AYRI iş, iki mod:
///  * **Kullanıcıya Ver** — kullanıcı seç → kimlik kartı + profildeki
///    özellikler (aç/kapa, kaldır) → katalogdan "Ver".
///  * **Katalog Yönetimi** — özelliklerin kendisi: kullanıcılara açık mı
///    (ücretsiz), puan fiyatı, sipariş kilidi. Kullanıcı seçmeden çalışır.
///
/// Eskiden ikisi aynı kartta, yalnız ikonlu düğmelerle karışıktı; mobilde
/// kullanıcı seçmek ayrı bir sekmedeydi ve seçimden sonra özellikler
/// sekmesine elle geçmek gerekiyordu.
class UserFeaturesAdminContent extends StatefulWidget {
  const UserFeaturesAdminContent({super.key, this.service});

  /// Yalnızca testler için (sahte servis); uygulama varsayılanı kullanır.
  final ProfileFeatureService? service;

  @override
  State<UserFeaturesAdminContent> createState() =>
      _UserFeaturesAdminContentState();
}

enum _Mode { grant, catalog }

/// Tür süzgeci: null = tümü.
const List<({String? value, String label})> _kindFilters = [
  (value: null, label: 'Tümü'),
  (value: 'effect', label: 'Efekt'),
  (value: 'avatar_effect', label: 'Profil Resmi Efekti'),
  (value: 'cover_effect', label: 'Kapak Efekti'),
  (value: 'icon', label: 'İkon'),
  (value: 'badge', label: 'Tik/Rozet'),
];

/// Katalogda en fazla bu kadar özellik kullanıcılara ücretsiz açılabilir.
const int _maxFreeFeatures = 2;

class _UserFeaturesAdminContentState extends State<UserFeaturesAdminContent> {
  late final ProfileFeatureService _service =
      widget.service ?? ProfileFeatureService();
  final _userSearchController = TextEditingController();
  final _catalogSearchController = TextEditingController();
  Timer? _userDebounce;
  Timer? _catalogDebounce;
  List<ProfileFeatureUser> _users = const [];
  List<ProfileFeature> _catalog = const [];
  List<ProfileFeature> _assignments = const [];
  ProfileFeatureUser? _selectedUser;
  _Mode _mode = _Mode.grant;
  String? _kind;
  bool _loadingUsers = true;
  bool _loadingCatalog = true;
  bool _loadingAssignments = false;
  bool _onlyFree = false;
  String? _error;

  List<ProfileFeature> get _visibleCatalog =>
      _onlyFree ? _catalog.where((f) => f.isUserClaimable).toList() : _catalog;

  /// Ücretsiz açık özellik sayısı — TÜM katalog üzerinden (süzgeçsiz son
  /// okumadan). Sunucu sınırı da tür ayırt etmeden sayar.
  int? _globalFreeCount;
  int get _freeCount =>
      _globalFreeCount ?? _catalog.where((f) => f.isUserClaimable).length;

  bool _isAssigned(ProfileFeature feature) =>
      _assignments.any((item) => item.id == feature.id && item.isEnabled);

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _loadCatalog();
  }

  @override
  void dispose() {
    _userDebounce?.cancel();
    _catalogDebounce?.cancel();
    _userSearchController.dispose();
    _catalogSearchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Veri
  // ---------------------------------------------------------------------------

  Future<void> _loadUsers() async {
    setState(() => _loadingUsers = true);
    try {
      final users = await _service.searchUsers(_userSearchController.text);
      if (!mounted) return;
      setState(() {
        _users = users;
        _loadingUsers = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingUsers = false;
        _error = 'Kullanıcılar alınamadı: $error';
      });
    }
  }

  Future<void> _loadCatalog() async {
    setState(() => _loadingCatalog = true);
    try {
      final catalog = await _service.getCatalog(
        kind: _kind,
        search: _catalogSearchController.text,
      );
      if (!mounted) return;
      final unfiltered =
          _kind == null && _catalogSearchController.text.trim().isEmpty;
      setState(() {
        _catalog = catalog;
        if (unfiltered) {
          _globalFreeCount = catalog.where((f) => f.isUserClaimable).length;
        }
        _loadingCatalog = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingCatalog = false;
        _error = 'Özellik kataloğu alınamadı: $error';
      });
    }
  }

  Future<void> _selectUser(ProfileFeatureUser user) async {
    setState(() {
      _selectedUser = user;
      _loadingAssignments = true;
    });
    try {
      final assignments = await _service.getAdminAssignments(user.id);
      if (!mounted || _selectedUser?.id != user.id) return;
      setState(() {
        _assignments = assignments;
        _loadingAssignments = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingAssignments = false;
        _error = 'Kullanıcı özellikleri alınamadı: $error';
      });
    }
  }

  void _clearUser() {
    setState(() {
      _selectedUser = null;
      _assignments = const [];
    });
  }

  void _searchUsers(String _) {
    _userDebounce?.cancel();
    _userDebounce = Timer(const Duration(milliseconds: 450), _loadUsers);
  }

  /// Katalog araması yazarken (gecikmeli) çalışır; eskiden yalnızca
  /// Enter'a ya da ok düğmesine basınca arıyordu.
  void _searchCatalog(String _) {
    _catalogDebounce?.cancel();
    _catalogDebounce = Timer(const Duration(milliseconds: 450), _loadCatalog);
  }

  void _setKind(String? kind) {
    if (_kind == kind) return;
    setState(() => _kind = kind);
    _loadCatalog();
  }

  // ---------------------------------------------------------------------------
  // Kullanıcıya ver
  // ---------------------------------------------------------------------------

  Future<void> _assign(ProfileFeature feature) async {
    final user = _selectedUser;
    if (user == null) {
      _message('Önce bir kullanıcı seçin.', isError: true);
      return;
    }
    final duration = await showModalBottomSheet<_GrantDuration>(
      context: context,
      showDragHandle: true,
      builder: (context) => const _DurationSheet(),
    );
    if (duration == null) return;

    try {
      await _service.assign(
        userId: user.id,
        featureId: feature.id,
        expiresAt: duration.days == null
            ? null
            : DateTime.now().add(Duration(days: duration.days!)),
      );
      await _selectUser(user);
      _message('${feature.name}, @${user.username} profiline verildi.');
    } catch (error) {
      _message('Atama başarısız: $error', isError: true);
    }
  }

  Future<void> _toggle(ProfileFeature feature, bool enabled) async {
    final user = _selectedUser;
    if (user == null) return;
    try {
      await _service.setEnabled(
        userId: user.id,
        featureId: feature.id,
        enabled: enabled,
      );
      await _selectUser(user);
    } catch (error) {
      _message('Durum güncellenemedi: $error', isError: true);
    }
  }

  Future<void> _revoke(ProfileFeature feature) async {
    final user = _selectedUser;
    if (user == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Özelliği kaldır'),
        content: Text(
          '${feature.name}, @${user.username} profilinden tamamen kaldırılsın mı?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton.tonal(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Kaldır'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await _service.revoke(userId: user.id, featureId: feature.id);
      await _selectUser(user);
      _message('${feature.name} kaldırıldı.');
    } catch (error) {
      _message('Kaldırma başarısız: $error', isError: true);
    }
  }

  // ---------------------------------------------------------------------------
  // Katalog yönetimi
  // ---------------------------------------------------------------------------

  Future<void> _toggleClaimable(ProfileFeature feature) async {
    if (feature.kind == ProfileFeatureKind.badge) return;
    if (!feature.isUserClaimable && _freeCount >= _maxFreeFeatures) {
      _message(
        'En fazla $_maxFreeFeatures özellik ücretsiz açılabilir. '
        'Önce başka birini kapatın.',
        isError: true,
      );
      return;
    }
    try {
      await _service.setCatalogClaimable(
        featureId: feature.id,
        claimable: !feature.isUserClaimable,
        durationDays: 30,
      );
      await _loadCatalog();
      _message(
        feature.isUserClaimable
            ? '${feature.name} kullanıcı kataloğundan kaldırıldı.'
            : '${feature.name} kullanıcılara 30 günlüğüne açıldı.',
      );
    } catch (error) {
      _message('Kullanıcı erişimi güncellenemedi: $error', isError: true);
    }
  }

  Future<void> _editPricing(ProfileFeature feature) async {
    if (feature.kind == ProfileFeatureKind.badge) return;
    final result = await showModalBottomSheet<_PricingResult>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _PricingSheet(feature: feature),
    );
    if (result == null) return;
    try {
      await _service.setCatalogPointsPricing(
        featureId: feature.id,
        pointsMonthly: result.pointsMonthly,
        pointsYearly: result.pointsYearly,
      );
      await _loadCatalog();
      _message('${feature.name} fiyatı güncellendi.');
    } catch (error) {
      _message('Fiyat güncellenemedi: $error', isError: true);
    }
  }

  static bool _supportsOrderUnlock(ProfileFeature feature) =>
      feature.kind == ProfileFeatureKind.avatarEffect ||
      feature.kind == ProfileFeatureKind.coverEffect;

  Future<void> _editOrderUnlock(ProfileFeature feature) async {
    if (!_supportsOrderUnlock(feature)) return;
    final result = await showModalBottomSheet<_OrderUnlockResult>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => _OrderUnlockSheet(feature: feature),
    );
    if (result == null) return;
    try {
      await _service.setCatalogOrderUnlock(
        featureId: feature.id,
        unlockAfterOrders: result.unlockAfterOrders,
      );
      await _loadCatalog();
      _message(
        result.unlockAfterOrders == null
            ? '${feature.name} için sipariş kilidi kaldırıldı.'
            : '${feature.name}, ${result.unlockAfterOrders}. tamamlanan siparişte açılacak.',
      );
    } catch (error) {
      _message('Sipariş kilidi güncellenemedi: $error', isError: true);
    }
  }

  void _message(String text, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: isError ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Görünüm
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return ColoredBox(
          color: const Color(0xFFF6F5FA),
          child: Column(
            children: [
              _buildHeader(),
              if (_error != null)
                MaterialBanner(
                  content: Text(_error!),
                  leading: const Icon(Icons.error_outline, color: Colors.red),
                  actions: [
                    TextButton(
                      onPressed: () {
                        _loadUsers();
                        _loadCatalog();
                      },
                      child: const Text('YENİDEN DENE'),
                    ),
                  ],
                ),
              Expanded(
                child: _mode == _Mode.catalog
                    ? _buildCatalogPane(manage: true)
                    : wide
                    ? Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(
                            width: 320,
                            child: _buildUserPicker(),
                          ),
                          const VerticalDivider(width: 1),
                          Expanded(child: _buildGrantPane(showPicker: false)),
                        ],
                      )
                    : _buildGrantPane(showPicker: true),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Başlık: özet sayılar + mod seçici.
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepPurple.shade700, Colors.purple.shade500],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome, color: Colors.white, size: 26),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Kullanıcı Profil Ayrıcalıkları',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _StatPill(label: 'Katalog', value: '${_catalog.length}'),
              _StatPill(
                label: 'Ücretsiz',
                value: '$_freeCount/$_maxFreeFeatures',
                highlight: true,
              ),
              if (_selectedUser != null)
                _StatPill(
                  label: '@${_selectedUser!.username}',
                  value: '${_assignments.length} özellik',
                ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: SegmentedButton<_Mode>(
              style: SegmentedButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.12),
                foregroundColor: Colors.white,
                selectedBackgroundColor: Colors.white,
                selectedForegroundColor: Colors.deepPurple.shade700,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.5)),
              ),
              segments: const [
                ButtonSegment(
                  value: _Mode.grant,
                  icon: Icon(Icons.person_add_alt_1_outlined),
                  label: Text('Kullanıcıya Ver'),
                ),
                ButtonSegment(
                  value: _Mode.catalog,
                  icon: Icon(Icons.tune),
                  label: Text('Katalog Yönetimi'),
                ),
              ],
              selected: {_mode},
              onSelectionChanged: (selection) =>
                  setState(() => _mode = selection.first),
            ),
          ),
        ],
      ),
    );
  }

  // ---- Kullanıcı seçimi ------------------------------------------------------

  Widget _userSearchField() {
    return TextField(
      controller: _userSearchController,
      onChanged: _searchUsers,
      decoration: InputDecoration(
        hintText: 'Kullanıcı adı veya ad ile ara',
        prefixIcon: const Icon(Icons.search),
        filled: true,
        fillColor: Colors.white,
        isDense: true,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
      ),
    );
  }

  Widget _userTile(ProfileFeatureUser user) {
    final selected = user.id == _selectedUser?.id;
    return ListTile(
      selected: selected,
      selectedTileColor: Colors.purple.withValues(alpha: 0.09),
      leading: _UserAvatar(user: user, radius: 20),
      title: Text(user.fullName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text('@${user.username}'),
      trailing: selected
          ? const Icon(Icons.check_circle, color: Colors.purple)
          : const Icon(Icons.chevron_right),
      onTap: () => _selectUser(user),
    );
  }

  /// Geniş ekranda sol sütun: arama + kaydırılabilir liste.
  Widget _buildUserPicker() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: _userSearchField(),
        ),
        Expanded(
          child: _loadingUsers
              ? const Center(child: CircularProgressIndicator())
              : _users.isEmpty
              ? const _EmptyNote(text: 'Kullanıcı bulunamadı.')
              : ListView.builder(
                  itemCount: _users.length,
                  itemBuilder: (context, index) => _userTile(_users[index]),
                ),
        ),
      ],
    );
  }

  // ---- Kullanıcıya ver ------------------------------------------------------

  Widget _buildGrantPane({required bool showPicker}) {
    final user = _selectedUser;
    return CustomScrollView(
      slivers: [
        if (user == null && showPicker) ...[
          SliverToBoxAdapter(
            child: _SectionTitle(
              step: 1,
              title: 'Kullanıcı seçin',
              child: _userSearchField(),
            ),
          ),
          if (_loadingUsers)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (_users.isEmpty)
            const SliverToBoxAdapter(
              child: _EmptyNote(text: 'Kullanıcı bulunamadı.'),
            )
          else
            SliverList.builder(
              itemCount: _users.length,
              itemBuilder: (context, index) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _Panel(child: _userTile(_users[index])),
              ),
            ),
        ] else if (user == null) ...[
          const SliverToBoxAdapter(
            child: _EmptyNote(
              icon: Icons.person_search_outlined,
              text: 'Soldan bir kullanıcı seçin; sonra katalogdan özellik verin.',
            ),
          ),
        ] else ...[
          SliverToBoxAdapter(child: _buildSelectedUserCard(user)),
          SliverToBoxAdapter(child: _buildAssignedList()),
          SliverToBoxAdapter(
            child: _SectionTitle(
              step: 2,
              title: 'Katalogdan özellik ver',
              child: _buildCatalogFilters(),
            ),
          ),
          ..._catalogSlivers(manage: false),
        ],
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Widget _buildSelectedUserCard(ProfileFeatureUser user) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: _Panel(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              _UserAvatar(user: user, radius: 26),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      user.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      '@${user.username}',
                      style: TextStyle(color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: _clearUser,
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('Değiştir'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Seçili kullanıcının profilindeki özellikler (aç/kapa, kaldır).
  Widget _buildAssignedList() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      child: _Panel(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
              child: Text(
                'Profildeki özellikler',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: Colors.grey.shade800,
                ),
              ),
            ),
            if (_loadingAssignments)
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (_assignments.isEmpty)
              const _EmptyNote(text: 'Bu profile henüz özellik verilmedi.')
            else
              for (final feature in _assignments)
                ListTile(
                  leading: AnimatedPrivilegeIcon(feature: feature, size: 27),
                  title: Text(
                    feature.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    feature.expiresAt == null
                        ? 'Süresiz'
                        : 'Bitiş: ${_date(feature.expiresAt!)}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Switch(
                        value: feature.isEnabled,
                        onChanged: (value) => _toggle(feature, value),
                      ),
                      IconButton(
                        tooltip: 'Kaldır',
                        onPressed: () => _revoke(feature),
                        icon: const Icon(
                          Icons.delete_outline,
                          color: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }

  // ---- Katalog --------------------------------------------------------------

  Widget _buildCatalogFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _catalogSearchController,
          onChanged: _searchCatalog,
          onSubmitted: (_) => _loadCatalog(),
          decoration: InputDecoration(
            hintText: 'Katalogda ara',
            prefixIcon: const Icon(Icons.search),
            filled: true,
            fillColor: Colors.white,
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
          ),
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final filter in _kindFilters) ...[
                ChoiceChip(
                  label: Text(filter.label),
                  selected: _kind == filter.value,
                  onSelected: (_) => _setKind(filter.value),
                ),
                const SizedBox(width: 6),
              ],
              FilterChip(
                label: Text('Ücretsiz ($_freeCount/$_maxFreeFeatures)'),
                avatar: const Icon(Icons.people_alt_rounded, size: 16),
                selected: _onlyFree,
                onSelected: (value) => setState(() => _onlyFree = value),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCatalogPane({required bool manage}) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _SectionTitle(
            title: 'Katalog',
            subtitle: 'Kullanıcılara açma, puan fiyatı ve sipariş kilidi',
            child: _buildCatalogFilters(),
          ),
        ),
        ..._catalogSlivers(manage: manage),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  List<Widget> _catalogSlivers({required bool manage}) {
    if (_loadingCatalog) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          ),
        ),
      ];
    }
    final items = _visibleCatalog;
    if (items.isEmpty) {
      return const [
        SliverToBoxAdapter(child: _EmptyNote(text: 'Bu süzgeçte özellik yok.')),
      ];
    }
    Widget card(ProfileFeature feature) => manage
        ? _CatalogManageCard(
            feature: feature,
            supportsOrderUnlock: _supportsOrderUnlock(feature),
            onToggleClaimable: () => _toggleClaimable(feature),
            onEditPricing: () => _editPricing(feature),
            onEditOrderUnlock: () => _editOrderUnlock(feature),
          )
        : _CatalogGrantCard(
            feature: feature,
            assigned: _isAssigned(feature),
            onGrant: () => _assign(feature),
          );
    return [
      SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        sliver: SliverLayoutBuilder(
          builder: (context, constraints) {
            // Dar ekranda alt alta (kart kendi yüksekliğinde, taşmaz);
            // genişte ızgara.
            final columns = (constraints.crossAxisExtent / 360).floor();
            if (columns < 2) {
              return SliverList.separated(
                itemCount: items.length,
                separatorBuilder: (_, _) => const SizedBox(height: 10),
                itemBuilder: (context, index) => card(items[index]),
              );
            }
            return SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisExtent: manage ? 300 : 200,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              itemCount: items.length,
              itemBuilder: (context, index) => card(items[index]),
            );
          },
        ),
      ),
    ];
  }

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
}

// =============================================================================
// Parçalar
// =============================================================================

/// Beyaz, hafif gölgeli yuvarlak kart kabuğu.
class _Panel extends StatelessWidget {
  const _Panel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.black.withValues(alpha: 0.06)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(color: Colors.transparent, child: child),
      ),
    );
  }
}

/// Adım başlığı ("1 Kullanıcı seçin") + altındaki içerik.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({
    required this.title,
    required this.child,
    this.step,
    this.subtitle,
  });

  final int? step;
  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (step != null) ...[
                CircleAvatar(
                  radius: 12,
                  backgroundColor: Colors.deepPurple,
                  child: Text(
                    '$step',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                subtitle!,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
            ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}

class _EmptyNote extends StatelessWidget {
  const _EmptyNote({required this.text, this.icon = Icons.info_outline});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: Colors.grey.shade500),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ),
        ],
      ),
    );
  }
}

class _UserAvatar extends StatelessWidget {
  const _UserAvatar({required this.user, required this.radius});

  final ProfileFeatureUser user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final hasAvatar = user.avatarUrl?.isNotEmpty == true;
    return CircleAvatar(
      radius: radius,
      backgroundColor: Colors.deepPurple.shade50,
      backgroundImage: hasAvatar ? NetworkImage(user.avatarUrl!) : null,
      child: hasAvatar
          ? null
          : Text(
              user.username.isEmpty ? '?' : user.username[0].toUpperCase(),
              style: TextStyle(
                color: Colors.deepPurple.shade700,
                fontWeight: FontWeight.w800,
              ),
            ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  final String label;
  final String value;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: highlight
            ? Colors.greenAccent.withValues(alpha: 0.28)
            : Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        child: Text(
          '$label: $value',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

/// Özelliğin önizleme + ad + tür satırı (iki kart türü paylaşır).
class _FeatureHeading extends StatelessWidget {
  const _FeatureHeading({required this.feature});

  final ProfileFeature feature;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ProfileFeaturePreview(feature: feature, size: 58),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                feature.name,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 4,
                runSpacing: 4,
                children: [
                  _KindChip(kind: feature.kind),
                  if (feature.isUserClaimable) const _FreeChip(),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// "Kullanıcıya Ver" kartı: önizleme, kısa açıklama, tek büyük eylem.
class _CatalogGrantCard extends StatelessWidget {
  const _CatalogGrantCard({
    required this.feature,
    required this.assigned,
    required this.onGrant,
  });

  final ProfileFeature feature;
  final bool assigned;
  final VoidCallback onGrant;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _FeatureHeading(feature: feature),
            if (feature.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                feature.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            ],
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: assigned
                  ? OutlinedButton.icon(
                      onPressed: null,
                      icon: const Icon(Icons.check, size: 17),
                      label: const Text('Profilde'),
                    )
                  : FilledButton.icon(
                      onPressed: onGrant,
                      icon: const Icon(Icons.add, size: 17),
                      label: const Text('Profile ver'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "Katalog Yönetimi" kartı: etiketli ayarlar — anahtar ve düğmeler ne
/// yaptığını söyler (eskiden yalnız ikon + ipucu balonuydu).
class _CatalogManageCard extends StatelessWidget {
  const _CatalogManageCard({
    required this.feature,
    required this.supportsOrderUnlock,
    required this.onToggleClaimable,
    required this.onEditPricing,
    required this.onEditOrderUnlock,
  });

  final ProfileFeature feature;
  final bool supportsOrderUnlock;
  final VoidCallback onToggleClaimable;
  final VoidCallback onEditPricing;
  final VoidCallback onEditOrderUnlock;

  bool get _isBadge => feature.kind == ProfileFeatureKind.badge;

  String get _priceText {
    final parts = [
      if (feature.pointsPriceMonthly != null)
        'Aylık ${feature.pointsPriceMonthly}',
      if (feature.pointsPriceYearly != null)
        'Yıllık ${feature.pointsPriceYearly}',
    ];
    return parts.isEmpty ? 'Satışta değil' : '${parts.join(' · ')} puan';
  }

  @override
  Widget build(BuildContext context) {
    return _Panel(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            _FeatureHeading(feature: feature),
            if (feature.description.isNotEmpty) ...[
              const SizedBox(height: 6),
              Text(
                feature.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
              ),
            ],
            const Divider(height: 18),
            if (_isBadge)
              Text(
                'Tik/rozetler yalnızca admin tarafından verilir.',
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              )
            else ...[
              _SettingRow(
                icon: Icons.people_alt_rounded,
                label: 'Kullanıcılara ücretsiz açık',
                trailing: Switch(
                  value: feature.isUserClaimable,
                  onChanged: (_) => onToggleClaimable(),
                ),
              ),
              _SettingRow(
                icon: Icons.sell_outlined,
                label: _priceText,
                trailing: TextButton(
                  onPressed: onEditPricing,
                  child: const Text('Fiyat'),
                ),
              ),
              if (supportsOrderUnlock)
                _SettingRow(
                  icon: Icons.local_shipping_outlined,
                  label: feature.unlockAfterOrders == null
                      ? 'Sipariş kilidi yok'
                      : '${feature.unlockAfterOrders}. siparişte açılır',
                  trailing: TextButton(
                    onPressed: onEditOrderUnlock,
                    child: const Text('Kilit'),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.icon,
    required this.label,
    required this.trailing,
  });

  final IconData icon;
  final String label;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: Colors.deepPurple.shade400),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13),
          ),
        ),
        trailing,
      ],
    );
  }
}

class _KindChip extends StatelessWidget {
  final ProfileFeatureKind kind;

  const _KindChip({required this.kind});

  @override
  Widget build(BuildContext context) {
    final label = switch (kind) {
      ProfileFeatureKind.effect => 'Efekt',
      ProfileFeatureKind.avatarEffect => 'Avatar',
      ProfileFeatureKind.coverEffect => 'Kapak',
      ProfileFeatureKind.icon => 'İkon',
      ProfileFeatureKind.badge => 'Tik',
    };
    return Chip(
      label: Text(label, style: const TextStyle(fontSize: 10)),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}

class _FreeChip extends StatelessWidget {
  const _FreeChip();

  @override
  Widget build(BuildContext context) {
    return Chip(
      backgroundColor: Colors.green.shade600,
      label: const Text(
        'ÜCRETSİZ',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          color: Colors.white,
        ),
      ),
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
    );
  }
}

class _GrantDuration {
  final int? days;

  const _GrantDuration(this.days);
}

class _DurationSheet extends StatelessWidget {
  const _DurationSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Ayrıcalık süresi',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text('Özelliğin profilde ne kadar süre kalacağını seçin.'),
            const SizedBox(height: 12),
            for (final option in const <(String, int?)>[
              ('7 gün', 7),
              ('30 gün', 30),
              ('90 gün', 90),
              ('365 gün', 365),
              ('Süresiz', null),
            ])
              ListTile(
                leading: const Icon(Icons.schedule),
                title: Text(option.$1),
                onTap: () => Navigator.pop(context, _GrantDuration(option.$2)),
              ),
          ],
        ),
      ),
    );
  }
}

class _PricingResult {
  final int? pointsMonthly;
  final int? pointsYearly;

  const _PricingResult({this.pointsMonthly, this.pointsYearly});
}

class _PricingSheet extends StatefulWidget {
  final ProfileFeature feature;

  const _PricingSheet({required this.feature});

  @override
  State<_PricingSheet> createState() => _PricingSheetState();
}

class _PricingSheetState extends State<_PricingSheet> {
  late final TextEditingController _monthlyController;
  late final TextEditingController _yearlyController;

  @override
  void initState() {
    super.initState();
    _monthlyController = TextEditingController(
      text: widget.feature.pointsPriceMonthly?.toString() ?? '',
    );
    _yearlyController = TextEditingController(
      text: widget.feature.pointsPriceYearly?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _monthlyController.dispose();
    _yearlyController.dispose();
    super.dispose();
  }

  void _submit() {
    int? parse(String text) {
      final trimmed = text.trim();
      if (trimmed.isEmpty) return null;
      return int.tryParse(trimmed);
    }

    Navigator.pop(
      context,
      _PricingResult(
        pointsMonthly: parse(_monthlyController.text),
        pointsYearly: parse(_yearlyController.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.feature.name} — Fiyat',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Puan cinsinden aylık/yıllık satın alma fiyatı. Puan parayla '
              'satın alınamaz — kullanıcılar yalnızca reklam izleyerek/görev '
              'tamamlayarak kazanır. Boş bırakılan plan satın alınamaz olur.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _monthlyController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Aylık puan',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _yearlyController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Yıllık puan',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Vazgeç'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _submit,
                    child: const Text('Kaydet'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderUnlockResult {
  final int? unlockAfterOrders;

  const _OrderUnlockResult({this.unlockAfterOrders});
}

class _OrderUnlockSheet extends StatefulWidget {
  final ProfileFeature feature;

  const _OrderUnlockSheet({required this.feature});

  @override
  State<_OrderUnlockSheet> createState() => _OrderUnlockSheetState();
}

class _OrderUnlockSheetState extends State<_OrderUnlockSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.feature.unlockAfterOrders?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final trimmed = _controller.text.trim();
    final parsed = trimmed.isEmpty ? null : int.tryParse(trimmed);
    Navigator.pop(context, _OrderUnlockResult(unlockAfterOrders: parsed));
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          24 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${widget.feature.name} — Sipariş kilidi',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'Kullanıcının kaçıncı tamamlanmış (teslim edilmiş) siparişinde '
              'bu özelliğin otomatik açılacağını belirleyin. Boş bırakılırsa '
              'sipariş ile açılmaz.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Kaçıncı siparişte açılsın',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Vazgeç'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _submit,
                    child: const Text('Kaydet'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
