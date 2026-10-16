import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/models/order_model.dart';
import '../../shop/services/return_request_service.dart';

/// İade talebi alt sayfasının sonucu. [items] null = kalan tüm ürünler.
class ReturnSheetResult {
  final String reason;
  final List<ReturnItemSelection>? items;

  const ReturnSheetResult({required this.reason, this.items});
}

/// Siparişte iade edilebilecek kalan adetler (önceki bekleyen/onaylı/
/// tamamlanmış taleplerdeki adetler düşülür).
Map<String, int> remainingReturnQuantities(Order order, List<ReturnRequest> requests) {
  final reserved = <String, int>{};
  for (final r in requests) {
    if (r.status == ReturnRequestStatus.rejected ||
        r.status == ReturnRequestStatus.cancelled) {
      continue;
    }
    for (final i in r.items) {
      reserved[i.orderItemId] = (reserved[i.orderItemId] ?? 0) + i.quantity;
    }
  }
  return {
    for (final item in order.items)
      if (item.quantity - (reserved[item.id] ?? 0) > 0)
        item.id: item.quantity - (reserved[item.id] ?? 0),
  };
}

/// Tahmini iade tutarı — DB'deki create_return_request ile aynı kural:
/// kupon/indirim orantılı düşülür, teslimat ücreti iade edilmez, siparişin
/// kalan son ürünlerini iade eden talep kalan tutarın tamamını alır.
double estimateReturnRefund({
  required Order order,
  required Map<String, int> remaining,
  required Map<String, int> selected,
  required double previouslyRefunded,
}) {
  final itemsSum = order.items.fold<double>(0, (s, i) => s + i.price * i.quantity);
  if (itemsSum <= 0) return 0;
  final goodsPaid = (order.totalAmount - order.deliveryFee).clamp(0, double.infinity).toDouble();
  final ratio = (goodsPaid / itemsSum).clamp(0, 1).toDouble();
  final remainingRefundable = (goodsPaid - previouslyRefunded).clamp(0, double.infinity).toDouble();

  final isFinal = remaining.isNotEmpty &&
      remaining.entries.every((e) => (selected[e.key] ?? 0) >= e.value);
  if (isFinal) return remainingRefundable;

  var value = 0.0;
  for (final item in order.items) {
    value += item.price * (selected[item.id] ?? 0);
  }
  final refund = (value * ratio * 100).roundToDouble() / 100;
  return refund > remainingRefundable ? remainingRefundable : refund;
}

/// Müşterinin "tümünü" ya da "seçili ürünleri" iade etmek için kullandığı
/// alt sayfa. Talep yönetici onayına gider.
Future<ReturnSheetResult?> showReturnRequestSheet(
  BuildContext context, {
  required Order order,
  required List<ReturnRequest> existingRequests,
}) {
  return showModalBottomSheet<ReturnSheetResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => ReturnRequestSheet(
      order: order,
      existingRequests: existingRequests,
    ),
  );
}

class ReturnRequestSheet extends StatefulWidget {
  final Order order;
  final List<ReturnRequest> existingRequests;

  const ReturnRequestSheet({
    super.key,
    required this.order,
    required this.existingRequests,
  });

  @override
  State<ReturnRequestSheet> createState() => _ReturnRequestSheetState();
}

class _ReturnRequestSheetState extends State<ReturnRequestSheet> {
  static const _quickReasons = [
    'Ürün hasarlı geldi',
    'Yanlış ürün gönderildi',
    'Ürün eksik geldi',
    'Son kullanma tarihi geçmiş',
    'Ürünü beğenmedim',
  ];

  final TextEditingController _reasonController = TextEditingController();
  late final Map<String, int> _remaining;
  late final double _previouslyRefunded;
  final Map<String, int> _selected = {};
  bool _returnAll = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _remaining = remainingReturnQuantities(widget.order, widget.existingRequests);
    _previouslyRefunded = widget.existingRequests
        .where((r) =>
            r.status == ReturnRequestStatus.approved ||
            r.status == ReturnRequestStatus.completed)
        .fold(0.0, (s, r) => s + r.refundAmount);
    // Tek ürün kaldıysa "seçili" modunun anlamı yok.
    if (_remaining.length == 1 && _remaining.values.first == 1) {
      _returnAll = true;
    }
  }

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  List<OrderItem> get _returnableItems =>
      widget.order.items.where((i) => _remaining.containsKey(i.id)).toList();

  Map<String, int> get _effectiveSelection {
    final selection = Map.of(_returnAll ? _remaining : _selected);
    selection.removeWhere((_, q) => q <= 0);
    return selection;
  }

  double get _estimate => estimateReturnRefund(
        order: widget.order,
        remaining: _remaining,
        selected: _effectiveSelection,
        previouslyRefunded: _previouslyRefunded,
      );

  void _toggleItem(OrderItem item, bool on) {
    setState(() {
      _error = null;
      if (on) {
        _selected[item.id] = _remaining[item.id] ?? 1;
      } else {
        _selected.remove(item.id);
      }
    });
  }

  void _changeQty(OrderItem item, int delta) {
    final max = _remaining[item.id] ?? 0;
    final next = ((_selected[item.id] ?? 0) + delta).clamp(0, max);
    setState(() {
      _error = null;
      if (next == 0) {
        _selected.remove(item.id);
      } else {
        _selected[item.id] = next;
      }
    });
  }

  void _submit() {
    final reason = _reasonController.text.trim();
    final selection = _effectiveSelection;
    if (selection.isEmpty) {
      setState(() => _error = 'İade etmek istediğiniz ürünleri seçin');
      return;
    }
    if (reason.length < 3) {
      setState(() => _error = 'İade sebebi en az 3 karakter olmalı');
      return;
    }
    final isAllRemaining = _remaining.entries
        .every((e) => (selection[e.key] ?? 0) >= e.value);
    Navigator.pop(
      context,
      ReturnSheetResult(
        reason: reason,
        items: isAllRemaining
            ? null
            : selection.entries
                .map((e) => ReturnItemSelection(orderItemId: e.key, quantity: e.value))
                .toList(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final items = _returnableItems;
    final selectionCount =
        _effectiveSelection.values.fold<int>(0, (s, q) => s + q);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        builder: (context, scrollController) => Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 4),
              child: Row(
                children: [
                  const Icon(Icons.assignment_return, color: Colors.orange),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'İade Talebi',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close),
                    tooltip: 'Kapat',
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                children: [
                  SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        icon: Icon(Icons.select_all, size: 18),
                        label: Text('Tümünü İade Et'),
                      ),
                      ButtonSegment(
                        value: false,
                        icon: Icon(Icons.checklist, size: 18),
                        label: Text('Ürün Seç'),
                      ),
                    ],
                    selected: {_returnAll},
                    showSelectedIcon: false,
                    onSelectionChanged: (v) => setState(() {
                      _error = null;
                      _returnAll = v.first;
                    }),
                  ),
                  const SizedBox(height: 12),
                  for (final item in items) _buildItemRow(item, theme),
                  const SizedBox(height: 12),
                  Text(
                    'İade sebebi',
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: Colors.grey.shade800,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final r in _quickReasons)
                        ActionChip(
                          label: Text(r, style: const TextStyle(fontSize: 12)),
                          onPressed: () => setState(() {
                            _error = null;
                            _reasonController.text = r;
                          }),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: _reasonController,
                    maxLines: 3,
                    maxLength: 1000,
                    onChanged: (_) {
                      if (_error != null) setState(() => _error = null);
                    },
                    decoration: const InputDecoration(
                      hintText: 'Örn: Ürün hasarlı geldi, yanlış ürün gönderildi...',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.blue.shade100),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.info_outline, size: 18, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Talebiniz yönetici onayına gider. Onaylanınca tutar '
                            'CizreApp bakiyenize eklenir ve satıcıya bildirilir '
                            '(kuryeli satıcıya kapıda ödediyseniz tutarı satıcı '
                            'nakit iade eder); ürünleri satıcıya teslim etmeniz '
                            'gerekir. Teslimat ücreti iade edilmez.',
                            style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            SafeArea(
              top: false,
              child: Container(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  border: Border(top: BorderSide(color: Colors.grey.shade200)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Text(
                          _error!,
                          style: TextStyle(color: Colors.red.shade700, fontSize: 13),
                        ),
                      ),
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$selectionCount ürün · tahmini iade',
                                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                              ),
                              Text(
                                '₺${_estimate.toStringAsFixed(2)}',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        ElevatedButton.icon(
                          onPressed: _submit,
                          icon: const Icon(Icons.send, size: 18),
                          label: const Text('Talebi Gönder'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemRow(OrderItem item, ThemeData theme) {
    final remaining = _remaining[item.id] ?? 0;
    final qty = _returnAll ? remaining : (_selected[item.id] ?? 0);
    final checked = qty > 0;
    final image = item.productImageUrl;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: checked ? Colors.orange.shade50 : Colors.grey.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: checked ? Colors.orange.shade200 : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          Checkbox(
            value: checked,
            onChanged: _returnAll ? null : (v) => _toggleItem(item, v ?? false),
          ),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              width: 44,
              height: 44,
              child: image != null && image.isNotEmpty
                  ? CachedNetworkImage(
                      imageUrl: image,
                      fit: BoxFit.cover,
                      memCacheWidth: 132,
                      errorWidget: (_, __, ___) => _placeholder(),
                    )
                  : _placeholder(),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.productName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                ),
                const SizedBox(height: 2),
                Text(
                  '₺${item.price.toStringAsFixed(2)} · iade edilebilir: $remaining adet',
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          if (!_returnAll && remaining > 1)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: qty > 0 ? () => _changeQty(item, -1) : null,
                  icon: const Icon(Icons.remove_circle_outline),
                  tooltip: 'Azalt',
                ),
                Text('$qty', style: const TextStyle(fontWeight: FontWeight.bold)),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  onPressed: qty < remaining ? () => _changeQty(item, 1) : null,
                  icon: const Icon(Icons.add_circle_outline),
                  tooltip: 'Artır',
                ),
              ],
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Text(
                '× $qty',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: checked ? Colors.orange.shade800 : Colors.grey,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _placeholder() => Container(
        color: Colors.grey.shade200,
        child: Icon(Icons.shopping_bag_outlined, color: Colors.grey.shade400, size: 22),
      );
}
