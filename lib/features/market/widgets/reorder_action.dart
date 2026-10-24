import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/models/order_model.dart';
import '../providers/cart_provider.dart';
import '../screens/cart_screen.dart';
import '../screens/product_detail_screen.dart';
import '../services/reorder_service.dart';

/// "Tekrar sipariş ver": sipariş kalemlerini sepete ekler ve özeti gösterir
/// (eklenenler, satıştan kalkanlar, seçenek gerektirenler, fiyatı değişenler).
Future<void> runReorder(
  BuildContext context,
  List<OrderItem> items, {
  ReorderService? service,
}) async {
  final cart = context.read<CartProvider>();
  final navigator = Navigator.of(context);
  final messenger = ScaffoldMessenger.of(context);

  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const Center(child: CircularProgressIndicator()),
  );
  ReorderResult result;
  try {
    result = await (service ?? ReorderService()).reorder(items, cart);
  } catch (e) {
    navigator.pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('Ürünler sepete eklenemedi, tekrar deneyin')),
    );
    return;
  }
  navigator.pop();
  if (!context.mounted) return;

  if (result.ordersClosed) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Şu an sipariş alınmıyor, daha sonra tekrar deneyin')),
    );
    return;
  }

  await showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (sheetContext) => ReorderSummarySheet(
      result: result,
      onGoToCart: () {
        Navigator.pop(sheetContext);
        navigator.push(MaterialPageRoute(builder: (_) => const CartScreen()));
      },
      onOpenProduct: (productId) {
        Navigator.pop(sheetContext);
        navigator.push(
          MaterialPageRoute(builder: (_) => ProductDetailScreen(productId: productId)),
        );
      },
    ),
  );
}

class ReorderSummarySheet extends StatelessWidget {
  const ReorderSummarySheet({
    super.key,
    required this.result,
    required this.onGoToCart,
    required this.onOpenProduct,
  });

  final ReorderResult result;
  final VoidCallback onGoToCart;
  final ValueChanged<String> onOpenProduct;

  @override
  Widget build(BuildContext context) {
    final plan = result.plan;
    final added = result.added;
    final title = added.isEmpty
        ? 'Sepete eklenemedi'
        : '${added.length} ürün sepete eklendi';

    Widget section(IconData icon, Color color, String text) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(child: Text(text, style: const TextStyle(fontSize: 13.5, height: 1.35))),
            ],
          ),
        );

    final reduced = added.where((l) => l.reducedFrom != null).toList();

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  added.isEmpty ? Icons.remove_shopping_cart_outlined : Icons.shopping_cart_checkout,
                  color: added.isEmpty ? Colors.orange : Colors.green,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            if (added.isNotEmpty)
              section(Icons.check_circle_outline, Colors.green,
                  added.map((l) => '${l.quantity} × ${l.name}').join(', ')),
            if (reduced.isNotEmpty)
              section(Icons.tune, Colors.blueGrey,
                  'Adet sınırı yüzünden azaltıldı: ${reduced.map((l) => '${l.name} (${l.reducedFrom} → ${l.quantity})').join(', ')}'),
            if (plan.priceChanged.isNotEmpty)
              section(Icons.sell_outlined, Colors.deepOrange,
                  'Fiyatı değişti: ${plan.priceChanged.join(', ')}'),
            if (plan.unavailable.isNotEmpty)
              section(Icons.block, Colors.red, 'Artık satışta değil: ${plan.unavailable.join(', ')}'),
            if (plan.alreadyInCart.isNotEmpty)
              section(Icons.shopping_cart_outlined, Colors.blueGrey,
                  'Sepetinde zaten en fazla adette: ${plan.alreadyInCart.join(', ')}'),
            if (result.failed.isNotEmpty)
              section(Icons.error_outline, Colors.red, 'Eklenemedi: ${result.failed.join(', ')}'),
            if (plan.needsOptions.isNotEmpty) ...[
              section(Icons.style_outlined, Colors.indigo,
                  'Beden/renk seçimi gerekiyor — ürüne dokunup seç:'),
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  for (final p in plan.needsOptions)
                    ActionChip(
                      label: Text(p.name, overflow: TextOverflow.ellipsis),
                      onPressed: () => onOpenProduct(p.id),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Kapat'),
                  ),
                ),
                if (added.isNotEmpty) ...[
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: onGoToCart,
                      icon: const Icon(Icons.shopping_cart),
                      label: const Text('Sepete git'),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
