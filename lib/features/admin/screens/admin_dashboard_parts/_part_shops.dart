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
  Widget _buildShopsContent() {
    if (_isLoadingShops && _shopsDetailed.isEmpty) {
      _loadAndSetShops();
      return const Center(child: CircularProgressIndicator());
    }

    final shops = _shopsDetailed;

    return RefreshIndicator(
      onRefresh: () async {
        await _loadAndSetShops();
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Dükkan Yönetimi',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                ),
                ElevatedButton.icon(
                  onPressed: () => _showAddShopDialog(),
                  icon: const Icon(Icons.add),
                  label: const Text('Yeni Dükkan'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.purple.shade600,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (shops.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Column(
                    children: [
                      Icon(
                        Icons.store_outlined,
                        size: 64,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Henüz dükkan yok',
                        style: TextStyle(
                          fontSize: 16,
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: shops.length,
                itemBuilder: (context, index) {
                  final shop = shops[index];
                  return _buildShopCard(shop);
                },
              ),
          ],
        ),
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

  // --- _buildShopCard ---
  Widget _buildShopCard(Map<String, dynamic> shop) {
    final ownerName =
        shop['profiles']?['full_name'] ??
        shop['profiles']?['username'] ??
        'Bilinmeyen';
    final ownerEmail = shop['profiles']?['email'] ?? '-';
    final commission = (shop['commission_rate'] as num?)?.toDouble() ?? 10.0;
    final productCount = shop['product_count'] ?? 0;
    final totalEarnings = (shop['total_earnings'] as num?)?.toDouble() ?? 0.0;
    final netEarnings = (shop['net_earnings'] as num?)?.toDouble() ?? 0.0;
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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: isShopPinned ? 4 : 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: isShopPinned
            ? BorderSide(color: Colors.amber.shade400, width: 2)
            : BorderSide.none,
      ),
      child: Stack(
        children: [
          if (isShopPinned)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.amber.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.push_pin,
                      size: 12,
                      color: Colors.amber.shade800,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      'Sabitlendi',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.amber.shade800,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _showShopDetailDialog(shop),
            onLongPress: () {
              showModalBottomSheet(
                context: context,
                builder: (ctx) => SafeArea(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: Icon(
                          isShopPinned
                              ? Icons.push_pin_outlined
                              : Icons.push_pin,
                          color: Colors.amber.shade700,
                        ),
                        title: Text(
                          isShopPinned
                              ? 'Sabitlemeyi Kaldır'
                              : 'Dükkanı Sabitle',
                        ),
                        onTap: () {
                          Navigator.pop(ctx);
                          _togglePin('shops', shop['id'], !isShopPinned);
                        },
                      ),
                    ],
                  ),
                ),
              );
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Colors.orange.shade400,
                              Colors.orange.shade600,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.store,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  shop['name'] ?? '-',
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                if (isVerified) ...[
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.verified,
                                    size: 18,
                                    color: Colors.blue,
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Wrap(
                              spacing: 6,
                              runSpacing: 4,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isApproved
                                        ? Colors.green.shade100
                                        : Colors.orange.shade100,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isApproved ? 'Onaylı' : 'Onay Bekliyor',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isApproved
                                          ? Colors.green.shade700
                                          : Colors.orange.shade700,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: isActive
                                        ? Colors.blue.shade100
                                        : Colors.grey.shade200,
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    isActive ? 'Aktif' : 'Pasif',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isActive
                                          ? Colors.blue.shade700
                                          : Colors.grey.shade600,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                                // Komisyon Durum Etiketi
                                Builder(
                                  builder: (context) {
                                    final adminCredit =
                                        (shop['admin_credit'] as num?)
                                            ?.toDouble() ??
                                        0;
                                    final commissionDebt =
                                        (shop['commission_debt'] as num?)
                                            ?.toDouble() ??
                                        0;
                                    final netBalance =
                                        adminCredit - commissionDebt;

                                    Color badgeColor;
                                    IconData badgeIcon;
                                    String badgeText;

                                    if (netBalance > 0) {
                                      badgeColor = Colors.green;
                                      badgeIcon = Icons.arrow_upward;
                                      badgeText = 'Ödeme';
                                    } else if (netBalance < 0) {
                                      badgeColor = Colors.red;
                                      badgeIcon = Icons.arrow_downward;
                                      badgeText = 'Borç';
                                    } else {
                                      badgeColor = Colors.grey;
                                      badgeIcon = Icons.balance;
                                      badgeText = 'Dengede';
                                    }

                                    return Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                        vertical: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: badgeColor.withOpacity(0.1),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: badgeColor.withOpacity(0.4),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            badgeIcon,
                                            size: 10,
                                            color: badgeColor,
                                          ),
                                          const SizedBox(width: 2),
                                          Text(
                                            badgeText,
                                            style: TextStyle(
                                              fontSize: 10,
                                              fontWeight: FontWeight.w600,
                                              color: badgeColor,
                                            ),
                                          ),
                                        ],
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Icon(
                                  Icons.person,
                                  size: 14,
                                  color: Colors.grey.shade600,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    ownerName,
                                    style: TextStyle(
                                      fontSize: 13,
                                      color: Colors.grey.shade700,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_vert,
                          color: Colors.grey.shade700,
                        ),
                        onSelected: (value) {
                          switch (value) {
                            case 'edit':
                              _showEditShopDialog(shop);
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
                            case 'delete':
                              _showDeleteShopDialog(shop);
                              break;
                          }
                        },
                        itemBuilder: (context) => [
                          const PopupMenuItem(
                            value: 'edit',
                            child: Row(
                              children: [
                                Icon(Icons.edit, size: 18),
                                SizedBox(width: 8),
                                Text('Düzenle'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'toggle_approval',
                            child: Row(
                              children: [
                                Icon(
                                  isApproved
                                      ? Icons.check_circle
                                      : Icons.pending,
                                  size: 18,
                                  color: isApproved
                                      ? Colors.green
                                      : Colors.orange,
                                ),
                                const SizedBox(width: 8),
                                Text(isApproved ? 'Onayı Kaldır' : 'Onayla'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'toggle_active',
                            child: Row(
                              children: [
                                Icon(
                                  isActive
                                      ? Icons.visibility
                                      : Icons.visibility_off,
                                  size: 18,
                                  color: isActive ? Colors.blue : Colors.grey,
                                ),
                                const SizedBox(width: 8),
                                Text(isActive ? 'Pasife Al' : 'Aktife Al'),
                              ],
                            ),
                          ),
                          PopupMenuItem(
                            value: 'toggle_verified',
                            child: Row(
                              children: [
                                Icon(
                                  isVerified
                                      ? Icons.verified
                                      : Icons.unpublished,
                                  size: 18,
                                  color: isVerified ? Colors.blue : Colors.grey,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  isVerified ? 'Doğrulamayı Kaldır' : 'Doğrula',
                                ),
                              ],
                            ),
                          ),
                          const PopupMenuItem(
                            value: 'delete',
                            child: Row(
                              children: [
                                Icon(Icons.delete, size: 18, color: Colors.red),
                                SizedBox(width: 8),
                                Text(
                                  'Sil',
                                  style: TextStyle(color: Colors.red),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // İstatistikler
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      children: [
                        // Gelir İstatistikleri
                        Row(
                          children: [
                            Expanded(
                              child: _buildShopStat(
                                icon: Icons.inventory_2,
                                label: 'Ürün',
                                value: '$productCount',
                                color: Colors.blue,
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 40,
                              color: Colors.grey.shade300,
                            ),
                            Expanded(
                              child: _buildShopStat(
                                icon: Icons.attach_money,
                                label: 'Kazanç',
                                value: '₺${totalEarnings.toStringAsFixed(0)}',
                                color: Colors.green,
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 40,
                              color: Colors.grey.shade300,
                            ),
                            Expanded(
                              child: _buildShopStat(
                                icon: Icons.percent,
                                label: 'Komisyon',
                                value: '%${commission.toStringAsFixed(0)}',
                                color: Colors.orange,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        // Net Kazanc (Kurye + Komisyon Kesilmis)
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [
                                Colors.teal.shade400,
                                Colors.teal.shade600,
                              ],
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              const Icon(
                                Icons.account_balance_wallet,
                                color: Colors.white,
                                size: 20,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'Net Kazanc',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    if (!hasOwnCourier &&
                                        (shop['courier_deduction'] as num?)
                                                ?.toDouble() !=
                                            0) ...[
                                      Text(
                                        'Kurye: -₺${((shop['courier_deduction'] as num?)?.toDouble() ?? 0).toStringAsFixed(0)} | Komisyon: -₺${(totalEarnings * (commission / 100)).toStringAsFixed(0)}',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ] else ...[
                                      Text(
                                        'Komisyon: -₺${(totalEarnings * (commission / 100)).toStringAsFixed(0)}',
                                        style: TextStyle(
                                          color: Colors.white70,
                                          fontSize: 10,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              Text(
                                '₺${netEarnings.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (hasOwnCourier) ...[
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Icon(
                                Icons.delivery_dining,
                                size: 14,
                                color: Colors.blue,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Kendi Kuryesi Var',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 12),
                        Divider(height: 1, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        // Sipariş İstatistikleri
                        Row(
                          children: [
                            Expanded(
                              child: _buildShopStat(
                                icon: Icons.shopping_bag,
                                label: 'Toplam Sipariş',
                                value: '$totalOrders',
                                color: Colors.indigo,
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 40,
                              color: Colors.grey.shade300,
                            ),
                            Expanded(
                              child: _buildShopStat(
                                icon: Icons.check_circle,
                                label: 'Teslim Edilen',
                                value: '$deliveredOrders',
                                color: Colors.green,
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 40,
                              color: Colors.grey.shade300,
                            ),
                            Expanded(
                              child: _buildShopStat(
                                icon: Icons.pending_actions,
                                label: 'Bekleyen',
                                value: '$pendingOrders',
                                color: Colors.amber,
                              ),
                            ),
                            Container(
                              width: 1,
                              height: 40,
                              color: Colors.grey.shade300,
                            ),
                            Expanded(
                              child: _buildShopStat(
                                icon: Icons.cancel,
                                label: 'İptal',
                                value: '$cancelledOrders',
                                color: Colors.red,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Kurye ve Teslimat Bilgisi
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: hasOwnCourier
                          ? Colors.green.shade50
                          : Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: hasOwnCourier
                            ? Colors.green.shade200
                            : Colors.orange.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          hasOwnCourier
                              ? Icons.delivery_dining
                              : Icons.local_shipping,
                          size: 16,
                          color: hasOwnCourier
                              ? Colors.green.shade700
                              : Colors.orange.shade700,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            hasOwnCourier ? 'Kendi Kuryesi' : 'Admin Kuryesi',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: hasOwnCourier
                                  ? Colors.green.shade700
                                  : Colors.orange.shade700,
                            ),
                          ),
                        ),
                        if (!hasOwnCourier) ...[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade700,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              '₺${deliveryFee.toStringAsFixed(2)}/teslimat',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Sahip Email
                  Row(
                    children: [
                      Icon(Icons.email, size: 14, color: Colors.grey.shade500),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          ownerEmail,
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // --- _buildShopStat ---
  Widget _buildShopStat({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, size: 20, color: color),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
        ),
      ],
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
