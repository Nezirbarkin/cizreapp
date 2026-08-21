import 'dart:async';

import 'package:flutter/material.dart';

import '../models/profile_feature.dart';
import '../services/profile_feature_service.dart';
import '../widgets/profile_privileges.dart';
import '../widgets/profile_feature_preview.dart';

class UserFeaturesAdminContent extends StatefulWidget {
  const UserFeaturesAdminContent({super.key});

  @override
  State<UserFeaturesAdminContent> createState() =>
      _UserFeaturesAdminContentState();
}

class _UserFeaturesAdminContentState extends State<UserFeaturesAdminContent> {
  final _service = ProfileFeatureService();
  final _userSearchController = TextEditingController();
  final _catalogSearchController = TextEditingController();
  Timer? _debounce;
  List<ProfileFeatureUser> _users = const [];
  List<ProfileFeature> _catalog = const [];
  List<ProfileFeature> _assignments = const [];
  ProfileFeatureUser? _selectedUser;
  String? _kind;
  bool _loadingUsers = true;
  bool _loadingCatalog = true;
  bool _loadingAssignments = false;
  bool _onlyFree = false;
  String? _error;

  List<ProfileFeature> get _visibleCatalog =>
      _onlyFree ? _catalog.where((f) => f.isUserClaimable).toList() : _catalog;

  @override
  void initState() {
    super.initState();
    _loadUsers();
    _loadCatalog();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _userSearchController.dispose();
    _catalogSearchController.dispose();
    super.dispose();
  }

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
      setState(() {
        _catalog = catalog;
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

  void _searchUsers(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), _loadUsers);
  }

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

  Future<void> _toggleClaimable(ProfileFeature feature) async {
    if (feature.kind == ProfileFeatureKind.badge) return;
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

  Future<void> _editOrderUnlock(ProfileFeature feature) async {
    if (feature.kind != ProfileFeatureKind.avatarEffect &&
        feature.kind != ProfileFeatureKind.coverEffect) {
      return;
    }
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

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return Column(
          children: [
            _buildSummary(),
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
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        SizedBox(width: 300, child: _buildUsers()),
                        const VerticalDivider(width: 1),
                        Expanded(child: _buildFeatureArea()),
                      ],
                    )
                  : _buildMobileTabs(),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummary() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.deepPurple.shade700, Colors.purple.shade500],
        ),
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const Icon(Icons.auto_awesome, color: Colors.white, size: 32),
          const Text(
            'Kullanıcı Profil Ayrıcalıkları',
            style: TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          _SummaryChip(label: 'Katalog', value: '${_catalog.length}'),
          _SummaryChip(
            label: 'Ücretsiz',
            value:
                '${_catalog.where((f) => f.isUserClaimable).length}/2',
            highlight: true,
          ),
          _SummaryChip(label: 'Atanmış', value: '${_assignments.length}'),
          if (_selectedUser != null)
            _SummaryChip(
              label: 'Kullanıcı',
              value: '@${_selectedUser!.username}',
            ),
        ],
      ),
    );
  }

  Widget _buildMobileTabs() {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const TabBar(
            tabs: [
              Tab(text: 'Kullanıcı Seç'),
              Tab(text: 'Özellikler'),
            ],
          ),
          Expanded(
            child: TabBarView(children: [_buildUsers(), _buildFeatureArea()]),
          ),
        ],
      ),
    );
  }

  Widget _buildUsers() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            controller: _userSearchController,
            onChanged: _searchUsers,
            decoration: const InputDecoration(
              labelText: 'Kullanıcı ara',
              hintText: 'Kullanıcı adı veya ad',
              prefixIcon: Icon(Icons.search),
              border: OutlineInputBorder(),
            ),
          ),
        ),
        Expanded(
          child: _loadingUsers
              ? const Center(child: CircularProgressIndicator())
              : ListView.builder(
                  itemCount: _users.length,
                  itemBuilder: (context, index) {
                    final user = _users[index];
                    final selected = user.id == _selectedUser?.id;
                    return ListTile(
                      selected: selected,
                      selectedTileColor: Colors.purple.withValues(alpha: 0.09),
                      leading: CircleAvatar(
                        backgroundImage: user.avatarUrl?.isNotEmpty == true
                            ? NetworkImage(user.avatarUrl!)
                            : null,
                        child: user.avatarUrl?.isNotEmpty == true
                            ? null
                            : Text(
                                user.username.isEmpty
                                    ? '?'
                                    : user.username[0].toUpperCase(),
                              ),
                      ),
                      title: Text(user.fullName),
                      subtitle: Text('@${user.username}'),
                      trailing: selected
                          ? const Icon(Icons.check_circle, color: Colors.purple)
                          : null,
                      onTap: () => _selectUser(user),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildFeatureArea() {
    return Column(
      children: [
        if (_selectedUser != null) _buildAssignedSection(),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _catalogSearchController,
                  onSubmitted: (_) => _loadCatalog(),
                  decoration: InputDecoration(
                    labelText: 'Katalogda ara',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: IconButton(
                      onPressed: _loadCatalog,
                      icon: const Icon(Icons.arrow_forward),
                    ),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String?>(
                value: _kind,
                hint: const Text('Tümü'),
                items: const [
                  DropdownMenuItem(value: null, child: Text('Tümü')),
                  DropdownMenuItem(value: 'effect', child: Text('Efekt')),
                  DropdownMenuItem(
                    value: 'avatar_effect',
                    child: Text('Profil Resmi Efekti'),
                  ),
                  DropdownMenuItem(
                    value: 'cover_effect',
                    child: Text('Kapak Efekti'),
                  ),
                  DropdownMenuItem(value: 'icon', child: Text('İkon')),
                  DropdownMenuItem(value: 'badge', child: Text('Tik/Rozet')),
                ],
                onChanged: (value) {
                  setState(() => _kind = value);
                  _loadCatalog();
                },
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: Row(
            children: [
              FilterChip(
                label: const Text('Sadece ücretsiz'),
                avatar: const Icon(Icons.people_alt_rounded, size: 16),
                selected: _onlyFree,
                onSelected: (value) => setState(() => _onlyFree = value),
              ),
              const SizedBox(width: 8),
              Text(
                'Ücretsiz: ${_catalog.where((f) => f.isUserClaimable).length}/2',
                style: TextStyle(
                  color: Colors.green.shade700,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: _loadingCatalog
              ? const Center(child: CircularProgressIndicator())
              : GridView.builder(
                  padding: const EdgeInsets.all(12),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 320,
                    mainAxisExtent: 260,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: _visibleCatalog.length,
                  itemBuilder: (context, index) {
                    final feature = _visibleCatalog[index];
                    final assigned = _assignments.any(
                      (item) => item.id == feature.id && item.isEnabled,
                    );
                    return Card(
                      clipBehavior: Clip.antiAlias,
                      shape: feature.isUserClaimable
                          ? RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: Colors.green.shade600,
                                width: 2,
                              ),
                            )
                          : null,
                      color: feature.isUserClaimable
                          ? Colors.green.withValues(alpha: 0.06)
                          : null,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ProfileFeaturePreview(
                                  feature: feature,
                                  size: 66,
                                ),
                                const SizedBox(width: 11),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        feature.name,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Wrap(
                                        spacing: 4,
                                        runSpacing: 4,
                                        children: [
                                          _KindChip(kind: feature.kind),
                                          if (feature.isUserClaimable)
                                            const _FreeChip(),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Expanded(
                              child: Text(
                                feature.description,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: Colors.grey.shade700,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            if (feature.pointsPriceMonthly != null ||
                                feature.pointsPriceYearly != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  [
                                    if (feature.pointsPriceMonthly != null)
                                      'Aylık ${feature.pointsPriceMonthly} puan',
                                    if (feature.pointsPriceYearly != null)
                                      'Yıllık ${feature.pointsPriceYearly} puan',
                                  ].join(' · '),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.green.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            if (feature.unlockAfterOrders != null)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 6),
                                child: Text(
                                  'Sipariş kilidi: #${feature.unlockAfterOrders}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.deepPurple.shade700,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            if (feature.kind != ProfileFeatureKind.badge)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 4),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Tooltip(
                                      message: feature.isUserClaimable
                                          ? 'Kullanıcı kataloğundan kaldır'
                                          : 'Kullanıcıların eklemesine izin ver',
                                      child: IconButton.filledTonal(
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () =>
                                            _toggleClaimable(feature),
                                        icon: Icon(
                                          feature.isUserClaimable
                                              ? Icons.people_alt_rounded
                                              : Icons.person_off_outlined,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Tooltip(
                                      message: 'Fiyat belirle',
                                      child: IconButton.filledTonal(
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => _editPricing(feature),
                                        icon: const Icon(
                                          Icons.sell_outlined,
                                          size: 18,
                                        ),
                                      ),
                                    ),
                                    if (feature.kind ==
                                            ProfileFeatureKind.avatarEffect ||
                                        feature.kind ==
                                            ProfileFeatureKind.coverEffect) ...[
                                      const SizedBox(width: 6),
                                      Tooltip(
                                        message: 'Sipariş kilidi belirle',
                                        child: IconButton.filledTonal(
                                          visualDensity: VisualDensity.compact,
                                          onPressed: () =>
                                              _editOrderUnlock(feature),
                                          icon: const Icon(
                                            Icons.local_shipping_outlined,
                                            size: 18,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            SizedBox(
                              width: double.infinity,
                              child: FilledButton.icon(
                                onPressed: assigned
                                    ? null
                                    : () => _assign(feature),
                                icon: Icon(
                                  assigned ? Icons.check : Icons.add,
                                  size: 17,
                                ),
                                label: Text(
                                  assigned ? 'VERİLDİ' : 'PROFİLE VER',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildAssignedSection() {
    return Container(
      height: 116,
      color: Colors.grey.shade100,
      child: _loadingAssignments
          ? const Center(child: CircularProgressIndicator())
          : _assignments.isEmpty
          ? const Center(child: Text('Bu profile henüz özellik verilmedi.'))
          : ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(10),
              itemCount: _assignments.length,
              itemBuilder: (context, index) {
                final feature = _assignments[index];
                return Container(
                  width: 230,
                  margin: const EdgeInsets.only(right: 8),
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: feature.primaryColor.withValues(alpha: 0.4),
                    ),
                  ),
                  child: Row(
                    children: [
                      AnimatedPrivilegeIcon(feature: feature, size: 27),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              feature.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              feature.expiresAt == null
                                  ? 'Süresiz'
                                  : 'Bitiş: ${_date(feature.expiresAt!)}',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ],
                        ),
                      ),
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
                );
              },
            ),
    );
  }

  String _date(DateTime value) =>
      '${value.day.toString().padLeft(2, '0')}.${value.month.toString().padLeft(2, '0')}.${value.year}';
}

class _SummaryChip extends StatelessWidget {
  final String label;
  final String value;
  final bool highlight;

  const _SummaryChip({
    required this.label,
    required this.value,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    return Chip(
      backgroundColor: highlight
          ? Colors.greenAccent.withValues(alpha: 0.28)
          : Colors.white.withValues(alpha: 0.18),
      side: BorderSide.none,
      avatar: highlight
          ? const Icon(Icons.check_circle, color: Colors.white, size: 16)
          : null,
      label: Text(
        '$label: $value',
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
        ),
      ),
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
          24 + MediaQuery.of(context).viewInsets.bottom,
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
          24 + MediaQuery.of(context).viewInsets.bottom,
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
