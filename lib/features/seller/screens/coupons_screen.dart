// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';

/// Satıcı Kupon Yönetim Ekranı
/// 
/// Özellikler:
/// - Kupon oluşturma (sabit tutar veya yüzde indirim)
/// - Minimum sipariş tutarı belirleme
/// - Kullanım limiti ayarlama
/// - Aktif/Pasif durumu
class CouponsScreen extends StatefulWidget {
  const CouponsScreen({super.key});

  @override
  State<CouponsScreen> createState() => _CouponsScreenState();
}

class _CouponsScreenState extends State<CouponsScreen> {
  final _supabase = Supabase.instance.client;
  List<Map<String, dynamic>> _coupons = [];
  bool _isLoading = true;
  String? _shopId;

  @override
  void initState() {
    super.initState();
    _loadCoupons();
  }

  Future<void> _loadCoupons() async {
    setState(() => _isLoading = true);
    
    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Satıcının mağazasını bul
      final shopResponse = await _supabase
          .from('shops')
          .select('id')
          .eq('owner_id', userId)
          .maybeSingle();

      if (shopResponse == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Mağaza bulunamadı')),
          );
        }
        return;
      }

      _shopId = shopResponse['id'] as String;

      // Kuponları yükle
      final couponsResponse = await _supabase
          .from('shop_coupons')
          .select('*')
          .eq('shop_id', _shopId!)
          .order('created_at', ascending: false);

      setState(() {
        _coupons = List<Map<String, dynamic>>.from(couponsResponse);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Kuponlar yüklenirken hata: $e');
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showCouponDialog({Map<String, dynamic>? coupon}) async {
    final isEdit = coupon != null;
    final codeController = TextEditingController(text: coupon?['code'] ?? '');
    final titleController = TextEditingController(text: coupon?['title'] ?? '');
    final descController = TextEditingController(text: coupon?['description'] ?? '');
    final discountValueController = TextEditingController(
      text: coupon?['discount_value']?.toString() ?? '',
    );
    final minOrderController = TextEditingController(
      text: coupon?['minimum_order_amount']?.toString() ?? '0',
    );
    final maxDiscountController = TextEditingController(
      text: coupon?['maximum_discount_amount']?.toString() ?? '',
    );
    final usageLimitController = TextEditingController(
      text: coupon?['usage_limit']?.toString() ?? '',
    );
    final usagePerUserController = TextEditingController(
      text: coupon?['usage_per_user']?.toString() ?? '1',
    );

    String discountType = coupon?['discount_type'] ?? 'fixed_amount';
    bool isActive = coupon?['is_active'] ?? true;

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(isEdit ? 'Kupon Düzenle' : 'Yeni Kupon Oluştur'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: codeController,
                  decoration: const InputDecoration(
                    labelText: 'Kupon Kodu',
                    hintText: 'Örn: YENI100',
                    prefixIcon: Icon(Icons.confirmation_number),
                  ),
                  textCapitalization: TextCapitalization.characters,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: titleController,
                  decoration: const InputDecoration(
                    labelText: 'Başlık',
                    hintText: 'Örn: 100TL İndirim',
                    prefixIcon: Icon(Icons.title),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: descController,
                  decoration: const InputDecoration(
                    labelText: 'Açıklama (İsteğe Bağlı)',
                    hintText: '1500TL üzeri alışverişlerde geçerlidir',
                    prefixIcon: Icon(Icons.description),
                  ),
                  maxLines: 2,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('Sabit Tutar'),
                        subtitle: const Text('₺ indirim'),
                        value: 'fixed_amount',
                        groupValue: discountType,
                        onChanged: (value) {
                          setDialogState(() => discountType = value!);
                        },
                      ),
                    ),
                    Expanded(
                      child: RadioListTile<String>(
                        title: const Text('Yüzde'),
                        subtitle: const Text('% indirim'),
                        value: 'percentage',
                        groupValue: discountType,
                        onChanged: (value) {
                          setDialogState(() => discountType = value!);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: discountValueController,
                  decoration: InputDecoration(
                    labelText: discountType == 'fixed_amount' 
                        ? 'İndirim Tutarı (₺)' 
                        : 'İndirim Yüzdesi (%)',
                    prefixIcon: const Icon(Icons.discount),
                  ),
                  keyboardType: TextInputType.number,
                ),
                if (discountType == 'percentage') ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: maxDiscountController,
                    decoration: const InputDecoration(
                      labelText: 'Maksimum İndirim (₺) - İsteğe Bağlı',
                      hintText: 'Örn: 200',
                      prefixIcon: Icon(Icons.money_off),
                    ),
                    keyboardType: TextInputType.number,
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: minOrderController,
                  decoration: const InputDecoration(
                    labelText: 'Minimum Sipariş Tutarı (₺)',
                    hintText: 'Örn: 1500',
                    prefixIcon: Icon(Icons.shopping_cart),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: usageLimitController,
                  decoration: const InputDecoration(
                    labelText: 'Toplam Kullanım Limiti (İsteğe Bağlı)',
                    hintText: 'Boş bırakılırsa sınırsız',
                    prefixIcon: Icon(Icons.people),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: usagePerUserController,
                  decoration: const InputDecoration(
                    labelText: 'Kullanıcı Başına Kullanım',
                    hintText: '1',
                    prefixIcon: Icon(Icons.person),
                  ),
                  keyboardType: TextInputType.number,
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  title: const Text('Aktif'),
                  subtitle: Text(isActive ? 'Kupon aktif' : 'Kupon pasif'),
                  value: isActive,
                  onChanged: (value) {
                    setDialogState(() => isActive = value);
                  },
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () async {
                if (codeController.text.isEmpty ||
                    titleController.text.isEmpty ||
                    discountValueController.text.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Lütfen zorunlu alanları doldurun'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                  return;
                }

                try {
                  final data = {
                    'shop_id': _shopId,
                    'code': codeController.text.toUpperCase(),
                    'title': titleController.text,
                    'description': descController.text.isEmpty 
                        ? null 
                        : descController.text,
                    'discount_type': discountType,
                    'discount_value': double.parse(discountValueController.text),
                    'minimum_order_amount': double.parse(minOrderController.text),
                    'maximum_discount_amount': maxDiscountController.text.isEmpty
                        ? null
                        : double.parse(maxDiscountController.text),
                    'usage_limit': usageLimitController.text.isEmpty
                        ? null
                        : int.parse(usageLimitController.text),
                    'usage_per_user': int.parse(usagePerUserController.text),
                    'is_active': isActive,
                  };

                  if (isEdit) {
                    await _supabase
                        .from('shop_coupons')
                        .update(data)
                        .eq('id', coupon['id']);
                  } else {
                    await _supabase.from('shop_coupons').insert(data);
                  }

                  if (mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(isEdit 
                            ? 'Kupon güncellendi' 
                            : 'Kupon oluşturuldu'),
                        backgroundColor: Colors.green,
                      ),
                    );
                    _loadCoupons();
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Hata: $e'),
                        backgroundColor: Colors.red,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.orange.shade700,
              ),
              child: Text(isEdit ? 'Güncelle' : 'Oluştur'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCouponStats(String couponId) async {
    try {
      // Kupon kullanımlarını al
      final usagesResponse = await _supabase
          .from('coupon_usages')
          .select('''
            *,
            profiles!coupon_usages_user_id_fkey(full_name, email),
            orders(order_number_int, total, created_at)
          ''')
          .eq('coupon_id', couponId)
          .order('used_at', ascending: false);

      final usages = List<Map<String, dynamic>>.from(usagesResponse);
      final totalDiscount = usages.fold<double>(
        0,
        (sum, usage) => sum + ((usage['discount_amount'] as num?)?.toDouble() ?? 0),
      );

      if (!mounted) return;

      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.bar_chart, color: Colors.orange.shade700),
              const SizedBox(width: 8),
              const Text('Kupon İstatistikleri'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Özet Kartları
                Row(
                  children: [
                    Expanded(
                      child: _buildStatCard(
                        'Kullanım',
                        '${usages.length}',
                        Icons.people,
                        Colors.blue,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildStatCard(
                        'Toplam İndirim',
                        '₺${totalDiscount.toStringAsFixed(0)}',
                        Icons.discount,
                        Colors.red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                if (usages.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Text(
                      'Henüz kullanılmamış',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 14,
                      ),
                    ),
                  )
                else
                  SizedBox(
                    height: 300,
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: usages.length,
                      itemBuilder: (context, index) {
                        final usage = usages[index];
                        final profile = usage['profiles'] as Map<String, dynamic>?;
                        final order = usage['orders'] as Map<String, dynamic>?;
                        final discount = (usage['discount_amount'] as num?)?.toDouble() ?? 0;
                        final usedAt = usage['used_at'] as String?;

                        return Card(
                          margin: const EdgeInsets.only(bottom: 8),
                          child: ListTile(
                            leading: CircleAvatar(
                              backgroundColor: Colors.orange.shade100,
                              child: Icon(
                                Icons.person,
                                color: Colors.orange.shade700,
                              ),
                            ),
                            title: Text(
                              profile?['full_name'] ?? 'Kullanıcı',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (order != null)
                                  Text(
                                    'Sipariş #${order['order_number_int'] ?? '-'}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                if (usedAt != null)
                                  Text(
                                    DateTime.parse(usedAt).toString().substring(0, 16),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.grey.shade600,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '- ₺${discount.toStringAsFixed(2)}',
                                style: TextStyle(
                                  color: Colors.green.shade700,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Kapat'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 24),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCoupon(String couponId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kuponu Sil'),
        content: const Text('Bu kuponu silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _supabase.from('shop_coupons').delete().eq('id', couponId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Kupon silindi'),
              backgroundColor: Colors.green,
            ),
          );
          _loadCoupons();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Hata: $e'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kupon Yönetimi'),
        backgroundColor: Colors.orange.shade700,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _coupons.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.confirmation_number_outlined,
                        size: 80,
                        color: Colors.grey.shade400,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Henüz kupon oluşturmadınız',
                        style: TextStyle(
                          fontSize: 18,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Müşterilerinize özel indirimler sunun',
                        style: TextStyle(
                          fontSize: 14,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _loadCoupons,
                  child: ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _coupons.length,
                    itemBuilder: (context, index) {
                      final coupon = _coupons[index];
                      return _buildCouponCard(coupon);
                    },
                  ),
                ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCouponDialog(),
        backgroundColor: Colors.orange.shade700,
        icon: const Icon(Icons.add),
        label: const Text('Yeni Kupon'),
      ),
    );
  }

  Widget _buildCouponCard(Map<String, dynamic> coupon) {
    final isActive = coupon['is_active'] as bool? ?? false;
    final discountType = coupon['discount_type'] as String;
    final discountValue = (coupon['discount_value'] as num?)?.toDouble() ?? 0;
    final minOrder = (coupon['minimum_order_amount'] as num?)?.toDouble() ?? 0;
    final usageCount = coupon['usage_count'] as int? ?? 0;
    final usageLimit = coupon['usage_limit'] as int?;
    final createdAt = coupon['created_at'] as String?;

    String discountText;
    if (discountType == 'fixed_amount') {
      discountText = '₺${discountValue.toStringAsFixed(0)} İndirim';
    } else {
      discountText = '%${discountValue.toStringAsFixed(0)} İndirim';
      final maxDiscount = (coupon['maximum_discount_amount'] as num?)?.toDouble();
      if (maxDiscount != null) {
        discountText += ' (Max: ₺${maxDiscount.toStringAsFixed(0)})';
      }
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          ListTile(
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: isActive ? Colors.green.shade50 : Colors.grey.shade200,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isActive ? Colors.green : Colors.grey,
                  width: 2,
                ),
              ),
              child: Icon(
                Icons.confirmation_number,
                color: isActive ? Colors.green : Colors.grey,
              ),
            ),
            title: Text(
              coupon['code'] ?? '-',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  coupon['title'] ?? '-',
                  style: const TextStyle(fontSize: 14),
                ),
                const SizedBox(height: 4),
                Text(
                  discountText,
                  style: TextStyle(
                    color: Colors.orange.shade700,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (usageCount > 0)
                  IconButton(
                    icon: const Icon(Icons.bar_chart, color: Colors.green),
                    tooltip: 'İstatistikler',
                    onPressed: () => _showCouponStats(coupon['id']),
                  ),
                IconButton(
                  icon: const Icon(Icons.edit, color: Colors.blue),
                  tooltip: 'Düzenle',
                  onPressed: () => _showCouponDialog(coupon: coupon),
                ),
                IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  tooltip: 'Sil',
                  onPressed: () => _deleteCoupon(coupon['id']),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildInfoChip(
                        'Min. Sipariş',
                        '₺${minOrder.toStringAsFixed(0)}',
                        Icons.shopping_cart,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildInfoChip(
                        'Kullanım',
                        usageLimit != null 
                            ? '$usageCount / $usageLimit' 
                            : '$usageCount',
                        Icons.people,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: isActive 
                              ? Colors.green.shade50 
                              : Colors.red.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              isActive ? Icons.check_circle : Icons.cancel,
                              size: 16,
                              color: isActive ? Colors.green : Colors.red,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              isActive ? 'Aktif' : 'Pasif',
                              style: TextStyle(
                                color: isActive ? Colors.green : Colors.red,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (createdAt != null) ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.calendar_today,
                                size: 14,
                                color: Colors.grey.shade600,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                DateFormat('dd.MM.yyyy').format(
                                  DateTime.parse(createdAt),
                                ),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
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
    );
  }

  Widget _buildInfoChip(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 16, color: Colors.blue.shade700),
          const SizedBox(width: 4),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade600,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
