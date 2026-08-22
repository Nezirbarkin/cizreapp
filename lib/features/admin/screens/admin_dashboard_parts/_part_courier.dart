// Bu dosya `part of admin_dashboard_screen.dart` oldugu icin ana dosyadaki
// ignore_for_file direktifleri buraya UYGULANMAZ; her part kendi listesini
// tasimak zorundadir.
//
// invalid_use_of_protected_member: bu part'lar `extension on
// _AdminDashboardScreenState` deseniyle yazildi; setState/mounted analiz
// acisindan sinif disindan cagrilmis gorunur ama calisma zamaninda
// State'in kendi uyesidir. Tek gercek false positive budur ve yalniz o
// susturulur - dosyalarin analizden komple cikarilmasi (analysis_options
// exclude) dead_code/tip hatalarini da gizliyordu.
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: use_build_context_synchronously, deprecated_member_use
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
                                if (!feeSnapshot.hasData) {
                                  return const SizedBox.shrink();
                                }
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
                const CourierPayoutRequestsSection(),

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
    // 2026-08-03: Kurye bakiyesi artık courier_earnings + courier_payout_items
    // üzerinden RPC ile yönetilir. authenticated doğrudan tablo yazamaz.
    // Toplu sıfırlama için admin_reject_courier_payout kullanılabilir
    // (payout reddi ile ilgili earnings'ler pending'e döner). Burada
    // kullanıcıyı bilgilendirip kısa yol bırakıyoruz.
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Bakiye sıfırlama artık ödeme istekleri üzerinden yönetiliyor. '
            'Lütfen "Ödeme İstekleri" sekmesini kullanın.',
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 5),
        ),
      );
    }
    return;
  }

  // --- _markCourierPaid ---
  Future<void> _markCourierPaid(Map<String, dynamic> courier) async {
    // 2026-08-03: Toplu ödeme artık admin_approve_courier_payout üzerinden
    // item-tabanlı yapılıyor. Burada kullanıcıyı yönlendiriyoruz.
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Toplu ödeme artık ödeme istekleri üzerinden yapılıyor. '
            'Lütfen "Ödeme İstekleri" sekmesinden ilgili payout'
            'ı onaylayın.',
          ),
          backgroundColor: Colors.orange,
          duration: Duration(seconds: 5),
        ),
      );
    }
    return;
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
