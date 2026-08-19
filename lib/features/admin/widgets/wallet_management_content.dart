import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/balance_service.dart';
import 'bank_accounts_tab_widget.dart';
import 'balance_load_tab_widget.dart';
import 'cancellation_requests_tab_widget.dart';
import 'transfer_confirmations_tab_widget.dart';
import 'wallet_notification_widgets.dart';
import 'wallet_settings_tab_widget.dart';
import 'users_with_balance_tab_widget.dart';

class WalletManagementContent extends StatefulWidget {
  const WalletManagementContent({super.key});

  @override
  State<WalletManagementContent> createState() =>
      _WalletManagementContentState();
}

class _WalletManagementContentState extends State<WalletManagementContent> {
  @override
  Widget build(BuildContext context) => _buildWalletManagementContent();

  // ========== CÜZDAN YÖNETİMİ İÇERİĞİ ==========
  // AppBar sağ üst köşede toplam bekleyen işlem bildirim rozeti gösterilir.
  // (havale onayları + iptal talepleri + destek talepleri)
  Widget _buildWalletManagementContent() {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cüzdan Yönetimi'),
        backgroundColor: Colors.white,
        actions: [
          // 2026-07-09: Admin anabaşlık rozeti — bekleyen işlem sayısı
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: WalletNotificationBell(),
          ),
        ],
      ),
      body: DefaultTabController(
        length: 7,
        child: Column(
          children: [
            TabBar(
              isScrollable: true,
              tabs: [
                const Tab(text: 'Bakiye Yükle'),
                Tab(child: TransferConfirmationsTabLabel()),
                const Tab(text: 'İşlem Geçmişi'),
                const Tab(text: 'Bakiyeli Kullanıcılar'),
                const Tab(text: 'Banka Hesapları'),
                const Tab(text: 'Bakiye Ayarları'),
                Tab(child: CancellationRequestsTabLabel()),
              ],
              labelColor: Colors.blue,
              unselectedLabelColor: Colors.grey,
              indicatorColor: Colors.blue,
            ),
            Expanded(
              child: TabBarView(
                children: [
                  const BalanceLoadTabWidget(),
                  const TransferConfirmationsTabWidget(),
                  _buildTransactionHistoryTab(),
                  const UsersWithBalanceTabWidget(),
                  BankAccountsTabWidget(),
                  const WalletSettingsTabWidget(),
                  const CancellationRequestsTabWidget(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<List<Map<String, dynamic>>> _searchUsers(String query) async {
    try {
      final supabase = Supabase.instance.client;
      // 20260803000006 sonrasında profiles üzerinde authenticated
      // SELECT policy'si yok; phone/email sütunları revoke edildi.
      // SECURITY DEFINER admin_search_users RPC üzerinden arama yapılır.
      final response = await supabase.rpc<List<dynamic>>(
        'admin_search_users',
        params: {'p_query': query, 'p_limit': 10},
      );

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Kullanıcı arama hatası: $e');
      return [];
    }
  }

  // İşlem geçmişi kartını oluşturur.
  // Her kart tıklanabilir; tıklanınca kişi detayı dialogu açılır.
  Widget _buildTransactionCard(Map<String, dynamic> tx) {
    final netAmount = (tx['net_amount'] as num?) ?? 0;
    final isPositive = netAmount > 0;
    final userProfile = tx['user_profile'] as Map<String, dynamic>?;
    final userName =
        userProfile?['full_name'] as String? ??
        userProfile?['username'] as String? ??
        'Bilinmeyen';

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showTransactionDetailDialog(context, tx),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: isPositive
                ? Colors.green.shade100
                : Colors.red.shade100,
            child: Icon(
              isPositive ? Icons.add : Icons.remove,
              color: isPositive ? Colors.green : Colors.red,
            ),
          ),
          title: Text(
            '${isPositive ? '+' : ''}₺${netAmount.toStringAsFixed(2)}',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: isPositive ? Colors.green : Colors.red,
            ),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                userName,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              Text(
                '${tx['description'] ?? tx['type']} • ${tx['created_at']}',
                style: const TextStyle(fontSize: 11),
              ),
            ],
          ),
          trailing: const Icon(Icons.chevron_right, color: Colors.grey),
        ),
      ),
    );
  }

  // İşlem detay dialogu — eski/yeni bakiye, kişi profili bilgilerini gösterir.
  void _showTransactionDetailDialog(
    BuildContext context,
    Map<String, dynamic> tx,
  ) {
    final netAmount = (tx['net_amount'] as num?) ?? 0;
    final isPositive = netAmount > 0;
    final userProfile = tx['user_profile'] as Map<String, dynamic>?;
    final userName =
        userProfile?['full_name'] as String? ??
        userProfile?['username'] as String? ??
        'Bilinmeyen';
    final userPhone = userProfile?['phone'] as String? ?? '-';
    final userAvatar = userProfile?['avatar_url'] as String?;

    // balance_before / balance_after SQL migration sonrası mevcut olabilir.
    final balanceBefore = tx['balance_before'] as num?;
    final balanceAfter = tx['balance_after'] as num?;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              isPositive ? Icons.add_circle : Icons.remove_circle,
              color: isPositive ? Colors.green : Colors.red,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'İşlem Detayı',
                style: TextStyle(
                  fontSize: 16,
                  color: isPositive ? Colors.green : Colors.red,
                ),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Kişi profili
              Center(
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 30,
                      backgroundColor: Colors.blue.shade100,
                      backgroundImage: userAvatar != null
                          ? NetworkImage(userAvatar)
                          : null,
                      child: userAvatar == null
                          ? Text(
                              userName.isNotEmpty
                                  ? userName[0].toUpperCase()
                                  : '?',
                              style: TextStyle(
                                fontSize: 24,
                                color: Colors.blue.shade700,
                              ),
                            )
                          : null,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      userName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      userPhone,
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 8),

              // İşlem tutarı
              _detailRow(
                'İşlem Tutarı',
                '${isPositive ? '+' : ''}₺${netAmount.toStringAsFixed(2)}',
                valueColor: isPositive ? Colors.green : Colors.red,
              ),
              const SizedBox(height: 8),

              // Eski bakiye (varsa)
              if (balanceBefore != null)
                _detailRow(
                  'Eski Bakiye',
                  '₺${balanceBefore.toStringAsFixed(2)}',
                ),
              if (balanceBefore != null) const SizedBox(height: 8),

              // Yeni bakiye (varsa)
              if (balanceAfter != null)
                _detailRow(
                  'Yeni Bakiye',
                  '₺${balanceAfter.toStringAsFixed(2)}',
                ),
              if (balanceAfter != null) const SizedBox(height: 8),

              // Açıklama
              if (tx['description'] != null || tx['type'] != null) ...[
                const SizedBox(height: 4),
                _detailRow('Açıklama', tx['description'] ?? tx['type']),
              ],
              const SizedBox(height: 8),

              // Tarih
              _detailRow('Tarih', tx['created_at'] ?? '-'),
              const SizedBox(height: 8),

              // İşlem türü
              if (tx['type'] != null) _detailRow('Tür', tx['type']),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
        ],
      ),
    );
  }

  // Dialog satırı: etiket + değer
  Widget _detailRow(String label, String value, {Color? valueColor}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: valueColor,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTransactionHistoryTab() {
    final balanceService = BalanceService();

    return FutureBuilder(
      future: balanceService.getAllTransactions(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (!snapshot.hasData || (snapshot.data as List).isEmpty) {
          return const Center(child: Text('Henüz işlem bulunmuyor'));
        }

        final transactions = snapshot.data as List;
        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: transactions.length,
          itemBuilder: (context, index) {
            final tx = transactions[index];
            return _buildTransactionCard(tx);
          },
        );
      },
    );
  }

  bool _isValidImageUrl(dynamic url) {
    if (url == null) return false;
    final urlStr = url.toString().trim();
    if (urlStr.isEmpty) return false;
    return urlStr.startsWith('http://') || urlStr.startsWith('https://');
  }
}
