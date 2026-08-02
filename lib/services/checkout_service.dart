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
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/checkout_session_model.dart';

class CheckoutException implements Exception {
  final String code;
  final String message;
  CheckoutException(this.code, this.message);

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
      final response = await _supabase
          .rpc('prepare_checkout_session', params: {
        'p_items': jsonEncode(req.items.map((e) => e.toJson()).toList()),
        'p_address_id': req.addressId,
        'p_payment_method': req.paymentMethod,
        'p_idempotency_key': req.idempotencyKey,
        'p_coupon_id': req.couponId,
        'p_coupon_code': req.couponCode,
        'p_notes': req.notes,
        'p_invoice_data': req.invoiceData,
        'p_order_group_id': req.orderGroupId,
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
      final data = response.data as Map<String, dynamic>?;
      if (response.status != 200 || data == null) {
        final code = data?['error'] as String? ?? 'init_failed';
        throw CheckoutException(code, data?['message'] as String? ?? 'Baslatma hatasi');
      }
      return OnlinePaymentInitResult.fromJson(data);
    } on CheckoutException {
      rethrow;
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
  final num amountPaid;
  final num? remainingBalance;
  final String? groupId;

  const CheckoutCommitResult({
    required this.orderId,
    required this.orderNumber,
    required this.amountPaid,
    this.remainingBalance,
    this.groupId,
  });

  factory CheckoutCommitResult.fromJson(Map<String, dynamic> json) {
    return CheckoutCommitResult(
      orderId: json['order_id'] as String,
      orderNumber: json['order_number'] as String? ?? '',
      amountPaid: json['amount_paid'] as num? ?? 0,
      remainingBalance: json['remaining_balance'] as num?,
      groupId: json['group_id'] as String?,
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
      conversationId: json['conversationId'] as String?,
      paymentTransactionId: json['payment_transaction_id'] as String?,
    );
  }
}
