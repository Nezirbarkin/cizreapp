// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/category_model.dart';
import '../../../core/models/shop_model.dart';
import '../services/shop_service.dart';
import 'shop_detail_screen.dart';

class CategoryShopsScreen extends StatefulWidget {
  final Category category;

  const CategoryShopsScreen({super.key, required this.category});

  @override
  State<CategoryShopsScreen> createState() => _CategoryShopsScreenState();
}

class _CategoryShopsScreenState extends State<CategoryShopsScreen> {
  final ShopService _shopService = ShopService();
  List<Shop> _shops = [];
  bool _isLoading = true;
  bool _globalOrdersEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadShops();
  }

  Future<void> _loadShops() async {
    setState(() => _isLoading = true);

    try {
      // Global sipariş durumunu yükle
      try {
        final settingsResponse = await Supabase.instance.client
            .from('app_about_settings')
            .select('global_orders_enabled')
            .maybeSingle();
        
        if (settingsResponse != null) {
          _globalOrdersEnabled = settingsResponse['global_orders_enabled'] as bool? ?? true;
        }
      } catch (e) {
        debugPrint('Global sipariş durumu yüklenirken hata: $e');
      }
      
      final shops = await _shopService.getShopsByCategory(widget.category.id);
      // Sponsor dükkanları en üste sabitle
      shops.sort((a, b) {
        if (a.isPinned && !b.isPinned) return -1;
        if (!a.isPinned && b.isPinned) return 1;
        return b.createdAt.compareTo(a.createdAt);
      });
      setState(() {
        _shops = shops;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dükkanlar yüklenirken hata: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.primary,
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(20, 48, 20, 20),
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: Colors.white),
                  onPressed: () => Navigator.pop(context),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.category.name,
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w900,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        '${_shops.length} Dükkan',
                        style: TextStyle(
                          fontSize: 14,
                          // ignore: deprecated_member_use
                          color: Colors.white.withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(40),
                topRight: Radius.circular(40),
              ),
              child: Container(
                color: const Color(0xFFF5F7FA),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _shops.isEmpty
                        ? const Center(
                            child: Text('Bu kategoride henüz dükkan bulunmuyor'),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.all(20),
                            itemCount: _shops.length,
                            itemBuilder: (context, index) {
                              final shop = _shops[index];
                              return _buildShopCard(shop);
                            },
                          ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<int> _getActiveCouponCount(String shopId) async {
    int retryCount = 0;
    const maxRetries = 3;
    
    while (retryCount <= maxRetries) {
      try {
        final response = await Supabase.instance.client
            .from('shop_coupons')
            .select('id')
            .eq('shop_id', shopId)
            .eq('is_active', true)
            .timeout(
              const Duration(seconds: 5),
              onTimeout: () => throw TimeoutException('Kupon sayısı sorgusu zaman aşımına uğradı'),
            );
        return (response as List).length;
      } catch (e) {
        retryCount++;
        if (retryCount > maxRetries) {
          debugPrint('Kupon sayısı alınırken hata (max retry aşımı): $e');
          return 0;
        }
        // Exponential backoff ile yeniden dene
        await Future.delayed(Duration(milliseconds: 500 * retryCount));
      }
    }
    return 0;
  }

  Widget _buildShopCard(Shop shop) {
    final bool isOrdersClosed = !_globalOrdersEnabled || !shop.isAcceptingOrders;
    
    return Opacity(
      opacity: isOrdersClosed ? 0.55 : 1.0,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: shop.isPinned
                ? Colors.amber.shade400
                : (isOrdersClosed ? Colors.red.shade100 : Colors.grey.shade100),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ShopDetailScreen(shopId: shop.id),
              ),
            );
          },
          borderRadius: BorderRadius.circular(20),
          child: Column(
            children: [
              Stack(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                children: [
                  // Logo
                  Container(
                    width: 70,
                    height: 70,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(12),
                      image: shop.logoUrl != null
                          ? DecorationImage(
                              image: NetworkImage(shop.logoUrl!),
                              fit: BoxFit.cover,
                            )
                          : null,
                    ),
                    child: shop.logoUrl == null
                        ? const Icon(Icons.store, size: 32, color: Colors.grey)
                        : null,
                  ),
                  const SizedBox(width: 12),

                  // Bilgiler
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Flexible(
                                    child: Text(
                                      shop.name,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (shop.isVerified) ...[
                                    const SizedBox(width: 4),
                                    Icon(
                                      Icons.verified,
                                      size: 18,
                                      color: Colors.blue.shade600,
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          shop.description ?? '',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.grey.shade600,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Icon(Icons.star, size: 16, color: Colors.amber.shade600),
                            const SizedBox(width: 4),
                            Text(
                              shop.rating.toStringAsFixed(1),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Icon(Icons.delivery_dining, size: 16, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text(
                              shop.deliveryFee > 0 ? '₺${shop.deliveryFee.toStringAsFixed(0)}' : 'Ücretsiz',
                              style: TextStyle(
                                color: shop.deliveryFee > 0 ? Colors.orange.shade700 : Colors.green.shade700,
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Icon(Icons.shopping_bag_outlined, size: 16, color: Colors.grey.shade600),
                            const SizedBox(width: 4),
                            Text(
                              shop.minOrderAmount > 0 ? 'Min. ₺${shop.minOrderAmount.toStringAsFixed(0)}' : 'Min. yok',
                              style: TextStyle(
                                color: Colors.grey.shade700,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            
                    // Sağ üst köşe etiketleri
                    Positioned(
                      top: 8,
                      right: 8,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          // Açık/Kapalı etiketi
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: shop.isOpen ? Colors.green : Colors.red,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              shop.isOpen ? 'Açık' : 'Kapalı',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          // Kupon Var etiketi - yanıp sönen yazı
                          FutureBuilder<int>(
                            future: _getActiveCouponCount(shop.id),
                            builder: (context, snapshot) {
                              final couponCount = snapshot.data ?? 0;
                              if (couponCount > 0) {
                                return const _BlinkingCouponBadge();
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              // Geçici Kapalı banner
              if (isOrdersClosed) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.pause_circle_filled, size: 14, color: Colors.red.shade700),
                        const SizedBox(width: 6),
                        Text(
                          'Geçici Kapalı - Sipariş Alınmıyor',
                          style: TextStyle(
                            color: Colors.red.shade700,
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ),
          if (shop.isPinned)
            Positioned(
              top: -8,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.amber,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.star,
                  size: 12,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ignore: must_be_immutable
class _BlinkingCouponBadge extends StatelessWidget {
  const _BlinkingCouponBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF6B00), Color(0xFFFF8C00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.confirmation_number, size: 11, color: Colors.white),
          SizedBox(width: 3),
          Text(
            'Kupon Var',
            style: TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
