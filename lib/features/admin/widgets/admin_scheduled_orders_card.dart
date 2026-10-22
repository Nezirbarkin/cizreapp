import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Admin > Ayarlar > Sipariş Kontrol altında "Randevulu Sipariş".
///
/// * Global anahtar (`app_about_settings.scheduled_orders_enabled`): kapalıyken
///   hiçbir mağazada randevu seçeneği çıkmaz, sunucu da randevulu siparişi
///   reddeder.
/// * Kurye öncesi süre (`scheduled_courier_lead_minutes`): randevulu sipariş
///   platform kuryesi havuzuna saatinden bu kadar dk önce düşer.
/// Mağaza bazında kapatma: Dükkanlar sekmesinde kart menüsü.
class AdminScheduledOrdersCard extends StatefulWidget {
  const AdminScheduledOrdersCard({super.key});

  static const List<int> leadOptions = [15, 30, 45, 60, 90, 120, 180];

  @override
  State<AdminScheduledOrdersCard> createState() => _AdminScheduledOrdersCardState();
}

class _AdminScheduledOrdersCardState extends State<AdminScheduledOrdersCard> {
  final SupabaseClient _db = Supabase.instance.client;
  bool _loading = true;
  bool _saving = false;
  bool _enabled = false;
  int _lead = 60;
  int? _shopCount;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final row = await _db
          .from('app_about_settings')
          .select('scheduled_orders_enabled, scheduled_courier_lead_minutes')
          .eq('id', 1)
          .maybeSingle();
      final count = await _db
          .from('shops')
          .select('id')
          .eq('scheduled_orders_enabled', true)
          .eq('scheduled_orders_admin_blocked', false)
          .count(CountOption.exact);
      if (!mounted) return;
      setState(() {
        _enabled = row?['scheduled_orders_enabled'] as bool? ?? false;
        final lead = (row?['scheduled_courier_lead_minutes'] as num?)?.toInt() ?? 60;
        _lead = AdminScheduledOrdersCard.leadOptions.contains(lead) ? lead : 60;
        _shopCount = count.count;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Ayarlar yüklenemedi: $e';
      });
    }
  }

  Future<void> _save({bool? enabled, int? lead}) async {
    final prevEnabled = _enabled;
    final prevLead = _lead;
    setState(() {
      _saving = true;
      _error = null;
      if (enabled != null) _enabled = enabled;
      if (lead != null) _lead = lead;
    });
    try {
      await _db.from('app_about_settings').update({
        'scheduled_orders_enabled': _enabled,
        'scheduled_courier_lead_minutes': _lead,
      }).eq('id', 1);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            enabled == null
                ? 'Kurye öncesi süre $_lead dk olarak kaydedildi'
                : (_enabled ? 'Randevulu sipariş açıldı' : 'Randevulu sipariş kapatıldı'),
          ),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _enabled = prevEnabled;
        _lead = prevLead;
        _error = 'Kaydedilemedi: $e';
      });
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: _loading
            ? const Center(child: Padding(padding: EdgeInsets.all(16), child: CircularProgressIndicator()))
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _enabled,
                    onChanged: _saving ? null : (v) => _save(enabled: v),
                    secondary: Icon(Icons.event_available,
                        color: _enabled ? Colors.deepPurple : Colors.grey),
                    title: const Text(
                      'Randevulu Sipariş',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      _enabled
                          ? 'Açık — ayarından izin veren mağazalarda müşteri ileri bir saat seçebilir'
                              '${_shopCount == null ? '' : ' (şu an $_shopCount mağaza)'}.'
                          : 'Kapalı — hiçbir mağazada randevu seçeneği görünmez.',
                    ),
                  ),
                  const Divider(),
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Platform kuryesi siparişi randevu saatinden kaç dk önce görsün?',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                      const SizedBox(width: 12),
                      DropdownButton<int>(
                        value: _lead,
                        onChanged: _saving ? null : (v) => v == null ? null : _save(lead: v),
                        items: [
                          for (final m in AdminScheduledOrdersCard.leadOptions)
                            DropdownMenuItem(value: m, child: Text('$m dk')),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Mağaza bazında kapatmak için: Dükkanlar → kart menüsü → "Randevulu sipariş".',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(_error!, style: TextStyle(color: Colors.red.shade700)),
                    ),
                ],
              ),
      ),
    );
  }
}
