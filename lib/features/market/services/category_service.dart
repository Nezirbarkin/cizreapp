import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/category_model.dart';

class CategoryService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Tüm aktif kategorileri getir
  Future<List<Category>> getCategories() async {
    try {
      final response = await _supabase
          .from('categories')
          .select()
          .eq('is_active', true)
          .order('display_order', ascending: true);

      return (response as List)
          .map((json) => Category.fromJson(Map<String, dynamic>.from(json)))
          .toList();
    } catch (e) {
      throw Exception('Kategoriler yüklenirken hata: $e');
    }
  }

  // Kategori ekle
  Future<Category> addCategory({
    required String name,
    required String slug,
    String? description,
    String? imageUrl,
    String? icon,
    int sortOrder = 0,
    bool isActive = true,
  }) async {
    try {
      final response = await _supabase.from('categories').insert({
        'name': name,
        'slug': slug,
        'description': description,
        'image_url': imageUrl,
        'icon': icon,
        'display_order': sortOrder,
        'is_active': isActive,
      }).select().single();

      return Category.fromJson(Map<String, dynamic>.from(response));
    } catch (e) {
      throw Exception('Kategori eklenirken hata: $e');
    }
  }

  // Kategori güncelle
  Future<Category> updateCategory({
    required String id,
    String? name,
    String? slug,
    String? description,
    String? imageUrl,
    String? icon,
    int? sortOrder,
    bool? isActive,
  }) async {
    try {
      final updates = <String, dynamic>{};
      if (name != null) updates['name'] = name;
      if (slug != null) updates['slug'] = slug;
      if (description != null) updates['description'] = description;
      if (imageUrl != null) updates['image_url'] = imageUrl;
      if (icon != null) updates['icon'] = icon;
      if (sortOrder != null) updates['display_order'] = sortOrder;
      if (isActive != null) updates['is_active'] = isActive;

      final response = await _supabase
          .from('categories')
          .update(updates)
          .eq('id', id)
          .select()
          .single();

      return Category.fromJson(Map<String, dynamic>.from(response));
    } catch (e) {
      throw Exception('Kategori güncellenirken hata: $e');
    }
  }

  // Kategori sil
  Future<void> deleteCategory(String id) async {
    try {
      await _supabase.from('categories').delete().eq('id', id);
    } catch (e) {
      throw Exception('Kategori silinirken hata: $e');
    }
  }

  // Kategori dükkan sayısını getir
  Future<int> getShopCountByCategory(String categoryId) async {
    try {
      final response = await _supabase
          .from('shops')
          .select('id')
          .eq('category_id', categoryId)
          .count();
      return response.count;
    } catch (e) {
      return 0;
    }
  }

  // ID'ye göre kategori getir
  Future<Category?> getCategoryById(String id) async {
    try {
      final response = await _supabase
          .from('categories')
          .select()
          .eq('id', id)
          .single();

      return Category.fromJson(Map<String, dynamic>.from(response));
    } catch (e) {
      return null;
    }
  }

  // Slug'a göre kategori getir
  Future<Category?> getCategoryBySlug(String slug) async {
    try {
      final response = await _supabase
          .from('categories')
          .select()
          .eq('slug', slug)
          .single();

      return Category.fromJson(Map<String, dynamic>.from(response));
    } catch (e) {
      return null;
    }
  }

  // Kategori arama
  Future<List<Category>> searchCategories(String query) async {
    try {
      final response = await _supabase
          .from('categories')
          .select()
          .eq('is_active', true)
          .or('name.ilike.%$query%,description.ilike.%$query%')
          .order('display_order', ascending: true)
          .limit(20);

      return (response as List)
          .map((json) => Category.fromJson(Map<String, dynamic>.from(json)))
          .toList();
    } catch (e) {
      return [];
    }
  }
}
