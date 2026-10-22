import 'package:flutter/material.dart';

import '../../../core/utils/schedule_format.dart';
import '../services/scheduled_order_service.dart';

/// Randevu saati seçici (alt sayfa). Seçilen zamanı (UTC) döner; vazgeçilirse null.
Future<DateTime?> showScheduledSlotPicker(
  BuildContext context, {
  required String shopId,
  String? shopName,
  DateTime? initial,
  bool isPickup = false,
  ScheduledOrderService? service,
}) {
  return showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ScheduledSlotPickerSheet(
      shopId: shopId,
      shopName: shopName,
      initial: initial,
      isPickup: isPickup,
      service: service ?? ScheduledOrderService(),
    ),
  );
}

class ScheduledSlotPickerSheet extends StatefulWidget {
  const ScheduledSlotPickerSheet({
    super.key,
    required this.shopId,
    required this.service,
    this.shopName,
    this.initial,
    this.isPickup = false,
    this.now,
  });

  final String shopId;
  final String? shopName;
  final DateTime? initial;
  final bool isPickup;
  final ScheduledOrderService service;

  /// Testlerde "Bugün/Yarın" etiketlerini sabitlemek için.
  final DateTime? now;

  @override
  State<ScheduledSlotPickerSheet> createState() => _ScheduledSlotPickerSheetState();
}

class _ScheduledSlotPickerSheetState extends State<ScheduledSlotPickerSheet> {
  List<DateTime>? _slots;
  DateTime? _day;
  DateTime? _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
    _load();
  }

  Future<void> _load() async {
    final slots = await widget.service.slots(widget.shopId);
    if (!mounted) return;
    setState(() {
      _slots = slots;
      final sel = _selected;
      // Önceki seçim artık listede yoksa düşer.
      if (sel != null && !slots.any((s) => s.isAtSameMomentAs(sel))) {
        _selected = null;
      }
      final focus = _selected ?? (slots.isEmpty ? null : slots.first);
      _day = focus == null ? null : ScheduleFormat.trDay(focus);
    });
  }

  List<DateTime> get _days {
    final out = <DateTime>[];
    for (final s in _slots ?? const <DateTime>[]) {
      final d = ScheduleFormat.trDay(s);
      if (out.isEmpty || out.last != d) out.add(d);
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final slots = _slots;
    final title = widget.isPickup ? 'Teslim alma saatini seç' : 'Teslimat saatini seç';

    Widget body;
    if (slots == null) {
      body = const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (slots.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 8),
        child: Column(
          children: [
            Icon(Icons.event_busy_rounded, size: 40, color: Colors.grey.shade500),
            const SizedBox(height: 10),
            const Text(
              'Bu dükkan için şu an uygun randevu saati yok.',
              textAlign: TextAlign.center,
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    } else {
      final daySlots = slots.where((s) => ScheduleFormat.trDay(s) == _day).toList();
      body = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 44,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _days.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final d = _days[i];
                return ChoiceChip(
                  label: Text(ScheduleFormat.dayLabel(d.subtract(const Duration(hours: 3)),
                      now: widget.now)),
                  selected: d == _day,
                  onSelected: (_) => setState(() => _day = d),
                );
              },
            ),
          ),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in daySlots)
                ChoiceChip(
                  label: Text(ScheduleFormat.time(s)),
                  selected: _selected != null && _selected!.isAtSameMomentAs(s),
                  onSelected: (_) => setState(() => _selected = s),
                ),
            ],
          ),
        ],
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Icon(Icons.event_available_rounded, color: primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          if (widget.shopName != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, left: 32),
              child: Text(
                widget.shopName!,
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12.5),
              ),
            ),
          const SizedBox(height: 14),
          Flexible(child: SingleChildScrollView(child: body)),
          const SizedBox(height: 14),
          FilledButton(
            onPressed: _selected == null ? null : () => Navigator.pop(context, _selected),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            child: Text(
              _selected == null ? 'Saat seçin' : '${ScheduleFormat.full(_selected!, now: widget.now)} — Onayla',
            ),
          ),
        ],
      ),
    );
  }
}

/// Checkout'taki "Teslimat zamanı" seçimi: Hemen / Randevulu.
class ScheduledDeliveryCard extends StatelessWidget {
  const ScheduledDeliveryCard({
    super.key,
    required this.shopId,
    required this.value,
    required this.onChanged,
    this.shopName,
    this.isPickup = false,
    this.shopClosedNow = false,
    this.service,
    this.dense = false,
  });

  final String shopId;
  final String? shopName;

  /// Seçili randevu (UTC); null = hemen.
  final DateTime? value;
  final ValueChanged<DateTime?> onChanged;
  final bool isPickup;

  /// Dükkan şu an kapalıysa randevu önerilir.
  final bool shopClosedNow;
  final ScheduledOrderService? service;

  /// Çoklu dükkan kartı içinde daha sıkı yerleşim.
  final bool dense;

  Future<void> _pick(BuildContext context) async {
    final picked = await showScheduledSlotPicker(
      context,
      shopId: shopId,
      shopName: shopName,
      initial: value,
      isPickup: isPickup,
      service: service,
    );
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final scheduled = value != null;
    final nowLabel = isPickup ? 'Hemen (hazır olunca teslim al)' : 'Hemen (en kısa sürede)';
    final schedLabel = scheduled
        ? '${isPickup ? 'Teslim alma' : 'Randevu'}: ${ScheduleFormat.full(value!)}'
        : (isPickup ? 'İleri bir saatte teslim al' : 'İleri bir saate randevu al');

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!dense)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 4, 2),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, size: 20, color: primary),
                const SizedBox(width: 8),
                Text(
                  isPickup ? 'Teslim alma zamanı' : 'Teslimat zamanı',
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                ),
              ],
            ),
          ),
        RadioGroup<bool>(
          groupValue: scheduled,
          onChanged: (v) {
            if (v == true) {
              _pick(context);
            } else {
              onChanged(null);
            }
          },
          child: Column(
            children: [
              RadioListTile<bool>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: false,
                title: Text(nowLabel),
              ),
              RadioListTile<bool>(
                dense: true,
                contentPadding: EdgeInsets.zero,
                value: true,
                title: Text(
                  schedLabel,
                  style: scheduled ? const TextStyle(fontWeight: FontWeight.w700) : null,
                ),
                secondary: scheduled
                    ? TextButton(onPressed: () => _pick(context), child: const Text('Değiştir'))
                    : const Icon(Icons.event_rounded),
              ),
            ],
          ),
        ),
        if (shopClosedNow && !scheduled)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 6),
            child: Text(
              'Dükkan şu an kapalı — açık olduğu bir saate randevu alabilirsiniz.',
              style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
            ),
          ),
      ],
    );

    if (dense) return content;
    return Card(
      margin: const EdgeInsets.only(top: 12),
      child: Padding(padding: const EdgeInsets.fromLTRB(12, 8, 12, 4), child: content),
    );
  }
}
