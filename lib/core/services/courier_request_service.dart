import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/courier_request_model.dart';
import '../services/notification_service.dart';

/// Kurye Talep Servisi
/// Satıcıların kurye taleplerini yönetir
class CourierRequestService {
  final SupabaseClient _supabase = Supabase.instance.client;
  final NotificationService _notificationService = NotificationService();

  /// Kurye talebi oluştur (Satıcı)
  Future<CourierRequest?> createCourierRequest({
    required String shopId,
    String? message,
  }) async {
    try {
      debugPrint('📨 COURIER REQUEST: Talep oluşturuluyor...');
      debugPrint('  └─ shopId: $shopId');
      
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Kullanıcı oturumu bulunamadı');
      }

      // Mevcut bekleyen talep var mı kontrol et
      final existing = await _supabase
          .from('courier_requests')
          .select()
          .eq('shop_id', shopId)
          .eq('status', 'pending')
          .maybeSingle();

      if (existing != null) {
        debugPrint('⚠️ COURIER REQUEST: Zaten bekleyen talep var');
        throw Exception('Zaten bekleyen bir kurye talebiniz var');
      }

      // Yeni talep oluştur
      final response = await _supabase.from('courier_requests').insert({
        'shop_id': shopId,
        'seller_id': userId,
        'status': 'pending',
        'message': message,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      }).select('''
        *,
        shops(name),
        profiles:seller_id(full_name, username, email)
      ''').single();

      debugPrint('✅ COURIER REQUEST: Talep oluşturuldu');

      // Admin'lere bildirim gönder
      await _notifyAdmins(
        shopId: shopId,
        shopName: response['shops']?['name'] as String? ?? 'Dükkan',
      );

      return CourierRequest.fromJson(response);
    } catch (e) {
      debugPrint('❌ COURIER REQUEST: Talep oluşturulurken hata: $e');
      rethrow;
    }
  }

  /// Kurye talebini onayla (Admin)
  Future<void> approveCourierRequest(String requestId) async {
    try {
      debugPrint('✅ COURIER REQUEST: Talep onaylanıyor...');
      debugPrint('  └─ requestId: $requestId');

      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Kullanıcı oturumu bulunamadı');
      }

      // Talebi getir
      final request = await _supabase
          .from('courier_requests')
          .select('*, profiles:seller_id(id)')
          .eq('id', requestId)
          .single();

      // Talebi onayla
      await _supabase.from('courier_requests').update({
        'status': 'approved',
        'reviewed_at': DateTime.now().toIso8601String(),
        'reviewed_by': userId,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', requestId);

      // Shop'u güncelle - has_own_courier = true
      await _supabase.from('shops').update({
        'has_own_courier': true,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', request['shop_id']);

      debugPrint('✅ COURIER REQUEST: Talep onaylandı ve dükkan güncellendi');

      // Satıcıya bildirim gönder
      final sellerId = request['profiles']?['id'] as String?;
      if (sellerId != null) {
        await _notificationService.createNotification(
          userId: sellerId,
          type: 'courier_request_approved',
          title: 'Kurye Talebiniz Onaylandı',
          content: 'Artık kendi teslimat ücretinizi belirleyebilirsiniz',
          entityId: requestId,
        );
      }
    } catch (e) {
      debugPrint('❌ COURIER REQUEST: Onaylama hatası: $e');
      rethrow;
    }
  }

  /// Kurye talebini reddet (Admin)
  Future<void> rejectCourierRequest(String requestId, {String? adminNotes}) async {
    try {
      debugPrint('❌ COURIER REQUEST: Talep reddediliyor...');
      debugPrint('  └─ requestId: $requestId');

      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Kullanıcı oturumu bulunamadı');
      }

      // Talebi getir
      final request = await _supabase
          .from('courier_requests')
          .select('*, profiles:seller_id(id)')
          .eq('id', requestId)
          .single();

      // Talebi reddet
      await _supabase.from('courier_requests').update({
        'status': 'rejected',
        'admin_notes': adminNotes,
        'reviewed_at': DateTime.now().toIso8601String(),
        'reviewed_by': userId,
        'updated_at': DateTime.now().toIso8601String(),
      }).eq('id', requestId);

      debugPrint('✅ COURIER REQUEST: Talep reddedildi');

      // Satıcıya bildirim gönder
      final sellerId = request['profiles']?['id'] as String?;
      if (sellerId != null) {
        await _notificationService.createNotification(
          userId: sellerId,
          type: 'courier_request_rejected',
          title: 'Kurye Talebiniz Reddedildi',
          content: adminNotes ?? 'Kurye talebiniz admin tarafından reddedildi',
          entityId: requestId,
        );
      }
    } catch (e) {
      debugPrint('❌ COURIER REQUEST: Red etme hatası: $e');
      rethrow;
    }
  }

  /// Satıcının kendi taleplerini getir
  Future<List<CourierRequest>> getSellerRequests(String sellerId) async {
    try {
      debugPrint('📋 COURIER REQUEST: Satıcı talepleri getiriliyor...');
      
      final response = await _supabase
          .from('courier_requests')
          .select('''
            *,
            shops(name),
            profiles:seller_id(full_name, username, email)
          ''')
          .eq('seller_id', sellerId)
          .order('created_at', ascending: false);

      final requests = (response as List)
          .map((json) => CourierRequest.fromJson(json as Map<String, dynamic>))
          .toList();

      debugPrint('✅ COURIER REQUEST: ${requests.length} talep bulundu');
      return requests;
    } catch (e) {
      debugPrint('❌ COURIER REQUEST: Talepler getirilemedi: $e');
      rethrow;
    }
  }

  /// Dükkanın son talebini getir
  Future<CourierRequest?> getShopLatestRequest(String shopId) async {
    try {
      final response = await _supabase
          .from('courier_requests')
          .select('''
            *,
            shops(name),
            profiles:seller_id(full_name, username, email)
          ''')
          .eq('shop_id', shopId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;
      return CourierRequest.fromJson(response);
    } catch (e) {
      debugPrint('❌ COURIER REQUEST: Son talep getirilemedi: $e');
      return null;
    }
  }

  /// Tüm talepleri getir (Admin)
  Future<List<CourierRequest>> getAllRequests({CourierRequestStatus? status}) async {
    try {
      debugPrint('📋 COURIER REQUEST: Tüm talepler getiriliyor...');
      
      var query = _supabase
          .from('courier_requests')
          .select('''
            *,
            shops(name),
            profiles:seller_id(full_name, username, email)
          ''');

      if (status != null) {
        query = query.eq('status', status.dbValue);
      }

      final response = await query.order('created_at', ascending: false);

      final requests = (response as List)
          .map((json) => CourierRequest.fromJson(json as Map<String, dynamic>))
          .toList();

      debugPrint('✅ COURIER REQUEST: ${requests.length} talep bulundu');
      return requests;
    } catch (e) {
      debugPrint('❌ COURIER REQUEST: Talepler getirilemedi: $e');
      rethrow;
    }
  }

  /// Bekleyen talep sayısını getir (Admin)
  Future<int> getPendingRequestsCount() async {
    try {
      final response = await _supabase
          .from('courier_requests')
          .select('id')
          .eq('status', 'pending');

      return (response as List).length;
    } catch (e) {
      debugPrint('❌ COURIER REQUEST: Sayı getirilemedi: $e');
      return 0;
    }
  }

  /// Admin'lere bildirim gönder
  Future<void> _notifyAdmins({
    required String shopId,
    required String shopName,
  }) async {
    try {
      // Admin kullanıcıları getir
      final admins = await _supabase
          .from('profiles')
          .select('id')
          .eq('role', 'admin');

      // Her admin'e bildirim gönder
      for (final admin in admins) {
        await _notificationService.createNotification(
          userId: admin['id'] as String,
          type: 'courier_request',
          title: 'Yeni Kurye Talebi',
          content: '$shopName kurye talebinde bulundu',
          entityId: shopId,
        );
      }

      debugPrint('✅ COURIER REQUEST: ${admins.length} admin\'e bildirim gönderildi');
    } catch (e) {
      debugPrint('⚠️ COURIER REQUEST: Admin bildirimi gönderilemedi: $e');
      // Bildirim hatası talep oluşturmayı engellemez
    }
  }
}
