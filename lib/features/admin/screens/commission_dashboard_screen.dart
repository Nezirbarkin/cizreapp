import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/widgets/commission_info_widget.dart';
import '../services/commission_service.dart';

/// Admin Komisyon Dashboard Ekranı
class CommissionDashboardScreen extends StatefulWidget {
  const CommissionDashboardScreen({super.key});

  @override
  State<CommissionDashboardScreen> createState() => _CommissionDashboardScreenState();
}

class _CommissionDashboardScreenState extends State<CommissionDashboardScreen> {
  final CommissionService _commissionService = CommissionService(Supabase.instance.client);
  
  bool _isLoading = true;
  AdminCommissionReport? _report;
  List<Map<String, dynamic>> _sellerList = [];
  String _selectedPeriod = '30';
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      final report = await _commissionService.getAdminCommissionReport(
        startDate: _startDate,
        endDate: _endDate,
      );
      
      final sellers = await _commissionService.getSellerCommissionList(
        startDate: _startDate,
        endDate: _endDate,
      );
      
      setState(() {
        _report = report;
        _sellerList = sellers;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Veriler yüklenemedi: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Komisyon Raporları'),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const CommissionSettingsScreen(),
                ),
              ).then((_) => _loadData());
            },
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildPeriodSelector(),
                    const SizedBox(height: 16),
                    if (_report != null) ...[
                      _buildTotalRevenueCard(),
                      const SizedBox(height: 16),
                      _buildCommissionBreakdown(),
                      const SizedBox(height: 24),
                      _buildSellerList(),
                    ],
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildPeriodSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Tarih Aralığı', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                _PeriodChip(
                  label: 'Son 7 Gün',
                  value: '7',
                  selectedValue: _selectedPeriod,
                  onTap: () => _selectPeriod('7'),
                ),
                _PeriodChip(
                  label: 'Son 30 Gün',
                  value: '30',
                  selectedValue: _selectedPeriod,
                  onTap: () => _selectPeriod('30'),
                ),
                _PeriodChip(
                  label: 'Bu Ay',
                  value: 'month',
                  selectedValue: _selectedPeriod,
                  onTap: () => _selectPeriod('month'),
                ),
                _PeriodChip(
                  label: 'Bu Yıl',
                  value: 'year',
                  selectedValue: _selectedPeriod,
                  onTap: () => _selectPeriod('year'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _selectPeriod(String period) {
    setState(() {
      _selectedPeriod = period;
      final now = DateTime.now();
      
      switch (period) {
        case '7':
          _startDate = now.subtract(const Duration(days: 7));
          _endDate = now;
          break;
        case '30':
          _startDate = now.subtract(const Duration(days: 30));
          _endDate = now;
          break;
        case 'month':
          _startDate = DateTime(now.year, now.month, 1);
          _endDate = DateTime(now.year, now.month + 1, 0, 23, 59, 59);
          break;
        case 'year':
          _startDate = DateTime(now.year, 1, 1);
          _endDate = DateTime(now.year, 12, 31, 23, 59, 59);
          break;
      }
    });
    _loadData();
  }

  Widget _buildTotalRevenueCard() {
    final total = _report!.totalNetAdmin;
    
    return Card(
      elevation: 3,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              Theme.of(context).colorScheme.primary.withValues(alpha: 0.05),
            ],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.account_balance_wallet,
                  color: Theme.of(context).colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                const Text(
                  'Toplam Admin Kazancı',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              '₺${total.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 36,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommissionBreakdown() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Komisyon Detayları',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _CommissionDetailItem(
                    label: 'Toplam',
                    amount: _report!.totalCommission,
                    color: Colors.blue,
                  ),
                ),
                Expanded(
                  child: _CommissionDetailItem(
                    label: 'Tahsil Edilen',
                    amount: _report!.collectedCommission,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _CommissionDetailItem(
                    label: 'Borç Bekleyen',
                    amount: _report!.debtCommission,
                    color: Colors.orange,
                  ),
                ),
                Expanded(
                  child: _CommissionDetailItem(
                    label: 'Affedilen',
                    amount: _report!.waivedCommission,
                    color: Colors.grey,
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _CommissionDetailItem(
              label: 'Teslimat Ücreti Kazancı',
              amount: _report!.totalDeliveryFee,
              color: Colors.purple,
              fullWidth: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSellerList() {
    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Satıcı Bazlı Özet',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Text('${_sellerList.length} satıcı'),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_sellerList.isEmpty)
            const Padding(
              padding: EdgeInsets.all(32),
              child: Center(
                child: Text('Veri bulunamadı'),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _sellerList.length,
              separatorBuilder: (context, index) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final seller = _sellerList[index];
                return _SellerListTile(seller: seller);
              },
            ),
        ],
      ),
    );
  }
}

class _CommissionDetailItem extends StatelessWidget {
  final String label;
  final double amount;
  final Color color;
  final bool fullWidth;

  const _CommissionDetailItem({
    required this.label,
    required this.amount,
    required this.color,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '₺${amount.toStringAsFixed(2)}',
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: fullWidth ? 18 : 16,
            ),
          ),
        ],
      ),
    );
  }
}

class _SellerListTile extends StatelessWidget {
  final Map<String, dynamic> seller;

  const _SellerListTile({required this.seller});

  @override
  Widget build(BuildContext context) {
    final debtAmount = (seller['debt_commission'] as num?)?.toDouble() ?? 0;
    final hasDebt = debtAmount > 0;
    
    return ListTile(
      title: Text(seller['shop_name'] ?? 'Bilinmeyen Dükkan'),
      subtitle: Text('${seller['total_orders']} sipariş'),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            '₺${((seller['total_commission'] as num?)?.toDouble() ?? 0).toStringAsFixed(2)}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          if (hasDebt)
            Text(
              '⚠️ ₺${debtAmount.toStringAsFixed(2)} borç',
              style: const TextStyle(
                fontSize: 12,
                color: Colors.orange,
              ),
            ),
        ],
      ),
      onTap: () {
        // Satıcı detay sayfasına git
      },
    );
  }
}

class _PeriodChip extends StatelessWidget {
  final String label;
  final String value;
  final String selectedValue;
  final VoidCallback onTap;

  const _PeriodChip({
    required this.label,
    required this.value,
    required this.selectedValue,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isSelected = value == selectedValue;
    
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) => onTap(),
      selectedColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
      checkmarkColor: Theme.of(context).colorScheme.primary,
    );
  }
}

/// Komisyon Ayarları Ekranı
class CommissionSettingsScreen extends StatefulWidget {
  const CommissionSettingsScreen({super.key});

  @override
  State<CommissionSettingsScreen> createState() => _CommissionSettingsScreenState();
}

class _CommissionSettingsScreenState extends State<CommissionSettingsScreen> {
  final CommissionService _commissionService = CommissionService(Supabase.instance.client);
  
  final _commissionRateController = TextEditingController();
  final _deliveryFeeController = TextEditingController();
  
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    
    try {
      final rate = await _commissionService.getAdminCommissionRate();
      final fee = await _commissionService.getDefaultDeliveryFee();
      
      setState(() {
        _commissionRateController.text = rate.toStringAsFixed(0);
        _deliveryFeeController.text = fee.toStringAsFixed(0);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    setState(() => _isSaving = true);
    
    try {
      final newRate = double.tryParse(_commissionRateController.text) ?? 10.0;
      final newFee = double.tryParse(_deliveryFeeController.text) ?? 30.0;
      
      await _commissionService.updateAdminCommissionRate(newRate);
      await _commissionService.updateDefaultDeliveryFee(newFee);
      
      setState(() {
        _isSaving = false;
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ayarlar kaydedildi')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      setState(() => _isSaving = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kaydetme başarısız: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _commissionRateController.dispose();
    _deliveryFeeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Komisyon Ayarları'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSettingCard(
                    title: 'Admin Komisyon Oranı',
                    description: 'Bu oran, kuryesi olmayan satıcılardan online ödemelerde ve kuryesi olanlardan online ödemelerde kesilir. Kapıda ödemelerde borç olarak işaretlenir.',
                    controller: _commissionRateController,
                    suffix: '%',
                    icon: Icons.percent,
                    min: 0,
                    max: 50,
                  ),
                  const SizedBox(height: 16),
                  _buildSettingCard(
                    title: 'Varsayılan Teslimat Ücreti',
                    description: 'Bu ücret kuryesi olmayan satıcılardan kesilir. Kuryesi olan satıcılar kendi teslimat ücretini belirler.',
                    controller: _deliveryFeeController,
                    suffix: '₺',
                    icon: Icons.delivery_dining,
                    min: 0,
                    max: 200,
                  ),
                  const SizedBox(height: 16),
                  _buildCommissionTable(),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _saveSettings,
                      child: _isSaving
                          ? const CircularProgressIndicator()
                          : const Text('Kaydet'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildSettingCard({
    required String title,
    required String description,
    required TextEditingController controller,
    required String suffix,
    required IconData icon,
    required double min,
    required double max,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              description,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                suffixText: suffix,
                border: const OutlineInputBorder(),
              ),
            ),
            Slider(
              value: double.tryParse(controller.text) ?? 0,
              min: min,
              max: max,
              divisions: (max - min).toInt(),
              label: '${controller.text}$suffix',
              onChanged: (value) {
                controller.text = value.round().toString();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCommissionTable() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Komisyon Mantığı',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const _CommissionRuleRow(
              sellerType: 'Kuryesi Yok',
              paymentMethod: 'Online',
              commission: '✅ Kes',
              deliveryFee: '✅ Kes',
            ),
            const Divider(),
            const _CommissionRuleRow(
              sellerType: 'Kuryesi Yok',
              paymentMethod: 'Kapıda',
              commission: '✅ Kes',
              deliveryFee: '✅ Kes',
            ),
            const Divider(),
            const _CommissionRuleRow(
              sellerType: 'Kuryesi Var',
              paymentMethod: 'Online',
              commission: '✅ Kes',
              deliveryFee: '❌ Kes',
            ),
            const Divider(),
            const _CommissionRuleRow(
              sellerType: 'Kuryesi Var',
              paymentMethod: 'Kapıda',
              commission: '⚠️ Borç',
              deliveryFee: '❌ Kes',
            ),
          ],
        ),
      ),
    );
  }
}

class _CommissionRuleRow extends StatelessWidget {
  final String sellerType;
  final String paymentMethod;
  final String commission;
  final String deliveryFee;

  const _CommissionRuleRow({
    required this.sellerType,
    required this.paymentMethod,
    required this.commission,
    required this.deliveryFee,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(flex: 2, child: Text(sellerType)),
          Expanded(child: Text(paymentMethod)),
          Expanded(child: Text(commission)),
          Expanded(child: Text(deliveryFee)),
        ],
      ),
    );
  }
}
