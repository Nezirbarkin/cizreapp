import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/product_review_model.dart';

class ProductReviewService {
  final _supabase = Supabase.instance.client;

  /// Ürün için tüm yorumları getir (user bilgisi ile birlikte)
  Future<List<ProductReview>> getProductReviews(String productId, {int limit = 50, int offset = 0}) async {
    try {
      debugPrint('📝 Ürün yorumları yükleniyor: $productId');

      final response = await _supabase
          .from('product_reviews')
          .select('''
            id,
            product_id,
            user_id,
            rating,
            comment,
            created_at,
            updated_at,
            seller_reply,
            seller_replied_at,
            order_id,
            is_approved,
            helpful_count,
            profiles(full_name, avatar_url)
          ''')
          .eq('product_id', productId)
          .eq('is_approved', true)
          .order('created_at', ascending: false)
          .range(offset, offset + limit - 1);

      debugPrint('✅ ${response.length} ürün yorumu bulundu');

      return List<ProductReview>.from(response.map((review) {
        final profile = review['profiles'] as Map<String, dynamic>?;
        return ProductReview.fromJson({
          ...review,
          'user_name': profile?['full_name'],
          'user_avatar': profile?['avatar_url'],
        });
      }));
    } catch (e) {
      debugPrint('❌ Ürün yorumları yüklenirken hata: $e');
      rethrow;
    }
  }

  /// Kullanıcının belirli bir ürün için yaptığı yorumu getir
  Future<ProductReview?> getUserProductReview(String productId, String userId) async {
    try {
      final response = await _supabase
          .from('product_reviews')
          .select('''
            id,
            product_id,
            user_id,
            rating,
            comment,
            created_at,
            updated_at,
            seller_reply,
            seller_replied_at,
            order_id,
            is_approved,
            helpful_count
          ''')
          .eq('product_id', productId)
          .eq('user_id', userId)
          .order('created_at', ascending: false)
          .limit(1)
          .maybeSingle();

      if (response == null) return null;

      return ProductReview.fromJson(response);
    } catch (e) {
      debugPrint('❌ Kullanıcı ürün yorumu getirilirken hata: $e');
      return null;
    }
  }

  /// Kullanıcının bu ürünü satın almış mı kontrol et
  Future<bool> hasPurchasedProduct(String productId, String userId) async {
    try {
      debugPrint('🔍 Ürün satın alma kontrolü: productId=$productId, userId=$userId');

      final response = await _supabase
          .from('order_items')
          .select('id, orders!inner(user_id, status)')
          .eq('product_id', productId)
          .eq('orders.user_id', userId)
          .eq('orders.status', 'delivered')
          .limit(1)
          .maybeSingle();

      final hasPurchased = response != null;
      debugPrint(hasPurchased ? '✅ Ürün satın alınmış' : '❌ Ürün satın alınmamış');

      return hasPurchased;
    } catch (e) {
      debugPrint('❌ Ürün satın alma kontrolü sırasında hata: $e');
      return false;
    }
  }

  /// Yeni ürün yorumu oluştur
  Future<ProductReview> addReview({
    required String productId,
    required String userId,
    required int rating,
    String? comment,
    String? orderId,
  }) async {
    try {
      debugPrint('📝 Ürün yorumu oluşturuluyor: rating=$rating, productId=$productId');

      if (rating < 1 || rating > 5) {
        throw Exception('Puan 1 ile 5 arasında olmalı');
      }

      // Satın alma kontrolü
      final hasPurchased = await hasPurchasedProduct(productId, userId);
      if (!hasPurchased) {
        throw Exception('Bu ürüne yorum yapabilmek için ürünü satın almış ve teslim almış olmanız gerekir');
      }

      // Daha önce yorum yapılmış mı kontrol et
      final existingReview = await getUserProductReview(productId, userId);
      if (existingReview != null) {
        throw Exception('Bu ürüne zaten yorum yapmışsınız. Yorumunuzu güncelleyebilirsiniz.');
      }

      final response = await _supabase
          .from('product_reviews')
          .insert({
            'product_id': productId,
            'user_id': userId,
            'rating': rating,
            'comment': comment?.trim(),
            'order_id': orderId,
            'is_approved': true,
            'created_at': DateTime.now().toUtc().toIso8601String(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .select()
          .single();

      // Ürün ortalama puanını güncelle
      await _updateProductRating(productId);

      debugPrint('✅ Ürün yorumu oluşturuldu');
      return ProductReview.fromJson(response);
    } catch (e) {
      debugPrint('❌ Ürün yorumu oluşturulurken hata: $e');
      rethrow;
    }
  }

  /// Yorumu güncelle
  Future<ProductReview> updateReview({
    required String reviewId,
    required int rating,
    String? comment,
  }) async {
    try {
      debugPrint('✏️ Ürün yorumu güncelleniyor: reviewId=$reviewId, rating=$rating');

      if (rating < 1 || rating > 5) {
        throw Exception('Puan 1 ile 5 arasında olmalı');
      }

      final response = await _supabase
          .from('product_reviews')
          .update({
            'rating': rating,
            'comment': comment?.trim(),
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', reviewId)
          .select()
          .single();

      final review = ProductReview.fromJson(response);

      // Ürün ortalama puanını güncelle
      await _updateProductRating(review.productId);

      debugPrint('✅ Ürün yorumu güncellendi');
      return review;
    } catch (e) {
      debugPrint('❌ Ürün yorumu güncellenirken hata: $e');
      rethrow;
    }
  }

  /// Yorumu sil
  Future<void> deleteReview(String reviewId, String productId) async {
    try {
      debugPrint('🗑️ Ürün yorumu siliniyor: reviewId=$reviewId');

      await _supabase
          .from('product_reviews')
          .delete()
          .eq('id', reviewId);

      // Ürün ortalama puanını güncelle
      await _updateProductRating(productId);

      debugPrint('✅ Ürün yorumu silindi');
    } catch (e) {
      debugPrint('❌ Ürün yorumu silinirken hata: $e');
      rethrow;
    }
  }

  /// Ürün ortalama puanını hesapla
  Future<Map<String, dynamic>> getProductRatingStats(String productId) async {
    try {
      final response = await _supabase
          .from('product_reviews')
          .select('rating')
          .eq('product_id', productId)
          .eq('is_approved', true);

      if (response.isEmpty) {
        return {'average': 0.0, 'count': 0, 'distribution': {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}};
      }

      final ratings = List<int>.from(response.map((r) => r['rating'] as int));
      final average = ratings.reduce((a, b) => a + b) / ratings.length;
      final distribution = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};

      for (var r in ratings) {
        if (distribution.containsKey(r)) {
          distribution[r] = (distribution[r] ?? 0) + 1;
        }
      }

      return {
        'average': double.parse(average.toStringAsFixed(1)),
        'count': ratings.length,
        'distribution': distribution,
      };
    } catch (e) {
      debugPrint('❌ Ürün puan istatistikleri hesaplanırken hata: $e');
      return {'average': 0.0, 'count': 0, 'distribution': {1: 0, 2: 0, 3: 0, 4: 0, 5: 0}};
    }
  }

  /// Ürün ortalama puanını veritabanında güncelle
  Future<void> _updateProductRating(String productId) async {
    try {
      final stats = await getProductRatingStats(productId);
      final average = stats['average'] as double;
      final count = stats['count'] as int;

      await _supabase
          .from('products')
          .update({
            'rating': average,
            'total_reviews': count,
          })
          .eq('id', productId);

      debugPrint('✅ Ürün puanı güncellendi: avg=$average, count=$count');
    } catch (e) {
      debugPrint('❌ Ürün puanı güncellenirken hata: $e');
    }
  }

  /// Satıcı cevabı ekle veya güncelle
  Future<ProductReview> addSellerReply({
    required String reviewId,
    required String reply,
  }) async {
    try {
      debugPrint('💬 Satıcı cevabı ekleniyor: reviewId=$reviewId');

      if (reply.trim().isEmpty) {
        throw Exception('Cevap boş olamaz');
      }

      final response = await _supabase
          .from('product_reviews')
          .update({
            'seller_reply': reply.trim(),
            'seller_replied_at': DateTime.now().toUtc().toIso8601String(),
          })
          .eq('id', reviewId)
          .select()
          .single();

      debugPrint('✅ Satıcı cevabı eklendi');
      return ProductReview.fromJson(response);
    } catch (e) {
      debugPrint('❌ Satıcı cevabı eklenirken hata: $e');
      rethrow;
    }
  }

  /// Satıcı cevabını sil
  Future<ProductReview> deleteSellerReply(String reviewId) async {
    try {
      debugPrint('🗑️ Satıcı cevabı siliniyor: reviewId=$reviewId');

      final response = await _supabase
          .from('product_reviews')
          .update({
            'seller_reply': null,
            'seller_replied_at': null,
          })
          .eq('id', reviewId)
          .select()
          .single();

      debugPrint('✅ Satıcı cevabı silindi');
      return ProductReview.fromJson(response);
    } catch (e) {
      debugPrint('❌ Satıcı cevabı silinirken hata: $e');
      rethrow;
    }
  }

  /// Faydalı olarak işaretle / geri al
  Future<void> toggleHelpful(String reviewId, String userId) async {
    try {
      // Kullanıcının bu yorumu zaten oylayıp oylamamadığını kontrol et
      final existing = await _supabase
          .from('product_review_helpful')
          .select('id')
          .eq('review_id', reviewId)
          .eq('user_id', userId)
          .maybeSingle();

      if (existing != null) {
        // Oyu kaldır
        await _supabase
            .from('product_review_helpful')
            .delete()
            .eq('review_id', reviewId)
            .eq('user_id', userId);
        debugPrint('✅ Faydalı oyu kaldırıldı');
      } else {
        // Oy ekle
        await _supabase
            .from('product_review_helpful')
            .insert({
              'review_id': reviewId,
              'user_id': userId,
              'created_at': DateTime.now().toUtc().toIso8601String(),
            });
        debugPrint('✅ Faydalı oyu eklendi');
      }

      // Faydalı sayısını güncelle
      await _updateHelpfulCount(reviewId);
    } catch (e) {
      debugPrint('❌ Faydalı oy işleminde hata: $e');
      rethrow;
    }
  }

  /// Faydalı sayısını güncelle
  Future<void> _updateHelpfulCount(String reviewId) async {
    try {
      final countResponse = await _supabase
          .from('product_review_helpful')
          .select('id')
          .eq('review_id', reviewId);

      final count = countResponse.length;

      await _supabase
          .from('product_reviews')
          .update({'helpful_count': count})
          .eq('id', reviewId);
    } catch (e) {
      debugPrint('❌ Faydalı sayısı güncellenirken hata: $e');
    }
  }

  /// Satıcının ürün yorumlarını getir (satıcı paneli için)
  Future<List<ProductReview>> getSellerProductReviews(String shopId) async {
    try {
      debugPrint('🏪 Satıcı ürün yorumları yükleniyor: shopId=$shopId');

      // Önce bu dükkana ait ürün ID'lerini al
      final products = await _supabase
          .from('products')
          .select('id')
          .eq('shop_id', shopId);

      if (products.isEmpty) return [];

      final productIds = products.map((p) => p['id'] as String).toList();

      final response = await _supabase
          .from('product_reviews')
          .select('''
            id,
            product_id,
            user_id,
            rating,
            comment,
            created_at,
            updated_at,
            seller_reply,
            seller_replied_at,
            order_id,
            is_approved,
            helpful_count,
            profiles(full_name, avatar_url),
            products(name, image_url)
          ''')
          .inFilter('product_id', productIds)
          .order('created_at', ascending: false);

      debugPrint('✅ ${response.length} ürün yorumu bulundu');

      return List<ProductReview>.from(response.map((review) {
        final profile = review['profiles'] as Map<String, dynamic>?;
        return ProductReview.fromJson({
          ...review,
          'user_name': profile?['full_name'],
          'user_avatar': profile?['avatar_url'],
        });
      }));
    } catch (e) {
      debugPrint('❌ Satıcı ürün yorumları yüklenirken hata: $e');
      rethrow;
    }
  }
}
