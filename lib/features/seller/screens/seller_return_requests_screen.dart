import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../shop/services/return_request_service.dart';

/// Satıcı İade Yönetimi Ekranı
class SellerReturnRequestsScreen extends StatefulWidget {
  const SellerReturnRequestsScreen({super.key});

  @override
  State<SellerReturnRequestsScreen> createState() => _SellerReturnRequestsScreenState();
}

class _SellerReturnRequestsScreenState extends State<SellerReturnRequestsScreen> {
  final ReturnRequestService _returnRequestService = ReturnRequestService();
  final _supabase = Supabase.instance.client;
  
  bool _isLoading = true;
  List<ReturnRequest> _returnRequests = [];
  String? _shopId;

  @override
  void initState() {
    super.initState();
    _loadShopAndRequests();
  }

  Future<void> _loadShopAndRequests() async {
    setState(() => _isLoading = true);
    
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('❌ RETURN REQUESTS: Kullanıcı oturum açmamış');
        return;
      }

      debugPrint('📦 RETURN REQUESTS: Satıcının dükkanı aranıyor... userId: $userId');
      
      // Satıcının dükkånını bul
      final shopResponse = await _supabase
          .from('shops')
          .select('id')
          .eq('owner_id', userId)
          .maybeSingle();

      debugPrint('📦 RETURN REQUESTS: Dükkan yanıtı: $shopResponse');

      if (shopResponse != null) {
        _shopId = shopResponse['id'];
        debugPrint('✅ RETURN REQUESTS: Dükkan bulundu - shopId: $_shopId');
        debugPrint('📦 RETURN REQUESTS: İade talepleri çekiliyor...');
        _returnRequests = await _returnRequestService.getShopReturnRequests(_shopId!);
        debugPrint('✅ RETURN REQUESTS: ${_returnRequests.length} adet iade talebi bulundu');
      } else {
        debugPrint('❌ RETURN REQUESTS: Satıcının dükkanı bulunamadı!');
      }
    } catch (e) {
      debugPrint('İade talepleri yüklenirken hata: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleReturnRequest(ReturnRequest request, bool approve) async {
    final responseController = TextEditingController();
    
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(approve ? 'İade Talebini Onayla' : 'İade Talebini Reddet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Müşteri: ${request.userName ?? "Bilinmiyor"}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text('İade sebebi: ${request.reason}'),
            if (request.orderTotal != null) ...[
              const SizedBox(height: 8),
              Text('Sipariş tutarı: ₺${request.orderTotal!.toStringAsFixed(2)}'),
            ],
            const SizedBox(height: 16),
            TextField(
              controller: responseController,
              maxLines: 3,
              decoration: InputDecoration(
                labelText: approve ? 'Onay mesajı (opsiyonel)' : 'Red sebebi',
                hintText: approve 
                    ? 'Örn: İadeniz onaylandı, 3-5 iş günü içinde hesabınıza yansıyacak'
                    : 'Örn: Ürün kullanılmış durumda, iade şartlarını karşılamıyor',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              responseController.dispose();
              Navigator.pop(context, false);
            },
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context, true);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: approve ? Colors.green : Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(approve ? 'Onayla' : 'Reddet'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      try {
        await _returnRequestService.updateReturnRequest(
          requestId: request.id,
          status: approve ? ReturnRequestStatus.approved : ReturnRequestStatus.rejected,
          adminResponse: responseController.text.trim().isEmpty 
              ? null 
              : responseController.text.trim(),
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(approve 
                  ? 'İade talebi onaylandı'
                  : 'İade talebi reddedildi'),
              backgroundColor: approve ? Colors.green : Colors.red,
            ),
          );
          await _loadShopAndRequests();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Hata: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
    
    responseController.dispose();
  }

  Future<void> _markAsCompleted(ReturnRequest request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('İadeyi Tamamla'),
        content: const Text(
          'İade işlemi tamamlandı mı? Bu işlem iade talebini "Tamamlandı" olarak işaretler.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Hayır'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Evet, Tamamla'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      try {
        await _returnRequestService.updateReturnRequest(
          requestId: request.id,
          status: ReturnRequestStatus.completed,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('İade işlemi tamamlandı olarak işaretlendi'),
              backgroundColor: Colors.blue,
            ),
          );
          await _loadShopAndRequests();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Hata: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
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
          ? const Center(child: CircularProgressIndicator())
          : _returnRequests.isEmpty
              ? _buildEmptyState()
              : RefreshIndicator(
                  onRefresh: _loadShopAndRequests,
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
            Icons.assignment_outlined,
            size: 80,
            color: Colors.grey.shade300,
          ),
          const SizedBox(height: 24),
          Text(
            'İade talebi bulunmuyor',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReturnRequestCard(ReturnRequest request) {
    final statusInfo = _getStatusInfo(request.status);
    
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Başlık ve Durum
            Row(
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
                        request.userName ?? 'Müşteri',
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
                  child: Text(
                    statusInfo.label,
                    style: TextStyle(
                      color: statusInfo.color,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            const Divider(height: 1),
            const SizedBox(height: 16),
            
            // İade Sebebi
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.report_problem_outlined, color: Colors.amber.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'İade Sebebi',
                          style: TextStyle(
                            color: Colors.amber.shade900,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          request.reason,
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
            
            // Admin Yanıtı
            if (request.adminResponse != null && request.adminResponse!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.reply, color: Colors.blue.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        request.adminResponse!,
                        style: TextStyle(fontSize: 14, color: Colors.grey.shade800),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            
            const SizedBox(height: 16),
            
            // Bilgiler
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
                      color: Color(0xFFF97316),
                    ),
                  ),
              ],
            ),
            
            // Aksiyon Butonları
            if (request.status == ReturnRequestStatus.pending) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _handleReturnRequest(request, false),
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Reddet'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _handleReturnRequest(request, true),
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('Onayla'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ] else if (request.status == ReturnRequestStatus.approved) ...[
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _markAsCompleted(request),
                  icon: const Icon(Icons.task_alt, size: 18),
                  label: const Text('Tamamlandı Olarak İşaretle'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  ({Color color, String label}) _getStatusInfo(ReturnRequestStatus status) {
    switch (status) {
      case ReturnRequestStatus.pending:
        return (color: Colors.orange, label: 'Beklemede');
      case ReturnRequestStatus.approved:
        return (color: Colors.green, label: 'Onaylandı');
      case ReturnRequestStatus.rejected:
        return (color: Colors.red, label: 'Reddedildi');
      case ReturnRequestStatus.completed:
        return (color: Colors.blue, label: 'Tamamlandı');
    }
  }

  String _formatDate(DateTime dateTime) {
    return '${dateTime.day.toString().padLeft(2, '0')}/${dateTime.month.toString().padLeft(2, '0')}/${dateTime.year} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}';
  }
}
