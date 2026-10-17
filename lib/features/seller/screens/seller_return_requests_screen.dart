import 'package:flutter/material.dart';

import '../../shop/services/return_request_service.dart';
import '../../shop/widgets/return_request_card.dart';
import '../widgets/common/seller_empty_state.dart';
import '../widgets/common/seller_list_skeleton.dart';

/// Satıcı İade Yönetimi Ekranı
///
/// İadeyi yönetici onaylar/reddeder (onayda para hareket etmez). Satıcı
/// onaylanan iadede ürünleri müşteriden teslim alınca "Teslim Aldım" der;
/// para iadesi ve satıcı payının düşülmesi bu anda DB'de yapılır (isteğe
/// bağlı stoğa geri ekleme).
class SellerReturnRequestsScreen extends StatefulWidget {
  const SellerReturnRequestsScreen({super.key});

  @override
  State<SellerReturnRequestsScreen> createState() => _SellerReturnRequestsScreenState();
}

class _SellerReturnRequestsScreenState extends State<SellerReturnRequestsScreen> {
  final ReturnRequestService _service = ReturnRequestService();

  bool _isLoading = true;
  String? _error;
  List<ReturnRequest> _returnRequests = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final list = await _service.getShopReturnRequests();
      if (!mounted) return;
      setState(() => _returnRequests = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = returnErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _markReceived(ReturnRequest request) async {
    var restock = false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Ürünleri Teslim Aldınız mı?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sipariş #${request.orderNumber ?? request.orderId.substring(0, 8)} için '
                '${request.totalQuantity} ürün müşteriden teslim alındı olarak işaretlenecek. '
                'İade süreci tamamlanır.',
              ),
              const SizedBox(height: 8),
              Text(
                request.isRefunded
                    ? 'Para iadesi yönetici tarafından müşterinin bakiyesine yapıldı; '
                        'müşteriye nakit vermeyin. Yalnız teslim alındı olarak işaretlenir.'
                    : request.isSellerCashRefund
                    ? 'Müşteriye ₺${request.refundAmount.toStringAsFixed(2)} nakit iade ettiğinizden '
                        'emin olun. Bu tutarın komisyonu borcunuzdan düşülür.'
                    : 'Onayınızla ₺${request.refundAmount.toStringAsFixed(2)} müşterinin bakiyesine '
                        'iade edilir ve bu tutardaki payınız (komisyon hariç) hesabınızdan düşülür.',
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: Colors.orange.shade900,
                ),
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: restock,
                onChanged: (v) => setDialogState(() => restock = v ?? false),
                title: const Text('Ürünleri stoğa geri ekle'),
                subtitle: const Text(
                  'Yalnız satılabilir durumdaysa işaretleyin. Sınırsız stoklu ürünler etkilenmez.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              child: const Text('Teslim Aldım'),
            ),
          ],
        ),
      ),
    );

    if (confirmed != true || !mounted) return;
    try {
      await _service.markReceived(requestId: request.id, restock: restock);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(restock
              ? 'İade tamamlandı, ürünler stoğa eklendi'
              : 'İade tamamlandı olarak işaretlendi'),
          backgroundColor: Colors.blue,
        ),
      );
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
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: const Text('İade Talepleri'),
        elevation: 0,
      ),
      body: _isLoading
          ? const SellerListSkeleton()
          : _error != null
              ? SellerEmptyState(
                  icon: Icons.error_outline,
                  message: 'İade talepleri yüklenemedi: $_error',
                )
              : _returnRequests.isEmpty
                  ? const SellerEmptyState(
                      icon: Icons.assignment_outlined,
                      message: 'İade talebi bulunmuyor',
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _returnRequests.length,
                        itemBuilder: (context, index) {
                          final r = _returnRequests[index];
                          return ReturnRequestCard(
                            request: r,
                            viewer: ReturnCardViewer.seller,
                            actions: [
                              if (r.status == ReturnRequestStatus.approved)
                                ElevatedButton.icon(
                                  onPressed: () => _markReceived(r),
                                  icon: const Icon(Icons.inventory_2_outlined, size: 18),
                                  label: const Text('Ürünleri Teslim Aldım'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                    foregroundColor: Colors.white,
                                  ),
                                ),
                            ],
                          );
                        },
                      ),
                    ),
    );
  }
}
