import 'package:flutter/material.dart';
import '../../../core/models/balance_transaction_model.dart';
import '../../../core/services/balance_service.dart';

/// İşlem Geçmişi Ekranı
class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  final BalanceService _balanceService = BalanceService();
  
  List<BalanceTransaction> _transactions = [];
  bool _isLoading = true;
  bool _hasMore = true;
  int _page = 1;
  String? _error;
  String? _filterType;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
  }

  Future<void> _loadTransactions({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _page = 1;
        _transactions = [];
        _isLoading = true;
        _error = null;
      });
    }

    try {
      final page = await _balanceService.getTransactionHistory(
        page: _page,
        limit: 20,
        type: _filterType,
      );

      setState(() {
        if (refresh) {
          _transactions = page.transactions;
        } else {
          _transactions.addAll(page.transactions);
        }
        _hasMore = page.hasMore;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isLoading) return;
    _page++;
    await _loadTransactions();
  }

  Future<void> _refresh() async {
    await _loadTransactions(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('İşlem Geçmişi'),
        actions: [
          PopupMenuButton<String?>(
            icon: const Icon(Icons.filter_list),
            tooltip: 'Filtrele',
            onSelected: (value) {
              setState(() {
                _filterType = value;
              });
              _loadTransactions(refresh: true);
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: null,
                child: Text('Tümü'),
              ),
              const PopupMenuItem(
                value: 'topup',
                child: Text('Yüklemeler'),
              ),
              const PopupMenuItem(
                value: 'order_payment',
                child: Text('Sipariş Ödemeleri'),
              ),
              const PopupMenuItem(
                value: 'refund',
                child: Text('İadeler'),
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _transactions.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null && _transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error_outline, size: 48, color: Colors.red.shade400),
            const SizedBox(height: 16),
            Text('Hata: $_error', textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _refresh,
              child: const Text('Tekrar Dene'),
            ),
          ],
        ),
      );
    }

    if (_transactions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.receipt_long, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Henüz işlem yok',
              style: TextStyle(
                color: Colors.grey.shade600,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _transactions.length + (_hasMore ? 1 : 0),
        separatorBuilder: (context, index) => const SizedBox(height: 8),
        itemBuilder: (context, index) {
          if (index >= _transactions.length) {
            // Yükleme göstergesi
            _loadMore();
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            );
          }

          final transaction = _transactions[index];
          return _buildTransactionCard(transaction);
        },
      ),
    );
  }

  Widget _buildTransactionCard(BalanceTransaction transaction) {
    final isPositive = transaction.isPositive;
    final amountColor = isPositive ? Colors.green : Colors.red;
    final icon = _getTransactionIcon(transaction.type);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          // İkon
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: amountColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: amountColor, size: 24),
          ),
          const SizedBox(width: 12),

          // Bilgiler
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.type.label,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  transaction.shortDate,
                  style: TextStyle(
                    color: Colors.grey.shade600,
                    fontSize: 12,
                  ),
                ),
                if (transaction.description != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    transaction.description!,
                    style: TextStyle(
                      color: Colors.grey.shade500,
                      fontSize: 11,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),

          // Tutar
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${isPositive ? '+' : '-'}₺${transaction.absoluteAmount.toStringAsFixed(2)}',
                style: TextStyle(
                  color: amountColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 2),
              _buildStatusBadge(transaction.status),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatusBadge(BalanceTransactionStatus status) {
    Color color;
    String text;

    switch (status) {
      case BalanceTransactionStatus.completed:
        color = Colors.green;
        text = 'Tamamlandı';
        break;
      case BalanceTransactionStatus.pending:
        color = Colors.orange;
        text = 'Beklemede';
        break;
      case BalanceTransactionStatus.failed:
        color = Colors.red;
        text = 'Başarısız';
        break;
      case BalanceTransactionStatus.cancelled:
        color = Colors.grey;
        text = 'İptal';
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  IconData _getTransactionIcon(BalanceTransactionType type) {
    switch (type) {
      case BalanceTransactionType.topup:
        return Icons.add_circle;
      case BalanceTransactionType.orderPayment:
        return Icons.shopping_cart;
      case BalanceTransactionType.refund:
        return Icons.replay;
      case BalanceTransactionType.withdrawal:
        return Icons.account_balance_wallet;
      case BalanceTransactionType.adjustment:
        return Icons.tune;
      case BalanceTransactionType.commission:
        return Icons.monetization_on;
    }
  }
}
