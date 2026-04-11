import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// İade talebi durumları
enum ReturnRequestStatus {
  pending,    // Beklemede
  approved,   // Onaylandı
  rejected,   // Reddedildi
  completed;  // Tamamlandı

  String get label {
    switch (this) {
      case ReturnRequestStatus.pending:
        return 'Beklemede';
      case ReturnRequestStatus.approved:
        return 'Onaylandı';
      case ReturnRequestStatus.rejected:
        return 'Reddedildi';
      case ReturnRequestStatus.completed:
        return 'Tamamlandı';
    }
  }

  String get dbValue => name;

  static ReturnRequestStatus fromString(String value) {
    return ReturnRequestStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => ReturnRequestStatus.pending,
    );
  }
}

/// İade talebi modeli
class ReturnRequest {
  final String id;
  final String orderId;
  final String userId;
  final String shopId;
  final String reason;
  final ReturnRequestStatus status;
  final String? adminResponse;
  final DateTime createdAt;
  final DateTime? updatedAt;

  // İlişkili veriler
  final String? orderNumber;
  final String? shopName;
  final String? userName;
  final double? orderTotal;

  ReturnRequest({
    required this.id,
    required this.orderId,
    required this.userId,
    required this.shopId,
    required this.reason,
    required this.status,
    this.adminResponse,
    required this.createdAt,
    this.updatedAt,
    this.orderNumber,
    this.shopName,
    this.userName,
    this.orderTotal,
  });

  factory ReturnRequest.fromJson(Map<String, dynamic> json) {
    // İlişkili veriler
    final order = json['orders'] as Map<String, dynamic>?;
    final shop = json['shops'] as Map<String, dynamic>?;
    final user = json['profiles'] as Map<String, dynamic>?;

    return ReturnRequest(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      userId: json['user_id'] as String,
      shopId: json['shop_id'] as String,
      reason: json['reason'] as String? ?? '',
      status: ReturnRequestStatus.fromString(json['status'] as String? ?? 'pending'),
      adminResponse: json['admin_response'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      orderNumber: order?['order_number']?.toString(),
      shopName: shop?['name'] as String?,
      userName: user?['name'] as String?,
      orderTotal: order?['total'] != null
          ? (order!['total'] as num).toDouble()
          : null,
    );
  }
}

/// İade talebi servisi
class ReturnRequestService {
  final SupabaseClient _supabase = Supabase.instance.client;

  /// Yeni iade talebi oluştur
  Future<ReturnRequest> createReturnRequest({
    required String orderId,
    required String userId,
    required String shopId,
    required String reason,
  }) async {
    try {
      debugPrint('📦 RETURN: İade talebi oluşturuluyor...');
      debugPrint('  └─ orderId: $orderId');
      debugPrint('  └─ userId: $userId');
      debugPrint('  └─ shopId: $shopId');
      debugPrint('  └─ reason: $reason');

      final response = await _supabase
          .from('return_requests')
          .insert({
            'order_id': orderId,
            'user_id': userId,
            'shop_id': shopId,
            'reason': reason,
            'status': 'pending',
            'created_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      debugPrint('✅ RETURN: İade talebi oluşturuldu - ID: ${response['id']}');
      return ReturnRequest.fromJson(response);
    } catch (e) {
      debugPrint('❌ RETURN: İade talebi oluşturulurken hata: $e');
      throw Exception('İade talebi oluşturulurken hata: $e');
    }
  }

  /// Kullanıcının iade taleplerini getir
  Future<List<ReturnRequest>> getUserReturnRequests(String userId) async {
    try {
      final response = await _supabase
          .from('return_requests')
          .select('''
            *,
            orders(order_number, total),
            shops(name)
          ''')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => ReturnRequest.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('❌ RETURN: Kullanıcı iade talepleri alınırken hata: $e');
      throw Exception('İade talepleri alınırken hata: $e');
    }
  }

  /// Dükkanın iade taleplerini getir
  Future<List<ReturnRequest>> getShopReturnRequests(String shopId) async {
    try {
      final response = await _supabase
          .from('return_requests')
          .select('''
            *,
            orders(order_number, total),
            profiles(name)
          ''')
          .eq('shop_id', shopId)
          .order('created_at', ascending: false);

      return (response as List)
          .map((json) => ReturnRequest.fromJson(json))
          .toList();
    } catch (e) {
      debugPrint('❌ RETURN: Dükkan iade talepleri alınırken hata: $e');
      throw Exception('İade talepleri alınırken hata: $e');
    }
  }

  /// İade talebini güncelle (satıcı/admin)
  Future<void> updateReturnRequest({
    required String requestId,
    required ReturnRequestStatus status,
    String? adminResponse,
  }) async {
    try {
      debugPrint('📦 RETURN: İade talebi güncelleniyor - ID: $requestId');
      
      final updateData = {
        'status': status.dbValue,
        'updated_at': DateTime.now().toIso8601String(),
      };
      
      if (adminResponse != null) {
        updateData['admin_response'] = adminResponse;
      }

      await _supabase
          .from('return_requests')
          .update(updateData)
          .eq('id', requestId);

      debugPrint('✅ RETURN: İade talebi güncellendi - Durum: ${status.label}');
    } catch (e) {
      debugPrint('❌ RETURN: İade talebi güncellenirken hata: $e');
      throw Exception('İade talebi güncellenirken hata: $e');
    }
  }

  /// Sipariş için iade talebi var mı kontrol et
  Future<ReturnRequest?> getReturnRequestByOrderId(String orderId) async {
    try {
      final response = await _supabase
          .from('return_requests')
          .select()
          .eq('order_id', orderId)
          .maybeSingle();

      if (response != null) {
        return ReturnRequest.fromJson(response);
      }
      return null;
    } catch (e) {
      debugPrint('❌ RETURN: İade talebi kontrol edilirken hata: $e');
      return null;
    }
  }

  /// Bekleyen iade taleplerinin sayısını getir (dükkan için)
  Future<int> getPendingReturnRequestsCount(String shopId) async {
    try {
      final response = await _supabase
          .from('return_requests')
          .select('id')
          .eq('shop_id', shopId)
          .eq('status', 'pending');

      return (response as List).length;
    } catch (e) {
      return 0;
    }
  }
}
