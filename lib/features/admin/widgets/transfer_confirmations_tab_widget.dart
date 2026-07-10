import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/services/transfer_service.dart';

/// Admin "Havale Onayları" sekmesi.
///
/// transfer_confirmations tablosundaki pending kayıtları listeler.
/// Onayla/Reddet butonları ile admin karar verir; onaylandığında DB
/// tarafında bakiye OTOMATİK eklenir + kullanıcıya notification gider.
///
/// İşlem:
/// - Onayla: TransferService.approveConfirmation → approve_transfer_confirmation RPC
///   → add_to_balance atomik → trigger ile notifications insert
/// - Reddet: TransferService.rejectConfirmation → reject_transfer_confirmation RPC
///   → trigger ile notifications insert (admin_note kullanıcıya iletilir)
class TransferConfirmationsTabWidget extends StatefulWidget {
  const TransferConfirmationsTabWidget({super.key});

  @override
  State<TransferConfirmationsTabWidget> createState() =>
      _TransferConfirmationsTabWidgetState();
}

class _TransferConfirmationsTabWidgetState
    extends State<TransferConfirmationsTabWidget> {
  final TransferService _service = TransferService();
  final NumberFormat _tl = NumberFormat.currency(
    locale: 'tr_TR',
    symbol: '₺',
    decimalDigits: 2,
  );
  final DateFormat _date = DateFormat('dd.MM.yyyy HH:mm');

  bool _isLoading = true;
  List<Map<String, dynamic>> _pending = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    try {
      final list = await _service.getPendingConfirmations();
      if (!mounted) return;
      setState(() {
        _pending = list;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Liste yüklenemedi: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _approve(Map<String, dynamic> item) async {
    final id = item['id'] as String;
    final amount = (item['amount'] as num).toDouble();

    // Onay öncesi son uyarı
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Havaleyi Onayla'),
        content: Text(
          '₺${amount.toStringAsFixed(2)} tutarındaki havaleyi onaylamak üzeresiniz. '
          'Onaylandığında kullanıcının bakiyesine OTOMATİK eklenecek ve '
          'bildirim gönderilecek.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Vazgeç'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Onayla'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    try {
      final result = await _service.approveConfirmation(confirmationId: id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Onaylandı. Kullanıcı bakiyesine ₺${amount.toStringAsFixed(2)} eklendi.',
          ),
          backgroundColor: Colors.green,
        ),
      );
      debugPrint('✅ approve result: $result');
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _reject(Map<String, dynamic> item) async {
    final id = item['id'] as String;
    final amount = (item['amount'] as num).toDouble();

    final adminNote = await showDialog<String?>(
      context: context,
      builder: (ctx) {
        final ctrl = TextEditingController();
        return AlertDialog(
          title: const Text('Havaleyi Reddet'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '₺${amount.toStringAsFixed(2)} tutarındaki havale reddedilecek. '
                'Kullanıcıya bildirim gidecek.',
              ),
              const SizedBox(height: 12),
              TextField(
                controller: ctrl,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Red Gerekçesi (kullanıcıya iletilecek)',
                  hintText: 'Örn: Tutar IBAN\'a yansımamış, dekont okunaksız',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Vazgeç'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('Reddet'),
            ),
          ],
        );
      },
    );
    if (adminNote == null || !mounted) return;

    try {
      await _service.rejectConfirmation(
        confirmationId: id,
        adminNote: adminNote.isEmpty ? null : adminNote,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reddedildi. Kullanıcıya bildirim gönderildi.'),
          backgroundColor: Colors.orange,
        ),
      );
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString()),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  String _userName(Map<String, dynamic> item) {
    final u = item['user'];
    if (u is Map) {
      return (u['full_name'] as String?) ?? 'Bilinmeyen kullanıcı';
    }
    return 'Bilinmeyen kullanıcı';
  }

  /// Bildirimi gönderen kişinin (havaleyi yapan) adı. UI'da en belirgin
  /// gösterilecek alan — admin'in onay kararı için kritik bilgi.
  /// Eski kayıtlarda null olabilir (migration öncesi), bu durumda
  /// "Belirtilmemiş" döner.
  String _senderName(Map<String, dynamic> item) {
    final s = item['sender_full_name'] as String?;
    if (s == null || s.trim().isEmpty) return 'Belirtilmemiş';
    return s.trim();
  }

  String _bankSummary(Map<String, dynamic> item) {
    // PostgREST join sözdizimi: bank_account:bank_accounts(...) → sonuç
    // 'bank_account' key'i altında döner. FK kolonu 'bank_account_id'
    // olduğu için isim çakışması olmaz.
    final b = item['bank_account'];
    if (b is Map) {
      final name = (b['bank_name'] as String?) ?? '-';
      final acc = (b['account_name'] as String?) ?? '';
      return '$name ${acc.isNotEmpty ? "($acc)" : ""}';
    }
    return 'Banka bilgisi yok';
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_pending.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'Bekleyen havale bildirimi yok',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('Yenile'),
              onPressed: _load,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        padding: const EdgeInsets.all(12),
        itemCount: _pending.length,
        itemBuilder: (context, i) {
          final item = _pending[i];
          final amount = (item['amount'] as num).toDouble();
          final created = DateTime.tryParse(item['created_at'] as String? ?? '');
          return Card(
            margin: const EdgeInsets.only(bottom: 12),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor: Colors.green.shade100,
                        child: Text(
                          _senderName(item).isNotEmpty &&
                                  _senderName(item) != 'Belirtilmemiş'
                              ? _senderName(item)[0].toUpperCase()
                              : '?',
                          style: TextStyle(
                            color: Colors.green.shade800,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Gönderen (havaleyi yapan) — en belirgin
                            Row(
                              children: [
                                Icon(Icons.person, size: 14, color: Colors.green.shade700),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    'Gönderen: ${_senderName(item)}',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 15,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            // Hesap sahibi (bildirim gönderen kullanıcı)
                            Text(
                              'Hesap: ${_userName(item)}',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              _bankSummary(item),
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        _tl.format(amount),
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Icon(Icons.access_time,
                          size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(
                        created != null ? _date.format(created) : '-',
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  if ((item['note'] as String?)?.isNotEmpty == true) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(Icons.note,
                              size: 14, color: Colors.grey.shade700),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              item['note'] as String,
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey.shade800,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _reject(item),
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('Reddet'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.red,
                            side: const BorderSide(color: Colors.red),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () => _approve(item),
                          icon: const Icon(Icons.check, size: 16),
                          label: const Text('Onayla'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.green,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}