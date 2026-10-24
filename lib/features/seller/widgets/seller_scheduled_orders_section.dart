import 'package:flutter/material.dart';

import '../../market/services/scheduled_order_service.dart';
import 'common/seller_section_card.dart';

/// Satıcı > Mağaza Ayarları > "Randevulu Sipariş".
///
/// Müşteri checkout'ta "Hemen" yerine ileri bir saat seçebilir. Saatler
/// mağazanın çalışma saatlerinden, burada seçilen aralık / gün / hazırlık
/// süresiyle sunucuda üretilir. Admin global olarak kapattıysa ya da bu mağaza
/// için engellediyse bölüm kilitli görünür.
class SellerScheduledOrdersSection extends StatefulWidget {
  const SellerScheduledOrdersSection({
    super.key,
    required this.shopData,
    required this.onSave,
    this.globalEnabledLoader,
  });

  /// `shops` satırı (select *).
  final Map<String, dynamic> shopData;

  /// Kaydet: (açık mı, slot dk, kaç gün, hazırlık dk, saat başına sınır).
  final Future<void> Function({
    required bool enabled,
    required int slotMinutes,
    required int maxDays,
    required int minLeadMinutes,
    required int? slotCapacity,
  }) onSave;

  /// Testlerde admin global anahtarını sahtelemek için.
  final Future<bool> Function()? globalEnabledLoader;

  static const List<int> slotOptions = [15, 30, 60, 120];
  static const List<int> dayOptions = [0, 1, 2, 3, 5, 7, 14];
  static const List<int> leadOptions = [15, 30, 45, 60, 90, 120, 180, 240, 1440];

  /// "Aynı saate en fazla" seçenekleri; null = sınırsız.
  static const List<int?> capacityOptions = [null, 1, 2, 3, 5, 10, 20, 50];

  static String capacityLabel(int? c) => c == null ? 'Sınırsız' : '$c sipariş';

  static String leadLabel(int m) {
    if (m >= 1440) return '${m ~/ 1440} gün';
    if (m >= 60 && m % 60 == 0) return '${m ~/ 60} saat';
    if (m > 60) return '${m ~/ 60} sa ${m % 60} dk';
    return '$m dk';
  }

  static String dayLabel(int d) => d == 0 ? 'Yalnız bugün' : '$d gün ileri';

  @override
  State<SellerScheduledOrdersSection> createState() => _SellerScheduledOrdersSectionState();
}

class _SellerScheduledOrdersSectionState extends State<SellerScheduledOrdersSection> {
  late bool _enabled;
  late int _slot;
  late int _days;
  late int _lead;
  int? _capacity;
  bool? _global;
  bool _saving = false;

  bool get _adminBlocked =>
      widget.shopData['scheduled_orders_admin_blocked'] as bool? ?? false;

  static int _snap(int v, List<int> options) {
    if (options.contains(v)) return v;
    return options.reduce((a, b) => (a - v).abs() <= (b - v).abs() ? a : b);
  }

  @override
  void initState() {
    super.initState();
    final d = widget.shopData;
    _enabled = d['scheduled_orders_enabled'] as bool? ?? false;
    _slot = _snap((d['scheduled_slot_minutes'] as num?)?.toInt() ?? 60,
        SellerScheduledOrdersSection.slotOptions);
    _days = _snap((d['scheduled_max_days'] as num?)?.toInt() ?? 3,
        SellerScheduledOrdersSection.dayOptions);
    _lead = _snap((d['scheduled_min_lead_minutes'] as num?)?.toInt() ?? 60,
        SellerScheduledOrdersSection.leadOptions);
    final cap = (d['scheduled_slot_capacity'] as num?)?.toInt();
    // Listede olmayan değer (ör. admin elle 4 yazdı) kaybolmasın: seçeneklere eklenir.
    _capacity = cap;
    (widget.globalEnabledLoader ?? () => ScheduledOrderService().globallyEnabled())()
        .then((v) {
      if (mounted) setState(() => _global = v);
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave(
        enabled: _enabled,
        slotMinutes: _slot,
        maxDays: _days,
        minLeadMinutes: _lead,
        slotCapacity: _capacity,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Randevulu sipariş ayarları kaydedildi'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Widget _dropdown<T>({
    required String label,
    required T value,
    required List<T> items,
    required String Function(T) text,
    required ValueChanged<T> onChanged,
    required bool enabled,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
      items: [
        for (final i in items) DropdownMenuItem<T>(value: i, child: Text(text(i))),
      ],
      onChanged: enabled ? (v) => v == null ? null : onChanged(v) : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final global = _global;
    final locked = _adminBlocked || global == false;
    final editable = !locked && !_saving;

    String? notice;
    if (_adminBlocked) {
      notice = 'Yönetim bu mağaza için randevulu siparişi kapattı.';
    } else if (global == false) {
      notice = 'Randevulu sipariş şu an yönetim tarafından tüm mağazalarda kapalı.';
    }

    return SellerSectionCard(
      margin: EdgeInsets.zero,
      title: 'Randevulu Sipariş',
      icon: Icons.event_available,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (notice != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, size: 18, color: Colors.amber.shade900),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(notice, style: TextStyle(color: Colors.amber.shade900, fontSize: 12.5)),
                  ),
                ],
              ),
            ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _enabled && !locked,
            onChanged: editable ? (v) => setState(() => _enabled = v) : null,
            title: const Text('Müşteri ileri bir saate sipariş verebilsin'),
            subtitle: const Text(
              'Checkout\'ta "Hemen" yerine çalışma saatleriniz içindeki bir saat seçilebilir. '
              'Gel Al siparişinde bu teslim alma saati olur.',
            ),
          ),
          if (_enabled && !locked) ...[
            const SizedBox(height: 8),
            _dropdown<int>(
              label: 'Saat aralığı',
              value: _slot,
              items: SellerScheduledOrdersSection.slotOptions,
              text: (m) => '$m dakikada bir',
              onChanged: (v) => setState(() => _slot = v),
              enabled: editable,
            ),
            const SizedBox(height: 12),
            _dropdown<int>(
              label: 'En fazla kaç gün ilerisi',
              value: _days,
              items: SellerScheduledOrdersSection.dayOptions,
              text: SellerScheduledOrdersSection.dayLabel,
              onChanged: (v) => setState(() => _days = v),
              enabled: editable,
            ),
            const SizedBox(height: 12),
            _dropdown<int>(
              label: 'En az hazırlık süresi',
              value: _lead,
              items: SellerScheduledOrdersSection.leadOptions,
              text: (m) => '${SellerScheduledOrdersSection.leadLabel(m)} sonrası',
              onChanged: (v) => setState(() => _lead = v),
              enabled: editable,
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int?>(
              initialValue: _capacity,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Aynı saate en fazla',
                helperText: 'Dolan saat müşteriye "Dolu" görünür; iptal olan sipariş yeri açar.',
                helperMaxLines: 2,
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final c in {
                  ...SellerScheduledOrdersSection.capacityOptions,
                  _capacity,
                })
                  DropdownMenuItem<int?>(
                    value: c,
                    child: Text(SellerScheduledOrdersSection.capacityLabel(c)),
                  ),
              ],
              onChanged: editable ? (v) => setState(() => _capacity = v) : null,
            ),
            const SizedBox(height: 8),
            Text(
              'Saatler "Çalışma Saatleri" bölümündeki açılış-kapanışa göre oluşur. '
              'Kuryesi olmayan mağazalarda platform kuryesi siparişi randevu saatinden '
              'kısa süre önce görür.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: editable ? _save : null,
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.save),
              label: const Text('Randevu Ayarlarını Kaydet'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
