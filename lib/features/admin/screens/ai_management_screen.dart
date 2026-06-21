// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/ai_settings_model.dart';
import '../../ai_chat/services/ai_chat_service.dart';

/// Admin Yapay Zeka Yönetimi Ekranı
/// 
/// Bu ekran admin panelinde Yapay Zeka Yönetimi menüsünden erişilir
/// ve AI sohbet sisteminin ayarlarını yönetmeye olanak tanır.
class AIManagementScreen extends StatefulWidget {
  const AIManagementScreen({super.key});

  @override
  State<AIManagementScreen> createState() => _AIManagementScreenState();
}

class _AIManagementScreenState extends State<AIManagementScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final _aiService = AIChatService();

  bool _isLoading = true;
  bool _isSaving = false;
  AISettings? _settings;
  AIUsageStats? _stats;

  // API Key controllers
  final _geminiKeyController = TextEditingController();
  final _groqKeyController = TextEditingController();
  final _openrouterKeyController = TextEditingController();
  final _openaiKeyController = TextEditingController();
  final _huggingfaceKeyController = TextEditingController();

  // Settings controllers
  final _systemPromptController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _geminiKeyController.dispose();
    _groqKeyController.dispose();
    _openrouterKeyController.dispose();
    _openaiKeyController.dispose();
    _huggingfaceKeyController.dispose();
    _systemPromptController.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _settings = await _aiService.getSettings();
      _stats = await _aiService.getUsageStats(days: 7);

      // Controllers'ları doldur
      _geminiKeyController.text = _settings?.geminiApiKey ?? '';
      _groqKeyController.text = _settings?.groqApiKey ?? '';
      _openrouterKeyController.text = _settings?.openrouterApiKey ?? '';
      _openaiKeyController.text = _settings?.openaiApiKey ?? '';
      _huggingfaceKeyController.text = _settings?.huggingfaceApiKey ?? '';
      _systemPromptController.text = _settings?.systemPrompt ?? '';
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Veri yüklenemedi: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveSettings() async {
    if (_settings == null) return;

    setState(() => _isSaving = true);
    try {
      final updatedSettings = _settings!.copyWith(
        geminiApiKey: _geminiKeyController.text.trim().isEmpty ? null : _geminiKeyController.text.trim(),
        groqApiKey: _groqKeyController.text.trim().isEmpty ? null : _groqKeyController.text.trim(),
        openrouterApiKey: _openrouterKeyController.text.trim().isEmpty ? null : _openrouterKeyController.text.trim(),
        openaiApiKey: _openaiKeyController.text.trim().isEmpty ? null : _openaiKeyController.text.trim(),
        huggingfaceApiKey: _huggingfaceKeyController.text.trim().isEmpty ? null : _huggingfaceKeyController.text.trim(),
        systemPrompt: _systemPromptController.text.trim(),
      );

      await _aiService.updateSettings(updatedSettings);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Ayarlar kaydedildi'), backgroundColor: Colors.green),
        );
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kaydetme hatası: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yapay Zeka Yönetimi'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.white,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          tabs: const [
            Tab(icon: Icon(Icons.settings), text: 'Ayarlar'),
            Tab(icon: Icon(Icons.analytics), text: 'İstatistikler'),
            Tab(icon: Icon(Icons.quickreply), text: 'Hazır Komutlar'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildSettingsTab(),
                _buildStatsTab(),
                _buildPromptsTab(),
              ],
            ),
    );
  }

  /// Ayarlar sekmesi
  Widget _buildSettingsTab() {
    if (_settings == null) return const Center(child: Text('Ayarlar yüklenemedi'));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Genel Durum
          _buildCard(
            title: 'Genel Durum',
            icon: Icons.power_settings_new,
            children: [
              SwitchListTile(
                title: const Text('Yapay Zeka Aktif'),
                subtitle: const Text('AI sohbet özelliğini açın/kapatın'),
                value: _settings!.enabled,
                activeColor: Colors.deepPurple,
                onChanged: (value) {
                  setState(() {
                    _settings = _settings!.copyWith(enabled: value);
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 16),

          // API Anahtarları
          _buildCard(
            title: 'API Anahtarları',
            icon: Icons.vpn_key,
            children: [
              _buildApiKeyField(
                label: 'Gemini API Key',
                controller: _geminiKeyController,
                isSet: _settings!.geminiKeySet,
                helperText: 'Google Gemini için API anahtarı',
              ),
              const Divider(),
              _buildApiKeyField(
                label: 'Groq API Key',
                controller: _groqKeyController,
                isSet: _settings!.groqKeySet,
                helperText: 'Groq için API anahtarı',
              ),
              const Divider(),
              _buildApiKeyField(
                label: 'OpenRouter API Key',
                controller: _openrouterKeyController,
                isSet: _settings!.openrouterKeySet,
                helperText: 'OpenRouter için API anahtarı',
              ),
              const Divider(),
              _buildApiKeyField(
                label: 'OpenAI API Key',
                controller: _openaiKeyController,
                isSet: _settings!.openaiKeySet,
                helperText: 'OpenAI için API anahtarı',
              ),
              const Divider(),
              _buildApiKeyField(
                label: 'HuggingFace API Key',
                controller: _huggingfaceKeyController,
                isSet: _settings!.huggingfaceKeySet,
                helperText: 'HuggingFace için API anahtarı (opsiyonel - ücretsiz)',
              ),
              const Divider(height: 24),
              // Ücretsiz sağlayıcılar bilgilendirme
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.green.shade700, size: 20),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Pollinations ve HuggingFace ücretsiz sağlayıcılardır ve API anahtarı gerektirmez.',
                        style: TextStyle(color: Colors.green.shade900, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveSettings,
                  icon: _isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text('API Anahtarlarını Kaydet'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Sağlayıcı Seçimi
          _buildCard(
            title: 'Varsayılan Sağlayıcı',
            icon: Icons.cloud,
            children: [
              _buildProviderDropdown('Metin Üretimi', _settings!.textProvider ?? _settings!.provider, (value) {
                setState(() {
                  _settings = _settings!.copyWith(textProvider: value);
                });
              }),
              const SizedBox(height: 12),
              _buildProviderDropdown('Görüntü Anlama', _settings!.visionProvider ?? _settings!.provider, (value) {
                setState(() {
                  _settings = _settings!.copyWith(visionProvider: value);
                });
              }),
              const SizedBox(height: 12),
              _buildProviderDropdown('Görüntü Üretimi', _settings!.imageProvider ?? _settings!.provider, (value) {
                setState(() {
                  _settings = _settings!.copyWith(imageProvider: value);
                });
              }),
              const Divider(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveSettings,
                  icon: _isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text('Sağlayıcı Ayarlarını Kaydet'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Limit Ayarları
          _buildCard(
            title: 'Kullanım Limitleri',
            icon: Icons.speed,
            children: [
              ListTile(
                title: const Text('Günlük İstek Limiti (Kullanıcı Başına)'),
                subtitle: Text('${_settings!.dailyRequestLimitPerUser} istek/gün'),
                trailing: SizedBox(
                  width: 100,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    controller: TextEditingController(text: _settings!.dailyRequestLimitPerUser.toString()),
                    onChanged: (value) {
                      final limit = int.tryParse(value);
                      if (limit != null) {
                        setState(() {
                          _settings = _settings!.copyWith(dailyRequestLimitPerUser: limit);
                        });
                      }
                    },
                  ),
                ),
              ),
              ListTile(
                title: const Text('Günlük Token Limiti (Kullanıcı Başına)'),
                subtitle: Text('${_settings!.dailyTokenLimitPerUser} token/gün'),
                trailing: SizedBox(
                  width: 100,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    controller: TextEditingController(text: _settings!.dailyTokenLimitPerUser.toString()),
                    onChanged: (value) {
                      final limit = int.tryParse(value);
                      if (limit != null) {
                        setState(() {
                          _settings = _settings!.copyWith(dailyTokenLimitPerUser: limit);
                        });
                      }
                    },
                  ),
                ),
              ),
              ListTile(
                title: const Text('Maks. Mesaj (Sohbet Başına)'),
                subtitle: Text('${_settings!.maxMessagesPerConversation} mesaj'),
                trailing: SizedBox(
                  width: 100,
                  child: TextField(
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    controller: TextEditingController(text: _settings!.maxMessagesPerConversation.toString()),
                    onChanged: (value) {
                      final limit = int.tryParse(value);
                      if (limit != null) {
                        setState(() {
                          _settings = _settings!.copyWith(maxMessagesPerConversation: limit);
                        });
                      }
                    },
                  ),
                ),
              ),
              const Divider(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveSettings,
                  icon: _isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text('Limit Ayarlarını Kaydet'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Özellik Ayarları
          _buildCard(
            title: 'Özellikler',
            icon: Icons.extension,
            children: [
              SwitchListTile(
                title: const Text('Görsel Yükleme'),
                subtitle: const Text('Kullanıcıların resim yüklemesine izin ver'),
                value: _settings!.allowImageUpload,
                activeColor: Colors.deepPurple,
                onChanged: (value) {
                  setState(() {
                    _settings = _settings!.copyWith(allowImageUpload: value);
                  });
                },
              ),
              SwitchListTile(
                title: const Text('Görsel Üretimi'),
                subtitle: const Text('AI ile görsel üretmeye izin ver'),
                value: _settings!.allowImageGeneration,
                activeColor: Colors.deepPurple,
                onChanged: (value) {
                  setState(() {
                    _settings = _settings!.copyWith(allowImageGeneration: value);
                  });
                },
              ),
              SwitchListTile(
                title: const Text('Kamera Kullanımı'),
                subtitle: const Text('Kameradan fotoğraf çekmeye izin ver'),
                value: _settings!.allowCameraCapture,
                activeColor: Colors.deepPurple,
                onChanged: (value) {
                  setState(() {
                    _settings = _settings!.copyWith(allowCameraCapture: value);
                  });
                },
              ),
              const Divider(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveSettings,
                  icon: _isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text('Özellik Ayarlarını Kaydet'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Sistem Prompt
          _buildCard(
            title: 'Sistem Prompt',
            icon: Icons.psychology,
            children: [
              Padding(
                padding: const EdgeInsets.all(8.0),
                child: TextField(
                  controller: _systemPromptController,
                  maxLines: 5,
                  decoration: const InputDecoration(
                    border: OutlineInputBorder(),
                    hintText: 'AI asistanının davranışını tanımlayan sistem mesajı...',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _saveSettings,
                  icon: _isSaving
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.save),
                  label: const Text('Sistem Prompt Kaydet'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// İstatistikler sekmesi
  Widget _buildStatsTab() {
    if (_stats == null) {
      return const Center(child: Text('İstatistikler yüklenemedi'));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Genel İstatistikler
          _buildCard(
            title: 'Genel İstatistikler',
            icon: Icons.analytics,
            children: [
              _buildStatRow('Toplam Sohbet', '${_stats!.totalConversations}'),
              _buildStatRow('Toplam Mesaj', '${_stats!.totalMessages}'),
              _buildStatRow('Toplam Kullanıcı', '${_stats!.totalUsers}'),
              _buildStatRow('Toplam Token', '${_stats!.totalTokens}'),
            ],
          ),
          const SizedBox(height: 16),

          // Bugünkü Kullanım
          _buildCard(
            title: 'Bugünkü Kullanım',
            icon: Icons.today,
            children: [
              _buildStatRow('Bugünkü İstekler', '${_stats!.todayRequests}'),
              _buildStatRow('Bugünkü Token', '${_stats!.todayTokens}'),
            ],
          ),
          const SizedBox(height: 16),

          // Sağlayıcı Dağılımı
          _buildCard(
            title: 'Sağlayıcı Dağılımı',
            icon: Icons.pie_chart,
            children: [
              _buildStatRow('Gemini', '${_stats!.geminiCount} istek'),
              _buildStatRow('Groq', '${_stats!.groqCount} istek'),
              _buildStatRow('OpenRouter', '${_stats!.openrouterCount} istek'),
              _buildStatRow('OpenAI', '${_stats!.openaiCount} istek'),
            ],
          ),
          const SizedBox(height: 16),

          // Günlük Kırılım
          if (_stats!.dailyBreakdown.isNotEmpty) ...[
            _buildCard(
              title: 'Son 7 Gün',
              icon: Icons.bar_chart,
              children: [
                SizedBox(
                  height: 200,
                  child: _buildSimpleChart(),
                ),
              ],
            ),
          ],
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  /// Hazır Komutlar sekmesi
  Widget _buildPromptsTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.quickreply, size: 80, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            'Hazır Komutlar',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          Text(
            'Hazır komutlar AI sohbet uygulamasında\nkullanıcılara hızlı erişim için sunulur.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Hazır komutlar henüz yapılmadı')),
              );
            },
            icon: const Icon(Icons.edit),
            label: const Text('Hazır Komutları Yönet'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.deepPurple,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
          ),
        ],
      ),
    );
  }

  // Yardımcı widgetlar

  Widget _buildCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return Card(
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Colors.deepPurple),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _buildApiKeyField({
    required String label,
    required TextEditingController controller,
    required bool isSet,
    required String helperText,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label, style: const TextStyle(fontWeight: FontWeight.w500)),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isSet ? Colors.green.shade100 : Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  isSet ? 'Ayarlanmış' : 'Ayarlanmamış',
                  style: TextStyle(
                    fontSize: 12,
                    color: isSet ? Colors.green.shade700 : Colors.grey.shade600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(helperText, style: TextStyle(fontSize: 12, color: Colors.grey.shade600)),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            obscureText: true,
            decoration: InputDecoration(
              border: const OutlineInputBorder(),
              hintText: isSet ? '••••••••••••••••' : 'API anahtarını girin',
              suffixIcon: IconButton(
                icon: Icon(controller.text.isNotEmpty ? Icons.clear : Icons.visibility),
                onPressed: () {
                  if (controller.text.isNotEmpty) {
                    controller.clear();
                  }
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderDropdown(String label, String currentValue, Function(String) onChanged) {
    final providers = [
      {'value': 'pollinations', 'label': 'Pollinations (Ücretsiz)'},
      {'value': 'gemini', 'label': 'Gemini'},
      {'value': 'groq', 'label': 'Groq'},
      {'value': 'openrouter', 'label': 'OpenRouter'},
      {'value': 'openai', 'label': 'OpenAI'},
      {'value': 'huggingface', 'label': 'HuggingFace (Ücretsiz)'},
    ];

    return Row(
      children: [
        Expanded(flex: 2, child: Text(label)),
        Expanded(
          flex: 3,
          child: DropdownButtonFormField<String>(
            value: providers.any((p) => p['value'] == currentValue) ? currentValue : 'pollinations',
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            items: providers.map((p) => DropdownMenuItem(
              value: p['value'] as String,
              child: Text(p['label'] as String, style: const TextStyle(fontSize: 14)),
            )).toList(),
            onChanged: (value) {
              if (value != null) onChanged(value);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildStatRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(fontSize: 16)),
          Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildSimpleChart() {
    if (_stats == null || _stats!.dailyBreakdown.isEmpty) {
      return const Center(child: Text('Veri yok'));
    }

    final maxRequests = _stats!.dailyBreakdown.map((e) => e.requests).reduce((a, b) => a > b ? a : b);
    if (maxRequests == 0) return const Center(child: Text('Veri yok'));

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: _stats!.dailyBreakdown.map((day) {
        final height = (day.requests / maxRequests) * 150;
        return Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            Text(
              '${day.requests}',
              style: const TextStyle(fontSize: 10),
            ),
            Container(
              width: 30,
              height: height.clamp(10.0, 150.0),
              decoration: BoxDecoration(
                color: Colors.deepPurple,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              day.date.substring(5),
              style: const TextStyle(fontSize: 10),
            ),
          ],
        );
      }).toList(),
    );
  }
}
