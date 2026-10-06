import 'package:flutter/material.dart';

import '../../../core/models/product_model.dart';
import '../../../core/models/sponsorship_model.dart';
import '../../market/services/product_service.dart';
import '../../market/widgets/shop_card.dart' show formatShopMoney;
import '../../wallet/screens/topup_screen.dart';
import '../services/sponsorship_service.dart';

/// Satıcı "Öne Çıkar" ekranı (Görev 3.2).
///
/// Mağazayı ya da bir ürünü seçilen süre boyunca bir listenin en üstüne,
/// "Sponsor" etiketiyle taşır. Ücret bakiyeden düşülür (sunucu kilitleyip
/// düşer); bakiye yetmezse bakiye yükleme ekranına yönlendirir.
class SellerSponsorshipScreen extends StatefulWidget {
  const SellerSponsorshipScreen({
    super.key,
    required this.shopId,
    this.shopName,
    this.service,
    this.productLoader,
    this.now,
  });

  final String shopId;
  final String? shopName;
  final SponsorshipService? service;

  /// Testler için: mağazanın ürünleri (varsayılan [ProductService.getShopProducts]).
  final Future<List<Product>> Function(String shopId)? productLoader;

  /// Testler için sabit saat.
  final DateTime Function()? now;

  static const Color accent = Color(0xFFF59E0B);

  @override
  State<SellerSponsorshipScreen> createState() => _SellerSponsorshipScreenState();
}

class _SellerSponsorshipScreenState extends State<SellerSponsorshipScreen> {
  late final SponsorshipService _service = widget.service ?? SponsorshipService();

  List<SponsorshipPackage> _packages = const [];
  List<ShopSponsorship> _history = const [];
  List<Product> _products = const [];
  double? _balance;
  bool _loading = true;
  String? _error;
  String? _busyPackageId;
  String? _selectedProductId;

  DateTime get _now => (widget.now ?? DateTime.now)();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = _packages.isEmpty;
      _error = null;
    });
    try {
      final results = await Future.wait<Object?>([
        _service.fetchPackages(),
        _service.fetchShopSponsorships(widget.shopId),
        (widget.productLoader ?? ProductService().getShopProducts)(widget.shopId),
        _service.fetchMyBalance(),
      ]);
      if (!mounted) return;
      final products = results[2] as List<Product>;
      setState(() {
        _packages = results[0] as List<SponsorshipPackage>;
        _history = results[1] as List<ShopSponsorship>;
        _products = products;
        _balance = results[3] as double;
        if (_selectedProductId != null && !products.any((p) => p.id == _selectedProductId)) {
          _selectedProductId = null;
        }
        _selectedProductId ??= products.isEmpty ? null : products.first.id;
        _loading = false;
      });
    } catch (e) {
      debugPrint('Öne çıkarma bilgileri yüklenemedi: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Öne çıkarma bilgileri yüklenemedi.';
      });
    }
  }

  Product? get _selectedProduct {
    for (final p in _products) {
      if (p.id == _selectedProductId) return p;
    }
    return null;
  }

  List<SponsorshipPackage> _packagesFor(SponsorPlacement placement) =>
      _packages.where((p) => p.placement == placement).toList()
        ..sort((a, b) => a.sortOrder != b.sortOrder
            ? a.sortOrder.compareTo(b.sortOrder)
            : a.durationDays.compareTo(b.durationDays));

  /// Bu vitrin + hedef için süren ya da sıradaki öne çıkarmaların son bitişi.
  DateTime? _currentUntil(SponsorPlacement placement, String? productId) {
    DateTime? until;
    for (final s in _history) {
      if (s.placement != placement || s.productId != productId) continue;
      if (!(s.isRunning(_now) || s.isQueued(_now))) continue;
      final end = s.endsAt;
      if (end != null && (until == null || end.isAfter(until))) until = end;
    }
    return until;
  }

  bool _hasPending(SponsorPlacement placement, String? productId) => _history.any(
    (s) => s.placement == placement && s.productId == productId && s.status == SponsorshipStatus.pending,
  );

  // ------------------------------------------------------------ satın alma

  Future<void> _buy(SponsorshipPackage package) async {
    final placement = package.placement;
    final product = placement.isProduct ? _selectedProduct : null;
    if (placement.isProduct && product == null) {
      _snack('Önce öne çıkaracağın ürünü seç.');
      return;
    }
    final target = product?.name ?? widget.shopName ?? 'Mağazan';
    final until = _currentUntil(placement, product?.id);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Öne çıkarmayı onayla'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(target, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            const SizedBox(height: 4),
            Text('${placement.label} · ${package.name} (${package.durationDays} gün)'),
            const SizedBox(height: 12),
            Text(
              'Ücret: ${formatShopMoney(package.price)} — bakiyenden düşülür.',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            if (until != null) ...[
              const SizedBox(height: 8),
              Text(
                'Süren öne çıkarman ${_formatDate(until)} tarihinde bitince başlar.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(backgroundColor: SellerSponsorshipScreen.accent),
            child: const Text('Satın Al'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _busyPackageId = package.id);
    SponsorshipPurchase? result;
    SponsorshipException? failure;
    try {
      result = await _service.purchase(
        shopId: widget.shopId,
        packageId: package.id,
        productId: product?.id,
      );
    } on SponsorshipException catch (e) {
      failure = e;
    } catch (e) {
      debugPrint('Öne çıkarma satın alınamadı: $e');
      failure = const SponsorshipException(
        SponsorshipFailure.unknown,
        'Öne çıkarma satın alınamadı. Lütfen tekrar deneyin.',
      );
    }
    if (!mounted) return;
    // Düğmedeki bekleme halkası, sonuç penceresi açılmadan kalkar.
    setState(() => _busyPackageId = null);

    if (failure != null) {
      if (failure.reason == SponsorshipFailure.insufficientBalance) {
        await _showInsufficientBalance(package);
      } else {
        _snack(failure.message);
      }
      return;
    }

    final done = result!;
    setState(() => _balance = done.balanceAfter);
    _snack(
      done.status == SponsorshipStatus.pending
          ? 'Talebin alındı; onaylanınca yayına girecek.'
          : 'Öne çıkarıldı! ${done.endsAt == null ? '' : '${_formatDate(done.endsAt!)} tarihine kadar en üstte.'}',
    );
    await _load();
  }

  Future<void> _showInsufficientBalance(SponsorshipPackage package) async {
    final topUp = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Bakiye yetersiz'),
        content: Text(
          'Bu paket ${formatShopMoney(package.price)}; bakiyen '
          '${formatShopMoney(_balance ?? 0)}. Bakiye yükleyip tekrar deneyebilirsin.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Vazgeç')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Bakiye Yükle')),
        ],
      ),
    );
    if (topUp == true && mounted) await _openTopUp();
  }

  Future<void> _openTopUp() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => const TopupScreen()));
    if (mounted) await _load();
  }

  Future<void> _pickProduct() async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        maxChildSize: 0.9,
        builder: (context, controller) => Column(
          children: [
            const SizedBox(height: 12),
            const Text('Ürün seç', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            Expanded(
              child: ListView.builder(
                controller: controller,
                itemCount: _products.length,
                itemBuilder: (context, i) {
                  final p = _products[i];
                  return ListTile(
                    selected: p.id == _selectedProductId,
                    title: Text(p.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text(
                      p.hasDiscount
                          ? '${formatShopMoney(p.effectivePrice)} · indirimde'
                          : formatShopMoney(p.effectivePrice),
                    ),
                    trailing: p.hasDiscount
                        ? const Icon(Icons.local_offer_outlined, color: Colors.redAccent)
                        : null,
                    onTap: () => Navigator.pop(sheetContext, p.id),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _selectedProductId = picked);
  }

  void _snack(String text) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), behavior: SnackBarBehavior.floating));
  }

  // ------------------------------------------------------------------ UI

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF7F6FB),
      appBar: AppBar(title: const Text('Öne Çıkar')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? _ErrorState(message: _error!, onRetry: _load)
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    children: [
                      _BalanceCard(balance: _balance ?? 0, onTopUp: _openTopUp),
                      const SizedBox(height: 14),
                      Text(
                        'Öne çıkan mağaza ya da ürün, seçtiğin süre boyunca listenin en '
                        'üstünde "Sponsor" etiketiyle görünür. Ücret bakiyenden düşülür, süre '
                        'dolunca kendiliğinden biter. Aynı vitrini tekrar alırsan süren öne '
                        'çıkarmanın bitişine eklenir.',
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 13, height: 1.4),
                      ),
                      const SizedBox(height: 20),
                      const _SectionTitle(icon: Icons.storefront_rounded, text: 'Mağazanı öne çıkar'),
                      for (final placement in const [SponsorPlacement.shopList, SponsorPlacement.shopCategory])
                        _placementCard(placement, productId: null),
                      const SizedBox(height: 12),
                      const _SectionTitle(icon: Icons.shopping_bag_rounded, text: 'Ürününü öne çıkar'),
                      _productSelector(),
                      for (final placement in const [SponsorPlacement.productCategory, SponsorPlacement.productDiscount])
                        _placementCard(placement, productId: _selectedProductId),
                      const SizedBox(height: 12),
                      const _SectionTitle(icon: Icons.history_rounded, text: 'Geçmiş'),
                      if (_history.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Text(
                            'Henüz öne çıkarma satın almadın.',
                            style: TextStyle(color: Colors.grey.shade600),
                          ),
                        )
                      else
                        for (final s in _history) _historyTile(s),
                    ],
                  ),
                ),
    );
  }

  Widget _productSelector() {
    final product = _selectedProduct;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.grey.shade200),
      ),
      child: ListTile(
        leading: const Icon(Icons.inventory_2_outlined),
        title: Text(
          product?.name ?? (_products.isEmpty ? 'Mağazanda satışta ürün yok' : 'Ürün seç'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: product == null
            ? null
            : Text(product.hasDiscount ? 'İndirimde' : 'İndirimsiz'),
        trailing: _products.isEmpty ? null : const Icon(Icons.expand_more),
        onTap: _products.isEmpty ? null : _pickProduct,
      ),
    );
  }

  Widget _placementCard(SponsorPlacement placement, {required String? productId}) {
    final packages = _packagesFor(placement);
    final product = placement.isProduct ? _selectedProduct : null;
    final String? blocker = switch (placement) {
      SponsorPlacement.productCategory || SponsorPlacement.productDiscount when product == null =>
        'Önce bir ürün seç.',
      SponsorPlacement.productDiscount when !(product?.hasDiscount ?? false) =>
        'Bu ürün indirimde değil. İndirim tanımla (eski fiyat / indirimli fiyat), sonra öne çıkar.',
      _ => null,
    };
    final until = _currentUntil(placement, placement.isProduct ? productId : null);
    final pending = _hasPending(placement, placement.isProduct ? productId : null);

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: until != null ? SellerSponsorshipScreen.accent : Colors.grey.shade200,
          width: until != null ? 1.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  placement.label,
                  style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                ),
                const Spacer(),
                if (until != null)
                  _StatusPill(
                    text: 'Yayında · ${_formatDate(until)}',
                    color: const Color(0xFF16A34A),
                  )
                else if (pending)
                  const _StatusPill(text: 'Onay bekliyor', color: Color(0xFF6366F1)),
              ],
            ),
            const SizedBox(height: 4),
            Text(placement.description, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
            const SizedBox(height: 12),
            if (blocker != null)
              Text(blocker, style: TextStyle(color: Colors.orange.shade800, fontSize: 12.5))
            else if (packages.isEmpty)
              Text('Bu vitrin için şu an paket yok.', style: TextStyle(color: Colors.grey.shade600))
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final package in packages)
                    _PackageButton(
                      package: package,
                      busy: _busyPackageId == package.id,
                      onTap: _busyPackageId == null ? () => _buy(package) : null,
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _historyTile(ShopSponsorship s) {
    final now = _now;
    final productName = s.productId == null
        ? null
        : _products.where((p) => p.id == s.productId).map((p) => p.name).firstOrNull;
    final label = s.statusLabel(now);
    final color = switch (label) {
      'Yayında' => const Color(0xFF16A34A),
      'Sırada' => const Color(0xFF0EA5E9),
      'Onay bekliyor' => const Color(0xFF6366F1),
      'Reddedildi' || 'İptal edildi' => const Color(0xFFDC2626),
      _ => Colors.grey.shade600,
    };
    final start = s.startsAt, end = s.endsAt;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(
            s.placement.isProduct ? Icons.shopping_bag_outlined : Icons.storefront_outlined,
            color: Colors.grey.shade600,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${s.placement.label} · ${s.packageName}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                if (productName != null)
                  Text(productName, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.grey.shade700, fontSize: 12.5)),
                Text(
                  start != null && end != null
                      ? '${_formatDate(start)} – ${_formatDate(end)}'
                      : 'Satın alındı: ${_formatDate(s.createdAt)}',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(formatShopMoney(s.pricePaid), style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 4),
              _StatusPill(text: label, color: color),
            ],
          ),
        ],
      ),
    );
  }

  static const List<String> _months = [
    'Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara',
  ];

  static String _formatDate(DateTime time) {
    final t = time.toLocal();
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '${t.day} ${_months[t.month - 1]} $hh:$mm';
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance, required this.onTopUp});

  final double balance;
  final VoidCallback onTopUp;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 14, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          colors: [Color(0xFFF59E0B), Color(0xFFEA580C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: const [BoxShadow(color: Color(0x33EA580C), blurRadius: 12, offset: Offset(0, 4))],
      ),
      child: Row(
        children: [
          const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Bakiyen', style: TextStyle(color: Colors.white70, fontSize: 12.5)),
                Text(
                  formatShopMoney(balance),
                  style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          FilledButton.tonal(
            onPressed: onTopUp,
            style: FilledButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFFEA580C),
            ),
            child: const Text('Bakiye Yükle'),
          ),
        ],
      ),
    );
  }
}

class _PackageButton extends StatelessWidget {
  const _PackageButton({required this.package, required this.busy, required this.onTap});

  final SponsorshipPackage package;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF9A3412),
        side: const BorderSide(color: SellerSponsorshipScreen.accent),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      ),
      child: busy
          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(package.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                Text(
                  '${package.durationDays} gün · ${formatShopMoney(package.price)}',
                  style: const TextStyle(fontSize: 12),
                ),
              ],
            ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text,
        style: TextStyle(color: color, fontSize: 11.5, fontWeight: FontWeight.w700),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 20, color: const Color(0xFF9A3412)),
          const SizedBox(width: 8),
          Text(text, style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.w800)),
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
