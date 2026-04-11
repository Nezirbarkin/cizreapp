// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
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

  // Feature controllers
  final List<TextEditingController> _featureControllers = [];

  // Social media controllers
  late TextEditingController _instagramController;
  late TextEditingController _twitterController;
  late TextEditingController _facebookController;
  late TextEditingController _youtubeController;

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
    _termsController = TextEditingController();
    _privacyController = TextEditingController();
    _instagramController = TextEditingController();
    _twitterController = TextEditingController();
    _facebookController = TextEditingController();
    _youtubeController = TextEditingController();
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
    _termsController.dispose();
    _privacyController.dispose();
    _instagramController.dispose();
    _twitterController.dispose();
    _facebookController.dispose();
    _youtubeController.dispose();
    for (var controller in _featureControllers) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final settings = await _aboutService.getAboutSettings();
    if (settings != null && mounted) {
      _settings = settings;
      _populateControllers(settings);
    }
    if (mounted) {
      setState(() => _isLoading = false);
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
                    _buildTextField(
                      controller: _appSloganController,
                      label: 'Slogan',
                      icon: Icons.format_quote,
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
}
