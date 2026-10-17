import 'package:flutter/material.dart';

import '../../shop/services/return_request_service.dart';
import '../../shop/widgets/return_request_card.dart';

/// Admin "İade Talepleri" sekmesi.
///
/// Müşterinin tümü/seçili ürünler için açtığı iade talepleri buraya düşer.
/// İşlem (DB tarafında atomik RPC):
/// - Onayla: approve_return_request → para hareketi YOK; müşteriye ve
///   satıcıya bildirim ("ürünü teslim edin / teslim alınca onaylayın").
/// - Reddet: reject_return_request → müşteriye bildirim
/// - Teslim alındı (satıcı ya da onun yerine yönetici): mark_return_received
///     ├─ iade tutarı müşterinin bakiyesine eklenir (kuryeli satıcının kapıda
///     │  tahsilatında satıcı nakit iade eder, komisyon borcundan düşer)
///     ├─ satıcıdan iade − komisyon geri alınır
///     └─ sipariş tamamen iade edildiyse payment_status = 'refunded'
class ReturnRequestsTabWidget extends StatefulWidget {
  /// Onay/ret/teslim sonrası (ör. sol menü rozetini yenilemek için).
  final VoidCallback? onChanged;

  const ReturnRequestsTabWidget({super.key, this.onChanged});

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
    widget.onChanged?.call();
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
    // null = vazgeçildi; note '' = notsuz onay; checked = hemen iade et
    final result = await showDialog<_NoteResult?>(
      context: context,
      builder: (ctx) => _NoteDialog(
        title: 'İadeyi Onayla',
        message: 'Sipariş #${req.orderNumber ?? req.orderId.substring(0, 8)} · '
            '${req.totalQuantity} ürün (${_paymentLabel(req.paymentMethod)})\n\n'
            'Onayda para hareket etmez. Müşteri ürünleri satıcıya teslim eder; '
            '${req.isSellerCashRefund ? 'kuryeli satıcı kapıda tahsil ettiği için '
                '₺${req.refundAmount.toStringAsFixed(2)} müşteriye SATICI tarafından nakit '
                'iade edilir ve satıcı teslim aldığını onaylayınca bu tutarın komisyonu '
                'satıcının borcundan düşülür.' : 'satıcı teslim aldığını onaylayınca '
                '₺${req.refundAmount.toStringAsFixed(2)} müşterinin CizreApp bakiyesine '
                'OTOMATİK eklenir ve satıcının payı mağaza hesabından düşülür.'} '
            'Müşteriye ve satıcıya bildirim gider.',
        fieldLabel: 'Not (isteğe bağlı, müşteri görür)',
        checkboxLabel: 'Satıcıyı beklemeden müşteriye hemen iade et',
        checkboxHint: 'Tutar şimdi müşterinin bakiyesine eklenir, satıcının payı '
            'hesabından düşülür; ürünler yine satıcıya teslim edilir.',
        confirmLabel: 'Onayla',
        confirmColor: Colors.green,
        minLength: 0,
      ),
    );
    if (result == null || !mounted) return;
    final note = result.note.isEmpty ? null : result.note;

    try {
      final updated = result.checked
          ? await _service.refundNow(requestId: req.id, adminResponse: note)
          : await _service.approve(requestId: req.id, adminResponse: note);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.checked
                ? 'Onaylandı ve ₺${updated.refundAmount.toStringAsFixed(2)} müşterinin '
                    'bakiyesine iade edildi; satıcıdan ₺${updated.sellerDebitAmount.toStringAsFixed(2)} düşüldü.'
                : 'Onaylandı. Satıcı ürünleri teslim alınca ₺${updated.refundAmount.toStringAsFixed(2)} '
                    '${updated.isSellerCashRefund ? 'satıcı tarafından nakit' : 'bakiyeye'} iade edilecek.',
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
    final result = await showDialog<_NoteResult?>(
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
    if (result == null || !mounted) return;

    try {
      await _service.reject(requestId: req.id, adminResponse: result.note);
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

  /// Onaylı ama parası ödenmemiş talepte satıcıyı beklemeden hemen iade.
  Future<void> _refundNow(ReturnRequest req) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hemen İade Et'),
        content: Text(
          '₺${req.refundAmount.toStringAsFixed(2)} satıcının ürünleri teslim almasını beklemeden '
          'müşterinin CizreApp bakiyesine şimdi eklenir; satıcının payı (komisyon hariç) '
          'hesabından düşülür.'
          '${req.isSellerCashRefund ? '\n\nSipariş kapıda nakit ödenmişti: satıcı müşteriye nakit '
              'VERMEYECEK, iade payı satıcının borcuna yazılır.' : ''}'
          '\n\nSatıcı ürünleri teslim alınca yine "Teslim Aldım" der; para tekrar hareket etmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Şimdi İade Et'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      final updated = await _service.refundNow(requestId: req.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '₺${updated.refundAmount.toStringAsFixed(2)} müşterinin bakiyesine iade edildi; '
            'satıcıdan ₺${updated.sellerDebitAmount.toStringAsFixed(2)} düşüldü.',
          ),
          backgroundColor: Colors.green,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('İade başarısız: ${returnErrorMessage(e)}'),
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
        content: Text(
          'Ürünlerin satıcıya ulaştığını satıcı adına işaretliyorsunuz. '
          '${req.isRefunded ? 'Para iadesi daha önce yapıldı; tekrar ödeme olmaz.' : req.isSellerCashRefund ? 'Satıcının müşteriye ₺${req.refundAmount.toStringAsFixed(2)} nakit iade ettiği kabul edilir ve komisyonu borcundan düşülür.' : '₺${req.refundAmount.toStringAsFixed(2)} müşterinin bakiyesine eklenir, satıcının payı hesabından düşülür.'} '
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
                                ] else if (r.status == ReturnRequestStatus.approved) ...[
                                  if (!r.isRefunded)
                                    ElevatedButton.icon(
                                      onPressed: () => _refundNow(r),
                                      icon: const Icon(Icons.account_balance_wallet, size: 16),
                                      label: const Text('Hemen İade Et'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.green,
                                        foregroundColor: Colors.white,
                                      ),
                                    ),
                                  OutlinedButton.icon(
                                    onPressed: () => _markReceived(r),
                                    icon: const Icon(Icons.inventory_2_outlined, size: 16),
                                    label: Text(r.isRefunded ? 'Teslim Alındı İşaretle' : 'Teslim Alındı'),
                                  ),
                                ],
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
/// _NoteDialog sonucu: not (boş olabilir) + isteğe bağlı onay kutusu.
class _NoteResult {
  final String note;
  final bool checked;

  const _NoteResult(this.note, this.checked);
}

class _NoteDialog extends StatefulWidget {
  final String title;
  final String? message;
  final String fieldLabel;
  final String? hint;
  final String confirmLabel;
  final Color confirmColor;
  final int minLength;
  final String? checkboxLabel;
  final String? checkboxHint;

  const _NoteDialog({
    required this.title,
    this.message,
    required this.fieldLabel,
    this.hint,
    required this.confirmLabel,
    required this.confirmColor,
    required this.minLength,
    this.checkboxLabel,
    this.checkboxHint,
  });

  @override
  State<_NoteDialog> createState() => _NoteDialogState();
}

class _NoteDialogState extends State<_NoteDialog> {
  final TextEditingController _ctrl = TextEditingController();
  String? _error;
  bool _checked = false;

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
            if (widget.checkboxLabel != null)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _checked,
                onChanged: (v) => setState(() => _checked = v ?? false),
                title: Text(widget.checkboxLabel!, style: const TextStyle(fontSize: 14)),
                subtitle: widget.checkboxHint == null
                    ? null
                    : Text(widget.checkboxHint!, style: const TextStyle(fontSize: 12)),
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
            Navigator.pop(context, _NoteResult(note, _checked));
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

/// Admin "İade Talepleri" ekranı: sol menüden ve bildirimden açılır.
class AdminReturnRequestsScreen extends StatelessWidget {
  final VoidCallback? onChanged;

  const AdminReturnRequestsScreen({super.key, this.onChanged});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('İade Talepleri'),
        backgroundColor: Colors.white,
      ),
      body: ReturnRequestsTabWidget(onChanged: onChanged),
    );
  }
}
