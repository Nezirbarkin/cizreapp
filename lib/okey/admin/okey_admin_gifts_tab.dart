import 'package:flutter/material.dart';

import '../widgets/okey_gift_badge.dart';
import 'okey_admin_service.dart';

/// Admin panelindeki HEDİYE YÖNETİMİ (kullanıcı isteği, 2026-09-05:
/// "hediyeler ... admin 101 okey yönetiminde düzenlenebilir").
///
/// ## İki ayrı karar, iki ayrı bölüm
///
///  1. **Katalog** — hangi hediyeler var, ne kadar, hangi sırada, açık mı.
///  2. **Alıcı payı** — gönderilen puanın yüzde kaçı ALICIYA geçer, kalanı
///     sistem kazancıdır. Bu tek sayı hediyenin ne olduğunu belirler:
///     %0'da saf bir jest ve puan musluğu kapatıcı, %100'de iki hesap
///     arasında serbest puan transferi. Aynı ekranda ama ayrı bir kutuda
///     duruyor çünkü bir hediyenin fiyatını değiştirmekle ekonominin
///     yönünü değiştirmek aynı ağırlıkta işler değil.
class OkeyAdminGiftsTab extends StatefulWidget {
  const OkeyAdminGiftsTab({super.key});

  @override
  State<OkeyAdminGiftsTab> createState() => _OkeyAdminGiftsTabState();
}

class _OkeyAdminGiftsTabState extends State<OkeyAdminGiftsTab> {
  final _service = OkeyAdminService();

  List<OkeyAdminGift> _gifts = const [];
  int _percent = 50;
  bool _loading = true;
  bool _savingPercent = false;

  /// Yükleme başarısız olduysa SEBEBİ — sessizce boş bir liste göstermek,
  /// admine "hediye kalmamış" dedirtirdi.
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final gifts = await _service.listGifts();
      final percent = await _service.giftRecipientPercent();
      if (!mounted) return;
      setState(() {
        _gifts = gifts;
        _percent = percent;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  Future<void> _savePercent(int value) async {
    setState(() => _savingPercent = true);
    try {
      final saved = await _service.setGiftRecipientPercent(value);
      if (!mounted) return;
      setState(() {
        _percent = saved;
        _savingPercent = false;
      });
      _toast('Alıcı payı %$saved olarak kaydedildi');
    } catch (e) {
      if (!mounted) return;
      setState(() => _savingPercent = false);
      _toast('Kaydedilemedi: $e');
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _edit([OkeyAdminGift? gift]) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _GiftDialog(gift: gift, service: _service),
    );
    if (saved == true) {
      _toast(gift == null ? 'Hediye eklendi' : 'Hediye güncellendi');
      await _load();
    }
  }

  Future<void> _delete(OkeyAdminGift gift) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hediye silinsin mi?'),
        // GÖNDERİLMİŞ hediyeler etkilenmez: kayıt kendi ad ve ikonunu
        // saklıyor (bkz. okey_gifts_sent). Admin bunu bilmezse silmeye
        // çekinir ya da geçmişi bozduğunu sanır.
        content: Text(
          '${gift.icon} ${gift.name} kataloğdan kalkacak. '
          'Daha önce gönderilmiş hediyeler masada olduğu gibi kalır.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await _service.deleteGift(gift.id);
      _toast('Hediye silindi');
      await _load();
    } catch (e) {
      _toast('Silinemedi: $e');
    }
  }

  Future<void> _toggleActive(OkeyAdminGift gift, bool value) async {
    try {
      await _service.upsertGift(
        id: gift.id,
        code: gift.code,
        name: gift.name,
        icon: gift.icon,
        price: gift.price,
        sortOrder: gift.sortOrder,
        isActive: value,
        anim: gift.anim,
      );
      await _load();
    } catch (e) {
      _toast('Değiştirilemedi: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 90),
        children: [
          if (_error != null)
            Card(
              color: Colors.red.shade50,
              child: ListTile(
                leading: const Icon(Icons.error_outline, color: Colors.red),
                title: const Text('Hediyeler yüklenemedi'),
                subtitle: Text(_error!),
                trailing: IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: _load,
                ),
              ),
            ),

          _PercentCard(
            percent: _percent,
            busy: _savingPercent,
            onChanged: _savePercent,
          ),
          const SizedBox(height: 12),

          Row(
            children: [
              const Expanded(
                child: Text(
                  'HEDİYE KATALOĞU',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Yeni'),
              ),
            ],
          ),
          const SizedBox(height: 6),

          if (_gifts.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Henüz hediye yok. "Yeni" ile ekleyebilirsin.',
                  style: TextStyle(color: Colors.black54),
                ),
              ),
            )
          else
            for (final g in _gifts)
              Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  // İkon PANELDE DE OYNAR: admin "shake" seçtiğinde ne
                  // olacağını kaydetmeden önce görsün.
                  leading: SizedBox(
                    width: 34,
                    height: 34,
                    child: Center(
                      child: OkeyAnimatedGiftIcon(
                        key: ValueKey('${g.id}:${g.icon}:${g.anim}'),
                        icon: g.icon,
                        anim: OkeyGiftAnim.parse(g.anim),
                        size: 26,
                      ),
                    ),
                  ),
                  title: Text(
                    g.name,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      decoration: g.isActive
                          ? null
                          : TextDecoration.lineThrough,
                    ),
                  ),
                  subtitle: Text(
                    '${g.price} çip · ${OkeyGiftAnim.parse(g.anim).label} · '
                    'sıra ${g.sortOrder} · kod: ${g.code}',
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // AÇIK/KAPALI — silmenin yumuşak hali. Bir hediyeyi
                      // sezonluk kaldırmak için silmek gerekmesin.
                      Switch(
                        value: g.isActive,
                        onChanged: (v) => _toggleActive(g, v),
                      ),
                      IconButton(
                        tooltip: 'Düzenle',
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: () => _edit(g),
                      ),
                      IconButton(
                        tooltip: 'Sil',
                        icon: const Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: Colors.red,
                        ),
                        onPressed: () => _delete(g),
                      ),
                    ],
                  ),
                ),
              ),
        ],
      ),
    );
  }
}

/// Alıcı payı — tek bir yüzde, ama ekonominin yönünü belirleyen sayı.
class _PercentCard extends StatefulWidget {
  final int percent;
  final bool busy;
  final ValueChanged<int> onChanged;

  const _PercentCard({
    required this.percent,
    required this.busy,
    required this.onChanged,
  });

  @override
  State<_PercentCard> createState() => _PercentCardState();
}

class _PercentCardState extends State<_PercentCard> {
  late double _value = widget.percent.toDouble();

  @override
  void didUpdateWidget(_PercentCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.percent != widget.percent) {
      _value = widget.percent.toDouble();
    }
  }

  @override
  Widget build(BuildContext context) {
    final pct = _value.round();
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.percent, color: Colors.purple),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Alıcıya geçen pay',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
                Text(
                  '%$pct',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const Text(
              'Hediyenin bedeli gönderenden düşer. Bu oran alıcının kazandığı '
              'kısımdır; kalanı sistem kazancına yazılır. Bot koltuğuna '
              'gönderilen hediyenin tamamı sistem kazancıdır.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
            Slider(
              value: _value,
              min: 0,
              max: 100,
              divisions: 20,
              label: '%$pct',
              onChanged: widget.busy ? null : (v) => setState(() => _value = v),
              onChangeEnd: (v) => widget.onChanged(v.round()),
            ),
          ],
        ),
      ),
    );
  }
}

/// Hediye ekleme/düzenleme formu.
class _GiftDialog extends StatefulWidget {
  final OkeyAdminGift? gift;
  final OkeyAdminService service;

  const _GiftDialog({required this.gift, required this.service});

  @override
  State<_GiftDialog> createState() => _GiftDialogState();
}

class _GiftDialogState extends State<_GiftDialog> {
  late final _code = TextEditingController(text: widget.gift?.code ?? '');
  late final _name = TextEditingController(text: widget.gift?.name ?? '');
  late final _icon = TextEditingController(text: widget.gift?.icon ?? '');
  late final _price = TextEditingController(
    text: '${widget.gift?.price ?? 100}',
  );
  late final _sort = TextEditingController(
    text: '${widget.gift?.sortOrder ?? 0}',
  );
  late bool _active = widget.gift?.isActive ?? true;
  late OkeyGiftAnim _anim = OkeyGiftAnim.parse(widget.gift?.anim);

  bool _saving = false;
  String? _error;

  /// Hazır emoji önerileri — admin klavyeden emoji aramakla uğraşmasın.
  /// Liste yalnızca bir KISAYOL: alana istediği emojiyi yazabilir.
  static const _suggestions = [
    '🍵',
    '☕',
    '🍦',
    '🍫',
    '💐',
    '🍮',
    '👏',
    '❤️',
    '🎂',
    '🍺',
    '🌹',
    '🎁',
    '💎',
    '🔥',
    '⭐',
    '🍩',
  ];

  @override
  void dispose() {
    for (final c in [_code, _name, _icon, _price, _sort]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final code = _code.text.trim();
    final name = _name.text.trim();
    final icon = _icon.text.trim();
    final price = int.tryParse(_price.text.trim());

    if (code.isEmpty || name.isEmpty || icon.isEmpty || price == null) {
      setState(() => _error = 'Kod, ad, ikon ve fiyat zorunlu.');
      return;
    }
    if (price < 0) {
      setState(() => _error = 'Fiyat negatif olamaz.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.service.upsertGift(
        id: widget.gift?.id,
        code: code,
        name: name,
        icon: icon,
        price: price,
        sortOrder: int.tryParse(_sort.text.trim()) ?? 0,
        isActive: _active,
        anim: _anim.code,
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = '$e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.gift == null ? 'Yeni hediye' : 'Hediyeyi düzenle'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: 'Ad',
                hintText: 'Kahve',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _code,
              decoration: const InputDecoration(
                labelText: 'Kod (benzersiz)',
                hintText: 'kahve',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _icon,
              decoration: const InputDecoration(
                labelText: 'İkon (emoji)',
                hintText: '☕',
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 4,
              children: [
                for (final e in _suggestions)
                  InkWell(
                    onTap: () => setState(() => _icon.text = e),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Text(e, style: const TextStyle(fontSize: 22)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              'Hareket',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
            ),
            const SizedBox(height: 4),
            // ÖNİZLEMELİ SEÇİM: her seçenek kendi hareketini oynar, çünkü
            // "shake" ile "bounce" arasındaki farkı bir etiket anlatamaz.
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final a in OkeyGiftAnim.values)
                  InkWell(
                    onTap: () => setState(() => _anim = a),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: _anim == a
                            ? Colors.purple.withValues(alpha: 0.12)
                            : null,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _anim == a ? Colors.purple : Colors.black26,
                          width: _anim == a ? 1.6 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          OkeyAnimatedGiftIcon(
                            key: ValueKey('$a:${_icon.text}'),
                            icon: _icon.text.trim().isEmpty
                                ? '🎁'
                                : _icon.text.trim(),
                            anim: a,
                            size: 18,
                          ),
                          const SizedBox(width: 6),
                          Text(a.label, style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _price,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Fiyat (çip)'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _sort,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Sıra'),
                  ),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('Masada gösterilsin'),
            ),
            if (_error != null)
              Text(
                _error!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.of(context).pop(false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Kaydet'),
        ),
      ],
    );
  }
}
