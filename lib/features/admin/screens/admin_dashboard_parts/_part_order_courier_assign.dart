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

extension on _AdminDashboardScreenState {
  // ==========================================================================
  // Admin -> kurye yonlendirmesi
  //
  // admin_route_order_to_courier RPC'si siparise aktif atama + hedef kuryeye
  // "pending" teklif olusturur: siparis genel kurye havuzundan cikar ve yalniz
  // secilen kuryenin panelinde gorunur. Kurye kabul edince mevcut
  // accept_routed_order_offer akisi devralir.
  // admin_cancel_order_courier_routing yonlendirmeyi geri alir (havuza doner).
  // ==========================================================================

  // --- _loadCourierPickerList ---
  /// Kurye secici icin hafif liste (kazanc sorgulari olmadan).
  Future<List<Map<String, dynamic>>> _loadCourierPickerList() async {
    final response = await Supabase.instance.client.rpc<List<dynamic>>(
      'admin_list_couriers',
    );
    return List<Map<String, dynamic>>.from(response);
  }

  // --- _assignCourierErrorText ---
  /// RPC'nin `APP:kod | mesaj` bicimli hatalarini okunur hale getirir.
  String _assignCourierErrorText(Object error) {
    final raw = error.toString();
    if (raw.contains('already_assigned_to_courier')) {
      return 'Sipariş zaten bu kuryede.';
    }
    if (raw.contains('already_picked_up')) {
      return 'Sipariş mevcut kurye tarafından teslim alınmış; devredilemez.';
    }
    if (raw.contains('courier_documents_not_approved')) {
      return 'Kuryenin evrakları onaylı değil. Önce evrak onayı verin.';
    }
    if (raw.contains('pickup_order')) {
      return '"Gel Al" siparişine kurye atanamaz.';
    }
    if (raw.contains('invalid_order_status')) {
      return 'Bu durumdaki siparişe kurye atanamaz.';
    }
    if (raw.contains('not_a_courier')) {
      return 'Seçilen kullanıcı kurye değil.';
    }
    if (raw.contains('self_delivery')) {
      return 'Kurye kendi siparişini teslim alamaz.';
    }
    if (raw.contains('not_found')) {
      return 'Sipariş ya da aktif atama bulunamadı.';
    }
    return 'İşlem başarısız: $error';
  }

  // --- _showAssignCourierDialog ---
  void _showAssignCourierDialog(Map<String, dynamic> order) {
    final orderId = order['id'] as String;
    final shop = order['shops'] as Map<String, dynamic>?;
    final courierInfo = order['courier_info'] as Map<String, dynamic>?;
    final isPickup = order['is_pickup'] as bool? ?? false;
    String? selectedCourierId;
    bool isBusy = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          Future<void> route() async {
            if (selectedCourierId == null) {
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                const SnackBar(content: Text('Önce bir kurye seçin')),
              );
              return;
            }
            setDialogState(() => isBusy = true);
            try {
              final result = await Supabase.instance.client.rpc<List<dynamic>>(
                'admin_route_order_to_courier',
                params: {
                  'p_order_id': orderId,
                  'p_courier_id': selectedCourierId,
                },
              );
              final row = result.isNotEmpty
                  ? Map<String, dynamic>.from(result.first as Map)
                  : <String, dynamic>{};
              final courierName = row['r_courier_name']?.toString() ?? 'Kurye';

              if (!mounted) return;
              Navigator.pop(dialogContext);
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '$courierName kuryesinin paneline yönlendirildi',
                  ),
                  backgroundColor: Colors.green,
                ),
              );
            } catch (e) {
              debugPrint('❌ Kurye yönlendirme hatası: $e');
              if (!dialogContext.mounted) return;
              setDialogState(() => isBusy = false);
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(
                  content: Text(_assignCourierErrorText(e)),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }

          Future<void> cancelRouting() async {
            final confirmed = await showDialog<bool>(
              context: dialogContext,
              builder: (ctx) => AlertDialog(
                title: const Text('Atamayı kaldır'),
                content: const Text(
                  'Kurye ataması iptal edilecek ve sipariş genel kurye '
                  'havuzuna geri dönecek.',
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: const Text('Vazgeç'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.orange.shade700,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Kaldır'),
                  ),
                ],
              ),
            );
            if (confirmed != true) return;

            setDialogState(() => isBusy = true);
            try {
              await Supabase.instance.client.rpc<List<dynamic>>(
                'admin_cancel_order_courier_routing',
                params: {'p_order_id': orderId},
              );
              if (!mounted) return;
              Navigator.pop(dialogContext);
              setState(() {});
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Atama kaldırıldı, sipariş havuza döndü'),
                  backgroundColor: Colors.green,
                ),
              );
            } catch (e) {
              debugPrint('❌ Atama kaldırma hatası: $e');
              if (!dialogContext.mounted) return;
              setDialogState(() => isBusy = false);
              ScaffoldMessenger.of(dialogContext).showSnackBar(
                SnackBar(
                  content: Text(_assignCourierErrorText(e)),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }

          return AlertDialog(
            title: Row(
              children: [
                Icon(Icons.two_wheeler, color: Colors.indigo.shade600),
                const SizedBox(width: 8),
                const Expanded(child: Text('Kurye Ata')),
              ],
            ),
            content: SizedBox(
              width: 460,
              height: 460,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Sipariş #${orderId.substring(0, 8)}'
                    '${shop?['name'] != null ? ' • ${shop!['name']}' : ''}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  if (isPickup)
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.red.shade200),
                      ),
                      child: Text(
                        'Bu sipariş "Gel Al" siparişi; müşteri mağazadan '
                        'teslim alacak, kurye atanamaz.',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.red.shade800,
                        ),
                      ),
                    )
                  else
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.indigo.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.indigo.shade100),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            courierInfo == null
                                ? 'Şu an atanmış kurye yok.'
                                : 'Mevcut kurye: ${courierInfo['courier_name'] ?? '-'}'
                                      ' (${courierInfo['status'] ?? '-'})',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Seçilen kurye siparişi kendi panelinde görür; '
                            'sipariş genel havuzdan çıkar. Teslim alınmış '
                            'siparişler devredilemez.',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.indigo.shade700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  Expanded(
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: _loadCourierPickerList(),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(),
                          );
                        }
                        if (snapshot.hasError) {
                          return Center(
                            child: Text('Kuryeler yüklenemedi: ${snapshot.error}'),
                          );
                        }
                        final couriers = snapshot.data ?? [];
                        if (couriers.isEmpty) {
                          return const Center(
                            child: Text('Kayıtlı kurye yok'),
                          );
                        }
                        return ListView.builder(
                          itemCount: couriers.length,
                          itemBuilder: (context, index) {
                            final courier = couriers[index];
                            final id = courier['id'] as String;
                            final isOnline =
                                courier['is_online'] as bool? ?? false;
                            final delivered =
                                (courier['delivered_count'] as num?)?.toInt() ??
                                0;
                            return RadioListTile<String>(
                              dense: true,
                              value: id,
                              groupValue: selectedCourierId,
                              onChanged: (isBusy || isPickup)
                                  ? null
                                  : (v) => setDialogState(
                                      () => selectedCourierId = v,
                                    ),
                              title: Text(
                                courier['full_name']?.toString() ??
                                    courier['username']?.toString() ??
                                    'Kurye',
                                style: const TextStyle(fontSize: 13),
                              ),
                              subtitle: Row(
                                children: [
                                  Icon(
                                    Icons.circle,
                                    size: 8,
                                    color: isOnline
                                        ? Colors.green
                                        : Colors.grey.shade400,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    isOnline ? 'Çevrimiçi' : 'Çevrimdışı',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  const SizedBox(width: 10),
                                  Text(
                                    '$delivered teslimat',
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: isBusy ? null : () => Navigator.pop(dialogContext),
                child: const Text('Kapat'),
              ),
              if (courierInfo != null && !isPickup)
                OutlinedButton.icon(
                  onPressed: isBusy ? null : cancelRouting,
                  icon: const Icon(Icons.link_off, size: 18),
                  label: const Text('Atamayı Kaldır'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.orange.shade800,
                  ),
                ),
              ElevatedButton.icon(
                onPressed: (isBusy || isPickup) ? null : route,
                icon: isBusy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send, size: 18),
                label: const Text('Kuryeye Gönder'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.indigo.shade600,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
