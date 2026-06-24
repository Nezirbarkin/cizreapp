import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/balance_model.dart';
import '../../../core/models/balance_transaction_model.dart';
import '../../../core/services/balance_service.dart';
import 'topup_screen.dart';
import '../../../features/wallet/screens/transaction_history_screen.dart';

/// Ana Bakiye Ekranı
class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen> {
  final BalanceService _balanceService = BalanceService();
  
  UserBalance? _balance;
  bool _isLoading = true;
  String? _error;
  List<BalanceTransaction> _recentTransactions = [];
  bool _isLoadingTransactions = false;

  @override
  void initState() {
    super.initState();
    _loadBalance();
    _loadRecentTransactions();
  }

  Future<void> _loadRecentTransactions() async {
    setState(() => _isLoadingTransactions = true);
    try {
      final result = await _balanceService.getTransactionHistory(page: 1, limit: 5);
      setState(() {
        _recentTransactions = result.transactions;
        _isLoadingTransactions = false;
      });
    } catch (e) {
      setState(() => _isLoadingTransactions = false);
    }
  }

  Future<void> _loadBalance() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final balance = await _balanceService.getBalance();
      setState(() {
        _balance = balance;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  void _navigateToTopup() async {
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const TopupScreen()),
    );
    if (result == true) {
      _loadBalance();
    }
  }

  void _navigateToHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const TransactionHistoryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Cüzdan'),
        actions: [
          IconButton(
            icon: const Icon(Icons.history),
            onPressed: _navigateToHistory,
            tooltip: 'İşlem Geçmişi',
          ),
        ],
      ),
      body: _buildBody(theme),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 16),
            Text('Hata: $_error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadBalance,
              child: const Text('Tekrar Dene'),
            ),
          ],
        ),
      );
    }

    final balance = _balance;
    final availableBalance = balance?.availableBalance ?? 0;

    return RefreshIndicator(
      onRefresh: _loadBalance,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Bakiye Kartı
            _buildBalanceCard(theme, availableBalance),
            const SizedBox(height: 16),

            // İstatistikler
            if (balance != null) ...[
              _buildStatsRow(theme, balance),
              const SizedBox(height: 16),
            ],

            // Yükleme Butonu
            ElevatedButton.icon(
              onPressed: _navigateToTopup,
              icon: const Icon(Icons.add),
              label: const Text('Bakiye Yükle'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 24),

            // Son İşlemler
            _buildRecentTransactions(theme),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceCard(ThemeData theme, double balance) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            theme.colorScheme.primary,
            theme.colorScheme.primary.withValues(alpha: 0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.primary.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Kullanılabilir Bakiye',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '₺${balance.toStringAsFixed(2)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (_balance != null && _balance!.lockedBalance > 0) ...[
            const SizedBox(height: 8),
            Text(
              'Kilitli: ₺${_balance!.lockedBalance.toStringAsFixed(2)}',
              style: const TextStyle(
                color: Colors.white60,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatsRow(ThemeData theme, UserBalance balance) {
    return Row(
      children: [
        Expanded(
          child: _buildStatCard(
            theme,
            icon: Icons.arrow_downward,
            iconColor: Colors.green,
            label: 'Toplam Yüklenen',
            value: '₺${balance.totalEarned.toStringAsFixed(2)}',
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildStatCard(
            theme,
            icon: Icons.arrow_upward,
            iconColor: Colors.red,
            label: 'Toplam Harcama',
            value: '₺${balance.totalSpent.toStringAsFixed(2)}',
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(
    ThemeData theme, {
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
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
                  value,
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentTransactions(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Son İşlemler',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            TextButton(
              onPressed: _navigateToHistory,
              child: const Text('Tümünü Gör'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (_isLoadingTransactions)
          Container(
            padding: const EdgeInsets.all(24),
            child: const Center(child: CircularProgressIndicator()),
          )
        else if (_recentTransactions.isEmpty)
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Column(
              children: [
                Icon(Icons.receipt_long, size: 48, color: Colors.grey.shade400),
                const SizedBox(height: 8),
                Text(
                  'Henüz işlem yok',
                  style: TextStyle(color: Colors.grey.shade600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Bakiye yükleyerek başlayın',
                  style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        )
      else
        Container(
          decoration: BoxDecoration(
            color: Colors.grey.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: Column(
            children: _recentTransactions.map((tx) {
              final isPositive = tx.type.toString().contains('topup') || tx.type.toString().contains('adjustment');
              return ListTile(
                dense: true,
                leading: CircleAvatar(
                  radius: 16,
                  backgroundColor: isPositive ? Colors.green.shade100 : Colors.red.shade100,
                  child: Icon(isPositive ? Icons.add : Icons.remove, size: 16, color: isPositive ? Colors.green : Colors.red),
                ),
                title: Text(
                  tx.description ?? (isPositive ? 'Bakiye Yükleme' : 'Ödeme'),
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  tx.createdAt.toString().substring(0, 10),
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                trailing: Text(
                  '${isPositive ? '+' : '-'}₺${tx.amount.toStringAsFixed(2)}',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: isPositive ? Colors.green : Colors.red,
                    fontSize: 13,
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}
