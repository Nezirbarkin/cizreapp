// ignore_for_file: unnecessary_underscores, use_build_context_synchronously

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/shop_review_service.dart';
import '../../shop/services/order_service.dart';

/// Bekleyen değerlendirme popup widget'ı
/// Kullanıcı uygulamaya giriş yaptığında teslim edilen siparişler için
/// değerlendirme yapması hatırlatılır
/// Hem ürün hem satıcı değerlendirmesi içerir
class PendingReviewDialog extends StatefulWidget {
  final PendingReview pendingReview;
  final Future<void> Function()? onReviewSubmitted;
  final Future<void> Function()? onSkipped;

  const PendingReviewDialog({
    super.key,
    required this.pendingReview,
    this.onReviewSubmitted,
    this.onSkipped,
  });

  @override
  State<PendingReviewDialog> createState() => _PendingReviewDialogState();
}

class _PendingReviewDialogState extends State<PendingReviewDialog> {
  final _reviewService = ShopReviewService();
  final _shopCommentController = TextEditingController();
  final _productCommentController = TextEditingController();
  int _shopRating = 0;
  int _productRating = 0;
  bool _isSubmitting = false;

  @override
  void dispose() {
    _shopCommentController.dispose();
    _productCommentController.dispose();
    super.dispose();
  }

  Future<void> _submitReview() async {
    if (_shopRating == 0 && _productRating == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Lütfen en az bir puan seçin')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) throw Exception('Kullanıcı bulunamadı');

      // Satıcı değerlendirmesi
      if (_shopRating > 0) {
        await _reviewService.addReview(
          shopId: widget.pendingReview.shopId,
          userId: userId,
          rating: _shopRating,
          comment: _shopCommentController.text.trim().isEmpty
              ? null
              : _shopCommentController.text.trim(),
          orderId: widget.pendingReview.orderId,
          digitalOrderId: widget.pendingReview.digitalOrderId,
        );
      }

      // Ürün değerlendirmesi (product_reviews tablosuna)
      if (_productRating > 0 && widget.pendingReview.productId != null) {
        await Supabase.instance.client.from('product_reviews').insert({
          'product_id': widget.pendingReview.productId,
          'user_id': userId,
          'rating': _productRating,
          'comment': _productCommentController.text.trim().isEmpty
              ? null
              : _productCommentController.text.trim(),
          'order_id': widget.pendingReview.orderId,
          'digital_order_id': widget.pendingReview.digitalOrderId,
        });
      }

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Değerlendirmeniz için teşekkürler!'),
            backgroundColor: Colors.green,
          ),
        );
        widget.onReviewSubmitted?.call();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSubmitting = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Row(
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.orange.shade100,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: widget.pendingReview.shopLogo != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(12),
                            child: CachedNetworkImage(
                              imageUrl: widget.pendingReview.shopLogo!,
                              fit: BoxFit.cover,
                              errorWidget: (_, __, ___) => Icon(
                                Icons.store,
                                color: Colors.orange.shade700,
                                size: 28,
                              ),
                            ),
                          )
                        : Icon(
                            Icons.store,
                            color: Colors.orange.shade700,
                            size: 28,
                          ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Sipariş Teslim Edildi!',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          widget.pendingReview.shopName,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    onPressed: () async {
                      debugPrint('❌ Çarpı butonuna basıldı');
                      if (widget.onSkipped != null) {
                        debugPrint('🔄 onSkipped callback çağrılıyor...');
                        await widget.onSkipped!();
                        debugPrint('✅ onSkipped callback tamamlandı');
                      } else {
                        debugPrint('⚠️ onSkipped callback null!');
                      }
                      if (mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    icon: const Icon(Icons.close),
                    color: Colors.grey,
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Ürün Değerlendirmesi
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blue.shade100),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.shopping_bag, color: Colors.blue, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.pendingReview.productName ?? 'Ürün',
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        return GestureDetector(
                          onTap: () => setState(() => _productRating = index + 1),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                              index < _productRating ? Icons.star : Icons.star_border,
                              size: 36,
                              color: Colors.amber,
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getRatingText(_productRating),
                      style: TextStyle(
                        color: _productRating > 0 ? Colors.amber.shade700 : Colors.grey,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Ürün yorumu
              TextField(
                controller: _productCommentController,
                decoration: InputDecoration(
                  hintText: 'Ürün hakkında yorumunuz (opsiyonel)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),

              // Satıcı Değerlendirmesi
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange.shade100),
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Icon(Icons.store, color: Colors.orange.shade700, size: 20),
                        const SizedBox(width: 8),
                        const Text(
                          'Satıcı/Dükkan',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(5, (index) {
                        return GestureDetector(
                          onTap: () => setState(() => _shopRating = index + 1),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Icon(
                              index < _shopRating ? Icons.star : Icons.star_border,
                              size: 36,
                              color: Colors.amber,
                            ),
                          ),
                        );
                      }),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getRatingText(_shopRating),
                      style: TextStyle(
                        color: _shopRating > 0 ? Colors.amber.shade700 : Colors.grey,
                        fontWeight: FontWeight.w500,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Satıcı yorumu
              TextField(
                controller: _shopCommentController,
                decoration: InputDecoration(
                  hintText: 'Satıcı hakkında yorumunuz (opsiyonel)',
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  contentPadding: const EdgeInsets.all(12),
                ),
                maxLines: 2,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 16),

              // Actions
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSubmitting
                          ? null
                          : () async {
                              debugPrint('⏩ Daha Sonra butonuna basıldı');
                              if (widget.onSkipped != null) {
                                debugPrint('🔄 onSkipped callback çağrılıyor...');
                                await widget.onSkipped!();
                                debugPrint('✅ onSkipped callback tamamlandı');
                              } else {
                                debugPrint('⚠️ onSkipped callback null!');
                              }
                              if (mounted) {
                                Navigator.of(context).pop();
                              }
                            },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('Daha Sonra'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitReview,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange.shade700,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Değerlendir',
                              style: TextStyle(fontWeight: FontWeight.bold),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getRatingText(int rating) {
    switch (rating) {
      case 1:
        return 'Çok Kötü 😞';
      case 2:
        return 'Kötü 😕';
      case 3:
        return 'Orta 😐';
      case 4:
        return 'İyi 🙂';
      case 5:
        return 'Harika! 🤩';
      default:
        return 'Puan seçin';
    }
  }
}

/// Bekleyen değerlendirmeleri kontrol eden ve popup gösteren helper class
class PendingReviewChecker {
  static final _reviewService = ShopReviewService();
  static bool _hasCheckedThisSession = false;

  /// Push bildiriminden gelen sipariş ID'si (bildirim tıklandığında ayarlanır)
  static String? _pendingOrderIdFromPush;
  
  /// Push bildiriminden gelen sipariş ID'sini ayarla
  static void setPendingOrderIdFromPush(String? orderId) {
    _pendingOrderIdFromPush = orderId;
    debugPrint('🔔 Push bildiriminden sipariş ID ayarlandı: $orderId');
  }
  
  /// Push bildiriminden gelen sipariş ID'sini al ve temizle
  static String? takePendingOrderIdFromPush() {
    final orderId = _pendingOrderIdFromPush;
    _pendingOrderIdFromPush = null;
    return orderId;
  }

  /// Siparişin hatırlatıcısını veritabanında kalıcı olarak atlanmış işaretle
  /// (cihaz/uygulama değişse bile tekrar sorulmaz)
  static Future<void> _markOrderAsSkipped(PendingReview review) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;
      await Supabase.instance.client.rpc('dismiss_review_reminder', params: {
        'p_order_id': review.orderId,
        'p_digital_order_id': review.digitalOrderId,
        'p_user_id': userId,
      });
      debugPrint('✅ Sipariş hatırlatıcısı DB\'de atlandı olarak işaretlendi: ${review.trackingId}');
    } catch (e) {
      debugPrint('❌ Atlanan sipariş kaydedilemedi: $e');
    }
  }

  /// Bekleyen değerlendirmeleri kontrol et ve varsa popup göster
  /// Push bildiriminden gelen sipariş ID varsa öncelikli olarak değerlendirme göster
  static Future<void> checkAndShowPendingReviews(BuildContext context) async {
    // Oturum başına sadece bir kez kontrol et (ama push bildirimi öncelikli)
    final bool isFirstCheck = !_hasCheckedThisSession;
    _hasCheckedThisSession = true;

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // Önce push bildiriminden gelen sipariş ID kontrol et
      final pushOrderId = takePendingOrderIdFromPush();
      if (pushOrderId != null) {
        debugPrint('🔔 Push bildiriminden sipariş değerlendirmesi gösterilecek: $pushOrderId');
        // Push bildirimi varsa direkt o siparişin değerlendirmesini göster
        await _showReviewForOrderId(context, pushOrderId);
        return;
      }

      // Normal akış: bekleyen değerlendirmeleri kontrol et
      if (!isFirstCheck) return; // İlk kontrol değilse atla

      final pendingReviews = await _reviewService.getPendingReviews(userId);

      if (pendingReviews.isEmpty) return; // Atlanmış siparişler zaten DB tarafında filtreleniyor

      // İlk bekleyen değerlendirmeyi göster
      if (context.mounted) {
        // Biraz bekle, uygulama tam yüklensin
        await Future.delayed(const Duration(seconds: 1));

        if (context.mounted) {
          _showPendingReviewDialog(context, pendingReviews.first);
        }
      }
    } catch (e) {
      debugPrint('❌ Bekleyen değerlendirmeler kontrol edilirken hata: $e');
    }
  }

  /// Push bildiriminden gelen sipariş ID'si için değerlendirme dialog'u göster
  static Future<void> _showReviewForOrderId(BuildContext context, String orderId) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // Sipariş detaylarını al
      final orderService = OrderService();
      final order = await orderService.getOrderById(orderId);
      
      if (order == null) {
        debugPrint('❌ Sipariş bulunamadı: $orderId');
        return;
      }

      // Atlanmış mı kontrol et (atlanmışsa gösterme)
      final orderRow = await Supabase.instance.client
          .from('orders')
          .select('review_reminder_dismissed')
          .eq('id', orderId)
          .maybeSingle();
      if (orderRow?['review_reminder_dismissed'] == true) {
        debugPrint('⚠️ Sipariş atlanmış, değerlendirme gösterilmiyor: $orderId');
        return;
      }

      // PendingReview modeli oluştur
      final pendingReview = PendingReview(
        orderId: order.id,
        shopId: order.shopId,
        shopName: order.shopName ?? 'Dükkan',
        shopLogo: null,
        orderDate: order.createdAt,
        deliveredAt: order.deliveredAt ?? DateTime.now(),
        productId: order.items.isNotEmpty ? order.items.first.productId : null,
        productName: order.items.isNotEmpty ? order.items.first.productName : null,
      );

      if (context.mounted) {
        // Biraz bekle, uygulama tam yüklensin
        await Future.delayed(const Duration(milliseconds: 500));
        
        if (context.mounted) {
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (dialogContext) => PendingReviewDialog(
              pendingReview: pendingReview,
              onReviewSubmitted: () async {},
              onSkipped: () async {
                await _markOrderAsSkipped(pendingReview);
              },
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Push sipariş değerlendirmesi gösterilirken hata: $e');
    }
  }

  static void _showPendingReviewDialog(
    BuildContext context,
    PendingReview pendingReview,
  ) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => PendingReviewDialog(
        pendingReview: pendingReview,
        onReviewSubmitted: () async {},
        onSkipped: () async {
          // Atlandı olarak DB'de işaretle - bu sayede tekrar gösterilmeyecek
          await _markOrderAsSkipped(pendingReview);
          debugPrint('📝 Sipariş değerlendirmesi atlandı: ${pendingReview.trackingId}');
        },
      ),
    );
  }

  /// Oturum kontrolünü sıfırla (test için)
  static void resetSessionCheck() {
    _hasCheckedThisSession = false;
  }
}
