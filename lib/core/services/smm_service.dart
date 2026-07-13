import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/smm_provider_model.dart';
import '../models/digital_order_model.dart';
import '../utils/app_error_handler.dart';

class SmmProviderServiceInfo {
  final String service;
  final String? name;
  final String? category;
  final double? rate; // 1000 adet fiyatı
  final int? min;
  final int? max;

  SmmProviderServiceInfo({
    required this.service,
    this.name,
    this.category,
    this.rate,
    this.min,
    this.max,
  });

  factory SmmProviderServiceInfo.fromJson(Map<String, dynamic> json) {
    return SmmProviderServiceInfo(
      service: json['service'].toString(),
      name: json['name'] as String?,
      category: json['category'] as String?,
      rate: (json['rate'] as num?)?.toDouble(),
      min: json['min'] as int?,
      max: json['max'] as int?,
    );
  }
}

class DigitalOrderCreateResult {
  final String digitalOrderId;
  final String? externalOrderId;
  final double totalPrice;
  final double? newBalance;

  DigitalOrderCreateResult({
    required this.digitalOrderId,
    this.externalOrderId,
    required this.totalPrice,
    this.newBalance,
  });
}

class SmmService {
  SupabaseClient get _supabase => Supabase.instance.client;

  /// Provider listesini getirir (RLS: satıcı kendi provider'larını, admin hepsini görür).
  Future<List<SmmProvider>> getProviders() async {
    try {
      final data = await _supabase
          .from('smm_providers')
          .select('id, owner_type, owner_id, name, api_url, is_active, created_at, updated_at')
          .order('created_at', ascending: false);
      return (data as List)
          .map((e) => SmmProvider.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('❌ SMM: Provider listesi getirme hatası - $e');
      throw FriendlyException.from(e);
    }
  }

  /// Yeni provider ekler. apiKey sadece bu çağrıda yazılır, hiçbir zaman geri okunmaz.
  Future<void> createProvider({
    required String name,
    required String apiKey,
    required String ownerType,
    required String ownerId,
    String apiUrl = 'https://smmget.com/api/v2',
  }) async {
    try {
      await _supabase.from('smm_providers').insert({
        'owner_type': ownerType,
        'owner_id': ownerId,
        'name': name,
        'api_url': apiUrl,
        'api_key': apiKey,
        'is_active': true,
      });
    } catch (e) {
      debugPrint('❌ SMM: Provider oluşturma hatası - $e');
      throw FriendlyException.from(e);
    }
  }

  /// apiKey null bırakılırsa mevcut key değiştirilmez.
  Future<void> updateProvider({
    required String id,
    String? name,
    String? apiUrl,
    String? apiKey,
    bool? isActive,
  }) async {
    try {
      final payload = <String, dynamic>{};
      if (name != null) payload['name'] = name;
      if (apiUrl != null) payload['api_url'] = apiUrl;
      if (apiKey != null && apiKey.isNotEmpty) payload['api_key'] = apiKey;
      if (isActive != null) payload['is_active'] = isActive;
      if (payload.isEmpty) return;
      await _supabase.from('smm_providers').update(payload).eq('id', id);
    } catch (e) {
      debugPrint('❌ SMM: Provider güncelleme hatası - $e');
      throw FriendlyException.from(e);
    }
  }

  Future<void> deleteProvider(String id) async {
    try {
      await _supabase.from('smm_providers').delete().eq('id', id);
    } catch (e) {
      debugPrint('❌ SMM: Provider silme hatası - $e');
      throw FriendlyException.from(e);
    }
  }

  /// Dijital ürün siparişi oluşturur: bakiye düşer ve sağlayıcıya iletir.
  Future<DigitalOrderCreateResult> createDigitalOrder({
    required String productId,
    required String targetUrl,
    required int quantity,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'smm-order-create',
        body: {
          'product_id': productId,
          'target_url': targetUrl,
          'quantity': quantity,
        },
      );

      if (response.status != 200) {
        final error = response.data?['error'] ?? 'Sipariş oluşturulamadı';
        throw Exception(error);
      }

      final data = response.data;
      if (data['status'] != 'success') {
        throw Exception(data['error'] ?? 'Sipariş oluşturulamadı');
      }

      return DigitalOrderCreateResult(
        digitalOrderId: data['digital_order_id'] as String,
        externalOrderId: data['external_order_id']?.toString(),
        totalPrice: (data['total_price'] as num).toDouble(),
        newBalance: (data['new_balance'] as num?)?.toDouble(),
      );
    } on FunctionException catch (e) {
      final details = e.details;
      final serverError = details is Map ? details['error'] as String? : null;
      debugPrint('❌ SMM: Sipariş oluşturma hatası - status: ${e.status}, error: $serverError');
      throw FriendlyException(serverError ?? 'Dijital sipariş oluşturulamadı.', originalError: e);
    } catch (e) {
      debugPrint('❌ SMM: Sipariş oluşturma hatası - $e');
      throw FriendlyException.from(e);
    }
  }

  /// Kullanıcının dijital siparişlerini getirir (ürün adı join edilir).
  Future<List<DigitalOrder>> getMyDigitalOrders() async {
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('⚠️ SMM: getMyDigitalOrders çağrıldı ama oturum yok');
        return [];
      }

      final data = await _supabase
          .from('digital_orders')
          .select()
          .eq('user_id', userId)
          .order('created_at', ascending: false);

      debugPrint('📦 SMM: getMyDigitalOrders userId=$userId satır sayısı=${(data as List).length}');

      final orders = data;
      final productIds = orders.map((o) => o['product_id'] as String).toSet().toList();
      final productNames = <String, String>{};
      if (productIds.isNotEmpty) {
        final products = await _supabase
            .from('products')
            .select('id, name')
            .inFilter('id', productIds);
        for (final p in products as List) {
          productNames[p['id'] as String] = p['name'] as String;
        }
      }

      return orders.map((e) {
        final map = Map<String, dynamic>.from(e);
        map['products'] = {'name': productNames[map['product_id']]};
        return DigitalOrder.fromJson(map);
      }).toList();
    } catch (e) {
      debugPrint('❌ SMM: Dijital sipariş listesi getirme hatası - $e');
      throw FriendlyException.from(e);
    }
  }

  /// Sağlayıcının hizmet (service) listesini getirir. Ürün eklerken açıklama/fiyat/min/max
  /// alanlarının otomatik doldurulması için kullanılır.
  Future<List<SmmProviderServiceInfo>> getProviderServices(String providerId) async {
    try {
      final response = await _supabase.functions.invoke(
        'smm-provider-services',
        body: {'provider_id': providerId},
      );

      if (response.status != 200) {
        final error = response.data?['error'] ?? 'Servis listesi alınamadı';
        throw Exception(error);
      }

      final data = response.data;
      if (data['status'] != 'success') {
        throw Exception(data['error'] ?? 'Servis listesi alınamadı');
      }

      return (data['services'] as List)
          .map((e) => SmmProviderServiceInfo.fromJson(e as Map<String, dynamic>))
          .toList();
    } on FunctionException catch (e) {
      final details = e.details;
      final serverError = details is Map ? details['error'] as String? : null;
      debugPrint('❌ SMM: Servis listesi getirme hatası - status: ${e.status}, error: $serverError');
      throw FriendlyException(serverError ?? 'Servis listesi alınamadı.', originalError: e);
    } catch (e) {
      debugPrint('❌ SMM: Servis listesi getirme hatası - $e');
      throw FriendlyException.from(e);
    }
  }

  /// Satıcının kendi mağazasına ait dijital siparişleri getirir (gerçek external_order_id dahil,
  /// sorun olduğunda satıcı bu ID ile sağlayıcı panelinden sipariş durumunu takip edebilir).
  /// Sağlayıcının kime ait olduğuna bakılmaz (admin paylaşımlı ya da satıcının kendi provider'ı),
  /// mağazanın kendi dijital ürünleri üzerinden eşleştirilir.
  Future<List<DigitalOrder>> getShopDigitalOrders(String shopId) async {
    try {
      final products = await _supabase
          .from('products')
          .select('id, name')
          .eq('shop_id', shopId)
          .eq('product_type', 'digital');
      final productList = (products as List);
      if (productList.isEmpty) return [];

      final productIds = productList.map((p) => p['id'] as String).toList();
      final productNames = {for (final p in productList) p['id'] as String: p['name'] as String};

      final data = await _supabase
          .from('digital_orders')
          .select()
          .inFilter('product_id', productIds)
          .order('created_at', ascending: false);

      return (data as List).map((e) {
        final map = Map<String, dynamic>.from(e);
        map['products'] = {'name': productNames[map['product_id']]};
        return DigitalOrder.fromJson(map);
      }).toList();
    } catch (e) {
      debugPrint('❌ SMM: Mağaza dijital sipariş listesi getirme hatası - $e');
      throw FriendlyException.from(e);
    }
  }

  /// Admin için tüm dijital siparişleri getirir (RLS: admin hepsini görür).
  Future<List<DigitalOrder>> getAllDigitalOrders() async {
    try {
      final data = await _supabase
          .from('digital_orders')
          .select()
          .order('created_at', ascending: false)
          .limit(200);
      final orders = (data as List);
      final productIds = orders.map((o) => o['product_id'] as String).toSet().toList();
      final productNames = <String, String>{};
      if (productIds.isNotEmpty) {
        final products = await _supabase.from('products').select('id, name').inFilter('id', productIds);
        for (final p in products as List) {
          productNames[p['id'] as String] = p['name'] as String;
        }
      }
      return orders.map((e) {
        final map = Map<String, dynamic>.from(e);
        map['products'] = {'name': productNames[map['product_id']]};
        return DigitalOrder.fromJson(map);
      }).toList();
    } catch (e) {
      debugPrint('❌ SMM: Tüm dijital sipariş listesi getirme hatası - $e');
      throw FriendlyException.from(e);
    }
  }

  /// Satıcının dijital ürün satışlarından elde ettiği toplam net kazancı hesaplar
  /// (sadece seller_credited=true olan, yani gerçekten bakiyesine eklenmiş siparişler).
  double calculateDigitalEarnings(List<DigitalOrder> orders) {
    return orders
        .where((o) => o.sellerCredited && o.netSellerAmount != null)
        .fold(0.0, (sum, o) => sum + o.netSellerAmount!);
  }

  /// Bir dijital siparişin durumunu admin veya provider sahibi satıcı olarak manuel değiştirir.
  /// completed/partial -> satıcıya kazanç kredisi, canceled/refunded -> müşteriye tam iade (otomatik).
  Future<void> manualUpdateDigitalOrderStatus({
    required String digitalOrderId,
    required String newStatus,
    int? remains,
  }) async {
    try {
      final response = await _supabase.functions.invoke(
        'smm-order-manual-status',
        body: {
          'digital_order_id': digitalOrderId,
          'new_status': newStatus,
          if (remains != null) 'remains': remains,
        },
      );

      if (response.status != 200) {
        final error = response.data?['error'] ?? 'Durum güncellenemedi';
        throw Exception(error);
      }
      final data = response.data;
      if (data['status'] != 'success') {
        throw Exception(data['error'] ?? 'Durum güncellenemedi');
      }
    } on FunctionException catch (e) {
      final details = e.details;
      final serverError = details is Map ? details['error'] as String? : null;
      final debugDetail = details is Map ? details['debug_detail'] : null;
      debugPrint('❌ SMM: Manuel durum güncelleme hatası - status: ${e.status}, error: $serverError');
      if (debugDetail != null) {
        debugPrint('🔎 SMM: debug_detail = $debugDetail');
      }
      throw FriendlyException(
        debugDetail != null ? '$serverError ($debugDetail)' : (serverError ?? 'Durum güncellenemedi.'),
        originalError: e,
      );
    } catch (e) {
      debugPrint('❌ SMM: Manuel durum güncelleme hatası - $e');
      throw FriendlyException.from(e);
    }
  }

  /// Bekleyen siparişlerin durumunu sağlayıcıdan sorgulatır (manuel tazeleme).
  Future<void> refreshDigitalOrdersStatus() async {
    try {
      final response = await _supabase.functions.invoke('smm-order-status-check', body: {});
      debugPrint('📡 SMM: status-check yanıtı - ${response.data}');
    } catch (e) {
      debugPrint('❌ SMM: Durum tazeleme hatası - $e');
      // Tazeleme hatası kritik değil, listeyi sessizce eski durumla gösterebiliriz.
    }
  }
}
