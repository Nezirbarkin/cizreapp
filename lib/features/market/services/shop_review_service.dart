import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/shop_review_model.dart';

/// Bekleyen değerlendirme modeli
class PendingReview {
  final String orderId;
  final String shopId;
  final String shopName;
  final String? shopLogo;
  final DateTime orderDate;
  final DateTime deliveredAt;
  final String? productId;
  final String? productName;

  PendingReview({
    required this.orderId,
    required this.shopId,
    required this.shopName,
    this.shopLogo,
    required this.orderDate,
    required this.deliveredAt,
    this.productId,
    this.productName,
  });

  factory PendingReview.fromJson(Map<String, dynamic> json) {
    return PendingReview(
      orderId: json['order_id'] as String,
      shopId: json['shop_id'] as String,
      shopName: json['shop_name'] as String,
      shopLogo: json['shop_logo'] as String?,
      orderDate: DateTime.parse(json['order_date'] as String),
      deliveredAt: DateTime.parse(json['delivered_at'] as String),
      productId: json['product_id'] as String?,
      productName: json['product_name'] as String?,
    );
  }
}

class ShopReviewService {
  final _supabase = Supabase.instance.client;

  /// Dükkan için tüm yorumları getir (user bilgisi ile birlikte)
  Future<List<ShopReview>> getShopReviews(String shopId) async {
    try {
      debugPrint('📝 Dükkan yorumları yükleniyor: $shopId');
      
      final response = await _supabase
          .from('shop_reviews')
          .select('''
            id,
            shop_id,
            user_id,
            rating,
            comment,
            created_at,
            updated_at,
            seller_reply,
            seller_replied_at,
            order_id,
            profiles(full_name, avatar_url)
          ''')
          .eq('shop_id', shopId)
          .order('created_at', ascending: false);

      debugPrint('✅ ${response.length} yorum bulundu');
      
      return List<ShopReview>.from(response.map((review) {
        // Profil bilgisini flatten et
        final profile = review['profiles'] as Map<String, dynamic>?;
        return ShopReview.fromJson({
          ...review,
          'user_name': profile?['full_name'],
          'user_avatar': profile?['avatar_url'],
        });
      }));
    } catch (e) {
      debugPrint('❌ Yorumlar yüklenirken hata: $e');
      rethrow;
    }
  }

  /// Kullanıcının belirli bir dükkan için yaptığı yorumu getir
  Future<ShopReview?> getUserReview(String shopId, String userId) async {
    try {
      final response = await _supabase
          .from('shop_reviews')
          .select('''
            id,
            shop_id,
            user_id,
            rating,
            comment,
            created_at,
            updated_at,
            seller_reply,
            seller_replied_at,
            order_id
          ''')
          .eq('shop_id', shopId)
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;
      
      return ShopReview.fromJson(response);
    } catch (e) {
      debugPrint('❌ Kullanıcı yorumu getirilirken hata: $e');
      return null;
    }
  }

  /// Kullanıcının bu dükkandan tamamlanmış siparişi var mı kontrol et
  Future<bool> hasCompletedOrder(String shopId, String userId) async {
    try {
      debugPrint('🔍 Tamamlanmış sipariş kontrolü: shopId=$shopId, userId=$userId');
      
      final response = await _supabase
          .from('orders')
          .select('id')
          .eq('shop_id', shopId)
          .eq('user_id', userId)
          .eq('status', 'delivered')
          .limit(1)
          .maybeSingle();

      final hasOrder = response != null;
      debugPrint(hasOrder ? '✅ Tamamlanmış sipariş bulundu' : '❌ Tamamlanmış sipariş yok');
      
      return hasOrder;
    } catch (e) {
      debugPrint('❌ Sipariş kontrolü sırasında hata: $e');
      return false;
    }
  }

  /// Yeni yorum oluştur
  Future<ShopReview> addReview({
    required String shopId,
    required String userId,
    required int rating,
    String? comment,
    String? orderId,
  }) async {
    try {
      debugPrint('📝 Yorum oluşturuluyor: rating=$rating, shopId=$shopId');
      
      if (rating < 1 || rating > 5) {
        throw Exception('Puan 1 ile 5 arasında olmalı');
      }

      // Tamamlanmış sipariş kontrolü
      final hasOrder = await hasCompletedOrder(shopId, userId);
      if (!hasOrder) {
        throw Exception('Bu dükkana yorum yapabilmek için teslim edilmiş bir siparişiniz olmalı');
      }

      final response = await _supabase
          .from('shop_reviews')
          .insert({
            'shop_id': shopId,
            'user_id': userId,
            'rating': rating,
            'comment': comment?.trim(),
            'order_id': orderId,
            'created_at': DateTime.now().toIso8601String(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .select()
          .single();

      debugPrint('✅ Yorum oluşturuldu');
      return ShopReview.fromJson(response);
    } catch (e) {
      debugPrint('❌ Yorum oluşturulurken hata: $e');
      rethrow;
    }
  }

  /// Yorumu güncelle
  Future<ShopReview> updateReview({
    required String reviewId,
    required int rating,
    String? comment,
  }) async {
    try {
      debugPrint('✏️ Yorum güncelleniyor: reviewId=$reviewId, rating=$rating');
      
      if (rating < 1 || rating > 5) {
        throw Exception('Puan 1 ile 5 arasında olmalı');
      }

      final response = await _supabase
          .from('shop_reviews')
          .update({
            'rating': rating,
            'comment': comment?.trim(),
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', reviewId)
          .select()
          .single();

      debugPrint('✅ Yorum güncellendi');
      return ShopReview.fromJson(response);
    } catch (e) {
      debugPrint('❌ Yorum güncellenirken hata: $e');
      rethrow;
    }
  }

  /// Yorumu sil
  Future<void> deleteReview(String reviewId) async {
    try {
      debugPrint('🗑️ Yorum siliniyor: reviewId=$reviewId');
      
      await _supabase
          .from('shop_reviews')
          .delete()
          .eq('id', reviewId);

      debugPrint('✅ Yorum silindi');
    } catch (e) {
      debugPrint('❌ Yorum silinirken hata: $e');
      rethrow;
    }
  }

  /// Dükkan ortalama puanını hesapla
  Future<double> getAverageRating(String shopId) async {
    try {
      final response = await _supabase
          .from('shop_reviews')
          .select('rating')
          .eq('shop_id', shopId);

      if (response.isEmpty) return 0.0;

      final ratings = List<int>.from(response.map((r) => r['rating'] as int));
      final average = ratings.reduce((a, b) => a + b) / ratings.length;
      
      return double.parse(average.toStringAsFixed(1));
    } catch (e) {
      debugPrint('❌ Ortalama puan hesaplanırken hata: $e');
      return 0.0;
    }
  }

  /// Dükkan için toplam yorum sayısı
  Future<int> getTotalReviews(String shopId) async {
    try {
      final count = await _supabase
          .from('shop_reviews')
          .count()
          .eq('shop_id', shopId);

      return count;
    } catch (e) {
      debugPrint('❌ Toplam yorum sayısı getirilirken hata: $e');
      return 0;
    }
  }

  /// Puan dağılımını getir (1 yıldız kaç tane, 2 yıldız kaç tane vb.)
  Future<Map<int, int>> getRatingDistribution(String shopId) async {
    try {
      final response = await _supabase
          .from('shop_reviews')
          .select('rating')
          .eq('shop_id', shopId);

      final distribution = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
      
      for (var review in response) {
        final rating = review['rating'] as int;
        if (distribution.containsKey(rating)) {
          distribution[rating] = (distribution[rating] ?? 0) + 1;
        }
      }

      return distribution;
    } catch (e) {
      debugPrint('❌ Puan dağılımı getirilirken hata: $e');
      return {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};
    }
  }

  /// Satıcı cevabı ekle veya güncelle
  Future<ShopReview> addSellerReply({
    required String reviewId,
    required String reply,
  }) async {
    try {
      debugPrint('💬 Satıcı cevabı ekleniyor: reviewId=$reviewId');
      
      if (reply.trim().isEmpty) {
        throw Exception('Cevap boş olamaz');
      }

      final response = await _supabase
          .from('shop_reviews')
          .update({
            'seller_reply': reply.trim(),
            // seller_replied_at trigger tarafından otomatik doldurulur
          })
          .eq('id', reviewId)
          .select()
          .single();

      debugPrint('✅ Satıcı cevabı eklendi');
      return ShopReview.fromJson(response);
    } catch (e) {
      debugPrint('❌ Satıcı cevabı eklenirken hata: $e');
      rethrow;
    }
  }

  /// Satıcı cevabını sil
  Future<ShopReview> deleteSellerReply(String reviewId) async {
    try {
      debugPrint('🗑️ Satıcı cevabı siliniyor: reviewId=$reviewId');
      
      final response = await _supabase
          .from('shop_reviews')
          .update({
            'seller_reply': null,
            'seller_replied_at': null,
          })
          .eq('id', reviewId)
          .select()
          .single();

      debugPrint('✅ Satıcı cevabı silindi');
      return ShopReview.fromJson(response);
    } catch (e) {
      debugPrint('❌ Satıcı cevabı silinirken hata: $e');
      rethrow;
    }
  }

  /// Kullanıcının bekleyen değerlendirmelerini getir
  Future<List<PendingReview>> getPendingReviews(String userId) async {
    try {
      debugPrint('⏳ Bekleyen değerlendirmeler getiriliyor: userId=$userId');
      
      final response = await _supabase
          .rpc('get_pending_reviews', params: {'p_user_id': userId});

      debugPrint('✅ ${response.length} bekleyen değerlendirme bulundu');
      debugPrint('📋 Ham veri: $response');
      
      final reviews = List<PendingReview>.from(
        response.map((item) {
          debugPrint('🔍 Pending review item: $item');
          debugPrint('🏪 Shop name: ${item['shop_name']}');
          return PendingReview.fromJson(item);
        })
      );
      
      debugPrint('✅ Parse edilmiş reviews: ${reviews.map((r) => r.shopName).toList()}');
      return reviews;
    } catch (e) {
      debugPrint('❌ Bekleyen değerlendirmeler getirilirken hata: $e');
      return [];
    }
  }

  /// Satıcının mağaza yorumlarını getir (satıcı paneli için)
  Future<List<ShopReview>> getSellerShopReviews(String shopId) async {
    try {
      debugPrint('🏪 Satıcı mağaza yorumları yükleniyor: $shopId');
      
      final response = await _supabase
          .from('shop_reviews')
          .select('''
            id,
            shop_id,
            user_id,
            rating,
            comment,
            created_at,
            updated_at,
            seller_reply,
            seller_replied_at,
            order_id,
            profiles(full_name, avatar_url)
          ''')
          .eq('shop_id', shopId)
          .order('created_at', ascending: false);

      debugPrint('✅ ${response.length} yorum bulundu');
      
      return List<ShopReview>.from(response.map((review) {
        final profile = review['profiles'] as Map<String, dynamic>?;
        return ShopReview.fromJson({
          ...review,
          'user_name': profile?['full_name'],
          'user_avatar': profile?['avatar_url'],
        });
      }));
    } catch (e) {
      debugPrint('❌ Satıcı yorumları yüklenirken hata: $e');
      rethrow;
    }
  }

  /// Sipariş için değerlendirme yapılabilir mi kontrol et
  Future<bool> canReviewOrder({
    required String userId,
    required String shopId,
    required String orderId,
  }) async {
    try {
      final response = await _supabase
          .rpc('can_review_order', params: {
            'p_user_id': userId,
            'p_shop_id': shopId,
            'p_order_id': orderId,
          });

      return response as bool? ?? false;
    } catch (e) {
      debugPrint('❌ Sipariş değerlendirme kontrolü hatası: $e');
      return false;
    }
  }
}
