// Post Report Service - Apple Guideline 1.2 UGC Safety Compliance
// Gönderi şikayet etme özelliği

// ignore_for_file: unnecessary_import

import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class PostReportService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Şikayet nedenleri
  static const Map<String, String> reportReasons = {
    'inappropriate': 'Uygunsuz İçerik',
    'spam': 'Spam/Reklam',
    'harassment': 'Taciz/Hakaret',
    'misinformation': 'Yanlış Bilgi',
    'violence': 'Şiddet İçerikli',
    'copyright': 'Telif Hakkı İhlali',
    'other': 'Diğer',
  };

  // Şikayet durumları
  static const Map<String, String> reportStatuses = {
    'pending': 'Beklemede',
    'reviewing': 'İnceleniyor',
    'resolved': 'Çözüldü',
    'rejected': 'Reddedildi',
  };

  /// Gönderi şikayet et
  /// 
  /// [reportedPostId] - Şikayet edilen gönderinin ID'si
  /// [reason] - Şikayet nedeni (reportReasons'dan biri)
  /// [description] - Ek açıklama (opsiyonel)
  /// 
  /// Dönüş değerleri:
  /// - 'success': Şikayet başarıyla oluşturuldu
  /// - 'duplicate': Bu gönderiyi daha önce şikayet etmişsiniz
  /// - 'error': Genel hata
  /// - 'not_logged_in': Kullanıcı giriş yapmamış
  Future<String> reportPost({
    required String reportedPostId,
    required String reason,
    String? description,
    List<String>? images,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      return 'not_logged_in';
    }

    try {
      debugPrint('🔍 Gönderi şikayet kontrolü: reporter=$userId, post=$reportedPostId');

      // Zaten şikayet edilmiş mi kontrol et
      final existing = await _supabase
          .from('post_reports')
          .select('id, status')
          .eq('reporter_id', userId)
          .eq('reported_post_id', reportedPostId)
          .maybeSingle();

      if (existing != null) {
        debugPrint('⚠️ Bu gönderiyi daha önce şikayet etmişsiniz (ID: ${existing['id']}, Status: ${existing['status']})');
        return 'duplicate';
      }

      debugPrint('✅ Yeni gönderi şikayeti oluşturuluyor...');

      final Map<String, dynamic> reportData = {
        'reporter_id': userId,
        'reported_post_id': reportedPostId,
        'reason': reason,
        'description': description,
        'status': 'pending',
      };

      // Not: Görsel yükleme devre dışı (platform bağımlı)
      // Storage bucket varsa ve dosya okunabilirse aktif edilecek

      await _supabase.from('post_reports').insert(reportData);
      debugPrint('✅ Gönderi şikayeti başarıyla oluşturuldu: reporter_id=$userId, post_id=$reportedPostId');

      return 'success';
    } catch (e) {
      debugPrint('❌ Gönderi şikayeti oluşturulurken hata: $e');
      return 'error: $e'; // Hatayı döndür ki UI'da görelim
    }
  }

  /// Kullanıcının yaptığı gönderi şikayetlerini getir
  Future<List<Map<String, dynamic>>> getMyPostReports() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return [];

      // Join ile tüm verileri tek sorguda al
      final response = await _supabase
          .from('post_reports')
          .select('''
            id,
            reported_post_id,
            reason,
            description,
            status,
            admin_response,
            created_at,
            reported_post:posts!reported_post_id(id, content, user_id)
          ''')
          .eq('reporter_id', userId)
          .order('created_at', ascending: false);

      debugPrint('✅ Şikayetler getirildi: ${response.length} adet');
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Şikayetler getirilirken hata: $e');
      return [];
    }
  }

  /// Şikayet durumunu kontrol et (kullanıcı gönderiye şikayet etmiş mi?)
  Future<bool> hasUserReportedPost(String postId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return false;

      final existing = await _supabase
          .from('post_reports')
          .select('id')
          .eq('reporter_id', userId)
          .eq('reported_post_id', postId)
          .maybeSingle();

      return existing != null;
    } catch (e) {
      return false;
    }
  }

  /// Admin: Tüm gönderi şikayetlerini getir
  Future<List<Map<String, dynamic>>> getAllPostReports() async {
    try {
      final response = await _supabase
          .from('post_reports')
          .select('''
            *,
            reporter:profiles!post_reports_reporter_id_fkey(id, username, full_name, email, avatar_url),
            reported_post:posts!post_reports_reported_post_id_fkey(id, content, user_id)
          ''')
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Tüm şikayetler getirilirken hata: $e');
      return [];
    }
  }

  /// Admin: Gönderi şikayetini güncelle
  Future<bool> updateReportStatus(String reportId, String status, {String? adminResponse}) async {
    try {
      await _supabase
          .from('post_reports')
          .update({
            'status': status,
            'admin_response': adminResponse,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', reportId);

      return true;
    } catch (e) {
      debugPrint('❌ Şikayet güncellenirken hata: $e');
      return false;
    }
  }

  /// Admin: Gönderi şikayetini sil
  Future<bool> deleteReport(String reportId) async {
    try {
      await _supabase
          .from('post_reports')
          .delete()
          .eq('id', reportId);

      return true;
    } catch (e) {
      debugPrint('❌ Şikayet silinirken hata: $e');
      return false;
    }
  }

  /// Dosya byte'larını oku (görsel yükleme için)
  Future<Uint8List> _readFileBytes(String path) async {
    // Bu method platforma göre implement edilmeli
    // Şimdilik placeholder
    throw UnimplementedError('Dosya okuma implement edilmeli');
  }

  /// Şikayet nedeninin görünen adını al
  String getReasonDisplayName(String reason) {
    return reportReasons[reason] ?? reason;
  }

  /// Şikayet durumunun görünen adını al
  String getStatusDisplayName(String status) {
    return reportStatuses[status] ?? status;
  }
}
