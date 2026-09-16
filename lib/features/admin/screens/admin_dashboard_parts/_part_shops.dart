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
  // ==========================================================================
  // Dukkanlar + kart + ekleme/duzenleme/silme dialoglari
  // ==========================================================================

  // --- _buildShopsContent ---
  /// Dukkanlar ekrani. Ust bolum: baslik + aksiyonlar, ozet metrikler, arama,
  /// hizli filtreler ve siralama. Alt bolum: dukkan kartlari.
  ///
  /// Tasma notu: eski surumde baslik ile aksiyon butonlari tek bir `Row`
  /// icindeydi ve baslik esnek degildi; dar ekranda butonlar tasiyordu.
  /// Artik dar ekranda butonlar tam genislikte alt alta, genis ekranda
  /// esnek baslik + sabit butonlar seklinde diziliyor. Kart icindeki tum
  /// rozet/istatistik satirlari da Wrap ya da Expanded+FittedBox ile
  /// sinirlandirildi.
  Widget _buildShopsContent() {
    if (_isLoadingShops && _shopsDetailed.isEmpty) {
      _loadAndSetShops();
      return const Center(child: CircularProgressIndicator());
    }

    final shops = _shopsDetailed;
    final visible = _visibleShops(shops);

    return RefreshIndicator(
      onRefresh: _loadAndSetShops,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final isCompact = width < 720;
          final columns = width >= 1360 ? 3 : (width >= 900 ? 2 : 1);
          final rowCount = (visible.length / columns).ceil();

          return CustomScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            slivers: [
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildShopsToolbar(shops, isCompact),
                      const SizedBox(height: 16),
                      _buildShopsSummary(shops),
                      const SizedBox(height: 14),
                      _buildShopsSearchField(),
                      const SizedBox(height: 10),
                      _buildShopsFilterChips(shops),
                      const SizedBox(height: 10),
                      _buildShopsResultBar(shops.length, visible.length),
                    ],
                  ),
                ),
              ),
              if (visible.isEmpty)
                SliverToBoxAdapter(child: _buildShopsEmptyState(shops.isEmpty))
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, rowIndex) {
                      final start = rowIndex * columns;
                      if (columns == 1) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _buildShopCard(visible[start]),
                        );
                      }
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (var i = 0; i < columns; i++) ...[
                              if (i > 0) const SizedBox(width: 12),
                              Expanded(
                                child: start + i < visible.length
                                    ? _buildShopCard(visible[start + i])
                                    : const SizedBox.shrink(),
                              ),
                            ],
                          ],
                        ),
                      );
                    }, childCount: rowCount),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // --- _loadAndSetShops ---
  Future<void> _loadAndSetShops() async {
    setState(() {
      _isLoadingShops = true;
    });
    final shops = await _loadShopsWithDetails();
    if (mounted) {
      setState(() {
        _shopsDetailed = shops;
        _isLoadingShops = false;
      });
    }
  }

  // ==========================================================================
  // Filtre / arama / siralama
  // ==========================================================================

  // --- _shopMatchesFilter ---
  bool _shopMatchesFilter(Map<String, dynamic> shop, String filter) {
    switch (filter) {
      case 'pending':
        return !(shop['is_approved'] as bool? ?? false);
      case 'active':
        return shop['is_active'] as bool? ?? true;
      case 'passive':
        return !(shop['is_active'] as bool? ?? true);
      case 'pinned':
        return shop['is_pinned'] as bool? ?? false;
      case 'verified':
        return shop['is_verified'] as bool? ?? false;
      case 'admin_courier':
        return !(shop['has_own_courier'] as bool? ?? false);
      case 'overridden':
        return _isShopPricingOverridden(shop);
      default:
        return true;
    }
  }

  // --- _visibleShops ---
  /// Arama sorgusu + hizli filtre + siralama uygulanmis liste.
  List<Map<String, dynamic>> _visibleShops(List<Map<String, dynamic>> shops) {
    final query = _shopSearchQuery.trim().toLowerCase();

    final list = shops.where((shop) {
      if (!_shopMatchesFilter(shop, _shopFilter)) return false;
      if (query.isEmpty) return true;
      final fields = <dynamic>[
        shop['name'],
        shop['slug'],
        shop['description'],
        shop['profiles']?['full_name'],
        shop['profiles']?['username'],
        shop['profiles']?['email'],
      ];
      return fields.whereType<Object>().any(
        (value) => value.toString().toLowerCase().contains(query),
      );
    }).toList();

    int byName(Map<String, dynamic> a, Map<String, dynamic> b) =>
        (a['name']?.toString() ?? '').toLowerCase().compareTo(
          (b['name']?.toString() ?? '').toLowerCase(),
        );

    double money(Map<String, dynamic> shop, String key) =>
        (shop[key] as num?)?.toDouble() ?? 0;

    switch (_shopSort) {
      case 'name':
        list.sort(byName);
        break;
      case 'earnings':
        list.sort(
          (a, b) =>
              money(b, 'total_earnings').compareTo(money(a, 'total_earnings')),
        );
        break;
      case 'orders':
        list.sort(
          (a, b) => ((b['total_orders'] as num?) ?? 0).compareTo(
            (a['total_orders'] as num?) ?? 0,
          ),
        );
        break;
      case 'newest':
        list.sort((a, b) {
          final da =
              DateTime.tryParse(a['created_at']?.toString() ?? '') ??
              DateTime(1970);
          final db =
              DateTime.tryParse(b['created_at']?.toString() ?? '') ??
              DateTime(1970);
          return db.compareTo(da);
        });
        break;
      default:
        // Sabitlenenler once, sonra isim sirasi.
        list.sort((a, b) {
          final ap = (a['is_pinned'] as bool? ?? false) ? 0 : 1;
          final bp = (b['is_pinned'] as bool? ?? false) ? 0 : 1;
          if (ap != bp) return ap - bp;
          return byName(a, b);
        });
    }

    return list;
  }

  // --- _shopMoney ---
  /// Turkce bicimli para etiketi: 12345.6 -> "₺12.345,60".
  String _shopMoney(double value, {int decimals = 0}) {
    final fixed = value.abs().toStringAsFixed(decimals);
    final parts = fixed.split('.');
    final digits = parts.first;
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write('.');
      buffer.write(digits[i]);
    }
    final sign = value < 0 ? '-' : '';
    final frac = parts.length > 1 ? ',${parts[1]}' : '';
    return '$sign₺$buffer$frac';
  }

  // ==========================================================================
  // Ust bolum parcalari
  // ==========================================================================

  // --- _buildShopsToolbar ---
  Widget _buildShopsToolbar(List<Map<String, dynamic>> shops, bool isCompact) {
    final pending = shops
        .where((s) => !(s['is_approved'] as bool? ?? false))
        .length;

    final title = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Dükkan Yönetimi',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          pending > 0
              ? '${shops.length} dükkan • $pending tanesi onay bekliyor'
              : '${shops.length} dükkan • tümü onaylı',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w500,
            color: pending > 0 ? Colors.orange.shade800 : Colors.grey.shade600,
          ),
        ),
      ],
    );

    final pricingButton = OutlinedButton.icon(
      onPressed: _showShopPricingOverrideDialog,
      icon: const Icon(Icons.price_change_outlined, size: 18),
      label: const Text(
        'Teslimat & Min. Sepet',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.purple.shade700,
        side: BorderSide(color: Colors.purple.shade200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    final addButton = ElevatedButton.icon(
      onPressed: _showAddShopDialog,
      icon: const Icon(Icons.add, size: 20),
      label: const Text(
        'Yeni Dükkan',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: Colors.purple.shade600,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );

    if (isCompact) {
      // Dar ekranda butonlar tam genislikte alt alta -> tasma imkansiz.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          title,
          const SizedBox(height: 14),
          addButton,
          const SizedBox(height: 8),
          pricingButton,
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: title),
        const SizedBox(width: 12),
        pricingButton,
        const SizedBox(width: 8),
        addButton,
      ],
    );
  }

  // --- _buildShopsSummary ---
  Widget _buildShopsSummary(List<Map<String, dynamic>> shops) {
    final total = shops.length;
    final pending = shops
        .where((s) => !(s['is_approved'] as bool? ?? false))
        .length;
    final passive = shops
        .where((s) => !(s['is_active'] as bool? ?? true))
        .length;
    final adminCourier = shops
        .where((s) => !(s['has_own_courier'] as bool? ?? false))
        .length;
    final revenue = shops.fold<double>(
      0,
      (sum, s) => sum + ((s['total_earnings'] as num?)?.toDouble() ?? 0),
    );
    final commission = shops.fold<double>(
      0,
      (sum, s) => sum + ((s['admin_commission_total'] as num?)?.toDouble() ?? 0),
    );

    // Wrap kullaniliyor: kutucuklar icerik genisliginde kalir, sigmayanlar
    // alt satira iner; hicbir ekran genisliginde tasma olusmaz.
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _shopSummaryTile(
          icon: Icons.storefront,
          label: 'Toplam',
          value: '$total',
          color: Colors.purple,
        ),
        _shopSummaryTile(
          icon: Icons.pending_actions,
          label: 'Onay bekleyen',
          value: '$pending',
          color: Colors.orange,
        ),
        _shopSummaryTile(
          icon: Icons.visibility_off_outlined,
          label: 'Pasif',
          value: '$passive',
          color: Colors.blueGrey,
        ),
        _shopSummaryTile(
          icon: Icons.local_shipping_outlined,
          label: 'Admin kuryesi',
          value: '$adminCourier',
          color: Colors.teal,
        ),
        _shopSummaryTile(
          icon: Icons.payments_outlined,
          label: 'Toplam ciro',
          value: _shopMoney(revenue),
          color: Colors.green,
        ),
        _shopSummaryTile(
          icon: Icons.percent,
          label: 'Komisyon',
          value: _shopMoney(commission),
          color: Colors.indigo,
        ),
      ],
    );
  }

  // --- _shopSummaryTile ---
  Widget _shopSummaryTile({
    required IconData icon,
    required String label,
    required String value,
    required MaterialColor color,
  }) {
    return Container(
      constraints: const BoxConstraints(minWidth: 104),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.shade100),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: color.shade700),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color.shade700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: color.shade800,
            ),
          ),
        ],
      ),
    );
  }

  // --- _buildShopsSearchField ---
  Widget _buildShopsSearchField() {
    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color, width: width),
    );

    return TextField(
      controller: _shopSearchController,
      onChanged: (value) => setState(() => _shopSearchQuery = value),
      textInputAction: TextInputAction.search,
      style: const TextStyle(fontSize: 14),
      decoration: InputDecoration(
        isDense: true,
        hintText: 'Dükkan adı, sahip veya e-posta ara',
        hintStyle: TextStyle(fontSize: 13.5, color: Colors.grey.shade500),
        prefixIcon: Icon(Icons.search, size: 20, color: Colors.grey.shade600),
        suffixIcon: _shopSearchQuery.isEmpty
            ? null
            : IconButton(
                tooltip: 'Aramayı temizle',
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _shopSearchController.clear();
                  setState(() => _shopSearchQuery = '');
                },
              ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        border: border(Colors.grey.shade300, 1),
        enabledBorder: border(Colors.grey.shade300, 1),
        focusedBorder: border(Colors.purple.shade400, 1.4),
      ),
    );
  }

  // --- _buildShopsFilterChips ---
  Widget _buildShopsFilterChips(List<Map<String, dynamic>> shops) {
    const filters = <MapEntry<String, String>>[
      MapEntry('all', 'Tümü'),
      MapEntry('pending', 'Onay bekleyen'),
      MapEntry('active', 'Aktif'),
      MapEntry('passive', 'Pasif'),
      MapEntry('pinned', 'Sabitlenen'),
      MapEntry('verified', 'Doğrulanmış'),
      MapEntry('admin_courier', 'Admin kuryesi'),
      MapEntry('overridden', 'Fiyat müdahaleli'),
    ];

    // Yatay kaydirilabilir liste: cip sayisi arttikca satir tasmaz.
    return SizedBox(
      height: 36,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: filters.length,
        padding: EdgeInsets.zero,
        itemBuilder: (context, index) {
          final entry = filters[index];
          final count = shops
              .where((s) => _shopMatchesFilter(s, entry.key))
              .length;
          final selected = _shopFilter == entry.key;
          return Padding(
            padding: EdgeInsets.only(
              right: index == filters.length - 1 ? 0 : 8,
            ),
            child: ChoiceChip(
              label: Text('${entry.value} ($count)'),
              selected: selected,
              onSelected: (_) => setState(() => _shopFilter = entry.key),
              showCheckmark: false,
              backgroundColor: Colors.white,
              selectedColor: Colors.purple.shade600,
              side: BorderSide(
                color: selected ? Colors.purple.shade600 : Colors.grey.shade300,
              ),
              labelStyle: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: selected ? Colors.white : Colors.grey.shade700,
              ),
              labelPadding: const EdgeInsets.symmetric(horizontal: 6),
              visualDensity: VisualDensity.compact,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          );
        },
      ),
    );
  }

  // --- _buildShopsResultBar ---
  Widget _buildShopsResultBar(int total, int visible) {
    const sortLabels = <String, String>{
      'default': 'Sabitlenen önce',
      'name': 'İsme göre',
      'earnings': 'Kazanca göre',
      'orders': 'Siparişe göre',
      'newest': 'En yeni',
    };

    return Row(
      children: [
        Expanded(
          child: Text(
            visible == total
                ? '$total dükkan listeleniyor'
                : '$total dükkandan $visible tanesi gösteriliyor',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Colors.grey.shade600,
            ),
          ),
        ),
        const SizedBox(width: 8),
        PopupMenuButton<String>(
          tooltip: 'Sırala',
          initialValue: _shopSort,
          padding: EdgeInsets.zero,
          position: PopupMenuPosition.under,
          onSelected: (value) => setState(() => _shopSort = value),
          itemBuilder: (context) => [
            for (final entry in sortLabels.entries)
              PopupMenuItem<String>(
                value: entry.key,
                height: 42,
                child: Text(
                  entry.value,
                  style: const TextStyle(fontSize: 13),
                ),
              ),
          ],
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.swap_vert, size: 16, color: Colors.grey.shade700),
                const SizedBox(width: 4),
                Text(
                  sortLabels[_shopSort] ?? 'Sırala',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // --- _buildShopsEmptyState ---
  Widget _buildShopsEmptyState(bool noShopsAtAll) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 48, 24, 48),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              shape: BoxShape.circle,
            ),
            child: Icon(
              noShopsAtAll ? Icons.storefront_outlined : Icons.search_off,
              size: 40,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            noShopsAtAll ? 'Henüz dükkan yok' : 'Eşleşen dükkan bulunamadı',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            noShopsAtAll
                ? '"Yeni Dükkan" ile ilk dükkanı ekleyebilirsin.'
                : 'Arama metnini ya da seçili filtreyi değiştirmeyi dene.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, color: Colors.grey.shade500),
          ),
          if (!noShopsAtAll) ...[
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                _shopSearchController.clear();
                setState(() {
                  _shopSearchQuery = '';
                  _shopFilter = 'all';
                });
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Filtreleri temizle'),
              style: TextButton.styleFrom(
                foregroundColor: Colors.purple.shade700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ==========================================================================
  // Dukkan karti
  // ==========================================================================

  // --- _buildShopCard ---
  Widget _buildShopCard(Map<String, dynamic> shop) {
    final ownerName =
        (shop['profiles']?['full_name'] ??
                shop['profiles']?['username'] ??
                'Bilinmeyen')
            .toString();
    final ownerEmail = (shop['profiles']?['email'] ?? '').toString();
    final commission = (shop['commission_rate'] as num?)?.toDouble() ?? 10.0;
    final productCount = shop['product_count'] ?? 0;
    final totalEarnings = (shop['total_earnings'] as num?)?.toDouble() ?? 0.0;
    final netEarnings = (shop['net_earnings'] as num?)?.toDouble() ?? 0.0;
    final courierDeduction =
        (shop['courier_deduction'] as num?)?.toDouble() ?? 0.0;
    final commissionAmount = totalEarnings * (commission / 100);
    final totalOrders = shop['total_orders'] ?? 0;
    final deliveredOrders = shop['delivered_orders'] ?? 0;
    final pendingOrders = shop['pending_orders'] ?? 0;
    final cancelledOrders = shop['cancelled_orders'] ?? 0;
    final isVerified = shop['is_verified'] as bool? ?? false;
    final isApproved = shop['is_approved'] as bool? ?? false;
    final isActive = shop['is_active'] as bool? ?? true;
    final isShopPinned = shop['is_pinned'] as bool? ?? false;
    final hasOwnCourier = shop['has_own_courier'] as bool? ?? false;
    final deliveryFee = (shop['delivery_fee'] as num?)?.toDouble() ?? 0.0;
    final minOrderAmount = (shop['min_order_amount'] as num?)?.toDouble() ?? 0.0;
    final deliveryTime = (shop['delivery_time'] as String?)?.trim() ?? '';
    final logoUrl = (shop['logo_url'] as String?)?.trim() ?? '';
    final adminCredit = (shop['admin_credit'] as num?)?.toDouble() ?? 0.0;
    final commissionDebt = (shop['commission_debt'] as num?)?.toDouble() ?? 0.0;
    final netBalance = adminCredit - commissionDebt;
    final isOverridden = _isShopPricingOverridden(shop);

    // Durum seridi rengi: once onay, sonra aktiflik.
    final MaterialColor accent = !isApproved
        ? Colors.orange
        : (!isActive ? Colors.blueGrey : Colors.green);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: isShopPinned ? Colors.amber.shade300 : Colors.grey.shade200,
          width: isShopPinned ? 1.5 : 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => _showShopDetailDialog(shop),
            onLongPress: () => _showShopQuickSheet(shop),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 4, color: accent.shade400),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 6, 14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // --- Baslik satiri ---
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildShopAvatar(logoUrl, accent),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        shop['name']?.toString() ?? '-',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 16,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: -0.1,
                                        ),
                                      ),
                                    ),
                                    if (isVerified) ...[
                                      const SizedBox(width: 4),
                                      const Icon(
                                        Icons.verified,
                                        size: 15,
                                        color: Colors.blue,
                                      ),
                                    ],
                                    if (isShopPinned) ...[
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.push_pin,
                                        size: 13,
                                        color: Colors.amber.shade700,
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 3),
                                _shopMetaLine(Icons.person_outline, ownerName),
                                if (ownerEmail.isNotEmpty &&
                                    ownerEmail != '-') ...[
                                  const SizedBox(height: 2),
                                  _shopMetaLine(
                                    Icons.alternate_email,
                                    ownerEmail,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          _buildShopCardMenu(
                            shop,
                            isApproved: isApproved,
                            isActive: isActive,
                            isVerified: isVerified,
                            isShopPinned: isShopPinned,
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),

                      // --- Durum rozetleri ---
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _shopBadge(
                              isApproved ? 'Onaylı' : 'Onay bekliyor',
                              isApproved ? Colors.green : Colors.orange,
                              icon: isApproved
                                  ? Icons.check_circle
                                  : Icons.schedule,
                            ),
                            _shopBadge(
                              isActive ? 'Aktif' : 'Pasif',
                              isActive ? Colors.blue : Colors.grey,
                              icon: isActive
                                  ? Icons.visibility
                                  : Icons.visibility_off,
                            ),
                            _shopBalanceBadge(netBalance),
                            if (isOverridden)
                              _shopBadge(
                                'Fiyat müdahalesi',
                                Colors.deepPurple,
                                icon: Icons.price_change,
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // --- Para bloku ---
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: _shopMoneyCell(
                                      label: 'Ciro',
                                      value: _shopMoney(totalEarnings),
                                      color: Colors.grey.shade900,
                                    ),
                                  ),
                                  _shopCellDivider(),
                                  Expanded(
                                    child: _shopMoneyCell(
                                      label:
                                          'Komisyon %${commission.toStringAsFixed(0)}',
                                      value: '-${_shopMoney(commissionAmount)}',
                                      color: Colors.orange.shade800,
                                    ),
                                  ),
                                  _shopCellDivider(),
                                  Expanded(
                                    child: _shopMoneyCell(
                                      label: 'Kurye gideri',
                                      value: hasOwnCourier
                                          ? '—'
                                          : '-${_shopMoney(courierDeduction)}',
                                      color: Colors.blueGrey.shade700,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.teal.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: Colors.teal.shade100,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.account_balance_wallet_outlined,
                                      size: 18,
                                      color: Colors.teal.shade700,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        'Net kazanç',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w600,
                                          color: Colors.teal.shade900,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: FittedBox(
                                        fit: BoxFit.scaleDown,
                                        alignment: Alignment.centerRight,
                                        child: Text(
                                          _shopMoney(netEarnings, decimals: 2),
                                          maxLines: 1,
                                          style: TextStyle(
                                            fontSize: 16,
                                            fontWeight: FontWeight.w800,
                                            color: Colors.teal.shade800,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // --- Sayac rozetleri ---
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _shopCountPill(
                              Icons.inventory_2_outlined,
                              'Ürün',
                              '$productCount',
                              Colors.blue,
                            ),
                            _shopCountPill(
                              Icons.receipt_long_outlined,
                              'Sipariş',
                              '$totalOrders',
                              Colors.indigo,
                            ),
                            _shopCountPill(
                              Icons.check_circle_outline,
                              'Teslim',
                              '$deliveredOrders',
                              Colors.green,
                            ),
                            _shopCountPill(
                              Icons.hourglass_bottom,
                              'Bekleyen',
                              '$pendingOrders',
                              Colors.amber,
                            ),
                            _shopCountPill(
                              Icons.cancel_outlined,
                              'İptal',
                              '$cancelledOrders',
                              Colors.red,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),

                      // --- Teslimat bilgisi ---
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            _shopTagPill(
                              icon: hasOwnCourier
                                  ? Icons.delivery_dining
                                  : Icons.local_shipping,
                              text: hasOwnCourier
                                  ? 'Kendi kuryesi'
                                  : 'Admin kuryesi',
                              color: hasOwnCourier
                                  ? Colors.green
                                  : Colors.orange,
                            ),
                            _shopTagPill(
                              icon: Icons.payments_outlined,
                              text:
                                  'Teslimat ${_shopMoney(deliveryFee, decimals: 2)}',
                              color: Colors.blueGrey,
                            ),
                            if (minOrderAmount > 0)
                              _shopTagPill(
                                icon: Icons.shopping_basket_outlined,
                                text:
                                    'Min. sepet ${_shopMoney(minOrderAmount, decimals: 2)}',
                                color: Colors.blueGrey,
                              ),
                            if (deliveryTime.isNotEmpty)
                              _shopTagPill(
                                icon: Icons.timer_outlined,
                                text: deliveryTime,
                                color: Colors.blueGrey,
                              ),
                          ],
                        ),
                      ),

                      // --- Admin fiyat mudahalesi uyarisi ---
                      if (isOverridden) ...[
                        const SizedBox(height: 10),
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: InkWell(
                            onTap: _showShopPricingOverrideDialog,
                            borderRadius: BorderRadius.circular(12),
                            child: Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 8,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade50,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: Colors.orange.shade200,
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Icons.info_outline,
                                    size: 14,
                                    color: Colors.orange.shade800,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Admin müdahalesi açık — satıcı değeri: '
                                      '${(shop['pre_override_delivery_fee'] as num?) != null ? 'teslimat ${_shopMoney((shop['pre_override_delivery_fee'] as num).toDouble(), decimals: 2)}' : 'teslimat —'}'
                                      ', '
                                      '${(shop['pre_override_min_order_amount'] as num?) != null ? 'min. sepet ${_shopMoney((shop['pre_override_min_order_amount'] as num).toDouble(), decimals: 2)}' : 'min. sepet —'}'
                                      ', '
                                      '${_sellerDeliveryTimeLabel(shop)}',
                                      style: TextStyle(
                                        fontSize: 11,
                                        height: 1.35,
                                        color: Colors.orange.shade900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Divider(height: 1, thickness: 1, color: Colors.grey.shade200),
                _buildShopCardActions(shop, isApproved),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- _buildShopCardMenu ---
  Widget _buildShopCardMenu(
    Map<String, dynamic> shop, {
    required bool isApproved,
    required bool isActive,
    required bool isVerified,
    required bool isShopPinned,
  }) {
    return PopupMenuButton<String>(
      tooltip: 'İşlemler',
      icon: Icon(Icons.more_vert, size: 20, color: Colors.grey.shade600),
      position: PopupMenuPosition.under,
      onSelected: (value) {
        switch (value) {
          case 'edit':
            _showEditShopDialog(shop);
            break;
          case 'detail':
            _openShopDetailScreen(shop);
            break;
          case 'toggle_verified':
            _toggleShopVerification(shop);
            break;
          case 'toggle_approval':
            _toggleShopApproval(shop);
            break;
          case 'toggle_active':
            _toggleShopActive(shop);
            break;
          case 'toggle_pin':
            _toggleShopPin(shop);
            break;
          case 'pricing':
            _showShopPricingOverrideDialog();
            break;
          case 'delete':
            _showDeleteShopDialog(shop);
            break;
        }
      },
      itemBuilder: (context) => [
        _shopMenuItem('detail', Icons.assessment_outlined, 'Detaylı rapor'),
        _shopMenuItem('edit', Icons.edit_outlined, 'Düzenle'),
        _shopMenuItem(
          'toggle_approval',
          isApproved ? Icons.pending_outlined : Icons.check_circle_outline,
          isApproved ? 'Onayı kaldır' : 'Onayla',
          color: isApproved ? Colors.orange : Colors.green,
        ),
        _shopMenuItem(
          'toggle_active',
          isActive ? Icons.visibility_off : Icons.visibility,
          isActive ? 'Pasife al' : 'Aktife al',
          color: isActive ? Colors.grey : Colors.blue,
        ),
        _shopMenuItem(
          'toggle_verified',
          isVerified ? Icons.unpublished_outlined : Icons.verified_outlined,
          isVerified ? 'Doğrulamayı kaldır' : 'Doğrula',
          color: isVerified ? Colors.grey : Colors.blue,
        ),
        _shopMenuItem(
          'toggle_pin',
          isShopPinned ? Icons.push_pin_outlined : Icons.push_pin,
          isShopPinned ? 'Sabitlemeyi kaldır' : 'Sabitle',
          color: Colors.amber.shade700,
        ),
        _shopMenuItem(
          'pricing',
          Icons.price_change_outlined,
          'Teslimat & min. sepet',
          color: Colors.purple,
        ),
        const PopupMenuDivider(height: 1),
        _shopMenuItem('delete', Icons.delete_outline, 'Sil', color: Colors.red),
      ],
    );
  }

  // --- _shopMenuItem ---
  PopupMenuItem<String> _shopMenuItem(
    String value,
    IconData icon,
    String label, {
    Color? color,
  }) {
    return PopupMenuItem<String>(
      value: value,
      height: 42,
      child: Row(
        children: [
          Icon(icon, size: 18, color: color ?? Colors.grey.shade700),
          const SizedBox(width: 10),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 13, color: color),
            ),
          ),
        ],
      ),
    );
  }

  // --- _buildShopCardActions ---
  /// Kart alt aksiyon seridi. Her buton `Expanded` + `FittedBox` oldugu icin
  /// kart ne kadar dar olursa olsun etiketler tasmaz.
  Widget _buildShopCardActions(Map<String, dynamic> shop, bool isApproved) {
    return Row(
      children: [
        Expanded(
          child: _shopCardAction(
            icon: Icons.assessment_outlined,
            label: 'Detay',
            color: Colors.blueGrey.shade700,
            onTap: () => _openShopDetailScreen(shop),
          ),
        ),
        Container(width: 1, height: 34, color: Colors.grey.shade200),
        Expanded(
          child: _shopCardAction(
            icon: Icons.edit_outlined,
            label: 'Düzenle',
            color: Colors.indigo.shade600,
            onTap: () => _showEditShopDialog(shop),
          ),
        ),
        Container(width: 1, height: 34, color: Colors.grey.shade200),
        Expanded(
          child: _shopCardAction(
            icon: isApproved
                ? Icons.pending_outlined
                : Icons.check_circle_outline,
            label: isApproved ? 'Onayı kaldır' : 'Onayla',
            color: isApproved ? Colors.orange.shade800 : Colors.green.shade700,
            onTap: () => _toggleShopApproval(shop),
          ),
        ),
      ],
    );
  }

  // --- _shopCardAction ---
  Widget _shopCardAction({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 16, color: color),
            const SizedBox(width: 5),
            Flexible(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: color,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- _openShopDetailScreen ---
  void _openShopDetailScreen(Map<String, dynamic> shop) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            ShopDetailAdminScreen(shopId: shop['id'].toString()),
      ),
    );
  }

  // --- _toggleShopPin ---
  Future<void> _toggleShopPin(Map<String, dynamic> shop) async {
    final next = !(shop['is_pinned'] as bool? ?? false);
    await _togglePin('shops', shop['id'].toString(), next);
    if (!mounted) return;
    setState(() => shop['is_pinned'] = next);
  }

  // --- _showShopQuickSheet ---
  /// Karta uzun basinca acilan hizli islem sayfasi.
  void _showShopQuickSheet(Map<String, dynamic> shop) {
    final isShopPinned = shop['is_pinned'] as bool? ?? false;
    final isApproved = shop['is_approved'] as bool? ?? false;
    final isActive = shop['is_active'] as bool? ?? true;
    final isVerified = shop['is_verified'] as bool? ?? false;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                dense: true,
                leading: Icon(Icons.storefront, color: Colors.purple.shade600),
                title: Text(
                  shop['name']?.toString() ?? '-',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(
                  isApproved ? 'Onaylı dükkan' : 'Onay bekliyor',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              const Divider(height: 1),
              _shopSheetTile(
                ctx,
                icon: isShopPinned ? Icons.push_pin_outlined : Icons.push_pin,
                label: isShopPinned ? 'Sabitlemeyi kaldır' : 'Dükkanı sabitle',
                color: Colors.amber.shade700,
                onTap: () => _toggleShopPin(shop),
              ),
              _shopSheetTile(
                ctx,
                icon: isApproved
                    ? Icons.pending_outlined
                    : Icons.check_circle_outline,
                label: isApproved ? 'Onayı kaldır' : 'Onayla',
                color: isApproved ? Colors.orange : Colors.green,
                onTap: () => _toggleShopApproval(shop),
              ),
              _shopSheetTile(
                ctx,
                icon: isActive ? Icons.visibility_off : Icons.visibility,
                label: isActive ? 'Pasife al' : 'Aktife al',
                color: isActive ? Colors.grey.shade700 : Colors.blue,
                onTap: () => _toggleShopActive(shop),
              ),
              _shopSheetTile(
                ctx,
                icon: isVerified
                    ? Icons.unpublished_outlined
                    : Icons.verified_outlined,
                label: isVerified ? 'Doğrulamayı kaldır' : 'Doğrula',
                color: isVerified ? Colors.grey.shade700 : Colors.blue,
                onTap: () => _toggleShopVerification(shop),
              ),
              _shopSheetTile(
                ctx,
                icon: Icons.edit_outlined,
                label: 'Düzenle',
                color: Colors.indigo,
                onTap: () => _showEditShopDialog(shop),
              ),
              _shopSheetTile(
                ctx,
                icon: Icons.assessment_outlined,
                label: 'Detaylı rapor',
                color: Colors.blueGrey.shade700,
                onTap: () => _openShopDetailScreen(shop),
              ),
              const Divider(height: 1),
              _shopSheetTile(
                ctx,
                icon: Icons.delete_outline,
                label: 'Dükkanı sil',
                color: Colors.red,
                onTap: () => _showDeleteShopDialog(shop),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // --- _shopSheetTile ---
  Widget _shopSheetTile(
    BuildContext sheetContext, {
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: color),
      title: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 14, color: color),
      ),
      onTap: () {
        Navigator.pop(sheetContext);
        onTap();
      },
    );
  }

  // ==========================================================================
  // Kart ici kucuk parcalar
  // ==========================================================================

  // --- _buildShopAvatar ---
  Widget _buildShopAvatar(String logoUrl, MaterialColor accent) {
    if (logoUrl.isEmpty) return _shopAvatarFallback(accent);
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: CachedNetworkImage(
        imageUrl: logoUrl,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        placeholder: (context, url) =>
            Container(width: 48, height: 48, color: Colors.grey.shade100),
        errorWidget: (context, url, error) => _shopAvatarFallback(accent),
      ),
    );
  }

  // --- _shopAvatarFallback ---
  Widget _shopAvatarFallback(MaterialColor accent) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [accent.shade300, accent.shade600],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: const Icon(Icons.storefront, color: Colors.white, size: 24),
    );
  }

  // --- _shopMetaLine ---
  Widget _shopMetaLine(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 13, color: Colors.grey.shade500),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
        ),
      ],
    );
  }

  // --- _shopBadge ---
  Widget _shopBadge(String text, MaterialColor color, {IconData? icon}) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 200),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: color.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 11, color: color.shade700),
              const SizedBox(width: 4),
            ],
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  color: color.shade700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- _shopBalanceBadge ---
  Widget _shopBalanceBadge(double netBalance) {
    if (netBalance > 0) {
      return _shopBadge(
        'Ödeme ${_shopMoney(netBalance)}',
        Colors.green,
        icon: Icons.arrow_upward,
      );
    }
    if (netBalance < 0) {
      return _shopBadge(
        'Borç ${_shopMoney(netBalance.abs())}',
        Colors.red,
        icon: Icons.arrow_downward,
      );
    }
    return _shopBadge('Dengede', Colors.grey, icon: Icons.balance);
  }

  // --- _shopMoneyCell ---
  Widget _shopMoneyCell({
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            color: Colors.grey.shade600,
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ),
      ],
    );
  }

  // --- _shopCellDivider ---
  Widget _shopCellDivider() {
    return Container(
      width: 1,
      height: 30,
      margin: const EdgeInsets.symmetric(horizontal: 4),
      color: Colors.grey.shade200,
    );
  }

  // --- _shopCountPill ---
  Widget _shopCountPill(
    IconData icon,
    String label,
    String value,
    MaterialColor color,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color.shade600),
          const SizedBox(width: 5),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: color.shade800,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  // --- _shopTagPill ---
  /// Wrap cocuklari sinirsiz genislik aldigi icin metin burada acikca
  /// sinirlaniyor: `delivery_time` serbest metin (60 karaktere kadar) ve
  /// sinirsiz birakilirsa dar kartta satiri tasiriyor.
  Widget _shopTagPill({
    required IconData icon,
    required String text,
    required MaterialColor color,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 230),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.shade100),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: color.shade600),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color.shade800,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- _showAddShopDialog ---
  void _showAddShopDialog() {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();
    final commissionController = TextEditingController(text: '10.0');
    String? selectedOwnerId;

    showDialog(
      context: context,
      builder: (context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: _loadUsersWithoutShop(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AlertDialog(
              content: Center(child: CircularProgressIndicator()),
            );
          }

          final users = snapshot.data ?? [];

          // Dükkanı olmayan kullanıcı yoksa uyar
          if (users.isEmpty) {
            return AlertDialog(
              title: const Row(
                children: [
                  Icon(Icons.info, color: Colors.blue),
                  SizedBox(width: 8),
                  Text('Bilgilendirme'),
                ],
              ),
              content: const Text(
                'Dükkanı olmayan kullanıcı bulunamadı. Tüm kullanıcıların zaten bir dükkanı var.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Tamam'),
                ),
              ],
            );
          }

          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Yeni Dükkan Ekle'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Dükkan Adı *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.store),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Açıklama',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.description),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: commissionController,
                        decoration: const InputDecoration(
                          labelText: 'Komisyon Oranı (%) *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.percent),
                          suffixText: '%',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      DropdownButtonFormField<String>(
                        value: selectedOwnerId,
                        decoration: const InputDecoration(
                          labelText: 'Dükkan Sahibi *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                        items: users.map((user) {
                          return DropdownMenuItem(
                            value: user['id'] as String,
                            child: Text(
                              user['full_name'] ?? user['username'] ?? '-',
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setDialogState(() => selectedOwnerId = value);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.isEmpty ||
                        selectedOwnerId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Lütfen tüm zorunlu alanları doldurun'),
                        ),
                      );
                      return;
                    }

                    try {
                      debugPrint('📝 Yeni dükkan ekleniyor...');

                      final shopData = {
                        'name': nameController.text.trim(),
                        'description': descriptionController.text.trim(),
                        'owner_id': selectedOwnerId,
                        'commission_rate':
                            double.tryParse(commissionController.text) ?? 10.0,
                      };

                      await Supabase.instance.client
                          .from('shops')
                          .insert(shopData);

                      debugPrint('✅ Dükkan başarıyla eklendi');

                      if (mounted) {
                        Navigator.pop(context);
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Dükkan başarıyla eklendi'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      debugPrint('❌ Dükkan eklenirken hata: $e');
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Dükkan eklenirken hata: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Ekle'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- _toggleShopVerification ---
  void _toggleShopVerification(Map<String, dynamic> shop) async {
    final currentStatus = shop['is_verified'] as bool? ?? false;
    final newStatus = !currentStatus;

    try {
      await Supabase.instance.client
          .from('shops')
          .update({'is_verified': newStatus})
          .eq('id', shop['id']);

      if (mounted) {
        setState(() => shop['is_verified'] = newStatus);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus ? 'Dükkan doğrulandı' : 'Doğrulama kaldırıldı',
            ),
            backgroundColor: newStatus ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Doğrulama güncellenirken hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- _toggleShopApproval ---
  void _toggleShopApproval(Map<String, dynamic> shop) async {
    final currentStatus = shop['is_approved'] as bool? ?? false;
    final newStatus = !currentStatus;

    try {
      await Supabase.instance.client
          .from('shops')
          .update({'is_approved': newStatus})
          .eq('id', shop['id']);

      if (mounted) {
        setState(() => shop['is_approved'] = newStatus);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus
                  ? 'Dükkan onaylandı - Müşterilere gösterilecek'
                  : 'Dükkan onayı kaldırıldı - Müşterilerden gizlendi',
            ),
            backgroundColor: newStatus ? Colors.green : Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Onay durumu güncellenirken hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- _toggleShopActive ---
  void _toggleShopActive(Map<String, dynamic> shop) async {
    final currentStatus = shop['is_active'] as bool? ?? true;
    final newStatus = !currentStatus;

    try {
      await Supabase.instance.client
          .from('shops')
          .update({'is_active': newStatus})
          .eq('id', shop['id']);

      if (mounted) {
        setState(() => shop['is_active'] = newStatus);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newStatus
                  ? 'Dükkan aktif edildi'
                  : 'Dükkan pasife alındı - Müşterilerden gizlendi',
            ),
            backgroundColor: newStatus ? Colors.blue : Colors.grey,
          ),
        );
      }
    } catch (e) {
      debugPrint('Aktif durumu güncellenirken hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // --- _showEditShopDialog ---
  void _showEditShopDialog(Map<String, dynamic> shop) {
    final nameController = TextEditingController(text: shop['name']);
    final descriptionController = TextEditingController(
      text: shop['description'] ?? '',
    );
    final commissionController = TextEditingController(
      text: shop['commission_rate']?.toString() ?? '10.0',
    );
    final deliveryFeeController = TextEditingController(
      text: shop['delivery_fee']?.toString() ?? '0',
    );
    final String shopOwnerId = shop['owner_id'] ?? '';
    String? selectedOwnerId;
    bool hasOwnCourier = shop['has_own_courier'] ?? false;
    // Mevcut sahip bilgilerini önceden al
    final String shopOwnerName =
        shop['profiles']?['full_name'] ?? shop['profiles']?['username'] ?? '';

    showDialog(
      context: context,
      builder: (context) => FutureBuilder<List<Map<String, dynamic>>>(
        future: _loadUsers(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const AlertDialog(
              content: Center(child: CircularProgressIndicator()),
            );
          }

          final users = snapshot.data ?? [];

          // Owner ID'nin listede olup olmadığını kontrol et
          // Yinelenen ID'leri filtrele ve seçili değeri ayarla
          final seenIds = <String>{};
          final uniqueUsers = users.where((user) {
            final id = user['id'] as String;
            if (seenIds.contains(id)) return false;
            seenIds.add(id);
            return true;
          }).toList();

          // Mevcut sahip listede yoksa, listeye ekle
          if (shopOwnerId.isNotEmpty &&
              !uniqueUsers.any((u) => u['id'] == shopOwnerId)) {
            uniqueUsers.insert(0, {
              'id': shopOwnerId,
              'full_name': shopOwnerName.isNotEmpty
                  ? shopOwnerName
                  : 'Mevcut Sahip',
              'username': shopOwnerName.isNotEmpty
                  ? shopOwnerName
                  : 'mevcut_sahip',
              'email': shop['profiles']?['email'] ?? '',
            });
          }

          // Seçili owner'ı listede bul
          if (shopOwnerId.isNotEmpty &&
              uniqueUsers.any((u) => u['id'] == shopOwnerId)) {
            selectedOwnerId = shopOwnerId;
          } else if (uniqueUsers.isNotEmpty) {
            selectedOwnerId = uniqueUsers.first['id'] as String;
          }

          return StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
              title: const Text('Dükkan Düzenle'),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: double.maxFinite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: nameController,
                        decoration: const InputDecoration(
                          labelText: 'Dükkan Adı *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.store),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: descriptionController,
                        decoration: const InputDecoration(
                          labelText: 'Açıklama',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.description),
                        ),
                        maxLines: 2,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: commissionController,
                        decoration: const InputDecoration(
                          labelText: 'Komisyon Oranı (%) *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.percent),
                          suffixText: '%',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      // Kurye Durumu Switch'i (Admin kontrol edebilir)
                      SwitchListTile(
                        title: const Text('Kendi Kuryesi Var'),
                        subtitle: Text(
                          hasOwnCourier
                              ? 'Dükkan kendi teslimat ücretini belirler'
                              : 'Admin teslimat ücretini belirler',
                          style: const TextStyle(fontSize: 12),
                        ),
                        value: hasOwnCourier,
                        activeColor: Colors.green,
                        onChanged: (value) {
                          setDialogState(() => hasOwnCourier = value);
                        },
                        contentPadding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 12),
                      // Kuryesi olmayan dükkanlar için teslimat ücreti alanı
                      if (!hasOwnCourier)
                        Column(
                          children: [
                            TextField(
                              controller: deliveryFeeController,
                              decoration: const InputDecoration(
                                labelText: 'Min. Teslimat Ücreti (₺) *',
                                border: OutlineInputBorder(),
                                prefixIcon: Icon(Icons.delivery_dining),
                                suffixText: '₺',
                              ),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                  ),
                            ),
                            const SizedBox(height: 12),
                          ],
                        ),
                      DropdownButtonFormField<String>(
                        value: selectedOwnerId,
                        decoration: const InputDecoration(
                          labelText: 'Dükkan Sahibi *',
                          border: OutlineInputBorder(),
                          prefixIcon: Icon(Icons.person),
                        ),
                        items: uniqueUsers.map((user) {
                          return DropdownMenuItem(
                            value: user['id'] as String,
                            child: Text(
                              user['full_name'] ?? user['username'] ?? '-',
                            ),
                          );
                        }).toList(),
                        onChanged: (value) {
                          setDialogState(() => selectedOwnerId = value);
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    if (nameController.text.isEmpty ||
                        selectedOwnerId == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Lütfen tüm zorunlu alanları doldurun'),
                        ),
                      );
                      return;
                    }

                    try {
                      debugPrint('📝 Dükkan güncelleniyor: ${shop['id']}');

                      final shopData = {
                        'name': nameController.text.trim(),
                        'description': descriptionController.text.trim(),
                        'owner_id': selectedOwnerId,
                        'commission_rate':
                            double.tryParse(commissionController.text) ?? 10.0,
                        'has_own_courier':
                            hasOwnCourier, // Admin tarafından kurye durumu belirlenir
                      };

                      // Kuryesi olmayan dükkanlar için teslimat ücretini ekle
                      if (!hasOwnCourier) {
                        shopData['delivery_fee'] =
                            double.tryParse(deliveryFeeController.text) ?? 0.0;
                      }

                      await Supabase.instance.client
                          .from('shops')
                          .update(shopData)
                          .eq('id', shop['id']);

                      debugPrint('✅ Dükkan başarıyla güncellendi');

                      if (mounted) {
                        Navigator.pop(context);
                        setState(() {});
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Dükkan başarıyla güncellendi'),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    } catch (e) {
                      debugPrint('❌ Dükkan güncellenirken hata: $e');
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Dükkan güncellenirken hata: $e'),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    }
                  },
                  child: const Text('Güncelle'),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // --- _showDeleteShopDialog ---
  void _showDeleteShopDialog(Map<String, dynamic> shop) async {
    // Önce sipariş kontrolü yap
    try {
      final ordersResponse = await Supabase.instance.client
          .from('order_items')
          .select('id')
          .eq('shop_id', shop['id'])
          .limit(1);

      final hasOrders = ordersResponse.isNotEmpty;

      if (!mounted) return;

      if (hasOrders) {
        // Siparişi olan dükkanlar silinemez
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error, color: Colors.red),
                SizedBox(width: 8),
                Text('Dükkan Silinemez'),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${shop['name']} dükkanı silinemez.',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red.shade300),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.shopping_bag,
                        color: Colors.red.shade700,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Bu dükkana ait geçmiş siparişler bulunmaktadır. Veri bütünlüğü için siparişi olan dükkanlar silinemez.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.red.shade900,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Alternatif: Dükkanı pasif hale getirebilirsiniz (is_active = false).',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tamam'),
              ),
            ],
          ),
        );
        return;
      }
    } catch (e) {
      debugPrint('Sipariş kontrolü hatası: $e');
    }

    final productCount = shop['product_count'] ?? 0;

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Dükkanı Sil'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${shop['name']} dükkanını silmek istediğinizden emin misiniz?',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            if (productCount > 0)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade300),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.warning,
                      color: Colors.orange.shade700,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bu dükkana ait $productCount ürün var. Dükkanı silmek bu ürünleri de silecektir.',
                        style: TextStyle(
                          fontSize: 13,
                          color: Colors.orange.shade900,
                        ),
                      ),
                    ),
                  ],
                ),
              )
            else
              Text(
                'Bu işlem geri alınamaz.',
                style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              try {
                debugPrint(
                  '🗑️ Dükkan siliniyor: ${shop['id']} (${shop['name']})',
                );

                await Supabase.instance.client
                    .from('shops')
                    .delete()
                    .eq('id', shop['id']);

                debugPrint('✅ Dükkan başarıyla silindi');

                if (mounted) {
                  Navigator.pop(context);
                  setState(() {});
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Dükkan başarıyla silindi'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
              } catch (e) {
                debugPrint('❌ Dükkan silinirken hata: $e');

                String errorMessage = 'Dükkan silinirken hata oluştu';
                if (e.toString().contains('foreign key') ||
                    e.toString().contains('23503')) {
                  errorMessage = 'Bu dükkana ait siparişler var, silinemez';
                }

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(errorMessage),
                      backgroundColor: Colors.red,
                      duration: const Duration(seconds: 5),
                    ),
                  );
                }
              }
            },
            child: const Text('Sil'),
          ),
        ],
      ),
    );
  }

  // --- _showShopDetailDialog ---
  void _showShopDetailDialog(Map<String, dynamic> shop) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        // Uc aksiyon butonu dar ekranda alt alta diziliyor; aralik
        // verilmezse butonlar birbirine yapisik gorunuyordu.
        actionsOverflowButtonSpacing: 8,
        actionsOverflowAlignment: OverflowBarAlignment.center,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.orange.shade400, Colors.orange.shade600],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.store, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shop['name'] ?? '-',
                    style: const TextStyle(fontSize: 18),
                  ),
                  Text(
                    'Dükkan Detayı',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                      fontWeight: FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Sahip Bilgisi
                const Text(
                  'Dükkan Sahibi',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Card(
                  color: Colors.grey.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        _buildInfoRow(
                          'İsim',
                          shop['profiles']?['full_name'] ??
                              shop['profiles']?['username'] ??
                              '-',
                          Colors.grey.shade700,
                        ),
                        _buildInfoRow(
                          'Email',
                          shop['profiles']?['email'] ?? '-',
                          Colors.grey.shade700,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Komisyon Bilgisi
                const Text(
                  'Komisyon Bilgisi',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Card(
                  color: Colors.orange.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _buildInfoRow(
                      'Komisyon Oranı',
                      '%${((shop['commission_rate'] as num?)?.toDouble() ?? 10.0).toStringAsFixed(1)}',
                      Colors.orange.shade700,
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // İstatistikler
                const Text(
                  'İstatistikler',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.inventory_2,
                        title: 'Ürün',
                        value: '${shop['product_count'] ?? 0}',
                        color: Colors.blue,
                        gradient: [Colors.blue.shade400, Colors.blue.shade600],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        icon: Icons.attach_money,
                        title: 'Kazanç',
                        value:
                            '₺${((shop['total_earnings'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(0)}',
                        color: Colors.green,
                        gradient: [
                          Colors.green.shade400,
                          Colors.green.shade600,
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Kazanç Bilgileri (Periyodik)
                const Text(
                  'Kazanç Bilgileri',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Card(
                  color: Colors.teal.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        _buildInfoRow(
                          'Toplam Kazanç',
                          '₺${((shop['total_earnings'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                          Colors.teal.shade700,
                        ),
                        _buildInfoRow(
                          'Haftalık Kazanç',
                          '₺${((shop['weekly_earnings'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                          Colors.blue.shade700,
                        ),
                        _buildInfoRow(
                          'Aylık Kazanç',
                          '₺${((shop['monthly_earnings'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                          Colors.indigo.shade700,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Mali Bilgiler
                const Text(
                  'Mali Bilgiler',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Card(
                  color: Colors.green.shade50,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        _buildInfoRow(
                          'Kapıda Ödeme Geliri',
                          '₺${((shop['cash_payment_revenue'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                          Colors.green.shade700,
                        ),
                        _buildInfoRow(
                          'Online Gelir',
                          '₺${((shop['online_payment_revenue'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                          Colors.blue.shade700,
                        ),
                        _buildInfoRow(
                          'Admin Alacak',
                          '₺${((shop['admin_credit'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                          Colors.teal.shade700,
                        ),
                        _buildInfoRow(
                          'Komisyon Borcu',
                          '₺${((shop['commission_debt'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                          Colors.red.shade700,
                        ),
                        _buildInfoRow(
                          'Toplanan Nakit',
                          '₺${((shop['total_collected_cash'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                          Colors.orange.shade700,
                        ),
                        _buildInfoRow(
                          'Ödenen',
                          '₺${((shop['total_paid'] as num?)?.toDouble() ?? 0.0).toStringAsFixed(2)}',
                          Colors.grey.shade700,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                // Ödeme İşlemleri
                const Text(
                  'Ödeme İşlemleri',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    // Ödeme Yapıldı Butonu (Admin dükkana ödeme yaptı)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onPressed: () async {
                        final adminCredit =
                            (shop['admin_credit'] as num?)?.toDouble() ?? 0.0;
                        if (adminCredit <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Ödeme yapılacak tutar yok'),
                            ),
                          );
                          return;
                        }

                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Ödeme Yapıldı'),
                            content: Text(
                              'Dükkana ₺${adminCredit.toStringAsFixed(2)} ödeme yapıldı olarak işaretlensin mi?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('İptal'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Onayla'),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          try {
                            await Supabase.instance.client
                                .from('shops')
                                .update({
                                  'admin_credit': 0.0,
                                  // Admin, satıcıya online alacağını ödedi → satıcı genel
                                  // bakıştaki "Online Kazanç" kartı da sıfırlanmalı (kafa
                                  // karışıklığını önlemek için). 2026-07-03.
                                  'online_payment_revenue': 0.0,
                                  'total_paid':
                                      ((shop['total_paid'] as num?)
                                              ?.toDouble() ??
                                          0.0) +
                                      adminCredit,
                                })
                                .eq('id', shop['id']);

                            if (mounted) {
                              final messenger = ScaffoldMessenger.of(context);
                              Navigator.pop(context);
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Ödeme yapıldı olarak işaretlendi',
                                  ),
                                ),
                              );
                              _loadAndSetShops();
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Hata: $e')),
                              );
                            }
                          }
                        }
                      },
                      icon: const Icon(Icons.payment, size: 18),
                      label: const Text('Ödeme Yapıldı'),
                    ),

                    // Ödeme Alındı Butonu (Admin nakit topladı)
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onPressed: () async {
                        final commissionDebt =
                            (shop['commission_debt'] as num?)?.toDouble() ??
                            0.0;
                        if (commissionDebt <= 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Tahsil edilecek tutar yok'),
                            ),
                          );
                          return;
                        }

                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Ödeme Alındı'),
                            content: Text(
                              'Dükkanından ₺${commissionDebt.toStringAsFixed(2)} ödeme alındı olarak işaretlensin mi?',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('İptal'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Onayla'),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          try {
                            await Supabase.instance.client
                                .from('shops')
                                .update({
                                  'commission_debt': 0.0,
                                  // Admin, kapıda (nakit) siparişlerin komisyonunu satıcıdan
                                  // tahsil etti → satıcı genel bakıştaki "Kapıda Kazanç" kartı
                                  // da sıfırlanmalı (kafa karışıklığını önlemek için). 2026-07-03.
                                  'cash_payment_revenue': 0.0,
                                  'total_collected_cash':
                                      ((shop['total_collected_cash'] as num?)
                                              ?.toDouble() ??
                                          0.0) +
                                      commissionDebt,
                                })
                                .eq('id', shop['id']);

                            if (mounted) {
                              final messenger = ScaffoldMessenger.of(context);
                              Navigator.pop(context);
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text(
                                    'Ödeme alındı olarak işaretlendi',
                                  ),
                                ),
                              );
                              _loadAndSetShops();
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Hata: $e')),
                              );
                            }
                          }
                        }
                      },
                      icon: const Icon(Icons.account_balance_wallet, size: 18),
                      label: const Text('Ödeme Alındı'),
                    ),

                    // Alacak/Verecek Kapat Butonu
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                      onPressed: () async {
                        final adminCredit =
                            (shop['admin_credit'] as num?)?.toDouble() ?? 0.0;
                        final commissionDebt =
                            (shop['commission_debt'] as num?)?.toDouble() ??
                            0.0;

                        if (adminCredit == 0 && commissionDebt == 0) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Kapanacak alacak/verecek yok'),
                            ),
                          );
                          return;
                        }

                        final balance = adminCredit - commissionDebt;
                        String message = '';
                        if (balance > 0) {
                          message =
                              'Admin dükkana ₺${balance.abs().toStringAsFixed(2)} borçlu. Tüm alacak/verecek kapatılsın mı?';
                        } else if (balance < 0) {
                          message =
                              'Dükkan admin\'e ₺${balance.abs().toStringAsFixed(2)} borçlu. Tüm alacak/verecek kapatılsın mı?';
                        } else {
                          message =
                              'Hesaplar denk. Tüm alacak/verecek kapatılsın mı?';
                        }

                        final confirm = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Alacak/Verecek Kapat'),
                            content: Text(message),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context, false),
                                child: const Text('İptal'),
                              ),
                              ElevatedButton(
                                onPressed: () => Navigator.pop(context, true),
                                child: const Text('Kapat'),
                              ),
                            ],
                          ),
                        );

                        if (confirm == true) {
                          try {
                            await Supabase.instance.client
                                .from('shops')
                                .update({
                                  'admin_credit': 0.0,
                                  'commission_debt': 0.0,
                                  'cash_payment_revenue': 0.0,
                                  'online_payment_revenue': 0.0,
                                  'total_collected_cash': 0.0,
                                })
                                .eq('id', shop['id']);

                            if (mounted) {
                              final messenger = ScaffoldMessenger.of(context);
                              Navigator.pop(context);
                              messenger.showSnackBar(
                                const SnackBar(
                                  content: Text('Alacak/verecek kapatıldı'),
                                ),
                              );
                              // Yalnızca DB'de gerçekten sıfırlanan bakiye
                              // alanlarını yerelde güncelle — sipariş/kazanç
                              // geçmişi bu aksiyondan etkilenmez, o yüzden
                              // burada uydurma sıfırlar yazılmaz. Kalan tüm
                              // alanlar _loadAndSetShops() ile sunucudan
                              // tazelenir.
                              setState(() {
                                shop['admin_credit'] = 0.0;
                                shop['commission_debt'] = 0.0;
                                shop['cash_payment_revenue'] = 0.0;
                                shop['online_payment_revenue'] = 0.0;
                                shop['total_collected_cash'] = 0.0;
                              });
                              _loadAndSetShops();
                            }
                          } catch (e) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(content: Text('Hata: $e')),
                              );
                            }
                          }
                        }
                      },
                      icon: const Icon(Icons.close, size: 18),
                      label: const Text('Alacak/Verecek Kapat'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // Oluşturulma Tarihi
                if (shop['created_at'] != null)
                  _buildInfoRow(
                    'Oluşturulma Tarihi',
                    _formatDate(shop['created_at']),
                    Colors.grey.shade600,
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Kapat'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            onPressed: () {
              Navigator.pop(context);
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) =>
                      ShopDetailAdminScreen(shopId: shop['id']),
                ),
              );
            },
            icon: const Icon(Icons.info),
            label: const Text('Detaylı Görüntüle'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _showEditShopDialog(shop);
            },
            icon: const Icon(Icons.edit),
            label: const Text('Düzenle'),
          ),
        ],
      ),
    );
  }
}
