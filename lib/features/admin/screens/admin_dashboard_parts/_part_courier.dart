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
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: _buildCourierDocumentStatusChip(courier)),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: () => _showCourierDocumentsDialog(courier),
                  icon: const Icon(Icons.badge_outlined, size: 16),
                  label: const Text('Evraklar'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.brown,
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

  // --- _buildCourierDocumentStatusChip ---
  Widget _buildCourierDocumentStatusChip(Map<String, dynamic> courier) {
    final status = courier['document_status'] as String?;

    late final Color color;
    late final String text;
    late final IconData icon;

    switch (status) {
      case 'approved':
        color = Colors.green;
        text = 'Evrak: Onaylı';
        icon = Icons.verified;
        break;
      case 'rejected':
        color = Colors.red;
        text = 'Evrak: Reddedildi';
        icon = Icons.error_outline;
        break;
      case 'pending':
        color = Colors.orange;
        text = 'Evrak: İncelemede';
        icon = Icons.hourglass_top;
        break;
      default:
        color = Colors.grey;
        text = 'Evrak: Gönderilmedi';
        icon = Icons.help_outline;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: color,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  // --- _showCourierDocumentsDialog ---
  void _showCourierDocumentsDialog(Map<String, dynamic> courier) async {
    final courierId = courier['id'] as String;

    Map<String, dynamic>? doc;
    try {
      doc = await Supabase.instance.client
          .from('courier_documents')
          .select()
          .eq('courier_id', courierId)
          .maybeSingle();
    } catch (e) {
      debugPrint('Kurye evrakı yüklenirken hata: $e');
    }

    if (!mounted) return;

    if (doc == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu kurye henüz evrak göndermemiş'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // showDialog'un builder closure'ı içinde `doc?[...]` her seferinde null
    // kontrolü gerektirmesin diye (Dart, mutable yakalanan değişkenlerde tip
    // daraltmasını closure sınırında korumuyor) null-check sonrası non-nullable
    // bir kopya alınır.
    final docData = doc;

    final slots = <String, String?>{
      'Kimlik (Ön Yüz)': docData['id_front_path'] as String?,
      'Kimlik (Arka Yüz)': docData['id_back_path'] as String?,
      'Ehliyet Fotoğrafı': docData['license_photo_path'] as String?,
      'Motor / Plaka Fotoğrafı': docData['vehicle_photo_path'] as String?,
    };

    final signedUrls = <String, String>{};
    for (final entry in slots.entries) {
      final path = entry.value;
      if (path == null || path.isEmpty) continue;
      try {
        final url = await Supabase.instance.client.storage
            .from('courier-documents')
            .createSignedUrl(path, 3600);
        signedUrls[entry.key] = url;
      } catch (e) {
        debugPrint('Signed url alınamadı (${entry.key}): $e');
      }
    }

    String? selfieVideoUrl;
    final selfieVideoPath = docData['selfie_video_path'] as String?;
    if (selfieVideoPath != null && selfieVideoPath.isNotEmpty) {
      try {
        selfieVideoUrl = await Supabase.instance.client.storage
            .from('courier-documents')
            .createSignedUrl(selfieVideoPath, 3600);
      } catch (e) {
        debugPrint('Selfie video signed url alınamadı: $e');
      }
    }

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          courier['full_name'] ?? courier['username'] ?? 'Kurye Evrakları',
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildCourierDocumentStatusChip({
                  ...courier,
                  'document_status': docData['status'],
                }),
                const SizedBox(height: 12),
                Text('Ad Soyad: ${docData['full_name'] ?? '-'}'),
                Text('Telefon: ${docData['phone'] ?? '-'}'),
                Text('Plaka: ${docData['plate_number'] ?? '-'}'),
                if (docData['admin_note'] != null &&
                    (docData['admin_note'] as String).isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      'Not: ${docData['admin_note']}',
                      style: const TextStyle(fontStyle: FontStyle.italic),
                    ),
                  ),
                const SizedBox(height: 16),
                GridView.count(
                  crossAxisCount: 2,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1,
                  children: slots.keys.map((label) {
                    final url = signedUrls[label];
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(label, style: const TextStyle(fontSize: 11)),
                        const SizedBox(height: 4),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: Colors.grey.shade300),
                            ),
                            clipBehavior: Clip.antiAlias,
                            child: url == null
                                ? const Center(
                                    child: Icon(
                                      Icons.image_not_supported_outlined,
                                      color: Colors.grey,
                                    ),
                                  )
                                : GestureDetector(
                                    onTap: () => _showFullscreenImage(url),
                                    child: Image.network(
                                      url,
                                      fit: BoxFit.cover,
                                      errorBuilder: (c, e, s) => const Center(
                                        child: Icon(
                                          Icons.broken_image,
                                          color: Colors.grey,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Selfie Doğrulama Videosu',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                if (selfieVideoUrl == null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.videocam_off_outlined, color: Colors.grey.shade500, size: 18),
                        const SizedBox(width: 8),
                        Text(
                          'Video gönderilmemiş',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  )
                else
                  OutlinedButton.icon(
                    onPressed: () => _showFullscreenVideo(selfieVideoUrl!),
                    icon: const Icon(Icons.play_circle_outline),
                    label: const Text('Videoyu Oynat'),
                    style: OutlinedButton.styleFrom(foregroundColor: Colors.teal),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Kapat'),
          ),
          if (docData['status'] != 'rejected')
            TextButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _reviewCourierDocument(courierId, 'rejected');
              },
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Reddet'),
            ),
          if (docData['status'] != 'approved')
            ElevatedButton(
              onPressed: () {
                Navigator.pop(dialogContext);
                _reviewCourierDocument(courierId, 'approved');
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Onayla'),
            ),
        ],
      ),
    );
  }

  // --- _showFullscreenImage ---
  void _showFullscreenImage(String url) {
    showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: const EdgeInsets.all(12),
        child: InteractiveViewer(
          child: Image.network(url, fit: BoxFit.contain),
        ),
      ),
    );
  }

  // --- _showFullscreenVideo ---
  void _showFullscreenVideo(String url) {
    showDialog(
      context: context,
      builder: (context) => _AdminVideoPreviewDialog(url: url),
    );
  }

  // --- _reviewCourierDocument ---
  Future<void> _reviewCourierDocument(String courierId, String status) async {
    String? note;
    if (status == 'rejected') {
      final noteController = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Reddetme Gerekçesi'),
          content: TextField(
            controller: noteController,
            maxLines: 3,
            decoration: const InputDecoration(
              hintText: 'Kurye evrakında düzeltilmesi gereken durumu yazın',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text('Reddet'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      note = noteController.text.trim();
    }

    try {
      await Supabase.instance.client.rpc(
        'admin_review_courier_document',
        params: {
          'p_courier_id': courierId,
          'p_status': status,
          'p_note': note,
        },
      );

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == 'approved'
                  ? 'Kurye evrakları onaylandı'
                  : 'Kurye evrakları reddedildi',
            ),
            backgroundColor: status == 'approved' ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Evrak inceleme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }
}

class _AdminVideoPreviewDialog extends StatefulWidget {
  const _AdminVideoPreviewDialog({required this.url});

  final String url;

  @override
  State<_AdminVideoPreviewDialog> createState() =>
      _AdminVideoPreviewDialogState();
}

class _AdminVideoPreviewDialogState extends State<_AdminVideoPreviewDialog> {
  VideoPlayerController? _controller;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await controller.initialize();
      await controller.play();
      if (mounted) setState(() => _controller = controller);
    } catch (e) {
      debugPrint('Video oynatma hatası: $e');
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(12),
      child: _hasError
          ? const Padding(
              padding: EdgeInsets.all(32),
              child: Text('Video oynatılamadı', style: TextStyle(color: Colors.white)),
            )
          : _controller == null
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _controller!.value.isPlaying
                            ? _controller!.pause()
                            : _controller!.play();
                      });
                    },
                    child: VideoPlayer(_controller!),
                  ),
                ),
    );
  }
}
