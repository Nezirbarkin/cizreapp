// ignore_for_file: deprecated_member_use, avoid_print

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/shop_model.dart';
import '../services/shop_service.dart';
import 'shop_detail_screen.dart';

class AllShopsScreen extends StatefulWidget {
  final List<Shop>? initialShops;

  const AllShopsScreen({super.key, this.initialShops});

  @override
  State<AllShopsScreen> createState() => _AllShopsScreenState();
}

class _AllShopsScreenState extends State<AllShopsScreen> {
  bool _globalOrdersEnabled = true;
  List<Shop> _shops = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    
    // İlk dükkanları yükle (varsa)
    if (widget.initialShops != null && widget.initialShops!.isNotEmpty) {
      _shops = List<Shop>.from(widget.initialShops!);
      _sortShops();
      _isLoading = false;
    }
    
    _loadData();
  }

  void _sortShops() {
    _shops.sort((a, b) {
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;
      return b.createdAt.compareTo(a.createdAt);
    });
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    
    try {
      // Global sipariş durumunu yükle
      final settingsResponse = await Supabase.instance.client
          .from('app_about_settings')
          .select('global_orders_enabled')
          .maybeSingle();
      
      if (settingsResponse != null && mounted) {
        setState(() {
          _globalOrdersEnabled = settingsResponse['global_orders_enabled'] as bool? ?? true;
        });
      }

      // Tüm dükkanları bağımsız olarak yükle
      final shopService = ShopService();
      final shops = await shopService.getShops();
      
      if (mounted) {
        setState(() {
          _shops = shops;
          _sortShops();
          _isLoading = false;
          _error = null;
        });
      }
    } catch (e) {
      print('AllShopsScreen: Dükkanlar yüklenirken hata: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _error = e.toString();
        });
      }
    }
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            const Text(
              'Tüm Dükkanlar',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 8),
            if (!_isLoading && _shops.isNotEmpty)
              Text(
                '${_shops.length}',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                ),
              ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              ),
            )
          else if (_error != null)
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadData,
              tooltip: 'Tekrar Dene',
            ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Dükkanlar yükleniyor...'),
          ],
        ),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              'Hata: $_error',
              style: const TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh),
              label: const Text('Tekrar Dene'),
            ),
          ],
        ),
      );
    }

    if (_shops.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.store_outlined, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'Henüz dükkan bulunmuyor',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _shops.length,
      itemBuilder: (context, index) {
        final shop = _shops[index];
        return _buildShopCard(context, shop);
      },
    );
  }

  Widget _buildShopCard(BuildContext context, Shop shop) {
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
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: shop.isPinned
                ? Colors.amber.shade400
                : (isOrdersClosed ? Colors.red.shade100 : Colors.grey.shade100),
            width: 1,
          ),
        ),
        child: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => ShopDetailScreen(shopId: shop.id),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
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
                              Expanded(
                                child: Wrap(
                                  spacing: 6,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        shop.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 14,
                                        ),
                                      ),
                                    ),
                                    if (shop.isVerified) ...[
                                      const Icon(
                                        Icons.verified,
                                        size: 16,
                                        color: Colors.blue,
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            shop.description ?? '',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Icon(Icons.star, size: 14, color: Colors.amber.shade600),
                              const SizedBox(width: 3),
                              Text(
                                shop.rating.toStringAsFixed(1),
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 11,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Icon(Icons.local_shipping, size: 14, color: Colors.grey.shade600),
                              const SizedBox(width: 3),
                              Text(
                                shop.deliveryFee > 0
                                    ? '${shop.deliveryFee.toStringAsFixed(0)}₺'
                                    : 'Ücretsiz',
                                style: TextStyle(
                                  color: shop.deliveryFee > 0
                                      ? Colors.grey.shade600
                                      : Colors.green.shade600,
                                  fontSize: 11,
                                  fontWeight: shop.deliveryFee == 0 ? FontWeight.w600 : null,
                                ),
                              ),
                              if (shop.minOrderAmount > 0) ...[
                                const SizedBox(width: 8),
                                Icon(Icons.shopping_cart, size: 14, color: Colors.grey.shade600),
                                const SizedBox(width: 3),
                                Text(
                                  'Min ${shop.minOrderAmount.toStringAsFixed(0)}₺',
                                  style: TextStyle(
                                    color: Colors.grey.shade600,
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Geçici Kapalı banner
                if (isOrdersClosed) ...[


                  const SizedBox(height: 8),
                  Container(
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
                ],
              ],
            ),
          ),
        ),
      ),
        // Sağ üst köşe - Pinned yıldızı + Açık/Kapalı + Kupon
        Positioned(
          top: 4,
          right: 4,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Açık/Kapalı badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: shop.isOpen ? Colors.green : Colors.red,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.15),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      shop.isOpen ? Icons.storefront : Icons.store,
                      size: 10,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      shop.isOpen ? 'Açık' : 'Kapalı',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              // Kupon badge (varsa)
              FutureBuilder<int>(
                future: _getActiveCouponCount(shop.id),
                builder: (context, snapshot) {
                  if (snapshot.hasData && snapshot.data! > 0) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.purple.shade500,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.purple.withOpacity(0.3),
                            blurRadius: 4,
                            offset: const Offset(0, 1),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            '🎟',
                            style: TextStyle(fontSize: 10),
                          ),
                          const SizedBox(width: 2),
                          const Text(
                            'Kupon Var',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return const SizedBox.shrink();
                },
              ),
              const SizedBox(width: 4),
              // Pinned yıldızı
              if (shop.isPinned)
                Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.amber,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.2),
                        blurRadius: 3,
                        offset: const Offset(0, 1),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.star,
                    size: 10,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
        ),
        ],
      ),
    );
  }
}

class _BlinkingCouponBadge extends StatelessWidget {
  const _BlinkingCouponBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.purple.shade500,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.local_offer, size: 9, color: Colors.white),
          const SizedBox(width: 2),
          const Text(
            'Kupon Var',
            style: TextStyle(
              color: Colors.white,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}
