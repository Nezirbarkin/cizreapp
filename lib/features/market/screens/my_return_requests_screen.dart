// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shop/services/return_request_service.dart';

/// Müşteri İade Takibi Ekranı
class MyReturnRequestsScreen extends StatefulWidget {
  const MyReturnRequestsScreen({super.key});

  @override
  State<MyReturnRequestsScreen> createState() => _MyReturnRequestsScreenState();
}

class _MyReturnRequestsScreenState extends State<MyReturnRequestsScreen> {
  final ReturnRequestService _returnRequestService = ReturnRequestService();
  late String userId;
  bool _isLoading = true;
  List<ReturnRequest> _returnRequests = [];

  @override
  void initState() {
    super.initState();
    userId = Supabase.instance.client.auth.currentUser?.id ?? '';
    _loadReturnRequests();
  }

  Future<void> _loadReturnRequests() async {
    if (userId.isEmpty) return;
    
    setState(() => _isLoading = true);
    try {
      _returnRequests = await _returnRequestService.getUserReturnRequests(userId);
    } catch (e) {
      debugPrint('İade talepleri yüklenirken hata: $e');
    } finally {
      setState(() => _isLoading = false);
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
          : _returnRequests.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadReturnRequests,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _returnRequests.length,
                    itemBuilder: (context, index) {
                      return _buildReturnRequestCard(_returnRequests[index]);
                    },
                  ),
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.assignment_return_outlined,
            size: 80,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 24),
          Text(
            'İade talebiniz bulunmuyor',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Teslim edilmiş siparişleriniz için\niade talebi oluşturabilirsiniz',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReturnRequestCard(ReturnRequest request) {
    final statusInfo = _getStatusInfo(request.status);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Başlık ve Durum
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Sipariş #${request.orderNumber ?? request.orderId.substring(0, 8)}',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        request.shopName ?? 'Dükkan',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    // ignore: deprecated_member_use
                    color: statusInfo.color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusInfo.icon, size: 16, color: statusInfo.color),
                      const SizedBox(width: 6),
                      Text(
                        statusInfo.label,
                        style: TextStyle(
                          color: statusInfo.color,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            
            // İade Sebebi
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(Icons.message_outlined, size: 18, color: Colors.grey.shade600),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'İade Sebebi',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        request.reason,
                        style: const TextStyle(fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            
            // Satıcı/Admin Yanıtı
            if (request.adminResponse != null && request.adminResponse!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: statusInfo.color.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: statusInfo.color.withOpacity(0.3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.reply, size: 18, color: statusInfo.color),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Satıcı Yanıtı',
                            style: TextStyle(
                              color: statusInfo.color,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            request.adminResponse!,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.grey.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 16),
            
            // Tarih ve Tutar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDate(request.createdAt),
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
                if (request.orderTotal != null)
                  Text(
                    '₺${request.orderTotal!.toStringAsFixed(2)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  ({Color color, IconData icon, String label}) _getStatusInfo(ReturnRequestStatus status) {
    switch (status) {
      case ReturnRequestStatus.pending:
        return (color: Colors.orange, icon: Icons.hourglass_empty, label: 'Beklemede');
      case ReturnRequestStatus.approved:
        return (color: Colors.green, icon: Icons.check_circle, label: 'Onaylandı');
      case ReturnRequestStatus.rejected:
        return (color: Colors.red, icon: Icons.cancel, label: 'Reddedildi');
      case ReturnRequestStatus.completed:
        return (color: Colors.blue, icon: Icons.task_alt, label: 'Tamamlandı');
    }
  }

  String _formatDate(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
