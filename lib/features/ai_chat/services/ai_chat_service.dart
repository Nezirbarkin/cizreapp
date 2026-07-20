import '../../../core/models/ai_quick_prompt_model.dart';
import '../../../core/models/ai_prompt_image_model.dart';

// ignore_for_file: unnecessary_brace_in_string_interps

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/ai_conversation_model.dart';
import '../../../core/models/ai_message_model.dart';
import '../../../core/models/ai_settings_model.dart';
import '../../../core/utils/app_logger.dart';

/// AI chat yanıt modeli (edge function dönen)
class AIChatResponse {
  final String conversationId;
  final String userMessageId;
  final String assistantMessageId;
  final String assistantContent;
  final List<String> generatedImages;
  final int tokensUsed;
  final int requestCount;
  final int tokenCount;
  final int dailyLimitRemaining;

  AIChatResponse({
    required this.conversationId,
    required this.userMessageId,
    required this.assistantMessageId,
    required this.assistantContent,
    required this.generatedImages,
    required this.tokensUsed,
    required this.requestCount,
    required this.tokenCount,
    required this.dailyLimitRemaining,
  });

  factory AIChatResponse.fromMap(Map<String, dynamic> map) {
    final usage = (map['usage'] as Map<String, dynamic>?) ?? {};
    return AIChatResponse(
      conversationId: map['conversation_id'] as String? ?? '',
      userMessageId: map['user_message_id'] as String? ?? '',
      assistantMessageId: map['assistant_message_id'] as String? ?? '',
      assistantContent: map['assistant_content'] as String? ?? '',
      generatedImages: (map['generated_images'] as List?)?.cast<String>() ?? [],
      tokensUsed: (map['tokens_used'] as num?)?.toInt() ?? 0,
      requestCount: (usage['request_count'] as num?)?.toInt() ?? 0,
      tokenCount: (usage['token_count'] as num?)?.toInt() ?? 0,
      dailyLimitRemaining: (usage['daily_limit_remaining'] as num?)?.toInt() ?? 0,
    );
  }
}

/// AI chat istisnaları
class AIChatException implements Exception {
  final String message;
  final String code;
  AIChatException(this.message, {this.code = 'unknown'});

  @override
  String toString() => message;
}

/// AI Chat servisi — Supabase Edge Function ile iletişim kurar.
///
/// Tüm API anahtarı/limit/maliyet işleri edge function tarafında yapılır.
/// Bu servis yalnızca istemci tarafı CRUD + dosya yükleme + çağrı sarmalayıcıdır.
class AIChatService {
  static const String _functionName = 'ai-chat-proxy';

  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      rethrow;
    }
  }

  /// Mevcut kullanıcı ID'sini döndürür, yoksa null.
  String? get currentUserId => _supabase.auth.currentUser?.id;

  // =====================================================
  // AYARLAR (kullanıcı okur, admin yazar)
  // =====================================================

  /// Sistem ayarlarını getir (enabled + özellik bayrakları için)
  Future<AISettings> getSettings() async {
    try {
      final data = await _supabase
          .from('ai_settings')
          .select('*')
          .eq('id', 1)
          .maybeSingle();
      if (data == null) {
        // Henüz seed yoksa varsayılan döndür
        return AISettings(
          enabled: false,
          provider: 'gemini',
          textModel: 'gemini-2.0-flash',
          visionModel: 'gemini-2.0-flash',
          imageModel: 'imagen-3.0-generate-002',
          groqTextModel: 'llama-3.3-70b-versatile',
          groqVisionModel: 'llama-3.2-90b-vision-preview',
          openrouterTextModel: 'google/gemini-2.0-flash-exp:free',
          openrouterVisionModel: 'google/gemini-2.0-flash-exp:free',
          openrouterImageModel: 'stable-diffusion-xl',
          openaiTextModel: 'gpt-4o-mini',
          openaiVisionModel: 'gpt-4o-mini',
          openaiImageModel: 'dall-e-3',
          dailyRequestLimitPerUser: 50,
          dailyTokenLimitPerUser: 100000,
          maxMessagesPerConversation: 100,
          allowImageUpload: true,
          allowImageGeneration: true,
          allowCameraCapture: true,
          systemPrompt: '',
          temperature: 0.7,
          maxOutputTokens: 2048,
        );
      }
      return AISettings.fromMap(data);
    } catch (e) {
      AppLogger.error('AI ayarları yüklenemedi: $e');
      rethrow;
    }
  }

  /// Admin: Ayarları günceller
  Future<void> updateSettings(AISettings settings) async {
    try {
      // Önce mevcut veriyi kontrol et
      final currentData = await _supabase
          .from('ai_settings')
          .select('id')
          .eq('id', 1)
          .maybeSingle();
      
      if (currentData == null) {
        // Kayıt yoksa INSERT
        await _supabase
            .from('ai_settings')
            .insert({
              ...settings.toMap(),
              'id': 1,
              'updated_at': DateTime.now().toIso8601String(),
              'updated_by': currentUserId,
            });
      } else {
        // Kayıt varsa UPDATE
        await _supabase
            .from('ai_settings')
            .update({
              ...settings.toMap(),
              'id': 1,
              'updated_at': DateTime.now().toIso8601String(),
              'updated_by': currentUserId,
            })
            .eq('id', 1);
      }
      
    } catch (e) {
      AppLogger.error('AI ayar güncelleme hatası: $e');
      rethrow;
    }
  }

  /// Admin: API anahtarı varlık durumu sorgular (vault'tan)
  /// NOT: Bu bilgi edge function üzerinden alınır; şu an için basit bir
  /// health-check yaparak anahtarın set edilip edilmediğini tahmin eder.
  Future<Map<String, bool>> getApiKeyStatus() async {
    // Edge function'a boş bir test çağrısı yaparız; hata kodundan çıkarım yapılır.
    // Şimdilik her ikisinin de set edildiğini varsay (admin manuel test eder).
    return {'gemini': false, 'openai': false};
  }

  // =====================================================
  // GÜNLÜK KULLANIM
  // =====================================================

  /// Mevcut kullanıcının bugünkü kullanımını getirir
  Future<AIDailyUsage> getDailyUsage() async {
    final userId = currentUserId;
    if (userId == null) return AIDailyUsage.empty();
    try {
      final data = await _supabase
          .from('ai_daily_usage')
          .select()
          .eq('user_id', userId)
          .eq('usage_date', DateTime.now().toUtc().toIso8601String().substring(0, 10))
          .maybeSingle();
      if (data == null) return AIDailyUsage.empty();
      return AIDailyUsage.fromMap(data);
    } catch (e) {
      debugPrint('Günlük kullanım yüklenemedi: $e');
      return AIDailyUsage.empty();
    }
  }

  // =====================================================
  // KONUŞMALAR (CRUD)
  // =====================================================

  /// Kullanıcı konuşmalarını listeler (son mesaj önizlemesiyle)
  Future<List<AIConversation>> getConversations({bool includeArchived = false}) async {
    final userId = currentUserId;
    if (userId == null) return [];
    try {
      // View kullanarak son mesaj önizlemesiyle birlikte al
      final baseQuery = _supabase
          .from('ai_conversations_with_preview')
          .select('*')
          .eq('user_id', userId);
      final filtered = includeArchived
          ? baseQuery
          : baseQuery.eq('is_archived', false);
      final data = await filtered.order('last_message_at', ascending: false);
      return data.map((e) => AIConversation.fromMap(e)).toList();
    } catch (e) {
      // View yoksa fallback - eski tablo kullan
      AppLogger.error('View hatası, fallback: $e');
      try {
        final baseQuery = _supabase
            .from('ai_conversations')
            .select('*')
            .eq('user_id', userId);
        final filtered = includeArchived
            ? baseQuery
            : baseQuery.eq('is_archived', false);
        final data = await filtered.order('last_message_at', ascending: false);
        return data.map((e) => AIConversation.fromMap(e)).toList();
      } catch (e2) {
        AppLogger.error('AI konuşmaları yüklenemedi: $e2');
        rethrow;
      }
    }
  }

  /// Konuşmayı ID'ye göre getirir
  Future<AIConversation?> getConversation(String id) async {
    try {
      final data = await _supabase
          .from('ai_conversations')
          .select('*')
          .eq('id', id)
          .maybeSingle();
      if (data == null) return null;
      return AIConversation.fromMap(data);
    } catch (e) {
      AppLogger.error('Konuşma yüklenemedi: $e');
      rethrow;
    }
  }

  /// Konuşmayı arşivler
  Future<void> archiveConversation(String id) async {
    try {
      await _supabase
          .from('ai_conversations')
          .update({'is_archived': true})
          .eq('id', id);
    } catch (e) {
      throw AIChatException('Arşivleme başarısız: $e');
    }
  }

  /// Konuşmayı siler (cascade: mesajlar da silinir)
  Future<void> deleteConversation(String id) async {
    try {
      await _supabase
          .from('ai_conversations')
          .delete()
          .eq('id', id);
    } catch (e) {
      throw AIChatException('Silme başarısız: $e');
    }
  }

  // =====================================================
  // MESAJLAR
  // =====================================================

  /// Konuşmadaki tüm mesajları getirir
  Future<List<AIMessage>> getMessages(String conversationId) async {
    try {
      final data = await _supabase
          .from('ai_messages')
          .select('*')
          .eq('conversation_id', conversationId)
          .order('created_at', ascending: true);
      return data.map((e) => AIMessage.fromMap(e)).toList();
    } catch (e) {
      AppLogger.error('Mesajlar yüklenemedi: $e');
      rethrow;
    }
  }

  // =====================================================
  // DOSYA YÜKLEME (resim)
  // =====================================================

  /// Resmi Supabase Storage'a yükler ve storage path döndürür.
  /// [bytes] = dosya içeriği, [fileName] = dosya adı, [mimeType] = MIME tipi.
  Future<String> uploadImage({
    required Uint8List bytes,
    required String fileName,
    required String mimeType,
  }) async {
    final userId = currentUserId;
    if (userId == null) throw AIChatException('Giriş yapmalısınız', code: 'unauthorized');

    final path = '$userId/${DateTime.now().millisecondsSinceEpoch}_$fileName';

    try {
      await _supabase.storage
          .from('ai-uploads')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(contentType: mimeType, upsert: false),
          );
      return 'ai-uploads/$path';
    } catch (e) {
      AppLogger.error('Resim yükleme hatası: $e');
      throw AIChatException('Resim yüklenemedi: $e', code: 'upload_error');
    }
  }

  // =====================================================
  // MESAJ GÖNDERME (Edge Function)
  // =====================================================

  /// Metin mesajı gönderir ve AI yanıtını döndürür.
  /// [conversationId] null ise yeni konuşma oluşturulur.
  Future<AIChatResponse> sendTextMessage({
    String? conversationId,
    required String message,
  }) async {
    return _invokeEdgeFunction(
      body: {
        'conversation_id': conversationId,
        'message': message,
        'action': 'text',
      },
    );
  }

  /// Vision mesajı gönderir (resim + metin).
  /// [attachments] = storage path listesi (uploadImage'den dönen)
  Future<AIChatResponse> sendVisionMessage({
    String? conversationId,
    required String message,
    required List<({String storagePath, String mimeType})> attachments,
  }) async {
    return _invokeEdgeFunction(
      body: {
        'conversation_id': conversationId,
        'message': message,
        'attachments': attachments
            .map((a) => {'storage_path': a.storagePath, 'mime_type': a.mimeType})
            .toList(),
        'action': 'vision',
      },
    );
  }

  /// AI ile görsel üretir.
  Future<AIChatResponse> generateImage({
    String? conversationId,
    required String prompt,
    int n = 1,
  }) async {
    return _invokeEdgeFunction(
      body: {
        'conversation_id': conversationId,
        'message': prompt,
        'generate_prompt': prompt,
        'action': 'generate_image',
        'n': n,
      },
    );
  }

  /// Edge function çağrısı — merkezi hata yönetimi
  Future<AIChatResponse> _invokeEdgeFunction({required Map<String, dynamic> body}) async {
    try {
      final response = await _supabase.functions.invoke(
        _functionName,
        body: body,
      );

      final data = response.data as Map<String, dynamic>?;
      if (data == null) {
        debugPrint('❌ AI Edge Function boş yanıt döndü');
        throw AIChatException('Boş yanıt alındı', code: 'empty_response');
      }

      // Hata yanıtı mı?
      if (data.containsKey('error') && data['error'] != null) {
        final errMsg = data['error'] as String? ?? 'Bilinmeyen hata';
        final errCode = data['code'] as String? ?? 'unknown';
        debugPrint('❌ AI Edge Function hata döndü: $errMsg (code: $errCode)');

        // Türkçe hata mesajları
        String friendlyMsg = errMsg;
        switch (errCode) {
          case 'limit_exceeded':
            friendlyMsg = errMsg; // zaten Türkçe
            break;
          case 'feature_disabled':
            friendlyMsg = 'Bu özellik şu anda kapalı.';
            break;
          case 'unauthorized':
            friendlyMsg = 'Lütfen giriş yapın.';
            break;
          case 'ai_error':
            friendlyMsg = 'Yapay zeka yanıtı alınamadı: $errMsg';
            break;
          case 'settings_error':
            friendlyMsg = 'Sistem yapılandırılmamış. Daha sonra tekrar deneyin.';
            break;
        }
        throw AIChatException(friendlyMsg, code: errCode);
      }

      // Başarılı yanıt
      debugPrint('✅ AI Edge Function başarılı yanıt: contentLength=${data['content']?.toString().length ?? 0}');
      return AIChatResponse.fromMap(data);
    } on AIChatException {
      rethrow;
    } on FunctionException catch (e) {
      // Supabase functions invoke HTTP hatası
      debugPrint('❌ AI FunctionException: $e');
      // Supabase functions invoke HTTP hatası
      final details = e.toString();
      String friendly = 'Bağlantı hatası. İnternet bağlantınızı kontrol edin.';
      if (details.contains('401') || details.contains('403')) {
        friendly = 'Yetkisiz erişim. Lütfen tekrar giriş yapın.';
      } else if (details.contains('429')) {
        friendly = 'Günlük limitiniz doldu. Lütfen yarın tekrar deneyin.';
      } else if (details.contains('502') || details.contains('503')) {
        friendly = 'Sunucu geçici olarak erişilemiyor. Lütfen tekrar deneyin.';
      }
      throw AIChatException(friendly, code: 'function_error');
    } catch (e) {
      debugPrint('❌ AI mesaj gönderme beklenmeyen hata: $e');
      AppLogger.error('AI mesaj gönderme hatası: $e');
      throw AIChatException('Beklenmeyen bir hata oluştu: $e', code: 'unknown');
    }
  }

  // =====================================================
  // ADMIN: İSTATİSTİKLER
  // =====================================================

  /// Admin: Sistem istatistiklerini getirir
  Future<AIUsageStats> getUsageStats({int days = 7}) async {
    try {
      final response = await _supabase.rpc('ai_get_admin_stats', params: {
        'p_days': days,
      });
      if (response == null) return AIUsageStats.empty();
      
      // RPC TABLE döndürdüğünde Supabase genellikle liste döner
      Map<String, dynamic> data;
      if (response is List) {
        if (response.isEmpty) return AIUsageStats.empty();
        data = Map<String, dynamic>.from(response.first as Map);
      } else if (response is Map) {
        data = Map<String, dynamic>.from(response);
      } else {
        AppLogger.error('AI istatistik: beklenmeyen RPC yanıt tipi: ${response.runtimeType}');
        return AIUsageStats.empty();
      }

      return AIUsageStats.fromMap(data);
    } catch (e) {
      AppLogger.error('AI istatistik yüklenemedi: $e');
      return AIUsageStats.empty();
    }
  }

  /// Admin: Tüm konuşmaları listeler (denetim için)
  Future<List<AIConversation>> getAllConversations({int limit = 50}) async {
    try {
      final data = await _supabase
          .from('ai_conversations')
          .select('*')
          .order('last_message_at', ascending: false)
          .limit(limit);
      return data.map((e) => AIConversation.fromMap(e)).toList();
    } catch (e) {
      AppLogger.error('Tüm konuşmalar yüklenemedi: $e');
      return [];
    }
  }

  /// Admin: Bir konuşmadaki tüm mesajları getirir (denetim için)
  Future<List<AIMessage>> getAllMessages(String conversationId) async {
    return getMessages(conversationId);
  }

  // =====================================================
  // HIZLI ŞABLONLAR (QUICK PROMPTS) CRUD
  // =====================================================

  /// Aktif hızlı şablonları getir
  Future<List<AIQuickPrompt>> getActiveQuickPrompts() async {
    try {
      final data = await _supabase
          .from('ai_quick_prompts')
          .select('*')
          .eq('is_active', true)
          .order('sort_order', ascending: true);
      return data.map((e) => AIQuickPrompt.fromMap(e)).toList();
    } catch (e) {
      AppLogger.error('Hızlı şablonlar yüklenemedi: $e');
      return [];
    }
  }

  /// Admin: Tüm hızlı şablonları getir
  Future<List<AIQuickPrompt>> getAllQuickPrompts() async {
    try {
      final data = await _supabase
          .from('ai_quick_prompts')
          .select('*')
          .order('sort_order', ascending: true);
      return data.map((e) => AIQuickPrompt.fromMap(e)).toList();
    } catch (e) {
      AppLogger.error('Tüm hızlı şablonlar yüklenemedi: $e');
      return [];
    }
  }

  /// Admin: Hızlı şablon ekle
  Future<String?> addQuickPrompt({
    required String title,
    required String prompt,
    String icon = 'lightbulb_outline',
    String color = '#FFC107',
    int sortOrder = 0,
  }) async {
    try {
      final data = await _supabase.from('ai_quick_prompts').insert({
        'title': title,
        'prompt': prompt,
        'icon': icon,
        'color': color,
        'sort_order': sortOrder,
        'is_active': true,
      }).select('id').single();
      return data['id'] as String?;
    } catch (e) {
      AppLogger.error('Hızlı şablon eklenemedi: $e');
      return null;
    }
  }

  /// Admin: Hızlı şablon güncelle
  Future<bool> updateQuickPrompt(AIQuickPrompt quickPrompt) async {
    try {
      await _supabase.from('ai_quick_prompts').update({
        'title': quickPrompt.title,
        'prompt': quickPrompt.prompt,
        'icon': quickPrompt.icon,
        'color': quickPrompt.color,
        'sort_order': quickPrompt.sortOrder,
        'is_active': quickPrompt.isActive,
        'image_url': quickPrompt.imageUrl,
        'category': quickPrompt.category ?? 'general',
        'thumbnail_color': quickPrompt.thumbnailColor ?? '#7B2CBF',
      }).eq('id', quickPrompt.id);
      return true;
    } catch (e) {
      AppLogger.error('Hızlı şablon güncellenemedi: $e');
      return false;
    }
  }

  // =====================================================
  // AI PROMPT IMAGES (Görsel Kütüphanesi)
  // =====================================================

  /// Admin: Tüm görselleri getir
  Future<List<AIPromptImage>> getPromptImages({
    String? category,
    String? search,
  }) async {
    try {
      List<Map<String, dynamic>> data;
      if (category != null) {
        data = await _supabase
            .from('ai_prompt_images')
            .select('*')
            .eq('category', category)
            .order('created_at', ascending: false);
      } else {
        data = await _supabase
            .from('ai_prompt_images')
            .select('*')
            .order('created_at', ascending: false);
      }

      return data.map((e) => AIPromptImage.fromMap(e)).toList();
    } catch (e) {
      AppLogger.error('Görseller yüklenemedi: $e');
      return [];
    }
  }

  /// Admin: Görsel yükle
  Future<String?> uploadPromptImage(
    File file, {
    String? category,
    List<String>? tags,
  }) async {
    try {
      // Dosyayı oku
      final bytes = await file.readAsBytes();
      final fileName = '${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last}';
      
      // Supabase Storage'a yükle
      final path = 'ai_prompt_images/$fileName';
      await _supabase.storage.from('images').uploadBinary(
        path,
        bytes,
        fileOptions: FileOptions(
          contentType: 'image/*',
          upsert: true,
        ),
      );

      // Public URL al
      final url = _supabase.storage.from('images').getPublicUrl(path);

      // Veritabanına kaydet
      await _supabase.from('ai_prompt_images').insert({
        'image_url': url,
        'thumbnail_url': url,
        'category': category ?? 'general',
        'tags': tags ?? [],
        'file_size': bytes.length,
      });

      return url;
    } catch (e) {
      AppLogger.error('Görsel yüklenemedi: $e');
      return null;
    }
  }

  /// Admin: Görsel sil
  Future<bool> deletePromptImage(String id) async {
    try {
      // Önce görsel URL'sini al
      final image = await _supabase
          .from('ai_prompt_images')
          .select('image_url')
          .eq('id', id)
          .maybeSingle();

      if (image != null) {
        // Storage'dan sil
        final url = image['image_url'] as String?;
        if (url != null) {
          final path = url.split('/').last;
          try {
            await _supabase.storage.from('images').remove(['ai_prompt_images/$path']);
          } catch (e) {
            AppLogger.error('Storage görsel silinemedi (path: $path): $e');
          }
        }
      }

      // Veritabanından sil
      await _supabase.from('ai_prompt_images').delete().eq('id', id);
      return true;
    } catch (e) {
      AppLogger.error('Görsel silinemedi: $e');
      return false;
    }
  }

  /// Admin: Görsel kullanım sayısını güncelle
  Future<void> updatePromptImageUsage(String id) async {
    try {
      await _supabase.rpc('increment_image_usage', params: {'p_id': id});
    } catch (_) {
      // Yoksay - kritik değil
    }
  }

  /// Admin: Hızlı şablon sil
  Future<bool> deleteQuickPrompt(String id) async {
    try {
      await _supabase.from('ai_quick_prompts').delete().eq('id', id);
      return true;
    } catch (e) {
      AppLogger.error('Hızlı şablon silinemedi: $e');
      return false;
    }
  }

  /// Admin: Şablon sıralamasını güncelle
  Future<bool> reorderQuickPrompts(List<String> orderedIds) async {
    try {
      for (int i = 0; i < orderedIds.length; i++) {
        await _supabase
            .from('ai_quick_prompts')
            .update({'sort_order': i})
            .eq('id', orderedIds[i]);
      }
      return true;
    } catch (e) {
      AppLogger.error('Şablon sıralaması güncellenemedi: $e');
      return false;
    }
  }
}

/// Resim yükleme için yardımcı — platformdan bağımsız bayt okuma.
/// Web'de [xFile] / mobilde [file] ile çağrılabilir. Burada sadece sarmalayıcı.
Future<Uint8List> readImageBytes(dynamic source) async {
  if (source is Uint8List) return source;
  if (kIsWeb && source is http.MultipartFile) {
    // Web yolu için çağırıcı tarafından bayt verilmeli
    throw AIChatException('Web için bayt verilmeli', code: 'web_no_bytes');
  }
  if (source is File) {
    return await source.readAsBytes();
  }
  throw AIChatException('Desteklenmeyen kaynak', code: 'unsupported_source');
}