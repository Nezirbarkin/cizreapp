class AppAboutSettings {
  final int id;
  final String appName;
  final String appSlogan;
  final String appDescription;
  final List<String> appFeatures;
  final String contactEmail;
  final String websiteUrl;
  final String? supportPhone;
  final String termsOfService;
  final String privacyPolicy;
  final String versionNumber;
  final String buildNumber;
  final Map<String, String>? socialMediaLinks;
  
  // Online Ödeme Ayarları
  final bool onlinePaymentEnabled;
  final String? iyzicoApiKey;
  final String? iyzicoSecretKey;
  final String? iyzicoApiUrl;
  
  // Sipariş Kontrol
  final bool globalOrdersEnabled;
  
  // Açılış Duyurusu
  final bool startupAnnouncementEnabled;
  final String? startupAnnouncementTitle;
  final String? startupAnnouncementMessage;
  final String startupAnnouncementType;
  final String startupAnnouncementButtonText;
  final DateTime? startupAnnouncementUpdatedAt;
  
  final DateTime createdAt;
  final DateTime updatedAt;

  AppAboutSettings({
    required this.id,
    required this.appName,
    required this.appSlogan,
    required this.appDescription,
    required this.appFeatures,
    required this.contactEmail,
    required this.websiteUrl,
    this.supportPhone,
    required this.termsOfService,
    required this.privacyPolicy,
    required this.versionNumber,
    required this.buildNumber,
    this.socialMediaLinks,
    this.onlinePaymentEnabled = true,
    this.iyzicoApiKey,
    this.iyzicoSecretKey,
    this.iyzicoApiUrl,
    this.globalOrdersEnabled = true,
    this.startupAnnouncementEnabled = false,
    this.startupAnnouncementTitle,
    this.startupAnnouncementMessage,
    this.startupAnnouncementType = 'info',
    this.startupAnnouncementButtonText = 'Tamam',
    this.startupAnnouncementUpdatedAt,
    required this.createdAt,
    required this.updatedAt,
  });

  factory AppAboutSettings.fromJson(Map<String, dynamic> json) {
    return AppAboutSettings(
      id: json['id'] as int,
      appName: json['app_name'] as String? ?? 'Cizre App',
      appSlogan: json['app_slogan'] as String? ?? 'Cizre\'nin En Büyük Alışveriş Platformu',
      appDescription: json['app_description'] as String? ?? '',
      appFeatures: (json['app_features'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [
            'Mağaza ve ürün yönetimi',
            'Sipariş takibi',
            'Sosyal paylaşım ve etkileşim',
            'Anlık mesajlaşma',
            'Favori ürünler ve mağazalar',
            'Ürün değerlendirme sistemi'
          ],
      contactEmail: json['contact_email'] as String? ?? 'destek@cizreapp.com',
      websiteUrl: json['website_url'] as String? ?? 'https://cizreapp.com',
      supportPhone: json['support_phone'] as String?,
      termsOfService: json['terms_of_service'] as String? ?? '',
      privacyPolicy: json['privacy_policy'] as String? ?? '',
      versionNumber: json['version_number'] as String? ?? '1.0.0',
      buildNumber: json['build_number'] as String? ?? '1',
      socialMediaLinks: (json['social_media_links'] as Map<String, dynamic>?)?.cast<String, String>(),
      onlinePaymentEnabled: json['online_payment_enabled'] as bool? ?? true,
      iyzicoApiKey: json['iyzico_api_key'] as String?,
      iyzicoSecretKey: json['iyzico_secret_key'] as String?,
      iyzicoApiUrl: json['iyzico_api_url'] as String?,
      globalOrdersEnabled: json['global_orders_enabled'] as bool? ?? true,
      startupAnnouncementEnabled: json['startup_announcement_enabled'] as bool? ?? false,
      startupAnnouncementTitle: json['startup_announcement_title'] as String?,
      startupAnnouncementMessage: json['startup_announcement_message'] as String?,
      startupAnnouncementType: json['startup_announcement_type'] as String? ?? 'info',
      startupAnnouncementButtonText: json['startup_announcement_button_text'] as String? ?? 'Tamam',
      startupAnnouncementUpdatedAt: json['startup_announcement_updated_at'] != null
          ? DateTime.parse(json['startup_announcement_updated_at'] as String)
          : null,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'app_name': appName,
      'app_slogan': appSlogan,
      'app_description': appDescription,
      'app_features': appFeatures,
      'contact_email': contactEmail,
      'website_url': websiteUrl,
      'support_phone': supportPhone,
      'terms_of_service': termsOfService,
      'privacy_policy': privacyPolicy,
      'version_number': versionNumber,
      'build_number': buildNumber,
      'social_media_links': socialMediaLinks,
      'online_payment_enabled': onlinePaymentEnabled,
      'iyzico_api_key': iyzicoApiKey,
      'iyzico_secret_key': iyzicoSecretKey,
      'iyzico_api_url': iyzicoApiUrl,
      'global_orders_enabled': globalOrdersEnabled,
      'startup_announcement_enabled': startupAnnouncementEnabled,
      'startup_announcement_title': startupAnnouncementTitle,
      'startup_announcement_message': startupAnnouncementMessage,
      'startup_announcement_type': startupAnnouncementType,
      'startup_announcement_button_text': startupAnnouncementButtonText,
      'startup_announcement_updated_at': startupAnnouncementUpdatedAt?.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  AppAboutSettings copyWith({
    String? appName,
    String? appSlogan,
    String? appDescription,
    List<String>? appFeatures,
    String? contactEmail,
    String? websiteUrl,
    String? supportPhone,
    String? termsOfService,
    String? privacyPolicy,
    String? versionNumber,
    String? buildNumber,
    Map<String, String>? socialMediaLinks,
    bool? onlinePaymentEnabled,
    String? iyzicoApiKey,
    String? iyzicoSecretKey,
    String? iyzicoApiUrl,
    bool? globalOrdersEnabled,
    bool? startupAnnouncementEnabled,
    String? startupAnnouncementTitle,
    String? startupAnnouncementMessage,
    String? startupAnnouncementType,
    String? startupAnnouncementButtonText,
    DateTime? startupAnnouncementUpdatedAt,
  }) {
    return AppAboutSettings(
      id: id,
      appName: appName ?? this.appName,
      appSlogan: appSlogan ?? this.appSlogan,
      appDescription: appDescription ?? this.appDescription,
      appFeatures: appFeatures ?? this.appFeatures,
      contactEmail: contactEmail ?? this.contactEmail,
      websiteUrl: websiteUrl ?? this.websiteUrl,
      supportPhone: supportPhone ?? this.supportPhone,
      termsOfService: termsOfService ?? this.termsOfService,
      privacyPolicy: privacyPolicy ?? this.privacyPolicy,
      versionNumber: versionNumber ?? this.versionNumber,
      buildNumber: buildNumber ?? this.buildNumber,
      socialMediaLinks: socialMediaLinks ?? this.socialMediaLinks,
      onlinePaymentEnabled: onlinePaymentEnabled ?? this.onlinePaymentEnabled,
      iyzicoApiKey: iyzicoApiKey ?? this.iyzicoApiKey,
      iyzicoSecretKey: iyzicoSecretKey ?? this.iyzicoSecretKey,
      iyzicoApiUrl: iyzicoApiUrl ?? this.iyzicoApiUrl,
      globalOrdersEnabled: globalOrdersEnabled ?? this.globalOrdersEnabled,
      startupAnnouncementEnabled: startupAnnouncementEnabled ?? this.startupAnnouncementEnabled,
      startupAnnouncementTitle: startupAnnouncementTitle ?? this.startupAnnouncementTitle,
      startupAnnouncementMessage: startupAnnouncementMessage ?? this.startupAnnouncementMessage,
      startupAnnouncementType: startupAnnouncementType ?? this.startupAnnouncementType,
      startupAnnouncementButtonText: startupAnnouncementButtonText ?? this.startupAnnouncementButtonText,
      startupAnnouncementUpdatedAt: startupAnnouncementUpdatedAt ?? this.startupAnnouncementUpdatedAt,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
