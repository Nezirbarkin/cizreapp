// payment_service.dart (SERVER-AUTHORITATIVE ADAPTER)
// Tarih: 2026-08-02
//
// Bu servis SADECE:
// 1) iyzico-payment-init edge function çağrısı (token al)
// 2) WebView açma (token ile paymentPageUrl)
// 3) Bakiye ödeme (CheckoutService.commitBalanceOrder)
//
// Eski completeOnlinePayment, atomicFinalizePaymentTransaction, callback_data
// üzerinden sipariş oluşturma KULLANILMAZ.

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/checkout_session_model.dart';
import 'checkout_service.dart';

class PaymentException implements Exception {
  final String code;
  final String message;
  PaymentException(this.code, this.message);

  @override
  String toString() => 'PaymentException($code): $message';
}

class PaymentService {
  final SupabaseClient _supabase;
  final CheckoutService _checkoutService;

  PaymentService(this._supabase, this._checkoutService);

  // ═══════════════════════════════════════════════════════════════
  // ONLINE (iyzico)
  // ═══════════════════════════════════════════════════════════════

  /// iyzico ödeme akışını başlatır. Server-authoritative: tüm
  /// fiyat, ürün, adres, kupon bilgisi session snapshot'tan
  /// okunur. Client'tan sadece session_id alınır.
  Future<OnlinePaymentInitResult> startOnlinePayment({
    required CheckoutSession session,
    String? preferredIdempotencyKey,
  }) async {
    if (!session.isOnline) {
      throw PaymentException('wrong_method', 'Bu session online ödeme için değil.');
    }
    final idemKey = preferredIdempotencyKey ??
        CheckoutService.generateIdempotencyKey(prefix: 'iyzico');

    return _checkoutService.initOnlinePayment(
      checkoutSessionId: session.id,
      idempotencyKey: idemKey,
    );
  }

  /// iyzico token ile checkout form URL'i döner. WebView bu URL'i
  /// yükler; kullanıcı ödemeyi tamamlar, callback session snapshot'tan
  /// order oluşturur.
  String buildCheckoutFormUrl(OnlinePaymentInitResult init) {
    if (init.paymentPageUrl != null && init.paymentPageUrl!.isNotEmpty) {
      return init.paymentPageUrl!;
    }
    // iyzico v2 token-based form
    return 'https://www.iyzico.com/checkoutform/content/form/${init.token}';
  }

  // ═══════════════════════════════════════════════════════════════
  // BALANCE
  // ═══════════════════════════════════════════════════════════════

  Future<CheckoutCommitResult> payWithBalance(CheckoutSession session) async {
    if (!session.isBalance) {
      throw PaymentException('wrong_method', 'Bu session bakiye ödemesi için değil.');
    }
    return _checkoutService.commitBalanceOrder(session.id);
  }

  // ═══════════════════════════════════════════════════════════════
  // RECONCILIATION
  // ═══════════════════════════════════════════════════════════════

  /// Pending iyzico ödemesinin sonucunu sorgular. Callback başarısız
  /// olursa (kullanıcı tarayıcıyı kapattı) buradan durum öğrenilir.
  Future<Map<String, dynamic>?> getPaymentTransaction(String txnId) async {
    final response = await _supabase
        .from('payment_transactions')
        .select('id, payment_status, order_id, reconciliation_status, reconciliation_note')
        .eq('id', txnId)
        .maybeSingle();
    return response;
  }
}
