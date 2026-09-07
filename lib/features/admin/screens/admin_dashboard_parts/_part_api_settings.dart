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
  // API ayarlari + Iyzico + S3 + API key + webhooks
  // ==========================================================================

  // --- _buildAPISettingsContent ---
  Widget _buildAPISettingsContent() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadAPISettings(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }

        final data = snapshot.data ?? {};
        final apiKeys = data['apiKeys'] as List<Map<String, dynamic>>? ?? [];
        final settings = data['settings'] as Map<String, dynamic>? ?? {};

        return RefreshIndicator(
          onRefresh: () async {
            setState(() {});
          },
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Başlık ve Yeni Anahtar Butonu
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'API Ayarları',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: () => _showCreateAPIKeyDialog(),
                      icon: const Icon(Icons.add),
                      label: const Text('Yeni Anahtar'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.purple.shade600,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // API Anahtarları Bölümü
                const Text(
                  'API Anahtarları',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (apiKeys.isEmpty)
                  Card(
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        children: [
                          Icon(
                            Icons.key_off,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Henüz API anahtarı yok',
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
                    itemCount: apiKeys.length,
                    itemBuilder: (context, index) {
                      final key = apiKeys[index];
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        elevation: 1,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(16),
                          leading: Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: key['is_active'] == true
                                  ? Colors.green.shade50
                                  : Colors.red.shade50,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.vpn_key,
                              color: key['is_active'] == true
                                  ? Colors.green.shade600
                                  : Colors.red.shade600,
                              size: 24,
                            ),
                          ),
                          title: Text(
                            key['name'] ?? 'API Anahtarı',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text(
                                'pk_${(key['key'] as String?)?.substring(0, 20) ?? '-'}...',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                  fontFamily: 'monospace',
                                ),
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
                                    'Oluşturuldu: ${_formatDate(key['created_at'])}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade500,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  if (key['last_used_at'] != null)
                                    Row(
                                      children: [
                                        Icon(
                                          Icons.check_circle,
                                          size: 12,
                                          color: Colors.green.shade500,
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          'Son Kullanım: ${_formatDate(key['last_used_at'])}',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: Colors.green.shade500,
                                          ),
                                        ),
                                      ],
                                    ),
                                ],
                              ),
                            ],
                          ),
                          trailing: PopupMenuButton<String>(
                            onSelected: (value) {
                              if (value == 'toggle') {
                                _toggleAPIKey(key);
                              } else if (value == 'regenerate') {
                                _regenerateAPIKey(key);
                              } else if (value == 'delete') {
                                _showDeleteAPIKeyDialog(key);
                              }
                            },
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'toggle',
                                child: Row(
                                  children: [
                                    Icon(Icons.power_settings_new, size: 18),
                                    SizedBox(width: 8),
                                    Text('Aç/Kapat'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'regenerate',
                                child: Row(
                                  children: [
                                    Icon(Icons.refresh, size: 18),
                                    SizedBox(width: 8),
                                    Text('Yenile'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.delete,
                                      size: 18,
                                      color: Colors.red,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Sil',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 24),

                // Güvenlik Ayarları
                const Text(
                  'Güvenlik Ayarları',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildInfoRow(
                          'Geçerli IP Adresleri',
                          settings['allowed_ips'] ?? 'Sınırlı yok',
                          Colors.blue,
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          title: const Text('HTTPS Zorunlu'),
                          subtitle: const Text(
                            'API istekleri sadece HTTPS üzerinden kabul et',
                          ),
                          value: settings['require_https'] ?? true,
                          onChanged: (value) {
                            _updateAPISetting('require_https', value);
                          },
                        ),
                        const SizedBox(height: 12),
                        SwitchListTile(
                          title: const Text('CORS Etkin'),
                          subtitle: const Text(
                            'Cross-Origin isteklerine izin ver',
                          ),
                          value: settings['cors_enabled'] ?? true,
                          onChanged: (value) {
                            _updateAPISetting('cors_enabled', value);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Rate Limiting
                const Text(
                  'Rate Limiting',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildInfoRow(
                          'Dakikalık İstek Limiti',
                          '${settings['requests_per_minute'] ?? 60}',
                          Colors.orange,
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow(
                          'Saatlik İstek Limiti',
                          '${settings['requests_per_hour'] ?? 10000}',
                          Colors.orange,
                        ),
                        const SizedBox(height: 12),
                        _buildInfoRow(
                          'Aylık İstek Limiti',
                          '${settings['requests_per_month'] ?? 500000}',
                          Colors.orange,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),

                // Webhooks
                const Text(
                  'Webhooks',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Card(
                  elevation: 1,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(Icons.webhook, color: Colors.orange.shade600),
                    ),
                    title: const Text('Webhook Yönetimi'),
                    subtitle: const Text(
                      'API olayları için webhook endpoints ayarla',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => _showWebhooksDialog(),
                  ),
                ),
                const SizedBox(height: 24),

                // Online Ödeme Ayarları (iyzico)
                const Text(
                  'Online Ödeme Ayarları (iyzico)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildIyzicoPaymentSettingsCard(data),

                const SizedBox(height: 24),

                // S3 Depolama Ayarları (idrive e2)
                const Text(
                  'S3 Depolama Ayarları',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                _buildS3StorageSettingsCard(data),

                const SizedBox(height: 24),

                // API İstatistikleri
                const Text(
                  'API İstatistikleri (Son 30 Gün)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.api,
                        title: 'Toplam İstek',
                        value: '${settings['total_requests'] ?? 0}',
                        color: Colors.blue,
                        gradient: [Colors.blue.shade400, Colors.blue.shade600],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.check_circle,
                        title: 'Başarılı',
                        value: '${settings['successful_requests'] ?? 0}',
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
                        icon: Icons.error,
                        title: 'Hata',
                        value: '${settings['failed_requests'] ?? 0}',
                        color: Colors.red,
                        gradient: [Colors.red.shade400, Colors.red.shade600],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- _buildIyzicoPaymentSettingsCard ---
  Widget _buildIyzicoPaymentSettingsCard(Map<String, dynamic> data) {
    return FutureBuilder<Map<String, dynamic>>(
      future: Supabase.instance.client
          .from('app_about_settings')
          .select('online_payment_enabled, iyzico_api_url')
          .single()
          .catchError(
            (_) => <String, dynamic>{
              'online_payment_enabled': true,
              'iyzico_api_url': 'https://sandbox-api.iyzipay.com',
            },
          ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            elevation: 1,
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final paySettings = snapshot.data ?? {};
        final isEnabled = paySettings['online_payment_enabled'] ?? true;
        final apiUrl =
            (paySettings['iyzico_api_url'] ?? 'https://sandbox-api.iyzipay.com')
                as String;

        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  title: const Text(
                    'Online Ödeme Aktif',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Kullanıcıların online ödeme yapabilmesi için iyzico entegrasyonunu açın',
                  ),
                  value: isEnabled,
                  onChanged: (value) async {
                    try {
                      await Supabase.instance.client
                          .from('app_about_settings')
                          .update({'online_payment_enabled': value})
                          .eq('id', 1);
                      setState(() {});
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Online ödeme ${value ? "aktif" : "pasif"} edildi',
                            ),
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
                  activeColor: Colors.purple,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      Icons.payment,
                      color: Colors.purple.shade600,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'iyzico API Bilgileri',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildInfoRow(
                  'API Kimlik Bilgileri',
                  'Supabase Edge Function Secrets ile yönetiliyor',
                  Colors.green,
                ),
                const SizedBox(height: 8),
                _buildInfoRow(
                  'API URL',
                  apiUrl.contains('sandbox')
                      ? 'Sandbox (Test)'
                      : 'Production (Canlı)',
                  apiUrl.contains('sandbox') ? Colors.orange : Colors.blue,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _showEditIyzicoDialog(apiUrl),
                    icon: const Icon(Icons.link),
                    label: const Text('iyzico Ortamını Düzenle'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.blue.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: Colors.blue.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'API Key ve Secret Key güvenlik nedeniyle uygulamaya gönderilmez. '
                          'Anahtarları Supabase Edge Function Secrets bölümünde IYZICO_API_KEY ve '
                          'IYZICO_SECRET_KEY olarak yönetin.\n\nSandbox: https://sandbox-api.iyzipay.com\n'
                          'Production: https://api.iyzipay.com',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- _showEditIyzicoDialog ---
  void _showEditIyzicoDialog(String currentApiUrl) {
    final apiUrlController = TextEditingController(text: currentApiUrl);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('iyzico Ortam Ayarı'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Gizli anahtarlar bu ekrandan okunamaz veya değiştirilemez. '
                'Supabase Edge Function Secrets kullanın.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: apiUrlController,
                decoration: const InputDecoration(
                  labelText: 'API URL',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.link),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final updateData = <String, dynamic>{};
                if (apiUrlController.text.trim().isNotEmpty) {
                  updateData['iyzico_api_url'] = apiUrlController.text.trim();
                }
                if (updateData.isNotEmpty) {
                  await Supabase.instance.client
                      .from('app_about_settings')
                      .update(updateData)
                      .eq('id', 1);
                }
                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('iyzico ayarları güncellendi'),
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

  // --- _showCreateAPIKeyDialog ---
  void _showCreateAPIKeyDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Yeni API Anahtarı Oluştur'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'Anahtar Adı',
                  hintText: 'örn: Mobile App',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Açıklama',
                  hintText: 'Bu anahtarın kullanım amacı',
                  border: OutlineInputBorder(),
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              if (nameController.text.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Anahtar adı gerekli')),
                );
                return;
              }

              try {
                final newKey = 'pk_${DateTime.now().millisecondsSinceEpoch}';

                await Supabase.instance.client.from('api_keys').insert({
                  'name': nameController.text.trim(),
                  'key': newKey,
                  'description': descriptionController.text.trim(),
                  'is_active': true,
                  'created_at': DateTime.now().toIso8601String(),
                });

                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('API anahtarı oluşturuldu: $newKey'),
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Hata: $e')));
                }
              }
            },
            child: const Text('Oluştur'),
          ),
        ],
      ),
    );
  }

  // --- _showDeleteAPIKeyDialog ---
  void _showDeleteAPIKeyDialog(Map<String, dynamic> key) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('API Anahtarını Sil'),
        content: Text(
          '${key['name']} API anahtarını silmek istediğinizden emin misiniz?\n\nBu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              try {
                await Supabase.instance.client
                    .from('api_keys')
                    .delete()
                    .eq('id', key['id']);

                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('API anahtarı silindi')),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Hata: $e')));
                }
              }
            },
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }

  // --- _toggleAPIKey ---
  void _toggleAPIKey(Map<String, dynamic> key) async {
    try {
      await Supabase.instance.client
          .from('api_keys')
          .update({'is_active': !(key['is_active'] ?? true)})
          .eq('id', key['id']);

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              (key['is_active'] ?? true)
                  ? 'Anahtar deaktive edildi'
                  : 'Anahtar aktive edildi',
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }

  // --- _regenerateAPIKey ---
  void _regenerateAPIKey(Map<String, dynamic> key) async {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('API Anahtarını Yenile'),
        content: const Text(
          'API anahtarını yenilemek istediğinizden emin misiniz?\n\nEski anahtar artık çalışmayacaktır.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final newKey = 'pk_${DateTime.now().millisecondsSinceEpoch}';

                await Supabase.instance.client
                    .from('api_keys')
                    .update({'key': newKey})
                    .eq('id', key['id']);

                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('API anahtarı yenilendi: $newKey'),
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
              } catch (e) {
                if (mounted) {
                  ScaffoldMessenger.of(
                    context,
                  ).showSnackBar(SnackBar(content: Text('Hata: $e')));
                }
              }
            },
            child: const Text('Yenile'),
          ),
        ],
      ),
    );
  }

  // --- _updateAPISetting ---
  void _updateAPISetting(String key, dynamic value) async {
    try {
      final settingsId = (await Supabase.instance.client
          .from('api_settings')
          .select('id')
          .single())['id'];

      await Supabase.instance.client
          .from('api_settings')
          .update({key: value})
          .eq('id', settingsId);

      if (mounted) {
        setState(() {});
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Ayar güncellendi')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }

  // --- _showWebhooksDialog ---
  void _showWebhooksDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Webhook Yönetimi'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Webhook Endpoint\'leri:',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    _buildWebhookItem('order.created', 'Sipariş oluşturuldu'),
                    _buildWebhookItem('order.completed', 'Sipariş tamamlandı'),
                    _buildWebhookItem(
                      'order.cancelled',
                      'Sipariş iptal edildi',
                    ),
                    _buildWebhookItem('payment.completed', 'Ödeme tamamlandı'),
                    _buildWebhookItem('payment.failed', 'Ödeme başarısız'),
                    _buildWebhookItem('user.created', 'Yeni kullanıcı'),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Yapılandır'),
          ),
        ],
      ),
    );
  }

  // --- _buildWebhookItem ---
  Widget _buildWebhookItem(String event, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Icon(Icons.webhook, size: 16, color: Colors.blue.shade600),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  event,
                  style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
                Text(
                  description,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- _buildS3StorageSettingsCard ---
  Widget _buildS3StorageSettingsCard(Map<String, dynamic> data) {
    return FutureBuilder<Map<String, dynamic>>(
      future: Supabase.instance.client
          .from('api_settings')
          .select(
            's3_enabled, s3_access_key, s3_secret_key, s3_bucket, s3_endpoint, s3_region, s3_public_url',
          )
          .single()
          .catchError(
            (_) => <String, dynamic>{
              's3_enabled': false,
              's3_access_key': '',
              's3_secret_key': '',
              's3_bucket': '',
              's3_endpoint': '',
              's3_region': 'us-east-1',
              's3_public_url': '',
            },
          ),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Card(
            elevation: 1,
            child: Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
          );
        }

        final s3Settings = snapshot.data ?? {};
        final isEnabled = s3Settings['s3_enabled'] ?? false;
        final accessKey = (s3Settings['s3_access_key'] ?? '') as String;
        final bucket = (s3Settings['s3_bucket'] ?? '') as String;
        final endpoint = (s3Settings['s3_endpoint'] ?? '') as String;
        final region = (s3Settings['s3_region'] ?? 'us-east-1') as String;

        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SwitchListTile(
                  title: const Text(
                    'S3 Storage Aktif',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Yeni dosyalar S3 uyumlu storage\'da (idrive e2 gibi) depolanır. Kapalıyken Supabase Storage kullanılır.',
                  ),
                  value: isEnabled,
                  onChanged: (value) async {
                    try {
                      await Supabase.instance.client
                          .from('api_settings')
                          .update({'s3_enabled': value})
                          .eq(
                            'id',
                            (await Supabase.instance.client
                                .from('api_settings')
                                .select('id')
                                .single())['id'],
                          );
                      setState(() {});
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'S3 Storage ${value ? "aktif" : "pasif"} edildi',
                            ),
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
                  activeColor: Colors.purple,
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Icon(
                      Icons.cloud_upload,
                      color: Colors.purple.shade600,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'S3 API Bilgileri',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Access Key', style: TextStyle(fontSize: 14)),
                      Text(
                        accessKey.isEmpty
                            ? 'Ayarlanmadı'
                            : '${accessKey.substring(0, accessKey.length > 10 ? 10 : accessKey.length)}...',
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.blue,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Bucket', style: TextStyle(fontSize: 14)),
                      Text(
                        bucket.isEmpty ? 'Ayarlanmadı' : bucket,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Endpoint', style: TextStyle(fontSize: 14)),
                      Text(
                        endpoint.isEmpty ? 'Ayarlanmadı' : endpoint,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.green,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Region', style: TextStyle(fontSize: 14)),
                      Text(
                        region,
                        style: const TextStyle(
                          fontSize: 14,
                          color: Colors.teal,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => _showS3SettingsDialog(s3Settings),
                    icon: const Icon(Icons.edit),
                    label: const Text('S3 Ayarlarını Düzenle'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.purple.shade600,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- _showS3SettingsDialog ---
  void _showS3SettingsDialog(Map<String, dynamic> currentSettings) {
    final accessKeyController = TextEditingController(
      text: currentSettings['s3_access_key'] ?? '',
    );
    final secretKeyController = TextEditingController(
      text: currentSettings['s3_secret_key'] ?? '',
    );
    final bucketController = TextEditingController(
      text: currentSettings['s3_bucket'] ?? '',
    );
    final endpointController = TextEditingController(
      text: currentSettings['s3_endpoint'] ?? '',
    );
    final regionController = TextEditingController(
      text: currentSettings['s3_region'] ?? 'us-east-1',
    );
    final publicUrlController = TextEditingController(
      text: currentSettings['s3_public_url'] ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('S3 Storage Ayarları'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: accessKeyController,
                decoration: const InputDecoration(
                  labelText: 'Access Key ID',
                  hintText: 'Örn: AKIAIOSFODNN7EXAMPLE',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: secretKeyController,
                decoration: const InputDecoration(
                  labelText: 'Secret Access Key',
                  hintText: 'Gizli anahtar',
                  border: OutlineInputBorder(),
                ),
                obscureText: true,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: bucketController,
                decoration: const InputDecoration(
                  labelText: 'Bucket Name',
                  hintText: 'Örn: cizreapp-storage',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: endpointController,
                decoration: const InputDecoration(
                  labelText: 'Endpoint URL',
                  hintText: 'Örn: s3.us-east-1.idrivee2.com',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: regionController,
                decoration: const InputDecoration(
                  labelText: 'Region',
                  hintText: 'Örn: us-east-1',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: publicUrlController,
                decoration: const InputDecoration(
                  labelText: 'Public URL (Opsiyonel)',
                  hintText: 'CDN URL varsa',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              try {
                final settingsId = (await Supabase.instance.client
                    .from('api_settings')
                    .select('id')
                    .single())['id'];

                await Supabase.instance.client
                    .from('api_settings')
                    .update({
                      's3_access_key': accessKeyController.text.trim(),
                      's3_secret_key': secretKeyController.text.trim(),
                      's3_bucket': bucketController.text.trim(),
                      's3_endpoint': endpointController.text.trim(),
                      's3_region': regionController.text.trim(),
                      's3_public_url': publicUrlController.text.trim(),
                    })
                    .eq('id', settingsId);

                if (context.mounted) {
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(context);
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('S3 ayarları kaydedildi'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  setState(() {});
                }
              } catch (e) {
                if (context.mounted) {
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
}
