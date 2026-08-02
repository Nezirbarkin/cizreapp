part of '../admin_dashboard_screen.dart';

/// Bir isim/kullanıcı adından avatar baş harfini güvenli alır.
/// Boş/null ise 'K' döner (RangeError fırlatmaz).
String _avatarInitial(String? name) {
  final n = (name ?? '').trim();
  return n.isNotEmpty ? n[0].toUpperCase() : 'K';
}

extension on _AdminDashboardScreenState {
  // ==========================================================================
  // Kurye yonetimi + bakiye/odeme dialoglari
  // ==========================================================================

  // --- _buildCourierManagementContent ---
  Widget _buildCourierManagementContent() {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _loadCouriers(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }

        final couriers = snapshot.data ?? [];

        // İstatistikler
        final totalDeliveries = couriers.fold<int>(
          0,
          (sum, c) => sum + ((c['delivered_count'] as int?) ?? 0),
        );
        final totalEarnings = couriers.fold<double>(
          0,
          (sum, c) => sum + ((c['total_earnings'] as num?)?.toDouble() ?? 0),
        );
        final totalPendingEarnings = couriers.fold<double>(
          0,
          (sum, c) => sum + ((c['pending_earnings'] as num?)?.toDouble() ?? 0),
        );

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Kurye Yönetimi',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // İstatistik Kartları
                Row(
                  children: [
                    Expanded(
                      child: _buildCourierStatCard(
                        icon: Icons.delivery_dining,
                        title: 'Toplam Kurye',
                        value: '${couriers.length}',
                        color: Colors.teal,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCourierStatCard(
                        icon: Icons.check_circle,
                        title: 'Toplam Teslimat',
                        value: '$totalDeliveries',
                        color: Colors.green,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildCourierStatCard(
                        icon: Icons.attach_money,
                        title: 'Ödenen Kazanç',
                        value: '₺${totalEarnings.toStringAsFixed(2)}',
                        color: Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildCourierStatCard(
                        icon: Icons.pending_actions,
                        title: 'Bekleyen Alacak',
                        value: '₺${totalPendingEarnings.toStringAsFixed(2)}',
                        color: Colors.orange,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Kurye Ücreti Ayarı
                Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.settings, color: Colors.teal),
                            const SizedBox(width: 8),
                            const Text(
                              'Kurye Ücret Ayarları',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            FutureBuilder<double>(
                              future: _getCourierFee(),
                              builder: (context, feeSnapshot) {
                                if (!feeSnapshot.hasData)
                                  return const SizedBox.shrink();
                                return Text(
                                  'Paket Başı: ₺${feeSnapshot.data!.toStringAsFixed(2)}',
                                  style: TextStyle(color: Colors.grey.shade600),
                                );
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton.icon(
                          onPressed: () => _showCourierFeeDialog(),
                          icon: const Icon(Icons.edit),
                          label: const Text('Ücreti Güncelle'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.teal,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Kurye Ödeme İstekleri
                Card(
                  margin: const EdgeInsets.only(bottom: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.payments, color: Colors.teal),
                            const SizedBox(width: 8),
                            const Text(
                              'Kurye Ödeme İstekleri',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            ElevatedButton.icon(
                              onPressed: () => _loadCourierPayouts(),
                              icon: const Icon(Icons.refresh, size: 16),
                              label: const Text('Yenile'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.teal,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                textStyle: const TextStyle(fontSize: 12),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        FutureBuilder<List<Map<String, dynamic>>>(
                          future: _loadCourierPayouts(),
                          builder: (context, payoutSnapshot) {
                            if (payoutSnapshot.connectionState ==
                                ConnectionState.waiting) {
                              return const Center(
                                child: CircularProgressIndicator(),
                              );
                            }
                            final payouts = payoutSnapshot.data ?? [];
                            if (payouts.isEmpty) {
                              return Center(
                                child: Padding(
                                  padding: const EdgeInsets.all(16),
                                  child: Text(
                                    'Bekleyen ödeme isteği yok',
                                    style: TextStyle(
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                                ),
                              );
                            }
                            return Column(
                              children: payouts.map((payout) {
                                final status =
                                    payout['status'] as String? ?? 'pending';
                                final amount =
                                    (payout['amount'] as num?)?.toDouble() ??
                                    0.0;
                                final courierName =
                                    payout['profiles']?['full_name'] ??
                                    payout['profiles']?['username'] ??
                                    'Kurye';
                                final statusColor = status == 'pending'
                                    ? Colors.orange
                                    : (status == 'approved'
                                          ? Colors.blue
                                          : Colors.green);
                                final statusText = status == 'pending'
                                    ? 'Bekliyor'
                                    : (status == 'approved'
                                          ? 'Onaylandı'
                                          : 'Ödendi');

                                return Card(
                                  margin: const EdgeInsets.only(bottom: 8),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      children: [
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                courierName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                '₺${amount.toStringAsFixed(2)}',
                                                style: TextStyle(
                                                  color: statusColor,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              Text(
                                                payout['requested_at'] != null
                                                    ? _formatDate(
                                                        payout['requested_at'],
                                                      )
                                                    : '-',
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
                                            horizontal: 12,
                                            vertical: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: statusColor.withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(
                                              20,
                                            ),
                                          ),
                                          child: Text(
                                            statusText,
                                            style: TextStyle(
                                              color: statusColor,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ),
                                        if (status == 'pending') ...[
                                          const SizedBox(width: 8),
                                          IconButton(
                                            icon: const Icon(
                                              Icons.check_circle,
                                              color: Colors.green,
                                            ),
                                            onPressed: () =>
                                                _approveCourierPayout(
                                                  payout['id'],
                                                ),
                                            tooltip: 'Onayla',
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                // Kurye Listesi
                const Text(
                  'Kuryeler',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),

                if (couriers.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.delivery_dining,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Henüz kurye yok',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Kullanıcı yönetiminden rol atayarak kurye ekleyebilirsiniz',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey.shade500,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: couriers.length,
                    itemBuilder: (context, index) {
                      final courier = couriers[index];
                      return _buildCourierCard(courier);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- _buildCourierStatCard ---
  Widget _buildCourierStatCard({
    required IconData icon,
    required String title,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            title,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  // --- _buildCourierCard ---
  Widget _buildCourierCard(Map<String, dynamic> courier) {
    final deliveredCount = (courier['delivered_count'] as int?) ?? 0;
    final totalEarnings =
        (courier['total_earnings'] as num?)?.toDouble() ?? 0.0;
    final pendingEarnings =
        (courier['pending_earnings'] as num?)?.toDouble() ?? 0.0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundImage: courier['avatar_url'] != null
                      ? NetworkImage(courier['avatar_url'])
                      : null,
                  child: courier['avatar_url'] == null
                      ? Text(
                          _avatarInitial(courier['username'] as String?),
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        )
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        courier['full_name'] ?? courier['username'] ?? 'Kurye',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        courier['email'] ?? '',
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
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: courier['is_online'] == true
                        ? Colors.green.shade100
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    courier['is_online'] == true ? 'Online' : 'Offline',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: courier['is_online'] == true
                          ? Colors.green
                          : Colors.grey,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _buildCourierInfoItem(
                    Icons.check_circle,
                    '$deliveredCount',
                    'Teslimat',
                    Colors.green,
                  ),
                  Container(width: 1, height: 30, color: Colors.grey.shade300),
                  _buildCourierInfoItem(
                    Icons.attach_money,
                    '₺${totalEarnings.toStringAsFixed(2)}',
                    'Ödenen',
                    Colors.blue,
                  ),
                  Container(width: 1, height: 30, color: Colors.grey.shade300),
                  _buildCourierInfoItem(
                    Icons.pending_actions,
                    '₺${pendingEarnings.toStringAsFixed(2)}',
                    'Alacak',
                    Colors.orange,
                  ),
                ],
              ),
            ),
            if (pendingEarnings > 0) ...[
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.account_balance_wallet,
                            size: 16,
                            color: Colors.orange.shade700,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '₺${pendingEarnings.toStringAsFixed(2)} alacak bekliyor',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.orange.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
                    onPressed: () => _markCourierPaid(courier),
                    icon: const Icon(Icons.check_circle, size: 16),
                    label: const Text('Ödeme Yapıldı'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      textStyle: const TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  // --- _buildCourierInfoItem ---
  Widget _buildCourierInfoItem(
    IconData icon,
    String value,
    String label,
    Color color,
  ) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, color: color),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  // --- _resetCourierBalance ---
  Future<void> _resetCourierBalance(Map<String, dynamic> courier) async {
    final courierId = courier['id'] as String?;
    final courierName = courier['full_name'] ?? courier['username'] ?? 'Kurye';
    final pendingAmount =
        (courier['pending_earnings'] as num?)?.toDouble() ?? 0;

    if (courierId == null || pendingAmount <= 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kurye Alacak Sıfırlama'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '$courierName - ₺${pendingAmount.toStringAsFixed(2)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Bekleyen alacak silinecek',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.red.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Bu işlem bekleyen kazançları "iptal" olarak işaretler. '
              'Geçmiş ödemeler ve sipariş geçmişi korunur.',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Sıfırla'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Bekleyen kazançları "cancelled" olarak işaretle
      await Supabase.instance.client
          .from('courier_earnings')
          .update({'status': 'cancelled'})
          .eq('courier_id', courierId)
          .eq('status', 'pending');

      // Bekleyen ödeme isteklerini de "cancelled" yap
      try {
        await Supabase.instance.client
            .from('courier_payout_requests')
            .update({'status': 'cancelled'})
            .eq('courier_id', courierId)
            .eq('status', 'pending');
      } catch (e) {
        debugPrint('Ödeme isteği iptal hatası: $e');
      }

      if (mounted) {
        setState(() {}); // Kurye listesini yenile
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$courierName alacak bakiyesi sıfırlandı (₺${pendingAmount.toStringAsFixed(2)})',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Kurye bakiye sıfırlama hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- _markCourierPaid ---
  Future<void> _markCourierPaid(Map<String, dynamic> courier) async {
    final courierId = courier['id'] as String?;
    final courierName = courier['full_name'] ?? courier['username'] ?? 'Kurye';
    final pendingAmount =
        (courier['pending_earnings'] as num?)?.toDouble() ?? 0;

    if (courierId == null) return;

    // Eğer alacak yoksa, yine de ödeme kaydı oluşturabilir (manuel ödeme için)
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kurye Ödemesi'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.green.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.payments, color: Colors.green.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          courierName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₺${pendingAmount.toStringAsFixed(2)} ödenecek',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.green.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Bu işlem:\n'
              '• Kazançları "ödendi" olarak işaretler\n'
              '• Kuryeye bildirim gönderir\n'
              '• Ödeme geçmişine kayıt ekler',
              style: TextStyle(fontSize: 13, color: Colors.grey),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Ödeme Yapıldı'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      // Bekleyen kazançları "paid" olarak işaretle
      await Supabase.instance.client
          .from('courier_earnings')
          .update({'status': 'paid'})
          .eq('courier_id', courierId)
          .eq('status', 'pending');

      // Bekleyen ödeme isteklerini "approved" yap
      try {
        await Supabase.instance.client
            .from('courier_payout_requests')
            .update({'status': 'approved'})
            .eq('courier_id', courierId)
            .eq('status', 'pending');
      } catch (e) {
        debugPrint('Ödeme isteği güncelleme hatası: $e');
      }

      // Kuryeye bildirim gönder
      try {
        await Supabase.instance.client.from('notifications').insert({
          'user_id': courierId,
          'type': 'courier_payout_approved',
          'title': '💰 Ödemeniz Hesabınıza Aktarıldı!',
          'content':
              '₺${pendingAmount.toStringAsFixed(2)} tutarındaki ödemeniz hesabınıza aktarıldı.',
          'data': {'type': 'courier_payout', 'amount': pendingAmount},
          'is_read': false,
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        debugPrint('Kurye bildirim hatası: $e');
      }

      if (mounted) {
        setState(() {}); // Kurye listesini yenile
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$courierName - ₺${pendingAmount.toStringAsFixed(2)} ödendi olarak işaretlendi',
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Kurye ödeme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- _showCourierFeeDialog ---
  void _showCourierFeeDialog() {
    final feeController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kurye Ücreti'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Paket başı kurye ücretini girin:'),
            const SizedBox(height: 12),
            TextField(
              controller: feeController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'Ücret (₺)',
                border: OutlineInputBorder(),
                prefixText: '₺',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final fee = double.tryParse(feeController.text);
              if (fee == null || fee < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Geçerli bir ücret girin'),
                    backgroundColor: Colors.red,
                  ),
                );
                return;
              }

              try {
                // Önce mevcut kayıt var mı kontrol et
                final existing = await Supabase.instance.client
                    .from('courier_settings')
                    .select('id')
                    .limit(1)
                    .maybeSingle();

                if (existing != null) {
                  // Kayıt varsa güncelle
                  await Supabase.instance.client
                      .from('courier_settings')
                      .update({
                        'fee_per_delivery': fee,
                        'updated_at': DateTime.now().toIso8601String(),
                      })
                      .eq('id', existing['id']);
                } else {
                  // Kayıt yoksa oluştur
                  await Supabase.instance.client
                      .from('courier_settings')
                      .insert({'fee_per_delivery': fee});
                }

                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Kurye ücreti ₺$fee olarak güncellendi'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Hata: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  // --- _approveCourierPayout ---
  Future<void> _approveCourierPayout(String payoutId) async {
    try {
      // Odeme isteginin detaylarini al
      final payout = await Supabase.instance.client
          .from('courier_payout_requests')
          .select('''
            id, amount, status, courier_id,
            profiles:courier_id(full_name, username)
          ''')
          .eq('id', payoutId)
          .maybeSingle();

      if (payout == null) return;

      // Kuryenin odeme bilgilerini al
      Map<String, dynamic>? paymentInfo;
      try {
        final response = await Supabase.instance.client
            .from('courier_payment_info')
            .select()
            .eq('courier_id', payout['courier_id'])
            .maybeSingle();
        paymentInfo = response;
      } catch (_) {
        // Tablo yoksa devam et
      }

      final courierName =
          payout['profiles']?['full_name'] ??
          payout['profiles']?['username'] ??
          'Kurye';
      final amount = (payout['amount'] as num?)?.toDouble() ?? 0.0;

      if (!mounted) return;

      // Onay dialogu goster
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Odeme Onayi'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Kurye: $courierName'),
              Text('Tutar: ₺${amount.toStringAsFixed(2)}'),
              const Divider(),
              if (paymentInfo != null) ...[
                const Text(
                  'Odeme Bilgileri:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (paymentInfo['iban'] != null)
                  Text('IBAN: ${paymentInfo['iban']}'),
                if (paymentInfo['bank_name'] != null)
                  Text('Banka: ${paymentInfo['bank_name']}'),
                if (paymentInfo['account_holder_name'] != null)
                  Text('Hesap Sahibi: ${paymentInfo['account_holder_name']}'),
              ] else ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Kurye odeme bilgisi girmemis!',
                    style: TextStyle(color: Colors.orange),
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Iptal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Onayla'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      // Odeme istegini onayla
      await Supabase.instance.client
          .from('courier_payout_requests')
          .update({
            'status': 'approved',
            'approved_at': DateTime.now().toIso8601String(),
          })
          .eq('id', payoutId);

      // Bu ödeme isteğine dahil olan kazançları "paid" olarak işaretle.
      // Payout isteği oluşturulurken kuryenin pending kazançları 'requested'
      // durumuna çevrilir (courier_panel_screen.dart). Dolayısıyla burada
      // 'pending' değil 'requested' olanlar ödenmeli — aksi halde istek
      // sonrası yapılan YENİ teslimatlar (hâlâ 'pending') yanlışlıkla ödenir
      // ve asıl istenen tutar ödenmemiş kalır.
      try {
        await Supabase.instance.client
            .from('courier_earnings')
            .update({'status': 'paid'})
            .eq('courier_id', payout['courier_id'])
            .eq('status', 'requested');
      } catch (e) {
        debugPrint('Kurye kazanc guncelleme hatasi: $e');
      }

      // Kuryeye bildirim gönder.
      // 2026-08-02 push pipeline refaktörü:
      //   - İstemci FCM token SELECT etmez, functions.invoke çağırmaz.
      //   - notifications INSERT sonrası notifications_outbox_trigger
      //     otomatik olarak notification_outbox'a yazar.
      //   - process-notification-outbox worker'ı FCM'yi iletir.
      try {
        await Supabase.instance.client.from('notifications').insert({
          'user_id': payout['courier_id'],
          'type': 'courier_payout_approved',
          'title': '💰 Ödemeniz Onaylandı!',
          'content':
              '₺${amount.toStringAsFixed(2)} tutarındaki ödemeniz onaylandı ve kısa süre içinde hesabınıza aktarılacaktır.',
          'metadata': {
            'payout_id': payoutId,
            'amount': amount,
            'type': 'courier_payout',
          },
          'is_read': false,
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (e) {
        debugPrint('Bildirim gonderme hatasi: $e');
      }

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 8),
                Text(
                  '$courierName\'e ₺${amount.toStringAsFixed(2)} ödeme onaylandı ve bildirim gönderildi',
                ),
              ],
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Odeme onaylama hatasi: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- _getCourierFee ---
  Future<double> _getCourierFee() async {
    try {
      final settings = await Supabase.instance.client
          .from('courier_settings')
          .select('fee_per_delivery')
          .order('updated_at', ascending: false)
          .limit(1)
          .maybeSingle();
      return (settings?['fee_per_delivery'] as num?)?.toDouble() ?? 15.0;
    } catch (e) {
      debugPrint('Kurye ücreti yüklenirken hata: $e');
      return 15.0;
    }
  }
}
