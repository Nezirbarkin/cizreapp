import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Admin panelindeki şehir içi paket taleplerini listeler ve yönetir.
///
/// Bu widget, dashboard ekranından davranış değişikliği yapılmadan ayrıştırıldı.
class AdminPackageRequestsTab extends StatefulWidget {
  const AdminPackageRequestsTab({super.key});

  @override
  State<AdminPackageRequestsTab> createState() =>
      _AdminPackageRequestsTabState();
}

class _AdminPackageRequestsTabState extends State<AdminPackageRequestsTab> {
  List<Map<String, dynamic>> _requests = [];
  bool _isLoading = true;
  String? _error;

  Future<void> _openLocation(num? lat, num? lng) async {
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu adres için konum bilgisi yok')),
      );
      return;
    }
    final url = Uri.parse('https://www.google.com/maps?q=$lat,$lng');
    await launchUrl(url, mode: LaunchMode.externalApplication);
  }

  Widget _buildAddressLine(
    String label,
    dynamic address,
    dynamic lat,
    dynamic lng,
  ) {
    final hasLocation = lat != null && lng != null;
    return InkWell(
      onTap: () => _openLocation(lat as num?, lng as num?),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Text(
              '$label: ${address ?? '-'}',
              style: TextStyle(
                fontSize: 13,
                color: hasLocation ? Colors.blue.shade700 : null,
                decoration: hasLocation ? TextDecoration.underline : null,
              ),
            ),
          ),
          if (hasLocation)
            Icon(Icons.map_outlined, size: 16, color: Colors.blue.shade700),
        ],
      ),
    );
  }

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
      final response = await Supabase.instance.client
          .from('courier_requests')
          .select()
          .order('created_at', ascending: false)
          .limit(100);
      final requests = List<Map<String, dynamic>>.from(response as List);

      // courier_requests.courier_id -> auth.users(id) olduğu için PostgREST
      // FK embed'i profiles ile ilişki kuramıyor; kurye bilgisini manuel eşleştiriyoruz.
      final courierIds = requests
          .map((r) => r['courier_id'] as String?)
          .where((id) => id != null)
          .cast<String>()
          .toSet()
          .toList();

      if (courierIds.isNotEmpty) {
        final couriers = await Supabase.instance.client
            .from('profiles')
            .select('id, full_name, phone')
            .inFilter('id', courierIds);
        final courierMap = {
          for (final c in List<Map<String, dynamic>>.from(couriers))
            c['id'] as String: c,
        };
        for (final r in requests) {
          final courierId = r['courier_id'] as String?;
          if (courierId != null) r['courier'] = courierMap[courierId];
        }
      }

      setState(() {
        _requests = requests;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _cancel(Map<String, dynamic> request) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Paketi İptal Et'),
        content: const Text(
          'Bu paket talebini iptal etmek istediğine emin misin? Ücret gönderene iade edilecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('İptal Et'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    final requestId = request['id'] as String?;
    if (requestId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Geçersiz talep kimliği'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      // Atomik admin iade RPC'si: courier_requests FOR UPDATE kilidi + admin
      // kontrolü + add_to_balance + notification tek transaction içinde. İstemci
      // user_id veya tutar göndermez; sunucu tarafı doğrulanmış ödeme
      // kaydından iade tutarını belirler.
      await Supabase.instance.client.rpc(
        'admin_cancel_courier_request_with_refund',
        params: {'p_request_id': requestId},
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Paket talebi iptal edildi'),
          backgroundColor: Colors.green,
        ),
      );
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('İptal başarısız: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _markDelivered(Map<String, dynamic> request) async {
    try {
      await Supabase.instance.client
          .from('courier_requests')
          .update({
            'status': 'delivered',
            'delivered_at': DateTime.now().toIso8601String(),
          })
          .eq('id', request['id']);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Paket teslim edildi olarak işaretlendi'),
            backgroundColor: Colors.green,
          ),
        );
      }
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String _statusLabel(String? status) {
    switch (status) {
      case 'pending':
        return 'Bekliyor';
      case 'accepted':
        return 'Kurye Yolda';
      case 'delivered':
        return 'Teslim Edildi';
      case 'cancelled':
        return 'İptal Edildi';
      default:
        return status ?? '-';
    }
  }

  Color _statusColor(String? status) {
    switch (status) {
      case 'pending':
        return Colors.orange;
      case 'accepted':
        return Colors.blue;
      case 'delivered':
        return Colors.green;
      case 'cancelled':
        return Colors.red;
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('Hata: $_error'));
    if (_requests.isEmpty) {
      return const Center(child: Text('Henüz paket talebi yok'));
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _requests.length,
        itemBuilder: (context, index) {
          final r = _requests[index];
          final courier = r['courier'] as Map<String, dynamic>?;
          final totalFee = (r['total_fee'] as num?)?.toDouble() ?? 0;
          final status = r['status'] as String?;
          final isFinal = status == 'delivered' || status == 'cancelled';

          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Gönderen: ${r['sender_name'] ?? '-'}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor(status).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _statusLabel(status),
                          style: TextStyle(
                            color: _statusColor(status),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _buildAddressLine(
                    'Alım',
                    r['pickup_address'],
                    r['pickup_lat'],
                    r['pickup_lng'],
                  ),
                  _buildAddressLine(
                    'Teslim',
                    r['delivery_address'],
                    r['delivery_lat'],
                    r['delivery_lng'],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    courier != null
                        ? 'Atanan Kurye: ${courier['full_name'] ?? '-'} (${courier['phone'] ?? '-'})'
                        : 'Atanan Kurye: Henüz atanmadı',
                    style: const TextStyle(
                      fontSize: 13,
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '${totalFee.toStringAsFixed(2)} ₺',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.teal,
                    ),
                  ),
                  if (!isFinal) ...[
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _cancel(r),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                            child: const Text('İptal Et'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _markDelivered(r),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.teal,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Teslim Edildi'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  bool _isValidImageUrl(dynamic url) {
    if (url == null) return false;
    final urlStr = url.toString().trim();
    if (urlStr.isEmpty) return false;
    return urlStr.startsWith('http://') || urlStr.startsWith('https://');
  }
}
