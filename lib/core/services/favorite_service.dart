import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/favorite_models.dart';

/// Favori servisi - Hem ürün hem gönderi favorilerini yönetir
class FavoriteService {
  final SupabaseClient _client = Supabase.instance.client;

  // ==================== ÜRÜN FAVORİLERİ ====================

  /// Kullanıcının tüm ürün favorilerini getirir (ürün bilgileriyle birlikte)
  Future<List<ProductFavorite>> getProductFavorites() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Kullanıcı giriş yapmamış');

    final response = await _client
        .from('product_favorites')
        .select('*, products(*)')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => ProductFavorite.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Ürünün favori olup olmadığını kontrol eder
  Future<bool> isProductFavorited(String productId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    final response = await _client
        .from('product_favorites')
        .select()
        .eq('user_id', userId)
        .eq('product_id', productId)
        .maybeSingle();

    return response != null;
  }

  /// Ürünü favorilere ekler veya çıkarır (toggle)
  /// Returns true if added, false if removed
  Future<bool> toggleProductFavorite(String productId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Kullanıcı giriş yapmamış');

    // Önce mevcut durumunu kontrol et
    final isFavorited = await isProductFavorited(productId);

    if (isFavorited) {
      // Favoriden çıkar
      await _client
          .from('product_favorites')
          .delete()
          .eq('user_id', userId)
          .eq('product_id', productId);
      return false;
    } else {
      // Favoriye ekle
      await _client.from('product_favorites').insert({
        'user_id': userId,
        'product_id': productId,
      });
      return true;
    }
  }

  /// Ürünü favorilerden kaldırır
  Future<void> removeProductFavorite(String productId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Kullanıcı giriş yapmamış');

    await _client
        .from('product_favorites')
        .delete()
        .eq('user_id', userId)
        .eq('product_id', productId);
  }

  /// Ürünün favori sayısını getirir
  Future<int> getProductFavoriteCount(String productId) async {
    final response = await _client
        .from('product_favorites')
        .select()
        .eq('product_id', productId);

    return (response as List).length;
  }

  // ==================== GÖNDERİ FAVORİLERİ ====================

  /// Kullanıcının tüm gönderi favorilerini getirir (gönderi bilgileriyle birlikte)
  Future<List<PostFavorite>> getPostFavorites() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Kullanıcı giriş yapmamış');

    final response = await _client
        .from('post_favorites')
        .select('*, posts(*)')
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (response as List)
        .map((json) => PostFavorite.fromJson(json as Map<String, dynamic>))
        .toList();
  }

  /// Gönderinin favori olup olmadığını kontrol eder
  Future<bool> isPostFavorited(String postId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) return false;

    final response = await _client
        .from('post_favorites')
        .select()
        .eq('user_id', userId)
        .eq('post_id', postId)
        .maybeSingle();

    return response != null;
  }

  /// Gönderiyi favorilere ekler veya çıkarır (toggle)
  /// Returns true if added, false if removed
  Future<bool> togglePostFavorite(String postId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Kullanıcı giriş yapmamış');

    // Önce mevcut durumunu kontrol et
    final isFavorited = await isPostFavorited(postId);

    if (isFavorited) {
      // Favoriden çıkar
      await _client
          .from('post_favorites')
          .delete()
          .eq('user_id', userId)
          .eq('post_id', postId);
      return false;
    } else {
      // Favoriye ekle
      await _client.from('post_favorites').insert({
        'user_id': userId,
        'post_id': postId,
      });
      return true;
    }
  }

  /// Gönderiyi favorilerden kaldırır
  Future<void> removePostFavorite(String postId) async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Kullanıcı giriş yapmamış');

    await _client
        .from('post_favorites')
        .delete()
        .eq('user_id', userId)
        .eq('post_id', postId);
  }

  /// Gönderinin favori sayısını getirir
  Future<int> getPostFavoriteCount(String postId) async {
    final response = await _client
        .from('post_favorites')
        .select()
        .eq('post_id', postId);

    return (response as List).length;
  }

  // ==================== GENEL FAVORİLER ====================

  /// Kullanıcının tüm favorilerini getirir (ürün ve gönderi)
  Future<Map<String, dynamic>> getAllFavorites() async {
    final products = await getProductFavorites();
    final posts = await getPostFavorites();

    return {
      'products': products,
      'posts': posts,
    };
  }

  /// Tüm favorileri temizler
  Future<void> clearAllFavorites() async {
    final userId = _client.auth.currentUser?.id;
    if (userId == null) throw Exception('Kullanıcı giriş yapmamış');

    await _client
        .from('product_favorites')
        .delete()
        .eq('user_id', userId);

    await _client
        .from('post_favorites')
        .delete()
        .eq('user_id', userId);
  }
}
