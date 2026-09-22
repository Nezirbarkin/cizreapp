// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/services/app_customization_prefs.dart';
import '../../../okey/okey.dart';

/// Yan menüdeki "Özelleştir" ekranı — hesap ayarlarından AYRI, tamamen cihaza
/// özel görünüm/davranış tikleri (sunucuya yazılmaz).
///
/// Buradaki her tık kendi anahtarını hemen kaydeder (ayrı bir "Kaydet"
/// düğmesi yok) — [OkeySoundService] ve [AppCustomizationPrefs]'teki diğer
/// anahtarlarla aynı desen.
class CustomizeScreen extends StatefulWidget {
  const CustomizeScreen({super.key});

  @override
  State<CustomizeScreen> createState() => _CustomizeScreenState();
}

class _CustomizeScreenState extends State<CustomizeScreen> {
  bool _isLoading = true;

  // Ses — OkeySoundService uygulama genelinde TEK örnektir; burada sadece
  // onun mevcut tercihini gösterip değiştiriyoruz.
  bool _musicEnabled = true;
  bool _soundEffectsEnabled = true;
  bool _voiceEnabled = true;

  // Arayüz. ("101 Okey" kısayolu ve müzik çalar kartı yan menüdeki GÖRÜNÜM
  // bölümüne taşındı — bkz. SettingsSidebar.)
  bool _hideCourierIcon = false;
  bool _hideSehiriciCard = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await OkeySoundService.instance.load();
    final hideCourierIcon = await AppCustomizationPrefs.getHideCourierIcon();
    final hideSehiriciCard =
        await AppCustomizationPrefs.getHideSehiriciCard();
    if (!mounted) return;
    setState(() {
      _musicEnabled = OkeySoundService.instance.isMusicEnabled;
      _soundEffectsEnabled = OkeySoundService.instance.isEnabled;
      _voiceEnabled = OkeySoundService.instance.isVoiceEnabled;
      _hideCourierIcon = hideCourierIcon;
      _hideSehiriciCard = hideSehiriciCard;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: themeProvider.primaryColor,
        elevation: 0,
        title: const Text(
          'Özelleştir',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSection(
                    title: 'Ses',
                    icon: Icons.volume_up_outlined,
                    color: Colors.deepPurple,
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('Arka Plan Müziği'),
                          subtitle: const Text(
                            'Kapalıyken uygulama genelinde şarkı çalmaz',
                          ),
                          value: _musicEnabled,
                          onChanged: (value) async {
                            setState(() => _musicEnabled = value);
                            await OkeySoundService.instance.setMusicEnabled(
                              value,
                            );
                          },
                          contentPadding: EdgeInsets.zero,
                          activeColor: Colors.deepPurple,
                        ),
                        SwitchListTile(
                          title: const Text('101 Okey Ses Efektleri'),
                          subtitle: const Text(
                            'Taş çekme, atma ve düğme sesleri',
                          ),
                          value: _soundEffectsEnabled,
                          onChanged: (value) async {
                            setState(() => _soundEffectsEnabled = value);
                            await OkeySoundService.instance.setEnabled(value);
                          },
                          contentPadding: EdgeInsets.zero,
                          activeColor: Colors.deepPurple,
                        ),
                        SwitchListTile(
                          title: const Text('101 Okey Sesli Anons'),
                          subtitle: const Text(
                            '"Seri açıldı", "Son üç taş" gibi anonslar',
                          ),
                          value: _voiceEnabled,
                          onChanged: (value) async {
                            setState(() => _voiceEnabled = value);
                            await OkeySoundService.instance.setVoiceEnabled(
                              value,
                            );
                          },
                          contentPadding: EdgeInsets.zero,
                          activeColor: Colors.deepPurple,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  _buildSection(
                    title: 'Arayüz',
                    icon: Icons.dashboard_customize_outlined,
                    color: Colors.teal,
                    child: Column(
                      children: [
                        SwitchListTile(
                          title: const Text('Kurye İkonunu Gizle'),
                          subtitle: const Text(
                            'Sohbet ikonunun üzerindeki "Paket Gönder" '
                            'moto kurye kısayolu görünmez',
                          ),
                          value: _hideCourierIcon,
                          onChanged: (value) async {
                            setState(() => _hideCourierIcon = value);
                            await AppCustomizationPrefs.setHideCourierIcon(
                              value,
                            );
                          },
                          contentPadding: EdgeInsets.zero,
                          activeColor: Colors.teal,
                        ),
                        SwitchListTile(
                          title: const Text('Şehiriçi Kartını Gizle'),
                          subtitle: const Text(
                            'Ana sayfadaki hikayeler satırının başındaki '
                            '"Şehiriçi" kısayolu görünmez',
                          ),
                          value: _hideSehiriciCard,
                          onChanged: (value) async {
                            setState(() => _hideSehiriciCard = value);
                            await AppCustomizationPrefs.setHideSehiriciCard(
                              value,
                            );
                          },
                          contentPadding: EdgeInsets.zero,
                          activeColor: Colors.teal,
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 80), // Alt boşluk
                ],
              ),
            ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}
