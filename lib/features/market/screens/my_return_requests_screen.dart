import 'package:flutter/material.dart';

import '../../shop/services/return_request_service.dart';
import '../../shop/widgets/return_request_card.dart';

/// Müşteri İade Takibi Ekranı
class MyReturnRequestsScreen extends StatefulWidget {
  const MyReturnRequestsScreen({super.key});

  @override
  State<MyReturnRequestsScreen> createState() => _MyReturnRequestsScreenState();
}

class _MyReturnRequestsScreenState extends State<MyReturnRequestsScreen> {
  final ReturnRequestService _service = ReturnRequestService();
  bool _isLoading = true;
  String? _error;
  List<ReturnRequest> _returnRequests = [];

  @override
  void initState() {
    super.initState();
    _loadReturnRequests();
  }

  Future<void> _loadReturnRequests() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final list = await _service.getMyReturnRequests();
      if (!mounted) return;
      setState(() => _returnRequests = list);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = returnErrorMessage(e));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _cancel(ReturnRequest request) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Talebi Geri Çek'),
        content: const Text('Bu iade talebini geri çekmek istiyor musunuz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Geri Çek'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _service.cancelReturnRequest(request.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İade talebiniz geri çekildi')),
      );
      await _loadReturnRequests();
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
        title: const Text('İade Taleplerim'),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadReturnRequests,
              child: _error != null
                  ? _buildMessage(Icons.error_outline, 'İade talepleri yüklenemedi', _error!)
                  : _returnRequests.isEmpty
                      ? _buildMessage(
                          Icons.assignment_return_outlined,
                          'İade talebiniz bulunmuyor',
                          'Teslim edilmiş siparişleriniz için ${ReturnRequestService.returnWindowDays} '
                              'gün içinde\nsipariş detayından iade talebi oluşturabilirsiniz',
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _returnRequests.length,
                          itemBuilder: (context, index) {
                            final r = _returnRequests[index];
                            return ReturnRequestCard(
                              request: r,
                              viewer: ReturnCardViewer.customer,
                              actions: [
                                if (r.status == ReturnRequestStatus.pending)
                                  OutlinedButton.icon(
                                    onPressed: () => _cancel(r),
                                    icon: const Icon(Icons.undo, size: 18),
                                    label: const Text('Talebi Geri Çek'),
                                  ),
                              ],
                            );
                          },
                        ),
            ),
    );
  }

  /// Boş/hata durumu — RefreshIndicator çalışsın diye kaydırılabilir.
  Widget _buildMessage(IconData icon, String title, String body) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        const SizedBox(height: 120),
        Icon(icon, size: 80, color: Colors.grey.shade300),
        const SizedBox(height: 24),
        Text(
          title,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            body,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
          ),
        ),
      ],
    );
  }
}
