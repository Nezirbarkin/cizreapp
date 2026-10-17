// checkout_service.dart
// Tarih: 2026-08-02
//
// Bu servis client'in TEK giris noktasidir. Tum finansal hesaplamalar
// sunucuda yapilir; client yalnizca session_id alip commit eder.
//
// - prepareCheckout(): private.prepare_checkout_session RPC
// - commitCod(): private.commit_cod_order RPC
// - commitBalance(): private.commit_balance_order RPC (veya edge function)
// - initOnlinePayment(): iyzico-payment-init edge function
//
// Eski API'ler (create_order_with_items, validate_coupon, use_coupon,
// atomic_finalize_payment_transaction) KULLANILMAZ.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../core/models/order_model.dart' show PaymentMethod;
import '../models/checkout_session_model.dart';

class CheckoutException implements Exception {
  final String code;
  final String message;
  CheckoutException(this.code, this.message);

  /// Kullanıcıya gösterilecek metin. Sunucu iş kuralı hatalarını
  /// `APP: kod | Türkçe mesaj` biçiminde verir; mesaj kısmı aynen gösterilir.
  String get userMessage {
    final sep = message.indexOf('|');
    if (message.trimLeft().startsWith('APP:') && sep > 0) {
      return message.substring(sep + 1).trim();
    }
    switch (code) {
      case 'auth_required':
        return 'Lütfen giriş yapın';
      case 'empty_cart':
        return 'Sepetiniz boş';
      case 'forbidden':
        return 'Bu işlem için yetkiniz yok';
      case 'network':
        return 'Bağlantı hatası, lütfen tekrar deneyin';
    }
    return message;
  }

  @override
  String toString() => 'CheckoutException($code): $message';
}

class CheckoutService {
  final SupabaseClient _supabase;
  static const Duration _sessionTtl = Duration(minutes: 15);

  CheckoutService(this._supabase);

  // ═══════════════════════════════════════════════════════════════
  // PREPARE — server quote snapshot
  // ═══════════════════════════════════════════════════════════════

  /// Yeni bir checkout oturumu olusturur veya ayni idempotency_key
  /// ile mevcutsa onu dondurur.
  ///
  /// Client yalnizca items (product_id+quantity), address_id,
  /// payment_method, coupon_id/code, notes, invoice_data ve
  /// idempotency_key gonderir. HIC BIR FINANSAL ALAN GONDERILMEZ.
  Future<CheckoutSession> prepareCheckout(CheckoutSessionRequest req) async {
    if (req.idempotencyKey.trim().isEmpty) {
      throw CheckoutException('idempotency_required',
          'Idempotency key zorunludur.');
    }
    if (req.items.isEmpty) {
      throw CheckoutException('empty_cart', 'Sepet bos.');
    }
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw CheckoutException('auth_required', 'Oturum acin.');
    }

    try {
      // p_items JSON dizisi olarak gider (metin değil). Tutar alanı YOK.
      final response = await _supabase
          .rpc('prepare_checkout_session', params: {
        'p_items': req.items.map((e) => e.toJson()).toList(),
        'p_address_id': req.addressId,
        'p_payment_method': req.paymentMethod,
        'p_idempotency_key': req.idempotencyKey,
        'p_coupon_ids': req.allCouponIds,
        'p_pickup_shop_ids': req.pickupShopIds,
        'p_notes': req.notes,
        'p_invoice_data': req.invoiceData,
      });

      final row = (response as List).first as Map<String, dynamic>;
      return CheckoutSession.fromJson(row);
    } on PostgrestException catch (e) {
      throw _mapPgError(e);
    } catch (e) {
      if (e is CheckoutException) rethrow;
      throw CheckoutException('prepare_failed', 'Hata: ${e.toString()}');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // COMMIT — COD / Balance
  // ═══════════════════════════════════════════════════════════════

  Future<CheckoutCommitResult> commitCodOrder(String sessionId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw CheckoutException('auth_required', 'Oturum acin.');
    }
    try {
      final response = await _supabase
          .rpc('commit_cod_order', params: {'p_session_id': sessionId});
      final row = (response as List).first as Map<String, dynamic>;
      return CheckoutCommitResult.fromJson(row);
    } on PostgrestException catch (e) {
      throw _mapPgError(e);
    }
  }

  /// Bakiyeden peşin ödeme. Hepsi ya da hiçbiri: toplam bakiye yetmezse
  /// hiçbir sipariş açılmaz (`insufficient_balance`).
  Future<CheckoutCommitResult> commitBalanceOrder(String sessionId) async {
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw CheckoutException('auth_required', 'Oturum acin.');
    }
    try {
      final response = await _supabase
          .rpc('commit_balance_order', params: {'p_session_id': sessionId});
      final row = (response as List).first as Map<String, dynamic>;
      return CheckoutCommitResult.fromJson(row);
    } on PostgrestException catch (e) {
      throw _mapPgError(e);
    }
  }

  /// Kullanıcı onay penceresini kapattığında oturumu ve flaş rezervasyonunu
  /// hemen bırakır (aksi halde 15 dk sonra kendiliğinden düşer). Hata
  /// yutulur: ödeme akışını hiçbir zaman engellemez.
  Future<bool> cancelCheckoutSession(String sessionId) async {
    try {
      final response = await _supabase.rpc(
        'cancel_checkout_session',
        params: {'p_session_id': sessionId},
      );
      return response == true;
    } catch (e) {
      debugPrint('cancel_checkout_session basarisiz: $e');
      return false;
    }
  }

  /// Uygulamanın ödeme yöntemi enum'unu sunucu oturum değerine çevirir.
  static String paymentMethodValue(PaymentMethod method) {
    switch (method) {
      case PaymentMethod.cash:
        return 'cash';
      case PaymentMethod.cardOnDelivery:
        return 'card_on_delivery';
      case PaymentMethod.balance:
        return 'balance';
      case PaymentMethod.online:
        return 'online';
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // INIT — iyzico online payment
  // ═══════════════════════════════════════════════════════════════

  /// iyzico checkout form token alir.
  /// Client yalnizca session_id gonderir; fiyat, urun, adres, kupon
  /// HICBIR SEKILDE yeniden gonderilmez. Edge function session
  /// snapshot'tan okur.
  Future<OnlinePaymentInitResult> initOnlinePayment({
    required String checkoutSessionId,
    required String idempotencyKey,
  }) async {
    if (checkoutSessionId.isEmpty || idempotencyKey.isEmpty) {
      throw CheckoutException('invalid_input', 'session_id ve idempotency_key zorunlu.');
    }
    final user = _supabase.auth.currentUser;
    if (user == null) {
      throw CheckoutException('auth_required', 'Oturum acin.');
    }
    try {
      final response = await _supabase.functions.invoke(
        'iyzico-payment-init',
        body: {
          'checkout_session_id': checkoutSessionId,
          'idempotency_key': idempotencyKey,
        },
      );
      final data = response.data is Map
          ? Map<String, dynamic>.from(response.data as Map)
          : null;
      if (response.status != 200 || data == null) {
        final code = data?['error'] as String? ?? 'init_failed';
        throw CheckoutException(code, data?['message'] as String? ?? 'Baslatma hatasi');
      }
      final result = OnlinePaymentInitResult.fromJson(data);
      if ((result.paymentPageUrl ?? '').isEmpty ||
          (result.paymentTransactionId ?? '').isEmpty) {
        throw CheckoutException('init_failed', 'Ödeme sayfası alınamadı');
      }
      return result;
    } on CheckoutException {
      rethrow;
    } on FunctionException catch (e) {
      // 2xx dışı yanıtlar burada gelir; gövde {error, message} taşır.
      final details = e.details;
      if (details is Map) {
        final code = details['error']?.toString() ?? 'init_failed';
        final message = details['message']?.toString() ?? code;
        throw CheckoutException(code, message);
      }
      throw CheckoutException('init_failed', 'Ödeme başlatılamadı');
    } catch (e) {
      throw CheckoutException('init_failed', 'Odeme baslatma hatasi');
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // IDEMPOTENCY KEY OLUSTURMA
  // ═══════════════════════════════════════════════════════════════

  /// Client tarafinda idempotency_key uretir. Network hata / retry
  /// durumlarinda AYNI key ile yeniden prepare edilirse server
  /// AYNI session_id'yi dondurur (UNIQUE(user_id, idempotency_key)).
  static String generateIdempotencyKey({String? prefix}) {
    final uuid = const Uuid().v4();
    final ts = DateTime.now().millisecondsSinceEpoch;
    return prefix != null ? '${prefix}_${ts}_$uuid' : '${ts}_$uuid';
  }

  /// Session icin 15dk TTL
  static Duration get sessionTtl => _sessionTtl;

  // ═══════════════════════════════════════════════════════════════
  // ERROR MAP
  // ═══════════════════════════════════════════════════════════════

  CheckoutException _mapPgError(PostgrestException e) {
    final code = e.code ?? '';
    final msg = e.message;

    // Uygulama seviyesi RAISE EXCEPTION (P0001)
    if (code == 'P0001' || code == 'P0002') {
      // Mesajdan kod cikar: "APP: stock_unavailable | ..."
      final appCode = msg.contains('|')
          ? msg.split('|').first.replaceFirst('APP:', '').trim()
          : 'app_error';
      return CheckoutException(appCode, msg);
    }
    if (code == '42501') {
      return CheckoutException('forbidden', msg);
    }
    if (code == '28000') {
      return CheckoutException('auth_required', msg);
    }
    // UNIQUE violation
    if (code == '23505') {
      return CheckoutException('duplicate', 'Tekrar istek.');
    }
    // Check violation
    if (code == '23514') {
      return CheckoutException('check_violation', msg);
    }
    return CheckoutException('db_error', msg);
  }
}

@immutable
class CheckoutCommitResult {
  final String orderId;
  final String orderNumber;
  /// Oturumun sunucu toplamı (tüm mağaza siparişleri).
  final num amountPaid;
  /// Bakiye ödemesinden sonra kalan bakiye.
  final num? remainingBalance;
  final String? groupId;
  final List<String> orderIds;
  final int orderCount;
  /// Çok mağazalı sepette ortak "GRP..." numarası; tek mağazada null.
  final String? groupOrderNumber;

  const CheckoutCommitResult({
    required this.orderId,
    required this.orderNumber,
    required this.amountPaid,
    this.remainingBalance,
    this.groupId,
    this.orderIds = const [],
    this.orderCount = 1,
    this.groupOrderNumber,
  });

  factory CheckoutCommitResult.fromJson(Map<String, dynamic> json) {
    final orderId = json['order_id'] as String;
    final ids = (json['order_ids'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [orderId];
    return CheckoutCommitResult(
      orderId: orderId,
      orderNumber: json['order_number'] as String? ?? '',
      amountPaid: (json['amount_paid'] ?? json['total']) as num? ?? 0,
      remainingBalance:
          (json['remaining_balance'] ?? json['new_balance']) as num?,
      groupId: (json['group_id'] ?? json['order_group_id']) as String?,
      orderIds: ids,
      orderCount: (json['order_count'] as num?)?.toInt() ?? ids.length,
      groupOrderNumber: json['group_order_number'] as String?,
    );
  }
}

@immutable
class OnlinePaymentInitResult {
  final String token;
  final String? paymentPageUrl;
  final String? conversationId;
  final String? paymentTransactionId;

  const OnlinePaymentInitResult({
    required this.token,
    this.paymentPageUrl,
    this.conversationId,
    this.paymentTransactionId,
  });

  factory OnlinePaymentInitResult.fromJson(Map<String, dynamic> json) {
    return OnlinePaymentInitResult(
      token: json['token'] as String? ?? '',
      paymentPageUrl: json['paymentPageUrl'] as String? ?? json['payment_page_url'] as String?,
      conversationId:
          json['conversationId'] as String? ?? json['conversation_id'] as String?,
      paymentTransactionId: json['payment_transaction_id'] as String?,
    );
  }
}
