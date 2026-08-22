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
  final String? iyzicoApiUrl;
  
  // Bakiye Sistemi
  final bool balanceEnabled;
  final bool cardTopupEnabled;
  final double minTopupAmount;
  final double maxTopupAmount;
  final double withdrawalFeePercent;
  final double minWithdrawalAmount;
  
  // Şirket Banka Hesabı
  final String? companyBankName;
  final String? companyIban;
  final String? companyAccountHolder;
  
  // Sipariş Kontrol
  final bool globalOrdersEnabled;
  
  // Açılış Duyurusu
  final bool startupAnnouncementEnabled;
  final String? startupAnnouncementTitle;
  final String? startupAnnouncementMessage;
  final String startupAnnouncementType;
  final String startupAnnouncementButtonText;
  final DateTime? startupAnnouncementUpdatedAt;
  
  // API Keys
  final String? googleMapsApiKey;
  
  // Animasyon Ayarları
  final int animationPrimaryDurationMs;
  final int animationSecondaryDurationMs;
  final int animationTransitionDurationMs;

  // Anasayfa Görünüm Ayarları
  /// Anasayfa kategori kartlarında gösterilecek maksimum kategori sayısı.
  /// Admin panelinden değiştirilebilir. 1-20 arası, varsayılan 4.
  final int homeCategoryLimit;

  /// Anasayfada gösterilecek maksimum haber kartı sayısı.
  /// Admin panelinden değiştirilebilir. 1-10 arası, varsayılan 3.
  final int homeNewsLimit;

  /// Anasayfada gösterilecek maksimum dükkan sayısı.
  /// Admin panelinden değiştirilebilir. 1-50 arası, varsayılan 8.
  final int homeShopLimit;

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
    this.iyzicoApiUrl,
    this.balanceEnabled = true,
    this.cardTopupEnabled = true,
    this.minTopupAmount = 10,
    this.maxTopupAmount = 10000,
    this.withdrawalFeePercent = 2,
    this.minWithdrawalAmount = 50,
    this.companyBankName,
    this.companyIban,
    this.companyAccountHolder,
    this.globalOrdersEnabled = true,
    this.startupAnnouncementEnabled = false,
    this.startupAnnouncementTitle,
    this.startupAnnouncementMessage,
    this.startupAnnouncementType = 'info',
    this.startupAnnouncementButtonText = 'Tamam',
    this.startupAnnouncementUpdatedAt,
    this.googleMapsApiKey,
    this.animationPrimaryDurationMs = 6000,
    this.animationSecondaryDurationMs = 3000,
    this.animationTransitionDurationMs = 700,
    this.homeCategoryLimit = 4,
    this.homeNewsLimit = 3,
    this.homeShopLimit = 8,
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
      iyzicoApiUrl: json['iyzico_api_url'] as String?,
      globalOrdersEnabled: json['global_orders_enabled'] as bool? ?? true,
      balanceEnabled: json['balance_enabled'] as bool? ?? true,
      cardTopupEnabled: json['card_topup_enabled'] as bool? ?? true,
      minTopupAmount: (json['min_topup_amount'] as num?)?.toDouble() ?? 10,
      maxTopupAmount: (json['max_topup_amount'] as num?)?.toDouble() ?? 10000,
      withdrawalFeePercent: (json['withdrawal_fee_percent'] as num?)?.toDouble() ?? 2,
      minWithdrawalAmount: (json['min_withdrawal_amount'] as num?)?.toDouble() ?? 50,
      companyBankName: json['company_bank_name'] as String?,
      companyIban: json['company_iban'] as String?,
      companyAccountHolder: json['company_account_holder'] as String?,
      startupAnnouncementEnabled: json['startup_announcement_enabled'] as bool? ?? false,
      startupAnnouncementTitle: json['startup_announcement_title'] as String?,
      startupAnnouncementMessage: json['startup_announcement_message'] as String?,
      startupAnnouncementType: json['startup_announcement_type'] as String? ?? 'info',
      startupAnnouncementButtonText: json['startup_announcement_button_text'] as String? ?? 'Tamam',
      startupAnnouncementUpdatedAt: json['startup_announcement_updated_at'] != null
          ? DateTime.parse(json['startup_announcement_updated_at'] as String)
          : null,
      googleMapsApiKey: json['google_maps_api_key'] as String?,
      animationPrimaryDurationMs: json['animation_primary_duration_ms'] as int? ?? 6000,
      animationSecondaryDurationMs: json['animation_secondary_duration_ms'] as int? ?? 3000,
      animationTransitionDurationMs: json['animation_transition_duration_ms'] as int? ?? 700,
      homeCategoryLimit: json['home_category_limit'] as int? ?? 4,
      homeNewsLimit: json['home_news_limit'] as int? ?? 3,
      homeShopLimit: json['home_shop_limit'] as int? ?? 8,
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
      'iyzico_api_url': iyzicoApiUrl,
      'global_orders_enabled': globalOrdersEnabled,
      'company_bank_name': companyBankName,
      'company_iban': companyIban,
      'company_account_holder': companyAccountHolder,
      'card_topup_enabled': cardTopupEnabled,
      'startup_announcement_enabled': startupAnnouncementEnabled,
      'startup_announcement_title': startupAnnouncementTitle,
      'startup_announcement_message': startupAnnouncementMessage,
      'startup_announcement_type': startupAnnouncementType,
      'startup_announcement_button_text': startupAnnouncementButtonText,
      'startup_announcement_updated_at': startupAnnouncementUpdatedAt?.toIso8601String(),
      'google_maps_api_key': googleMapsApiKey,
      'animation_primary_duration_ms': animationPrimaryDurationMs,
      'animation_secondary_duration_ms': animationSecondaryDurationMs,
      'animation_transition_duration_ms': animationTransitionDurationMs,
      'home_category_limit': homeCategoryLimit,
      'home_news_limit': homeNewsLimit,
      'home_shop_limit': homeShopLimit,
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
    String? iyzicoApiUrl,
    bool? globalOrdersEnabled,
    bool? startupAnnouncementEnabled,
    String? startupAnnouncementTitle,
    String? startupAnnouncementMessage,
    String? startupAnnouncementType,
    String? startupAnnouncementButtonText,
    DateTime? startupAnnouncementUpdatedAt,
    String? googleMapsApiKey,
    bool? balanceEnabled,
    bool? cardTopupEnabled,
    double? minTopupAmount,
    double? maxTopupAmount,
    double? withdrawalFeePercent,
    double? minWithdrawalAmount,
    String? companyBankName,
    String? companyIban,
    String? companyAccountHolder,
    int? animationPrimaryDurationMs,
    int? animationSecondaryDurationMs,
    int? animationTransitionDurationMs,
    int? homeCategoryLimit,
    int? homeNewsLimit,
    int? homeShopLimit,
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
      iyzicoApiUrl: iyzicoApiUrl ?? this.iyzicoApiUrl,
      globalOrdersEnabled: globalOrdersEnabled ?? this.globalOrdersEnabled,
      startupAnnouncementEnabled: startupAnnouncementEnabled ?? this.startupAnnouncementEnabled,
      startupAnnouncementTitle: startupAnnouncementTitle ?? this.startupAnnouncementTitle,
      startupAnnouncementMessage: startupAnnouncementMessage ?? this.startupAnnouncementMessage,
      startupAnnouncementType: startupAnnouncementType ?? this.startupAnnouncementType,
      startupAnnouncementButtonText: startupAnnouncementButtonText ?? this.startupAnnouncementButtonText,
      startupAnnouncementUpdatedAt: startupAnnouncementUpdatedAt ?? this.startupAnnouncementUpdatedAt,
      googleMapsApiKey: googleMapsApiKey ?? this.googleMapsApiKey,
      balanceEnabled: balanceEnabled ?? this.balanceEnabled,
      cardTopupEnabled: cardTopupEnabled ?? this.cardTopupEnabled,
      minTopupAmount: minTopupAmount ?? this.minTopupAmount,
      maxTopupAmount: maxTopupAmount ?? this.maxTopupAmount,
      withdrawalFeePercent: withdrawalFeePercent ?? this.withdrawalFeePercent,
      minWithdrawalAmount: minWithdrawalAmount ?? this.minWithdrawalAmount,
      companyBankName: companyBankName ?? this.companyBankName,
      companyIban: companyIban ?? this.companyIban,
      companyAccountHolder: companyAccountHolder ?? this.companyAccountHolder,
      animationPrimaryDurationMs: animationPrimaryDurationMs ?? this.animationPrimaryDurationMs,
      animationSecondaryDurationMs: animationSecondaryDurationMs ?? this.animationSecondaryDurationMs,
      animationTransitionDurationMs: animationTransitionDurationMs ?? this.animationTransitionDurationMs,
      homeCategoryLimit: homeCategoryLimit ?? this.homeCategoryLimit,
      homeNewsLimit: homeNewsLimit ?? this.homeNewsLimit,
      homeShopLimit: homeShopLimit ?? this.homeShopLimit,
      createdAt: createdAt,
      updatedAt: DateTime.now(),
    );
  }
}
