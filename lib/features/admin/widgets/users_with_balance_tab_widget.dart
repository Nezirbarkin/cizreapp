import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Bakiyeli kullanıcıların detaylı kazanç/harcama dökümü
/// (`admin_users_with_balance` + `admin_user_spending_summary`).
///
/// Hem "Cüzdan Yönetimi" ekranının "Bakiyeli Kullanıcılar" sekmesinde hem de
/// "Ödemeler" hub'ının "Detaylı Kazanç Dökümü" sekmesinde aynı veriyle
/// kullanılır.
class UsersWithBalanceTabWidget extends StatefulWidget {
  const UsersWithBalanceTabWidget({super.key});

  @override
  State<UsersWithBalanceTabWidget> createState() =>
      _UsersWithBalanceTabWidgetState();
}

class _UsersWithBalanceTabWidgetState
    extends State<UsersWithBalanceTabWidget> {
  late Future<List<Map<String, dynamic>>> _usersFuture;

  @override
  void initState() {
    super.initState();
    _usersFuture = _getUsersWithBalance();
  }

  void _refresh() {
    setState(() {
      _usersFuture = _getUsersWithBalance();
    });
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

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _usersFuture,
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
                  onPressed: _refresh,
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

        return RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: users.length,
            itemBuilder: (context, index) {
              final user = users[index];
              final balance =
                  (user['available_balance'] as num?)?.toDouble() ??
                  (user['balance'] as num?)?.toDouble() ??
                  0.0;
              final totalSpent =
                  (user['total_spent'] as num?)?.toDouble() ?? 0.0;
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
          ),
        );
      },
    );
  }
}
