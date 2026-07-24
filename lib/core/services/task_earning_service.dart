// ignore_for_file: unnecessary_import

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/task_earning_model.dart';
import '../utils/app_error_handler.dart';

/// Görev Yaparak Kazan Servisi
///
/// Akış:
/// - Kullanıcı: getActiveTasks → claimTask (katıl) → uploadScreenshot → submitTaskWithProof
/// - Admin: getAllTasks → createTask/updateTask/deleteTask → adminGetSubmissions → approve/reject
///
/// Tüm mutasyonlar SECURITY DEFINER RPC üzerinden yapılır:
/// - claim_task: FOR UPDATE lock ile race condition koruması
/// - submit_task_with_proof: yalnızca kendi pending başvurusunu günceller
/// - approve_task_submission: idempotent (status='approved' ise no-op), atomik bakiye
/// - reject_task_submission: bakiye iade yok, katılımcı limiti geri açılır
class TaskEarningService {
  TaskEarningService._();
  static final TaskEarningService instance = TaskEarningService._();

  SupabaseClient get _supabase => Supabase.instance.client;

  // ===========================================================================
  // KATEGORİLER
  // ===========================================================================

  /// Tüm kategorileri getir
  Future<List<TaskCategory>> getCategories() async {
    try {
      final response = await _supabase
          .from('task_categories')
          .select('*')
          .eq('is_active', true)
          .order('sort_order', ascending: true);
      return (response as List)
          .map((e) => TaskCategory.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('❌ TaskEarningService.getCategories hatası: $e');
      return [];
    }
  }

  // ===========================================================================
  // KULLANICI: AKTİF GÖREVLER
  // ===========================================================================

  /// Aktif görevleri listele (kullanıcı için)
  Future<List<Task>> getActiveTasks({String? categoryId, int limit = 50}) async {
    try {
      final response = await _supabase.rpc(
        'get_active_tasks',
        params: {
          'p_category_id': categoryId,
          'p_limit': limit,
          'p_offset': 0,
        },
      );
      return (response as List)
          .map((e) => Task.fromJson(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      debugPrint('❌ get_active_tasks RPC hatası: ${e.code} ${e.message}');
      throw Exception(_friendlyError(e));
    }
  }

  /// Göreve katıl (katılımcı limiti atomik artırılır)
  /// Returns: submission_id (ekran görüntüsü yüklemek için)
  Future<String> claimTask(String taskId) async {
    try {
      final response = await _supabase.rpc(
        'claim_task',
        params: {'p_task_id': taskId},
      );
      return response as String;
    } on PostgrestException catch (e) {
      debugPrint('❌ claim_task RPC hatası: ${e.code} ${e.message}');
      throw Exception(_friendlyError(e));
    }
  }

  /// Ekran görüntüsünü Supabase Storage'a yükle
  /// Returns: Public URL
  Future<String> uploadTaskScreenshot({
    required String submissionId,
    required XFile file,
  }) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Oturum açmanız gerekli');
      }

      // Cache-bust için timestamp (PROJE_HAVIZA: 2026-07-04 grup foto cache fix)
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ext = p.extension(file.path).isNotEmpty ? p.extension(file.path) : '.jpg';
      final fileName = '${submissionId}_$timestamp$ext';
      final filePath = '$userId/$fileName';

      Uint8List bytes;
      if (kIsWeb) {
        bytes = await file.readAsBytes();
      } else {
        bytes = await File(file.path).readAsBytes();
      }

      await _supabase.storage.from('task_screenshots').uploadBinary(
            filePath,
            bytes,
            fileOptions: FileOptions(
              contentType: _guessContentType(file.path),
              upsert: false,
            ),
          );

      final publicUrl = _supabase.storage
          .from('task_screenshots')
          .getPublicUrl(filePath);

      return publicUrl;
    } catch (e) {
      // StorageException veya genel hata olabilir
      debugPrint('❌ uploadTaskScreenshot hatası: $e');
      throw Exception('Ekran görüntüsü yüklenemedi: ${e.toString()}');
    }
  }

  /// Yüklenen ekran görüntüsünü submission'a bağla
  Future<void> submitTaskWithProof({
    required String submissionId,
    required String screenshotUrl,
    String? userNote,
  }) async {
    try {
      await _supabase.rpc(
        'submit_task_with_proof',
        params: {
          'p_submission_id': submissionId,
          'p_screenshot_url': screenshotUrl,
          'p_user_note': userNote,
        },
      );
    } on PostgrestException catch (e) {
      debugPrint('❌ submit_task_with_proof RPC hatası: ${e.code} ${e.message}');
      throw Exception(_friendlyError(e));
    }
  }

  /// Kullanıcının görev geçmişini getir
  Future<List<TaskSubmission>> getUserTaskHistory({
    TaskSubmissionStatus? status,
    int limit = 50,
  }) async {
    try {
      final response = await _supabase.rpc(
        'get_user_task_history',
        params: {
          'p_status': status?.name,
          'p_limit': limit,
          'p_offset': 0,
        },
      );
      return (response as List)
          .map((e) => TaskSubmission.fromJson(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      debugPrint('❌ get_user_task_history RPC hatası: ${e.code} ${e.message}');
      throw Exception(_friendlyError(e));
    }
  }

  /// Kullanıcının görevlerden kazandığı toplam bakiye
  Future<double> getUserTotalEarned() async {
    try {
      final result = await _supabase.rpc(
        'get_user_task_history',
        params: {
          'p_status': 'approved',
          'p_limit': 1000,
          'p_offset': 0,
        },
      );
      double total = 0;
      for (final row in (result as List)) {
        final earned = (row as Map<String, dynamic>)['total_earned'] as num?;
        if (earned != null) total += earned.toDouble();
      }
      return total;
    } catch (e) {
      debugPrint('❌ getUserTotalEarned hatası: $e');
      return 0;
    }
  }

  /// Kullanıcının bekleyen (onaylanmamış) başvurusu var mı?
  Future<int> getUserPendingCount() async {
    try {
      final result = await _supabase.rpc(
        'get_user_task_history',
        params: {
          'p_status': 'pending',
          'p_limit': 1000,
          'p_offset': 0,
        },
      );
      return (result as List).length;
    } catch (e) {
      debugPrint('❌ getUserPendingCount hatası: $e');
      return 0;
    }
  }

  // ===========================================================================
  // ADMIN: GÖREV YÖNETİMİ
  // ===========================================================================

  /// Tüm görevleri getir (admin — durum filtresi ile)
  Future<List<Task>> getAllTasks({TaskStatus? statusFilter, int limit = 200}) async {
    try {
      // Önce tüm görevleri çek, sonra Dart tarafında filtrele
      // (PostgrestTransformBuilder'da chain sorunu yaşamamak için)
      final response = await _supabase
          .from('tasks')
          .select('*, task_categories(name, icon)')
          .order('created_at', ascending: false)
          .limit(limit);

      var list = (response as List).cast<Map<String, dynamic>>();

      if (statusFilter != null) {
        list = list.where((row) => row['status'] == statusFilter.name).toList();
      }

      return list.map(_parseAdminTask).toList();
    } catch (e) {
      debugPrint('❌ TaskEarningService.getAllTasks hatası: $e');
      throw FriendlyException.from(e);
    }
  }

  Task _parseAdminTask(Map<String, dynamic> json) {
    final cat = json['task_categories'] as Map<String, dynamic>?;
    return Task(
      id: json['id'] as String? ?? '',
      categoryId: json['category_id'] as String?,
      categoryName: cat?['name'] as String?,
      categoryIcon: cat?['icon'] as String?,
      title: json['title'] as String? ?? '',
      description: json['description'] as String? ?? '',
      warningText: json['warning_text'] as String?,
      taskLink: json['task_link'] as String?,
      imageUrl: json['image_url'] as String?,
      imageUrls: (json['image_urls'] as List?)?.cast<String>() ?? const [],
      rewardAmount: (json['reward_amount'] as num?)?.toDouble() ?? 0,
      maxParticipants: json['max_participants'] as int? ?? 0,
      currentParticipants: json['current_participants'] as int? ?? 0,
      remainingSlots:
          (json['max_participants'] as int? ?? 0) - (json['current_participants'] as int? ?? 0),
      startsAt: json['starts_at'] != null
          ? DateTime.parse(json['starts_at'] as String)
          : DateTime.now(),
      expiresAt: json['expires_at'] != null
          ? DateTime.parse(json['expires_at'] as String)
          : null,
      status: TaskStatus.fromString(json['status'] as String? ?? 'draft'),
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(),
    );
  }

  /// Yeni görev oluştur (admin)
  Future<String> createTask({
    String? categoryId,
    required String title,
    required String description,
    String? warningText,
    String? taskLink,
    String? imageUrl,
    List<String> imageUrls = const [],
    required double rewardAmount,
    required int maxParticipants,
    DateTime? startsAt,
    DateTime? expiresAt,
    TaskStatus status = TaskStatus.active,
  }) async {
    try {
      final adminId = _supabase.auth.currentUser?.id;
      if (adminId == null) throw Exception('Oturum açmanız gerekli');

      final response = await _supabase
          .from('tasks')
          .insert({
            'category_id': categoryId,
            'title': title,
            'description': description,
            'warning_text': warningText,
            'task_link': taskLink,
            'image_url': imageUrl,
            'image_urls': imageUrls,
            'reward_amount': rewardAmount,
            'max_participants': maxParticipants,
            'starts_at': (startsAt ?? DateTime.now()).toUtc().toIso8601String(),
            'expires_at': expiresAt?.toUtc().toIso8601String(),
            'status': status.name,
            'created_by': adminId,
          })
          .select('id')
          .single();

      return response['id'] as String;
    } on PostgrestException catch (e) {
      debugPrint('❌ createTask hatası: ${e.code} ${e.message}');
      throw Exception(_friendlyError(e));
    }
  }

  /// Görevi güncelle (admin)
  Future<void> updateTask({
    required String taskId,
    String? categoryId,
    String? title,
    String? description,
    String? warningText,
    String? taskLink,
    String? imageUrl,
    bool clearImageUrl = false,
    List<String>? imageUrls,
    double? rewardAmount,
    int? maxParticipants,
    DateTime? startsAt,
    DateTime? expiresAt,
    bool clearExpiresAt = false,
    TaskStatus? status,
  }) async {
    try {
      final update = <String, dynamic>{};
      if (categoryId != null) update['category_id'] = categoryId;
      if (title != null) update['title'] = title;
      if (description != null) update['description'] = description;
      if (warningText != null) update['warning_text'] = warningText;
      if (taskLink != null) update['task_link'] = taskLink;
      if (imageUrl != null) update['image_url'] = imageUrl;
      if (clearImageUrl) update['image_url'] = null;
      if (imageUrls != null) update['image_urls'] = imageUrls;
      if (rewardAmount != null) update['reward_amount'] = rewardAmount;
      if (maxParticipants != null) update['max_participants'] = maxParticipants;
      if (startsAt != null) update['starts_at'] = startsAt.toUtc().toIso8601String();
      if (expiresAt != null) update['expires_at'] = expiresAt.toUtc().toIso8601String();
      if (clearExpiresAt) update['expires_at'] = null;
      if (status != null) update['status'] = status.name;

      if (update.isEmpty) return;

      await _supabase.from('tasks').update(update).eq('id', taskId);
    } on PostgrestException catch (e) {
      debugPrint('❌ updateTask hatası: ${e.code} ${e.message}');
      throw Exception(_friendlyError(e));
    }
  }

  /// Admin görev görselini task_images bucket'ına yükle
  /// Returns: public URL
  Future<String> uploadTaskImage({
    required XFile file,
    String? existingPath, // upsert için
  }) async {
    try {
      final adminId = _supabase.auth.currentUser?.id;
      if (adminId == null) throw Exception('Oturum açmanız gerekli');

      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ext = p.extension(file.path).isNotEmpty ? p.extension(file.path) : '.jpg';
      final fileName = 'task_$timestamp$ext';
      final filePath = '$adminId/$fileName';

      Uint8List bytes;
      if (kIsWeb) {
        bytes = await file.readAsBytes();
      } else {
        bytes = await File(file.path).readAsBytes();
      }

      await _supabase.storage.from('task_images').uploadBinary(
            filePath,
            bytes,
            fileOptions: FileOptions(
              contentType: _guessContentType(file.path),
              upsert: false,
            ),
          );

      return _supabase.storage.from('task_images').getPublicUrl(filePath);
    } catch (e) {
      debugPrint('❌ uploadTaskImage hatası: $e');
      throw Exception('Görev görseli yüklenemedi: ${e.toString()}');
    }
  }

  /// Görev durumunu değiştir (admin)
  Future<void> updateTaskStatus(String taskId, TaskStatus newStatus) async {
    try {
      await _supabase
          .from('tasks')
          .update({'status': newStatus.name})
          .eq('id', taskId);
    } catch (e) {
      debugPrint('❌ updateTaskStatus hatası: $e');
      throw FriendlyException.from(e);
    }
  }

  /// Görevi sil (admin)
  Future<void> deleteTask(String taskId) async {
    try {
      await _supabase.from('tasks').delete().eq('id', taskId);
    } on PostgrestException catch (e) {
      debugPrint('❌ deleteTask hatası: ${e.code} ${e.message}');
      throw Exception(_friendlyError(e));
    }
  }

  // ===========================================================================
  // ADMIN: BAŞVURU YÖNETİMİ
  // ===========================================================================

  /// Tüm başvuruları listele (admin — status/task filtresi)
  Future<List<TaskSubmission>> adminGetSubmissions({
    TaskSubmissionStatus? status,
    String? taskId,
    int limit = 100,
  }) async {
    try {
      final response = await _supabase.rpc(
        'admin_get_task_submissions',
        params: {
          'p_status': status?.name,
          'p_task_id': taskId,
          'p_limit': limit,
          'p_offset': 0,
        },
      );
      return (response as List)
          .map((e) => TaskSubmission.fromJson(e as Map<String, dynamic>))
          .toList();
    } on PostgrestException catch (e) {
      debugPrint('❌ admin_get_task_submissions RPC hatası: ${e.code} ${e.message}');
      throw Exception(_friendlyError(e));
    }
  }

  /// Başvuruyu onayla (admin) — atomik bakiye ekleme
  /// Returns: { reward_amount, new_balance, transaction_id }
  Future<Map<String, dynamic>> approveSubmission({
    required String submissionId,
    String? adminNote,
  }) async {
    try {
      final response = await _supabase.rpc(
        'approve_task_submission',
        params: {
          'p_submission_id': submissionId,
          'p_admin_note': adminNote,
        },
      );
      return Map<String, dynamic>.from(response as Map);
    } on PostgrestException catch (e) {
      debugPrint('❌ approve_task_submission RPC hatası: ${e.code} ${e.message}');
      throw Exception(_friendlyError(e));
    }
  }

  /// Başvuruyu reddet (admin)
  Future<void> rejectSubmission({
    required String submissionId,
    required String rejectionReason,
  }) async {
    try {
      await _supabase.rpc(
        'reject_task_submission',
        params: {
          'p_submission_id': submissionId,
          'p_rejection_reason': rejectionReason,
        },
      );
    } on PostgrestException catch (e) {
      debugPrint('❌ reject_task_submission RPC hatası: ${e.code} ${e.message}');
      throw Exception(_friendlyError(e));
    }
  }

  /// Admin: görev istatistikleri
  Future<TaskStats> getTaskStats() async {
    try {
      final response = await _supabase.rpc('get_task_stats');
      return TaskStats.fromJson(Map<String, dynamic>.from(response as Map));
    } on PostgrestException catch (e) {
      debugPrint('❌ get_task_stats RPC hatası: ${e.code} ${e.message}');
      throw Exception(_friendlyError(e));
    }
  }

  // ===========================================================================
  // REALTIME SUBSCRIPTIONS
  // ===========================================================================

  /// Kullanıcının kendi başvurularında değişiklik dinle (badge güncellemesi)
  RealtimeChannel subscribeUserSubmissions({
    required String userId,
    required void Function(TaskSubmissionStatus newStatus) onChange,
  }) {
    final channel = _supabase
        .channel('user_task_submissions_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'task_submissions',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (payload) {
            final newStatus = payload.newRecord['status'] as String?;
            if (newStatus != null) {
              onChange(TaskSubmissionStatus.fromString(newStatus));
            }
          },
        )
        .subscribe();
    return channel;
  }

  /// Admin: tüm başvurularda değişiklik dinle (insert + update + delete)
  RealtimeChannel subscribeAllSubmissions({
    required void Function() onChange,
  }) {
    final channel = _supabase
        .channel('admin_task_submissions_all')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'task_submissions',
          callback: (payload) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.update,
          schema: 'public',
          table: 'task_submissions',
          callback: (payload) => onChange(),
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.delete,
          schema: 'public',
          table: 'task_submissions',
          callback: (payload) => onChange(),
        )
        .subscribe();
    return channel;
  }

  /// Admin: görev değişikliklerini dinle
  RealtimeChannel subscribeAllTasks({
    required void Function() onChange,
  }) {
    final channel = _supabase
        .channel('admin_all_tasks')
        .onPostgresChanges(
          event: PostgresChangeEvent.all, // supabase v2'de PostgresChangeEvent.all mevcut
          schema: 'public',
          table: 'tasks',
          callback: (payload) => onChange(),
        )
        .subscribe();
    return channel;
  }

  // ===========================================================================
  // YARDIMCI
  // ===========================================================================

  String _guessContentType(String filePath) {
    final ext = p.extension(filePath).toLowerCase();
    switch (ext) {
      case '.png':
        return 'image/png';
      case '.webp':
        return 'image/webp';
      case '.jpg':
      case '.jpeg':
      default:
        return 'image/jpeg';
    }
  }

  String _friendlyError(PostgrestException e) {
    final msg = e.message;
    if (e.code == '42501') return 'Bu işlem için yetkiniz yok';
    if (msg.contains('admin yetkisi')) return 'Bu işlem için admin yetkisi gerekli';
    if (msg.contains('zaten katıldınız')) return msg;
    if (msg.contains('limit')) return msg;
    if (msg.contains('süresi dolmuş')) return msg;
    if (msg.contains('henüz başlamadı')) return msg;
    if (msg.contains('bulunamadı')) return 'Görev/başvuru bulunamadı';
    if (msg.contains('Oturum')) return msg;
    return msg.isEmpty ? 'İşlem başarısız' : msg;
  }
}