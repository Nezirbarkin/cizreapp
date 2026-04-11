// ignore_for_file: unnecessary_underscores, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/shop_review_service.dart';

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
        });
      }

      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
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
                            child: Image.network(
                              widget.pendingReview.shopLogo!,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
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
  static const String _skippedOrdersKey = 'skipped_review_orders';

  /// Atlanan siparişi kaydet
  static Future<void> _markOrderAsSkipped(String orderId) async {
    try {
      debugPrint('🔄 Sipariş atlanıyor: $orderId');
      final prefs = await SharedPreferences.getInstance();
      
      // Önce mevcut listeyi oku
      await prefs.reload(); // Cache'i yenile
      final skippedOrders = prefs.getStringList(_skippedOrdersKey) ?? [];
      debugPrint('📋 Mevcut atlanan siparişler: $skippedOrders');
      
      if (!skippedOrders.contains(orderId)) {
        skippedOrders.add(orderId);
        final saved = await prefs.setStringList(_skippedOrdersKey, skippedOrders);
        debugPrint('✅ Sipariş atlanan listesine eklendi: $orderId (Başarılı: $saved)');
        debugPrint('📋 Güncel liste: $skippedOrders');
        
        // Verilerin disk'e yazıldığından emin ol
        // Android'de SharedPreferences otomatik persist eder,
        // ancak bazen gecikme olabilir
      } else {
        debugPrint('⚠️ Sipariş zaten atlanan listede: $orderId');
      }
    } catch (e) {
      debugPrint('❌ Atlanan sipariş kaydedilemedi: $e');
    }
  }

  /// Siparişin daha önce atlanıp atlanmadığını kontrol et
  static Future<bool> _isOrderSkipped(String orderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload(); // Cache'i yenile - disk'ten oku
      final skippedOrders = prefs.getStringList(_skippedOrdersKey) ?? [];
      final isSkipped = skippedOrders.contains(orderId);
      debugPrint('🔍 Sipariş kontrolü: $orderId -> ${isSkipped ? "ATLANDI" : "YENİ"}');
      debugPrint('📋 Atlanan liste: $skippedOrders');
      return isSkipped;
    } catch (e) {
      debugPrint('❌ Atlanan sipariş kontrolü hatası: $e');
      return false;
    }
  }

  /// Atlanan siparişleri temizle (değerlendirme yapıldıktan sonra)
  static Future<void> _removeSkippedOrder(String orderId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final skippedOrders = prefs.getStringList(_skippedOrdersKey) ?? [];
      if (skippedOrders.contains(orderId)) {
        skippedOrders.remove(orderId);
        await prefs.setStringList(_skippedOrdersKey, skippedOrders);
        debugPrint('✅ Sipariş atlanan listesinden çıkarıldı: $orderId');
      }
    } catch (e) {
      debugPrint('❌ Atlanan sipariş silinemedi: $e');
    }
  }

  /// Bekleyen değerlendirmeleri kontrol et ve varsa popup göster
  static Future<void> checkAndShowPendingReviews(BuildContext context) async {
    // Oturum başına sadece bir kez kontrol et
    if (_hasCheckedThisSession) return;
    _hasCheckedThisSession = true;

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final pendingReviews = await _reviewService.getPendingReviews(userId);
      
      if (pendingReviews.isEmpty) return;

      // Atlanmamış ilk siparişi bul
      PendingReview? firstNonSkipped;
      for (var review in pendingReviews) {
        final isSkipped = await _isOrderSkipped(review.orderId);
        if (!isSkipped) {
          firstNonSkipped = review;
          break;
        }
      }

      if (firstNonSkipped == null) return; // Hepsi atlanmış

      // İlk atlanmamış değerlendirmeyi göster
      if (context.mounted) {
        // Biraz bekle, uygulama tam yüklensin
        await Future.delayed(const Duration(seconds: 1));
        
        if (context.mounted) {
          _showPendingReviewDialog(context, firstNonSkipped);
        }
      }
    } catch (e) {
      debugPrint('❌ Bekleyen değerlendirmeler kontrol edilirken hata: $e');
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
        onReviewSubmitted: () async {
          // Değerlendirme yapıldı, atlanan listesinden çıkar
          await _removeSkippedOrder(pendingReview.orderId);
        },
        onSkipped: () async {
          // Atlandı olarak işaretle - bu sayede tekrar gösterilmeyecek
          await _markOrderAsSkipped(pendingReview.orderId);
          debugPrint('📝 Sipariş değerlendirmesi atlandı: ${pendingReview.orderId}');
        },
      ),
    );
  }

  /// Oturum kontrolünü sıfırla (test için)
  static void resetSessionCheck() {
    _hasCheckedThisSession = false;
  }

  /// Tüm atlanan siparişleri temizle (test/debug için)
  static Future<void> clearSkippedOrders() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_skippedOrdersKey);
      debugPrint('✅ Tüm atlanan siparişler temizlendi');
    } catch (e) {
      debugPrint('❌ Atlanan siparişler temizlenemedi: $e');
    }
  }
}
