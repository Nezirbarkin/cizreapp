/// AI sohbet sistemi global ayarları (tek satır tablo)
class AISettings {
  // Geriye dönük uyumluluk: eski tek "provider" alanı.
  // Artık text/vision/image için ayrı sağlayıcılar var; bu alan
  // text_provider boşsa fallback olarak kullanılır.
  final String provider;

  // Her görev türü için bağımsız varsayılan sağlayıcı
  // Değerler: 'pollinations' | 'gemini' | 'groq' | 'openrouter' | 'openai' | 'huggingface'
  final String? textProvider;
  final String? visionProvider;
  final String? imageProvider;

  // Gemini modelleri
  final String textModel;
  final String visionModel;
  final String imageModel;

  // Groq modelleri
  final String groqTextModel;
  final String groqVisionModel;

  // OpenRouter modelleri
  final String openrouterTextModel;
  final String openrouterVisionModel;
  final String openrouterImageModel;

  // OpenAI modelleri
  final String openaiTextModel;
  final String openaiVisionModel;
  final String openaiImageModel;

  // Pollinations modelleri (ücretsiz, anahtarsız)
  final String pollinationsTextModel;
  final String pollinationsImageModel;

  // HuggingFace modelleri (ücretsiz inference)
  final String huggingfaceTextModel;

  // Limitler
  final int dailyRequestLimitPerUser;
  final int dailyTokenLimitPerUser;
  final int maxMessagesPerConversation;

  // Özellikler
  final bool allowImageUpload;
  final bool allowImageGeneration;
  final bool allowCameraCapture;

  // Davranış
  final String systemPrompt;
  final double temperature;
  final int maxOutputTokens;

  // API anahtarları (admin panelde girilir, settings tablosunda saklanır)
  final String? geminiApiKey;
  final String? groqApiKey;
  final String? openrouterApiKey;
  final String? openaiApiKey;
  final String? huggingfaceApiKey;

  // Vault anahtar varlık durumu (admin UI için)
  final bool geminiKeySet;
  final bool groqKeySet;
  final bool openrouterKeySet;
  final bool openaiKeySet;
  final bool huggingfaceKeySet;

  AISettings({
    required this.enabled,
    required this.provider,
    required this.textModel,
    required this.visionModel,
    required this.imageModel,
    required this.groqTextModel,
    required this.groqVisionModel,
    required this.openrouterTextModel,
    required this.openrouterVisionModel,
    required this.openrouterImageModel,
    required this.openaiTextModel,
    required this.openaiVisionModel,
    required this.openaiImageModel,
    required this.dailyRequestLimitPerUser,
    required this.dailyTokenLimitPerUser,
    required this.maxMessagesPerConversation,
    required this.allowImageUpload,
    required this.allowImageGeneration,
    required this.allowCameraCapture,
    required this.systemPrompt,
    required this.temperature,
    required this.maxOutputTokens,
    this.textProvider,
    this.visionProvider,
    this.imageProvider,
    this.pollinationsTextModel = 'openai',
    this.pollinationsImageModel = 'flux',
    this.huggingfaceTextModel = 'meta-llama/Llama-3.2-3B-Instruct',
    this.geminiApiKey,
    this.groqApiKey,
    this.openrouterApiKey,
    this.openaiApiKey,
    this.huggingfaceApiKey,
    this.geminiKeySet = false,
    this.groqKeySet = false,
    this.openrouterKeySet = false,
    this.openaiKeySet = false,
    this.huggingfaceKeySet = false,
  });

  final bool enabled;

  factory AISettings.fromMap(Map<String, dynamic> map) {
    final provider = (map['provider'] as String?) ?? 'pollinations';
    return AISettings(
      enabled: (map['enabled'] as bool?) ?? true,
      provider: provider,
      // Yeni kolonlar boşsa eski provider'a fallback (geriye dönük uyum)
      textProvider: (map['text_provider'] as String?) ?? provider,
      visionProvider: (map['vision_provider'] as String?) ?? provider,
      imageProvider: (map['image_provider'] as String?) ?? provider,
      textModel: (map['text_model'] as String?) ?? 'gemini-2.0-flash',
      visionModel: (map['vision_model'] as String?) ?? 'gemini-2.0-flash',
      imageModel: (map['image_model'] as String?) ?? 'imagen-3.0-generate-002',
      groqTextModel: (map['groq_text_model'] as String?) ?? 'llama-3.3-70b-versatile',
      groqVisionModel: (map['groq_vision_model'] as String?) ?? 'llama-3.2-90b-vision-preview',
      openrouterTextModel: (map['openrouter_text_model'] as String?) ?? 'google/gemini-2.0-flash-exp:free',
      openrouterVisionModel: (map['openrouter_vision_model'] as String?) ?? 'google/gemini-2.0-flash-exp:free',
      openrouterImageModel: (map['openrouter_image_model'] as String?) ?? 'stable-diffusion-xl',
      openaiTextModel: (map['openai_text_model'] as String?) ?? 'gpt-4o-mini',
      openaiVisionModel: (map['openai_vision_model'] as String?) ?? 'gpt-4o-mini',
      openaiImageModel: (map['openai_image_model'] as String?) ?? 'dall-e-3',
      pollinationsTextModel: (map['pollinations_text_model'] as String?) ?? 'openai',
      pollinationsImageModel: (map['pollinations_image_model'] as String?) ?? 'flux',
      huggingfaceTextModel: (map['huggingface_text_model'] as String?) ?? 'meta-llama/Llama-3.2-3B-Instruct',
      dailyRequestLimitPerUser: (map['daily_request_limit_per_user'] as num?)?.toInt() ?? 50,
      dailyTokenLimitPerUser: (map['daily_token_limit_per_user'] as num?)?.toInt() ?? 100000,
      maxMessagesPerConversation: (map['max_messages_per_conversation'] as num?)?.toInt() ?? 100,
      allowImageUpload: (map['allow_image_upload'] as bool?) ?? true,
      allowImageGeneration: (map['allow_image_generation'] as bool?) ?? true,
      allowCameraCapture: (map['allow_camera_capture'] as bool?) ?? true,
      systemPrompt: (map['system_prompt'] as String?) ?? '',
      temperature: ((map['temperature'] as num?) ?? 0.7).toDouble(),
      maxOutputTokens: (map['max_output_tokens'] as num?)?.toInt() ?? 2048,
      geminiApiKey: map['gemini_api_key'] as String?,
      groqApiKey: map['groq_api_key'] as String?,
      openrouterApiKey: map['openrouter_api_key'] as String?,
      openaiApiKey: map['openai_api_key'] as String?,
      huggingfaceApiKey: map['huggingface_api_key'] as String?,
      geminiKeySet: (map['gemini_key_set'] as bool?) ?? (map['gemini_api_key'] as String?)?.isNotEmpty ?? false,
      groqKeySet: (map['groq_key_set'] as bool?) ?? (map['groq_api_key'] as String?)?.isNotEmpty ?? false,
      openrouterKeySet: (map['openrouter_key_set'] as bool?) ?? (map['openrouter_api_key'] as String?)?.isNotEmpty ?? false,
      openaiKeySet: (map['openai_key_set'] as bool?) ?? (map['openai_api_key'] as String?)?.isNotEmpty ?? false,
      huggingfaceKeySet: (map['huggingface_key_set'] as bool?) ?? (map['huggingface_api_key'] as String?)?.isNotEmpty ?? false,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'enabled': enabled,
      'provider': provider,
      'text_provider': textProvider ?? provider,
      'vision_provider': visionProvider ?? provider,
      'image_provider': imageProvider ?? provider,
      'text_model': textModel,
      'vision_model': visionModel,
      'image_model': imageModel,
      'groq_text_model': groqTextModel,
      'groq_vision_model': groqVisionModel,
      'openrouter_text_model': openrouterTextModel,
      'openrouter_vision_model': openrouterVisionModel,
      'openrouter_image_model': openrouterImageModel,
      'openai_text_model': openaiTextModel,
      'openai_vision_model': openaiVisionModel,
      'openai_image_model': openaiImageModel,
      'pollinations_text_model': pollinationsTextModel,
      'pollinations_image_model': pollinationsImageModel,
      'huggingface_text_model': huggingfaceTextModel,
      'daily_request_limit_per_user': dailyRequestLimitPerUser,
      'daily_token_limit_per_user': dailyTokenLimitPerUser,
      'max_messages_per_conversation': maxMessagesPerConversation,
      'allow_image_upload': allowImageUpload,
      'allow_image_generation': allowImageGeneration,
      'allow_camera_capture': allowCameraCapture,
      'system_prompt': systemPrompt,
      'temperature': temperature,
      'max_output_tokens': maxOutputTokens,
      'gemini_api_key': geminiApiKey,
      'groq_api_key': groqApiKey,
      'openrouter_api_key': openrouterApiKey,
      'openai_api_key': openaiApiKey,
      'huggingface_api_key': huggingfaceApiKey,
    };
  }

  /// Bir sağlayıcı API anahtarı gerektiriyor mu?
  static bool requiresApiKey(String providerName) {
    switch (providerName.toLowerCase()) {
      case 'pollinations':
        return false; // Ücretsiz, anahtarsız
      case 'huggingface':
        // Çoğu inference API anahtarsız çalışır ama rate-limit için önerilir
        return false;
      default:
        return true;
    }
  }

  /// Belirli bir görev için seçili sağlayıcı adını döndürür
  String providerForTask(String task) {
    switch (task) {
      case 'vision':
        return (visionProvider?.isNotEmpty ?? false) ? visionProvider! : provider;
      case 'image':
        return (imageProvider?.isNotEmpty ?? false) ? imageProvider! : provider;
      case 'text':
      default:
        return (textProvider?.isNotEmpty ?? false) ? textProvider! : provider;
    }
  }

  /// Sağlayıcı için okunabilir ad
  String get providerLabel {
    switch (provider.toLowerCase()) {
      case 'pollinations':
        return 'Pollinations (Ücretsiz)';
      case 'gemini':
        return 'Gemini';
      case 'groq':
        return 'Groq';
      case 'openrouter':
        return 'OpenRouter';
      case 'openai':
        return 'OpenAI';
      case 'huggingface':
        return 'HuggingFace (Ücretsiz)';
      default:
        return provider;
    }
  }

  AISettings copyWith({
    bool? enabled,
    String? provider,
    String? textProvider,
    String? visionProvider,
    String? imageProvider,
    String? textModel,
    String? visionModel,
    String? imageModel,
    String? groqTextModel,
    String? groqVisionModel,
    String? openrouterTextModel,
    String? openrouterVisionModel,
    String? openrouterImageModel,
    String? openaiTextModel,
    String? openaiVisionModel,
    String? openaiImageModel,
    String? pollinationsTextModel,
    String? pollinationsImageModel,
    String? huggingfaceTextModel,
    int? dailyRequestLimitPerUser,
    int? dailyTokenLimitPerUser,
    int? maxMessagesPerConversation,
    bool? allowImageUpload,
    bool? allowImageGeneration,
    bool? allowCameraCapture,
    String? systemPrompt,
    double? temperature,
    int? maxOutputTokens,
    String? geminiApiKey,
    String? groqApiKey,
    String? openrouterApiKey,
    String? openaiApiKey,
    String? huggingfaceApiKey,
    bool? geminiKeySet,
    bool? groqKeySet,
    bool? openrouterKeySet,
    bool? openaiKeySet,
    bool? huggingfaceKeySet,
  }) {
    return AISettings(
      enabled: enabled ?? this.enabled,
      provider: provider ?? this.provider,
      textProvider: textProvider ?? this.textProvider,
      visionProvider: visionProvider ?? this.visionProvider,
      imageProvider: imageProvider ?? this.imageProvider,
      textModel: textModel ?? this.textModel,
      visionModel: visionModel ?? this.visionModel,
      imageModel: imageModel ?? this.imageModel,
      groqTextModel: groqTextModel ?? this.groqTextModel,
      groqVisionModel: groqVisionModel ?? this.groqVisionModel,
      openrouterTextModel: openrouterTextModel ?? this.openrouterTextModel,
      openrouterVisionModel: openrouterVisionModel ?? this.openrouterVisionModel,
      openrouterImageModel: openrouterImageModel ?? this.openrouterImageModel,
      openaiTextModel: openaiTextModel ?? this.openaiTextModel,
      openaiVisionModel: openaiVisionModel ?? this.openaiVisionModel,
      openaiImageModel: openaiImageModel ?? this.openaiImageModel,
      pollinationsTextModel: pollinationsTextModel ?? this.pollinationsTextModel,
      pollinationsImageModel: pollinationsImageModel ?? this.pollinationsImageModel,
      huggingfaceTextModel: huggingfaceTextModel ?? this.huggingfaceTextModel,
      dailyRequestLimitPerUser: dailyRequestLimitPerUser ?? this.dailyRequestLimitPerUser,
      dailyTokenLimitPerUser: dailyTokenLimitPerUser ?? this.dailyTokenLimitPerUser,
      maxMessagesPerConversation: maxMessagesPerConversation ?? this.maxMessagesPerConversation,
      allowImageUpload: allowImageUpload ?? this.allowImageUpload,
      allowImageGeneration: allowImageGeneration ?? this.allowImageGeneration,
      allowCameraCapture: allowCameraCapture ?? this.allowCameraCapture,
      systemPrompt: systemPrompt ?? this.systemPrompt,
      temperature: temperature ?? this.temperature,
      maxOutputTokens: maxOutputTokens ?? this.maxOutputTokens,
      geminiApiKey: geminiApiKey ?? this.geminiApiKey,
      groqApiKey: groqApiKey ?? this.groqApiKey,
      openrouterApiKey: openrouterApiKey ?? this.openrouterApiKey,
      openaiApiKey: openaiApiKey ?? this.openaiApiKey,
      huggingfaceApiKey: huggingfaceApiKey ?? this.huggingfaceApiKey,
      geminiKeySet: geminiKeySet ?? this.geminiKeySet,
      groqKeySet: groqKeySet ?? this.groqKeySet,
      openrouterKeySet: openrouterKeySet ?? this.openrouterKeySet,
      openaiKeySet: openaiKeySet ?? this.openaiKeySet,
      huggingfaceKeySet: huggingfaceKeySet ?? this.huggingfaceKeySet,
    );
  }
}

/// Kullanıcı günlük kullanımı
class AIDailyUsage {
  final int requestCount;
  final int tokenCount;
  final int imageGenerationCount;
  final DateTime? lastRequestAt;

  AIDailyUsage({
    required this.requestCount,
    required this.tokenCount,
    required this.imageGenerationCount,
    this.lastRequestAt,
  });

  factory AIDailyUsage.empty() => AIDailyUsage(
        requestCount: 0,
        tokenCount: 0,
        imageGenerationCount: 0,
      );

  factory AIDailyUsage.fromMap(Map<String, dynamic> map) {
    final lastRequest = map['last_request_at'];
    return AIDailyUsage(
      requestCount: (map['request_count'] as num?)?.toInt() ?? 0,
      tokenCount: (map['token_count'] as num?)?.toInt() ?? 0,
      imageGenerationCount: (map['image_generation_count'] as num?)?.toInt() ?? 0,
      lastRequestAt: lastRequest == null
          ? null
          : (lastRequest is DateTime ? lastRequest : DateTime.tryParse(lastRequest.toString())),
    );
  }
}

/// Admin istatistikleri
class AIUsageStats {
  final int totalConversations;
  final int totalMessages;
  final int totalUsers;
  final int todayRequests;
  final int todayTokens;
  final int totalTokens;
  final int geminiCount;
  final int groqCount;
  final int openrouterCount;
  final int openaiCount;
  final List<AIDailyBreakdown> dailyBreakdown;

  AIUsageStats({
    required this.totalConversations,
    required this.totalMessages,
    required this.totalUsers,
    required this.todayRequests,
    required this.todayTokens,
    required this.totalTokens,
    required this.geminiCount,
    required this.groqCount,
    required this.openrouterCount,
    required this.openaiCount,
    required this.dailyBreakdown,
  });

  factory AIUsageStats.fromMap(Map<String, dynamic> map) {
    final provDist = (map['provider_distribution'] as Map<String, dynamic>?) ?? {};
    final breakdownRaw = map['daily_breakdown'] as List?;
    return AIUsageStats(
      totalConversations: (map['total_conversations'] as num?)?.toInt() ?? 0,
      totalMessages: (map['total_messages'] as num?)?.toInt() ?? 0,
      totalUsers: (map['total_users'] as num?)?.toInt() ?? 0,
      todayRequests: (map['today_requests'] as num?)?.toInt() ?? 0,
      todayTokens: (map['today_tokens'] as num?)?.toInt() ?? 0,
      totalTokens: (map['total_tokens'] as num?)?.toInt() ?? 0,
      geminiCount: (provDist['gemini'] as num?)?.toInt() ?? 0,
      groqCount: (provDist['groq'] as num?)?.toInt() ?? 0,
      openrouterCount: (provDist['openrouter'] as num?)?.toInt() ?? 0,
      openaiCount: (provDist['openai'] as num?)?.toInt() ?? 0,
      dailyBreakdown: (breakdownRaw ?? [])
          .map((e) => e is Map<String, dynamic> ? AIDailyBreakdown.fromMap(e) : null)
          .whereType<AIDailyBreakdown>()
          .toList(),
    );
  }

  factory AIUsageStats.empty() => AIUsageStats(
        totalConversations: 0,
        totalMessages: 0,
        totalUsers: 0,
        todayRequests: 0,
        todayTokens: 0,
        totalTokens: 0,
        geminiCount: 0,
        groqCount: 0,
        openrouterCount: 0,
        openaiCount: 0,
        dailyBreakdown: [],
      );
}

/// Günlük kırılım (grafik için)
class AIDailyBreakdown {
  final String date;
  final int requests;
  final int tokens;
  final int images;

  AIDailyBreakdown({
    required this.date,
    required this.requests,
    required this.tokens,
    required this.images,
  });

  factory AIDailyBreakdown.fromMap(Map<String, dynamic> map) {
    return AIDailyBreakdown(
      date: (map['date'] as String?) ?? '',
      requests: (map['requests'] as num?)?.toInt() ?? 0,
      tokens: (map['tokens'] as num?)?.toInt() ?? 0,
      images: (map['images'] as num?)?.toInt() ?? 0,
    );
  }
}