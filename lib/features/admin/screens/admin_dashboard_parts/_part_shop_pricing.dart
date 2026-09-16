// Bu dosya `part of admin_dashboard_screen.dart` oldugu icin ana dosyadaki
// ignore_for_file direktifleri buraya UYGULANMAZ; her part kendi listesini
// tasimak zorundadir.
//
// invalid_use_of_protected_member: bu part'lar `extension on
// _AdminDashboardScreenState` deseniyle yazildi; setState/mounted analiz
// acisindan sinif disindan cagrilmis gorunur ama calisma zamaninda
// State'in kendi uyesidir. Tek gercek false positive budur ve yalniz o
// susturulur - dosyalarin analizden komple cikarilmasi (analysis_options
// exclude) dead_code/tip hatalarini da gizliyordu.
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: use_build_context_synchronously, deprecated_member_use
part of '../admin_dashboard_screen.dart';

// ==========================================================================
// Admin fiyat mudahalesi: satici teslimat ucreti + min. sepet tutari
//
// Canonical deger shops.delivery_fee / shops.min_order_amount olarak kalir;
// admin ezdiginde saticinin eski degeri pre_override_* sutunlarina yedeklenir
// (admin_set_shop_pricing_override RPC). Geri alindiginda
// (admin_clear_shop_pricing_override) satici degerleri aynen geri doner.
// ==========================================================================

// --- _parseAmountInput ---
/// "25", "25,50", "25.50" -> 25.5. Bos/gecersiz girdi null doner.
double? _parseAmountInput(String raw) {
  final text = raw.trim().replaceAll(',', '.');
  if (text.isEmpty) return null;
  return double.tryParse(text);
}

// --- _isShopPricingOverridden ---
// Not: bu fonksiyon _part_shops.dart icindeki dukkan kartlarindan da
// cagriliyor (ayni library'nin parcasi oldugu icin ust duzey fonksiyon
// olarak kalmasi gerekiyor, State'e bagli bir extension metodu olamaz).
bool _isShopPricingOverridden(Map<String, dynamic> shop) =>
    shop['pre_override_delivery_fee'] != null ||
    shop['pre_override_min_order_amount'] != null ||
    shop['pre_override_delivery_time'] != null;

// --- _sellerDeliveryTimeLabel ---
/// Yedekteki satıcı teslimat süresi; '' sentinel'i "değeri yoktu" demek.
String _sellerDeliveryTimeLabel(Map<String, dynamic> shop) {
  final raw = shop['pre_override_delivery_time'] as String?;
  if (raw == null) return 'süre —';
  return raw.trim().isEmpty ? 'süre yok' : 'süre $raw';
}

extension on _AdminDashboardScreenState {
  // --- _showShopPricingOverrideDialog ---
  /// Tum saticilarin (veya secilenlerin) teslimat ucreti ve min. sepet
  /// tutarini admin olarak ezme / geri alma ekrani.
  void _showShopPricingOverrideDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ShopPricingOverrideDialog(onApplied: _loadAndSetShops),
    );
  }
}

// --- _AdminPricingField ---
class _AdminPricingField extends StatelessWidget {
  const _AdminPricingField({
    required this.controller,
    required this.enabled,
    required this.label,
    required this.icon,
  });

  final TextEditingController controller;
  final bool enabled;
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      enabled: enabled,
      decoration: InputDecoration(
        labelText: label,
        helperText: 'Boş = değiştirme',
        border: const OutlineInputBorder(),
        isDense: true,
        prefixIcon: Icon(icon),
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
    );
  }
}

// --- _ShopPricingOverrideDialog ---
class _ShopPricingOverrideDialog extends StatefulWidget {
  const _ShopPricingOverrideDialog({required this.onApplied});

  /// Uygulama/geri alma basarili oldugunda ana ekrandaki dukkan listesini
  /// tazelemek icin cagrilir (_AdminDashboardScreenState._loadAndSetShops).
  final Future<void> Function() onApplied;

  @override
  State<_ShopPricingOverrideDialog> createState() =>
      _ShopPricingOverrideDialogState();
}

class _ShopPricingOverrideDialogState
    extends State<_ShopPricingOverrideDialog> {
  final _feeController = TextEditingController();
  final _minOrderController = TextEditingController();
  final _deliveryTimeController = TextEditingController();
  final _noteController = TextEditingController();
  final _selectedShopIds = <String>{};

  bool _applyToAll = true;
  bool _isBusy = false;
  bool _isLoading = true;
  List<Map<String, dynamic>> _shops = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  @override
  void dispose() {
    _feeController.dispose();
    _minOrderController.dispose();
    _deliveryTimeController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    try {
      final rows = await Supabase.instance.client
          .from('shops')
          .select('''
            id,
            name,
            is_active,
            has_own_courier,
            delivery_fee,
            min_order_amount,
            delivery_time,
            pre_override_delivery_fee,
            pre_override_min_order_amount,
            pre_override_delivery_time,
            admin_pricing_override_at,
            admin_pricing_override_note
          ''')
          .order('name', ascending: true);
      if (!mounted) return;
      setState(() {
        _shops = List<Map<String, dynamic>>.from(rows);
        _isLoading = false;
        _selectedShopIds.retainAll(
          _shops.map((s) => s['id'] as String).toSet(),
        );
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Dükkanlar yüklenemedi: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  List<String>? _scopeIds() => _applyToAll ? null : _selectedShopIds.toList();

  Future<void> _applyOverride() async {
    final fee = _parseAmountInput(_feeController.text);
    final minOrder = _parseAmountInput(_minOrderController.text);
    final deliveryTime = _deliveryTimeController.text.trim().isEmpty
        ? null
        : _deliveryTimeController.text.trim();

    if (fee == null && minOrder == null && deliveryTime == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'En az bir alan doldurun: teslimat ücreti, min. sepet '
            'tutarı veya teslimat süresi',
          ),
        ),
      );
      return;
    }
    if (!_applyToAll && _selectedShopIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Hiç dükkan seçilmedi')));
      return;
    }

    final scopeLabel = _applyToAll
        ? 'TÜM dükkanlara'
        : '${_selectedShopIds.length} dükkana';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Fiyat müdahalesini uygula'),
        content: Text(
          '$scopeLabel uygulanacak:\n'
          '${fee != null ? '• Teslimat ücreti: ₺${fee.toStringAsFixed(2)}\n' : ''}'
          '${minOrder != null ? '• Min. sepet tutarı: ₺${minOrder.toStringAsFixed(2)}\n' : ''}'
          '${deliveryTime != null ? '• Ortalama teslimat süresi: $deliveryTime\n' : ''}'
          '\nSatıcıların mevcut değerleri saklanır; "Geri Al" ile '
          'eski hallerine döner.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Uygula'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isBusy = true);
    try {
      final affected = await Supabase.instance.client.rpc<int>(
        'admin_set_shop_pricing_override',
        params: {
          'p_shop_ids': _scopeIds(),
          'p_delivery_fee': fee,
          'p_min_order_amount': minOrder,
          'p_delivery_time': deliveryTime,
          'p_note': _noteController.text.trim().isEmpty
              ? null
              : _noteController.text.trim(),
        },
      );
      await _reload();
      await widget.onApplied();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$affected dükkana uygulandı'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Uygulanamadı: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _clearOverride({List<String>? shopIds}) async {
    final ids = shopIds ?? _scopeIds();
    if (shopIds == null && !_applyToAll && _selectedShopIds.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Hiç dükkan seçilmedi')));
      return;
    }

    final scopeLabel = shopIds != null
        ? 'Bu dükkanın'
        : (_applyToAll
              ? 'TÜM dükkanların'
              : '${_selectedShopIds.length} dükkanın');
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Müdahaleyi geri al'),
        content: Text(
          '$scopeLabel teslimat ücreti, min. sepet tutarı ve ortalama '
          'teslimat süresi satıcının kendi değerine geri dönecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.orange.shade700,
              foregroundColor: Colors.white,
            ),
            child: const Text('Geri Al'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isBusy = true);
    try {
      final affected = await Supabase.instance.client.rpc<int>(
        'admin_clear_shop_pricing_override',
        params: {'p_shop_ids': ids},
      );
      await _reload();
      await widget.onApplied();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            affected == 0
                ? 'Geri alınacak müdahale yok'
                : '$affected dükkan eski değerine döndü',
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Geri alınamadı: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isCompact = media.size.width < 640;
    final horizontalInset = isCompact ? 16.0 : 40.0;
    final verticalInset = isCompact ? 24.0 : 40.0;

    // Icerik artik tek parca kaydirilabilir (form alanlari + dukkan
    // listesi ayni scroll icinde); bu yuzden burada sadece bir UST SINIR
    // veriyoruz, sabit bir yukseklik degil. Klavye acildiginda
    // (viewInsets.bottom) sinir otomatik daralir, ic Expanded scroll alani
    // kucular ama hicbir sabit-yukseklik cocuk tasmaz - eski tasarimdaki
    // "sabit SizedBox + esnek olmayan alanlarin toplami sigmiyor" tasma
    // kaynagi boylece ortadan kalkiyor.
    final rawMaxWidth = media.size.width - horizontalInset * 2;
    final maxWidth = rawMaxWidth > 560
        ? 560.0
        : (rawMaxWidth < 280 ? 280.0 : rawMaxWidth);
    final rawMaxHeight =
        media.size.height - media.viewInsets.bottom - verticalInset * 2;
    final maxHeight = rawMaxHeight > 680
        ? 680.0
        : (rawMaxHeight < 320 ? 320.0 : rawMaxHeight);

    final overriddenCount = _shops.where(_isShopPricingOverridden).length;

    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: horizontalInset,
        vertical: verticalInset,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 8, 12),
              child: Row(
                children: [
                  Icon(Icons.price_change, color: Colors.purple.shade600),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Teslimat & Min. Sepet Müdahalesi',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kapat',
                    icon: const Icon(Icons.close),
                    onPressed: _isBusy ? null : () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Colors.grey.shade300),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _buildBody(overriddenCount),
            ),
            Divider(height: 1, color: Colors.grey.shade300),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                alignment: WrapAlignment.end,
                spacing: 8,
                runSpacing: 8,
                children: [
                  TextButton(
                    onPressed: _isBusy ? null : () => Navigator.pop(context),
                    child: const Text('Kapat'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _isBusy ? null : () => _clearOverride(),
                    icon: const Icon(Icons.undo, size: 18),
                    label: const Text('Geri Al'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.orange.shade800,
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _isBusy ? null : _applyOverride,
                    icon: _isBusy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check, size: 18),
                    label: const Text('Uygula'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade600,
                      foregroundColor: Colors.white,
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

  Widget _buildBody(int overriddenCount) {
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          sliver: SliverToBoxAdapter(child: _buildForm(overriddenCount)),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          sliver: _shops.isEmpty
              ? const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(child: Text('Dükkan bulunamadı')),
                  ),
                )
              : SliverList.separated(
                  itemCount: _shops.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) =>
                      _buildShopTile(_shops[index]),
                ),
        ),
      ],
    );
  }

  Widget _buildForm(int overriddenCount) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.amber.shade50,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.amber.shade200),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.info_outline, size: 18, color: Colors.amber.shade800),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Teslimat ücreti, min. sepet tutarı ve ortalama '
                  'teslimat süresi için müdahale yalnızca admin '
                  'tarafından oluşturulur. Satıcının eski değeri '
                  'saklanır, "Geri Al" ile aynen döner.',
                  style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        // Dar telefonlarda iki alan yan yana sigmiyor (uzun label +
        // prefixIcon); genislige gore Row <-> Column arasinda geciyor.
        LayoutBuilder(
          builder: (context, constraints) {
            final feeField = _AdminPricingField(
              controller: _feeController,
              enabled: !_isBusy,
              label: 'Teslimat Ücreti (₺)',
              icon: Icons.delivery_dining,
            );
            final minOrderField = _AdminPricingField(
              controller: _minOrderController,
              enabled: !_isBusy,
              label: 'Min. Sepet (₺)',
              icon: Icons.shopping_basket,
            );
            if (constraints.maxWidth < 360) {
              return Column(
                children: [feeField, const SizedBox(height: 10), minOrderField],
              );
            }
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: feeField),
                const SizedBox(width: 10),
                Expanded(child: minOrderField),
              ],
            );
          },
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _deliveryTimeController,
          enabled: !_isBusy,
          maxLength: 60,
          decoration: const InputDecoration(
            labelText: 'Ortalama Teslimat Süresi',
            helperText: 'Boş = değiştirme • örn: 30-45 dakika',
            counterText: '',
            border: OutlineInputBorder(),
            isDense: true,
            prefixIcon: Icon(Icons.timer),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _noteController,
          enabled: !_isBusy,
          decoration: const InputDecoration(
            labelText: 'Gerekçe (opsiyonel)',
            border: OutlineInputBorder(),
            isDense: true,
            prefixIcon: Icon(Icons.notes),
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ChoiceChip(
              label: const Text('Tüm dükkanlar'),
              selected: _applyToAll,
              onSelected: _isBusy
                  ? null
                  : (_) => setState(() => _applyToAll = true),
            ),
            ChoiceChip(
              label: Text('Seçili (${_selectedShopIds.length})'),
              selected: !_applyToAll,
              onSelected: _isBusy
                  ? null
                  : (_) => setState(() => _applyToAll = false),
            ),
            if (overriddenCount > 0)
              Chip(
                backgroundColor: Colors.orange.shade100,
                label: Text(
                  '$overriddenCount müdahaleli',
                  style: TextStyle(fontSize: 11, color: Colors.orange.shade900),
                ),
                visualDensity: VisualDensity.compact,
              ),
          ],
        ),
        const SizedBox(height: 12),
        Divider(height: 1, color: Colors.grey.shade300),
      ],
    );
  }

  Widget _buildShopTile(Map<String, dynamic> shop) {
    final id = shop['id'] as String;
    final overridden = _isShopPricingOverridden(shop);
    final fee = (shop['delivery_fee'] as num?)?.toDouble() ?? 0;
    final minOrder = (shop['min_order_amount'] as num?)?.toDouble() ?? 0;
    final sellerFee = (shop['pre_override_delivery_fee'] as num?)?.toDouble();
    final sellerMin = (shop['pre_override_min_order_amount'] as num?)
        ?.toDouble();
    final deliveryTime = (shop['delivery_time'] as String?)?.trim();

    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        dense: true,
        leading: _applyToAll
            ? Icon(
                Icons.store,
                color: overridden
                    ? Colors.orange.shade700
                    : Colors.grey.shade500,
              )
            : Checkbox(
                value: _selectedShopIds.contains(id),
                onChanged: _isBusy
                    ? null
                    : (v) => setState(() {
                        if (v == true) {
                          _selectedShopIds.add(id);
                        } else {
                          _selectedShopIds.remove(id);
                        }
                      }),
              ),
        title: Text(
          shop['name']?.toString() ?? '-',
          style: const TextStyle(fontSize: 13),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Teslimat ₺${fee.toStringAsFixed(2)}  •  '
              'Min. sepet ₺${minOrder.toStringAsFixed(2)}'
              '${deliveryTime != null && deliveryTime.isNotEmpty ? '  •  $deliveryTime' : ''}',
              style: const TextStyle(fontSize: 12),
            ),
            if (overridden)
              Text(
                'Satıcının değeri: '
                '${sellerFee != null ? 'teslimat ₺${sellerFee.toStringAsFixed(2)}' : 'teslimat —'}'
                '  •  '
                '${sellerMin != null ? 'min. sepet ₺${sellerMin.toStringAsFixed(2)}' : 'min. sepet —'}'
                '  •  '
                '${_sellerDeliveryTimeLabel(shop)}',
                style: TextStyle(fontSize: 11, color: Colors.orange.shade800),
              ),
          ],
        ),
        trailing: overridden
            ? IconButton(
                tooltip: 'Bu dükkanı geri al',
                icon: Icon(Icons.undo, color: Colors.orange.shade700),
                onPressed: _isBusy ? null : () => _clearOverride(shopIds: [id]),
              )
            : null,
      ),
    );
  }
}
