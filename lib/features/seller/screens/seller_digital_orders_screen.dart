// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/models/digital_order_model.dart';
import '../../../core/services/smm_service.dart';

class SellerDigitalOrdersScreen extends StatefulWidget {
  const SellerDigitalOrdersScreen({super.key});

  @override
  State<SellerDigitalOrdersScreen> createState() => _SellerDigitalOrdersScreenState();
}

class _SellerDigitalOrdersScreenState extends State<SellerDigitalOrdersScreen> {
  final _smmService = SmmService();
  SupabaseClient get _supabase => Supabase.instance.client;

  bool _isLoading = true;
  List<DigitalOrder> _orders = [];

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Kullanıcı oturumu bulunamadı');
      final shop = await _supabase
          .from('shops')
          .select('id')
          .eq('owner_id', userId)
          .maybeSingle();
      if (shop == null) throw Exception('Mağaza bulunamadı');

      final orders = await _smmService.getShopDigitalOrders(shop['id'] as String);
      if (mounted) setState(() => _orders = orders);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Siparişler yüklenemedi: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Kopyalandı')));
    }
  }

  Future<void> _showManualStatusDialog(DigitalOrder order) async {
    if (order.status == DigitalOrderStatus.canceled ||
        order.status == DigitalOrderStatus.refunded ||
        order.status == DigitalOrderStatus.failed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bu sipariş zaten kapanmış, durumu değiştirilemez')),
      );
      return;
    }

    String selected = 'completed';
    final remainsController = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Durumu Manuel Değiştir'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              RadioListTile<String>(
                title: const Text('Tamamlandı'),
                value: 'completed',
                groupValue: selected,
                onChanged: (v) => setDialogState(() => selected = v!),
              ),
              RadioListTile<String>(
                title: const Text('Kısmi Tamamlandı'),
                value: 'partial',
                groupValue: selected,
                onChanged: (v) => setDialogState(() => selected = v!),
              ),
              RadioListTile<String>(
                title: const Text('İptal Et (bakiye iade edilir)'),
                value: 'canceled',
                groupValue: selected,
                onChanged: (v) => setDialogState(() => selected = v!),
              ),
              if (selected == 'partial')
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: TextField(
                    controller: remainsController,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: 'Kalan (teslim edilmeyen) miktar',
                      helperText: 'Toplam miktar: ${order.quantity}',
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
            FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Kaydet')),
          ],
        ),
      ),
    );

    if (confirmed != true) return;

    int? remains;
    if (selected == 'partial') {
      remains = int.tryParse(remainsController.text.trim());
      if (remains == null || remains < 0 || remains > order.quantity) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Geçerli bir kalan miktar girin')),
          );
        }
        return;
      }
    }

    try {
      await _smmService.manualUpdateDigitalOrderStatus(
        digitalOrderId: order.id,
        newStatus: selected,
        remains: remains,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Durum güncellendi'), backgroundColor: Colors.green),
        );
      }
      await _loadOrders();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Güncellenemedi: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final totalEarnings = _smmService.calculateDigitalEarnings(_orders);
    return Scaffold(
      appBar: AppBar(title: const Text('Dijital Siparişler')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadOrders,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Card(
                    color: Colors.green.shade50,
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Dijital Ürün Kazancım', style: TextStyle(fontWeight: FontWeight.bold)),
                              SizedBox(height: 4),
                              Text('Bakiyenize eklenen net kazanç', style: TextStyle(fontSize: 12, color: Colors.grey)),
                            ],
                          ),
                          Text(
                            '₺${totalEarnings.toStringAsFixed(2)}',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: Colors.green.shade800,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  if (_orders.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(24),
                      child: Center(child: Text('Henüz dijital sipariş yok')),
                    )
                  else
                    ..._orders.map((order) => Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                      child: Text(
                                        order.productName ?? 'Dijital Ürün',
                                        style: const TextStyle(fontWeight: FontWeight.bold),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(order.status.label, style: const TextStyle(fontWeight: FontWeight.bold)),
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 20),
                                      tooltip: 'Durumu Manuel Değiştir',
                                      onPressed: () => _showManualStatusDialog(order),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(order.targetUrl, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.tag, size: 16, color: Colors.grey),
                                    const SizedBox(width: 4),
                                    Expanded(
                                      child: Text(
                                        'Gerçek Sipariş ID: ${order.externalOrderId ?? 'Henüz iletilmedi'}',
                                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                      ),
                                    ),
                                    if (order.externalOrderId != null)
                                      IconButton(
                                        icon: const Icon(Icons.copy, size: 18),
                                        onPressed: () => _copyToClipboard(order.externalOrderId!),
                                        tooltip: 'Kopyala',
                                      ),
                                  ],
                                ),
                                Text('Miktar: ${order.quantity} • Tutar: ₺${order.totalPrice.toStringAsFixed(2)}',
                                    style: const TextStyle(fontSize: 13)),
                                if (order.startCount != null || order.remains != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    [
                                      if (order.startCount != null) 'Başlangıç: ${order.startCount}',
                                      if (order.remains != null) 'Kalan: ${order.remains}',
                                    ].join(' • '),
                                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                                  ),
                                ],
                                if (order.sellerCredited && order.netSellerAmount != null) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    'Net kazanç: ₺${order.netSellerAmount!.toStringAsFixed(2)} (komisyon: ₺${order.commissionAmount?.toStringAsFixed(2) ?? '-'})',
                                    style: TextStyle(fontSize: 12, color: Colors.green.shade700, fontWeight: FontWeight.w600),
                                  ),
                                ],
                                const SizedBox(height: 4),
                                Text(
                                  'Oluşturulma: ${DateFormat('dd.MM.yyyy HH:mm').format(order.createdAt.toLocal())}',
                                  style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                                ),
                              ],
                            ),
                          ),
                        )),
                ],
              ),
            ),
    );
  }
}
