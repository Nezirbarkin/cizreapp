import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/daily_deal_model.dart';

class DailyDealService {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Aktif günün fırsatlarını getir
  Future<List<DailyDeal>> getActiveDeals() async {
    try {
      final now = DateTime.now();
      final response = await _supabase
          .from('daily_deals')
          .select()
          .eq('is_active', true)
          .or('start_date.is.null,start_date.lte.$now')
          .or('end_date.is.null,end_date.gte.$now')
          .order('sort_order', ascending: true);

      return (response as List)
          .map((json) => DailyDeal.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Fırsat kartları yüklenirken hata: $e');
    }
  }

  // Tüm fırsat kartlarını getir (admin için)
  Future<List<DailyDeal>> getAllDeals() async {
    try {
      final response = await _supabase
          .from('daily_deals')
          .select()
          .order('sort_order', ascending: true);

      return (response as List)
          .map((json) => DailyDeal.fromJson(json))
          .toList();
    } catch (e) {
      throw Exception('Fırsat kartları yüklenirken hata: $e');
    }
  }

  // ID'ye göre fırsat kartı getir
  Future<DailyDeal?> getDealById(String id) async {
    try {
      final response = await _supabase
          .from('daily_deals')
          .select()
          .eq('id', id)
          .single();

      return DailyDeal.fromJson(response);
    } catch (e) {
      return null;
    }
  }

  // Fırsat kartı oluştur
  Future<DailyDeal> createDeal(Map<String, dynamic> data) async {
    try {
      final response = await _supabase
          .from('daily_deals')
          .insert(data)
          .select()
          .single();

      return DailyDeal.fromJson(response);
    } catch (e) {
      throw Exception('Fırsat kartı oluşturulurken hata: $e');
    }
  }

  // Fırsat kartını güncelle
  Future<DailyDeal> updateDeal(String id, Map<String, dynamic> data) async {
    try {
      final response = await _supabase
          .from('daily_deals')
          .update(data)
          .eq('id', id)
          .select()
          .single();

      return DailyDeal.fromJson(response);
    } catch (e) {
      throw Exception('Fırsat kartı güncellenirken hata: $e');
    }
  }

  // Fırsat kartını sil
  Future<void> deleteDeal(String id) async {
    try {
      await _supabase.from('daily_deals').delete().eq('id', id);
    } catch (e) {
      throw Exception('Fırsat kartı silinirken hata: $e');
    }
  }

  // Sıralamayı güncelle
  Future<void> updateOrder(List<Map<String, dynamic>> updates) async {
    try {
      for (var update in updates) {
        await _supabase
            .from('daily_deals')
            .update({'sort_order': update['sort_order']})
            .eq('id', update['id']);
      }
    } catch (e) {
      throw Exception('Sıralama güncellenirken hata: $e');
    }
  }
}
