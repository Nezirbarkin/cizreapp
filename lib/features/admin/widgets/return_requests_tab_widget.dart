import 'package:flutter/material.dart';

import '../../shop/services/return_request_service.dart';
import '../../shop/widgets/return_request_card.dart';

/// Admin "İade Talepleri" sekmesi.
///
/// Müşterinin tümü/seçili ürünler için açtığı iade talepleri buraya düşer.
/// İşlem (DB tarafında atomik RPC):
/// - Onayla: approve_return_request
///     ├─ iade tutarı müşterinin bakiyesine eklenir (add_to_balance 'refund')
///     ├─ satıcının bu tutardaki payı mağaza hesabından düşülür
///     ├─ sipariş tamamen iade edildiyse payment_status = 'refunded'
///     └─ müşteriye ve satıcıya bildirim
/// - Reddet: reject_return_request → müşteriye bildirim
/// - Onaylanmış iadede satıcı yerine "Teslim alındı" işaretlenebilir.
class ReturnRequestsTabWidget extends StatefulWidget {
  const ReturnRequestsTabWidget({super.key});

  @override
  State<ReturnRequestsTabWidget> createState() => _ReturnRequestsTabWidgetState();
}

class _ReturnRequestsTabWidgetState extends State<ReturnRequestsTabWidget> {
  static const _filters = <(String?, String)>[
    ('pending', 'Bekleyen'),
    ('approved', 'Teslim Bekleyen'),
    (null, 'Tümü'),
  ];

  final ReturnRequestService _service = ReturnRequestService();
  String? _status = 'pending';
  bool _isLoading = true;
  List<ReturnRequest> _requests = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final list = await _service.getAdminReturnRequests(status: _status);
      if (!mounted) return;
      setState(() => _requests = list);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('İade talepleri yüklenemedi: ${returnErrorMessage(e)}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _paymentLabel(String? method) {
    switch (method) {
      case 'balance':
        return 'Bakiye ile ödeme';
      case 'online':
        return 'Online ödeme';
      case 'cash':
        return 'Kapıda nakit';
      case 'card_on_delivery':
      case 'cardOnDelivery':
        return 'Kapıda kart';
      default:
        return method ?? '-';
    }
  }

  Future<void> _approve(ReturnRequest req) async {
    // null = vazgeçildi, '' = notsuz onay
    final note = await showDialog<String?>(
      context: context,
      builder: (ctx) => _NoteDialog(
        title: 'İadeyi Onayla',
        message: 'Sipariş #${req.orderNumber ?? req.orderId.substring(0, 8)} · '
            '${req.totalQuantity} ürün (${_paymentLabel(req.paymentMethod)})\n\n'
            '${req.isSellerCashRefund ? 'Kuryeli satıcı kapıda tahsil etmişti: '
                '₺${req.refundAmount.toStringAsFixed(2)} müşteriye SATICI tarafından nakit '
                'iade edilir, bakiyeye iade yapılmaz. Bu tutarın komisyonu satıcının '
                'komisyon borcundan düşülecek.' : '₺${req.refundAmount.toStringAsFixed(2)} '
                'müşterinin CizreApp bakiyesine OTOMATİK eklenecek; satıcının bu tutardaki '
                'payı mağaza hesabından düşülecek.'} Müşteriye ve satıcıya bildirim gider.',
        fieldLabel: 'Not (isteğe bağlı, müşteri görür)',
        confirmLabel: 'Onayla ve İade Et',
        confirmColor: Colors.green,
        minLength: 0,
      ),
    );
    if (note == null || !mounted) return;

    try {
      final result = await _service.approve(
        requestId: req.id,
        adminResponse: note.isEmpty ? null : note,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.isSellerCashRefund
                ? 'Onaylandı. Satıcı ₺${result.refundAmount.toStringAsFixed(2)} nakit iade edecek; '
                    'komisyon borcundan ₺${result.commissionRefundAmount.toStringAsFixed(2)} düşüldü.'
                : 'Onaylandı. ₺${result.refundAmount.toStringAsFixed(2)} bakiyeye iade edildi, '
                    'satıcıdan ₺${result.sellerDebitAmount.toStringAsFixed(2)} düşüldü.',
          ),
          backgroundColor: Colors.green,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Onay başarısız: ${returnErrorMessage(e)}'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _reject(ReturnRequest req) async {
    final note = await showDialog<String?>(
      context: context,
      builder: (ctx) => const _NoteDialog(
        title: 'İadeyi Reddet',
        fieldLabel: 'Red gerekçesi (müşteriye iletilir)',
        hint: 'Örn: Ürün kullanılmış, iade şartlarını karşılamıyor',
        confirmLabel: 'Reddet',
        confirmColor: Colors.red,
        minLength: 3,
      ),
    );
    if (note == null || !mounted) return;

    try {
      await _service.reject(requestId: req.id, adminResponse: note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reddedildi. Müşteriye bildirim gönderildi.'),
          backgroundColor: Colors.orange,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Red başarısız: ${returnErrorMessage(e)}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _markReceived(ReturnRequest req) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Teslim Alındı'),
        content: const Text(
          'Ürünlerin satıcıya ulaştığını satıcı adına işaretliyorsunuz. '
          'Stok değiştirilmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('İşaretle'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _service.markReceived(requestId: req.id);
      if (!mounted) return;
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(returnErrorMessage(e)),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
          child: Row(
            children: [
              for (final (value, label) in _filters)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _status == value,
                    onSelected: (_) {
                      if (_status == value) return;
                      setState(() => _status = value);
                      _load();
                    },
                  ),
                ),
            ],
          ),
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : RefreshIndicator(
                  onRefresh: _load,
                  child: _requests.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          children: [
                            const SizedBox(height: 80),
                            Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
                            const SizedBox(height: 12),
                            const Text(
                              'İade talebi yok',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontSize: 14, color: Colors.grey),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(12),
                          itemCount: _requests.length,
                          itemBuilder: (context, i) {
                            final r = _requests[i];
                            return ReturnRequestCard(
                              request: r,
                              viewer: ReturnCardViewer.admin,
                              actions: [
                                if (r.status == ReturnRequestStatus.pending) ...[
                                  OutlinedButton.icon(
                                    onPressed: () => _reject(r),
                                    icon: const Icon(Icons.close, size: 16),
                                    label: const Text('Reddet'),
                                    style: OutlinedButton.styleFrom(
                                      foregroundColor: Colors.red,
                                      side: const BorderSide(color: Colors.red),
                                    ),
                                  ),
                                  ElevatedButton.icon(
                                    onPressed: () => _approve(r),
                                    icon: const Icon(Icons.check, size: 16),
                                    label: const Text('Onayla'),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.green,
                                      foregroundColor: Colors.white,
                                    ),
                                  ),
                                ] else if (r.status == ReturnRequestStatus.approved)
                                  OutlinedButton.icon(
                                    onPressed: () => _markReceived(r),
                                    icon: const Icon(Icons.inventory_2_outlined, size: 16),
                                    label: const Text('Teslim Alındı İşaretle'),
                                  ),
                              ],
                            );
                          },
                        ),
                ),
        ),
      ],
    );
  }
}

/// Notlu onay/red diyaloğu. Controller diyaloğun kendi State'inde yaşar;
/// kapanış animasyonu sürerken dışarıda dispose edilmesin diye.
/// Vazgeçince null, onayda (boş olabilen) not döner.
class _NoteDialog extends StatefulWidget {
  final String title;
  final String? message;
  final String fieldLabel;
  final String? hint;
  final String confirmLabel;
  final Color confirmColor;
  final int minLength;

  const _NoteDialog({
    required this.title,
    this.message,
    required this.fieldLabel,
    this.hint,
    required this.confirmLabel,
    required this.confirmColor,
    required this.minLength,
  });

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final TextEditingController _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.message != null) ...[
              Text(widget.message!),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _ctrl,
              maxLines: 3,
              autofocus: widget.minLength > 0,
              decoration: InputDecoration(
                labelText: widget.fieldLabel,
                hintText: widget.hint,
                border: const OutlineInputBorder(),
                errorText: _error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Vazgeç'),
        ),
        ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: widget.confirmColor,
            foregroundColor: Colors.white,
          ),
          onPressed: () {
            final note = _ctrl.text.trim();
            if (note.length < widget.minLength) {
              setState(() => _error = 'En az ${widget.minLength} karakter');
              return;
            }
            Navigator.pop(context, note);
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

/// Sekme etiketi: bekleyen iade sayısı rozeti.
class ReturnRequestsTabLabel extends StatefulWidget {
  const ReturnRequestsTabLabel({super.key});

  @override
  State<ReturnRequestsTabLabel> createState() => _ReturnRequestsTabLabelState();
}

class _ReturnRequestsTabLabelState extends State<ReturnRequestsTabLabel> {
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final count = await ReturnRequestService().getPendingCount();
    if (!mounted) return;
    setState(() => _pendingCount = count);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('İade Talepleri'),
        if (_pendingCount > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$_pendingCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Bildirimden açılan bağımsız admin iade ekranı.
class AdminReturnRequestsScreen extends StatelessWidget {
  const AdminReturnRequestsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('İade Talepleri')),
      body: const ReturnRequestsTabWidget(),
    );
  }
}
