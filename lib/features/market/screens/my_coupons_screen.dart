import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'shop_detail_screen.dart';

/// Bilet kartının alt (kod) bölümünün sabit yüksekliği.
/// Kenar çentikleri ve kesikli çizgi bu değere göre konumlanır.
const double _kTicketFooterHeight = 54;

/// Müşteri tarafında tüm satıcıların aktif kuponlarını listeleyen ekran.
///
/// `shop_coupons` tablosunun RLS politikası (shop_coupons_select) herkesin
/// `is_active = true` kayıtları görmesine izin verir, bu yüzden misafir
/// dahil her kullanıcı bu ekranı görebilir.
///
/// Tüm renkler `ThemeProvider`'ın ürettiği aktif temadan (primary renk +
/// açık/koyu mod) türetilir; ekranda sabit kodlanmış marka rengi yoktur.
class MyCouponsScreen extends StatefulWidget {
  const MyCouponsScreen({super.key});

  @override
  State<MyCouponsScreen> createState() => _MyCouponsScreenState();
}

enum _CouponFilter { all, expiringSoon, percentage, amount }

class _MyCouponsScreenState extends State<MyCouponsScreen> {
  List<_CouponItem> _coupons = [];
  bool _isLoading = true;
  String? _error;
  _CouponFilter _filter = _CouponFilter.all;

  @override
  void initState() {
    super.initState();
    _loadCoupons();
  }

  List<_CouponItem> get _visibleCoupons {
    switch (_filter) {
      case _CouponFilter.all:
        return _coupons;
      case _CouponFilter.expiringSoon:
        return _coupons.where((c) => c.isExpiringSoon).toList();
      case _CouponFilter.percentage:
        return _coupons.where((c) => c.isPercentage).toList();
      case _CouponFilter.amount:
        return _coupons.where((c) => !c.isPercentage).toList();
    }
  }

  Future<void> _loadCoupons() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final now = DateTime.now().toUtc().toIso8601String();
      final response = await Supabase.instance.client
          .from('shop_coupons')
          .select('*, shops!inner(id, name, logo_url, is_active)')
          .eq('is_active', true)
          .eq('shops.is_active', true)
          .or('end_date.is.null,end_date.gte.$now')
          .or('start_date.is.null,start_date.lte.$now')
          .order('created_at', ascending: false);

      // usage_limit ile usage_count karşılaştırması PostgREST'te iki kolon
      // arasında yapılamadığı için kotası dolan kuponları burada eliyoruz.
      final coupons = List<Map<String, dynamic>>.from(response)
          .map(_CouponItem.fromRow)
          .where((c) => !c.isSoldOut)
          .toList();

      if (mounted) {
        setState(() {
          _coupons = coupons;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ KUPONLARIM: yükleme hatası: $e');
      if (mounted) {
        setState(() {
          _error = 'Kuponlar yüklenirken bir hata oluştu';
          _isLoading = false;
        });
      }
    }
  }

  void _copyCode(String code) {
    HapticFeedback.lightImpact();
    Clipboard.setData(ClipboardData(text: code));

    final theme = Theme.of(context);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle_rounded, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$code kopyalandı',
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                    ),
                    const Text(
                      'Sepetteki indirim kutusuna yapıştırın',
                      style: TextStyle(fontSize: 11.5, color: Colors.white70),
                    ),
                  ],
                ),
              ),
            ],
          ),
          backgroundColor: theme.colorScheme.primary,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          margin: const EdgeInsets.all(12),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final visible = _visibleCoupons;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Kuponlarım',
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        centerTitle: true,
        // Tema renginin tam tonu: gradyan/şeffaflık yok, M3'ün yüzey
        // tint'i ve scrolled-under gölgesi kapalı — bar hiç solmuyor.
        backgroundColor: primary,
        foregroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        systemOverlayStyle: SystemUiOverlayStyle.light.copyWith(
          statusBarColor: primary,
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        actionsIconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            onPressed: _isLoading ? null : _loadCoupons,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _isLoading
          ? const _CouponSkeletonList()
          : _error != null
              ? _buildErrorState(theme)
              : RefreshIndicator(
                  color: primary,
                  onRefresh: _loadCoupons,
                  child: CustomScrollView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    slivers: [
                      SliverToBoxAdapter(child: _buildHeaderBanner(theme)),
                      if (_coupons.isNotEmpty)
                        SliverToBoxAdapter(child: _buildFilterBar(theme)),
                      if (visible.isEmpty)
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: _buildEmptyState(theme),
                        )
                      else
                        SliverPadding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          sliver: SliverList.builder(
                            itemCount: visible.length,
                            itemBuilder: (context, index) =>
                                _buildCouponCard(visible[index], theme),
                          ),
                        ),
                    ],
                  ),
                ),
    );
  }

  // ---------------------------------------------------------------- header

  Widget _buildHeaderBanner(ThemeData theme) {
    final primary = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            primary.withValues(alpha: isDark ? 0.28 : 0.14),
            primary.withValues(alpha: isDark ? 0.10 : 0.04),
          ],
        ),
        border: Border.all(color: primary.withValues(alpha: 0.20)),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: primary,
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Icon(
              Icons.local_activity_rounded,
              color: Colors.white,
              size: 24,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _coupons.isEmpty
                      ? 'Kullanılabilir kupon yok'
                      : '${_coupons.length} kupon seni bekliyor',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Kodu kopyala, sepette indirim kutusuna yapıştır.',
                  style: theme.textTheme.bodySmall?.copyWith(fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterBar(ThemeData theme) {
    const labels = {
      _CouponFilter.all: 'Tümü',
      _CouponFilter.expiringSoon: 'Yakında bitiyor',
      _CouponFilter.percentage: 'Yüzde indirim',
      _CouponFilter.amount: 'Tutar indirimi',
    };

    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        children: [
          for (final entry in labels.entries) ...[
            _FilterChipButton(
              label: entry.key == _CouponFilter.all
                  ? entry.value
                  : '${entry.value} (${_countFor(entry.key)})',
              selected: _filter == entry.key,
              onTap: () => setState(() => _filter = entry.key),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }

  int _countFor(_CouponFilter filter) {
    switch (filter) {
      case _CouponFilter.all:
        return _coupons.length;
      case _CouponFilter.expiringSoon:
        return _coupons.where((c) => c.isExpiringSoon).length;
      case _CouponFilter.percentage:
        return _coupons.where((c) => c.isPercentage).length;
      case _CouponFilter.amount:
        return _coupons.where((c) => !c.isPercentage).length;
    }
  }

  // ----------------------------------------------------------- boş / hata

  Widget _buildErrorState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.error.withValues(alpha: 0.10),
              ),
              child: Icon(
                Icons.wifi_off_rounded,
                size: 40,
                color: theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 18),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium?.copyWith(fontSize: 15),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _loadCoupons,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Tekrar Dene'),
              style: FilledButton.styleFrom(
                backgroundColor: theme.colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    final primary = theme.colorScheme.primary;
    final filtered = _filter != _CouponFilter.all && _coupons.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 40, 32, 60),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 110,
            height: 110,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: primary.withValues(alpha: 0.10),
            ),
            child: Icon(
              Icons.confirmation_number_outlined,
              size: 52,
              color: primary.withValues(alpha: 0.75),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            filtered ? 'Bu filtrede kupon yok' : 'Şu anda aktif kupon yok',
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            filtered
                ? 'Diğer filtrelere göz atabilirsin.'
                : 'Satıcılar kupon oluşturduğunda burada görünecek.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(fontSize: 13),
          ),
          if (filtered) ...[
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => setState(() => _filter = _CouponFilter.all),
              style: TextButton.styleFrom(foregroundColor: primary),
              child: const Text('Tüm kuponları göster'),
            ),
          ],
        ],
      ),
    );
  }

  // ------------------------------------------------------------ kupon kartı

  Widget _buildCouponCard(_CouponItem coupon, ThemeData theme) {
    final primary = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final onSurfaceSoft = theme.colorScheme.onSurface.withValues(alpha: 0.62);

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: PhysicalShape(
        clipper: const _TicketClipper(notchFromBottom: _kTicketFooterHeight),
        clipBehavior: Clip.antiAlias,
        color: surface,
        elevation: isDark ? 0 : 3,
        shadowColor: primary.withValues(alpha: 0.22),
        child: Material(
          color: Colors.transparent,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: coupon.shopId == null
                    ? null
                    : () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                ShopDetailScreen(shopId: coupon.shopId!),
                          ),
                        ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildShopRow(coupon, theme, onSurfaceSoft),
                      const SizedBox(height: 12),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildDiscountBadge(coupon, primary),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _buildDetails(coupon, theme, onSurfaceSoft),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              _buildCodeFooter(coupon, theme),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShopRow(
    _CouponItem coupon,
    ThemeData theme,
    Color onSurfaceSoft,
  ) {
    final placeholder = Container(
      width: 34,
      height: 34,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.07),
      child: Icon(Icons.storefront_rounded, size: 17, color: onSurfaceSoft),
    );

    return Row(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: coupon.shopLogo != null && coupon.shopLogo!.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: coupon.shopLogo!,
                  width: 34,
                  height: 34,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => placeholder,
                  errorWidget: (context, url, error) => placeholder,
                )
              : placeholder,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            coupon.shopName,
            style: theme.textTheme.titleSmall?.copyWith(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (coupon.shopId != null) ...[
          Text(
            'Mağaza',
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 11.5,
              color: onSurfaceSoft,
            ),
          ),
          const SizedBox(width: 2),
          Icon(Icons.chevron_right_rounded, size: 18, color: onSurfaceSoft),
        ],
      ],
    );
  }

  Widget _buildDiscountBadge(_CouponItem coupon, Color primary) {
    return Container(
      width: 92,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            primary.withValues(alpha: 0.20),
            primary.withValues(alpha: 0.06),
          ],
        ),
        border: Border.all(color: primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              coupon.discountLabel,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                height: 1.1,
                color: primary,
              ),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'İNDİRİM',
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
              color: primary.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetails(
    _CouponItem coupon,
    ThemeData theme,
    Color onSurfaceSoft,
  ) {
    final badges = <Widget>[];

    if (coupon.minOrder > 0) {
      badges.add(_InfoPill(
        icon: Icons.shopping_bag_outlined,
        label: 'Min. ₺${coupon.minOrder.toStringAsFixed(0)}',
      ));
    }
    if (coupon.isPercentage && coupon.maxDiscount != null) {
      badges.add(_InfoPill(
        icon: Icons.trending_down_rounded,
        label: 'Max ₺${coupon.maxDiscount!.toStringAsFixed(0)}',
      ));
    }
    if (coupon.remainingLabel != null) {
      badges.add(_InfoPill(
        icon: Icons.schedule_rounded,
        label: coupon.remainingLabel!,
        highlighted: coupon.isExpiringSoon,
      ));
    } else {
      badges.add(const _InfoPill(
        icon: Icons.all_inclusive_rounded,
        label: 'Süresiz',
      ));
    }
    if (coupon.remainingUsage != null && coupon.remainingUsage! <= 20) {
      badges.add(_InfoPill(
        icon: Icons.local_fire_department_rounded,
        label: 'Son ${coupon.remainingUsage} adet',
        highlighted: true,
      ));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (coupon.title.isNotEmpty)
          Text(
            coupon.title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              height: 1.25,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        if (coupon.description != null && coupon.description!.isNotEmpty) ...[
          const SizedBox(height: 3),
          Text(
            coupon.description!,
            style: theme.textTheme.bodySmall?.copyWith(
              fontSize: 12,
              color: onSurfaceSoft,
              height: 1.3,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: badges),
      ],
    );
  }

  Widget _buildCodeFooter(_CouponItem coupon, ThemeData theme) {
    final primary = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;

    return SizedBox(
      height: _kTicketFooterHeight,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: primary.withValues(alpha: isDark ? 0.16 : 0.07),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18),
              child: CustomPaint(
                size: const Size(double.infinity, 1),
                painter: _DashedLinePainter(
                  color: primary.withValues(alpha: 0.45),
                ),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  const SizedBox(width: 14),
                  Icon(
                    Icons.confirmation_number_rounded,
                    size: 17,
                    color: primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      coupon.code,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.4,
                        color: primary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Material(
                      color: primary,
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => _copyCode(coupon.code),
                        child: const Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.copy_rounded,
                                size: 14,
                                color: Colors.white,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Kopyala',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- modeller

/// `shop_coupons` satırının ekranda kullanılan alanlarını tipli hale getirir.
class _CouponItem {
  const _CouponItem({
    required this.id,
    required this.code,
    required this.title,
    required this.description,
    required this.isPercentage,
    required this.discountValue,
    required this.minOrder,
    required this.maxDiscount,
    required this.endDate,
    required this.usageLimit,
    required this.usageCount,
    required this.shopId,
    required this.shopName,
    required this.shopLogo,
  });

  final String id;
  final String code;
  final String title;
  final String? description;
  final bool isPercentage;
  final double discountValue;
  final double minOrder;
  final double? maxDiscount;
  final DateTime? endDate;
  final int? usageLimit;
  final int usageCount;
  final String? shopId;
  final String shopName;
  final String? shopLogo;

  factory _CouponItem.fromRow(Map<String, dynamic> row) {
    final shop = row['shops'] as Map<String, dynamic>?;
    return _CouponItem(
      id: row['id'].toString(),
      code: row['code'] as String? ?? '',
      title: row['title'] as String? ?? '',
      description: row['description'] as String?,
      isPercentage: (row['discount_type'] as String?) == 'percentage',
      discountValue: (row['discount_value'] as num?)?.toDouble() ?? 0,
      minOrder: (row['minimum_order_amount'] as num?)?.toDouble() ?? 0,
      maxDiscount: (row['maximum_discount_amount'] as num?)?.toDouble(),
      endDate: row['end_date'] != null
          ? DateTime.tryParse(row['end_date'].toString())?.toLocal()
          : null,
      usageLimit: (row['usage_limit'] as num?)?.toInt(),
      usageCount: (row['usage_count'] as num?)?.toInt() ?? 0,
      shopId: shop?['id'] as String?,
      shopName: shop?['name'] as String? ?? 'Mağaza',
      shopLogo: shop?['logo_url'] as String?,
    );
  }

  /// Rozet üzerindeki büyük indirim etiketi: "%20" veya "₺100".
  String get discountLabel => isPercentage
      ? '%${discountValue.toStringAsFixed(0)}'
      : '₺${discountValue.toStringAsFixed(0)}';

  /// Toplam kullanım kotası dolmuşsa kupon artık kullanılamaz.
  bool get isSoldOut => usageLimit != null && usageCount >= usageLimit!;

  /// Kalan kullanım hakkı (limit yoksa null).
  int? get remainingUsage {
    if (usageLimit == null) return null;
    final left = usageLimit! - usageCount;
    return left < 0 ? 0 : left;
  }

  Duration? get remaining {
    if (endDate == null) return null;
    final diff = endDate!.difference(DateTime.now());
    return diff.isNegative ? Duration.zero : diff;
  }

  bool get isExpiringSoon {
    final r = remaining;
    return r != null && r.inDays < 3;
  }

  String? get remainingLabel {
    final r = remaining;
    if (r == null) return null;
    if (r.inDays >= 1) return '${r.inDays} gün kaldı';
    if (r.inHours >= 1) return '${r.inHours} saat kaldı';
    if (r.inMinutes >= 1) return '${r.inMinutes} dk kaldı';
    return 'Son dakikalar';
  }
}

// ---------------------------------------------------------------- parçalar

/// Kupon kartındaki küçük bilgi etiketi (min tutar, kalan süre, stok...).
class _InfoPill extends StatelessWidget {
  const _InfoPill({
    required this.icon,
    required this.label,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;

  /// Aciliyet vurgusu (son gün / son adetler) — tema error rengini kullanır.
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = highlighted
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface.withValues(alpha: 0.65);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// Filtre çubuğundaki tema renkli seçim butonu.
class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return Material(
      color: selected ? primary : primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: selected ? Colors.white : primary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Bilet kenarındaki yarım daire çentikleri ve yuvarlak köşeleri çizen clipper.
/// [notchFromBottom] kartın altından çentik merkezine olan mesafedir.
class _TicketClipper extends CustomClipper<Path> {
  const _TicketClipper({required this.notchFromBottom});

  /// Kartın altından çentik merkezine olan mesafe.
  final double notchFromBottom;

  /// Köşe yuvarlaklığı ve kenar çentiğinin yarıçapı.
  static const double radius = 20;
  static const double notchRadius = 11;

  @override
  Path getClip(Size size) {
    const r = radius;
    const nr = notchRadius;
    final ny = size.height - notchFromBottom;

    return Path()
      ..moveTo(r, 0)
      ..lineTo(size.width - r, 0)
      ..arcToPoint(Offset(size.width, r), radius: Radius.circular(r))
      ..lineTo(size.width, ny - nr)
      ..arcToPoint(
        Offset(size.width, ny + nr),
        radius: Radius.circular(nr),
        clockwise: false,
      )
      ..lineTo(size.width, size.height - r)
      ..arcToPoint(Offset(size.width - r, size.height), radius: Radius.circular(r))
      ..lineTo(r, size.height)
      ..arcToPoint(Offset(0, size.height - r), radius: Radius.circular(r))
      ..lineTo(0, ny + nr)
      ..arcToPoint(
        Offset(0, ny - nr),
        radius: Radius.circular(nr),
        clockwise: false,
      )
      ..lineTo(0, r)
      ..arcToPoint(Offset(r, 0), radius: Radius.circular(r))
      ..close();
  }

  @override
  bool shouldReclip(_TicketClipper oldClipper) =>
      oldClipper.notchFromBottom != notchFromBottom;
}

/// İki çentik arasındaki perforasyon (kesikli) çizgisi.
class _DashedLinePainter extends CustomPainter {
  const _DashedLinePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    const dashWidth = 6.0;
    const dashGap = 5.0;
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    var x = 0.0;
    while (x < size.width) {
      final end = (x + dashWidth).clamp(0.0, size.width);
      canvas.drawLine(Offset(x, 0), Offset(end, 0), paint);
      x += dashWidth + dashGap;
    }
  }

  @override
  bool shouldRepaint(_DashedLinePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Yükleme sırasında gösterilen, tema rengiyle nabız atan iskelet kartlar.
class _CouponSkeletonList extends StatefulWidget {
  const _CouponSkeletonList();

  @override
  State<_CouponSkeletonList> createState() => _CouponSkeletonListState();
}

class _CouponSkeletonListState extends State<_CouponSkeletonList>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;
    final isDark = theme.brightness == Brightness.dark;
    final surface = isDark ? const Color(0xFF1E1E1E) : Colors.white;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      itemCount: 4,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final t = 0.35 + (_controller.value * 0.45);
            return Opacity(opacity: t, child: child);
          },
          child: PhysicalShape(
            clipper: const _TicketClipper(notchFromBottom: _kTicketFooterHeight),
            clipBehavior: Clip.antiAlias,
            color: surface,
            elevation: isDark ? 0 : 2,
            shadowColor: primary.withValues(alpha: 0.15),
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const _SkeletonBox(width: 92, height: 74, radius: 14),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: const [
                            _SkeletonBox(width: 140, height: 13),
                            SizedBox(height: 8),
                            _SkeletonBox(width: double.infinity, height: 11),
                            SizedBox(height: 6),
                            _SkeletonBox(width: 180, height: 11),
                            SizedBox(height: 12),
                            _SkeletonBox(width: 110, height: 18, radius: 8),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  height: _kTicketFooterHeight,
                  color: primary.withValues(alpha: isDark ? 0.16 : 0.07),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkeletonBox extends StatelessWidget {
  const _SkeletonBox({
    required this.width,
    required this.height,
    this.radius = 6,
  });

  final double width;
  final double height;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
