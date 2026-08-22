import 'package:flutter/material.dart';
import '../../../core/models/balance_transaction_model.dart';
import '../../../core/services/balance_service.dart';
import '../widgets/transaction_detail_sheet.dart';

/// İşlem Geçmişi Ekranı - Modern Tasarım
class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  final BalanceService _balanceService = BalanceService();
  final ScrollController _scrollController = ScrollController();

  List<BalanceTransaction> _transactions = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _loadMoreFailed = false;
  bool _hasMore = true;
  int _page = 1;
  String? _error;
  String? _filterType;

  @override
  void initState() {
    super.initState();
    _loadTransactions();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      _loadMore();
    }
  }

  Future<void> _loadTransactions({bool refresh = false}) async {
    if (refresh) {
      setState(() {
        _page = 1;
        _transactions = [];
        _isLoading = true;
        _hasMore = true;
        _loadMoreFailed = false;
        _error = null;
      });
    } else {
      setState(() {
        _isLoadingMore = true;
        _loadMoreFailed = false;
      });
    }

    try {
      final page = await _balanceService.getTransactionHistory(
        page: _page,
        limit: 20,
        type: _filterType,
      );

      if (!mounted) return;
      setState(() {
        if (refresh) {
          _transactions = page.transactions;
        } else {
          _transactions.addAll(page.transactions);
        }
        _hasMore = page.hasMore;
        _isLoading = false;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isLoadingMore = false;
        if (refresh || _transactions.isEmpty) {
          _error = e.toString();
        } else {
          _loadMoreFailed = true;
        }
      });
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _isLoading || _isLoadingMore || _loadMoreFailed) return;
    _page++;
    await _loadTransactions();
  }

  void _retryLoadMore() {
    _loadMore();
  }

  Future<void> _refresh() async {
    await _loadTransactions(refresh: true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        title: const Text(
          'İşlem Geçmişi',
          style: TextStyle(fontWeight: FontWeight.w600),
        ),
        centerTitle: false,
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: PopupMenuButton<String?>(
              icon: Icon(
                Icons.filter_list_rounded,
                color: Theme.of(context).colorScheme.primary,
              ),
              tooltip: 'Filtrele',
              onSelected: (value) {
                setState(() {
                  _filterType = value;
                });
                _loadTransactions(refresh: true);
              },
              itemBuilder: (context) => [
                PopupMenuItem(
                  value: null,
                  child: _buildFilterItem(null, 'Tümü', Icons.list_rounded),
                ),
                PopupMenuItem(
                  value: 'topup',
                  child: _buildFilterItem('topup', 'Yüklemeler', Icons.add_circle_rounded),
                ),
                PopupMenuItem(
                  value: 'order_payment',
                  child: _buildFilterItem('order_payment', 'Sipariş Ödemeleri', Icons.shopping_cart_rounded),
                ),
                PopupMenuItem(
                  value: 'refund',
                  child: _buildFilterItem('refund', 'İadeler', Icons.replay_rounded),
                ),
                PopupMenuItem(
                  value: 'withdrawal',
                  child: _buildFilterItem('withdrawal', 'Çekimler', Icons.account_balance_wallet_rounded),
                ),
                PopupMenuItem(
                  value: 'commission',
                  child: _buildFilterItem('commission', 'Komisyonlar', Icons.monetization_on_rounded),
                ),
                PopupMenuItem(
                  value: 'ad_reward',
                  child: _buildFilterItem('ad_reward', 'Reklam Ödülleri', Icons.play_circle_outline),
                ),
                PopupMenuItem(
                  value: 'task_reward',
                  child: _buildFilterItem('task_reward', 'Görev Ödülleri', Icons.assignment_turned_in_rounded),
                ),
                PopupMenuItem(
                  value: 'courier_payment',
                  child: _buildFilterItem('courier_payment', 'Kurye Ücretleri', Icons.local_shipping_rounded),
                ),
                PopupMenuItem(
                  value: 'campaign_reward',
                  child: _buildFilterItem('campaign_reward', 'Kampanya Ödülleri', Icons.card_giftcard_rounded),
                ),
                PopupMenuItem(
                  value: 'ilan_publish_fee',
                  child: _buildFilterItem('ilan_publish_fee', 'İlan Ücretleri', Icons.campaign_rounded),
                ),
                PopupMenuItem(
                  value: 'profile_feature_purchase',
                  child: _buildFilterItem('profile_feature_purchase', 'Profil Özellikleri', Icons.workspace_premium_rounded),
                ),
                PopupMenuItem(
                  value: 'adjustment',
                  child: _buildFilterItem('adjustment', 'Düzeltmeler', Icons.tune_rounded),
                ),
              ],
            ),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildFilterItem(String? value, String label, IconData icon) {
    final isSelected = _filterType == value;
    return Row(
      children: [
        Icon(
          icon,
          size: 20,
          color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey.shade600,
        ),
        const SizedBox(width: 12),
        Text(
          label,
          style: TextStyle(
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            color: isSelected ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
        if (isSelected) ...[
          const Spacer(),
          Icon(
            Icons.check_rounded,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
        ],
      ],
    );
  }

  Widget _buildBody() {
    if (_isLoading && _transactions.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('İşlemler yükleniyor...'),
          ],
        ),
      );
    }

    if (_error != null && _transactions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.error_outline_rounded,
                  size: 48,
                  color: Colors.red.shade400,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Bir hata oluştu',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      );
    }

    if (_transactions.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.receipt_long_rounded,
                  size: 56,
                  color: Colors.grey.shade400,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                'Henüz işlem yapılmadı',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 17,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Bakiye yükleyerek başlayın',
                style: TextStyle(
                  color: Colors.grey.shade400,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
        itemCount: _transactions.length + ((_hasMore || _loadMoreFailed) ? 1 : 0),
        itemBuilder: (context, index) {
          if (index >= _transactions.length) {
            if (_loadMoreFailed) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: Center(
                  child: TextButton.icon(
                    onPressed: _retryLoadMore,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Tekrar dene'),
                  ),
                ),
              );
            }
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final transaction = _transactions[index];
          return Padding(
            padding: EdgeInsets.only(
              bottom: index < _transactions.length - 1 ? 14 : 0,
            ),
            child: _buildTransactionCard(transaction),
          );
        },
      ),
    );
  }

  Widget _buildTransactionCard(BalanceTransaction transaction) {
    final isPositive = transaction.isPositive;
    final amountColor = isPositive ? Colors.green : Colors.red;
    final icon = transaction.type.icon;
    final hasBankInfo = transaction.bankName != null || transaction.bankAccountName != null;

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(20),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showTransactionDetailSheet(context, transaction),
          child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(18),
            child: Row(
              children: [
                // İkon
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: amountColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Icon(icon, color: amountColor, size: 26),
                ),
                const SizedBox(width: 16),

                // Bilgiler
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        transaction.type.label,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Icon(
                            Icons.access_time_rounded,
                            size: 14,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            transaction.shortDate,
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                      if (transaction.description != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          transaction.description!,
                          style: TextStyle(
                            color: Colors.grey.shade500,
                            fontSize: 12,
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
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: amountColor.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${isPositive ? '+' : '-'}₺${transaction.absoluteAmount.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: amountColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildStatusBadge(transaction.status),
                  ],
                ),
              ],
            ),
          ),

          // Banka bilgileri (varsa)
          if (hasBankInfo) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.account_balance_rounded, size: 16, color: Colors.blue.shade700),
                        const SizedBox(width: 8),
                        Text(
                          'Banka Bilgileri',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (transaction.bankName != null)
                          Expanded(
                            child: _buildBankInfoChip(
                              Icons.account_balance,
                              'Banka: ${transaction.bankName}',
                            ),
                          ),
                        if (transaction.bankAccountName != null)
                          Expanded(
                            child: _buildBankInfoChip(
                              Icons.person_outline,
                              'Hesap: ${transaction.bankAccountName}',
                            ),
                          ),
                      ],
                    ),
                    if (transaction.bankIban != null) ...[
                      const SizedBox(height: 8),
                      _buildBankInfoChip(
                        Icons.numbers,
                        'IBAN: ${_maskIban(transaction.bankIban!)}',
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
          ),
        ),
      ),
    );
  }

  Widget _buildBankInfoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.blue.shade600),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            text,
            style: TextStyle(
              fontSize: 11,
              color: Colors.blue.shade700,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }

  String _maskIban(String iban) {
    if (iban.length <= 8) return iban;
    return '${iban.substring(0, 4)}****${iban.substring(iban.length - 4)}';
  }

  Widget _buildStatusBadge(BalanceTransactionStatus status) {
    Color color;
    Color bgColor;
    String text;
    IconData icon;

    switch (status) {
      case BalanceTransactionStatus.completed:
        color = Colors.green;
        bgColor = Colors.green.shade50;
        text = 'Tamamlandı';
        icon = Icons.check_circle_outline_rounded;
        break;
      case BalanceTransactionStatus.pending:
        color = Colors.orange;
        bgColor = Colors.orange.shade50;
        text = 'Beklemede';
        icon = Icons.schedule_rounded;
        break;
      case BalanceTransactionStatus.failed:
        color = Colors.red;
        bgColor = Colors.red.shade50;
        text = 'Başarısız';
        icon = Icons.cancel_outlined;
        break;
      case BalanceTransactionStatus.cancelled:
        color = Colors.grey;
        bgColor = Colors.grey.shade100;
        text = 'İptal';
        icon = Icons.block_rounded;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            text,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

}
