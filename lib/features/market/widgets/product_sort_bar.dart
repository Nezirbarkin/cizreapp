import 'package:flutter/material.dart';
import '../../../core/models/product_model.dart';

/// Dükkan ürün listesinin sıralaması.
///
/// [recommended] sunucunun verdiği sırayı korur (satıcının sabitledikleri
/// önce, sonra en yeniler); diğerleri istemcide yeniden sıralar.
enum ProductSort { recommended, newest, priceAsc, priceDesc }

extension ProductSortX on ProductSort {
  bool get isPrice =>
      this == ProductSort.priceAsc || this == ProductSort.priceDesc;

  String get label => switch (this) {
    ProductSort.recommended => 'Önerilen',
    ProductSort.newest => 'En yeni',
    ProductSort.priceAsc => 'Fiyat: düşükten yükseğe',
    ProductSort.priceDesc => 'Fiyat: yüksekten düşüğe',
  };
}

/// [products]'ı [sort]'a göre sıralanmış YENİ bir listede döndürür; girdi
/// listesine dokunmaz.
///
/// Fiyat, kartta yazan fiyattır: [priceOf] verilmezse
/// [Product.listingPrice] (indirimli fiyat, dijitalde liste fiyatı); ekran
/// flaş fiyatını da hesaba katmak için kendi fonksiyonunu verir. Eşit
/// değerlerde gelen sıra korunur (Dart'ın `sort`'u kararlı değildir).
List<Product> sortProducts(
  List<Product> products,
  ProductSort sort, {
  double Function(Product product)? priceOf,
}) {
  if (sort == ProductSort.recommended) return List<Product>.of(products);
  final price = priceOf ?? (Product p) => p.listingPrice;
  final indexed = products.indexed.toList();
  indexed.sort((a, b) {
    final int byKey;
    switch (sort) {
      case ProductSort.newest:
        byKey = b.$2.createdAt.compareTo(a.$2.createdAt);
      case ProductSort.priceAsc:
        byKey = price(a.$2).compareTo(price(b.$2));
      case ProductSort.priceDesc:
        byKey = price(b.$2).compareTo(price(a.$2));
      case ProductSort.recommended:
        byKey = 0;
    }
    return byKey != 0 ? byKey : a.$1.compareTo(b.$1);
  });
  return [for (final entry in indexed) entry.$2];
}

/// Ürün başlığının yanına sığan, ikonlu sıralama seçici: üç ayrı kare düğme.
///
/// Seçili düğme dolu renkle öne çıkar; seçili düğmeye yeniden dokunmak
/// [ProductSort.recommended]'a döner. Seçilen sıralamanın adı
/// ([ProductSortX.label]) başlığın altında gösterilmek üzere dışarıda kalır.
class ProductSortBar extends StatelessWidget {
  final ProductSort value;
  final ValueChanged<ProductSort> onChanged;

  const ProductSortBar({
    super.key,
    required this.value,
    required this.onChanged,
  });

  static const double buttonSize = 38;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _button(
          context,
          sort: ProductSort.newest,
          icon: const Icon(Icons.auto_awesome_outlined, size: 21),
        ),
        const SizedBox(width: 6),
        _button(
          context,
          sort: ProductSort.priceAsc,
          icon: const _PriceArrowIcon(up: true),
        ),
        const SizedBox(width: 6),
        _button(
          context,
          sort: ProductSort.priceDesc,
          icon: const _PriceArrowIcon(up: false),
        ),
      ],
    );
  }

  Widget _button(
    BuildContext context, {
    required ProductSort sort,
    required Widget icon,
  }) {
    final selected = value == sort;
    final primary = Theme.of(context).colorScheme.primary;
    final fg = selected ? Colors.white : Colors.grey.shade800;
    void tap() => onChanged(selected ? ProductSort.recommended : sort);
    return Tooltip(
      message: selected ? '${sort.label} (kaldırmak için dokunun)' : sort.label,
      // İçerideki "₺" metni okunmasın diye alt anlamlar dışlanır; bu InkWell'in
      // dokunma eylemini de sildiği için eylem burada yeniden verilir.
      child: Semantics(
        button: true,
        selected: selected,
        label: sort.label,
        onTap: tap,
        excludeSemantics: true,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(11),
            onTap: tap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOut,
              width: buttonSize,
              height: buttonSize,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: selected ? primary : Colors.white,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: selected ? primary : Colors.grey.shade300,
                ),
                boxShadow: selected
                    ? [
                        BoxShadow(
                          color: primary.withValues(alpha: 0.30),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: IconTheme.merge(
                data: IconThemeData(color: fg),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: fg),
                  child: icon,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "₺" ve yön oku: fiyat sıralamasının ikonu.
class _PriceArrowIcon extends StatelessWidget {
  final bool up;

  const _PriceArrowIcon({required this.up});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text(
          '₺',
          style: TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.w800,
            height: 1,
          ),
        ),
        Icon(
          up ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
          size: 16,
        ),
      ],
    );
  }
}
