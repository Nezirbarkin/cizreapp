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
  // --- _loadPosts ---
  Future<List<Map<String, dynamic>>> _loadPosts() async {
    try {
      final response = await Supabase.instance.client
          .from('posts')
          .select('*, profiles(id, username, full_name, avatar_url)')
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false)
          .limit(50);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Gönderiler yüklenirken hata: $e');
      // Onceki surum burada SAHTE gonderiler donuyordu ('Ahmet Yılmaz',
      // 'Kahve mola zamanı' vb. id'leri '1'..'4'). Sorgu RLS/ag hatasiyla
      // dustugunde admin bunlari gercek gonderi sanip moderasyon yapmaya
      // calisiyor, sabitleme/silme islemleri de "id=1" bulunamadigi icin
      // sessizce basarisiz oluyordu. Ayrica panel, gonderi yokken bile dolu
      // gorunerek gercek arizayi gizliyordu.
      // _loadStories/_loadProducts ile ayni davranis: bos liste + gorunur hata.
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Gönderiler yüklenemedi: $e'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 5),
            ),
          );
        });
      }
      return [];
    }
  }

  // --- _loadStories ---
  Future<List<Map<String, dynamic>>> _loadStories() async {
    try {
      debugPrint('📌 _loadStories() çağrıldı');
      final response = await Supabase.instance.client
          .from('stories')
          .select('*, profiles(id, username, full_name, avatar_url)')
          .order('admin_pinned', ascending: false, nullsFirst: false)
          .order('is_pinned', ascending: false, nullsFirst: false)
          .order('created_at', ascending: false)
          .limit(50);

      final stories = List<Map<String, dynamic>>.from(response);

      // İlk 5 hikayenin sabitleme durumunu logla
      debugPrint('📌 Yüklenen hikayeler: ${stories.length} adet');
      for (int i = 0; i < 5 && i < stories.length; i++) {
        final s = stories[i];
        debugPrint(
          '📌  Hikayeler[$i]: id=${s['id']}, is_pinned=${s['is_pinned']}, admin_pinned=${s['admin_pinned']}',
        );
      }

      return stories;
    } catch (e) {
      debugPrint('❌ Hikayeler yüklenirken hata: $e');
      return [];
    }
  }

  // --- _loadProducts ---
  Future<List<Map<String, dynamic>>> _loadProducts() async {
    try {
      final response = await Supabase.instance.client
          .from('products')
          .select('*, shops(id, name, owner_id)')
          .order('is_pinned', ascending: false)
          .order('created_at', ascending: false)
          .limit(50);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Ürünler yüklenirken hata: $e');
      // Hata durumunda boş liste döndür
      return [];
    }
  }

  // --- _loadShops ---
  Future<List<Map<String, dynamic>>> _loadShops() async {
    try {
      final response = await Supabase.instance.client
          .from('shops')
          .select('id, name, owner_id')
          .order('name', ascending: true);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Satıcılar yüklenirken hata: $e');
      return [];
    }
  }

  // --- _loadCategories ---
  Future<List<Map<String, dynamic>>> _loadCategories() async {
    try {
      debugPrint('🔍 Kategoriler yükleniyor...');

      // Kategorileri getir
      final categoriesResponse = await Supabase.instance.client
          .from('categories')
          .select()
          .order('display_order', ascending: true);

      final categoriesList = List<Map<String, dynamic>>.from(categoriesResponse)
          .map(
            (cat) => {
              'id': cat['id'] as String,
              'name': cat['name'] as String?,
              'description': cat['description'] as String?,
              'display_order': cat['display_order'] as int?,
              'is_active': cat['is_active'] as bool?,
              'image_url': cat['image_url'] as String?,
              'shop_count': 0,
            },
          )
          .toList();

      // Tüm dükkanları getir ve kategorilere göre grupla
      final shopsResponse = await Supabase.instance.client
          .from('shops')
          .select('category_id');

      // Dükkan sayılarını hesapla
      final shopCounts = <String, int>{};
      for (var shop in shopsResponse) {
        final catId = shop['category_id'] as String?;
        if (catId != null) {
          shopCounts[catId] = (shopCounts[catId] ?? 0) + 1;
        }
      }

      // Kategorilere dükkan sayılarını ata
      for (var category in categoriesList) {
        category['shop_count'] = shopCounts[category['id']] ?? 0;
      }

      debugPrint('✅ ${categoriesList.length} kategori yüklendi');
      for (var cat in categoriesList) {
        debugPrint('   - ${cat['name']}: ${cat['shop_count']} dükkan');
      }
      return categoriesList;
    } catch (e) {
      debugPrint('❌ Kategoriler yüklenirken hata: $e');

      // Hata durumunda boş liste döndür
      return [];
    }
  }

  // --- _loadShopsWithDetails ---
  Future<List<Map<String, dynamic>>> _loadShopsWithDetails() async {
    try {
      debugPrint('🔍 Dükkanlar detaylı bilgilerle yükleniyor...');

      // Dükkanları al (foreign key join yerine ayrı sorgu ile profile bilgisi çekeceğiz)
      final response = await Supabase.instance.client
          .from('shops')
          .select('''
            id,
            name,
            slug,
            description,
            logo_url,
            category_id,
            owner_id,
            commission_rate,
            is_verified,
            is_approved,
            is_active,
            is_pinned,
            has_own_courier,
            delivery_fee,
            created_at,
            admin_credit,
            commission_debt,
            total_collected_cash,
            total_paid,
            cash_payment_revenue,
            online_payment_revenue
          ''')
          .order('is_pinned', ascending: false)
          .order('name', ascending: true);

      final shops = List<Map<String, dynamic>>.from(response);

      // Her dükkan için profile bilgisini ayrı sorgu ile al
      for (var shop in shops) {
        final ownerId = shop['owner_id'] as String?;
        if (ownerId != null) {
          try {
            // 20260803000006 sonrasında profiles üzerinde authenticated
            // SELECT policy'si yok; email/role sütunları revoke edildi.
            // Minimal profil bilgisi admin_profiles_minimal RPC üzerinden,
            // email ise admin_get_profile_email RPC üzerinden alınır.
            final minimalResp = await Supabase.instance.client
                .rpc<List<dynamic>>(
                  'admin_profiles_minimal',
                  params: {
                    'p_user_ids': [ownerId],
                  },
                );
            final profile = minimalResp.isNotEmpty
                ? Map<String, dynamic>.from(minimalResp.first)
                : null;
            final email = await Supabase.instance.client.rpc<String?>(
              'admin_get_profile_email',
              params: {'p_user_id': ownerId},
            );
            if (profile != null) {
              profile['email'] = email;
              shop['profiles'] = profile;
            }
          } catch (e) {
            debugPrint('⚠️ Profile yüklenemedi (owner_id: $ownerId): $e');
          }
        }

        try {
          // Ürün sayısı
          final productsCount = await Supabase.instance.client
              .from('products')
              .select('id')
              .eq('shop_id', shop['id'])
              .count();

          shop['product_count'] = productsCount.count;

          // Toplam kazanç (tamamlanan siparişlerden) ve sipariş sayıları
          final ordersResponse = await Supabase.instance.client
              .from('orders')
              .select('total, status, created_at')
              .eq('shop_id', shop['id']);

          double totalEarnings = 0.0;
          double weeklyEarnings = 0.0;
          double monthlyEarnings = 0.0;
          int totalOrders = (ordersResponse as List).length;
          int deliveredOrders = 0;
          int pendingOrders = 0;
          int cancelledOrders = 0;

          final now = DateTime.now();
          final weekAgo = now.subtract(const Duration(days: 7));
          final monthAgo = now.subtract(const Duration(days: 30));

          for (var order in ordersResponse) {
            final status = order['status'] as String?;
            if (status == 'delivered') {
              deliveredOrders++;
              final orderTotal = (order['total'] as num?)?.toDouble() ?? 0.0;
              totalEarnings += orderTotal;

              // Tarih bazlı kazanç hesaplama
              final createdAt = order['created_at'] != null
                  ? DateTime.tryParse(order['created_at'].toString())
                  : null;
              if (createdAt != null) {
                if (createdAt.isAfter(weekAgo)) {
                  weeklyEarnings += orderTotal;
                }
                if (createdAt.isAfter(monthAgo)) {
                  monthlyEarnings += orderTotal;
                }
              }
            } else if (status == 'cancelled') {
              cancelledOrders++;
            } else {
              pendingOrders++;
            }
          }

          // Komisyon hesaplamasi
          final commissionRate =
              (shop['commission_rate'] as num?)?.toDouble() ?? 10.0;
          final adminCommission = totalEarnings * (commissionRate / 100);

          // Kurye teslimat ucreti (kuryesi olmayan satıcılar icin)
          final hasOwnCourier = shop['has_own_courier'] as bool? ?? true;
          double courierDeduction = 0.0;
          if (!hasOwnCourier) {
            // Kuryesi olmayan satıcının teslim edilen siparişlerinden kurye ucretini hesapla
            final courierFee = await _getCourierFee();
            courierDeduction = deliveredOrders * courierFee;
          }

          // Net kazanc = Toplam kazanc - Komisyon - Kurye ucreti
          final netEarnings =
              totalEarnings - adminCommission - courierDeduction;

          shop['total_earnings'] = totalEarnings;
          shop['weekly_earnings'] = weeklyEarnings;
          shop['monthly_earnings'] = monthlyEarnings;
          shop['admin_commission_total'] = adminCommission;
          shop['courier_deduction'] = courierDeduction;
          shop['net_earnings'] = netEarnings;
          shop['total_orders'] = totalOrders;
          shop['delivered_orders'] = deliveredOrders;
          shop['pending_orders'] = pendingOrders;
          shop['cancelled_orders'] = cancelledOrders;
        } catch (e) {
          debugPrint(
            'Dükkan istatistikleri yüklenirken hata (${shop['id']}): $e',
          );
          shop['product_count'] = 0;
          shop['total_earnings'] = 0.0;
          shop['weekly_earnings'] = 0.0;
          shop['monthly_earnings'] = 0.0;
          shop['admin_commission_total'] = 0.0;
          shop['net_earnings'] = 0.0;
          shop['total_orders'] = 0;
          shop['delivered_orders'] = 0;
          shop['pending_orders'] = 0;
          shop['cancelled_orders'] = 0;
        }
      }

      debugPrint('✅ ${shops.length} dükkan yüklendi');
      return shops;
    } catch (e) {
      debugPrint('❌ Dükkanlar yüklenirken hata: $e');
      return [];
    }
  }

  // --- _loadOrders ---
  Future<List<Map<String, dynamic>>> _loadOrders() async {
    try {
      debugPrint(
        '🔍 Siparişler yükleniyor... (Filtre: ${_selectedShopFilter ?? "Tümü"})',
      );

      var query = Supabase.instance.client.from('orders').select('''
            *,
            profiles!orders_user_id_fkey(id, username, full_name, email, avatar_url, phone),
            shops(id, name, owner_id, commission_rate, has_own_courier),
            order_items(id, product_id, product_name, product_image_url, price, quantity)
          ''');

      // customer_phone alanını siparişlerden almak için ek sorgu gerekmiyor,
      // ancak address_display ve address_id alanları orders tablosundan gelmeli

      // Dükkan filtresi varsa ekle
      if (_selectedShopFilter != null && _selectedShopFilter != 'all') {
        query = query.eq('shop_id', _selectedShopFilter!);
      }

      final response = await query
          .order('created_at', ascending: false)
          .limit(100);

      final orders = List<Map<String, dynamic>>.from(response);
      debugPrint('✅ ${orders.length} sipariş yüklendi');

      // Kurye bilgilerini toplu olarak çek
      final orderIds = orders.map((o) => o['id'] as String).toList();
      Map<String, Map<String, dynamic>> courierInfoMap = {};

      if (orderIds.isNotEmpty) {
        try {
          final courierAssignments = await Supabase.instance.client
              .from('courier_assignments')
              .select('''
                id, order_id, status, picked_up_at, delivered_at,
                courier:profiles!courier_assignments_courier_id_fkey(id, full_name, phone)
              ''')
              .inFilter('order_id', orderIds);

          for (var assignment in courierAssignments) {
            final orderId = assignment['order_id'] as String;
            courierInfoMap[orderId] = {
              'courier_name':
                  assignment['courier']?['full_name'] ?? 'Bilinmeyen Kurye',
              'courier_phone': assignment['courier']?['phone'] ?? '',
              'status': assignment['status'] ?? 'pending',
              'picked_up_at': assignment['picked_up_at'],
              'delivered_at': assignment['delivered_at'],
            };
          }
        } catch (e) {
          debugPrint('⚠️ Kurye bilgileri yüklenemedi: $e');
        }

        // Fallback: courier_assignments kaydı olmayan teslim edilmiş siparişler
        // için orders tablosundaki delivered_courier_* alanlarını kullan.
        try {
          final ordersFallback = await Supabase.instance.client
              .from('orders')
              .select(
                'id, delivered_courier_name, delivered_courier_phone, delivered_at, status',
              )
              .inFilter('id', orderIds);
          for (var row in ordersFallback) {
            final orderId = row['id'] as String;
            if (courierInfoMap.containsKey(orderId)) continue;
            final courierName = row['delivered_courier_name'] as String?;
            if (courierName == null || courierName.isEmpty) continue;
            final status = (row['status'] as String?) ?? '';
            courierInfoMap[orderId] = {
              'courier_name': courierName,
              'courier_phone':
                  (row['delivered_courier_phone'] as String?) ?? '',
              'status': status == 'delivered' ? 'delivered' : 'pending',
              'picked_up_at': null,
              'delivered_at': row['delivered_at'],
            };
          }
        } catch (e) {
          // Sütunlar eklenmemiş olabilir (migration çalıştırılmamış); sessizce geç.
          debugPrint(
            'orders.delivered_courier_* fallback yüklenemedi (sütun eksik olabilir): $e',
          );
        }
      }

      // Her sipariş için kazanç hesaplaması yap ve adres alanını düzelt
      for (var order in orders) {
        final totalAmount = (order['total'] as num?)?.toDouble() ?? 0.0;
        final shop = order['shops'] as Map<String, dynamic>?;
        final commissionRate =
            (shop?['commission_rate'] as num?)?.toDouble() ?? 10.0;

        final adminCommission = totalAmount * (commissionRate / 100);
        final sellerEarnings = totalAmount - adminCommission;

        order['admin_commission'] = adminCommission;
        order['seller_earnings'] = sellerEarnings;
        order['commission_rate'] = commissionRate;

        // delivery_address_text varsa address_display'e kopyala
        if (order['delivery_address_text'] != null &&
            order['address_display'] == null) {
          order['address_display'] = order['delivery_address_text'];
        }

        // Kurye bilgisini ekle
        final orderId = order['id'] as String;
        if (courierInfoMap.containsKey(orderId)) {
          order['courier_info'] = courierInfoMap[orderId];
        }
      }

      return orders;
    } catch (e, stackTrace) {
      debugPrint('❌ Siparişler yüklenirken hata: $e');
      debugPrint('Stack trace: $stackTrace');
      // Hata durumunda boş liste döndür - gerçek hatanın görünmesi için
      return [];
    }
  }

  // --- _loadShopsForFilter ---
  Future<List<Map<String, dynamic>>> _loadShopsForFilter() async {
    try {
      final response = await Supabase.instance.client
          .from('shops')
          .select('id, name')
          .eq('is_active', true)
          .order('name');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Dükkanlar yüklenirken hata: $e');
      return [];
    }
  }

  // --- _loadReports ---
  Future<List<Map<String, dynamic>>> _loadReports() async {
    try {
      debugPrint('🔍 Kullanıcı şikayetleri yükleniyor...');

      final response = await Supabase.instance.client
          .from('user_reports')
          .select('''
            *,
            reporter:profiles!user_reports_reporter_id_fkey(id, username, full_name, email, avatar_url),
            reported:profiles!user_reports_reported_user_id_fkey(id, username, full_name, email, avatar_url)
          ''')
          .order('created_at', ascending: false)
          .limit(100);

      final reports = List<Map<String, dynamic>>.from(response);
      debugPrint('✅ ${reports.length} şikayet yüklendi');
      return reports;
    } catch (e, stackTrace) {
      debugPrint('❌ Şikayetler yüklenirken hata: $e');
      debugPrint('📍 Stack trace: $stackTrace');
      return [];
    }
  }

  // --- _loadPostReports ---
  Future<List<Map<String, dynamic>>> _loadPostReports() async {
    try {
      final response = await Supabase.instance.client
          .from('post_reports')
          .select('''
            *,
            reporter:profiles!post_reports_reporter_id_fkey(id, username, full_name, email, avatar_url),
            reported_post:posts!post_reports_reported_post_id_fkey(id, content, user_id)
          ''')
          .order('created_at', ascending: false);
      debugPrint('✅ Gönderi şikayetleri yüklendi: ${response.length} adet');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('❌ Gönderi şikayetleri yüklenirken hata: $e');
      // Hata mesajını sakla, UI'da göstermek için
      return [];
    }
  }

  // --- _loadSupportTickets ---
  Future<List<Map<String, dynamic>>> _loadSupportTickets() async {
    try {
      final response = await Supabase.instance.client
          .from('support_tickets')
          .select('*, profiles(email, username)')
          .order('created_at', ascending: false)
          .limit(100);

      // Format ve user email ekle
      final tickets = List<Map<String, dynamic>>.from(response);
      for (var ticket in tickets) {
        if (ticket['profiles'] != null) {
          ticket['user_email'] = ticket['profiles']['email'] ?? '-';
        }
      }

      return tickets;
    } catch (e) {
      debugPrint('Destek talepleri yüklenirken hata: $e');
      // Mock veriler döndür
      return [
        {
          'id': '1',
          'subject': 'Ödeme sorunu',
          'message': 'Siparişim hala işleniyor.',
          'user_email': 'user1@example.com',
          'status': 'open',
          'created_at': DateTime.now()
              .subtract(const Duration(days: 2))
              .toIso8601String(),
        },
        {
          'id': '2',
          'subject': 'Ürün teslimi',
          'message': 'Ürün ne zaman gelecek?',
          'user_email': 'user2@example.com',
          'status': 'in_progress',
          'created_at': DateTime.now()
              .subtract(const Duration(days: 1))
              .toIso8601String(),
        },
        {
          'id': '3',
          'subject': 'İade işlemi',
          'message': 'Ürünü iade etmek istiyorum.',
          'user_email': 'user3@example.com',
          'status': 'resolved',
          'created_at': DateTime.now().toIso8601String(),
        },
      ];
    }
  }

  // --- _loadPaymentData ---
  Future<Map<String, dynamic>> _loadPaymentData() async {
    try {
      // Ödeme isteklerini ve dükkan bilgilerini çek
      final payoutResponse = await Supabase.instance.client
          .from('payout_requests')
          .select('''
            *,
            shops(
              id,
              name,
              owner_id,
              profiles(email, username)
            )
          ''')
          .order('created_at', ascending: false)
          .limit(50);

      final payouts = List<Map<String, dynamic>>.from(payoutResponse);

      // İstatistikler
      final totalPayouts = payouts.length;
      final pendingPayouts = payouts
          .where((p) => p['status'] == 'pending')
          .length;
      final approvedPayouts = payouts
          .where((p) => p['status'] == 'approved')
          .length;
      final rejectedPayouts = payouts
          .where((p) => p['status'] == 'rejected')
          .length;

      // Toplam tutar hesapla
      double totalAmount = 0;
      double pendingAmount = 0;
      double approvedAmount = 0;

      for (var payout in payouts) {
        final amount = (payout['total_amount'] as num?)?.toDouble() ?? 0.0;
        totalAmount += amount;

        if (payout['status'] == 'pending') {
          pendingAmount += amount;
        } else if (payout['status'] == 'approved') {
          approvedAmount += amount;
        }
      }

      return {
        'payments': payouts,
        'stats': {
          'total_revenue': totalAmount.toStringAsFixed(2),
          'total_payments': totalPayouts,
          'completed_count': approvedPayouts,
          'pending_count': pendingPayouts,
          'cancelled_count': rejectedPayouts,
          'pending_amount': pendingAmount.toStringAsFixed(2),
          'approved_amount': approvedAmount.toStringAsFixed(2),
        },
      };
    } catch (e) {
      debugPrint('Ödeme istekleri yüklenirken hata: $e');
      // Mock veriler döndür
      final now = DateTime.now();
      final mockPayments = [
        {
          'id': 'pay_${now.millisecondsSinceEpoch}_1',
          'total_amount': 5000.00,
          'status': 'pending',
          'created_at': now
              .subtract(const Duration(hours: 2))
              .toIso8601String(),
          'iban': 'TR12 3456 7890 1234 5678 9012 34',
          'account_holder_name': 'Ahmet Yılmaz',
          'notes': 'Ocak ayı kazancım',
          'shops': {
            'id': 'shop1',
            'name': 'Teknoloji Dükkanı',
            'owner_id': 'user1',
            'profiles': {
              'email': 'ahmet@example.com',
              'username': 'ahmet_tech',
            },
          },
        },
        {
          'id': 'pay_${now.millisecondsSinceEpoch}_2',
          'total_amount': 3250.50,
          'status': 'approved',
          'created_at': now
              .subtract(const Duration(hours: 5))
              .toIso8601String(),
          'iban': 'TR98 7654 3210 9876 5432 1098 76',
          'account_holder_name': 'Ayşe Demir',
          'notes': 'Haftalık ödeme',
          'reviewed_at': now
              .subtract(const Duration(hours: 1))
              .toIso8601String(),
          'shops': {
            'id': 'shop2',
            'name': 'Moda Evi',
            'owner_id': 'user2',
            'profiles': {'email': 'ayse@example.com', 'username': 'ayse_moda'},
          },
        },
        {
          'id': 'pay_${now.millisecondsSinceEpoch}_3',
          'total_amount': 7500.00,
          'status': 'pending',
          'created_at': now.subtract(const Duration(days: 1)).toIso8601String(),
          'iban': 'TR45 6789 0123 4567 8901 2345 67',
          'account_holder_name': 'Mehmet Kaya',
          'notes': 'Aralık ayı kazancı',
          'shops': {
            'id': 'shop3',
            'name': 'Spor Market',
            'owner_id': 'user3',
            'profiles': {
              'email': 'mehmet@example.com',
              'username': 'mehmet_spor',
            },
          },
        },
        {
          'id': 'pay_${now.millisecondsSinceEpoch}_4',
          'total_amount': 1500.00,
          'status': 'rejected',
          'created_at': now.subtract(const Duration(days: 2)).toIso8601String(),
          'iban': 'TR32 1098 7654 3210 9876 5432 10',
          'account_holder_name': 'Zeynep Şahin',
          'admin_notes': 'IBAN bilgileri hatalı',
          'reviewed_at': now
              .subtract(const Duration(days: 1))
              .toIso8601String(),
          'shops': {
            'id': 'shop4',
            'name': 'Kırtasiye Dünyası',
            'owner_id': 'user4',
            'profiles': {
              'email': 'zeynep@example.com',
              'username': 'zeynep_kirtasiye',
            },
          },
        },
        {
          'id': 'pay_${now.millisecondsSinceEpoch}_5',
          'total_amount': 4200.75,
          'status': 'pending',
          'created_at': now.subtract(const Duration(days: 3)).toIso8601String(),
          'iban': 'TR76 5432 1098 7654 3210 9876 54',
          'account_holder_name': 'Can Özkan',
          'shops': {
            'id': 'shop5',
            'name': 'Elektronik Market',
            'owner_id': 'user5',
            'profiles': {
              'email': 'can@example.com',
              'username': 'can_electronik',
            },
          },
        },
      ];

      return {
        'payments': mockPayments,
        'stats': {
          'total_revenue': '21450.25',
          'total_payments': 5,
          'completed_count': 1,
          'pending_count': 3,
          'cancelled_count': 1,
          'pending_amount': '16700.75',
          'approved_amount': '3250.50',
        },
      };
    }
  }

  // --- _loadReportData ---
  Future<Map<String, dynamic>> _loadReportData() async {
    try {
      final now = DateTime.now();
      DateTime startDate;

      // Tarihe göre filtrele
      switch (_selectedPeriod) {
        case 'daily':
          startDate = now.subtract(const Duration(days: 7));
          break;
        case 'weekly':
          startDate = now.subtract(const Duration(days: 30));
          break;
        case 'monthly':
        default:
          startDate = now.subtract(const Duration(days: 90));
          break;
      }

      // Siparişleri yükle
      final ordersResponse = await Supabase.instance.client
          .from('orders')
          .select()
          .gte('created_at', startDate.toIso8601String())
          .order('created_at', ascending: true);

      final orders = List<Map<String, dynamic>>.from(ordersResponse);

      // Toplam istatistikler
      double totalRevenue = 0;
      final customerIds = <String>{};

      for (var order in orders) {
        totalRevenue += (order['total'] as num?)?.toDouble() ?? 0.0;
        if (order['customer_id'] != null) {
          customerIds.add(order['customer_id'] as String);
        }
      }

      final avgOrder = orders.isNotEmpty ? totalRevenue / orders.length : 0.0;

      // Kazanç grafiği verisi
      final revenueData = <Map<String, dynamic>>[];
      final ordersData = <Map<String, dynamic>>[];

      // Veriyi grupla
      final groupedRevenue = <String, double>{};
      final groupedOrders = <String, int>{};

      for (var order in orders) {
        final date = DateTime.parse(order['created_at'] as String);
        String key;

        switch (_selectedPeriod) {
          case 'daily':
            key = '${date.day}/${date.month}';
            break;
          case 'weekly':
            final weekNum = ((date.day - 1) / 7).floor() + 1;
            key = 'H$weekNum';
            break;
          case 'monthly':
          default:
            key = '${date.month}/${date.year.toString().substring(2)}';
            break;
        }

        groupedRevenue[key] =
            (groupedRevenue[key] ?? 0.0) +
            ((order['total'] as num?)?.toDouble() ?? 0.0);
        groupedOrders[key] = (groupedOrders[key] ?? 0) + 1;
      }

      // Sıralı listeye çevir
      final sortedKeys = groupedRevenue.keys.toList()..sort();
      for (var key in sortedKeys.take(10)) {
        revenueData.add({'label': key, 'value': groupedRevenue[key] ?? 0});
        ordersData.add({'label': key, 'value': groupedOrders[key] ?? 0});
      }

      // Kategori dağılımı (ürün kategorilerine göre)
      final categoryData = <Map<String, dynamic>>[];
      final categoryColors = [
        Colors.purple,
        Colors.blue,
        Colors.green,
        Colors.orange,
        Colors.red,
        Colors.teal,
      ];

      try {
        final productsResponse = await Supabase.instance.client
            .from('products')
            .select('category_id, categories(name)')
            .limit(100);

        final products = List<Map<String, dynamic>>.from(productsResponse);
        final categoryCounts = <String, int>{};

        for (var product in products) {
          final category = product['categories']?['name'] ?? 'Diğer';
          categoryCounts[category] = (categoryCounts[category] ?? 0) + 1;
        }

        int colorIndex = 0;
        categoryCounts.forEach((category, count) {
          categoryData.add({
            'label': category,
            'value': count,
            'color': categoryColors[colorIndex % categoryColors.length],
          });
          colorIndex++;
        });

        // Sırala
        categoryData.sort(
          (a, b) => (b['value'] as int).compareTo(a['value'] as int),
        );
      } catch (e) {
        debugPrint('Kategori verileri yüklenirken hata: $e');
      }

      return {
        'totalRevenue': totalRevenue.toStringAsFixed(2),
        'totalOrders': orders.length,
        'avgOrder': avgOrder.toStringAsFixed(2),
        'activeCustomers': customerIds.length,
        'revenueData': revenueData,
        'ordersData': ordersData,
        'categoryData': categoryData,
      };
    } catch (e) {
      debugPrint('Rapor verileri yüklenirken hata: $e');

      // Mock veriler döndür
      final categoryColors = [
        Colors.purple,
        Colors.blue,
        Colors.green,
        Colors.orange,
        Colors.red,
        Colors.teal,
      ];

      final mockRevenueData = [
        {'label': 'Pzt', 'value': 4500.0},
        {'label': 'Sal', 'value': 5200.0},
        {'label': 'Çar', 'value': 3800.0},
        {'label': 'Per', 'value': 6100.0},
        {'label': 'Cum', 'value': 7500.0},
        {'label': 'Cmt', 'value': 8200.0},
        {'label': 'Paz', 'value': 5400.0},
      ];

      final mockOrdersData = [
        {'label': 'Pzt', 'value': 15},
        {'label': 'Sal', 'value': 18},
        {'label': 'Çar', 'value': 12},
        {'label': 'Per', 'value': 22},
        {'label': 'Cum', 'value': 28},
        {'label': 'Cmt', 'value': 31},
        {'label': 'Paz', 'value': 19},
      ];

      final mockCategoryData = [
        {'label': 'Elektronik', 'value': 45, 'color': categoryColors[0]},
        {'label': 'Giyim', 'value': 32, 'color': categoryColors[1]},
        {'label': 'Ev & Yaşam', 'value': 28, 'color': categoryColors[2]},
        {'label': 'Spor', 'value': 21, 'color': categoryColors[3]},
        {'label': 'Kitap', 'value': 15, 'color': categoryColors[4]},
      ];

      return {
        'totalRevenue': '40700.00',
        'totalOrders': 145,
        'avgOrder': '280.69',
        'activeCustomers': 89,
        'revenueData': mockRevenueData,
        'ordersData': mockOrdersData,
        'categoryData': mockCategoryData,
      };
    }
  }

  // --- _loadLogsData ---
  Future<Map<String, dynamic>> _loadLogsData() async {
    final client = Supabase.instance.client;
    final raw = await client.rpc<dynamic>(
      'admin_logs_data',
      params: {
        'p_recent_user_limit': 20,
        'p_error_limit': 20,
        'p_most_viewed_limit': 5,
        'p_window_days': _logsWindowDays,
      },
    );
    final data = Map<String, dynamic>.from(raw as Map);

    int asInt(dynamic value) => value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '') ?? 0;

    final errors = ((data['errors'] as List?) ?? const []).map((rawError) {
      final error = Map<String, dynamic>.from(rawError as Map);
      return AnalyticsEvent(
        eventType: error['event_type']?.toString() ?? 'error',
        entityId: error['entity_id']?.toString(),
        timestamp: DateTime.parse(error['created_at'] as String),
        metadata: error['metadata'] is Map
            ? Map<String, dynamic>.from(error['metadata'] as Map)
            : null,
        duration: error['duration_ms'] == null
            ? null
            : asInt(error['duration_ms']),
      );
    }).toList();

    final errorTypeCounts = <String, int>{
      for (final entry in Map<String, dynamic>.from(
        (data['errorTypeCounts'] as Map?) ?? const {},
      ).entries)
        entry.key: asInt(entry.value),
    };
    final hourlyDistribution = <int, int>{
      for (final entry in Map<String, dynamic>.from(
        (data['hourlyDistribution'] as Map?) ?? const {},
      ).entries)
        if (int.tryParse(entry.key) != null)
          int.parse(entry.key): asInt(entry.value),
    };
    // mostViewedPosts artik gercek post_views verisinden gelen bir dizi:
    // her eleman {post_id, label, view_count}. Eskiden entity_id -> sayi
    // seklinde bir obje idi ve o kaynak (app_analytics_events'teki post_view)
    // hicbir zaman yazilmadigi icin kart daima bostu.
    final mostViewedPosts = ((data['mostViewedPosts'] as List?) ?? const [])
        .map((rawPost) {
          final post = Map<String, dynamic>.from(rawPost as Map);
          return <String, dynamic>{
            'post_id': post['post_id']?.toString() ?? '',
            'label': post['label']?.toString() ?? '',
            'view_count': asInt(post['view_count']),
          };
        })
        .toList();

    final eventTypeCounts = <String, int>{
      for (final entry in Map<String, dynamic>.from(
        (data['eventTypeCounts'] as Map?) ?? const {},
      ).entries)
        entry.key: asInt(entry.value),
    };

    // platform: 'ios' | 'android' | 'web' | 'unknown' -> {online, total}
    final platformCounts = <String, Map<String, int>>{
      for (final entry in Map<String, dynamic>.from(
        (data['platformCounts'] as Map?) ?? const {},
      ).entries)
        entry.key: {
          'online': asInt((entry.value as Map?)?['online']),
          'total': asInt((entry.value as Map?)?['total']),
        },
    };

    return {
      'windowDays': asInt(data['windowDays']),
      'online': asInt(data['online']),
      'inactive': asInt(data['inactive']),
      'errorTypeCounts': errorTypeCounts,
      'eventTypeCounts': eventTypeCounts,
      'platformCounts': platformCounts,
      'hourlyDistribution': hourlyDistribution,
      'mostViewedPosts': mostViewedPosts,
      'windowEvents': asInt(data['windowEvents']),
      'postViewCount': asInt(data['postViewCount']),
      'dau': asInt(data['dau']),
      'wau': asInt(data['wau']),
      'mau': asInt(data['mau']),
      'totalUsers': asInt(data['totalUsers']),
      'newToday': asInt(data['newToday']),
      'totalEvents': asInt(data['totalEvents']),
      'avgViewDuration': asInt(data['avgViewDuration']),
      'errorCount': asInt(data['errorCount']),
      'errors': errors,
      'recentUsers': ((data['recentUsers'] as List?) ?? const [])
          .map((user) => Map<String, dynamic>.from(user as Map))
          .toList(),
    };
  }

  // --- _loadOrderControlSettings ---
  Future<Map<String, dynamic>> _loadOrderControlSettings() async {
    try {
      // Önce tüm sütunları çekmeyi dene
      final response = await Supabase.instance.client
          .from('app_about_settings')
          .select()
          .single();

      return {
        'global_orders_enabled':
            response['global_orders_enabled'] as bool? ?? true,
        'order_approval_code_enabled':
            response['order_approval_code_enabled'] as bool? ?? true,
      };
    } catch (e) {
      debugPrint('⚠️ app_about_settings yüklenirken hata: $e');
      // Sütun yoksa sadece global_orders_enabled'ı çekmeyi dene
      try {
        final response = await Supabase.instance.client
            .from('app_about_settings')
            .select('global_orders_enabled')
            .single();
        return {
          'global_orders_enabled':
              response['global_orders_enabled'] as bool? ?? true,
          'order_approval_code_enabled': true, // Sütun yoksa varsayılan true
        };
      } catch (e2) {
        debugPrint('⚠️ global_orders_enabled da yüklenemedi: $e2');
        return {
          'global_orders_enabled': true,
          'order_approval_code_enabled': true,
        };
      }
    }
  }

  // --- _loadAPISettings ---
  Future<Map<String, dynamic>> _loadAPISettings() async {
    try {
      // API Keys yükle
      final apiKeysResponse = await Supabase.instance.client
          .from('api_keys')
          .select()
          .order('created_at', ascending: false);

      final apiKeys = List<Map<String, dynamic>>.from(apiKeysResponse);

      // API Settings yükle
      final settingsResponse = await Supabase.instance.client
          .from('api_settings')
          .select()
          .single()
          .catchError(
            (_) => {
              'require_https': true,
              'cors_enabled': true,
              'requests_per_minute': 60,
              'requests_per_hour': 10000,
              'requests_per_month': 500000,
              'total_requests': 0,
              'successful_requests': 0,
              'failed_requests': 0,
              'allowed_ips': 'Sınırlı yok',
            },
          );

      return {'apiKeys': apiKeys, 'settings': settingsResponse};
    } catch (e) {
      debugPrint('API ayarları yüklenirken hata: $e');
      // Mock veriler döndür
      final now = DateTime.now();
      return {
        'apiKeys': [
          {
            'id': '1',
            'name': 'Production API',
            'key': 'live_${now.millisecondsSinceEpoch}_prod',
            'description': 'Ana üretim ortamı API anahtarı',
            'is_active': true,
            'created_at': now
                .subtract(const Duration(days: 30))
                .toIso8601String(),
            'last_used_at': now
                .subtract(const Duration(hours: 2))
                .toIso8601String(),
          },
          {
            'id': '2',
            'name': 'Mobile App',
            'key': 'mobile_${now.millisecondsSinceEpoch}_app',
            'description': 'Mobil uygulama API anahtarı',
            'is_active': true,
            'created_at': now
                .subtract(const Duration(days: 15))
                .toIso8601String(),
            'last_used_at': now
                .subtract(const Duration(minutes: 30))
                .toIso8601String(),
          },
          {
            'id': '3',
            'name': 'Test Environment',
            'key': 'test_${now.millisecondsSinceEpoch}_env',
            'description': 'Test ortamı için API anahtarı',
            'is_active': false,
            'created_at': now
                .subtract(const Duration(days: 60))
                .toIso8601String(),
            'last_used_at': now
                .subtract(const Duration(days: 10))
                .toIso8601String(),
          },
          {
            'id': '4',
            'name': 'Web Dashboard',
            'key': 'web_${now.millisecondsSinceEpoch}_dash',
            'description': 'Web dashboard için API anahtarı',
            'is_active': true,
            'created_at': now
                .subtract(const Duration(days: 45))
                .toIso8601String(),
            'last_used_at': now
                .subtract(const Duration(hours: 1))
                .toIso8601String(),
          },
        ],
        'settings': {
          'require_https': true,
          'cors_enabled': true,
          'requests_per_minute': 60,
          'requests_per_hour': 10000,
          'requests_per_month': 500000,
          'total_requests': 145678,
          'successful_requests': 142341,
          'failed_requests': 3337,
          'allowed_ips': 'Sınırsız',
        },
      };
    }
  }

  // --- _loadCouriers ---
  Future<List<Map<String, dynamic>>> _loadCouriers() async {
    try {
      // 20260803000006 ile profiles üzerinde authenticated SELECT
      // policy'si kaldırıldı; ayrıca email/role/delivered_count
      // sütunları grant'sız. SECURITY DEFINER admin_list_couriers
      // RPC üzerinden alıyoruz.
      final response = await Supabase.instance.client.rpc<List<dynamic>>(
        'admin_list_couriers',
      );

      final couriers = List<Map<String, dynamic>>.from(response);

      // Her kurye için toplam kazancı ve bekleyen kazancı hesapla
      for (var courier in couriers) {
        try {
          // Ödenmiş kazançlar
          final paidEarningsResponse = await Supabase.instance.client
              .from('courier_earnings')
              .select('amount')
              .eq('courier_id', courier['id'])
              .eq('status', 'paid');

          final totalPaidEarnings = (paidEarningsResponse as List).fold<double>(
            0,
            (sum, e) => sum + ((e['amount'] as num?)?.toDouble() ?? 0),
          );
          courier['total_earnings'] = totalPaidEarnings;

          // Bekleyen kazançlar (alacak)
          final pendingEarningsResponse = await Supabase.instance.client
              .from('courier_earnings')
              .select('amount')
              .eq('courier_id', courier['id'])
              .eq('status', 'pending');

          final totalPendingEarnings = (pendingEarningsResponse as List)
              .fold<double>(
                0,
                (sum, e) => sum + ((e['amount'] as num?)?.toDouble() ?? 0),
              );
          courier['pending_earnings'] = totalPendingEarnings;
        } catch (e) {
          courier['total_earnings'] = 0.0;
          courier['pending_earnings'] = 0.0;
        }
      }

      // Evrak durumunu (varsa) tek sorguyla eşleştir.
      try {
        final courierIds = couriers.map((c) => c['id']).toList();
        if (courierIds.isNotEmpty) {
          final docs = await Supabase.instance.client
              .from('courier_documents')
              .select('courier_id, status')
              .inFilter('courier_id', courierIds);
          final statusById = <String, String>{
            for (final d in List<Map<String, dynamic>>.from(docs))
              d['courier_id'] as String: d['status'] as String,
          };
          for (var courier in couriers) {
            courier['document_status'] = statusById[courier['id']];
          }
        }
      } catch (e) {
        debugPrint('Kurye evrak durumu yüklenirken hata: $e');
      }

      return couriers;
    } catch (e) {
      debugPrint('Kuryeler yüklenirken hata: $e');
      return [];
    }
  }

  // --- _loadCourierPayouts ---
  Future<List<Map<String, dynamic>>> _loadCourierPayouts() async {
    try {
      final response = await Supabase.instance.client
          .from('courier_payout_requests')
          .select('''
            id,
            amount,
            status,
            requested_at,
            approved_at,
            courier_id,
            profiles:courier_id(full_name, username)
          ''')
          .order('requested_at', ascending: false)
          .limit(50);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Kurye odeme istekleri yuklenirken hata: $e');
      return [];
    }
  }
}
