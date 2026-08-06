part of '../admin_dashboard_screen.dart';

extension on _AdminDashboardScreenState {
  // ==========================================================================
  // Ayarlar + siparis kontrol + duyuru
  // ==========================================================================

  // --- _buildSettingsContent ---
  Widget _buildSettingsContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Sipariş Kontrol Bölümü
          const Text(
            'Sipariş Kontrol',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildOrderControlCard(),

          const SizedBox(height: 24),

          // Açılış Duyurusu Bölümü
          const Text(
            'Açılış Duyurusu',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildStartupAnnouncementCard(),

          const SizedBox(height: 24),

          // Sistem Ayarları
          const Text(
            'Sistem Ayarları',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.cleaning_services),
                  title: const Text('Tüm Cache Temizle'),
                  subtitle: const Text('Tüm önbelleği sil'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await _cacheService.clearCache();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Cache temizlendi')),
                      );
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.delete_forever),
                  title: const Text('Tüm Analytics Temizle'),
                  subtitle: const Text('Tüm analitik verilerini sil'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () async {
                    await _analyticsService.clearAllEvents();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Analytics temizlendi')),
                      );
                    }
                  },
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.restore),
                  title: const Text('Metrikleri Sıfırla'),
                  subtitle: const Text('Performance metriklerini sıfırla'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    _performanceService.clearMetrics();
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Metrikler sıfırlandı')),
                      );
                    }
                  },
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- _buildOrderControlCard ---
  Widget _buildOrderControlCard() {
    return FutureBuilder<Map<String, dynamic>>(
      future: _loadOrderControlSettings(),
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

        if (snapshot.hasError) {
          return Card(
            elevation: 1,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Hata: ${snapshot.error}',
                style: const TextStyle(color: Colors.red),
              ),
            ),
          );
        }

        final isEnabled = snapshot.data?['global_orders_enabled'] ?? true;
        final approvalCodeEnabled =
            snapshot.data?['order_approval_code_enabled'] ?? true;

        return Card(
          elevation: 1,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Global Sipariş Alma - Daha belirgin tasarım
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isEnabled
                        ? Colors.green.shade50
                        : Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isEnabled ? Colors.green : Colors.red,
                      width: 2,
                    ),
                  ),
                  child: Row(
                    children: [
                      // Durum ikonu
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: isEnabled ? Colors.green : Colors.red,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          isEnabled ? Icons.store : Icons.store_mall_directory,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      // Metin ve açıklama
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Global Sipariş Alma',
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              isEnabled
                                  ? '✅ Açık - Tüm satıcılar sipariş alabilir'
                                  : '❌ Kapalı - Sipariş alma durduruldu!',
                              style: TextStyle(
                                color: isEnabled
                                    ? Colors.green.shade700
                                    : Colors.red.shade700,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                      ),
                      // Toggle switch
                      Switch(
                        value: isEnabled,
                        onChanged: (value) async {
                          try {
                            await Supabase.instance.client
                                .from('app_about_settings')
                                .update({'global_orders_enabled': value})
                                .eq('id', 1);
                            setState(() {});
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    value
                                        ? '✅ Sipariş alma açıldı'
                                        : '❌ Sipariş alma kapatıldı',
                                  ),
                                  backgroundColor: value
                                      ? Colors.green
                                      : Colors.red,
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
                        activeColor: Colors.green,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                const Divider(height: 1),
                // Sipariş Onay Kodu Toggle
                SwitchListTile(
                  title: const Text(
                    'Sipariş Onay Kodu',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    approvalCodeEnabled
                        ? 'Sipariş verirken onay kodu gereklidir'
                        : 'Sipariş onay kodu zorunluluğu kapatıldı',
                    style: TextStyle(
                      color: approvalCodeEnabled ? Colors.blue : Colors.grey,
                    ),
                  ),
                  value: approvalCodeEnabled,
                  onChanged: (value) async {
                    try {
                      await Supabase.instance.client
                          .from('app_about_settings')
                          .update({'order_approval_code_enabled': value})
                          .eq('id', 1);
                      setState(() {});
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              value
                                  ? 'Onay kodu açıldı'
                                  : 'Onay kodu kapatıldı',
                            ),
                            backgroundColor: value
                                ? Colors.blue
                                : Colors.orange,
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
                  activeColor: Colors.blue,
                  contentPadding: EdgeInsets.zero,
                ),
                if (!isEnabled)
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.red.shade700,
                          size: 22,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Dikkat: Tüm mağazalarda sipariş alma durdurulmuş durumda. '
                            'Müşteriler hiçbir mağazadan sipariş veremez.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.red.shade700,
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

  // --- _buildStartupAnnouncementCard ---
  Widget _buildStartupAnnouncementCard() {
    return FutureBuilder<Map<String, dynamic>>(
      future: Supabase.instance.client
          .from('app_about_settings')
          .select(
            'startup_announcement_enabled, startup_announcement_title, startup_announcement_message, startup_announcement_type, startup_announcement_button_text',
          )
          .single()
          .catchError(
            (_) => <String, dynamic>{
              'startup_announcement_enabled': false,
              'startup_announcement_title': '',
              'startup_announcement_message': '',
              'startup_announcement_type': 'info',
              'startup_announcement_button_text': 'Tamam',
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

        final announcementData = snapshot.data ?? {};
        final isEnabled =
            announcementData['startup_announcement_enabled'] ?? false;
        final title =
            (announcementData['startup_announcement_title'] ?? '') as String;
        final message =
            (announcementData['startup_announcement_message'] ?? '') as String;
        final type =
            (announcementData['startup_announcement_type'] ?? 'info') as String;
        final buttonText =
            (announcementData['startup_announcement_button_text'] ?? 'Tamam')
                as String;

        Color getColor(String t) {
          switch (t) {
            case 'warning':
              return Colors.orange;
            case 'success':
              return Colors.green;
            case 'error':
              return Colors.red;
            default:
              return Colors.blue;
          }
        }

        IconData getIcon(String t) {
          switch (t) {
            case 'warning':
              return Icons.warning;
            case 'success':
              return Icons.check_circle;
            case 'error':
              return Icons.error;
            default:
              return Icons.info;
          }
        }

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
                    'Duyuru Aktif',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text(
                    'Uygulama açılışında kullanıcılara bilgilendirme/not gösterilir',
                  ),
                  value: isEnabled,
                  onChanged: (value) async {
                    try {
                      await Supabase.instance.client
                          .from('app_about_settings')
                          .update({
                            'startup_announcement_enabled': value,
                            if (value)
                              'startup_announcement_updated_at': DateTime.now()
                                  .toIso8601String(),
                          })
                          .eq('id', 1);
                      setState(() {});
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              'Duyuru ${value ? "aktif" : "pasif"} edildi',
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
                  activeColor: Colors.orange,
                  contentPadding: EdgeInsets.zero,
                ),
                if (isEnabled) ...[
                  const SizedBox(height: 16),
                  const Divider(),
                  const SizedBox(height: 12),
                  // Önizleme
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: getColor(type).withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: getColor(type).withValues(alpha: 0.3),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              getIcon(type),
                              color: getColor(type),
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Önizleme',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: getColor(type),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          title.isNotEmpty ? title : 'Başlık',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          message.isNotEmpty
                              ? message
                              : 'Mesaj içeriği burada görünecek...',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Buton: $buttonText',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade500,
                            fontStyle: FontStyle.italic,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showEditAnnouncementDialog(
                        title,
                        message,
                        type,
                        buttonText,
                      ),
                      icon: const Icon(Icons.edit),
                      label: const Text('Duyuruyu Düzenle'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  // --- _showEditAnnouncementDialog ---
  void _showEditAnnouncementDialog(
    String currentTitle,
    String currentMessage,
    String currentType,
    String currentButton,
  ) {
    final titleController = TextEditingController(text: currentTitle);
    final messageController = TextEditingController(text: currentMessage);
    final buttonController = TextEditingController(text: currentButton);
    String selectedType = currentType;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Açılış Duyurusunu Düzenle'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Duyuru Başlığı',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.title),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: messageController,
                  decoration: const InputDecoration(
                    labelText: 'Duyuru Mesajı',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.message),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: buttonController,
                  decoration: const InputDecoration(
                    labelText: 'Buton Metni (varsayılan: Tamam)',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.smart_button),
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Duyuru Tipi',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    _buildTypeChip(
                      selectedType,
                      'info',
                      'Bilgi',
                      Icons.info,
                      Colors.blue,
                      (t) {
                        setDialogState(() => selectedType = t);
                      },
                    ),
                    _buildTypeChip(
                      selectedType,
                      'warning',
                      'Uyarı',
                      Icons.warning,
                      Colors.orange,
                      (t) {
                        setDialogState(() => selectedType = t);
                      },
                    ),
                    _buildTypeChip(
                      selectedType,
                      'success',
                      'Başarılı',
                      Icons.check_circle,
                      Colors.green,
                      (t) {
                        setDialogState(() => selectedType = t);
                      },
                    ),
                    _buildTypeChip(
                      selectedType,
                      'error',
                      'Hata',
                      Icons.error,
                      Colors.red,
                      (t) {
                        setDialogState(() => selectedType = t);
                      },
                    ),
                  ],
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
                  await Supabase.instance.client
                      .from('app_about_settings')
                      .update({
                        'startup_announcement_title': titleController.text
                            .trim(),
                        'startup_announcement_message': messageController.text
                            .trim(),
                        'startup_announcement_type': selectedType,
                        'startup_announcement_button_text':
                            buttonController.text.trim().isEmpty
                            ? 'Tamam'
                            : buttonController.text.trim(),
                        'startup_announcement_updated_at': DateTime.now()
                            .toIso8601String(),
                      })
                      .eq('id', 1);
                  if (mounted) {
                    Navigator.pop(context);
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Duyuru güncellendi'),
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
      ),
    );
  }

  // --- _buildTypeChip ---
  Widget _buildTypeChip(
    String current,
    String type,
    String label,
    IconData icon,
    Color color,
    Function(String) onSelect,
  ) {
    final isSelected = current == type;
    return FilterChip(
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: isSelected ? Colors.white : color),
          const SizedBox(width: 4),
          Text(label),
        ],
      ),
      selected: isSelected,
      onSelected: (selected) {
        if (selected) onSelect(type);
      },
      selectedColor: color,
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : Colors.black87,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
      checkmarkColor: Colors.white,
    );
  }

  // --- _showSendNotificationDialog ---
  void _showSendNotificationDialog() {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    String targetAudience = 'all';

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Bildirim Gönder'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Başlık',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bodyController,
                  decoration: const InputDecoration(
                    labelText: 'Mesaj',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  value: targetAudience,
                  decoration: const InputDecoration(
                    labelText: 'Hedef Kitle',
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                      value: 'all',
                      child: Text('Tüm Kullanıcılar'),
                    ),
                    DropdownMenuItem(
                      value: 'customers',
                      child: Text('Müşteriler'),
                    ),
                    DropdownMenuItem(value: 'admins', child: Text('Adminler')),
                  ],
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => targetAudience = value);
                    }
                  },
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
                if (titleController.text.isEmpty ||
                    bodyController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Tüm alanları doldurun')),
                  );
                  return;
                }

                try {
                  // Bulk notification için tüm kullanıcılara gönder.
                  // 20260803000006 sonrasında profiles üzerinde
                  // authenticated SELECT policy'si yok; SECURITY DEFINER
                  // admin_profiles_minimal RPC üzerinden alıyoruz.
                  final usersResponse = await Supabase.instance.client
                      .rpc<List<dynamic>>('admin_profiles_minimal', params: {
                    'p_user_ids': null,
                  });

                  if (usersResponse.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Kullanıcı bulunamadı')),
                    );
                    return;
                  }

                  for (var user in usersResponse) {
                    await Supabase.instance.client.from('notifications').insert(
                      {
                        'user_id': user['id'],
                        'type': 'shop', // Admin notification type
                        'title': titleController.text.trim(),
                        'content': bodyController.text.trim(),
                        'is_read': false,
                      },
                    );
                  }

                  if (mounted) {
                    Navigator.pop(context);
                    setState(() {});
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Bildirim gönderildi')),
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
              child: const Text('Gönder'),
            ),
          ],
        ),
      ),
    );
  }
}
