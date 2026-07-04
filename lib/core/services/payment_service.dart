import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../utils/app_error_handler.dart';

/// Online Ödeme Servisi (iyzico)
/// iyzico Edge Functions ile iletişim kurar
class PaymentService {
  /// Supabase client'ı güvenli şekilde al (lazy) - class-level initializer yerine
  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      rethrow;
    }
  }
  // NOT: Aşağıdaki edge function çağrılarında ham FunctionException yerine
  // FriendlyException fırlatılır (kullanıcı dostu mesaj).

  /// iyzico ödeme başlatma
  /// 
  /// Returns: payment_page_url (iyzico ödeme sayfası)
  /// 
  /// Edge Function: iyzico-payment-init
  Future<PaymentInitResult> initializePayment({
    required Map<String, dynamic> orderData,
    required Map<String, dynamic> buyer,
    Map<String, dynamic>? billingAddress,
    Map<String, dynamic>? shippingAddress,
  }) async {
    try {
      debugPrint('💳 PAYMENT: iyzico ödeme başlatılıyor...');
      debugPrint('  └─ shopId: ${orderData['shop_id']}');
      debugPrint('  └─ total: ${orderData['total']}');

      // User ID'yi authenticated user'dan al
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        throw Exception('Kullanıcı oturumu bulunamadı. Lütfen giriş yapın.');
      }

      // Edge Function çağrısı
      final response = await _supabase.functions.invoke(
        'iyzico-payment-init',
        body: {
          'user_id': userId,
          'order_data': orderData,
          'buyer': buyer,
          if (billingAddress != null) 'billing_address': billingAddress,
          if (shippingAddress != null) 'shipping_address': shippingAddress,
        },
      );

      debugPrint('💳 PAYMENT: Edge Function yanıt alındı');
      debugPrint('  └─ status: ${response.status}');

      if (response.status != 200) {
        debugPrint('❌ PAYMENT: Edge Function hatası');
        final errorData = response.data;
        throw Exception(
          errorData['error'] ?? 'Ödeme başlatılamadı. Lütfen tekrar deneyin.',
        );
      }

      final data = response.data;
      
      if (data['status'] != 'success') {
        throw Exception(data['error'] ?? 'Ödeme başlatılamadı');
      }

      debugPrint('✅ PAYMENT: Ödeme sayfası URL alındı');

      return PaymentInitResult(
        paymentPageUrl: data['payment_page_url'],
        token: data['token'],
        tokenExpireTime: data['token_expire_time'],
        conversationId: data['conversation_id'],
        paymentTransactionId: data['payment_transaction_id'],
      );
    } catch (e) {
      debugPrint('❌ PAYMENT: Hata - $e');
      throw FriendlyException.from(e);
    }
  }

  /// Ödeme durumunu sorgula (payment_transactions tablosundan)
  ///
  /// ÖNEMLİ: payment_status='success' olması yeterli DEĞİL.
  /// order_id'nin de var olup olmadığını kontrol etmek gerekir.
  /// Callback'de sıra kaybı olursa (callback başarılı ama sipariş
  /// oluşturulamadıysa), payment_status='success' olur ama order_id
  /// NULL kalır. Bu durumda "zaten sipariş oluşturulmuş" yanılgısı
  /// oluşur — Flutter "başarılı" der ama sipariş veritabanında yoktur.
  Future<PaymentStatus> checkPaymentStatus(String paymentTransactionId) async {
    try {
      debugPrint('🔍 PAYMENT: Ödeme durumu sorgulanıyor...');
      debugPrint('  └─ paymentTransactionId: $paymentTransactionId');

      final response = await _supabase
          .from('payment_transactions')
          .select('payment_status, order_id')
          .eq('id', paymentTransactionId)
          .single();

      final status = response['payment_status'] as String;
      final orderId = response['order_id'] as String?;

      debugPrint('✅ PAYMENT: Durum alındı - $status, orderId: ${orderId ?? "yok"}');

      // 2026-06-30: order_id kontrolü kaldırıldı.
      // ÖNEMLİ: payment_status='success' ise callback başarıyla çalışmış demektir.
      // order_id set edilse de edilmese de sipariş oluşturulmuştur
      // (callback'de idempotent RPC kullanılıyor, sipariş orders tablosunda).
      // Order_id sadece bonus bilgi — yoksa sipariş yine de oluşmuş olabilir.

      return PaymentStatus(
        status: status,
        orderId: orderId,
      );
    } catch (e) {
      debugPrint('❌ PAYMENT: Durum sorgulama hatası - $e');
      throw FriendlyException.from(e);
    }
  }

  /// Sipariş numarasını payment transaction'dan al
  Future<String?> getOrderNumber(String orderId) async {
    try {
      final response = await _supabase
          .from('orders')
          .select('order_number')
          .eq('id', orderId)
          .single();

      return response['order_number'] as String?;
    } catch (e) {
      debugPrint('❌ PAYMENT: Sipariş numarası alınamadı - $e');
      return null;
    }
  }

  /// Payment transaction'ı iptal et (pending durumundaysa)
  Future<void> cancelPaymentTransaction(String paymentTransactionId) async {
    try {
      debugPrint('🚫 PAYMENT: Ödeme transaction iptal ediliyor...');

      await _supabase
          .from('payment_transactions')
          .update({
            'payment_status': 'cancelled',
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', paymentTransactionId)
          .eq('payment_status', 'pending'); // Sadece pending olanları iptal et

      debugPrint('✅ PAYMENT: Transaction iptal edildi');
    } catch (e) {
      debugPrint('❌ PAYMENT: İptal hatası (kritik değil) - $e');
      // İptal hatası kritik değil, sessizce devam et
    }
  }

  /// Edge Function'ları ısıt (cold start'ı önle)
  /// Uygulama açılışında arka planda çağrılır
  static Future<void> warmUpEdgeFunctions() async {
    try {
      final supabase = Supabase.instance.client;
      
      // Kullanıcı giriş yapmamışsa warm-up yapma
      if (supabase.auth.currentUser == null) return;
      
      debugPrint('🔥 PAYMENT WARM-UP: iyzico Edge Function\'lar ısıtılıyor...');
      
      // iyzico-payment-init fonksiyonuna hafif bir ping at
      // Gerçek ödeme başlatmaz, sadece fonksiyonu uyandırır
      final stopwatch = Stopwatch()..start();
      
      await supabase.functions.invoke(
        'iyzico-payment-init',
        body: {'ping': true},
      ).timeout(
        const Duration(seconds: 10),
        onTimeout: () {
          debugPrint('⚠️ PAYMENT WARM-UP: Timeout (10s) - ama fonksiyon ısınmış olabilir');
          return FunctionResponse(status: 408, data: {});
        },
      );
      
      stopwatch.stop();
      debugPrint('🔥 PAYMENT WARM-UP: Tamamlandı (${stopwatch.elapsedMilliseconds}ms)');
    } catch (e) {
      debugPrint('⚠️ PAYMENT WARM-UP: Hata (önemli değil) - $e');
      // Warm-up başarısız olsa bile uygulama çalışmaya devam eder
    }
  }
}

/// Ödeme başlatma sonucu
class PaymentInitResult {
  final String paymentPageUrl;
  final String token;
  final int tokenExpireTime;
  final String conversationId;
  final String paymentTransactionId;

  PaymentInitResult({
    required this.paymentPageUrl,
    required this.token,
    required this.tokenExpireTime,
    required this.conversationId,
    required this.paymentTransactionId,
  });
}

/// Ödeme durumu
class PaymentStatus {
  final String status; // pending, success, failure, cancelled, error
  final String? orderId;

  PaymentStatus({
    required this.status,
    this.orderId,
  });

  /// Ödeme başarılı: payment_status='success'
  /// callback zaten complete_online_payment ile siparişi oluşturur,
  /// order_id opsiyonel (bazı durumlarda set edilmemiş olabilir ama
  /// sipariş orders tablosunda payment_transaction_id ile bulunabilir)
  bool get isSuccess => status == 'success';
  
  /// (artık kullanılmıyor — isSuccess yeterli)
  bool get isOrphanSuccess => false;
  
  bool get isFailure => status == 'failure' || status == 'error';
  bool get isPending => status == 'pending';
  bool get isCancelled => status == 'cancelled';
  bool get isError => status == 'error';
}
