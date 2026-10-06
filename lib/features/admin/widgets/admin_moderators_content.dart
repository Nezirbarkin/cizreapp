import 'dart:async';

import 'package:flutter/material.dart';

import '../../moderation/models/moderation_models.dart';
import '../services/admin_moderators_service.dart';
import 'admin_ui.dart';

/// Admin > Moderatörler (Görev 4.6).
///
/// Moderatörlük, kişinin asıl rolünden bağımsız bir yetkidir (satıcı satıcı
/// kalır). Kapsamlar: Şikayetler, İçerik, İlanlar, Canlı yayınlar. Yetki
/// kontrolü sunucuda (`auth_is_moderator`); her değişiklik denetim günlüğüne
/// yazılır ve kişiye bildirim gider. İlanlar ve Canlı yayınlar kapsamında
/// yönetici kategori seçebilir (ilan / mağaza kategorisi; boş = tümü).
class AdminModeratorsContent extends StatefulWidget {
  const AdminModeratorsContent({super.key, this.service});

  /// Testlerde sahte servis vermek için.
  final AdminModeratorsService? service;

  @override
  State<AdminModeratorsContent> createState() => _AdminModeratorsContentState();
}

void _snack(BuildContext context, String text, {bool error = false}) {
  ScaffoldMessenger.maybeOf(context)
    ?..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red.shade700 : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
}

class _AdminModeratorsContentState extends State<AdminModeratorsContent> {
  late final AdminModeratorsService _service = widget.service ?? AdminModeratorsService();

  List<AdminModerator> _moderators = const [];
  bool _loading = true;
  String? _error;
  String? _busyUser;

  /// Kategori seçenekleri (ilk düzenlemede yüklenir; alınamazsa kategoriler
  /// değiştirilmez).
  ModerationCategoryOptions? _categories;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final list = await _service.list();
      if (!mounted) return;
      setState(() {
        _moderators = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        if (!silent || _moderators.isEmpty) _error = AdminModeratorsService.errorMessage(e);
      });
    }
  }

  Future<void> _save(
    String userId,
    String name,
    Set<ModerationScope> scopes,
    String? note, {
    List<String>? ilanCategoryIds,
    List<String>? shopCategoryIds,
  }) async {
    setState(() => _busyUser = userId);
    try {
      final saved = await _service.setModerator(
        userId,
        scopes,
        note: note,
        ilanCategoryIds: ilanCategoryIds,
        shopCategoryIds: shopCategoryIds,
      );
      if (!mounted) return;
      _snack(context, saved.isEmpty ? '$name moderatörlükten çıkarıldı' : '$name: ${_labels(saved)}');
    } catch (e) {
      if (!mounted) return;
      _snack(context, AdminModeratorsService.errorMessage(e), error: true);
    } finally {
      if (mounted) setState(() => _busyUser = null);
    }
    await _load(silent: true);
  }

  static String _labels(Set<ModerationScope> scopes) => [
    for (final s in ModerationScope.values)
      if (scopes.contains(s)) s.label,
  ].join(', ');

  Future<ModerationCategoryOptions?> _loadCategories() async {
    if (_categories != null) return _categories;
    try {
      final options = await _service.fetchCategories();
      if (mounted) _categories = options;
      return options;
    } catch (e) {
      if (mounted) _snack(context, 'Kategoriler alınamadı; kategori sınırı değiştirilmeyecek.', error: true);
      return null;
    }
  }

  Future<void> _add() async {
    final candidate = await showDialog<ModeratorCandidate>(
      context: context,
      builder: (_) => _PickUserDialog(service: _service, existing: {for (final m in _moderators) m.userId}),
    );
    if (candidate == null || !mounted) return;
    final categories = await _loadCategories();
    if (!mounted) return;
    final result = await showDialog<_ScopesResult>(
      context: context,
      builder: (_) => _ScopesDialog(
        title: candidate.displayName,
        initial: const {},
        initialNote: '',
        categories: categories,
      ),
    );
    if (result == null || result.scopes.isEmpty || !mounted) return;
    await _save(
      candidate.id,
      candidate.displayName,
      result.scopes,
      result.note,
      ilanCategoryIds: result.ilanCategoryIds,
      shopCategoryIds: result.shopCategoryIds,
    );
  }

  Future<void> _edit(AdminModerator moderator) async {
    final categories = await _loadCategories();
    if (!mounted) return;
    final result = await showDialog<_ScopesResult>(
      context: context,
      builder: (_) => _ScopesDialog(
        title: moderator.displayName,
        initial: moderator.scopes,
        initialNote: moderator.note ?? '',
        categories: categories,
        initialIlanCategories: moderator.ilanCategories,
        initialShopCategories: moderator.shopCategories,
      ),
    );
    if (result == null || !mounted) return;
    await _save(
      moderator.userId,
      moderator.displayName,
      result.scopes,
      result.note,
      ilanCategoryIds: result.ilanCategoryIds,
      shopCategoryIds: result.shopCategoryIds,
    );
  }

  Future<void> _remove(AdminModerator moderator) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Moderatörlük kaldırılsın mı?'),
        content: Text('${moderator.displayName} artık moderasyon yapamaz; kendisine bildirim gider.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            child: const Text('Kaldır'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    await _save(moderator.userId, moderator.displayName, const {}, moderator.note);
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AdminUi.page,
      child: RefreshIndicator(
        onRefresh: () => _load(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          children: [
            AdminCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.shield_outlined, color: AdminUi.ink),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Moderatörler',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AdminUi.ink),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Moderatör, rolünü kaybetmeden (ör. satıcı) seçtiğin alanlarda moderasyon yapar. '
                    'Ayarlar menüsünde "Moderasyon Paneli" görür; her işlemi denetim günlüğüne yazılır. '
                    'Askıya alınan moderatörün yetkisi kendiliğinden düşer.',
                    style: TextStyle(fontSize: 12.5, color: AdminUi.muted, height: 1.4),
                  ),
                  const SizedBox(height: 8),
                  for (final scope in ModerationScope.values)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(scope.icon, size: 16, color: AdminUi.brand),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              '${scope.label}: ${scope.description}',
                              style: const TextStyle(fontSize: 12.5, color: AdminUi.ink),
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 10),
                  Align(
                    alignment: Alignment.centerRight,
                    child: FilledButton.icon(
                      key: const ValueKey('add-moderator'),
                      onPressed: _busyUser == null ? _add : null,
                      icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                      label: const Text('Moderatör ekle'),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            if (_loading)
              const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator()))
            else if (_error != null && _moderators.isEmpty)
              AdminEmpty(
                icon: Icons.error_outline,
                title: 'Moderatörler alınamadı',
                subtitle: _error,
                action: OutlinedButton(onPressed: _load, child: const Text('Tekrar dene')),
              )
            else if (_moderators.isEmpty)
              const AdminEmpty(
                icon: Icons.shield_outlined,
                title: 'Henüz moderatör yok',
                subtitle: '"Moderatör ekle" ile bir kullanıcıya yetki verebilirsin.',
              )
            else
              for (final moderator in _moderators) ...[
                _ModeratorCard(
                  moderator: moderator,
                  busy: _busyUser == moderator.userId,
                  onEdit: () => _edit(moderator),
                  onRemove: () => _remove(moderator),
                ),
                const SizedBox(height: 10),
              ],
          ],
        ),
      ),
    );
  }
}

class _ModeratorCard extends StatelessWidget {
  const _ModeratorCard({required this.moderator, required this.busy, required this.onEdit, required this.onRemove});

  static String _names(List<ModCategory> categories) =>
      categories.isEmpty ? 'kategori kalmadı' : modCategoryNames(categories)!;

  final AdminModerator moderator;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return AdminCard(
      key: ValueKey('moderator-${moderator.userId}'),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AdminAvatar(url: moderator.avatarUrl, name: moderator.displayName, radius: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      moderator.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AdminUi.ink),
                    ),
                    if (moderator.username != null)
                      Text(
                        '@${moderator.username}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12.5, color: AdminUi.muted),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final scope in ModerationScope.values)
                if (moderator.scopes.contains(scope)) AdminPill(label: scope.label, color: AdminUi.brand, icon: scope.icon),
              if (moderator.scopes.contains(ModerationScope.ilanlar) && moderator.ilanCategories != null)
                AdminPill(
                  label: 'İlan: ${_names(moderator.ilanCategories!)}',
                  color: Colors.teal.shade700,
                  icon: Icons.filter_alt_outlined,
                ),
              if (moderator.scopes.contains(ModerationScope.live) && moderator.shopCategories != null)
                AdminPill(
                  label: 'Mağaza: ${_names(moderator.shopCategories!)}',
                  color: Colors.deepOrange.shade700,
                  icon: Icons.filter_alt_outlined,
                ),
              if (moderator.role != null) AdminPill(label: 'Rol: ${moderator.role}', color: Colors.blueGrey),
              if (moderator.isSuspended)
                AdminPill(label: 'Askıda — yetkisi geçersiz', color: Colors.red.shade700, icon: Icons.block),
            ],
          ),
          if (moderator.note != null && moderator.note!.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Not: ${moderator.note}', style: const TextStyle(fontSize: 12.5, color: AdminUi.ink)),
          ],
          const SizedBox(height: 6),
          Text(
            [
              'Atayan: ${moderator.grantedByName ?? '—'} · ${adminDate(moderator.createdAt)}',
              '30 günde ${moderator.actions30d} işlem',
            ].join(' · '),
            style: const TextStyle(fontSize: 12, color: AdminUi.muted),
          ),
          const SizedBox(height: 8),
          if (busy)
            const LinearProgressIndicator(minHeight: 3)
          else
            Align(
              alignment: Alignment.centerRight,
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: onRemove,
                    style: TextButton.styleFrom(foregroundColor: Colors.red.shade700),
                    child: const Text('Kaldır'),
                  ),
                  OutlinedButton(onPressed: onEdit, child: const Text('Yetkileri düzenle')),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Kullanıcı ara ve seç (en az 2 karakter; 350 ms gecikmeli).
class _PickUserDialog extends StatefulWidget {
  const _PickUserDialog({required this.service, required this.existing});

  final AdminModeratorsService service;
  final Set<String> existing;

  @override
  State<_PickUserDialog> createState() => _PickUserDialogState();
}

class _PickUserDialogState extends State<_PickUserDialog> {
  final _query = TextEditingController();
  Timer? _debounce;
  List<ModeratorCandidate> _results = const [];
  bool _searching = false;
  String? _error;
  int _seq = 0;

  @override
  void dispose() {
    _debounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), _search);
  }

  Future<void> _search() async {
    final seq = ++_seq;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final list = await widget.service.searchUsers(_query.text);
      if (!mounted || seq != _seq) return;
      setState(() {
        _results = list;
        _searching = false;
      });
    } catch (e) {
      if (!mounted || seq != _seq) return;
      setState(() {
        _searching = false;
        _error = AdminModeratorsService.errorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Moderatör ekle'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              key: const ValueKey('moderator-search'),
              controller: _query,
              autofocus: true,
              onChanged: _onChanged,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: 'Ad, kullanıcı adı ya da e-posta',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            if (_searching)
              const Padding(padding: EdgeInsets.all(12), child: Center(child: CircularProgressIndicator()))
            else if (_error != null)
              Text(_error!, style: TextStyle(color: Colors.red.shade700))
            else if (_query.text.trim().length >= 2 && _results.isEmpty)
              const Padding(
                padding: EdgeInsets.all(8),
                child: Text('Sonuç yok', style: TextStyle(color: AdminUi.muted)),
              )
            else
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final c in _results)
                      ListTile(
                        key: ValueKey('candidate-${c.id}'),
                        contentPadding: EdgeInsets.zero,
                        leading: AdminAvatar(url: c.avatarUrl, name: c.displayName, radius: 18),
                        title: Text(c.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                          c.isAdmin
                              ? 'Yönetici — zaten tüm yetkilere sahip'
                              : widget.existing.contains(c.id)
                              ? 'Zaten moderatör'
                              : (c.username == null ? '' : '@${c.username}'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        enabled: !c.isAdmin && !widget.existing.contains(c.id),
                        onTap: () => Navigator.pop(context, c),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç'))],
    );
  }
}

/// Yetki penceresinin sonucu. Kategori listeleri: null = değiştirme (kapsam
/// seçili değil, seçime dokunulmadı ya da seçenekler alınamadı), boş = tüm
/// kategoriler.
typedef _ScopesResult = ({
  Set<ModerationScope> scopes,
  String note,
  List<String>? ilanCategoryIds,
  List<String>? shopCategoryIds,
});

/// Kapsam seçimi + kategori sınırı + not. Boş kapsamla kaydetmek "kaldır"
/// demektir (düzenlemede).
class _ScopesDialog extends StatefulWidget {
  const _ScopesDialog({
    required this.title,
    required this.initial,
    required this.initialNote,
    this.categories,
    this.initialIlanCategories,
    this.initialShopCategories,
  });

  final String title;
  final Set<ModerationScope> initial;
  final String initialNote;

  /// null = seçenekler alınamadı → kategori seçimi gösterilmez, değişmez.
  final ModerationCategoryOptions? categories;
  final List<ModCategory>? initialIlanCategories;
  final List<ModCategory>? initialShopCategories;

  @override
  State<_ScopesDialog> createState() => _ScopesDialogState();
}

class _ScopesDialogState extends State<_ScopesDialog> {
  late final Set<ModerationScope> _scopes = {...widget.initial};
  late final TextEditingController _note = TextEditingController(text: widget.initialNote);

  /// Boş küme = tüm kategoriler. Artık olmayan kategoriler başta ayıklanır.
  late Set<String> _ilan = _known(widget.initialIlanCategories, widget.categories?.ilan);
  late Set<String> _shop = _known(widget.initialShopCategories, widget.categories?.shop);

  /// Seçime dokunulmadıysa sunucuya "değiştirme" (null) gider. Aksi hâlde
  /// sınırladığı kategorilerin hepsi silinmiş bir moderatörün ayıklanmış boş
  /// seçimi "tümü" diye kaydedilir ve yetkisi sessizce genişlerdi.
  bool _ilanTouched = false;
  bool _shopTouched = false;

  static Set<String> _known(List<ModCategory>? initial, List<ModCategory>? options) {
    if (initial == null || options == null) return {};
    final ids = {for (final c in options) c.id};
    return {for (final c in initial) if (ids.contains(c.id)) c.id};
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  List<String>? _result(ModerationScope scope, Set<String> selected, List<ModCategory>? options, bool touched) {
    if (options == null || !touched || !_scopes.contains(scope)) return null;
    return [for (final c in options) if (selected.contains(c.id)) c.id];
  }

  /// Sınırlı moderatörün atanmış kategorilerinin hiçbiri artık yok (silinmiş):
  /// o alanda yetkisi yoktur. Dokunulana kadar "Tümü" seçili GÖSTERİLMEZ.
  static bool _orphaned(List<ModCategory>? initial, Set<String> selected, bool touched) =>
      !touched && initial != null && selected.isEmpty;

  Widget _categoryPicker({
    required String keyPrefix,
    required String title,
    required List<ModCategory> options,
    required Set<String> selected,
    required bool orphaned,
    required ValueChanged<Set<String>> onChanged,
  }) {
    return Padding(
      key: ValueKey('$keyPrefix-picker'),
      padding: const EdgeInsets.fromLTRB(12, 0, 0, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: AdminUi.muted)),
          const SizedBox(height: 4),
          if (orphaned)
            Padding(
              key: ValueKey('$keyPrefix-orphaned'),
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                'Atanan kategorilerin hiçbiri artık yok; bu alanda yetkisi kalmadı. Seçim yapmazsan böyle kalır.',
                style: TextStyle(fontSize: 12.5, color: Colors.orange.shade900),
              ),
            ),
          if (options.isEmpty)
            const Text('Tanımlı kategori yok', style: TextStyle(fontSize: 12.5, color: AdminUi.muted))
          else
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                FilterChip(
                  key: ValueKey('$keyPrefix-all'),
                  label: const Text('Tümü'),
                  selected: selected.isEmpty && !orphaned,
                  onSelected: (_) => onChanged(const {}),
                ),
                for (final category in options)
                  FilterChip(
                    key: ValueKey('$keyPrefix-${category.id}'),
                    label: Text(category.isActive ? category.name : '${category.name} (pasif)'),
                    selected: selected.contains(category.id),
                    onSelected: (value) {
                      final next = {...selected};
                      if (value) {
                        next.add(category.id);
                      } else {
                        next.remove(category.id);
                      }
                      onChanged(next);
                    },
                  ),
              ],
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final removing = widget.initial.isNotEmpty && _scopes.isEmpty;
    final categories = widget.categories;
    return AlertDialog(
      title: Text(widget.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Yetki alanları', style: TextStyle(fontWeight: FontWeight.w700)),
            for (final scope in ModerationScope.values) ...[
              CheckboxListTile(
                key: ValueKey('scope-${scope.key}'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _scopes.contains(scope),
                onChanged: (value) => setState(() {
                  if (value == true) {
                    _scopes.add(scope);
                  } else {
                    _scopes.remove(scope);
                  }
                }),
                title: Text(scope.label),
                subtitle: Text(scope.description),
              ),
              if (categories != null && scope == ModerationScope.ilanlar && _scopes.contains(scope))
                _categoryPicker(
                  keyPrefix: 'mod-ilan-cat',
                  title: 'Hangi ilan kategorileri?',
                  options: categories.ilan,
                  selected: _ilan,
                  orphaned: _orphaned(widget.initialIlanCategories, _ilan, _ilanTouched),
                  onChanged: (value) => setState(() {
                    _ilan = value;
                    _ilanTouched = true;
                  }),
                ),
              if (categories != null && scope == ModerationScope.live && _scopes.contains(scope))
                _categoryPicker(
                  keyPrefix: 'mod-shop-cat',
                  title: 'Hangi mağaza kategorileri?',
                  options: categories.shop,
                  selected: _shop,
                  orphaned: _orphaned(widget.initialShopCategories, _shop, _shopTouched),
                  onChanged: (value) => setState(() {
                    _shop = value;
                    _shopTouched = true;
                  }),
                ),
            ],
            if (categories == null && (_scopes.contains(ModerationScope.ilanlar) || _scopes.contains(ModerationScope.live)))
              const Padding(
                padding: EdgeInsets.only(bottom: 8),
                child: Text(
                  'Kategoriler alınamadı; mevcut kategori sınırı korunur.',
                  style: TextStyle(fontSize: 12.5, color: AdminUi.muted),
                ),
              ),
            TextField(
              key: const ValueKey('moderator-note'),
              controller: _note,
              maxLength: 300,
              maxLines: 2,
              minLines: 1,
              decoration: const InputDecoration(labelText: 'Not (isteğe bağlı)', border: OutlineInputBorder()),
            ),
            if (removing)
              Text(
                'Hiçbir alan seçili değil: kaydedince moderatörlükten çıkarılır.',
                style: TextStyle(fontSize: 12.5, color: Colors.red.shade700),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: widget.initial.isEmpty && _scopes.isEmpty
              ? null
              : () => Navigator.pop<_ScopesResult>(context, (
                  scopes: {..._scopes},
                  note: _note.text.trim(),
                  ilanCategoryIds: _result(ModerationScope.ilanlar, _ilan, categories?.ilan, _ilanTouched),
                  shopCategoryIds: _result(ModerationScope.live, _shop, categories?.shop, _shopTouched),
                )),
          child: Text(removing ? 'Kaldır' : 'Kaydet'),
        ),
      ],
    );
  }
}
