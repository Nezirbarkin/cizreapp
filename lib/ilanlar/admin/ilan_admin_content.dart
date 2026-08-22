// ignore_for_file: curly_braces_in_flow_control_structures, use_build_context_synchronously

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../models/ilan_models.dart';
import '../screens/ilan_detail_screen.dart';
import '../services/ilan_service.dart';
import '../utils/ilan_ui.dart';

class IlanAdminContent extends StatefulWidget {
  const IlanAdminContent({super.key});

  @override
  State<IlanAdminContent> createState() => _IlanAdminContentState();
}

class _IlanAdminContentState extends State<IlanAdminContent> {
  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Column(
        children: [
          Material(
            color: Colors.white,
            child: TabBar(
              labelColor: Theme.of(context).colorScheme.primary,
              tabs: const [
                Tab(icon: Icon(Icons.campaign_outlined), text: 'İlanlar'),
                Tab(icon: Icon(Icons.category_outlined), text: 'Kategoriler'),
                Tab(icon: Icon(Icons.tune), text: 'Ayarlar'),
              ],
            ),
          ),
          const Expanded(
            child: TabBarView(
              children: [
                _IlanModerationTab(),
                _CategoryAdminTab(),
                _SettingsAdminTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _IlanModerationTab extends StatefulWidget {
  const _IlanModerationTab();
  @override
  State<_IlanModerationTab> createState() => _IlanModerationTabState();
}

class _IlanModerationTabState extends State<_IlanModerationTab> {
  final _service = IlanService();
  // Admin ekranı açıldığında yalnız onay bekleyenleri göstermek, yayındaki
  // ilanların "kaybolmuş" gibi görünmesine neden oluyordu. Varsayılan olarak
  // bütün durumları göster; admin isterse filtrelesin.
  String _status = 'all';
  late Future<List<Ilan>> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Ilan>> _load() => _service.getAdminIlanlar(status: _status);
  void _refresh() => setState(() {
    _future = _load();
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: DropdownButtonFormField<String>(
            initialValue: _status,
            decoration: const InputDecoration(
              labelText: 'Durum filtresi',
              border: OutlineInputBorder(),
            ),
            items: const [
              DropdownMenuItem(value: 'all', child: Text('Tüm ilanlar')),
              DropdownMenuItem(
                value: 'pending',
                child: Text('Onay bekleyenler'),
              ),
              DropdownMenuItem(value: 'published', child: Text('Yayındakiler')),
              DropdownMenuItem(value: 'rejected', child: Text('Reddedilenler')),
              DropdownMenuItem(value: 'archived', child: Text('Arşivlenenler')),
            ],
            onChanged: (value) {
              _status = value ?? 'all';
              _refresh();
            },
          ),
        ),
        Expanded(
          child: FutureBuilder<List<Ilan>>(
            future: _future,
            builder: (_, snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting)
                return const Center(child: CircularProgressIndicator());
              if (snapshot.hasError) {
                return _AdminIlanError(
                  message: IlanUi.friendlyError(snapshot.error!),
                  onRetry: _refresh,
                );
              }
              final values = snapshot.data ?? const <Ilan>[];
              if (values.isEmpty)
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.campaign_outlined,
                        size: 54,
                        color: Colors.black26,
                      ),
                      const SizedBox(height: 10),
                      const Text('Bu filtrede ilan bulunmuyor.'),
                      const SizedBox(height: 8),
                      TextButton.icon(
                        onPressed: _refresh,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Yenile'),
                      ),
                    ],
                  ),
                );
              return RefreshIndicator(
                onRefresh: () async => _refresh(),
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
                  itemCount: values.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (_, index) {
                    final ilan = values[index];
                    return Card(
                      child: ListTile(
                        leading: ilan.coverImageUrl == null
                            ? CircleAvatar(
                                child: Icon(
                                  IlanUi.icon(
                                    ilan.category?.iconName ?? 'category',
                                  ),
                                ),
                              )
                            : CircleAvatar(
                                backgroundImage: NetworkImage(
                                  ilan.coverImageUrl!,
                                ),
                              ),
                        title: Text(
                          ilan.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        subtitle: Text(
                          '${ilan.category?.name ?? 'Kategori'} • ${ilan.ownerName ?? 'Kullanıcı'}\n'
                          '${IlanUi.status(ilan.status)}'
                          '${ilan.paidFee > 0 ? ' • ${IlanUi.formatFee(ilan.paidFee)} ödendi${ilan.feeRefunded ? ' (iade edildi)' : ''}' : ''}',
                        ),
                        isThreeLine: true,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => IlanDetailScreen(ilanId: ilan.id),
                          ),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (ilan.status == IlanStatus.published)
                              IconButton(
                                tooltip: 'Onayı kaldır',
                                onPressed: () => _action(ilan, 'unapprove'),
                                icon: const Icon(
                                  Icons.unpublished_outlined,
                                  color: Colors.orange,
                                ),
                              )
                            else
                              IconButton(
                                tooltip: 'Onayla ve yayınla',
                                onPressed: () => _action(ilan, 'publish'),
                                icon: const Icon(
                                  Icons.visibility_outlined,
                                  color: Colors.green,
                                ),
                              ),
                            PopupMenuButton<String>(
                              tooltip: 'Diğer işlemler',
                              onSelected: (action) => _action(ilan, action),
                              itemBuilder: (_) => [
                                if (ilan.status != IlanStatus.published)
                                  const PopupMenuItem(
                                    value: 'publish',
                                    child: ListTile(
                                      leading: Icon(
                                        Icons.visibility_outlined,
                                        color: Colors.green,
                                      ),
                                      title: Text('Onayla ve Yayınla'),
                                    ),
                                  ),
                                if (ilan.status == IlanStatus.published)
                                  const PopupMenuItem(
                                    value: 'unapprove',
                                    child: ListTile(
                                      leading: Icon(
                                        Icons.unpublished_outlined,
                                        color: Colors.orange,
                                      ),
                                      title: Text('Onayı Kaldır'),
                                    ),
                                  ),
                                const PopupMenuItem(
                                  value: 'reject',
                                  child: ListTile(
                                    leading: Icon(Icons.block_outlined),
                                    title: Text('Reddet'),
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'archive',
                                  child: ListTile(
                                    leading: Icon(
                                      Icons.visibility_off_outlined,
                                    ),
                                    title: Text('Pasife Al / Arşivle'),
                                  ),
                                ),
                                const PopupMenuItem(
                                  value: 'delete',
                                  child: ListTile(
                                    leading: Icon(
                                      Icons.delete_forever_outlined,
                                      color: Colors.red,
                                    ),
                                    title: Text(
                                      'Kalıcı Sil',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _action(Ilan ilan, String action) async {
    if (action == 'publish') {
      await _service.updateStatus(ilan.id, IlanStatus.published);
    }
    if (action == 'unapprove') {
      await _service.updateStatus(ilan.id, IlanStatus.pending);
    }
    if (action == 'archive') {
      await _service.updateStatus(ilan.id, IlanStatus.archived);
    }
    if (action == 'delete') {
      final approved =
          await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('İlan silinsin mi?'),
              content: const Text('Bu işlem geri alınamaz.'),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Sil'),
                ),
              ],
            ),
          ) ??
          false;
      if (approved) {
        await _service.deleteIlan(ilan.id);
      }
    }
    if (!mounted) return;
    if (action == 'reject' && mounted) {
      final controller = TextEditingController();
      final reason = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Reddetme gerekçesi'),
          content: TextField(
            controller: controller,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              hintText: 'Kullanıcıya gösterilecek gerekçe',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text),
              child: const Text('Reddet'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (reason != null && reason.trim().isNotEmpty) {
        await _service.updateStatus(
          ilan.id,
          IlanStatus.rejected,
          rejectionReason: reason,
        );
      }
    }
    _refresh();
  }
}

class _AdminIlanError extends StatelessWidget {
  const _AdminIlanError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, size: 54, color: Colors.redAccent),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar Dene'),
            ),
          ],
        ),
      ),
    );
  }
}

class _CategoryAdminTab extends StatefulWidget {
  const _CategoryAdminTab();
  @override
  State<_CategoryAdminTab> createState() => _CategoryAdminTabState();
}

class _CategoryAdminTabState extends State<_CategoryAdminTab> {
  final _service = IlanService();
  late Future<List<IlanCategory>> _future;
  @override
  void initState() {
    super.initState();
    _future = _service.getCategories(admin: true);
  }

  void _refresh() => setState(() {
    _future = _service.getCategories(admin: true);
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: FutureBuilder<List<IlanCategory>>(
        future: _future,
        builder: (_, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          return ListView.separated(
            padding: const EdgeInsets.all(12),
            itemCount: snapshot.data?.length ?? 0,
            separatorBuilder: (_, __) => const SizedBox(height: 6),
            itemBuilder: (_, index) {
              final category = snapshot.data![index];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: IlanUi.color(
                      category.colorHex,
                    ).withValues(alpha: .12),
                    child: Icon(
                      IlanUi.icon(category.iconName),
                      color: IlanUi.color(category.colorHex),
                    ),
                  ),
                  title: Text(
                    category.name,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${category.type.name} • Fiyat: ${category.pricingMode.name} • '
                    'Sıra: ${category.sortOrder} • Yayın: ${IlanUi.formatFee(category.publishFee)}',
                  ),
                  trailing: Switch(
                    value: category.isActive,
                    onChanged: (value) async {
                      await _service.saveCategory(
                        _copyCategory(category, isActive: value),
                      );
                      _refresh();
                    },
                  ),
                  onTap: () => _edit(category),
                ),
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _edit(null),
        icon: const Icon(Icons.add),
        label: const Text('Kategori Ekle'),
      ),
    );
  }

  Future<void> _edit(IlanCategory? existing) async {
    final name = TextEditingController(text: existing?.name);
    final slug = TextEditingController(text: existing?.slug);
    final description = TextEditingController(text: existing?.description);
    final color = TextEditingController(text: existing?.colorHex ?? '#6D28D9');
    final order = TextEditingController(text: '${existing?.sortOrder ?? 100}');
    final fee = TextEditingController(
      text: (existing?.publishFee ?? 0).toStringAsFixed(0),
    );
    var type = existing?.type ?? IlanCategoryType.other;
    var pricing = existing?.pricingMode ?? IlanPricingMode.optional;
    var iconName = existing?.iconName ?? 'category';
    final saved =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => StatefulBuilder(
            builder: (_, setDialogState) => AlertDialog(
              title: Text(
                existing == null ? 'Kategori Ekle' : 'Kategoriyi Düzenle',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Ad'),
                    ),
                    TextField(
                      controller: slug,
                      decoration: const InputDecoration(
                        labelText: 'Slug (ornek-kategori, boş bırakılırsa addan üretilir)',
                      ),
                    ),
                    TextField(
                      controller: description,
                      decoration: const InputDecoration(labelText: 'Açıklama'),
                    ),
                    TextField(
                      controller: color,
                      decoration: const InputDecoration(
                        labelText: 'Renk (#6D28D9)',
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'Simge',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final entry in IlanUi.iconCatalog)
                          ChoiceChip(
                            label: Text(entry.$2),
                            avatar: Icon(IlanUi.icon(entry.$1), size: 18),
                            selected: iconName == entry.$1,
                            onSelected: (_) =>
                                setDialogState(() => iconName = entry.$1),
                          ),
                      ],
                    ),
                    TextField(
                      controller: order,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(labelText: 'Sıralama'),
                    ),
                    TextField(
                      controller: fee,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        labelText: 'Yayınlama ücreti (₺, 0 = ücretsiz)',
                      ),
                    ),
                    DropdownButtonFormField<IlanCategoryType>(
                      initialValue: type,
                      decoration: const InputDecoration(labelText: 'Tür'),
                      items: IlanCategoryType.values
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setDialogState(() => type = value!),
                    ),
                    DropdownButtonFormField<IlanPricingMode>(
                      initialValue: pricing,
                      decoration: const InputDecoration(
                        labelText: 'Fiyat kuralı',
                      ),
                      items: IlanPricingMode.values
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(value.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) =>
                          setDialogState(() => pricing = value!),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext, false),
                  child: const Text('Vazgeç'),
                ),
                FilledButton(
                  onPressed: () => Navigator.pop(dialogContext, true),
                  child: const Text('Kaydet'),
                ),
              ],
            ),
          ),
        ) ??
        false;
    if (saved) {
      final rawSlug = slug.text.trim().isEmpty ? name.text : slug.text;
      try {
        await _service.saveCategory(
          IlanCategory(
            id: existing?.id ?? '',
            name: name.text,
            slug: _slugify(rawSlug),
            description: description.text,
            iconName: iconName,
            colorHex: color.text.toUpperCase(),
            type: type,
            pricingMode: pricing,
            allowedConditions: existing?.allowedConditions ?? const [],
            isActive: existing?.isActive ?? true,
            sortOrder: int.tryParse(order.text) ?? 100,
            publishFee:
                double.tryParse(fee.text.trim().replaceAll(',', '.')) ?? 0,
          ),
        );
        _refresh();
      } catch (error) {
        if (mounted) {
          final message = error.toString().contains('duplicate key')
              ? 'Bu slug zaten kullanılıyor. Kategori adını veya slug alanını değiştirin.'
              : 'Kategori kaydedilemedi: $error';
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(message)));
        }
      }
    }
    name.dispose();
    slug.dispose();
    description.dispose();
    color.dispose();
    order.dispose();
    fee.dispose();
  }

  static String _slugify(String input) {
    const trMap = {
      'ç': 'c', 'Ç': 'c', 'ğ': 'g', 'Ğ': 'g', 'ı': 'i', 'I': 'i',
      'İ': 'i', 'ö': 'o', 'Ö': 'o', 'ş': 's', 'Ş': 's', 'ü': 'u', 'Ü': 'u',
    };
    var result = input.trim();
    trMap.forEach((tr, ascii) => result = result.replaceAll(tr, ascii));
    result = result
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return result.isEmpty ? 'kategori' : result;
  }

  IlanCategory _copyCategory(IlanCategory value, {required bool isActive}) =>
      IlanCategory(
        id: value.id,
        name: value.name,
        slug: value.slug,
        description: value.description,
        iconName: value.iconName,
        colorHex: value.colorHex,
        type: value.type,
        pricingMode: value.pricingMode,
        allowedConditions: value.allowedConditions,
        isActive: isActive,
        sortOrder: value.sortOrder,
        publishFee: value.publishFee,
      );
}

class _SettingsAdminTab extends StatefulWidget {
  const _SettingsAdminTab();
  @override
  State<_SettingsAdminTab> createState() => _SettingsAdminTabState();
}

class _SettingsAdminTabState extends State<_SettingsAdminTab> {
  final _service = IlanService();
  late Future<IlanSettings> _future;
  @override
  void initState() {
    super.initState();
    _future = _service.getSettings();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<IlanSettings>(
      future: _future,
      builder: (_, snapshot) {
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        return _SettingsForm(
          settings: snapshot.data!,
          onSave: (settings) async {
            await _service.updateSettings(settings);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('İlan ayarları kaydedildi.')),
              );
            }
          },
        );
      },
    );
  }
}

class _SettingsForm extends StatefulWidget {
  const _SettingsForm({required this.settings, required this.onSave});
  final IlanSettings settings;
  final Future<void> Function(IlanSettings) onSave;
  @override
  State<_SettingsForm> createState() => _SettingsFormState();
}

class _SettingsFormState extends State<_SettingsForm> {
  late IlanSettings value = widget.settings;
  bool saving = false;
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      if (!value.requireApproval)
        Container(
          margin: const EdgeInsets.only(bottom: 16),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.info.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.info.withValues(alpha: .25)),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 19, color: AppTheme.info),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Yeni ilanlar şu an doğrudan yayınlanıyor. Kötüye kullanım '
                  'durumunda ilanı reddedip/arşivleyebilirsiniz.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
        ),
      _toggle(
        'İlanlar açık',
        'Ana sayfa ve ilan listelemeyi etkinleştirir.',
        value.isEnabled,
        (v) => value = value.copyWith(isEnabled: v),
      ),
      _toggle(
        'Tüm kullanıcılar paylaşabilsin',
        'Kapalı olduğunda kullanıcılar yeni ilan oluşturamaz.',
        value.allowUserCreate,
        (v) => value = value.copyWith(allowUserCreate: v),
      ),
      _toggle(
        'Yönetici onayı zorunlu',
        'Yeni ve düzenlenen ilanlar onaya düşer.',
        value.requireApproval,
        (v) => value = value.copyWith(requireApproval: v),
      ),
      _toggle(
        'Misafirler ilanları görebilsin',
        'Giriş yapmayan ziyaretçilere açık erişim.',
        value.allowGuestView,
        (v) => value = value.copyWith(allowGuestView: v),
      ),
      _toggle(
        'Ana sayfada fiyat göster',
        'Fiyat kullanan kategorilerin fiyatını kartta gösterir.',
        value.showPricesOnHome,
        (v) => value = value.copyWith(showPricesOnHome: v),
      ),
      const SizedBox(height: 12),
      _slider(
        'Kullanıcı başına aktif ilan',
        value.maxActivePerUser,
        1,
        100,
        (v) => value = value.copyWith(maxActivePerUser: v),
      ),
      _slider(
        'İlan başına görsel',
        value.maxImagesPerIlan,
        1,
        12,
        (v) => value = value.copyWith(maxImagesPerIlan: v),
      ),
      _slider(
        'Varsayılan yayın süresi (gün)',
        value.defaultExpiryDays,
        1,
        365,
        (v) => value = value.copyWith(defaultExpiryDays: v),
      ),
      _slider(
        'Ana sayfa kategori sayısı',
        value.homeCategoryLimit,
        1,
        12,
        (v) => value = value.copyWith(homeCategoryLimit: v),
      ),
      _slider(
        'Ana sayfa ilan sayısı',
        value.homeIlanLimit,
        1,
        20,
        (v) => value = value.copyWith(homeIlanLimit: v),
      ),
      const SizedBox(height: 18),
      FilledButton.icon(
        onPressed: saving
            ? null
            : () async {
                setState(() => saving = true);
                await widget.onSave(value);
                if (mounted) setState(() => saving = false);
              },
        icon: const Icon(Icons.save),
        label: Text(saving ? 'Kaydediliyor...' : 'Ayarları Kaydet'),
      ),
    ],
  );

  Widget _toggle(
    String title,
    String subtitle,
    bool selected,
    ValueChanged<bool> change,
  ) => SwitchListTile(
    value: selected,
    title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
    subtitle: Text(subtitle),
    onChanged: (v) => setState(() => change(v)),
  );
  Widget _slider(
    String title,
    int selected,
    int min,
    int max,
    ValueChanged<int> change,
  ) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        '$title: $selected',
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
      Slider(
        value: selected.toDouble(),
        min: min.toDouble(),
        max: max.toDouble(),
        divisions: max - min,
        onChanged: (v) => setState(() => change(v.round())),
      ),
    ],
  );
}
