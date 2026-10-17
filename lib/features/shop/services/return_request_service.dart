import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// İade talebi durumları
///
/// [pending]   -> Müşteri açtı, yönetici inceliyor
/// [approved]  -> Yönetici onayladı; tutar müşteri bakiyesine eklendi,
///                satıcının payı mağaza hesabından düşüldü
/// [rejected]  -> Yönetici reddetti
/// [completed] -> Satıcı (veya yönetici) iade edilen ürünleri teslim aldı
/// [cancelled] -> Müşteri bekleyen talebini geri çekti
enum ReturnRequestStatus {
  pending,
  approved,
  rejected,
  completed,
  cancelled;

  String get label {
    switch (this) {
      case ReturnRequestStatus.pending:
        return 'İncelemede';
      case ReturnRequestStatus.approved:
        return 'Onaylandı';
      case ReturnRequestStatus.rejected:
        return 'Reddedildi';
      case ReturnRequestStatus.completed:
        return 'Tamamlandı';
      case ReturnRequestStatus.cancelled:
        return 'Geri Çekildi';
    }
  }

  String get dbValue => name;

  static ReturnRequestStatus fromString(String? value) {
    return ReturnRequestStatus.values.firstWhere(
      (status) => status.name == value,
      orElse: () => ReturnRequestStatus.pending,
    );
  }
}

/// İade talebindeki tek ürün satırı (talep anındaki fiyat kilitlidir)
class ReturnRequestItem {
  final String id;
  final String orderItemId;
  final String? productId;
  final String productName;
  final String? productImageUrl;
  final int quantity;
  final double unitPrice;
  final double lineTotal;

  const ReturnRequestItem({
    required this.id,
    required this.orderItemId,
    this.productId,
    required this.productName,
    this.productImageUrl,
    required this.quantity,
    required this.unitPrice,
    required this.lineTotal,
  });

  factory ReturnRequestItem.fromJson(Map<String, dynamic> json) {
    return ReturnRequestItem(
      id: json['id'] as String? ?? '',
      orderItemId: json['order_item_id'] as String? ?? '',
      productId: json['product_id'] as String?,
      productName: json['product_name'] as String? ?? 'Ürün',
      productImageUrl: json['product_image_url'] as String?,
      quantity: (json['quantity'] as num?)?.toInt() ?? 0,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0,
      lineTotal: (json['line_total'] as num?)?.toDouble() ?? 0,
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

  /// 'full' = siparişin tamamı tek talepte, 'partial' = seçili ürünler
  final String returnScope;
  final String? paymentMethod;

  /// 'balance' = platform müşteri bakiyesine iade eder;
  /// 'seller_cash' = kuryeli satıcı kapıda tahsil etmişti, nakdi kendisi iade
  /// eder ve iade tutarının komisyonu satıcının borcundan düşülür.
  final String refundMethod;
  final double refundAmount;
  final double sellerDebitAmount;

  /// İade edilen tutar için adminin vazgeçtiği komisyon.
  final double commissionRefundAmount;
  final String? adminResponse;
  final DateTime? reviewedAt;
  final DateTime? receivedAt;

  /// Para iadesinin yapıldığı an (satıcının teslim alması ya da yöneticinin
  /// "Hemen İade Et"i). null = henüz ödenmedi.
  final DateTime? refundedAt;
  final bool restocked;
  final DateTime createdAt;
  final DateTime? updatedAt;

  final List<ReturnRequestItem> items;

  // İlişkili veriler (get_return_requests RPC'si doldurur)
  final String? orderNumber;
  final double? orderTotal;
  final String? shopName;
  final String? customerName;

  ReturnRequest({
    required this.id,
    required this.orderId,
    required this.userId,
    required this.shopId,
    required this.reason,
    required this.status,
    this.returnScope = 'full',
    this.paymentMethod,
    this.refundMethod = 'balance',
    this.refundAmount = 0,
    this.sellerDebitAmount = 0,
    this.commissionRefundAmount = 0,
    this.adminResponse,
    this.reviewedAt,
    this.receivedAt,
    this.refundedAt,
    this.restocked = false,
    required this.createdAt,
    this.updatedAt,
    this.items = const [],
    this.orderNumber,
    this.orderTotal,
    this.shopName,
    this.customerName,
  });

  bool get isFullReturn => returnScope == 'full';
  bool get isSellerCashRefund => refundMethod == 'seller_cash';

  /// Müşteriye para iadesi yapıldı mı?
  bool get isRefunded => refundedAt != null;
  int get totalQuantity => items.fold(0, (sum, i) => sum + i.quantity);

  static DateTime? _date(dynamic v) =>
      v == null ? null : DateTime.tryParse(v as String);

  factory ReturnRequest.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List? ?? const [];
    return ReturnRequest(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      userId: json['user_id'] as String,
      shopId: json['shop_id'] as String,
      reason: json['reason'] as String? ?? '',
      status: ReturnRequestStatus.fromString(json['status'] as String?),
      returnScope: json['return_scope'] as String? ?? 'full',
      paymentMethod: json['payment_method'] as String?,
      refundAmount: (json['refund_amount'] as num?)?.toDouble() ?? 0,
      refundMethod: json['refund_method'] as String? ?? 'balance',
      sellerDebitAmount: (json['seller_debit_amount'] as num?)?.toDouble() ?? 0,
      commissionRefundAmount:
          (json['commission_refund_amount'] as num?)?.toDouble() ?? 0,
      adminResponse: json['admin_response'] as String?,
      reviewedAt: _date(json['reviewed_at']),
      receivedAt: _date(json['received_at']),
      refundedAt: _date(json['refunded_at']),
      restocked: json['restocked'] as bool? ?? false,
      createdAt: _date(json['created_at']) ?? DateTime.now(),
      updatedAt: _date(json['updated_at']),
      items: rawItems
          .map((e) => ReturnRequestItem.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList(),
      orderNumber: json['order_number']?.toString(),
      orderTotal: (json['order_total'] as num?)?.toDouble(),
      shopName: json['shop_name'] as String?,
      customerName: json['customer_name'] as String?,
    );
  }
}

/// Müşterinin iade için seçtiği sipariş kalemi + adet
class ReturnItemSelection {
  final String orderItemId;
  final int quantity;

  const ReturnItemSelection({required this.orderItemId, required this.quantity});

  Map<String, dynamic> toJson() => {
        'order_item_id': orderItemId,
        'quantity': quantity,
      };
}

/// İade talebi servisi
///
/// Tüm yazma işlemleri DB'de atomik RPC'lerdir (20261016000007):
/// - create_return_request   (müşteri; tümü ya da seçili ürünler)
/// - cancel_return_request   (müşteri; yalnız bekleyen)
/// - approve_return_request  (yönetici; bakiyeye iade + satıcı payı + bildirim;
///                            kuryeli satıcının kapıda tahsilatında satıcı nakit
///                            iade eder, komisyon borcundan düşülür)
/// - reject_return_request   (yönetici)
/// - mark_return_received    (satıcı/yönetici; isteğe bağlı stoğa ekleme)
/// - get_return_requests     (liste; adlar ve kalemler tek istekte)
class ReturnRequestService {
  /// İade hakkı teslimattan sonra bu kadar gün (DB'deki sınırla aynı).
  static const int returnWindowDays = 14;

  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      rethrow;
    }
  }

  ReturnRequest _single(dynamic response) =>
      ReturnRequest.fromJson(Map<String, dynamic>.from(response as Map));

  Future<List<ReturnRequest>> _list({
    required String scope,
    String? status,
    String? orderId,
  }) async {
    final response = await _supabase.rpc(
      'get_return_requests',
      params: {
        'p_scope': scope,
        'p_status': status,
        'p_order_id': orderId,
      },
    );
    return (response as List? ?? const [])
        .map((e) => ReturnRequest.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList();
  }

  // ---------------------------------------------------------------------
  // MÜŞTERİ
  // ---------------------------------------------------------------------

  /// İade talebi aç. [items] null/boş = siparişte kalan tüm ürünler.
  Future<ReturnRequest> createReturnRequest({
    required String orderId,
    required String reason,
    List<ReturnItemSelection>? items,
  }) async {
    try {
      final response = await _supabase.rpc(
        'create_return_request',
        params: {
          'p_order_id': orderId,
          'p_reason': reason,
          'p_items': (items == null || items.isEmpty)
              ? null
              : items.map((i) => i.toJson()).toList(),
        },
      );
      return _single(response);
    } catch (e) {
      debugPrint('❌ RETURN: İade talebi oluşturulamadı: $e');
      rethrow;
    }
  }

  /// Bekleyen talebi geri çek
  Future<ReturnRequest> cancelReturnRequest(String requestId) async {
    final response = await _supabase.rpc(
      'cancel_return_request',
      params: {'p_request_id': requestId},
    );
    return _single(response);
  }

  /// Kullanıcının iade talepleri (en yeni önce)
  Future<List<ReturnRequest>> getMyReturnRequests() async {
    try {
      return await _list(scope: 'customer');
    } catch (e) {
      debugPrint('❌ RETURN: Kullanıcı iade talepleri alınamadı: $e');
      rethrow;
    }
  }

  /// Bir siparişe ait talepler (sipariş detay ekranı için)
  Future<List<ReturnRequest>> getOrderReturnRequests(String orderId) async {
    try {
      return await _list(scope: 'customer', orderId: orderId);
    } catch (e) {
      debugPrint('❌ RETURN: Sipariş iade talepleri alınamadı: $e');
      return [];
    }
  }

  // ---------------------------------------------------------------------
  // SATICI
  // ---------------------------------------------------------------------

  /// Satıcının mağaza(lar)ına gelen talepler
  Future<List<ReturnRequest>> getShopReturnRequests() async {
    try {
      return await _list(scope: 'seller');
    } catch (e) {
      debugPrint('❌ RETURN: Dükkan iade talepleri alınamadı: $e');
      rethrow;
    }
  }

  /// İade edilen ürünler teslim alındı (onaylı talep → tamamlandı)
  Future<ReturnRequest> markReceived({
    required String requestId,
    bool restock = false,
  }) async {
    final response = await _supabase.rpc(
      'mark_return_received',
      params: {'p_request_id': requestId, 'p_restock': restock},
    );
    return _single(response);
  }

  // ---------------------------------------------------------------------
  // YÖNETİCİ
  // ---------------------------------------------------------------------

  Future<List<ReturnRequest>> getAdminReturnRequests({String? status}) =>
      _list(scope: 'admin', status: status);

  Future<int> getPendingCount() async {
    try {
      final response = await _supabase
          .from('return_requests')
          .select('id')
          .eq('status', 'pending');
      return (response as List).length;
    } catch (e) {
      return 0;
    }
  }

  Future<ReturnRequest> approve({
    required String requestId,
    String? adminResponse,
  }) async {
    final response = await _supabase.rpc(
      'approve_return_request',
      params: {
        'p_request_id': requestId,
        'p_admin_response': adminResponse,
      },
    );
    return _single(response);
  }

  /// Satıcıyı beklemeden müşteriye hemen iade (bekleyen talebi de onaylar).
  /// Kapıda nakitte de bakiyeye iade edilir; satıcı payı borcuna yazılır.
  Future<ReturnRequest> refundNow({
    required String requestId,
    String? adminResponse,
  }) async {
    final response = await _supabase.rpc(
      'admin_refund_return_now',
      params: {
        'p_request_id': requestId,
        'p_admin_response': adminResponse,
      },
    );
    return _single(response);
  }

  /// Satıcının Genel Bakış iade özeti (seller_return_summary).
  Future<Map<String, dynamic>> getSellerSummary() async {
    final response = await _supabase.rpc('seller_return_summary');
    return Map<String, dynamic>.from(response as Map? ?? const {});
  }

  Future<ReturnRequest> reject({
    required String requestId,
    required String adminResponse,
  }) async {
    final response = await _supabase.rpc(
      'reject_return_request',
      params: {
        'p_request_id': requestId,
        'p_admin_response': adminResponse,
      },
    );
    return _single(response);
  }
}

/// Supabase/PostgREST hatasından kullanıcıya gösterilecek kısa metin.
String returnErrorMessage(Object e) {
  if (e is PostgrestException) return e.message;
  final s = e.toString();
  return s.startsWith('Exception: ') ? s.substring(11) : s;
}
