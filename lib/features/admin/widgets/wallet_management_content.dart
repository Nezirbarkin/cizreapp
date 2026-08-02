import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/balance_service.dart';
import 'bank_accounts_tab_widget.dart';
import 'balance_load_tab_widget.dart';
import 'cancellation_requests_tab_widget.dart';
import 'transfer_confirmations_tab_widget.dart';
import 'wallet_notification_widgets.dart';
import 'wallet_settings_tab_widget.dart';

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
                  _buildUsersWithBalanceTab(),
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

  // ========== HAVALE ONAYLARI TAB ETİKETİ (bekleyen sayısı rozeti) ==========

  Widget _buildUsersWithBalanceTab() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _getUsersWithBalance(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline, size: 48, color: Colors.red.shade300),
                const SizedBox(height: 16),
                Text('Hata: ${snapshot.error}'),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => setState(() {}),
                  child: const Text('Tekrar Dene'),
                ),
              ],
            ),
          );
        }

        final users = snapshot.data ?? [];

        if (users.isEmpty) {
          return const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.account_balance_wallet,
                  size: 64,
                  color: Colors.grey,
                ),
                SizedBox(height: 16),
                Text(
                  'Bakiyeli kullanıcı bulunamadı',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(8),
          itemCount: users.length,
          itemBuilder: (context, index) {
            final user = users[index];
            final balance =
                (user['available_balance'] as num?)?.toDouble() ??
                (user['balance'] as num?)?.toDouble() ??
                0.0;
            final totalSpent = (user['total_spent'] as num?)?.toDouble() ?? 0.0;
            final totalEarned =
                (user['total_earned'] as num?)?.toDouble() ?? 0.0;
            final totalOrderPayments =
                (user['total_order_payments'] as num?)?.toDouble() ?? 0.0;
            final totalTopups =
                (user['total_topups'] as num?)?.toDouble() ?? 0.0;
            final orderCount = (user['order_count'] as num?)?.toInt() ?? 0;
            final topupCount = (user['topup_count'] as num?)?.toInt() ?? 0;
            final isPositive = balance > 0;

            return Card(
              margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
              elevation: 2,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Üst satır: İsim ve bakiye
                    Row(
                      children: [
                        CircleAvatar(
                          backgroundColor: isPositive
                              ? Colors.green.shade100
                              : Colors.grey.shade100,
                          child: Icon(
                            Icons.account_balance_wallet,
                            color: isPositive ? Colors.green : Colors.grey,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                user['full_name'] ??
                                    user['user_name'] ??
                                    'Bilinmeyen',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                ),
                              ),
                              Text(
                                user['phone'] ?? user['user_phone'] ?? '-',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: isPositive
                                ? Colors.green.shade100
                                : Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '₺${balance.toStringAsFixed(2)}',
                            style: TextStyle(
                              color: isPositive
                                  ? Colors.green.shade700
                                  : Colors.grey.shade700,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 16),

                    // Bakiye detayları
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildBalanceInfo(
                          'Mevcut Bakiye',
                          balance,
                          Colors.green,
                        ),
                        _buildBalanceInfo(
                          'Toplam Yükleme',
                          totalTopups > 0 ? totalTopups : totalEarned,
                          Colors.blue,
                        ),
                        _buildBalanceInfo(
                          'Toplam Harcama',
                          totalOrderPayments > 0
                              ? totalOrderPayments
                              : totalSpent,
                          Colors.orange,
                        ),
                      ],
                    ),

                    // İşlem sayıları
                    if (orderCount > 0 || topupCount > 0) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Icon(
                            Icons.receipt_long,
                            size: 14,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$topupCount yükleme',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Icon(
                            Icons.shopping_bag,
                            size: 14,
                            color: Colors.grey.shade500,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$orderCount sipariş',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<List<Map<String, dynamic>>> _getUsersWithBalance() async {
    try {
      // admin_users_with_balance view'ından bakiyeli kullanıcıları getir
      // (bakiye > 0 VEYA toplam harcama > 0 VEYA toplam kazanç > 0)
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('admin_users_with_balance')
          .select('*')
          .order('available_balance', ascending: false)
          .limit(100);

      final users = List<Map<String, dynamic>>.from(response as List);

      // Her kullanıcı için ek harcama özetini al
      for (var user in users) {
        final userId = user['user_id'];
        if (userId == null) continue;

        try {
          final summary = await supabase
              .from('admin_user_spending_summary')
              .select('*')
              .eq('user_id', userId)
              .maybeSingle();

          if (summary != null) {
            user['total_order_payments'] = summary['total_order_payments'] ?? 0;
            user['total_topups'] = summary['total_topups'] ?? 0;
            user['order_count'] = summary['order_count'] ?? 0;
            user['topup_count'] = summary['topup_count'] ?? 0;
          } else {
            user['total_order_payments'] = 0;
            user['total_topups'] = 0;
            user['order_count'] = 0;
            user['topup_count'] = 0;
          }
        } catch (_) {
          user['total_order_payments'] = 0;
          user['total_topups'] = 0;
          user['order_count'] = 0;
          user['topup_count'] = 0;
        }
      }

      return users;
    } catch (e) {
      debugPrint('Bakiyeli kullanıcılar getirme hatası: $e');
      // Alternatif: balance_transactions'dan user_id'leri çek
      try {
        final supabase = Supabase.instance.client;
        final txResponse = await supabase
            .from('balance_transactions')
            .select('user_id, profiles!inner(full_name, phone), net_amount')
            .eq('status', 'completed')
            .order('created_at', ascending: false);

        // Kullanıcıları ve son bakiyelerini grupla
        final Map<String, Map<String, dynamic>> userMap = {};
        for (var tx in (txResponse as List)) {
          final userId = tx['user_id'] as String;
          if (!userMap.containsKey(userId)) {
            userMap[userId] = {
              'user_id': userId,
              'full_name': tx['profiles']?['full_name'] ?? 'Bilinmeyen',
              'phone': tx['profiles']?['phone'] ?? '-',
            };
          }
        }

        return userMap.values.toList();
      } catch (e2) {
        debugPrint('Alternatif yöntem de hata: $e2');
        return [];
      }
    }
  }

  Future<List<Map<String, dynamic>>> _searchUsers(String query) async {
    try {
      final supabase = Supabase.instance.client;
      final response = await supabase
          .from('profiles')
          .select('id, full_name, phone, email')
          .or(
            'full_name.ilike.%$query%,phone.ilike.%$query%,email.ilike.%$query%,username.ilike.%$query%',
          )
          .limit(10);

      return List<Map<String, dynamic>>.from(response as List);
    } catch (e) {
      debugPrint('Kullanıcı arama hatası: $e');
      return [];
    }
  }

  // İşlem geçmişi kartını oluşturur.
  // Her kart tıklanabilir; tıklanınca kişi detayı dialogu açılır.
  Widget _buildTransactionCard(Map<String, dynamic> tx) {
    final isPositive = (tx['net_amount'] as num) > 0;
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
            '${isPositive ? '+' : ''}₺${(tx['net_amount'] as num).toStringAsFixed(2)}',
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
    final isPositive = (tx['net_amount'] as num) > 0;
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
                '${isPositive ? '+' : ''}₺${(tx['net_amount'] as num).toStringAsFixed(2)}',
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

  Widget _buildBalanceInfo(String label, double amount, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
        ),
        const SizedBox(height: 2),
        Text(
          '₺${amount.toStringAsFixed(2)}',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }

  bool _isValidImageUrl(dynamic url) {
    if (url == null) return false;
    final urlStr = url.toString().trim();
    if (urlStr.isEmpty) return false;
    return urlStr.startsWith('http://') || urlStr.startsWith('https://');
  }
}
