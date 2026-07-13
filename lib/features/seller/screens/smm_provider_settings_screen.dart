import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/smm_provider_model.dart';
import '../../../core/services/smm_service.dart';
import '../../wallet/screens/wallet_screen.dart';

class SmmProviderSettingsScreen extends StatefulWidget {
  const SmmProviderSettingsScreen({super.key});

  @override
  State<SmmProviderSettingsScreen> createState() => _SmmProviderSettingsScreenState();
}

class _SmmProviderSettingsScreenState extends State<SmmProviderSettingsScreen> {
  final _smmService = SmmService();
  SupabaseClient get _supabase => Supabase.instance.client;

  bool _isLoading = true;
  bool _canUseOwnApi = false;
  String? _shopId;
  List<SmmProvider> _providers = [];
  double _digitalEarnings = 0.0; // Dijital ürün (SMM) kazancı - cüzdan bakiyesinden

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) throw Exception('Kullanıcı oturumu bulunamadı');

      final shop = await _supabase
          .from('shops')
          .select('id, can_use_own_smm_api')
          .eq('owner_id', userId)
          .maybeSingle();

      if (shop == null) throw Exception('Mağaza bulunamadı');

      _shopId = shop['id'] as String;
      _canUseOwnApi = shop['can_use_own_smm_api'] as bool? ?? false;

      final providers = await _smmService.getProviders();
      _providers = providers.where((p) => p.ownerType == 'seller' && p.ownerId == _shopId).toList();

      // Dijital ürün (SMM) kazancı - fiziksel siparişlerden AYRI olarak
      // doğrudan cüzdan bakiyesine (user_balances) eklenir, shops tablosundaki
      // admin_credit/cash_payment_revenue sütunlarına dahil DEĞİLDİR.
      try {
        final digitalEarningRows = await _supabase
            .from('balance_transactions')
            .select('amount')
            .eq('user_id', userId)
            .eq('reference_type', 'digital_order')
            .eq('type', 'commission');
        _digitalEarnings = (digitalEarningRows as List)
            .fold<double>(0, (sum, row) => sum + ((row['amount'] as num?)?.toDouble() ?? 0));
      } catch (e) {
        _digitalEarnings = 0;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Yüklenirken hata: $e')));
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _showAddProviderDialog() async {
    final nameController = TextEditingController();
    final apiUrlController = TextEditingController(text: 'https://smmget.com/api/v2');
    final apiKeyController = TextEditingController();

    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('SMM Sağlayıcısı Ekle'),
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

    if (result == true && _shopId != null) {
      if (nameController.text.trim().isEmpty || apiKeyController.text.trim().isEmpty) return;
      try {
        await _smmService.createProvider(
          name: nameController.text.trim(),
          apiUrl: apiUrlController.text.trim(),
          apiKey: apiKeyController.text.trim(),
          ownerType: 'seller',
          ownerId: _shopId!,
        );
        await _loadData();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Eklenemedi: $e')));
        }
      }
    }
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

  Widget _buildDigitalEarningsCard() {
    return Card(
      color: Colors.purple.shade50,
      margin: const EdgeInsets.only(bottom: 16),
      child: ListTile(
        leading: Icon(Icons.smart_toy_outlined, color: Colors.purple.shade700),
        title: const Text('Dijital Ürün Kazancı'),
        subtitle: const Text('Cüzdanınıza eklendi, Cüzdan ekranından çekebilirsiniz'),
        trailing: Text(
          '₺${_digitalEarnings.toStringAsFixed(2)}',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 16,
            color: Colors.purple.shade700,
          ),
        ),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const WalletScreen()),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('SMM Ayarları')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : !_canUseOwnApi
              ? RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.all(24),
                    children: [
                      _buildDigitalEarningsCard(),
                      Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.lock_outline, size: 48, color: Colors.grey.shade400),
                              const SizedBox(height: 16),
                              const Text(
                                'Kendi SMM API panelinizi ekleyebilmek için yönetici onayı gereklidir.',
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadData,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      _buildDigitalEarningsCard(),
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
                              subtitle: Text(p.apiUrl),
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
                ),
    );
  }
}
