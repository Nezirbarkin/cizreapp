import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/providers/theme_provider.dart';
import '../../../core/services/app_about_service.dart';
import '../../../core/models/app_about_settings.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  final AppAboutService _aboutService = AppAboutService();
  AppAboutSettings? _settings;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final settings = await _aboutService.getAboutSettings();
    if (mounted) {
      setState(() {
        _settings = settings;
        _isLoading = false;
      });
    }
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final primaryColor = themeProvider.primaryColor;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: CustomScrollView(
        slivers: [
          // Modern AppBar
          SliverAppBar(
            expandedHeight: 200,
            floating: false,
            pinned: true,
            backgroundColor: primaryColor,
            flexibleSpace: FlexibleSpaceBar(
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      primaryColor,
                      primaryColor.withValues(alpha: 0.8),
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // Logo
                        Container(
                          width: 80,
                          height: 80,
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(20),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.2),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: Icon(
                            Icons.shopping_bag_outlined,
                            size: 40,
                            color: primaryColor,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _settings?.appName ?? 'Cizre App',
                          style: const TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _settings?.appSlogan ?? 'Cizre\'nin En Büyük Alışveriş Platformu',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.white.withValues(alpha: 0.9),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // İçerik
          SliverToBoxAdapter(
            child: _isLoading
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(),
                    ),
                  )
                : _buildContent(primaryColor),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(Color primaryColor) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Versiyon Bilgisi
          _buildVersionCard(primaryColor),

          const SizedBox(height: 20),

          // Uygulama Hakkında
          _buildSectionCard(
            icon: Icons.info_outline,
            title: 'Uygulama Hakkında',
            color: primaryColor,
            child: Text(
              _settings?.appDescription ??
                  'Cizre App, Cizre ve çevresindeki kullanıcıların güvenli bir şekilde '
                  'alışveriş yapabileceği, ürün satışı gerçekleştirebileceği ve '
                  'sosyal etkileşimde bulunabileceği kapsamlı bir platformdur.',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade700,
                height: 1.6,
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Özellikler
          if (_settings?.appFeatures.isNotEmpty ?? false)
            _buildFeaturesCard(primaryColor),

          const SizedBox(height: 16),

          // İletişim
          _buildContactCard(primaryColor),

          const SizedBox(height: 16),

          // Yasal Bilgiler
          _buildLegalCard(primaryColor),

          const SizedBox(height: 16),

          // Sosyal Medya
          if (_settings?.socialMediaLinks != null)
            _buildSocialMediaCard(primaryColor),

          const SizedBox(height: 30),
        ],
      ),
    );
  }

  Widget _buildVersionCard(Color primaryColor) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: primaryColor.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.verified,
              size: 18,
              color: primaryColor,
            ),
            const SizedBox(width: 8),
            Text(
              'v${_settings?.versionNumber ?? '1.0.0'} (${_settings?.buildNumber ?? '1'})',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: primaryColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required IconData icon,
    required String title,
    required Color color,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
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
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: 22),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
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

  Widget _buildFeaturesCard(Color primaryColor) {
    final features = _settings?.appFeatures ?? [];
    return _buildSectionCard(
      icon: Icons.star_outline,
      title: 'Özellikler',
      color: Colors.amber,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: features.map((feature) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                Icon(
                  Icons.check_circle_outline,
                  size: 18,
                  color: primaryColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    feature,
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey.shade700,
                    ),
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildContactCard(Color primaryColor) {
    return _buildSectionCard(
      icon: Icons.contact_support_outlined,
      title: 'İletişim',
      color: Colors.green,
      child: Column(
        children: [
          if (_settings?.contactEmail != null && _settings!.contactEmail.isNotEmpty)
            _buildContactItem(
              icon: Icons.email_outlined,
              label: 'E-posta',
              value: _settings!.contactEmail,
              color: Colors.red,
              onTap: () => _launchUrl('mailto:${_settings!.contactEmail}'),
            ),
          if (_settings?.supportPhone != null && _settings!.supportPhone!.isNotEmpty)
            _buildContactItem(
              icon: Icons.phone_outlined,
              label: 'Telefon',
              value: _settings!.supportPhone!,
              color: Colors.green,
              onTap: () => _launchUrl('tel:${_settings!.supportPhone}'),
            ),
          if (_settings?.websiteUrl != null && _settings!.websiteUrl.isNotEmpty)
            _buildContactItem(
              icon: Icons.language,
              label: 'Web Sitesi',
              value: _settings!.websiteUrl,
              color: Colors.blue,
              onTap: () => _launchUrl(_settings!.websiteUrl),
            ),
        ],
      ),
    );
  }

  Widget _buildContactItem({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      color: Colors.grey.shade500,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: color,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildLegalCard(Color primaryColor) {
    return _buildSectionCard(
      icon: Icons.gavel_outlined,
      title: 'Yasal Bilgiler',
      color: Colors.purple,
      child: Column(
        children: [
          _buildLegalItem(
            icon: Icons.description_outlined,
            label: 'Kullanım Koşulları',
            color: Colors.indigo,
            onTap: () => _showTermsDialog(),
          ),
          const SizedBox(height: 10),
          _buildLegalItem(
            icon: Icons.privacy_tip_outlined,
            label: 'Gizlilik Politikası',
            color: Colors.teal,
            onTap: () => _showPrivacyDialog(),
          ),
        ],
      ),
    );
  }

  Widget _buildLegalItem({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
              ),
            ),
            Icon(Icons.arrow_forward_ios, color: color, size: 14),
          ],
        ),
      ),
    );
  }

  Widget _buildSocialMediaCard(Color primaryColor) {
    final Map<String, String> links = _settings?.socialMediaLinks ?? {};
    final platforms = {
      'instagram': {'icon': Icons.camera_alt, 'color': Colors.pink},
      'twitter': {'icon': Icons.alternate_email, 'color': Colors.blue},
      'facebook': {'icon': Icons.facebook, 'color': Colors.blue.shade700},
      'youtube': {'icon': Icons.play_arrow, 'color': Colors.red},
    };

    final validLinks = links.entries
        .where((e) => e.value.isNotEmpty)
        .toList();

    if (validLinks.isEmpty) return const SizedBox.shrink();

    return _buildSectionCard(
      icon: Icons.share,
      title: 'Sosyal Medya',
      color: Colors.orange,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: validLinks.map((entry) {
          final platform = platforms[entry.key];
          if (platform == null) return const SizedBox.shrink();

          final color = platform['color'] as Color;
          final icon = platform['icon'] as IconData;

          return InkWell(
            onTap: () => _launchUrl(entry.value),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                shape: BoxShape.circle,
                border: Border.all(
                  color: color.withValues(alpha: 0.3),
                ),
              ),
              child: Icon(
                icon,
                color: color,
                size: 24,
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  void _showTermsDialog() {
    showDialog(
      context: context,
      builder: (context) => _buildLegalDialog(
        title: 'Kullanım Koşulları',
        icon: Icons.description_outlined,
        color: Colors.indigo,
        content: _settings?.termsOfService ?? '',
      ),
    );
  }

  void _showPrivacyDialog() {
    showDialog(
      context: context,
      builder: (context) => _buildLegalDialog(
        title: 'Gizlilik Politikası',
        icon: Icons.privacy_tip_outlined,
        color: Colors.teal,
        content: _settings?.privacyPolicy ?? '',
      ),
    );
  }

  Widget _buildLegalDialog({
    required String title,
    required IconData icon,
    required Color color,
    required String content,
  }) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 500, maxWidth: 400),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  content.isNotEmpty
                      ? content
                      : 'İçerik yüklenemedi.',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey.shade700,
                    height: 1.6,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
