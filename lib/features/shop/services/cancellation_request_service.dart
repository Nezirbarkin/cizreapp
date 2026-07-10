import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// İptal talebi durumları
///
/// [pending]   -> Müşteri açtı, admin bekliyor
/// [approved]  -> Admin onayladı; sipariş cancelled + (iade varsa) bakiyeye eklendi
/// [rejected]  -> Admin reddetti; sipariş olduğu gibi kalır
/// [cancelled] -> Müşteri geri çekti (opsiyonel; şu an UI'da yok)
enum CancellationRequestStatus {
  pending,
  approved,
  rejected,
  cancelled;

  String get label {
    switch (this) {
      case CancellationRequestStatus.pending:
        return 'Beklemede';
      case CancellationRequestStatus.approved:
        return 'Onaylandı';
      case CancellationRequestStatus.rejected:
        return 'Reddedildi';
      case CancellationRequestStatus.cancelled:
        return 'İptal';
    }
  }

  String get dbValue => name;

  static CancellationRequestStatus fromString(String? value) {
    if (value == null) return CancellationRequestStatus.pending;
    return CancellationRequestStatus.values.firstWhere(
      (s) => s.name == value,
      orElse: () => CancellationRequestStatus.pending,
    );
  }
}

/// İade yöntemi snapshot'ı (DB'de `refund_method` enum)
/// - [balance]: CizreApp bakiyesine iade (admin onayı sonrası add_to_balance ile)
/// - [none]   : cash/card_on_delivery (iade yok, sadece iptal)
enum CancellationRefundMethod {
  balance,
  none;

  String get label {
    switch (this) {
      case CancellationRefundMethod.balance:
        return 'Bakiyeye İade';
      case CancellationRefundMethod.none:
        return 'İade Yok';
    }
  }

  String get dbValue => name;

  static CancellationRefundMethod fromString(String? value) {
    if (value == null) return CancellationRefundMethod.none;
    return CancellationRefundMethod.values.firstWhere(
      (m) => m.name == value,
      orElse: () => CancellationRefundMethod.none,
    );
  }
}

/// İptal talebi modeli
class CancellationRequest {
  final String id;
  final String orderId;
  final String userId;
  final String? shopId;
  final String reason;
  final CancellationRequestStatus status;

  // Snapshot alanları (talep anında kilitlenir)
  final double orderTotal;
  final String paymentMethod;
  final CancellationRefundMethod refundMethod;
  final double refundAmount;

  // İnceleme
  final String? reviewedBy;
  final DateTime? reviewedAt;
  final String? adminResponse;
  final String? balanceTransactionId;

  final DateTime createdAt;
  final DateTime? updatedAt;

  // İlişkili veriler (join'lendiğinde)
  final String? orderNumber;
  final String? shopName;
  final String? customerName;

  CancellationRequest({
    required this.id,
    required this.orderId,
    required this.userId,
    this.shopId,
    required this.reason,
    required this.status,
    required this.orderTotal,
    required this.paymentMethod,
    required this.refundMethod,
    required this.refundAmount,
    this.reviewedBy,
    this.reviewedAt,
    this.adminResponse,
    this.balanceTransactionId,
    required this.createdAt,
    this.updatedAt,
    this.orderNumber,
    this.shopName,
    this.customerName,
  });

  bool get isPending => status == CancellationRequestStatus.pending;
  bool get isApproved => status == CancellationRequestStatus.approved;
  bool get hasRefund => refundMethod == CancellationRefundMethod.balance && refundAmount > 0;

  factory CancellationRequest.fromJson(Map<String, dynamic> json) {
    final order = json['orders'] as Map<String, dynamic>?;
    final shop = json['shops'] as Map<String, dynamic>?;
    final user = json['profiles'] as Map<String, dynamic>?;

    return CancellationRequest(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      userId: json['user_id'] as String,
      shopId: json['shop_id'] as String?,
      reason: json['reason'] as String? ?? '',
      status: CancellationRequestStatus.fromString(json['status'] as String?),
      orderTotal: (json['order_total'] as num?)?.toDouble() ?? 0,
      paymentMethod: json['payment_method'] as String? ?? 'cash',
      refundMethod: CancellationRefundMethod.fromString(json['refund_method'] as String?),
      refundAmount: (json['refund_amount'] as num?)?.toDouble() ?? 0,
      reviewedBy: json['reviewed_by'] as String?,
      reviewedAt: json['reviewed_at'] != null
          ? DateTime.parse(json['reviewed_at'] as String)
          : null,
      adminResponse: json['admin_response'] as String?,
      balanceTransactionId: json['balance_transaction_id'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      orderNumber: order?['order_number']?.toString(),
      shopName: shop?['name'] as String?,
      customerName: user?['full_name'] as String? ?? user?['username'] as String?,
    );
  }
}

/// İptal talebi servisi
///
/// Üç RPC'yi sarmalayan Dart servisi:
/// - create_cancellation_request (müşteri)
/// - approve_cancellation_request (admin)
/// - reject_cancellation_request (admin)
///
/// Veritabanı tarafında atomic:
/// approve -> orders cancelled + (iade varsa) add_to_balance + notification.
class CancellationRequestService {
  /// Supabase client'ı güvenli şekilde al (lazy)
  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      rethrow;
    }
  }

  // ---------------------------------------------------------------------
  // MÜŞTERİ
  // ---------------------------------------------------------------------

  /// Müşteri iptal talebi açar
  Future<CancellationRequest> createRequest({
    required String orderId,
    required String reason,
  }) async {
    try {
      debugPrint('📦 CANCEL REQ: Talep oluşturuluyor...');
      debugPrint('  └─ orderId: $orderId');
      debugPrint('  └─ reason: $reason');

      final response = await _supabase.rpc(
        'create_cancellation_request',
        params: {
          'p_order_id': orderId,
          'p_reason': reason,
        },
      );

      // RPC RETURNS cancellation_requests (single row object) — direkt map
      return CancellationRequest.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      debugPrint('❌ CANCEL REQ: Talep oluşturulamadı - $e');
      rethrow;
    }
  }

  /// Müşterinin belirli sipariş için bekleyen talebi var mı?
  /// (Sipariş detay ekranında "Talebiniz var" badge'i için)
  Future<CancellationRequest?> getMyPendingRequest(String orderId) async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return null;

      final response = await _supabase
          .from('cancellation_requests')
          .select('*, orders(order_number)')
          .eq('order_id', orderId)
          .eq('user_id', userId)
          .eq('status', 'pending')
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;
      return CancellationRequest.fromJson(response);
    } catch (e) {
      debugPrint('⚠️ CANCEL REQ: Bekleyen talep kontrolü başarısız - $e');
      return null;
    }
  }

  /// Müşterinin tüm iptal talepleri (geçmiş + bekleyen)
  Future<List<CancellationRequest>> getMyRequests() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return [];

      final response = await _supabase
          .from('cancellation_requests')
          .select('*, orders(order_number), shops(name)')
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      return (response as List)
          .map((j) => CancellationRequest.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('❌ CANCEL REQ: Talepler getirilemedi - $e');
      return [];
    }
  }

  // ---------------------------------------------------------------------
  // ADMIN
  // ---------------------------------------------------------------------

  /// Admin: bekleyen tüm iptal talepleri
  Future<List<CancellationRequest>> getPendingRequests() async {
    try {
      final response = await _supabase
          .from('cancellation_requests')
          .select('''
            *,
            orders(order_number, total),
            shops(name),
            profiles:user_id(full_name, username)
          ''')
          .eq('status', 'pending')
          .order('created_at', ascending: true);

      return (response as List)
          .map((j) => CancellationRequest.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('❌ CANCEL REQ (admin): Bekleyen talepler getirilemedi - $e');
      rethrow;
    }
  }

  /// Admin: tüm talepler (status filtresi opsiyonel)
  Future<List<CancellationRequest>> getAllRequests({String? status}) async {
    try {
      var query = _supabase
          .from('cancellation_requests')
          .select('''
            *,
            orders(order_number, total),
            shops(name),
            profiles:user_id(full_name, username)
          ''');

      if (status != null) {
        query = query.eq('status', status);
      }

      final response = await query.order('created_at', ascending: false);
      return (response as List)
          .map((j) => CancellationRequest.fromJson(j as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('❌ CANCEL REQ (admin): Talepler getirilemedi - $e');
      rethrow;
    }
  }

  /// Admin: bekleyen talep sayısı (sidebar badge'i için)
  Future<int> getPendingCount() async {
    try {
      final response = await _supabase
          .from('cancellation_requests')
          .select('id')
          .eq('status', 'pending');

      return (response as List).length;
    } catch (e) {
      return 0;
    }
  }

  /// Admin: iptal talebini onayla
  /// Atomik: orders cancelled + (iade varsa) bakiyeye ekleme + notification
  Future<CancellationRequest> approve({
    required String requestId,
    String? adminResponse,
  }) async {
    try {
      debugPrint('✅ CANCEL REQ: Onaylanıyor...');
      debugPrint('  └─ requestId: $requestId');

      final response = await _supabase.rpc(
        'approve_cancellation_request',
        params: {
          'p_request_id': requestId,
          'p_admin_response': adminResponse,
        },
      );

      return CancellationRequest.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      debugPrint('❌ CANCEL REQ: Onay başarısız - $e');
      rethrow;
    }
  }

  /// Admin: iptal talebini reddet
  Future<CancellationRequest> reject({
    required String requestId,
    required String adminResponse,
  }) async {
    try {
      debugPrint('❌ CANCEL REQ: Reddediliyor...');
      debugPrint('  └─ requestId: $requestId');

      final response = await _supabase.rpc(
        'reject_cancellation_request',
        params: {
          'p_request_id': requestId,
          'p_admin_response': adminResponse,
        },
      );

      return CancellationRequest.fromJson(response as Map<String, dynamic>);
    } catch (e) {
      debugPrint('❌ CANCEL REQ: Red başarısız - $e');
      rethrow;
    }
  }

  /// Admin: tek adımda sipariş iptal + (iade varsa) bakiyeye iade.
  ///
  /// Müşteri talebi olmadan admin direkt iptal ettiğinde çağrılır.
  /// Onay diyaloğu UI tarafında gösterilir; admin onayladığında bu metot
  /// çağrılır ve DB'de atomik olarak:
  ///   1) cancellation_requests kaydı (status=approved, audit trail)
  ///   2) refund_amount>0 ise add_to_balance ile bakiyeye iade
  ///   3) orders.status='cancelled', payment_status='refunded' (iade varsa)
  ///   4) restore_product_stock trigger (confirmed->cancelled)
  ///   5) müşteriye notification
  Future<CancellationRequest> adminCancelWithRefund({
    required String orderId,
    String reason = 'Admin tarafından iptal edildi',
  }) async {
    try {
      debugPrint('⚠️ CANCEL REQ (admin): Tek adım iptal+iade');
      debugPrint('  └─ orderId: $orderId');
      debugPrint('  └─ reason: $reason');

      final response = await _supabase.rpc(
        'admin_cancel_with_refund',
        params: {
          'p_order_id': orderId,
          'p_reason': reason,
        },
      );

      final result = CancellationRequest.fromJson(response as Map<String, dynamic>);
      debugPrint('✅ CANCEL REQ (admin): İptal+iade tamam - iade: ₺${result.refundAmount}');
      return result;
    } catch (e) {
      debugPrint('❌ CANCEL REQ (admin): İptal+iade başarısız - $e');
      rethrow;
    }
  }
}