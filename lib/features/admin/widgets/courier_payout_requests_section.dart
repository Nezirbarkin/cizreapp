// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Kurye ödeme isteklerini listeleyip onaylama/reddetme kartı.
///
/// Hem "Kurye Yönetimi" sekmesinde hem de "Ödemeler" hub'ının "Kurye
/// Kazançları" sekmesinde aynı canlı veri/aksiyonlarla kullanılır (tek
/// kaynak — iki yerde ayrı sorgu/mutasyon mantığı tutulmaz).
class CourierPayoutRequestsSection extends StatefulWidget {
  const CourierPayoutRequestsSection({super.key});

  @override
  State<CourierPayoutRequestsSection> createState() =>
      _CourierPayoutRequestsSectionState();
}

class _CourierPayoutRequestsSectionState
    extends State<CourierPayoutRequestsSection> {
  late Future<List<Map<String, dynamic>>> _payoutsFuture;

  @override
  void initState() {
    super.initState();
    _payoutsFuture = _loadCourierPayouts();
  }

  void _refresh() {
    setState(() {
      _payoutsFuture = _loadCourierPayouts();
    });
  }

  Future<List<Map<String, dynamic>>> _loadCourierPayouts() async {
    try {
      final response = await Supabase.instance.client
          .from('courier_payout_requests')
          .select('''
            id,
            amount,
            status,
            requested_at,
            approved_at,
            courier_id,
            profiles:courier_id(full_name, username)
          ''')
          .order('requested_at', ascending: false)
          .limit(50);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Kurye odeme istekleri yuklenirken hata: $e');
      return [];
    }
  }

  String _formatDate(dynamic date) {
    if (date == null) return '-';
    try {
      final dateTime = DateTime.parse(date.toString());
      return '${dateTime.day}/${dateTime.month}/${dateTime.year}';
    } catch (e) {
      return '-';
    }
  }

  // Sunucu 'APP:<kod> | <aciklama>' bicimli hatalar firlatiyor. Ham
  // PostgrestException metnini gostermek yerine anlasilir karsiligi verilir.
  String _readableRpcError(Object error) {
    final raw = error is PostgrestException ? error.message : error.toString();
    final match = RegExp(r'APP:([a-z_]+)').firstMatch(raw);
    return switch (match?.group(1)) {
      'forbidden' => 'Bu işlem için admin yetkisi gerekiyor.',
      'not_found' => 'Ödeme isteği bulunamadı.',
      'invalid_state' =>
        'Bu ödeme isteği artık beklemede değil (başka bir admin işlem yapmış olabilir).',
      'payout_id_required' => 'Ödeme isteği kimliği eksik.',
      'open_payout_exists' => 'Kuryenin zaten bekleyen bir ödeme isteği var.',
      'no_pending_earnings' => 'Kuryenin bekleyen kazancı yok.',
      _ => raw,
    };
  }

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
      final referenceController = TextEditingController();
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
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
              const SizedBox(height: 12),
              TextField(
                controller: referenceController,
                decoration: const InputDecoration(
                  labelText: 'Ödeme Referansı (Havale Dekont No / Açıklama)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Iptal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text('Onayla'),
            ),
          ],
        ),
      );

      final paymentReference = referenceController.text.trim();
      if (confirmed != true) {
        referenceController.dispose();
        return;
      }

      // Sunucu-otoriteli onay: payout header + items + earnings status +
      // timestamp + bildirim tek transaction'da. İstemci doğrudan tablo
      // yazmaz; sadece RPC çağırır.
      try {
        await Supabase.instance.client.rpc(
          'admin_approve_courier_payout',
          params: {
            'p_payout_id': payoutId,
            'p_payment_reference': paymentReference.isEmpty
                ? null
                : paymentReference,
          },
        );
      } catch (e) {
        debugPrint('Payout onaylama hatasi: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Hata: ${_readableRpcError(e)}'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      } finally {
        referenceController.dispose();
      }

      if (mounted) {
        _refresh();
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

  // admin_reject_courier_payout RPC'si 20260817000017 ile olusturulmustu ama
  // Dart tarafinda hicbir cagri yeri yoktu: admin bir odeme istegini
  // reddedemiyordu. Red, kazanclari 'pending'e geri dondurdugu icin kuryenin
  // yeniden talep olusturabilmesinin de tek yoludur.
  Future<void> _rejectCourierPayout(
    String payoutId,
    String courierName,
    double amount,
  ) async {
    final reasonController = TextEditingController();
    try {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ödeme İsteğini Reddet'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Kurye: $courierName'),
              Text('Tutar: ₺${amount.toStringAsFixed(2)}'),
              const SizedBox(height: 12),
              const Text(
                'Reddedilen istekteki kazançlar kuryenin bekleyen '
                'alacağına geri döner.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(
                  labelText: 'Red gerekçesi',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                maxLines: 2,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(ctx, true),
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
      final reason = reasonController.text.trim();

      await Supabase.instance.client.rpc(
        'admin_reject_courier_payout',
        params: {
          'p_payout_id': payoutId,
          'p_reason': reason.isEmpty ? null : reason,
        },
      );

      if (mounted) {
        _refresh();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$courierName ödeme isteği reddedildi'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Payout reddetme hatasi: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: ${_readableRpcError(e)}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      reasonController.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const Spacer(),
                ElevatedButton.icon(
                  onPressed: _refresh,
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
              future: _payoutsFuture,
              builder: (context, payoutSnapshot) {
                if (payoutSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final payouts = payoutSnapshot.data ?? [];
                if (payouts.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        'Bekleyen ödeme isteği yok',
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  );
                }
                return Column(
                  children: payouts.map((payout) {
                    final status = payout['status'] as String? ?? 'pending';
                    final amount =
                        (payout['amount'] as num?)?.toDouble() ?? 0.0;
                    final courierName =
                        payout['profiles']?['full_name'] ??
                        payout['profiles']?['username'] ??
                        'Kurye';
                    final statusColor = switch (status) {
                      'pending' => Colors.orange,
                      'approved' => Colors.blue,
                      'paid' => Colors.green,
                      'rejected' => Colors.red,
                      'cancelled' => Colors.grey,
                      _ => Colors.grey,
                    };
                    final statusText = switch (status) {
                      'pending' => 'Bekliyor',
                      'approved' => 'Onaylandı',
                      'paid' => 'Ödendi',
                      'rejected' => 'Reddedildi',
                      'cancelled' => 'İptal edildi',
                      _ => status,
                    };

                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
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
                                        ? _formatDate(payout['requested_at'])
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
                                borderRadius: BorderRadius.circular(20),
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
                                    _approveCourierPayout(payout['id']),
                                tooltip: 'Onayla',
                              ),
                              IconButton(
                                icon: const Icon(
                                  Icons.cancel,
                                  color: Colors.red,
                                ),
                                onPressed: () => _rejectCourierPayout(
                                  payout['id'],
                                  courierName,
                                  amount,
                                ),
                                tooltip: 'Reddet',
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
    );
  }
}
