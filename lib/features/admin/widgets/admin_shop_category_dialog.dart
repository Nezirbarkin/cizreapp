import 'package:flutter/material.dart';

import '../services/admin_shop_category_service.dart';
import 'admin_ui.dart';

/// Admin > Dükkanlar > kart menüsü "Ana kategori" (Görev 4.5).
///
/// Satıcının seçtiği ana kategoriyi değiştirir; isteğe bağlı kilitle satıcı
/// geri değiştiremez. Pasif kategoriler listede görünür ama seçilemez.
/// Kaydedilirse sonucu ([ShopCategoryChange]) döner.
class AdminShopCategoryDialog extends StatefulWidget {
  const AdminShopCategoryDialog({
    super.key,
    required this.shopId,
    required this.shopName,
    this.currentCategoryId,
    this.currentLocked = false,
    this.currentLockNote,
    this.service,
  });

  final String shopId;
  final String shopName;
  final String? currentCategoryId;
  final bool currentLocked;
  final String? currentLockNote;

  /// Testlerde sahte servis vermek için.
  final AdminShopCategoryService? service;

  static Future<ShopCategoryChange?> show(
    BuildContext context, {
    required String shopId,
    required String shopName,
    String? currentCategoryId,
    bool currentLocked = false,
    String? currentLockNote,
    AdminShopCategoryService? service,
  }) => showDialog<ShopCategoryChange>(
    context: context,
    builder: (_) => AdminShopCategoryDialog(
      shopId: shopId,
      shopName: shopName,
      currentCategoryId: currentCategoryId,
      currentLocked: currentLocked,
      currentLockNote: currentLockNote,
      service: service,
    ),
  );

  @override
  State<AdminShopCategoryDialog> createState() => _AdminShopCategoryDialogState();
}

class _AdminShopCategoryDialogState extends State<AdminShopCategoryDialog> {
  late final AdminShopCategoryService _service = widget.service ?? AdminShopCategoryService();
  late final TextEditingController _note = TextEditingController(text: widget.currentLockNote ?? '');

  List<ShopCategoryOption>? _categories;
  String? _loadError;
  late String? _selected = widget.currentCategoryId;

  /// Yönetici düzeltmesi genelde kalıcıdır: varsayılan kilitli.
  bool _lock = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loadError = null;
      _categories = null;
    });
    try {
      final list = await _service.fetchCategories();
      if (!mounted) return;
      setState(() => _categories = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = AdminShopCategoryService.errorMessage(e));
    }
  }

  Future<void> _save() async {
    final selected = _selected;
    if (selected == null) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final change = await _service.setShopCategory(
        shopId: widget.shopId,
        categoryId: selected,
        lock: _lock,
        note: _note.text,
      );
      if (!mounted) return;
      Navigator.pop(context, change);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = AdminShopCategoryService.errorMessage(e);
      });
    }
  }

  Widget _option(ShopCategoryOption option) {
    final selected = _selected == option.id;
    final current = widget.currentCategoryId == option.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Opacity(
        opacity: option.isActive ? 1 : .5,
        child: InkWell(
          key: ValueKey('shop-category-${option.id}'),
          onTap: option.isActive && !_saving ? () => setState(() => _selected = option.id) : null,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? AdminUi.brandSoft : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: selected ? AdminUi.brand : AdminUi.line),
            ),
            child: Row(
              children: [
                Text(option.emoji, style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        option.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700, color: AdminUi.ink),
                      ),
                      if (current || !option.isActive)
                        Text(
                          [if (current) 'Şu anki kategori', if (!option.isActive) 'Pasif — seçilemez'].join(' · '),
                          style: const TextStyle(fontSize: 11.5, color: AdminUi.muted),
                        ),
                    ],
                  ),
                ),
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: selected ? AdminUi.brand : AdminUi.muted,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final categories = _categories;
    return AlertDialog(
      title: const Text('Ana kategori'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.shopName,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w800, color: AdminUi.ink),
              ),
              const SizedBox(height: 4),
              const Text(
                'Mağazanın market ekranında görüneceği bölüm. Değişince satıcıya bildirim gider.',
                style: TextStyle(fontSize: 12.5, color: AdminUi.muted),
              ),
              const SizedBox(height: 12),
              if (_loadError != null) ...[
                Text(_loadError!, style: TextStyle(color: Colors.red.shade700)),
                TextButton.icon(onPressed: _load, icon: const Icon(Icons.refresh), label: const Text('Tekrar dene')),
              ] else if (categories == null)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (categories.isEmpty)
                const Text('Henüz kategori yok; önce Kategoriler menüsünden ekleyin.')
              else
                for (final option in categories) _option(option),
              const SizedBox(height: 4),
              CheckboxListTile(
                key: const ValueKey('shop-category-lock'),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _lock,
                onChanged: _saving ? null : (value) => setState(() => _lock = value ?? false),
                title: const Text('Satıcı değiştiremesin (kilitle)'),
                subtitle: Text(
                  widget.currentLocked
                      ? 'Şu an kilitli. İşareti kaldırırsanız satıcı yeniden seçebilir.'
                      : 'Kilitliyken satıcı mağaza ayarlarından kategoriyi değiştiremez.',
                ),
              ),
              TextField(
                key: const ValueKey('shop-category-note'),
                controller: _note,
                enabled: !_saving,
                maxLength: 300,
                maxLines: 2,
                minLines: 1,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Satıcıya not (isteğe bağlı)',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) Text(_error!, style: TextStyle(color: Colors.red.shade700)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.pop(context), child: const Text('Vazgeç')),
        FilledButton(
          onPressed: _saving || _selected == null || categories == null ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Kaydet'),
        ),
      ],
    );
  }
}
