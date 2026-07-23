import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class CourierQuickSettingsScreen extends StatefulWidget {
  const CourierQuickSettingsScreen({super.key});

  @override
  State<CourierQuickSettingsScreen> createState() =>
      _CourierQuickSettingsScreenState();
}

class _CourierQuickSettingsScreenState extends State<CourierQuickSettingsScreen> {
  bool _enabled = false;
  bool _allowsUserRequests = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final response = await Supabase.instance.client
          .from('courier_service_settings')
          .select()
          .limit(1)
          .maybeSingle();

      if (response != null) {
        setState(() {
          _enabled = response['enabled'] as bool? ?? false;
          _allowsUserRequests = response['allows_user_requests'] as bool? ?? false;
          _isLoading = false;
        });
      } else {
        setState(() => _isLoading = false);
      }
    } catch (e) {
      debugPrint('Ayarlar yükleme hatası: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _updateSettings() async {
    try {
      await Supabase.instance.client
          .from('courier_service_settings')
          .update({
            'enabled': _enabled,
            'allows_user_requests': _allowsUserRequests,
          })
          .limit(1);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Ayarlar kaydedildi'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Ayarlar güncellenirken hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kurye Servisi Ayarları'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
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
                            subtitle: const Text('Kullanıcılar kargo gönderebilsin'),
                            value: _enabled,
                            onChanged: (value) {
                              setState(() => _enabled = value);
                              _updateSettings();
                            },
                            activeThumbColor: Colors.teal,
                          ),
                          const Divider(),
                          SwitchListTile(
                            title: const Text('Tüm Kullanıcılara İzin Ver'),
                            subtitle: const Text('Herkes kargo talep gönderebilsin'),
                            value: _allowsUserRequests,
                            onChanged: _enabled
                                ? (value) {
                                    setState(() => _allowsUserRequests = value);
                                    _updateSettings();
                                  }
                                : null,
                            activeThumbColor: Colors.teal,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Teslimat Kartları',
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('Teslimat Seçenekleri'),
                              ElevatedButton.icon(
                                onPressed: () {
                                  // TODO: Yeni kart ekleme dialog'u
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                      content:
                                          Text('Henüz uygulanmadı (minimal)'),
                                    ),
                                  );
                                },
                                icon: const Icon(Icons.add),
                                label: const Text('Yeni'),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.teal,
                                  foregroundColor: Colors.white,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            '• Standart Teslimat (2-4 saat) - 15₺',
                            style: TextStyle(fontSize: 12),
                          ),
                          const Text(
                            '• Express Teslimat (30 dk) - BEDAVA (50₺+)',
                            style: TextStyle(fontSize: 12, color: Colors.green),
                          ),
                          const Text(
                            '• Same Day (6-8 saat) - 25₺',
                            style: TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
