part of '../admin_dashboard_screen.dart';

extension on _AdminDashboardScreenState {
  // ==========================================================================
  // Odemeler + payout islemleri + dialoglar
  // ==========================================================================

  // --- _buildPaymentsContent ---
  Widget _buildPaymentsContent() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadPaymentData(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snapshot.hasError) {
          return Center(child: Text('Hata: ${snapshot.error}'));
        }

        final data = snapshot.data ?? {};
        final payments = data['payments'] as List<Map<String, dynamic>>? ?? [];
        final stats = data['stats'] as Map<String, dynamic>? ?? {};

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
                  'Ödeme Yönetimi',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),

                // İstatistik Kartları
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.payments,
                        title: 'Toplam Gelir',
                        value: '₺${stats['total_revenue'] ?? 0}',
                        color: Colors.green,
                        gradient: [
                          Colors.green.shade400,
                          Colors.green.shade600,
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.receipt_long,
                        title: 'Ödeme Sayısı',
                        value: '${stats['total_payments'] ?? 0}',
                        color: Colors.blue,
                        gradient: [Colors.blue.shade400, Colors.blue.shade600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.check_circle,
                        title: 'Başarılı',
                        value: '${stats['completed_count'] ?? 0}',
                        color: Colors.teal,
                        gradient: [Colors.teal.shade400, Colors.teal.shade600],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.pending,
                        title: 'Bekleyen',
                        value: '${stats['pending_count'] ?? 0}',
                        color: Colors.orange,
                        gradient: [
                          Colors.orange.shade400,
                          Colors.orange.shade600,
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.cancel,
                        title: 'İptal',
                        value: '${stats['cancelled_count'] ?? 0}',
                        color: Colors.red,
                        gradient: [Colors.red.shade400, Colors.red.shade600],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Ödeme Geçmişi
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Son Ödemeler',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        // Tümünü göster
                      },
                      icon: const Icon(Icons.filter_list),
                      label: const Text('Filtrele'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                if (payments.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.payment_outlined,
                            size: 64,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Henüz ödeme yok',
                            style: TextStyle(
                              fontSize: 16,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ListView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: payments.length,
                    itemBuilder: (context, index) {
                      final payment = payments[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(12),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: _getPaymentStatusColor(
                                payment['status'],
                              ).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              _getPaymentIcon(payment['status']),
                              color: _getPaymentStatusColor(payment['status']),
                              size: 24,
                            ),
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  payment['shops']?['name'] ?? '-',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                  ),
                                ),
                              ),
                              Text(
                                '₺${payment['total_amount'] ?? 0}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 16,
                                  color: Colors.green.shade700,
                                ),
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.person,
                                    size: 12,
                                    color: Colors.grey.shade500,
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      payment['shops']?['profiles']?['email'] ??
                                          '-',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey.shade600,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.access_time,
                                    size: 12,
                                    color: Colors.grey.shade500,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _formatDate(payment['created_at']),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                  const Spacer(),
                                  Chip(
                                    label: Text(
                                      _getPaymentStatusText(payment['status']),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    backgroundColor: _getPaymentStatusColor(
                                      payment['status'],
                                    ).withOpacity(0.2),
                                    labelStyle: TextStyle(
                                      color: _getPaymentStatusColor(
                                        payment['status'],
                                      ),
                                    ),
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                  ),
                                ],
                              ),
                            ],
                          ),
                          onTap: () => _showPaymentDetailDialog(payment),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- _markPayoutAsPaid ---
  Future<void> _markPayoutAsPaid(Map<String, dynamic> payment) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.payment, color: Colors.purple),
            const SizedBox(width: 8),
            const Text('Ödemeyi Tamamla'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${payment['shops']?['name'] ?? 'Mağaza'} mağazasına ₺${(payment['total_amount'] as num?)?.toStringAsFixed(2) ?? '0.00'} TL ödeme yapıldı olarak işaretlenecek.',
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    color: Colors.orange.shade700,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Bu işlem satıcının tüm bakiyelerini (kapıda kazanç, online kazanç ve komisyon borcu) sıfırlayacak.',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.orange.shade900,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.check),
            label: const Text('Evet, Ödendi'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.purple),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        final payoutId = payment['id'] as String;
        final shopId = payment['shop_id'] as String?;

        // Shop bilgilerini al
        final shop = await Supabase.instance.client
            .from('shops')
            .select('owner_id, name')
            .eq('id', shopId!)
            .single();

        // Ödeme durumunu 'paid' olarak güncelle
        // Trigger otomatik olarak bakiyeleri sıfırlayacak
        await Supabase.instance.client
            .from('payout_requests')
            .update({
              'status': 'paid',
              'paid_at': DateTime.now().toIso8601String(),
              'updated_at': DateTime.now().toIso8601String(),
            })
            .eq('id', payoutId);

        // Satıcıya bildirim gönder
        final sellerId = shop['owner_id'];
        final shopName = shop['name'] ?? 'Mağazanız';
        final amount = (payment['total_amount'] as num?)?.toDouble() ?? 0.0;

        if (sellerId != null) {
          await Supabase.instance.client.from('notifications').insert({
            'user_id': sellerId,
            'type': 'shop',
            'title': 'Ödeme Yapıldı',
            'content':
                '$shopName için ₺${amount.toStringAsFixed(2)} TL ödemeniz yapıldı. Tüm bakiyeleriniz sıfırlandı.',
            'is_read': false,
            'created_at': DateTime.now().toIso8601String(),
          });
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Ödeme tamamlandı ve bakiyeler sıfırlandı'),
              backgroundColor: Colors.purple,
            ),
          );
          setState(() {});
        }
      } catch (e) {
        debugPrint('❌ Ödeme tamamlama hatası: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('İşlem başarısız: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  // --- _showPaymentDetailDialog ---
  void _showPaymentDetailDialog(Map<String, dynamic> payment) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(
              _getPaymentIcon(payment['status']),
              color: _getPaymentStatusColor(payment['status']),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Ödeme Detayı', style: const TextStyle(fontSize: 18)),
                  Text(
                    '#${(payment['id'] as String?)?.substring(0, 8) ?? '-'}',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Durum
              Card(
                color: _getPaymentStatusColor(
                  payment['status'],
                ).withOpacity(0.1),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      const Text(
                        'Durum:',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(width: 8),
                      Chip(
                        label: Text(_getPaymentStatusText(payment['status'])),
                        backgroundColor: _getPaymentStatusColor(
                          payment['status'],
                        ).withOpacity(0.2),
                        labelStyle: TextStyle(
                          color: _getPaymentStatusColor(payment['status']),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Dükkan Bilgisi
              const Text(
                'Dükkan Bilgisi',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              _buildInfoRow(
                'Dükkan',
                payment['shops']?['name'] ?? '-',
                Colors.grey.shade700,
              ),
              _buildInfoRow(
                'Email',
                payment['shops']?['profiles']?['email'] ?? '-',
                Colors.grey.shade700,
              ),
              const SizedBox(height: 16),

              // Ödeme İsteği Bilgisi
              const Text(
                'Ödeme İsteği Bilgisi',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              _buildInfoRow(
                'Tutar',
                '₺${payment['total_amount'] ?? 0}',
                Colors.green.shade700,
              ),
              _buildInfoRow(
                'İsteme Tarihi',
                _formatDate(payment['created_at']),
                Colors.grey.shade700,
              ),

              const SizedBox(height: 16),

              // Banka Bilgileri
              const Text(
                'Banka Bilgileri',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 8),
              _buildInfoRow(
                'IBAN',
                payment['iban'] ?? '-',
                Colors.grey.shade700,
              ),
              _buildInfoRow(
                'Hesap Sahibi',
                payment['account_holder_name'] ?? '-',
                Colors.grey.shade700,
              ),

              if (payment['notes'] != null &&
                  (payment['notes'] as String).isNotEmpty) ...[
                const SizedBox(height: 16),
                const Text(
                  'Satıcı Notu',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(payment['notes'] ?? '-'),
              ],

              if (payment['admin_notes'] != null &&
                  (payment['admin_notes'] as String).isNotEmpty) ...[
                const SizedBox(height: 16),
                Text(
                  'Admin Notu',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: Colors.orange.shade700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(payment['admin_notes'] ?? '-'),
              ],

              // İşleme Tarihi
              if (payment['updated_at'] != null &&
                  payment['status'] != 'pending') ...[
                const SizedBox(height: 16),
                _buildInfoRow(
                  'İşleme Tarihi',
                  _formatDate(payment['updated_at']),
                  Colors.grey.shade700,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
          if (payment['status'] == 'pending') ...[
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _showRejectPayoutDialog(payment['id']);
              },
              icon: const Icon(Icons.cancel, color: Colors.red),
              label: const Text('Reddet', style: TextStyle(color: Colors.red)),
            ),
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await _processPayoutRequest(payment['id'], 'approved');
              },
              icon: const Icon(Icons.check_circle),
              label: const Text('Onayla'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
            ),
          ],
          if (payment['status'] == 'approved') ...[
            // Onaylandıysa - ÖDEME YAP butonu
            ElevatedButton.icon(
              onPressed: () async {
                Navigator.pop(context);
                await _markPayoutAsPaid(payment);
              },
              icon: const Icon(Icons.payment),
              label: const Text('Ödeme Yap'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.purple,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // --- _processPayoutRequest ---
  Future<void> _processPayoutRequest(String payoutId, String newStatus) async {
    try {
      // Önce payout request bilgilerini al (shop_id ve total_amount için)
      final payoutRequest = await Supabase.instance.client
          .from('payout_requests')
          .select('shop_id, total_amount')
          .eq('id', payoutId)
          .single();

      // Shop bilgisini al (owner_id ve bildirim için)
      final shop = await Supabase.instance.client
          .from('shops')
          .select('owner_id, name')
          .eq('id', payoutRequest['shop_id'])
          .single();

      final sellerId = shop['owner_id'];
      final shopName = shop['name'];
      final amount = (payoutRequest['total_amount'] as num).toDouble();

      // Ödeme isteğini güncelle.
      // ÖNEMLI (2026-07-03): shops tablosundaki total_paid / pending_payout /
      // kazanç sıfırlama İŞLEMLERİ ARTIK BURADA YAPILMIYOR. Tek yetkili kaynak
      // clear_shop_balance trigger'ı (payout_requests UPDATE). Eskiden Dart hem
      // total_paid += amount yapıyor hem trigger tekrar ekliyordu → ÇİFT SAYIM.
      // Trigger approved VEYA paid'e İLK geçişte bir kez settle eder (idempotent).
      await Supabase.instance.client
          .from('payout_requests')
          .update({
            'status': newStatus,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', payoutId);

      // Satıcıya bildirim gönder
      final notificationMessage = newStatus == 'approved'
          ? '$shopName mağazanız için ${amount.toStringAsFixed(2)} TL tutarındaki ödeme isteğiniz onaylandı. Ödeme kısa süre içinde hesabınıza aktarılacaktır.'
          : '$shopName mağazanız için ${amount.toStringAsFixed(2)} TL tutarındaki ödeme isteğiniz reddedildi. Daha fazla bilgi için destek ekibiyle iletişime geçebilirsiniz.';

      await Supabase.instance.client.from('notifications').insert({
        'user_id': sellerId,
        'type': 'shop', // Mevcut enum değerlerinden biri
        'title': newStatus == 'approved'
            ? 'Ödeme Onaylandı'
            : 'Ödeme Reddedildi',
        'content': notificationMessage,
        'is_read': false,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus == 'approved'
                  ? 'Ödeme isteği onaylandı ve satıcıya bildirim gönderildi'
                  : 'Ödeme isteği reddedildi ve satıcıya bildirim gönderildi',
            ),
            backgroundColor: newStatus == 'approved'
                ? Colors.green
                : Colors.red,
          ),
        );
        setState(() {});
      }
    } catch (e) {
      debugPrint('❌ PAYOUT: İşlem başarısız: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('İşlem başarısız: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // --- _showRejectPayoutDialog ---
  void _showRejectPayoutDialog(String payoutId) {
    final adminNotesController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Ödeme İsteğini Reddet'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Red sebebini belirtin:'),
            const SizedBox(height: 12),
            TextField(
              controller: adminNotesController,
              maxLines: 3,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Red sebebi...',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () async {
              if (adminNotesController.text.trim().isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Lütfen red sebini girin'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }

              Navigator.pop(context);

              try {
                await Supabase.instance.client
                    .from('payout_requests')
                    .update({
                      'status': 'rejected',
                      'admin_notes': adminNotesController.text.trim(),
                      'updated_at': DateTime.now().toIso8601String(),
                    })
                    .eq('id', payoutId);

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ödeme isteği reddedildi'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  setState(() {});
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('İşlem başarısız: $e'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              }
            },
            child: const Text('Reddet', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  // --- _getPaymentStatusText ---
  String _getPaymentStatusText(String? status) {
    switch (status) {
      case 'paid':
        return 'Ödendi';
      case 'approved':
        return 'Onaylandı';
      case 'pending':
        return 'Bekliyor';
      case 'rejected':
        return 'Reddedildi';
      default:
        return 'Bilinmeyen';
    }
  }

  // --- _getAddressPhoneForAdmin ---
  Future<String?> _getAddressPhoneForAdmin(String addressId) async {
    try {
      final response = await Supabase.instance.client
          .from('addresses')
          .select('phone')
          .eq('id', addressId)
          .maybeSingle();

      if (response != null) {
        return response['phone'] as String?;
      }
      return null;
    } catch (e) {
      debugPrint('Admin: Telefon numarası alınırken hata: $e');
      return null;
    }
  }
}
