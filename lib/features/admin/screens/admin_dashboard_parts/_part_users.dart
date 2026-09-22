// Bu dosya `part of admin_dashboard_screen.dart` oldugu icin ana dosyadaki
// ignore_for_file direktifleri buraya UYGULANMAZ; her part kendi listesini
// tasimak zorundadir.
//
// invalid_use_of_protected_member: bu part'lar `extension on
// _AdminDashboardScreenState` deseniyle yazildi; setState/mounted analiz
// acisindan sinif disindan cagrilmis gorunur ama calisma zamaninda
// State'in kendi uyesidir. Tek gercek false positive budur ve yalniz o
// susturulur - dosyalarin analizden komple cikarilmasi (analysis_options
// exclude) dead_code/tip hatalarini da gizliyordu.
// ignore_for_file: invalid_use_of_protected_member
// ignore_for_file: use_build_context_synchronously, deprecated_member_use
part of '../admin_dashboard_screen.dart';

extension on _AdminDashboardScreenState {
  // ==========================================================================
  // Kullanicilar
  //
  // Kullanicilar sekmesinin arayuzu (arama, filtre, detay, askiya alma, silme)
  // artik ayri bir widget: lib/features/admin/widgets/admin_users_content.dart
  // (AdminUsersContent). Bu dosyada yalniz baska parcalarin (dukkan atama
  // ekranlari) kullandigi kullanici yukleyicileri kaldi.
  // ==========================================================================

  // Dükkanı olmayan kullanıcıları yükle (dükkan ekleme için)
  Future<List<Map<String, dynamic>>> _loadUsersWithoutShop() async {
    try {
      debugPrint('🔍 Dükkanı olmayan kullanıcılar yükleniyor...');

      // Önce tüm dükkan sahiplerini al
      final shopsResponse = await Supabase.instance.client
          .from('shops')
          .select('owner_id');

      // Null ve duplicate kontrolü ile owner ID'lerini al
      final shopOwnerIds = <String>{};
      for (final shop in shopsResponse) {
        final ownerId = shop['owner_id'] as String?;
        if (ownerId != null && ownerId.isNotEmpty) {
          shopOwnerIds.add(ownerId);
        }
      }

      // Tüm kullanıcıları al — profiles tablosuna authenticated SELECT
      // grant'i 20260803000006 ile kaldırıldı; doğrudan from('profiles')
      // çağrısı 42501 fırlatır. SECURITY DEFINER admin_list_users RPC
      // üzerinden, sayfalı/dar sütunlu liste çekilir.
      // NOT: Bu RPC `email` sütununu döndürmez (PII). Bu ekran yalnız
      // dükkan atamak için kullanıldığından email gerekmiyor.
      final usersResponse = await Supabase.instance.client.rpc<List<dynamic>>(
        'admin_list_users',
        params: {'p_limit': 100},
      );

      // Yinelenenleri filtrele ve dükkanı olmayanları al
      final seenIds = <String>{};
      final usersWithoutShop = List<Map<String, dynamic>>.from(usersResponse)
          .where((user) {
            final userId = user['id'] as String;
            // Yinelenen ID'leri atla
            if (seenIds.contains(userId)) return false;
            seenIds.add(userId);
            // Zaten dükkanı olanları atla
            return !shopOwnerIds.contains(userId);
          })
          .toList();

      debugPrint(
        '✅ Dükkanı olmayan ${usersWithoutShop.length} kullanıcı bulundu',
      );

      return usersWithoutShop;
    } catch (e) {
      debugPrint('❌ Dükkanı olmayan kullanıcılar yüklenirken hata: $e');
      return [];
    }
  }

  // Kullanıcıları yükle (dükkan sahibi seçimi gibi ekranlar için)
  // Not: profiles tablosundan SELECT grant'i REVOKE edildiği için
  // doğrudan select('*') ile PII yüklemesi yapılamaz. Bunun yerine
  // SECURITY DEFINER admin_user_list_with_stats() RPC'si kullanılır; o hem
  // dar güvenli sütunları hem de e-posta/telefon (PII, yalnız admin'e) ve
  // sosyal istatistikleri (gönderi/takipçi/takip/teslim) tek sorguda döner.
  // Migration henüz uygulanmadıysa RPC yok olabilir; o durumda eski
  // admin_list_users()'a düşeriz (email/istatistik yok ama kart yine çalışır).
  Future<List<Map<String, dynamic>>> _loadUsers({String? role}) async {
    try {
      debugPrint(
        '🔍 Kullanıcılar yükleniyor (admin_user_list_with_stats RPC, role=$role)',
      );

      List<dynamic> response;
      try {
        response = await Supabase.instance.client.rpc<List<dynamic>>(
          'admin_user_list_with_stats',
          params: {'p_limit': 100, 'p_role': role},
        );
        debugPrint('✅ ${response.length} kullanıcı yüklendi (istatistikli)');
      } catch (e) {
        // Zengin RPC yok (migration uygulanmamış) — eski sözleşmeye düş.
        debugPrint(
          '⚠️ admin_user_list_with_stats kullanılamıyor, admin_list_users\'a düşülüyor: $e',
        );
        response = await Supabase.instance.client.rpc<List<dynamic>>(
          'admin_list_users',
          params: {'p_limit': 100, 'p_role': role},
        );
        debugPrint('✅ ${response.length} kullanıcı yüklendi (sade)');
      }

      // PII debugPrint KALDIRILDI: tüm kullanıcı listesi log'a yazılmaz.
      return List<Map<String, dynamic>>.from(response);
    } catch (e, stackTrace) {
      debugPrint('❌ Kullanıcılar yüklenirken hata: $e');
      debugPrint('📍 Stack trace: $stackTrace');

      // Hata mesajını kullanıcıya göster
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Kullanıcılar yüklenirken hata oluştu: ${e.toString()}',
              ),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        });
      }

      // Hata durumunda boş liste döndür
      return [];
    }
  }
}
