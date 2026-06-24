import 'package:flutter/material.dart';
import '../../../core/models/seller_withdrawal_model.dart';
import '../../../core/services/withdrawal_service.dart';

/// Admin: Çekim Talepleri Yönetim Ekranı
class AdminWithdrawalScreen extends StatefulWidget {
  const AdminWithdrawalScreen({super.key});

  @override
  State<AdminWithdrawalScreen> createState() => _AdminWithdrawalScreenState();
}

class _AdminWithdrawalScreenState extends State<AdminWithdrawalScreen> with SingleTickerProviderStateMixin {
  final WithdrawalService _withdrawalService = WithdrawalService();
  late TabController _tabController;
  
  List<WithdrawalWithSeller> _pendingWithdrawals = [];
  List<WithdrawalWithSeller> _processedWithdrawals = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadWithdrawals();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadWithdrawals() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final pending = await _withdrawalService.getAllWithdrawals(status: 'pending');
      final processed = await _withdrawalService.getAllWithdrawals(status: 'processing,completed,failed,cancelled');

      setState(() {
        _pendingWithdrawals = pending;
        _processedWithdrawals = processed;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _processWithdrawal(WithdrawalWithSeller item, String action) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(action == 'approve' ? 'Çekimi Onayla' : 'Çekimi Reddet'),
        content: Text(
          action == 'approve'
              ? 'Bu çekim talebini onaylamak istediğinize emin misiniz?\n\nTutar: ₺${item.withdrawal.amount.toStringAsFixed(2)}\nNet: ₺${item.withdrawal.netAmount.toStringAsFixed(2)}'
              : 'Bu çekim talebini reddetmek istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: action == 'approve' ? Colors.green : Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(action == 'approve' ? 'Onayla' : 'Reddet'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _withdrawalService.processWithdrawal(
        withdrawalId: item.withdrawal.id,
        action: action == 'approve' ? 'approve' : 'reject',
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(action == 'approve' ? 'Çekim onaylandı' : 'Çekim reddedildi'),
          backgroundColor: action == 'approve' ? Colors.green : Colors.orange,
        ),
      );

      _loadWithdrawals();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Çekim Talepleri'),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('Bekleyen'),
                  if (_pendingWithdrawals.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.orange,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${_pendingWithdrawals.length}',
                        style: const TextStyle(color: Colors.white, fontSize: 12),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const Tab(text: 'İşlenenler'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildWithdrawalsList(_pendingWithdrawals, isPending: true),
                _buildWithdrawalsList(_processedWithdrawals, isPending: false),
              ],
            ),
    );
  }

  Widget _buildWithdrawalsList(List<WithdrawalWithSeller> withdrawals, {required bool isPending}) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 16),
            Text('Hata: $_error'),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadWithdrawals,
              child: const Text('Tekrar Dene'),
            ),
          ],
        ),
      );
    }

    if (withdrawals.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              isPending ? 'Bekleyen çekim talebi yok' : 'Henüz işlenen çekim yok',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 16),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadWithdrawals,
      child: ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: withdrawals.length,
        itemBuilder: (context, index) {
          final item = withdrawals[index];
          return _buildWithdrawalCard(item, isPending: isPending);
        },
      ),
    );
  }

  Widget _buildWithdrawalCard(WithdrawalWithSeller item, {required bool isPending}) {
    final withdrawal = item.withdrawal;
    final statusColor = _getStatusColor(withdrawal.status);

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Üst satır: Satıcı + Durum
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.sellerName ?? 'Satıcı',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (item.sellerPhone != null)
                        Text(
                          item.sellerPhone!,
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
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor),
                  ),
                  child: Text(
                    withdrawal.status.label,
                    style: TextStyle(
                      color: statusColor,
                      fontWeight: FontWeight.w600,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
            const Divider(height: 24),

            // Tutar bilgisi
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildAmountInfo('Tutar', withdrawal.amount),
                _buildAmountInfo('Komisyon', withdrawal.fee, isNegative: true),
                _buildAmountInfo('Net', withdrawal.netAmount, isHighlighted: true),
              ],
            ),
            const SizedBox(height: 12),

            // Banka bilgisi
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.account_balance, size: 20, color: Colors.grey),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          withdrawal.bankName ?? '',
                          style: const TextStyle(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          withdrawal.maskedIban,
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Tarih
            Text(
              'Talep: ${withdrawal.formattedDate}',
              style: TextStyle(color: Colors.grey.shade500, fontSize: 12),
            ),

            // Admin işlemleri
            if (isPending) ...[
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _processWithdrawal(item, 'reject'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                      ),
                      child: const Text('Reddet'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => _processWithdrawal(item, 'approve'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('Onayla'),
                    ),
                  ),
                ],
              ),
            ],

            // Admin notları
            if (withdrawal.adminNotes != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.note, size: 16, color: Colors.amber.shade700),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        withdrawal.adminNotes!,
                        style: TextStyle(
                          color: Colors.amber.shade900,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAmountInfo(String label, double value, {bool isNegative = false, bool isHighlighted = false}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            color: Colors.grey.shade600,
            fontSize: 11,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '${isNegative ? '-' : ''}₺${value.toStringAsFixed(2)}',
          style: TextStyle(
            fontWeight: isHighlighted ? FontWeight.bold : FontWeight.w500,
            fontSize: isHighlighted ? 16 : 14,
            color: isHighlighted ? Colors.green : (isNegative ? Colors.red : null),
          ),
        ),
      ],
    );
  }

  Color _getStatusColor(WithdrawalStatus status) {
    switch (status) {
      case WithdrawalStatus.pending:
        return Colors.orange;
      case WithdrawalStatus.processing:
        return Colors.blue;
      case WithdrawalStatus.completed:
        return Colors.green;
      case WithdrawalStatus.failed:
        return Colors.red;
      case WithdrawalStatus.cancelled:
        return Colors.grey;
    }
  }
}
