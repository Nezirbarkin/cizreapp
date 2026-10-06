import 'package:flutter/material.dart';

import '../../../market/screens/live_host_screen.dart';
import '../../../market/widgets/shop_card.dart';
import '../../screens/coupons_screen.dart';
import '../../screens/seller_digital_orders_screen.dart';
import '../../screens/seller_flash_sales_screen.dart';
import '../../screens/seller_return_requests_screen.dart';
import '../../screens/seller_cart_insights_screen.dart';
import '../../screens/seller_reviews_screen.dart';
import '../../screens/seller_sponsorship_screen.dart';
import '../../screens/shop_settings_screen.dart';
import '../../screens/smm_provider_settings_screen.dart';

/// Panelin canlı mağaza bilgisi — sekmelerin iç Navigator'larındaki sayfalar
/// için. İç yığındaki bir sayfa (ör. "Diğer") yığın kurulurken yakalanan
/// değerlerle kalırdı; sipariş alma durumu ya da mağaza adı değişince menü
/// bayat görünürdü. Bu kapsam değişince bağımlı sayfalar yeniden çizilir.
class SellerPanelInfo extends InheritedWidget {
  const SellerPanelInfo({
    super.key,
    required this.shopInfo,
    required this.isAcceptingOrders,
    required super.child,
  });

  final Map<String, dynamic>? shopInfo;
  final bool isAcceptingOrders;

  static SellerPanelInfo? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SellerPanelInfo>();

  @override
  bool updateShouldNotify(SellerPanelInfo oldWidget) =>
      !identical(oldWidget.shopInfo, shopInfo) ||
      oldWidget.isAcceptingOrders != isAcceptingOrders;
}

/// Menü öğesini açar: sayfaysa [navigator]'a iter (dönüşte gerekiyorsa
/// [onReturnRefresh]), değilse eylemini [context] ile çalıştırır.
void openSellerMenuEntry({
  required BuildContext context,
  required NavigatorState navigator,
  required SellerMenuEntry entry,
  required VoidCallback onReturnRefresh,
}) {
  final page = entry.page;
  if (page == null) {
    entry.action?.call(context);
    return;
  }
  final done = navigator.push(MaterialPageRoute<void>(builder: page));
  if (entry.refreshOnReturn) done.then((_) => onReturnRefresh());
}

/// Satıcı menüsünün bir öğesi (Görev 2.4).
///
/// Menü iki yerde aynıdır: panelin "Diğer" sekmesi ve sağdan açılan yan
/// menü. Öğenin NASIL açılacağına menüyü barındıran karar verir (bkz.
/// [SellerMenu.onOpen]); öğe yalnızca ne açılacağını söyler.
class SellerMenuEntry {
  const SellerMenuEntry({
    required this.id,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    this.page,
    this.action,
    this.refreshOnReturn = false,
    this.requiresShop = false,
  }) : assert(page != null || action != null);

  final String id;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;

  /// Açılacak sayfa. Null ise [action] çalışır (ör. kategori penceresi).
  final WidgetBuilder? page;
  final void Function(BuildContext context)? action;

  /// Dönüşte panel verileri tazelensin mi? (eski Drawer davranışıyla aynı:
  /// Kuponlar/İade/Yorumlar/Mağaza Ayarları tazeler.)
  final bool refreshOnReturn;

  /// Mağaza kaydı olmadan açılamaz (mağaza kimliği gerekir).
  final bool requiresShop;
}

/// Menü içeriği: hızlı işlemler ızgarası + gruplu araç listeleri.
class SellerMenuContent {
  SellerMenuContent._({
    required this.quick,
    required this.sections,
  });

  /// Izgarada büyük kutucuk olarak gösterilen, en sık kullanılanlar.
  final List<SellerMenuEntry> quick;

  /// Başlıklı liste bölümleri.
  final List<({String title, List<SellerMenuEntry> entries})> sections;

  factory SellerMenuContent.forShop({
    required Map<String, dynamic>? shopInfo,
    required VoidCallback onManageCategories,
  }) {
    final shopId = shopInfo?['id'] as String?;
    final shopName = (shopInfo?['name'] as String?) ?? 'Mağazam';
    return SellerMenuContent._(
      quick: [
        SellerMenuEntry(
          id: 'coupons',
          icon: Icons.confirmation_number_outlined,
          title: 'Kuponlar',
          subtitle: 'İndirim kodları',
          color: const Color(0xFFF57C00),
          page: (_) => const CouponsScreen(),
          refreshOnReturn: true,
        ),
        SellerMenuEntry(
          id: 'flash',
          icon: Icons.flash_on,
          title: 'Flash Satış',
          subtitle: 'Süreli kampanya',
          color: const Color(0xFFE64A19),
          page: (_) => SellerFlashSalesScreen(shopId: shopId!),
          requiresShop: true,
        ),
        SellerMenuEntry(
          id: 'live',
          icon: Icons.live_tv,
          title: 'Canlı Yayın',
          subtitle: 'Canlı tanıt',
          color: const Color(0xFFD32F2F),
          page: (_) => LiveHostScreen(shopId: shopId!, shopName: shopName),
          requiresShop: true,
        ),
        SellerMenuEntry(
          id: 'returns',
          icon: Icons.assignment_return_outlined,
          title: 'İade Talepleri',
          subtitle: 'İade ve değişim',
          color: const Color(0xFF00897B),
          page: (_) => const SellerReturnRequestsScreen(),
          refreshOnReturn: true,
        ),
        SellerMenuEntry(
          id: 'reviews',
          icon: Icons.rate_review_outlined,
          title: 'Yorumlar',
          subtitle: 'Müşteri yorumları',
          color: const Color(0xFFF9A825),
          page: (_) => const SellerReviewsScreen(),
          refreshOnReturn: true,
        ),
        SellerMenuEntry(
          id: 'settings',
          icon: Icons.storefront_outlined,
          title: 'Mağaza Ayarları',
          subtitle: 'Teslimat, konum',
          color: const Color(0xFF3949AB),
          page: (_) => const ShopSettingsScreen(),
          refreshOnReturn: true,
        ),
      ],
      sections: [
        (
          title: 'Tanıtım',
          entries: [
            SellerMenuEntry(
              id: 'sponsorship',
              icon: Icons.rocket_launch_outlined,
              title: 'Öne Çıkar',
              subtitle: 'Sponsorlu vitrin: mağazanı ya da ürününü en üste taşı',
              color: const Color(0xFFF59E0B),
              page: (_) => SellerSponsorshipScreen(shopId: shopId!, shopName: shopName),
              requiresShop: true,
            ),
            SellerMenuEntry(
              id: 'cart_insights',
              icon: Icons.shopping_cart_checkout_rounded,
              title: 'Sepet Takibi',
              subtitle: 'Sepetteki ürünlerin; indirim yap, müşteriye bildirim gitsin',
              color: const Color(0xFF6366F1),
              page: (_) => SellerCartInsightsScreen(shopId: shopId!),
              requiresShop: true,
            ),
          ],
        ),
        (
          title: 'Ürün & Kategori',
          entries: [
            SellerMenuEntry(
              id: 'categories',
              icon: Icons.category_outlined,
              title: 'Kategori Ekle',
              subtitle: 'Mağaza kategorilerini düzenle',
              color: const Color(0xFF7E57C2),
              action: (_) => onManageCategories(),
            ),
          ],
        ),
        (
          title: 'Dijital & SMM',
          entries: [
            SellerMenuEntry(
              id: 'smm',
              icon: Icons.smart_toy_outlined,
              title: 'SMM Ayarları',
              subtitle: 'Sağlayıcı ve servis ayarları',
              color: const Color(0xFF5C6BC0),
              page: (_) => const SmmProviderSettingsScreen(),
            ),
            SellerMenuEntry(
              id: 'digital_orders',
              icon: Icons.list_alt_outlined,
              title: 'Dijital Siparişler',
              subtitle: 'SMM / dijital ürün siparişleri',
              color: const Color(0xFF26A69A),
              page: (_) => const SellerDigitalOrdersScreen(),
            ),
          ],
        ),
        (
          title: 'Destek',
          entries: [
            SellerMenuEntry(
              id: 'help',
              icon: Icons.help_outline,
              title: 'Yardım',
              subtitle: 'Sık sorulanlar ve destek',
              color: const Color(0xFF78909C),
              action: (context) => ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Yardım ekranı yakında eklenecek')),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// Panelin ana bölümleri (alt bardaki sekmeler) — yan menünün üstünde.
class SellerMenuSection {
  const SellerMenuSection({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;
}

/// Satıcı menüsü — "Diğer" sekmesi ve yan menü aynı tasarımı paylaşır.
class SellerMenu extends StatelessWidget {
  const SellerMenu({
    super.key,
    required this.shopInfo,
    required this.isAcceptingOrders,
    required this.content,
    required this.onOpen,
    this.sections = const [],
    this.currentSection,
    this.onSection,
    this.padding = const EdgeInsets.fromLTRB(16, 16, 16, 24),
  });

  final Map<String, dynamic>? shopInfo;
  final bool isAcceptingOrders;
  final SellerMenuContent content;

  /// Seçilen öğeyi açar (sekmede iç yığına, yan menüde "Diğer" sekmesine).
  final void Function(BuildContext context, SellerMenuEntry entry) onOpen;

  /// Yan menüde panel sekmeleri (alt bardakilerin aynısı); sekmede boş.
  final List<SellerMenuSection> sections;
  final int? currentSection;
  final ValueChanged<int>? onSection;
  final EdgeInsetsGeometry padding;

  void _open(BuildContext context, SellerMenuEntry entry) {
    if (entry.requiresShop && shopInfo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Önce mağaza oluşturmalısınız')),
      );
      return;
    }
    onOpen(context, entry);
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: padding,
      children: [
        _SellerMenuHeader(shopInfo: shopInfo, isAcceptingOrders: isAcceptingOrders),
        if (sections.isNotEmpty) ...[
          const SizedBox(height: 18),
          const _MenuLabel('Panel'),
          _SectionList(
            sections: sections,
            current: currentSection,
            onSelect: onSection,
          ),
        ],
        const SizedBox(height: 18),
        const _MenuLabel('Hızlı İşlemler'),
        _QuickGrid(
          entries: content.quick,
          onTap: (entry) => _open(context, entry),
        ),
        for (final section in content.sections) ...[
          const SizedBox(height: 18),
          _MenuLabel(section.title),
          _EntryList(
            entries: section.entries,
            onTap: (entry) => _open(context, entry),
          ),
        ],
      ],
    );
  }
}

class _MenuLabel extends StatelessWidget {
  const _MenuLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        // Türkçe büyük harf: i → İ, ı → I (Dart'ın toUpperCase'i dile duyarsız).
        text.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase(),
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.8,
          color: Colors.grey.shade600,
        ),
      ),
    );
  }
}

/// Mağaza kimlik kartı: logo, ad, sipariş alma durumu.
class _SellerMenuHeader extends StatelessWidget {
  const _SellerMenuHeader({
    required this.shopInfo,
    required this.isAcceptingOrders,
  });

  final Map<String, dynamic>? shopInfo;
  final bool isAcceptingOrders;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final name = (shopInfo?['name'] as String?) ?? 'Mağaza';
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primary,
            Color.alphaBlend(Colors.black.withValues(alpha: 0.28), primary),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: primary.withValues(alpha: 0.25),
            blurRadius: 14,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white.withValues(alpha: 0.7), width: 2),
              ),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: ShopLogoTile(
                  name: name,
                  logoUrl: shopInfo?['logo_url'] as String?,
                  size: 52,
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Mağazam',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                  const SizedBox(height: 8),
                  _StatusPill(open: isAcceptingOrders),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.open});

  final bool open;

  @override
  Widget build(BuildContext context) {
    final dot = open ? const Color(0xFF69F0AE) : const Color(0xFFFFCDD2);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              open ? 'Sipariş alıyor' : 'Siparişler kapalı',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Panel sekmeleri (yalnız yan menüde).
class _SectionList extends StatelessWidget {
  const _SectionList({
    required this.sections,
    required this.current,
    required this.onSelect,
  });

  final List<SellerMenuSection> sections;
  final int? current;
  final ValueChanged<int>? onSelect;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return _MenuCard(
      child: Column(
        children: [
          for (var i = 0; i < sections.length; i++)
            Material(
              color: i == current ? primary.withValues(alpha: 0.08) : Colors.transparent,
              child: ListTile(
                dense: true,
                leading: Icon(
                  sections[i].icon,
                  color: i == current ? primary : Colors.grey.shade600,
                ),
                title: Text(
                  sections[i].label,
                  style: TextStyle(
                    fontWeight: i == current ? FontWeight.w800 : FontWeight.w600,
                    color: i == current ? primary : null,
                  ),
                ),
                onTap: onSelect == null ? null : () => onSelect!(i),
              ),
            ),
        ],
      ),
    );
  }
}

/// Hızlı işlemler: üçlü satırlar; bir satırdaki kutucuklar aynı yükseklikte
/// (yazı büyütülse de taşmaz, satır uzar).
class _QuickGrid extends StatelessWidget {
  const _QuickGrid({required this.entries, required this.onTap});

  final List<SellerMenuEntry> entries;
  final ValueChanged<SellerMenuEntry> onTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final perRow = constraints.maxWidth >= 520 ? 4 : 3;
        final rows = <Widget>[];
        for (var i = 0; i < entries.length; i += perRow) {
          final chunk = entries.skip(i).take(perRow).toList();
          rows.add(
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : 10),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var j = 0; j < perRow; j++) ...[
                      if (j > 0) const SizedBox(width: 10),
                      Expanded(
                        child: j < chunk.length
                            ? _QuickTile(entry: chunk[j], onTap: () => onTap(chunk[j]))
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        }
        return Column(children: rows);
      },
    );
  }
}

class _QuickTile extends StatelessWidget {
  const _QuickTile({required this.entry, required this.onTap});

  final SellerMenuEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _MenuCard(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _IconChip(icon: entry.icon, color: entry.color, size: 44),
              const SizedBox(height: 10),
              Text(
                entry.title,
                textAlign: TextAlign.center,
                maxLines: 2,
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(
                entry.subtitle,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryList extends StatelessWidget {
  const _EntryList({required this.entries, required this.onTap});

  final List<SellerMenuEntry> entries;
  final ValueChanged<SellerMenuEntry> onTap;

  @override
  Widget build(BuildContext context) {
    return _MenuCard(
      child: Column(
        children: [
          for (var i = 0; i < entries.length; i++) ...[
            if (i > 0) Divider(height: 1, indent: 64, color: Colors.grey.shade200),
            ListTile(
              leading: _IconChip(icon: entries[i].icon, color: entries[i].color, size: 38),
              title: Text(
                entries[i].title,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                entries[i].subtitle,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
              onTap: () => onTap(entries[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _IconChip extends StatelessWidget {
  const _IconChip({required this.icon, required this.color, required this.size});

  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, color: color, size: size * 0.52),
    );
  }
}

/// Menü kartı kabuğu (SellerSectionCard'ın reçetesiyle aynı: çok hafif gölge
/// + ince kenarlık), içerik kenarlara kadar dokunulabilir.
class _MenuCard extends StatelessWidget {
  const _MenuCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.035),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
        border: Border.all(color: Colors.black.withValues(alpha: 0.07)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Material(color: Colors.transparent, child: child),
      ),
    );
  }
}
