import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CourierQuickSettingsScreen extends StatefulWidget {
  final bool embedded;

  const CourierQuickSettingsScreen({super.key, this.embedded = false});

  @override
  State<CourierQuickSettingsScreen> createState() =>
      _CourierQuickSettingsScreenState();
}

class _CourierQuickSettingsScreenState extends State<CourierQuickSettingsScreen> {
  bool _enabled = false;
  bool _allowsUserRequests = false;
  bool _isLoading = true;
  dynamic _settingsId;

  final _commissionController = TextEditingController();
  final _baseFeeController = TextEditingController();
  final _perKmFeeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  @override
  void dispose() {
    _commissionController.dispose();
    _baseFeeController.dispose();
    _perKmFeeController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    try {
      final response = await Supabase.instance.client
          .from('courier_service_settings')
          .select()
          .limit(1)
          .maybeSingle();

      if (!mounted) return;
      if (response != null) {
        setState(() {
          _settingsId = response['id'];
          _enabled = response['enabled'] as bool? ?? false;
          _allowsUserRequests = response['allows_user_requests'] as bool? ?? false;
          _commissionController.text =
              ((response['commission_percent'] as num?)?.toDouble() ?? 20).toString();
          _baseFeeController.text =
              ((response['base_fee'] as num?)?.toDouble() ?? 15).toString();
          _perKmFeeController.text =
              ((response['per_km_fee'] as num?)?.toDouble() ?? 3).toString();
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Ayarlar yükleme hatası: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// Ayarları kaydeder. Başarı durumunda true, hata durumunda false döner
  /// (hata Snackbar'ı burada gösterilir; çağıran taraf false alırsa UI'ı geri alır).
  Future<bool> _updateSettings({Map<String, dynamic>? extra}) async {
    if (_settingsId == null) return false;
    try {
      final updated = await Supabase.instance.client
          .from('courier_service_settings')
          .update({
            'enabled': _enabled,
            'allows_user_requests': _allowsUserRequests,
            ...?extra,
          })
          .eq('id', _settingsId)
          .select();

      if ((updated as List).isEmpty) {
        throw Exception('Kayıt güncellenemedi (yetki veya id sorunu olabilir)');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ayarlar kaydedildi'),
            backgroundColor: Colors.green,
          ),
        );
      }
      return true;
    } catch (e) {
      debugPrint('Ayarlar güncellenirken hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
      return false;
    }
  }

  void _savePricing() {
    _updateSettings(extra: {
      'commission_percent': double.tryParse(_commissionController.text) ?? 20,
      'base_fee': double.tryParse(_baseFeeController.text) ?? 15,
      'per_km_fee': double.tryParse(_perKmFeeController.text) ?? 3,
    });
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final body = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('Kurye Servisi'),
                          subtitle: const Text('Kullanıcılar paket gönderebilsin'),
                          value: _enabled,
                          onChanged: (value) async {
                            final previous = _enabled;
                            setState(() => _enabled = value);
                            final ok = await _updateSettings();
                            // DB güncellenemediyse UI'ı eski duruma geri al.
                            if (!ok && mounted) setState(() => _enabled = previous);
                          },
                          activeThumbColor: primary,
                        ),
                        const Divider(),
                        SwitchListTile(
                          title: const Text('Tüm Kullanıcılara İzin Ver'),
                          subtitle: const Text('Herkes paket talebi gönderebilsin'),
                          value: _allowsUserRequests,
                          onChanged: _enabled
                              ? (value) async {
                                  final previous = _allowsUserRequests;
                                  setState(() => _allowsUserRequests = value);
                                  final ok = await _updateSettings();
                                  if (!ok && mounted) {
                                    setState(() => _allowsUserRequests = previous);
                                  }
                                }
                              : null,
                          activeThumbColor: primary,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Ücret ve Komisyon Ayarları',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Card(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextField(
                          controller: _commissionController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Admin Komisyonu (%)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _baseFeeController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Açılış Ücreti (₺)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _perKmFeeController,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'Kilometre Başı Ücret (₺)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _savePricing,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primary,
                              foregroundColor: Colors.white,
                            ),
                            child: const Text('Kaydet'),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );

    if (widget.embedded) return body;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kurye Servisi Ayarları'),
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      body: body,
    );
  }
}
