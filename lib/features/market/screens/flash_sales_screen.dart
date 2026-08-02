// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:provider/provider.dart';
import '../../../core/models/flash_sale_model.dart';
import '../providers/cart_provider.dart';
import '../services/flash_sale_service.dart';
import '../widgets/flash_sale_card.dart';
import '../widgets/flash_countdown_banner.dart';
import '../../market/screens/product_detail_screen.dart';
import '../../../shared/widgets/add_to_cart_fab.dart';

/// Tüm aktif flash satışları listeleyen ekran.
/// Üstte geri sayım banner'ı (en yakın biten sale için), altta grid.
class FlashSalesScreen extends StatefulWidget {
  const FlashSalesScreen({super.key});

  @override
  State<FlashSalesScreen> createState() => _FlashSalesScreenState();
}

class _FlashSalesScreenState extends State<FlashSalesScreen> {
  final _service = FlashSaleService();
  List<FlashSale> _sales = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final sales = await _service.getActiveFlashSales();
      if (!mounted) return;
      setState(() {
        _sales = sales;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Flash satışlar yüklenemedi';
        _loading = false;
      });
    }
  }

  DateTime? get _nearestEndAt {
    if (_sales.isEmpty) return null;
    return _sales
        .map((s) => s.endAt)
        .reduce((a, b) => a.isBefore(b) ? a : b);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text('⚡ Flash Satış'),
        backgroundColor: const Color(0xFFE53935),
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _errorView()
                : _sales.isEmpty
                    ? _emptyView()
                    : _content(),
      ),
    );
  }

  Widget _errorView() {
    return ListView(
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.error_outline, size: 60, color: Colors.grey),
        const SizedBox(height: 12),
        Center(
          child: Text(_error!, style: const TextStyle(color: Colors.grey)),
        ),
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Tekrar Dene'),
          ),
        ),
      ],
    );
  }

  Widget _emptyView() {
    return ListView(
      children: const [
        SizedBox(height: 80),
        Icon(Icons.flash_off, size: 60, color: Colors.grey),
        SizedBox(height: 12),
        Center(
          child: Text(
            'Şu an aktif flash satış yok',
            style: TextStyle(color: Colors.grey),
          ),
        ),
      ],
    );
  }

  Widget _content() {
    final nearestEnd = _nearestEndAt;
    return CustomScrollView(
      slivers: [
        if (nearestEnd != null)
          SliverToBoxAdapter(
            child: FlashCountdownBanner(
              endAt: nearestEnd,
              title: '⚡ Aktif Flash Satışlar',
              onTap: () {},
            ),
          ),
        SliverPadding(
          padding: const EdgeInsets.all(12),
          sliver: SliverGrid(
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: 0.55,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final sale = _sales[index];
                return FlashSaleCard(
                  sale: sale,
                  onTap: () => _openProduct(sale),
                  onAddToCart: () => _addToCart(sale),
                );
              },
              childCount: _sales.length,
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 24)),
      ],
    );
  }

  Future<void> _openProduct(FlashSale sale) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProductDetailScreen(productId: sale.productId),
      ),
    );
    // Geri dönünce listeyi tazele (stok değişmiş olabilir)
    _load();
  }

  Future<void> _addToCart(FlashSale sale) async {
    if (sale.isSoldOut) {
      _snack('Stok tükendi');
      return;
    }
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      _snack('Lütfen giriş yapın');
      return;
    }

    // 1) Önce stoğu atomik düş (claim). Başarısızsa kullanıcıya bildir ve çık.
    final claim = await _service.claimFlashSale(
      saleId: sale.id,
      quantity: 1,
    );
    if (!mounted) return;
    if (claim['success'] != true) {
      _snack(claim['error']?.toString() ?? 'Flaş stok alınamadı');
      return;
    }

    // 2) Stoğu başarıyla aldıysak, asıl sepet satırına da ekle.
    // Hata olursa claim'ı geri bırak (release).
    try {
      final cartProvider = context.read<CartProvider>();
      await cartProvider.addToCart(
        sale.productId,
        quantity: 1,
        flashSaleId: sale.id,
        flashPrice: sale.flashPrice,
      );
      if (!mounted) return;
      _snack('✅ Flaş satıştan sepete eklendi! Kalan: ${claim['remaining']}');
      // Liste stoklarını tazele
      _load();
    } catch (e) {
      // Sepete ekleme başarısız — claim'ı geri bırak
      try {
        await _service.releaseFlashSale(
          saleId: sale.id,
          quantity: 1,
        );
      } catch (releaseErr) {
        debugPrint('release_flash_sale hata: $releaseErr');
      }
      if (!mounted) return;
      _snack('Sepete eklenemedi: $e');
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
    );
  }
}

/// Ürün detayda / mağazada kullanılan küçük "Flash Aktif" rozeti.
class FlashSaleMiniBanner extends StatelessWidget {
  final FlashSale sale;
  const FlashSaleMiniBanner({super.key, required this.sale});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF5252), Color(0xFFE53935)],
        ),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.bolt, color: Colors.white, size: 14),
          const SizedBox(width: 4),
          Text(
            'Flash: ${sale.flashPrice.toStringAsFixed(2)} ₺',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}