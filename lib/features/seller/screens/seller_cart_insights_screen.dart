import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../market/widgets/shop_card.dart' show formatShopMoney;
import '../models/cart_insights.dart';
import '../services/cart_insights_service.dart';

/// Satıcı "Sepet Takibi" ekranı (Görev 3.3).
///
/// Ürünlerini sepetine ekleyen müşterilerin SAYILARINI gösterir (kim olduğu
/// değil). Bir ürüne buradan indirim uygulanınca, o ürünü sepetinde tutan
/// müşterilere otomatik bildirim gider (sunucu tetikleyicisi; müşteri başına
/// ürün başına günde en fazla bir kez).
class SellerCartInsightsScreen extends StatefulWidget {
  const SellerCartInsightsScreen({super.key, required this.shopId, this.service, this.now});

  final String shopId;
  final CartInsightsService? service;

  /// Testler için sabit saat.
  final DateTime Function()? now;

  static const List<int> discountSteps = [5, 10, 15, 20, 25, 30];

  @override
  State<SellerCartInsightsScreen> createState() => _SellerCartInsightsScreenState();
}

class _SellerCartInsightsScreenState extends State<SellerCartInsightsScreen> {
  late final CartInsightsService _service = widget.service ?? CartInsightsService();

  ShopCartStats? _stats;
  String? _error;
  bool _loading = true;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _stats == null;
      _error = null;
    });
    try {
      final stats = await _service.fetchStats(widget.shopId);
      if (!mounted) return;
      setState(() {
        _stats = stats;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Sepet istatistiği yüklenemedi: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Sepet istatistiği yüklenemedi.';
      });
    }
  }

  Future<void> _openDiscount(CartProductStat product) async {
    final percent = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => _DiscountSheet(product: product),
    );
    if (percent == null || !mounted) return;
    try {
      final updated = await _service.applyPercentDiscount(product.productId, percent.toDouble());
      if (!mounted) return;
      _snack(
        updated > 0
            ? 'İndirim uygulandı. Sepetinde bu ürün olan müşterilere bildirim gönderildi.'
            : 'İndirim uygulanamadı: bu oran ürünün fiyatını düşürmüyor.',
      );
      await _load();
    } catch (e) {
      debugPrint('İndirim uygulanamadı: $e');
      if (mounted) _snack('İndirim uygulanamadı. Lütfen tekrar deneyin.');
    }
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(title: const Text('Sepet Takibi')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _StatTile(
                              icon: Icons.people_alt_rounded,
                              value: '${stats!.users}',
                              label: 'Müşteri',
                              color: const Color(0xFF6366F1),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _StatTile(
                              icon: Icons.inventory_2_rounded,
                              value: '${stats.productCount}',
                              label: 'Ürün',
                              color: const Color(0xFF0EA5E9),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _StatTile(
                              icon: Icons.payments_rounded,
                              value: formatShopMoney(stats.value),
                              label: 'Sepette bekleyen',
                              color: const Color(0xFF16A34A),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFFF7ED),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFFED7AA)),
                        ),
                        child: const Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(Icons.notifications_active_outlined, color: Color(0xFFEA580C)),
                            SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                'Bir ürüne indirim yaptığında, o ürünü sepetinde tutan müşterilere '
                                'otomatik bildirim gider (müşteri başına ürün başına günde en fazla '
                                'bir kez). Müşterilerin kimliği gizlidir; yalnızca sayılarını görürsün.',
                                style: TextStyle(fontSize: 12.5, height: 1.4, color: Color(0xFF7C2D12)),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                      if (stats.isEmpty)
                        const _EmptyState()
                      else
                        for (final product in stats.products)
                          _ProductTile(
                            product: product,
                            now: _now,
                            onDiscount: product.isDigital || !product.isAvailable
                                ? null
                                : () => _openDiscount(product),
                          ),
                    ],
                  ),
                ),
    );
  }
}

String _ago(DateTime? time, DateTime now) {
  if (time == null) return '';
  final diff = now.toUtc().difference(time.toUtc());
  if (diff.inMinutes < 1) return 'az önce';
  if (diff.inMinutes < 60) return '${diff.inMinutes} dk önce';
  if (diff.inHours < 24) return '${diff.inHours} sa önce';
  if (diff.inDays == 1) return 'dün';
  return '${diff.inDays} gün önce';
}

class _ProductTile extends StatelessWidget {
  const _ProductTile({required this.product, required this.now, required this.onDiscount});

  final CartProductStat product;
  final DateTime now;
  final VoidCallback? onDiscount;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: product.image == null
                      ? ColoredBox(
                          color: Colors.grey.shade100,
                          child: Icon(Icons.shopping_bag_outlined, color: Colors.grey.shade400),
                        )
                      : CachedNetworkImage(
                          imageUrl: product.image!,
                          fit: BoxFit.cover,
                          memCacheWidth: 168,
                          errorWidget: (_, __, ___) => ColoredBox(
                            color: Colors.grey.shade100,
                            child: Icon(Icons.image_not_supported_outlined, color: Colors.grey.shade400),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.name,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        if (product.hasDiscount) ...[
                          Text(
                            formatShopMoney(product.price),
                            style: TextStyle(
                              color: Colors.grey.shade500,
                              decoration: TextDecoration.lineThrough,
                              fontSize: 12.5,
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Text(
                          formatShopMoney(product.effectivePrice),
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: product.hasDiscount ? const Color(0xFFDC2626) : const Color(0xFF111827),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              const Icon(Icons.shopping_cart_rounded, size: 16, color: Color(0xFF6366F1)),
              const SizedBox(width: 5),
              Text(
                '${product.users} müşterinin sepetinde · ${product.quantity} adet',
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ],
          ),
          if (product.lastAddedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                'Son eklenme: ${_ago(product.lastAddedAt, now)}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
              ),
            ),
          if (product.notifiedUsers > 0)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                'İndirim bildirimi: ${_ago(product.lastNotifiedAt, now)} · ${product.notifiedUsers} kişi',
                style: const TextStyle(color: Color(0xFF16A34A), fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerRight,
            child: onDiscount == null
                ? Text(
                    product.isDigital ? 'Dijital üründe indirim buradan yapılmaz' : 'Ürün satışta değil',
                    style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                  )
                : FilledButton.icon(
                    onPressed: onDiscount,
                    icon: const Icon(Icons.local_offer_rounded, size: 18),
                    label: const Text('İndirim Yap'),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFEA580C),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

/// İndirim oranı seçimi: yeni fiyat ve kaç müşteriye bildirim gideceği önizlenir.
class _DiscountSheet extends StatefulWidget {
  const _DiscountSheet({required this.product});

  final CartProductStat product;

  @override
  State<_DiscountSheet> createState() => _DiscountSheetState();
}

class _DiscountSheetState extends State<_DiscountSheet> {
  int _percent = 10;

  @override
  Widget build(BuildContext context) {
    final product = widget.product;
    final newPrice = product.priceAfterPercent(_percent.toDouble());
    final lowers = product.percentLowersPrice(_percent.toDouble());
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 14),
            const Text('İndirim uygula', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
            const SizedBox(height: 2),
            Text(product.name, maxLines: 1, overflow: TextOverflow.ellipsis,
                style: TextStyle(color: Colors.grey.shade700)),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final step in SellerCartInsightsScreen.discountSteps)
                  ChoiceChip(
                    label: Text('%$step'),
                    selected: step == _percent,
                    onSelected: (_) => setState(() => _percent = step),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              'Yeni fiyat: ${formatShopMoney(newPrice)} (şimdi ${formatShopMoney(product.effectivePrice)})',
              style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 6),
            Text(
              lowers
                  ? 'Sepetinde bu ürün olan ${product.users} müşteriye bildirim gidecek '
                      '(son 24 saatte bildirim alanlara tekrar gönderilmez).'
                  : 'Bu oran mevcut fiyatı düşürmüyor; daha yüksek bir oran seç.',
              style: TextStyle(
                fontSize: 13,
                color: lowers ? Colors.grey.shade700 : Colors.orange.shade800,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: lowers ? () => Navigator.pop(context, _percent) : null,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFFEA580C),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: const Text('İndirimi Uygula'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.icon, required this.value, required this.label, required this.color});

  final IconData icon;
  final String value;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          ),
          Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(
        children: [
          Icon(Icons.remove_shopping_cart_outlined, size: 56, color: Colors.grey.shade400),
          const SizedBox(height: 12),
          const Text(
            'Henüz müşterilerinin sepetinde ürünün yok.',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Müşteriler ürünlerini sepetine ekledikçe burada görünecek.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.cloud_off_rounded, size: 48, color: Colors.grey),
          const SizedBox(height: 12),
          Text(message),
          const SizedBox(height: 12),
          FilledButton(onPressed: onRetry, child: const Text('Tekrar dene')),
        ],
      ),
    );
  }
}
