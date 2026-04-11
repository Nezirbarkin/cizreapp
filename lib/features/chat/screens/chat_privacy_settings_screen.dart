// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/services/privacy_service.dart';

class ChatPrivacySettingsScreen extends StatefulWidget {
  const ChatPrivacySettingsScreen({super.key});

  @override
  State<ChatPrivacySettingsScreen> createState() => _ChatPrivacySettingsScreenState();
}

class _ChatPrivacySettingsScreenState extends State<ChatPrivacySettingsScreen> {
  final PrivacyService _privacyService = PrivacyService();
  bool _isOnline = true;
  bool _isGhostMode = false;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final isOnline = await _privacyService.getOnlineStatus();
      final isGhostMode = await _privacyService.getGhostMode();
      if (mounted) {
        setState(() {
          _isOnline = isOnline;
          _isGhostMode = isGhostMode;
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
      final success = await _privacyService.updateOnlineStatus(value);
      if (success && mounted) {
        setState(() => _isOnline = value);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _setGhostMode(bool value) async {
    setState(() => _isLoading = true);
    try {
      final success = await _privacyService.updateGhostMode(value);
      if (success && mounted) {
        setState(() {
          _isGhostMode = value;
          if (value) {
            _isOnline = false;
          }
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
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
                        _isOnline ? Icons.circle : Icons.circle_outlined,
                        color: _isOnline ? Colors.green : Colors.grey,
                      ),
                      title: Text(
                        'Çevrimiçi Durumum',
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
                      subtitle: Text(
                        _isOnline
                            ? 'Aktif görünüyorsun'
                            : 'Çevrimdışı görünüyorsun',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.grey[600],
                        ),
                      ),
                      value: _isOnline,
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
                        '• Hayalet modu açıkken çevrimiçi durumu değiştiremezsin',
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
