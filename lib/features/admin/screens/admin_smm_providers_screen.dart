// ignore_for_file: deprecated_member_use
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/models/smm_provider_model.dart';
import '../../../core/models/digital_order_model.dart';
import '../../../core/services/smm_service.dart';

class AdminSmmProvidersScreen extends StatefulWidget {
  const AdminSmmProvidersScreen({super.key});

  @override
  State<AdminSmmProvidersScreen> createState() => _AdminSmmProvidersScreenState();
}

class _AdminSmmProvidersScreenState extends State<AdminSmmProvidersScreen>
    with SingleTickerProviderStateMixin {
  final _smmService = SmmService();
  SupabaseClient get _supabase => Supabase.instance.client;

  late TabController _tabController;
  bool _isLoading = true;
  List<SmmProvider> _providers = [];
  List<Map<String, dynamic>> _shops = [];
  List<DigitalOrder> _allOrders = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final providers = await _smmService.getProviders();
      final userId = _supabase.auth.currentUser?.id;
      final shops = await _supabase
          .from('shops')
          .select('id, name, can_use_own_smm_api, digital_commission_rate')
          .order('name');
      final orders = await _smmService.getAllDigitalOrders();
      setState(() {
        _providers = providers;
        _shops = List<Map<String, dynamic>>.from(shops);
        _allOrders = orders;
      });
      // ignore: unused_local_variable
      final _ = userId;
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yüklenirken hata: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showDigitalCommissionDialog(Map<String, dynamic> shop) async {
    final controller = TextEditingController(
      text: (shop['digital_commission_rate'] as num?)?.toString() ?? '',
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('${shop['name']} - Dijital Komisyon Oranı'),
        content: TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: const InputDecoration(
            labelText: 'Komisyon Oranı (%)',
            helperText: 'Boş bırakılırsa varsayılan %10 uygulanır. Fiziksel sipariş komisyonundan bağımsızdır.',
            border: OutlineInputBorder(),
            suffixText: '%',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Kaydet')),
        ],
      ),
    );

    if (confirmed != true) return;

    final text = controller.text.trim();
    double? rate;
    if (text.isNotEmpty) {
      rate = double.tryParse(text);
      if (rate == null || rate < 0 || rate > 100) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('0-100 arasında geçerli bir oran girin')),
          );
        }
        return;
      }
    }

    try {
      await _supabase.from('shops').update({'digital_commission_rate': rate}).eq('id', shop['id']);
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Güncellenemedi: $e')));
      }
    }
  }

  Future<void> _toggleShopPermission(String shopId, bool value) async {
    try {
      await _supabase.from('shops').update({'can_use_own_smm_api': value}).eq('id', shopId);
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Güncellenemedi: $e')),
        );
      }
    }
  }

  Future<void> _showAddProviderDialog() async {
    final nameController = TextEditingController();
    final apiUrlController = TextEditingController(text: 'https://smmget.com/api/v2');
    final apiKeyController = TextEditingController();
    final userId = _supabase.auth.currentUser?.id;

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Admin SMM Sağlayıcısı Ekle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Sağlayıcı Adı'),
            ),
            TextField(
              controller: apiUrlController,
              decoration: const InputDecoration(labelText: 'API URL'),
            ),
            TextField(
              controller: apiKeyController,
              decoration: const InputDecoration(labelText: 'API Key'),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Ekle')),
        ],
      ),
    );

    if (result == true && userId != null) {
      if (nameController.text.trim().isEmpty || apiKeyController.text.trim().isEmpty) return;
      try {
        await _smmService.createProvider(
          name: nameController.text.trim(),
          apiUrl: apiUrlController.text.trim(),
          apiKey: apiKeyController.text.trim(),
          ownerType: 'admin',
          ownerId: userId,
        );
        await _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Eklenemedi: $e')));
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TabBar(
          controller: _tabController,
          labelColor: Theme.of(context).colorScheme.primary,
          tabs: const [
            Tab(text: 'Sağlayıcılar'),
            Tab(text: 'Satıcı Yetkileri'),
            Tab(text: 'Tüm Siparişler'),
          ],
        ),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : TabBarView(
                  controller: _tabController,
                  children: [
                    _buildProvidersTab(),
                    _buildPermissionsTab(),
                    _buildAllOrdersTab(),
                  ],
                ),
        ),
      ],
    );
  }

  Future<void> _showEditProviderDialog(SmmProvider provider) async {
    final nameController = TextEditingController(text: provider.name);
    final apiUrlController = TextEditingController(text: provider.apiUrl);
    final apiKeyController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Sağlayıcıyı Düzenle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameController,
              decoration: const InputDecoration(labelText: 'Sağlayıcı Adı'),
            ),
            TextField(
              controller: apiUrlController,
              decoration: const InputDecoration(labelText: 'API URL'),
            ),
            TextField(
              controller: apiKeyController,
              decoration: const InputDecoration(
                labelText: 'API Key',
                helperText: 'Boş bırakılırsa mevcut key değişmez',
              ),
              obscureText: true,
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Kaydet')),
        ],
      ),
    );

    if (result != true) return;
    if (nameController.text.trim().isEmpty) return;
    try {
      await _smmService.updateProvider(
        id: provider.id,
        name: nameController.text.trim(),
        apiUrl: apiUrlController.text.trim(),
        apiKey: apiKeyController.text.trim().isEmpty ? null : apiKeyController.text.trim(),
      );
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Güncellenemedi: $e')));
      }
    }
  }

  Widget _buildProvidersTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          FilledButton.icon(
            onPressed: _showAddProviderDialog,
            icon: const Icon(Icons.add),
            label: const Text('Sağlayıcı Ekle'),
          ),
          const SizedBox(height: 16),
          if (_providers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Text('Henüz sağlayıcı eklenmemiş.'),
            ),
          ..._providers.map((p) => Card(
                child: ListTile(
                  leading: Icon(
                    p.isActive ? Icons.check_circle : Icons.cancel,
                    color: p.isActive ? Colors.green : Colors.red,
                  ),
                  title: Text(p.name),
                  subtitle: Text('${p.ownerType == 'admin' ? 'Admin' : 'Satıcı'} • ${p.apiUrl}'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        tooltip: 'Düzenle',
                        onPressed: () => _showEditProviderDialog(p),
                      ),
                      Switch(
                        value: p.isActive,
                        onChanged: (v) async {
                          await _smmService.updateProvider(id: p.id, isActive: v);
                          await _loadData();
                        },
                      ),
                    ],
                  ),
                ),
              )),
        ],
      ),
    );
  }

  Widget _buildPermissionsTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: _shops.length,
        itemBuilder: (context, index) {
          final shop = _shops[index];
          final canUse = shop['can_use_own_smm_api'] as bool? ?? false;
          final digitalRate = (shop['digital_commission_rate'] as num?)?.toDouble();
          return Card(
            child: Column(
              children: [
                SwitchListTile(
                  title: Text(shop['name'] as String? ?? 'Mağaza'),
                  subtitle: const Text('Kendi SMM API panelini ekleme yetkisi'),
                  value: canUse,
                  onChanged: (v) => _toggleShopPermission(shop['id'] as String, v),
                ),
                ListTile(
                  leading: const Icon(Icons.percent),
                  title: Text('Dijital Komisyon Oranı: ${digitalRate != null ? '%${digitalRate.toStringAsFixed(1)}' : 'Varsayılan (%10)'}'),
                  trailing: TextButton(
                    onPressed: () => _showDigitalCommissionDialog(shop),
                    child: const Text('Düzenle'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
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
      await _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Güncellenemedi: $e')));
      }
    }
  }

  Widget _buildAllOrdersTab() {
    return RefreshIndicator(
      onRefresh: _loadData,
      child: _allOrders.isEmpty
          ? ListView(
              children: const [
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('Henüz dijital sipariş yok')),
                ),
              ],
            )
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: _allOrders.length,
              itemBuilder: (context, index) {
                final order = _allOrders[index];
                return Card(
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
                        const SizedBox(height: 4),
                        Text(order.targetUrl, style: TextStyle(color: Colors.grey.shade600, fontSize: 13)),
                        Text(
                          'Sipariş ID: ${order.externalOrderId ?? '-'} • Miktar: ${order.quantity} • Tutar: ₺${order.totalPrice.toStringAsFixed(2)}',
                          style: const TextStyle(fontSize: 12),
                        ),
                        if (order.startCount != null || order.remains != null)
                          Text(
                            [
                              if (order.startCount != null) 'Başlangıç: ${order.startCount}',
                              if (order.remains != null) 'Kalan: ${order.remains}',
                            ].join(' • '),
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                        if (order.sellerCredited && order.netSellerAmount != null)
                          Text(
                            'Satıcıya ödenen: ₺${order.netSellerAmount!.toStringAsFixed(2)}',
                            style: TextStyle(fontSize: 12, color: Colors.green.shade700),
                          ),
                        Text(
                          DateFormat('dd.MM.yyyy HH:mm').format(order.createdAt.toLocal()),
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}
