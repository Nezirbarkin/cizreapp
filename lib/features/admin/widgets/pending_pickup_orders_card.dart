import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

/// Müşterisi "Teslim Aldım" onayı vermemiş, uzun süredir hazır bekleyen
/// "Gel Al" siparişleri.
///
/// Gel Al siparişleri peşin (bakiyeden) tahsil edilir ama satıcının kazancı
/// ancak sipariş `delivered` olunca işlenir. Onay gelmezse para askıda kalır;
/// otomatik kapatma bilinçli olarak YOK (yanlış ödeme riski), bunun yerine
/// admin burada görüp müşteri/satıcı ile iletişime geçer.
///
/// Hiç bekleyen sipariş yoksa widget hiçbir yer kaplamaz.
class PendingPickupOrdersCard extends StatefulWidget {
  /// Kaç günden uzun süredir bekleyenler listelensin.
  final int minDays;

  const PendingPickupOrdersCard({super.key, this.minDays = 2});

  @override
  State<PendingPickupOrdersCard> createState() =>
      _PendingPickupOrdersCardState();
}

class _PendingPickupOrdersCardState extends State<PendingPickupOrdersCard> {
  late Future<List<Map<String, dynamic>>> _future;
  bool _expanded = false;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<List<Map<String, dynamic>>> _load() async {
    try {
      final response = await Supabase.instance.client.rpc(
        'admin_list_pending_pickup_orders',
        params: {'p_min_days': widget.minDays},
      );
      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('Bekleyen Gel Al siparişleri alınamadı: $e');
      return [];
    }
  }

  Future<void> _call(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _future,
      builder: (context, snapshot) {
        final orders = snapshot.data ?? const <Map<String, dynamic>>[];
        if (orders.isEmpty) return const SizedBox.shrink();

        return Card(
          // Yatay boşluk üst ekranın padding'inden gelir.
          margin: const EdgeInsets.only(bottom: 16),
          color: Colors.orange.shade50,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: Colors.orange.shade200),
          ),
          child: Column(
            children: [
              ListTile(
                leading: Icon(
                  Icons.hourglass_bottom,
                  color: Colors.orange.shade800,
                ),
                title: Text(
                  'Teslim onayı bekleyen Gel Al siparişi: ${orders.length}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade900,
                    fontSize: 14,
                  ),
                ),
                subtitle: Text(
                  '${widget.minDays} günden uzun süredir "hazır" durumunda; '
                  'müşteri teslim onayı vermediği için satıcı kazancı işlenmedi.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.orange.shade900,
                  ),
                ),
                trailing: Icon(
                  _expanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.orange.shade800,
                ),
                onTap: () => setState(() => _expanded = !_expanded),
              ),
              if (_expanded)
                ...orders.map((order) => _buildRow(order)),
              if (_expanded)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: TextButton.icon(
                    onPressed: () => setState(() => _future = _load()),
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Yenile'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildRow(Map<String, dynamic> order) {
    final orderNo = order['order_number_int']?.toString() ??
        (order['order_number'] as String? ?? '').toString();
    final days = (order['days_waiting'] as num?)?.toInt() ?? 0;
    final total = (order['total'] as num?)?.toDouble() ?? 0;
    final shopName = order['shop_name'] as String? ?? 'Dükkan';
    final customerName = order['customer_name'] as String? ?? 'Müşteri';
    final customerPhone = order['customer_phone'] as String?;
    final shopPhone = order['shop_phone'] as String?;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.orange.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '#$orderNo • $shopName',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: Colors.orange.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$days gün',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.orange.shade900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            '$customerName • ₺${total.toStringAsFixed(2)}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              if (customerPhone != null && customerPhone.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _call(customerPhone),
                  icon: const Icon(Icons.phone, size: 14),
                  label: const Text('Müşteri', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              if (shopPhone != null && shopPhone.isNotEmpty)
                TextButton.icon(
                  onPressed: () => _call(shopPhone),
                  icon: const Icon(Icons.storefront, size: 14),
                  label: const Text('Dükkan', style: TextStyle(fontSize: 12)),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
