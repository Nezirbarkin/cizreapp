// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/app_about_settings.dart';
import '../../../core/services/app_about_service.dart';

class AdminAboutSettingsScreen extends StatefulWidget {
  const AdminAboutSettingsScreen({super.key});

  @override
  State<AdminAboutSettingsScreen> createState() => _AdminAboutSettingsScreenState();
}

class _AdminAboutSettingsScreenState extends State<AdminAboutSettingsScreen> {
  final AppAboutService _aboutService = AppAboutService();
  final _formKey = GlobalKey<FormState>();
  
  AppAboutSettings? _settings;
  bool _isLoading = true;
  bool _isSaving = false;

  // Controllers
  late TextEditingController _appNameController;
  late TextEditingController _appSloganController;
  late TextEditingController _appDescriptionController;
  late TextEditingController _contactEmailController;
  late TextEditingController _websiteUrlController;
  late TextEditingController _supportPhoneController;
  late TextEditingController _versionController;
  late TextEditingController _buildController;
  late TextEditingController _termsController;
  late TextEditingController _privacyController;

  // Zorunlu güncelleme controllers
  late TextEditingController _minVersionController;
  late TextEditingController _minBuildController;
  bool _forceUpdateEnabled = true;
  bool _isSavingForceUpdate = false;

  // Feature controllers
  final List<TextEditingController> _featureControllers = [];

  // Social media controllers
  late TextEditingController _instagramController;
  late TextEditingController _twitterController;
  late TextEditingController _facebookController;
  late TextEditingController _youtubeController;
  
  // API Key controller
  late TextEditingController _mapsApiKeyController;

  // Animasyon süreleri (slider ile, int ms olarak)
  int _animationPrimaryDurationMs = 6000;
  int _animationSecondaryDurationMs = 3000;
  int _animationTransitionDurationMs = 700;

  @override
  void initState() {
    super.initState();
    _initializeControllers();
    _loadSettings();
  }

  void _initializeControllers() {
    _appNameController = TextEditingController();
    _appSloganController = TextEditingController();
    _appDescriptionController = TextEditingController();
    _contactEmailController = TextEditingController();
    _websiteUrlController = TextEditingController();
    _supportPhoneController = TextEditingController();
    _versionController = TextEditingController();
    _buildController = TextEditingController();
    _minVersionController = TextEditingController();
    _minBuildController = TextEditingController();
    _termsController = TextEditingController();
    _privacyController = TextEditingController();
    _instagramController = TextEditingController();
    _twitterController = TextEditingController();
    _facebookController = TextEditingController();
    _youtubeController = TextEditingController();
    _mapsApiKeyController = TextEditingController();
  }

  @override
  void dispose() {
    _appNameController.dispose();
    _appSloganController.dispose();
    _appDescriptionController.dispose();
    _contactEmailController.dispose();
    _websiteUrlController.dispose();
    _supportPhoneController.dispose();
    _versionController.dispose();
    _buildController.dispose();
    _minVersionController.dispose();
    _minBuildController.dispose();
    _termsController.dispose();
    _privacyController.dispose();
    _instagramController.dispose();
    _twitterController.dispose();
    _facebookController.dispose();
    _youtubeController.dispose();
    for (var controller in _featureControllers) {
      controller.dispose();
    }
    _mapsApiKeyController.dispose();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final settings = await _aboutService.getAboutSettings();
    if (settings != null && mounted) {
      _settings = settings;
      _populateControllers(settings);
    }
    try {
      final row = await Supabase.instance.client
          .from('app_about_settings')
          .select('min_version, min_build_code, force_update_enabled')
          .eq('id', 1)
          .single();
      _minVersionController.text = row['min_version']?.toString() ?? '';
      _minBuildController.text = row['min_build_code']?.toString() ?? '';
      _forceUpdateEnabled = row['force_update_enabled'] as bool? ?? true;
    } catch (e) {
      debugPrint('⚠️ Zorunlu güncelleme ayarları yüklenemedi: $e');
    }
    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _saveForceUpdateSettings() async {
    final minVersion = _minVersionController.text.trim();
    final minBuild = int.tryParse(_minBuildController.text.trim());
    if (minVersion.isEmpty || minBuild == null) {
      _showSnackBar('Geçerli bir versiyon ve build kodu girin', isError: true);
      return;
    }

    setState(() => _isSavingForceUpdate = true);
    try {
      await Supabase.instance.client.from('app_about_settings').update({
        'min_version': minVersion,
        'min_build_code': minBuild,
        'current_version': minVersion,
        'current_build_code': minBuild,
        'force_update_enabled': _forceUpdateEnabled,
      }).eq('id', 1);
      if (mounted) _showSnackBar('Zorunlu güncelleme ayarları kaydedildi', isError: false);
    } catch (e) {
      if (mounted) _showSnackBar('Hata: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSavingForceUpdate = false);
    }
  }

  void _populateControllers(AppAboutSettings settings) {
    _appNameController.text = settings.appName;
    _appSloganController.text = settings.appSlogan;
    _appDescriptionController.text = settings.appDescription;
    _contactEmailController.text = settings.contactEmail;
    _websiteUrlController.text = settings.websiteUrl;
    _supportPhoneController.text = settings.supportPhone ?? '';
    _versionController.text = settings.versionNumber;
    _buildController.text = settings.buildNumber;
    _termsController.text = settings.termsOfService;
    _privacyController.text = settings.privacyPolicy;

    // Populate features
    _featureControllers.clear();
    for (var feature in settings.appFeatures) {
      _featureControllers.add(TextEditingController(text: feature));
    }
    if (_featureControllers.isEmpty) {
      _featureControllers.add(TextEditingController());
    }

    // Populate social media links
    final links = settings.socialMediaLinks ?? {};
    _instagramController.text = links['instagram'] ?? '';
    _twitterController.text = links['twitter'] ?? '';
    _facebookController.text = links['facebook'] ?? '';
    _youtubeController.text = links['youtube'] ?? '';
    
    // Populate API Keys
    _mapsApiKeyController.text = settings.googleMapsApiKey ?? '';

    // Populate animation settings
    _animationPrimaryDurationMs = settings.animationPrimaryDurationMs;
    _animationSecondaryDurationMs = settings.animationSecondaryDurationMs;
    _animationTransitionDurationMs = settings.animationTransitionDurationMs;
  }

  Future<void> _saveSettings() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final updatedSettings = _settings!.copyWith(
        appName: _appNameController.text.trim(),
        appSlogan: _appSloganController.text.trim(),
        appDescription: _appDescriptionController.text.trim(),
        appFeatures: _featureControllers
            .map((c) => c.text.trim())
            .where((text) => text.isNotEmpty)
            .toList(),
        contactEmail: _contactEmailController.text.trim(),
        websiteUrl: _websiteUrlController.text.trim(),
        supportPhone: _supportPhoneController.text.trim().isEmpty
            ? null
            : _supportPhoneController.text.trim(),
        versionNumber: _versionController.text.trim(),
        buildNumber: _buildController.text.trim(),
        termsOfService: _termsController.text.trim(),
        privacyPolicy: _privacyController.text.trim(),
        socialMediaLinks: {
          'instagram': _instagramController.text.trim(),
          'twitter': _twitterController.text.trim(),
          'facebook': _facebookController.text.trim(),
          'youtube': _youtubeController.text.trim(),
        },
        googleMapsApiKey: _mapsApiKeyController.text.trim().isEmpty
            ? null
            : _mapsApiKeyController.text.trim(),
        animationPrimaryDurationMs: _animationPrimaryDurationMs.clamp(1000, 30000),
        animationSecondaryDurationMs: _animationSecondaryDurationMs.clamp(500, 15000),
        animationTransitionDurationMs: _animationTransitionDurationMs.clamp(100, 3000),
      );

      final success = await _aboutService.updateAboutSettings(updatedSettings);
      if (success && mounted) {
        _showSnackBar('Ayarlar başarıyla güncellendi', isError: false);
        await _loadSettings();
      } else if (mounted) {
        _showSnackBar('Ayarlar güncellenirken hata oluştu', isError: true);
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Hata: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.purple,
        title: const Text(
          'Hakkında Ayarları',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (!_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : TextButton.icon(
                        onPressed: _saveSettings,
                        icon: const Icon(Icons.save, color: Colors.white),
                        label: const Text(
                          'Kaydet',
                          style: TextStyle(color: Colors.white),
                        ),
                      ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _buildSectionHeader('Uygulama Bilgileri', Icons.info_outline),
                  const SizedBox(height: 12),
                  _buildCard([
                    _buildTextField(
                      controller: _appNameController,
                      label: 'Uygulama Adı',
                      icon: Icons.app_settings_alt,
                      required: true,
                    ),
                        _buildTextArea(
                          controller: _appDescriptionController,
                          label: 'Açıklama',
                          icon: Icons.description,
                          required: true,
                          minLines: 3,
                        ),
                      ]),

                      const SizedBox(height: 24),
    
                      _buildSectionHeader('Animasyon Ayarları', Icons.animation),
                      const SizedBox(height: 12),
                      _buildCard([
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.purple.shade400, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '"Her an her kapıda" sloganının ekranda kalma süresi ve geçiş animasyonu hızını ayarlayın.',
                                  style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                                ),
                              ),
                            ],
                          ),
                        ),
                        _buildDurationSlider(
                          label: 'Başlık Süresi (CizreApp)',
                          value: _animationPrimaryDurationMs,
                          min: 1000,
                          max: 30000,
                          divisions: 29,
                          unit: 'sn',
                          onChanged: (v) => setState(() => _animationPrimaryDurationMs = v),
                        ),
                        const SizedBox(height: 8),
                        _buildDurationSlider(
                          label: 'Slogan Süresi',
                          value: _animationSecondaryDurationMs,
                          min: 500,
                          max: 15000,
                          divisions: 29,
                          unit: 'sn',
                          onChanged: (v) => setState(() => _animationSecondaryDurationMs = v),
                        ),
                        const SizedBox(height: 8),
                        _buildDurationSlider(
                          label: 'Geçiş Animasyonu Süresi',
                          value: _animationTransitionDurationMs,
                          min: 100,
                          max: 3000,
                          divisions: 29,
                          unit: 'sn',
                          onChanged: (v) => setState(() => _animationTransitionDurationMs = v),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          onPressed: () {
                            setState(() {
                              _animationPrimaryDurationMs = 6000;
                              _animationSecondaryDurationMs = 3000;
                              _animationTransitionDurationMs = 700;
                            });
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Varsayılana Dön'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.purple,
                            side: const BorderSide(color: Colors.purple),
                          ),
                        ),
                        const SizedBox(height: 16),
                        // Slogan metni (animasyon bölümü içinde)
                        _buildTextField(
                          controller: _appSloganController,
                          label: 'Slogan Metni ("Her an her kapıda")',
                          icon: Icons.format_quote,
                          required: true,
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.amber.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.amber.shade200),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.lightbulb_outline, color: Colors.amber.shade700, size: 18),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Bu metin üst bardaki CizreApp başlığıyla dönüşümlü gösterilir.',
                                  style: TextStyle(fontSize: 11, color: Colors.amber.shade800),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ]),
    
                      const SizedBox(height: 24),
    
                      _buildSectionHeader('Özellikler', Icons.star_outline),
                  const SizedBox(height: 12),
                  _buildCard([
                    ...List.generate(_featureControllers.length, (index) {
                      return Padding(
                        padding: EdgeInsets.only(bottom: index < _featureControllers.length - 1 ? 12 : 0),
                        child: _buildFeatureField(
                          controller: _featureControllers[index],
                          index: index,
                        ),
                      );
                    }),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: () {
                        setState(() {
                          _featureControllers.add(TextEditingController());
                        });
                      },
                      icon: const Icon(Icons.add),
                      label: const Text('Özellik Ekle'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.purple,
                        side: const BorderSide(color: Colors.purple),
                      ),
                    ),
                  ]),

                  const SizedBox(height: 24),

                  _buildSectionHeader('İletişim Bilgileri', Icons.contact_mail),
                  const SizedBox(height: 12),
                  _buildCard([
                    _buildTextField(
                      controller: _contactEmailController,
                      label: 'E-posta',
                      icon: Icons.email,
                      keyboardType: TextInputType.emailAddress,
                      required: true,
                    ),
                    _buildTextField(
                      controller: _websiteUrlController,
                      label: 'Web Sitesi',
                      icon: Icons.language,
                      keyboardType: TextInputType.url,
                      required: true,
                    ),
                    _buildTextField(
                      controller: _supportPhoneController,
                      label: 'Telefon (Opsiyonel)',
                      icon: Icons.phone,
                      keyboardType: TextInputType.phone,
                    ),
                  ]),

                  const SizedBox(height: 24),

                  _buildSectionHeader('API Anahtarları', Icons.vpn_key),
                  const SizedBox(height: 12),
                  _buildCard([
                    _buildTextField(
                      controller: _mapsApiKeyController,
                      label: 'Google Maps API Key',
                      icon: Icons.map,
                      required: false,
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber, color: Colors.orange.shade700, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'API Key almak için: console.cloud.google.com > API & Services > Credentials',
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.orange.shade700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ]),

                  const SizedBox(height: 24),

                  _buildSectionHeader('Sosyal Medya', Icons.share),
                  const SizedBox(height: 12),
                  _buildCard([
                    _buildTextField(
                      controller: _instagramController,
                      label: 'Instagram URL',
                      icon: Icons.camera_alt,
                      keyboardType: TextInputType.url,
                    ),
                    _buildTextField(
                      controller: _twitterController,
                      label: 'Twitter/X URL',
                      icon: Icons.alternate_email,
                      keyboardType: TextInputType.url,
                    ),
                    _buildTextField(
                      controller: _facebookController,
                      label: 'Facebook URL',
                      icon: Icons.facebook,
                      keyboardType: TextInputType.url,
                    ),
                    _buildTextField(
                      controller: _youtubeController,
                      label: 'YouTube URL',
                      icon: Icons.play_arrow,
                      keyboardType: TextInputType.url,
                    ),
                  ]),

                  const SizedBox(height: 24),

                  _buildSectionHeader('Versiyon Bilgileri', Icons.settings),
                  const SizedBox(height: 12),
                  _buildCard([
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _versionController,
                            label: 'Versiyon',
                            icon: Icons.tag,
                            required: true,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            controller: _buildController,
                            label: 'Build',
                            icon: Icons.build,
                            required: true,
                          ),
                        ),
                      ],
                    ),
                  ]),

                  const SizedBox(height: 24),

                  _buildSectionHeader('Zorunlu Güncelleme', Icons.system_update_alt),
                  const SizedBox(height: 12),
                  _buildCard([
                    SwitchListTile(
                      title: const Text(
                        'Zorunlu Güncelleme Aktif',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        _forceUpdateEnabled
                            ? 'Minimum sürümün altındaki kullanıcılar güncellemeye zorlanır'
                            : 'Zorunlu güncelleme kapalı',
                        style: TextStyle(color: _forceUpdateEnabled ? Colors.purple : Colors.grey),
                      ),
                      value: _forceUpdateEnabled,
                      onChanged: (value) => setState(() => _forceUpdateEnabled = value),
                      activeColor: Colors.purple,
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _buildTextField(
                            controller: _minVersionController,
                            label: 'Minimum Versiyon (örn: 1.3.0)',
                            icon: Icons.tag,
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: _buildTextField(
                            controller: _minBuildController,
                            label: 'Minimum Build Kodu',
                            icon: Icons.build,
                            keyboardType: TextInputType.number,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.purple.shade100),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.purple.shade400, size: 18),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Yeni bir zorunlu sürüm çıkardığında buraya pubspec.yaml\'daki versiyon ve build numarasını gir, ardından "Kaydet"e bas. Bu değerin altındaki tüm kullanıcılar açılışta güncellemeye zorlanır.',
                              style: TextStyle(fontSize: 11, color: Colors.purple.shade700),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _isSavingForceUpdate ? null : _saveForceUpdateSettings,
                        icon: _isSavingForceUpdate
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.save),
                        label: const Text('Zorunlu Güncellemeyi Kaydet'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.purple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ]),

                  const SizedBox(height: 24),

                  _buildSectionHeader('Yasal Belgeler', Icons.gavel),
                  const SizedBox(height: 12),
                  _buildCard([
                    _buildTextArea(
                      controller: _termsController,
                      label: 'Kullanım Koşulları',
                      icon: Icons.description,
                      required: true,
                      minLines: 8,
                    ),
                    const SizedBox(height: 16),
                    _buildTextArea(
                      controller: _privacyController,
                      label: 'Gizlilik Politikası',
                      icon: Icons.privacy_tip,
                      required: true,
                      minLines: 8,
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.orange.shade50,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange.shade200),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.policy_outlined,
                            color: Colors.orange.shade800,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Operatör notu: Bu iki uygulama içi metin veritabanındaki '
                              'app_about_settings.terms_of_service ve privacy_policy alanlarından '
                              'yönetilir; bir uygulama kodu yayını mevcut DB metnini otomatik '
                              'güncellemez. Yayın öncesinde isteğe bağlı AdMob/SSV veri işleme, '
                              'puanların nakit olmadığı, yalnız uygun dijital üründe önce puan '
                              'sonra TL kullanımı, kaynağına iade ve geçmiş TL ödüllerine no-backfill '
                              'özetini buraya da işleyin. Kanonik bağlantı: '
                              'https://cizreapp.com/privacy.html',
                              style: TextStyle(
                                fontSize: 12,
                                height: 1.4,
                                color: Colors.orange.shade900,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ]),

                  const SizedBox(height: 32),

                  // Bilgilendirme notu
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.blue.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Online ödeme ayarları "API Ayarları" bölümünde, '
                            'sipariş kontrol ve açılış duyurusu "Ayarlar" bölümünde yönetilmektedir.',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.blue.shade700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 32),
                ],
              ),
            ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.purple.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.purple, size: 20),
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
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    bool required = false,
    bool obscureText = false,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.purple, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
        suffixIcon: obscureText
            ? Icon(Icons.visibility_off, color: Colors.grey.shade400)
            : null,
      ),
      obscureText: obscureText,
      validator: required
          ? (value) {
              if (value == null || value.trim().isEmpty) {
                return '$label boş bırakılamaz';
              }
              return null;
            }
          : null,
    );
  }

  Widget _buildTextArea({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    int minLines = 3,
    bool required = false,
  }) {
    return TextFormField(
      controller: controller,
      minLines: minLines,
      maxLines: null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.purple, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
        alignLabelWithHint: true,
      ),
      validator: required
          ? (value) {
              if (value == null || value.trim().isEmpty) {
                return '$label boş bırakılamaz';
              }
              return null;
            }
          : null,
    );
  }

  Widget _buildFeatureField({
    required TextEditingController controller,
    required int index,
  }) {
    return Row(
      children: [
        Expanded(
          child: TextFormField(
            controller: controller,
            decoration: InputDecoration(
              labelText: 'Özellik ${index + 1}',
              prefixIcon: const Icon(Icons.check_circle_outline, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: Colors.purple, width: 2),
              ),
              filled: true,
              fillColor: Colors.grey.shade50,
            ),
          ),
        ),
        const SizedBox(width: 8),
        if (_featureControllers.length > 1)
          IconButton(
            onPressed: () {
              setState(() {
                controller.dispose();
                _featureControllers.removeAt(index);
              });
            },
            icon: const Icon(Icons.delete_outline, color: Colors.red),
          ),
      ],
    );
  }

  /// Animasyon süresi için slider widget'ı.
  /// Değeri milisaniye olarak gösterir ama kullanıcıya saniye cinsinden
  /// (1 ondalık basamak) gösterir.
  Widget _buildDurationSlider({
    required String label,
    required int value,
    required int min,
    required int max,
    required int divisions,
    required String unit,
    required ValueChanged<int> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.purple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${(value / 1000).toStringAsFixed(1)} $unit',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: Colors.purple.shade700,
                ),
              ),
            ),
          ],
        ),
        Slider(
          value: value.toDouble(),
          min: min.toDouble(),
          max: max.toDouble(),
          divisions: divisions,
          activeColor: Colors.purple,
          label: '${(value / 1000).toStringAsFixed(1)} $unit',
          onChanged: (v) => onChanged(v.round()),
        ),
      ],
    );
  }
}
