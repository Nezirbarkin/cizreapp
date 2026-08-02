// product_detail_checkout_button.dart
// Tarih: 2026-08-02
//
// Ürün detay ekranında "Sepete Ekle" yerine "Hızlı Satın Al"
// akışı. Bu buton:
//
// 1) Kullanıcının seçtiği adres + payment_method + idempotency_key
//    ile private.prepare_checkout_session çağırır.
// 2) Gelen session.server_total'ı gösterir.
// 3) Onay → commit_cod / init_online / commit_balance.
//
// Client ASLA fiyat hesaplamaz; sadece RPC sonucu gelen snapshot
// kullanılır. CartService.addItem (görsel için) çağrısı TAMAMEN
// kaldırıldı.

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/checkout_session_model.dart';
import '../services/checkout_service.dart';

class ProductDetailCheckoutButton extends StatefulWidget {
  final String productId;
  final int quantity;
  final String? variantId;
  final String? variant;
  final String? flashSaleId;
  final VoidCallback? onCompleted;

  const ProductDetailCheckoutButton({
    super.key,
    required this.productId,
    this.quantity = 1,
    this.variantId,
    this.variant,
    this.flashSaleId,
    this.onCompleted,
  });

  @override
  State<ProductDetailCheckoutButton> createState() =>
      _ProductDetailCheckoutButtonState();
}

class _ProductDetailCheckoutButtonState
    extends State<ProductDetailCheckoutButton> {
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: _loading ? null : _onPressed,
        icon: _loading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.shopping_bag),
        label: const Text('Hızlı Satın Al'),
      ),
    );
  }

  Future<void> _onPressed() async {
    setState(() => _loading = true);
    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;
      if (user == null) {
        _snack('Önce giriş yapın.');
        return;
      }
      // Kullanıcının varsayılan adresini al
      final addr = await supabase
          .from('addresses')
          .select('id')
          .eq('user_id', user.id)
          .eq('is_default', true)
          .maybeSingle();
      if (addr == null) {
        _snack('Önce bir adres ekleyin.');
        return;
      }
      final idem = CheckoutService.generateIdempotencyKey(prefix: 'detail');
      final session = await CheckoutService(supabase).prepareCheckout(
        CheckoutSessionRequest(
          items: [
            CheckoutItemRequest(
              productId: widget.productId,
              quantity: widget.quantity,
              variant: widget.variant,
              variantId: widget.variantId,
              flashSaleId: widget.flashSaleId,
            )
          ],
          addressId: addr['id'] as String,
          paymentMethod: 'cod',
          idempotencyKey: idem,
        ),
      );

      if (!mounted) return;
      _showSummary(session);
    } catch (e) {
      _snack('Hata: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showSummary(CheckoutSession session) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Sipariş Özeti (sunucu onaylı)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            const SizedBox(height: 12),
            Text('Ara Toplam: ${session.serverSubtotal.toStringAsFixed(2)} TL'),
            Text('Kargo: ${session.serverDeliveryFee.toStringAsFixed(2)} TL'),
            if (session.serverCouponDiscount > 0)
              Text('İndirim: ${session.serverCouponDiscount.toStringAsFixed(2)} TL'),
            const Divider(),
            Text('Toplam: ${session.serverTotal.toStringAsFixed(2)} TL',
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 18)),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  await CheckoutService(Supabase.instance.client)
                      .commitCodOrder(session.id);
                  _snack('Sipariş oluşturuldu');
                  widget.onCompleted?.call();
                } catch (e) {
                  _snack('Sipariş oluşturulamadı: $e');
                }
              },
              child: const Text('Onayla ve Sipariş Ver'),
            ),
          ],
        ),
      ),
    );
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(msg)));
  }
}
