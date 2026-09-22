// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';

import '../../../core/models/seller_announcement_model.dart';
import '../../../core/services/seller_announcement_service.dart';
import '../../seller/widgets/seller_announcement_card.dart';
import '../widgets/admin_ui.dart';

/// Admin > Satıcı Duyuruları > yeni / düzenle.
///
/// Solda (dar ekranda üstte) form, sağda canlı önizleme: satıcı kartı tam da
/// burada göründüğü gibi görür, çünkü ikisi de [SellerAnnouncementCard]'ı çizer.
/// Kaydedilirse `true` ile kapanır.
class SellerAnnouncementEditorScreen extends StatefulWidget {
  const SellerAnnouncementEditorScreen({super.key, this.initial, this.service});

  final SellerAnnouncement? initial;

  /// Testlerde sahte servis vermek için.
  final SellerAnnouncementService? service;

  @override
  State<SellerAnnouncementEditorScreen> createState() =>
      _SellerAnnouncementEditorScreenState();
}

class _SellerAnnouncementEditorScreenState
    extends State<SellerAnnouncementEditorScreen> {
  static const int _titleMax = 60;
  static const int _messageMax = 160;
  static const int _labelMax = 30;

  late final SellerAnnouncementService _service =
      widget.service ?? SellerAnnouncementService();
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleC;
  late final TextEditingController _messageC;
  late final TextEditingController _labelC;
  late final TextEditingController _urlC;

  late AnnouncementType _type;
  late AnnouncementAudience _audience;
  late AnnouncementTarget _target;
  late bool _hasAction;
  late bool _dismissible;
  late bool _pinned;
  late Set<String> _shopIds;
  DateTime? _startsAt;
  DateTime? _endsAt;

  List<({String id, String name})>? _allShops;
  String? _shopError;
  String? _dateError;
  bool _saving = false;

  bool get _isEdit => widget.initial?.id != null;

  @override
  void initState() {
    super.initState();
    final i = widget.initial;
    _titleC = TextEditingController(text: i?.title ?? '');
    _messageC = TextEditingController(text: i?.message ?? '');
    _labelC = TextEditingController(text: i?.actionLabel ?? '');
    _urlC = TextEditingController(text: i?.actionUrl ?? '');
    for (final c in [_titleC, _messageC, _labelC, _urlC]) {
      c.addListener(() => setState(() {}));
    }
    _type = i?.type ?? AnnouncementType.info;
    _audience = i?.audience ?? AnnouncementAudience.all;
    _target = i?.actionTarget ?? AnnouncementTarget.products;
    _hasAction = i?.hasAction ?? false;
    _dismissible = i?.isDismissible ?? true;
    _pinned = i?.isPinned ?? false;
    _shopIds = {...?i?.shopIds};
    _startsAt = i?.startsAt;
    _endsAt = i?.endsAt;
    if (_audience == AnnouncementAudience.shops) _loadShops();
  }

  @override
  void dispose() {
    _titleC.dispose();
    _messageC.dispose();
    _labelC.dispose();
    _urlC.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Veri
  // -------------------------------------------------------------------------

  Future<List<({String id, String name})>> _loadShops() async {
    final cached = _allShops;
    if (cached != null) return cached;
    final list = await _service.fetchShopsForPicker();
    if (mounted) setState(() => _allShops = list);
    return list;
  }

  String _shopName(String id) {
    for (final s in _allShops ?? const <({String id, String name})>[]) {
      if (s.id == id) return s.name;
    }
    return 'Mağaza';
  }

  Future<void> _pickShops() async {
    List<({String id, String name})> shops;
    try {
      shops = await _loadShops();
    } catch (e) {
      _snack('Mağazalar yüklenemedi: ${_clean(e)}', error: true);
      return;
    }
    if (!mounted) return;
    final picked = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ShopPickerSheet(shops: shops, selected: _shopIds),
    );
    if (picked != null) {
      setState(() {
        _shopIds = picked;
        _shopError = null;
      });
    }
  }

  Future<void> _pickDate({required bool start}) async {
    final now = DateTime.now();
    final current = (start ? _startsAt : _endsAt) ?? now;
    final d = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(now.year - 1),
      lastDate: DateTime(now.year + 3),
    );
    if (d == null) return;
    setState(() {
      _dateError = null;
      // Başlangıç günün başı, bitiş günün sonu: seçilen gün tam kapsansın.
      if (start) {
        _startsAt = DateTime(d.year, d.month, d.day);
      } else {
        _endsAt = DateTime(d.year, d.month, d.day, 23, 59);
      }
    });
  }

  // -------------------------------------------------------------------------
  // Kaydet
  // -------------------------------------------------------------------------

  SellerAnnouncement _build({required bool publish}) => SellerAnnouncement(
        id: widget.initial?.id,
        type: _type,
        title: _titleC.text,
        message: _messageC.text,
        actionLabel: _hasAction ? _labelC.text : null,
        actionTarget: _hasAction ? _target : null,
        actionUrl: _hasAction && _target == AnnouncementTarget.url
            ? _urlC.text
            : null,
        audience: _audience,
        shopIds: _shopIds.toList(),
        isDismissible: _type != AnnouncementType.urgent && _dismissible,
        isPinned: _pinned,
        isPublished: publish,
        startsAt: _startsAt,
        endsAt: _endsAt,
      );

  bool _validateExtras() {
    var ok = true;
    String? shopError;
    String? dateError;
    if (_audience == AnnouncementAudience.shops && _shopIds.isEmpty) {
      shopError = 'En az bir mağaza seçin.';
      ok = false;
    }
    final start = _startsAt ?? DateTime.now();
    if (_endsAt != null && !_endsAt!.isAfter(start)) {
      dateError = 'Bitiş tarihi başlangıçtan sonra olmalı.';
      ok = false;
    }
    setState(() {
      _shopError = shopError;
      _dateError = dateError;
    });
    return ok;
  }

  Future<void> _save({required bool publish}) async {
    final formOk = _formKey.currentState?.validate() ?? false;
    final extrasOk = _validateExtras();
    if (!formOk || !extrasOk) return;
    setState(() => _saving = true);
    try {
      await _service.save(_build(publish: publish));
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _snack('Kaydedilemedi: ${_clean(e)}', error: true);
    }
  }

  String _clean(Object e) =>
      e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');

  void _snack(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red.shade700 : null,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Arayüz
  // -------------------------------------------------------------------------

  InputDecoration _dec(String label, {String? hint, String? helper}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        helperText: helper,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      );

  Widget _section(String title, List<Widget> children) => AdminCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AdminUi.muted,
                letterSpacing: 0.2,
              ),
            ),
            const SizedBox(height: 12),
            ...children,
          ],
        ),
      );

  Widget _previewPanel() {
    final label = _labelC.text.trim();
    final item = SellerAnnouncement(
      type: _type,
      title: _titleC.text.trim().isEmpty ? 'Başlık yazın' : _titleC.text.trim(),
      message: _messageC.text.trim().isEmpty
          ? 'Mesajınız burada görünecek.'
          : _messageC.text.trim(),
      actionLabel: _hasAction ? (label.isEmpty ? 'Eylem' : label) : null,
      actionTarget: _hasAction ? _target : null,
      isDismissible: _type != AnnouncementType.urgent && _dismissible,
      isNew: true,
    );
    return AdminCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'SATICININ GÖRECEĞİ GÖRÜNÜM',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: AdminUi.muted,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
            decoration: BoxDecoration(
              color: const Color(0xFFF5F5F5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: SellerAnnouncementCard(
              item: item,
              onDismiss: item.isDismissible ? () {} : null,
              onAction: item.hasAction ? () {} : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _contentSection() {
    final style = _type.style;
    return _section('İÇERİK', [
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final t in AnnouncementType.values)
            ChoiceChip(
              selected: _type == t,
              showCheckmark: false,
              avatar: Icon(t.style.icon, size: 16, color: t.style.iconColor),
              label: Text(t.style.label),
              selectedColor: t.style.iconBackground,
              onSelected: (_) => setState(() {
                _type = t;
                if (t == AnnouncementType.urgent) _dismissible = false;
              }),
            ),
        ],
      ),
      const SizedBox(height: 6),
      Text(style.hint, style: const TextStyle(fontSize: 12, color: AdminUi.muted)),
      const SizedBox(height: 14),
      TextFormField(
        controller: _titleC,
        maxLength: _titleMax,
        textCapitalization: TextCapitalization.sentences,
        decoration: _dec('Başlık'),
        validator: (v) =>
            (v ?? '').trim().isEmpty ? 'Bir başlık yazın.' : null,
      ),
      const SizedBox(height: 6),
      TextFormField(
        controller: _messageC,
        maxLength: _messageMax,
        minLines: 3,
        maxLines: 5,
        textCapitalization: TextCapitalization.sentences,
        decoration: _dec('Mesaj'),
        validator: (v) =>
            (v ?? '').trim().isEmpty ? 'Bir mesaj yazın.' : null,
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _hasAction,
        onChanged: (v) => setState(() => _hasAction = v),
        title: const Text('Eylem butonu ekle'),
        subtitle: const Text('Kartın altında satıcıyı bir ekrana götüren bağlantı.'),
      ),
      if (_hasAction) ...[
        const SizedBox(height: 4),
        TextFormField(
          controller: _labelC,
          maxLength: _labelMax,
          decoration: _dec('Buton yazısı', hint: 'Ürünlerim'),
          validator: (v) => _hasAction && (v ?? '').trim().isEmpty
              ? 'Buton yazısını girin.'
              : null,
        ),
        const SizedBox(height: 6),
        DropdownButtonFormField<AnnouncementTarget>(
          initialValue: _target,
          decoration: _dec('Nereye gitsin'),
          items: [
            for (final t in AnnouncementTarget.values)
              DropdownMenuItem(value: t, child: Text(t.label)),
          ],
          onChanged: (v) => setState(() => _target = v ?? _target),
        ),
        if (_target == AnnouncementTarget.url) ...[
          const SizedBox(height: 12),
          TextFormField(
            controller: _urlC,
            keyboardType: TextInputType.url,
            decoration: _dec('Bağlantı', hint: 'https://…'),
            validator: (v) {
              if (!_hasAction || _target != AnnouncementTarget.url) return null;
              final t = (v ?? '').trim();
              if (!RegExp(r'^https://\S+$', caseSensitive: false).hasMatch(t)) {
                return 'https:// ile başlayan bir bağlantı girin.';
              }
              return null;
            },
          ),
        ],
      ],
    ]);
  }

  Widget _dateTile({required bool start}) {
    final value = start ? _startsAt : _endsAt;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _pickDate(start: start),
        child: InputDecorator(
          decoration: _dec(start ? 'Başlangıç' : 'Bitiş').copyWith(
            suffixIcon: value == null
                ? const Icon(Icons.calendar_today_outlined, size: 18)
                : IconButton(
                    icon: const Icon(Icons.close_rounded, size: 18),
                    tooltip: 'Temizle',
                    onPressed: () => setState(() {
                      _dateError = null;
                      if (start) {
                        _startsAt = null;
                      } else {
                        _endsAt = null;
                      }
                    }),
                  ),
          ),
          child: Text(
            value == null ? (start ? 'Hemen' : 'Süresiz') : adminDate(value),
            style: TextStyle(
              color: value == null ? AdminUi.muted : AdminUi.ink,
            ),
          ),
        ),
      ),
    );
  }

  Widget _audienceSection() {
    return _section('KİME VE NE ZAMAN', [
      DropdownButtonFormField<AnnouncementAudience>(
        initialValue: _audience,
        decoration: _dec('Kimlere gösterilsin'),
        items: [
          for (final a in AnnouncementAudience.values)
            DropdownMenuItem(value: a, child: Text(a.label)),
        ],
        onChanged: (v) {
          setState(() {
            _audience = v ?? _audience;
            _shopError = null;
          });
          if (_audience == AnnouncementAudience.shops) _loadShops();
        },
      ),
      if (_audience == AnnouncementAudience.shops) ...[
        const SizedBox(height: 10),
        if (_shopIds.isNotEmpty)
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              for (final id in _shopIds)
                InputChip(
                  label: Text(_shopName(id)),
                  onDeleted: () => setState(() => _shopIds = {..._shopIds}..remove(id)),
                ),
            ],
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: _pickShops,
            icon: const Icon(Icons.storefront_outlined, size: 18),
            label: Text(
              _shopIds.isEmpty
                  ? 'Mağaza seç'
                  : 'Mağaza seç (${_shopIds.length})',
            ),
          ),
        ),
        if (_shopError != null)
          Text(_shopError!, style: TextStyle(color: Colors.red.shade700, fontSize: 12.5)),
      ],
      const SizedBox(height: 14),
      Row(
        children: [
          _dateTile(start: true),
          const SizedBox(width: 10),
          _dateTile(start: false),
        ],
      ),
      if (_dateError != null) ...[
        const SizedBox(height: 6),
        Text(_dateError!, style: TextStyle(color: Colors.red.shade700, fontSize: 12.5)),
      ],
    ]);
  }

  Widget _behaviorSection() {
    final urgent = _type == AnnouncementType.urgent;
    return _section('DAVRANIŞ', [
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: !urgent && _dismissible,
        onChanged: urgent ? null : (v) => setState(() => _dismissible = v),
        title: const Text('Satıcı kartı kapatabilsin'),
        subtitle: Text(
          urgent
              ? 'Acil kartlar kapatılamaz.'
              : 'Kapatan satıcıya kart bir daha gösterilmez.',
        ),
      ),
      SwitchListTile(
        contentPadding: EdgeInsets.zero,
        value: _pinned,
        onChanged: (v) => setState(() => _pinned = v),
        title: const Text('En üste sabitle'),
        subtitle: const Text('Acil kartlardan sonra, diğerlerinin önünde durur.'),
      ),
    ]);
  }

  Widget _actions() {
    final published = widget.initial?.isPublished ?? false;
    return Row(
      children: [
        Expanded(
          child: OutlinedButton(
            onPressed: _saving ? null : () => _save(publish: false),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text(published ? 'Taslağa al' : 'Taslak kaydet'),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton(
            onPressed: _saving ? null : () => _save(publish: true),
            style: FilledButton.styleFrom(
              backgroundColor: AdminUi.brand,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : Text(published ? 'Güncelle' : 'Yayınla'),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdminUi.page,
      appBar: AppBar(
        backgroundColor: Colors.purple.shade700,
        foregroundColor: Colors.white,
        title: Text(_isEdit ? 'Duyuruyu düzenle' : 'Yeni duyuru'),
      ),
      body: Form(
        key: _formKey,
        child: LayoutBuilder(
          builder: (context, c) {
            final form = <Widget>[
              _contentSection(),
              const SizedBox(height: 12),
              _audienceSection(),
              const SizedBox(height: 12),
              _behaviorSection(),
              const SizedBox(height: 16),
              _actions(),
            ];
            if (c.maxWidth >= 900) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ListView(padding: const EdgeInsets.all(16), children: form),
                  ),
                  SizedBox(
                    width: 380,
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
                      children: [_previewPanel()],
                    ),
                  ),
                ],
              );
            }
            return ListView(
              padding: const EdgeInsets.all(16),
              children: [_previewPanel(), const SizedBox(height: 12), ...form],
            );
          },
        ),
      ),
    );
  }
}

/// Mağaza çoklu seçici: arama + onay kutuları.
class _ShopPickerSheet extends StatefulWidget {
  const _ShopPickerSheet({required this.shops, required this.selected});

  final List<({String id, String name})> shops;
  final Set<String> selected;

  @override
  State<_ShopPickerSheet> createState() => _ShopPickerSheetState();
}

class _ShopPickerSheetState extends State<_ShopPickerSheet> {
  late final Set<String> _selected = {...widget.selected};
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    final visible = widget.shops
        .where((s) => q.isEmpty || s.name.toLowerCase().contains(q))
        .toList();
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scroll) => Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                onChanged: (v) => setState(() => _query = v),
                decoration: InputDecoration(
                  hintText: 'Mağaza ara',
                  prefixIcon: const Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                controller: scroll,
                itemCount: visible.length,
                itemBuilder: (context, i) {
                  final s = visible[i];
                  return CheckboxListTile(
                    value: _selected.contains(s.id),
                    title: Text(s.name),
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selected.add(s.id);
                      } else {
                        _selected.remove(s.id);
                      }
                    }),
                  );
                },
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _selected),
                    style: FilledButton.styleFrom(
                      backgroundColor: AdminUi.brand,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text('Tamam (${_selected.length} seçili)'),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
