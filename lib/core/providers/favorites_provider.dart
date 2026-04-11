import 'package:flutter/foundation.dart';
import '../models/favorite_models.dart';
import '../models/product_model.dart';
import '../models/post_model.dart' show Post;
import '../services/favorite_service.dart';

/// Favori Provider - Favorileri yönetir
class FavoritesProvider with ChangeNotifier {
  final FavoriteService _favoriteService = FavoriteService();

  List<ProductFavorite> _productFavorites = [];
  List<PostFavorite> _postFavorites = [];
  Map<String, bool> _productFavoritedCache = {}; // productId -> isFavorited
  Map<String, bool> _postFavoritedCache = {}; // postId -> isFavorited

  bool _isLoading = false;
  String? _error;

  // Getters
  List<ProductFavorite> get productFavorites => _productFavorites;
  List<PostFavorite> get postFavorites => _postFavorites;
  bool get isLoading => _isLoading;
  String? get error => _error;

  int get productFavoritesCount => _productFavorites.length;
  int get postFavoritesCount => _postFavorites.length;
  int get totalFavoritesCount => _productFavorites.length + _postFavorites.length;

  /// Kullanıcının tüm favorilerini yükler
  Future<void> loadFavorites() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final result = await _favoriteService.getAllFavorites();
      _productFavorites = result['products'] as List<ProductFavorite>;
      _postFavorites = result['posts'] as List<PostFavorite>;

      // Cache'i güncelle
      _productFavoritedCache.clear();
      for (var fav in _productFavorites) {
        _productFavoritedCache[fav.productId] = true;
      }

      _postFavoritedCache.clear();
      for (var fav in _postFavorites) {
        _postFavoritedCache[fav.postId] = true;
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sadece ürün favorilerini yükler
  Future<void> loadProductFavorites() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _productFavorites = await _favoriteService.getProductFavorites();

      // Cache'i güncelle
      _productFavoritedCache.clear();
      for (var fav in _productFavorites) {
        _productFavoritedCache[fav.productId] = true;
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Sadece gönderi favorilerini yükler
  Future<void> loadPostFavorites() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _postFavorites = await _favoriteService.getPostFavorites();

      // Cache'i güncelle
      _postFavoritedCache.clear();
      for (var fav in _postFavorites) {
        _postFavoritedCache[fav.postId] = true;
      }

      _isLoading = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Ürünün favori olup olmadığını kontrol eder (cache'li)
  bool isProductFavorited(String productId) {
    return _productFavoritedCache[productId] ?? false;
  }

  /// Gönderinin favori olup olmadığını kontrol eder (cache'li)
  bool isPostFavorited(String postId) {
    return _postFavoritedCache[postId] ?? false;
  }

  /// Ürünü favorilere ekler veya çıkarır
  Future<bool> toggleProductFavorite(String productId) async {
    try {
      final isAdded = await _favoriteService.toggleProductFavorite(productId);
      _productFavoritedCache[productId] = isAdded;

      if (!isAdded) {
        // Favoriden çıkarıldıysa listeden de çıkar
        _productFavorites.removeWhere((fav) => fav.productId == productId);
      } else {
        // Favoriye eklendiyse listeyi yeniden yükle
        await loadProductFavorites();
      }

      notifyListeners();
      return isAdded;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Gönderiyi favorilere ekler veya çıkarır
  Future<bool> togglePostFavorite(String postId) async {
    try {
      final isAdded = await _favoriteService.togglePostFavorite(postId);
      _postFavoritedCache[postId] = isAdded;

      if (!isAdded) {
        // Favoriden çıkarıldıysa listeden de çıkar
        _postFavorites.removeWhere((fav) => fav.postId == postId);
      } else {
        // Favoriye eklendiyse listeyi yeniden yükle
        await loadPostFavorites();
      }

      notifyListeners();
      return isAdded;
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Ürünü favorilerden kaldırır
  Future<void> removeProductFavorite(String productId) async {
    try {
      await _favoriteService.removeProductFavorite(productId);
      _productFavorites.removeWhere((fav) => fav.productId == productId);
      _productFavoritedCache[productId] = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Gönderiyi favorilerden kaldırır
  Future<void> removePostFavorite(String postId) async {
    try {
      await _favoriteService.removePostFavorite(postId);
      _postFavorites.removeWhere((fav) => fav.postId == postId);
      _postFavoritedCache[postId] = false;
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Favori ürünlerden ürün listesi döndürür
  List<Product> get favoriteProducts {
    return _productFavorites
        .map((fav) => fav.product)
        .whereType<Product>()
        .toList();
  }

  /// Favori gönderilerden gönderi listesi döndürür
  List<Post> get favoritePosts {
    return _postFavorites
        .map((fav) => fav.post)
        .whereType<Post>()
        .toList();
  }

  /// Cache'i günceller (batch işlemler için)
  void updateProductFavoritedCache(Map<String, bool> updates) {
    _productFavoritedCache.addAll(updates);
    notifyListeners();
  }

  void updatePostFavoritedCache(Map<String, bool> updates) {
    _postFavoritedCache.addAll(updates);
    notifyListeners();
  }

  /// Tüm favorileri temizler
  Future<void> clearAll() async {
    try {
      await _favoriteService.clearAllFavorites();
      _productFavorites.clear();
      _postFavorites.clear();
      _productFavoritedCache.clear();
      _postFavoritedCache.clear();
      notifyListeners();
    } catch (e) {
      _error = e.toString();
      notifyListeners();
      rethrow;
    }
  }

  /// Hata mesajını temizler
  void clearError() {
    _error = null;
    notifyListeners();
  }
}
