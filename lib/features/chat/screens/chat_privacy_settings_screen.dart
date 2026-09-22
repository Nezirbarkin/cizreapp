// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/services/privacy_service.dart';
import '../models/chat_presence.dart';
import '../services/presence_service.dart';
import '../services/user_presence_service.dart';

class ChatPrivacySettingsScreen extends StatefulWidget {
  const ChatPrivacySettingsScreen({super.key});

  @override
  State<ChatPrivacySettingsScreen> createState() => _ChatPrivacySettingsScreenState();
}

class _ChatPrivacySettingsScreenState extends State<ChatPrivacySettingsScreen> {
  final PrivacyService _privacyService = PrivacyService();
  // Çevrimiçi GÖRÜNME TERCİHİ (kalıcı, is_online_enabled sütunu).
  // Toggle bu değeri gösterir/günceller; app lifecycle bu tercihe saygı duyar.
  bool _isOnlineEnabled = true;
  bool _isGhostMode = false;
  bool _isLoading = true;

  // Son görülme / yazıyor tercihleri (sunucuda profiles'ta) ve yöneticinin
  // genel kuralları. Yönetici bir özelliği kapattıysa kullanıcıya söylenir;
  // ayarı yine kaydedilir ama özellik açılana kadar etkisi olmaz.
  ChatPrivacyPrefs _prefs = const ChatPrivacyPrefs();
  ChatPresenceSettings _adminSettings = const ChatPresenceSettings();
  bool _savingPrefs = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final isOnlineEnabled = await _privacyService.getOnlineEnabled();
      final isGhostMode = await _privacyService.getGhostMode();
      final prefs = await UserPresenceService.instance.loadMyPrivacy();
      final adminSettings = await UserPresenceService.instance.loadSettings();
      if (mounted) {
        setState(() {
          _isOnlineEnabled = isOnlineEnabled;
          _isGhostMode = isGhostMode;
          _prefs = prefs;
          _adminSettings = adminSettings;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Gizlilik ayarları yüklenirken hata: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _setOnlineStatus(bool value) async {
    setState(() => _isLoading = true);
    try {
      final success = await _privacyService.updateOnlineEnabled(value);
      if (success) {
        await PresenceService.instance.setOnlineEnabled(value);
      }
      if (success && mounted) {
        setState(() => _isOnlineEnabled = value);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Bir sohbet gizlilik tercihini kaydeder; başarısız olursa eski konuma döner.
  Future<void> _savePrefs(
    ChatPrivacyPrefs next, {
    LastSeenAudience? audience,
    bool? showTyping,
  }) async {
    if (_savingPrefs) return;
    final previous = _prefs;
    setState(() {
      _prefs = next;
      _savingPrefs = true;
    });
    try {
      await UserPresenceService.instance.saveMyPrivacy(
        lastSeenAudience: audience,
        showTypingIndicator: showTyping,
      );
    } catch (e) {
      debugPrint('Sohbet gizlilik tercihi kaydedilemedi: $e');
      if (!mounted) return;
      setState(() => _prefs = previous);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ayar kaydedilemedi, tekrar dene.'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _savingPrefs = false);
    }
  }

  Future<void> _setGhostMode(bool value) async {
    setState(() => _isLoading = true);
    try {
      final success = await _privacyService.updateGhostMode(value);
      if (success) {
        if (value) {
          await PresenceService.instance.setOnlineEnabled(false);
        }
        if (mounted) {
          setState(() {
            _isGhostMode = value;
            if (value) {
              _isOnlineEnabled = false;
            }
          });
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildAdminNotice(String text) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 18, color: Colors.orange[800]),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 12.5,
                height: 1.35,
                color: Colors.orange[900],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _audienceTile({
    required LastSeenAudience value,
    required IconData icon,
    required String title,
    required String subtitle,
    required Color accent,
  }) {
    final selected = _prefs.lastSeenAudience == value;
    return InkWell(
      onTap: _savingPrefs || selected
          ? null
          : () => _savePrefs(
              _prefs.copyWith(lastSeenAudience: value),
              audience: value,
            ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            Icon(icon, color: selected ? accent : Colors.grey),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12.5, color: Colors.grey[600]),
                  ),
                ],
              ),
            ),
            Icon(
              selected ? Icons.check_circle : Icons.radio_button_unchecked,
              color: selected ? accent : Colors.grey[400],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLastSeenCard(ThemeData theme, ThemeProvider themeProvider) {
    final accent = themeProvider.primaryColor;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                Icon(Icons.schedule_rounded, size: 20),
                SizedBox(width: 8),
                Text(
                  'Son görülmem',
                  style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              'Uygulamayı en son ne zaman kullandığını kimlerin görebileceğini seç.',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
          ),
          if (!_adminSettings.lastSeen)
            _buildAdminNotice(
              'Son görülme özelliği şu an yönetici tarafından kapalı; kimse '
              'kimsenin son görülmesini göremiyor. Seçimin kaydedilir ve özellik '
              'açılınca geçerli olur.',
            ),
          _audienceTile(
            value: LastSeenAudience.everyone,
            icon: Icons.public,
            title: 'Herkes',
            subtitle: 'Seni engellemeyen herkes görebilir',
            accent: accent,
          ),
          _audienceTile(
            value: LastSeenAudience.friends,
            icon: Icons.people_alt_outlined,
            title: 'Arkadaşlarım',
            subtitle: 'Yalnız karşılıklı takipleştiklerin',
            accent: accent,
          ),
          _audienceTile(
            value: LastSeenAudience.nobody,
            icon: Icons.visibility_off_outlined,
            title: 'Hiç kimse',
            subtitle: 'Son görülmen kimseye gösterilmez',
            accent: accent,
          ),
          if (_isGhostMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
              child: Text(
                'Hayalet modu açık olduğu için son görülmen şu an herkese gizli.',
                style: TextStyle(fontSize: 12.5, color: Colors.indigo[400]),
              ),
            )
          else
            const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildTypingCard(ThemeProvider themeProvider) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        children: [
          if (!_adminSettings.typing)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: _buildAdminNotice(
                '"Yazıyor…" göstergesi şu an yönetici tarafından kapalı. '
                'Seçimin kaydedilir ve özellik açılınca geçerli olur.',
              ),
            ),
          SwitchListTile(
            secondary: Icon(
              Icons.edit_note_rounded,
              color: _prefs.showTypingIndicator
                  ? themeProvider.primaryColor
                  : Colors.grey,
            ),
            title: const Text(
              '"Yazıyor…" bilgisini göster',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
            ),
            subtitle: Text(
              _prefs.showTypingIndicator
                  ? 'Sohbet ettiğin kişi yazdığını görebilir'
                  : 'Yazdığın kimseye gösterilmez',
              style: TextStyle(fontSize: 13, color: Colors.grey[600]),
            ),
            value: _prefs.showTypingIndicator,
            activeColor: themeProvider.primaryColor,
            onChanged: _savingPrefs
                ? null
                : (value) => _savePrefs(
                    _prefs.copyWith(showTypingIndicator: value),
                    showTyping: value,
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gizlilik & Durum'),
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 2,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                // Açıklama
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: theme.primaryColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: theme.primaryColor,
                        size: 24,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Gizlilik ayarlarınızı buradan yönetebilirsiniz',
                          style: TextStyle(
                            fontSize: 14,
                            color: theme.primaryColor,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),

                // Çevrimiçi Durum
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Opacity(
                    opacity: _isGhostMode ? 0.5 : 1.0,
                    child: SwitchListTile(
                      secondary: Icon(
                        _isOnlineEnabled ? Icons.circle : Icons.circle_outlined,
                        color: _isOnlineEnabled ? Colors.green : Colors.grey,
                      ),
                      title: Text(
                        'Çevrimiçi Durumum',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Text(
                        _isOnlineEnabled
                            ? 'Aktif görünüyorsun'
                            : 'Çevrimdışı görünüyorsun',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                      value: _isOnlineEnabled,
                      activeColor: themeProvider.primaryColor,
                      onChanged: (value) {
                        if (!_isGhostMode) {
                          _setOnlineStatus(value);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Hayalet Modu
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SwitchListTile(
                    secondary: Icon(
                      _isGhostMode ? Icons.visibility_off : Icons.visibility,
                      color: _isGhostMode ? Colors.indigo : Colors.grey,
                    ),
                    title: const Text(
                      'Hayalet Modu',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    subtitle: Text(
                      _isGhostMode
                          ? 'Kimse seni göremez'
                          : 'Aktif kullanıcı listesinde görünürsün',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                    ),
                    value: _isGhostMode,
                    activeColor: Colors.indigo,
                    onChanged: (value) {
                      _setGhostMode(value);
                    },
                  ),
                ),
                const SizedBox(height: 16),

                // Son görülme: kimler görebilir
                _buildLastSeenCard(theme, themeProvider),
                const SizedBox(height: 16),

                // Yazıyor bilgisi
                _buildTypingCard(themeProvider),
                const SizedBox(height: 24),

                // Bilgi Kartı
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.grey[100],
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            Icons.lightbulb_outline,
                            color: Colors.orange[700],
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Bilgi',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: Colors.orange[700],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Text(
                        '• Çevrimiçi durumu: Diğer kullanıcılar seni aktif olarak görebilir\n'
                        '• Hayalet modu: Kimse seni göremez ve sen de aktif kullanıcı listesinde görünmezsin\n'
                        '• Hayalet modu açıkken çevrimiçi durumu değiştiremezsin\n'
                        '• Son görülme: ${_adminSettings.lastSeenMaxDays} günden eski olan hiç gösterilmez; '
                        'engellediğin kişiler ve seni engelleyenler hiçbir durumunu göremez\n'
                        '• "Çevrimiçi durumum" kapalıyken uygulamayı kullandığın sürece son görülmen de gizli kalır',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[700],
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
