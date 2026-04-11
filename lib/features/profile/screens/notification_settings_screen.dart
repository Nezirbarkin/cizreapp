// ignore_for_file: use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/notification_preferences_model.dart';
import '../../../core/services/notification_preferences_service.dart';

class NotificationSettingsScreen extends StatefulWidget {
  const NotificationSettingsScreen({super.key});

  @override
  State<NotificationSettingsScreen> createState() => _NotificationSettingsScreenState();
}

class _NotificationSettingsScreenState extends State<NotificationSettingsScreen> {
  final NotificationPreferencesService _preferencesService = NotificationPreferencesService();
  
  bool _isLoading = true;
  NotificationPreferences? _preferences;

  @override
  void initState() {
    super.initState();
    _loadPreferences();
  }

  Future<void> _loadPreferences() async {
    setState(() => _isLoading = true);
    
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final prefs = await _preferencesService.getUserPreferences(userId);
      setState(() {
        _preferences = prefs;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Tercihler yüklenirken hata: $e')),
        );
      }
    }
  }

  Future<void> _updatePreference(String type, bool value) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      switch (type) {
        case 'likes':
          await _preferencesService.updatePreferences(
            userId: userId,
            likesEnabled: value,
          );
          break;
        case 'comments':
          await _preferencesService.updatePreferences(
            userId: userId,
            commentsEnabled: value,
          );
          break;
        case 'followers':
          await _preferencesService.updatePreferences(
            userId: userId,
            followersEnabled: value,
          );
          break;
        case 'order_updates':
          await _preferencesService.updatePreferences(
            userId: userId,
            orderUpdatesEnabled: value,
          );
          break;
        case 'order_ready':
          await _preferencesService.updatePreferences(
            userId: userId,
            orderReadyEnabled: value,
          );
          break;
        case 'delivery':
          await _preferencesService.updatePreferences(
            userId: userId,
            deliveryEnabled: value,
          );
          break;
        case 'promotional':
          await _preferencesService.updatePreferences(
            userId: userId,
            promotionalEnabled: value,
          );
          break;
        case 'group_join_request':
          await _preferencesService.updatePreferences(
            userId: userId,
            groupJoinRequestsEnabled: value,
          );
          break;
        case 'group_member_joined':
          await _preferencesService.updatePreferences(
            userId: userId,
            groupMemberJoinedEnabled: value,
          );
          break;
      }
      
      await _loadPreferences();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Güncelleme hatası: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Bildirim Ayarları'),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _preferences == null
              ? const Center(child: Text('Tercihler yüklenemedi'))
              : ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    // Sosyal Bildirimler
                    _buildSectionHeader('Sosyal'),
                    _buildSwitchTile(
                      title: 'Beğeni Bildirimleri',
                      subtitle: 'Gönderileriniz beğenildiğinde bildirim alın',
                      icon: Icons.favorite,
                      iconColor: Colors.red,
                      value: _preferences!.likesEnabled,
                      onChanged: (value) => _updatePreference('likes', value),
                    ),
                    _buildSwitchTile(
                      title: 'Yorum Bildirimleri',
                      subtitle: 'Gönderilerinize yorum yapıldığında bildirim alın',
                      icon: Icons.comment,
                      iconColor: Colors.blue,
                      value: _preferences!.commentsEnabled,
                      onChanged: (value) => _updatePreference('comments', value),
                    ),
                    _buildSwitchTile(
                      title: 'Takipçi Bildirimleri',
                      subtitle: 'Yeni takipçileriniz olduğunda bildirim alın',
                      icon: Icons.person_add,
                      iconColor: Colors.green,
                      value: _preferences!.followersEnabled,
                      onChanged: (value) => _updatePreference('followers', value),
                    ),

                    _buildSwitchTile(
                      title: 'Bahsetme Bildirimleri',
                      subtitle: 'Birisi sizi bahsettiğinde bildirim alın',
                      icon: Icons.alternate_email,
                      iconColor: Colors.cyan,
                      value: _preferences!.mentionsEnabled,
                      onChanged: (value) {
                        final uid = Supabase.instance.client.auth.currentUser?.id;
                        if (uid != null) {
                          _preferencesService.updatePreferences(userId: uid, mentionsEnabled: value).then((_) => _loadPreferences());
                        }
                      },
                    ),

                    const SizedBox(height: 24),

                    // Grup Bildirimleri
                    _buildSectionHeader('Gruplar'),
                    _buildSwitchTile(
                      title: 'Katılma İstekleri',
                      subtitle: 'Birisi grubunuza katılmak istediğinde bildirim alın',
                      icon: Icons.person_add,
                      iconColor: Colors.indigo,
                      value: _preferences!.groupJoinRequestsEnabled,
                      onChanged: (value) => _updatePreference('group_join_request', value),
                    ),
                    _buildSwitchTile(
                      title: 'Yeni Üye Katılımı',
                      subtitle: 'Birisi grubunuza katıldığında bildirim alın',
                      icon: Icons.group_add,
                      iconColor: Colors.pink,
                      value: _preferences!.groupMemberJoinedEnabled,
                      onChanged: (value) => _updatePreference('group_member_joined', value),
                    ),

                    const SizedBox(height: 24),

                    // Sipariş Bildirimleri
                    _buildSectionHeader('Siparişler'),
                    _buildSwitchTile(
                      title: 'Sipariş Güncellemeleri',
                      subtitle: 'Sipariş durumu değiştiğinde bildirim alın',
                      icon: Icons.shopping_bag,
                      iconColor: Colors.orange,
                      value: _preferences!.orderUpdatesEnabled,
                      onChanged: (value) => _updatePreference('order_updates', value),
                    ),
                    _buildSwitchTile(
                      title: 'Sipariş Hazırlandı',
                      subtitle: 'Siparişiniz hazırlandığında bildirim alın',
                      icon: Icons.check_circle,
                      iconColor: Colors.teal,
                      value: _preferences!.orderReadyEnabled,
                      onChanged: (value) => _updatePreference('order_ready', value),
                    ),
                    _buildSwitchTile(
                      title: 'Teslimat Başladı',
                      subtitle: 'Siparişiniz yola çıktığında bildirim alın',
                      icon: Icons.local_shipping,
                      iconColor: Colors.purple,
                      value: _preferences!.deliveryEnabled,
                      onChanged: (value) => _updatePreference('delivery', value),
                    ),

                    const SizedBox(height: 24),

                    // Pazarlama
                    _buildSectionHeader('Pazarlama'),
                    _buildSwitchTile(
                      title: 'Promosyon Bildirimleri',
                      subtitle: 'İndirim ve kampanyalar hakkında bildirim alın',
                      icon: Icons.local_offer,
                      iconColor: Colors.amber,
                      value: _preferences!.promotionalEnabled,
                      onChanged: (value) => _updatePreference('promotional', value),
                    ),

                    const SizedBox(height: 32),

                    // Hızlı Eylemler
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Hızlı Eylemler',
                              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                            const SizedBox(height: 16),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final userId = Supabase.instance.client.auth.currentUser?.id;
                                if (userId != null) {
                                  await _preferencesService.toggleAllNotifications(userId, true);
                                  await _loadPreferences();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Tüm bildirimler açıldı')),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.notifications_active),
                              label: const Text('Tümünü Aç'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 48),
                              ),
                            ),
                            const SizedBox(height: 8),
                            OutlinedButton.icon(
                              onPressed: () async {
                                final userId = Supabase.instance.client.auth.currentUser?.id;
                                if (userId != null) {
                                  await _preferencesService.toggleAllNotifications(userId, false);
                                  await _loadPreferences();
                                  if (mounted) {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      const SnackBar(content: Text('Tüm bildirimler kapatıldı')),
                                    );
                                  }
                                }
                              },
                              icon: const Icon(Icons.notifications_off),
                              label: const Text('Tümünü Kapat'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(double.infinity, 48),
                                foregroundColor: Colors.red,
                                side: const BorderSide(color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8, top: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color iconColor,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: SwitchListTile(
        value: value,
        onChanged: onChanged,
        title: Text(title),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        secondary: Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            // ignore: deprecated_member_use
            color: iconColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: iconColor),
        ),
      ),
    );
  }
}
