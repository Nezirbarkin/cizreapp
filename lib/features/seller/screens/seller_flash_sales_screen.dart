// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import '../../../core/models/flash_sale_model.dart';
import '../../../core/models/product_model.dart';
import '../../market/services/flash_sale_service.dart';
import '../../market/services/product_service.dart';

/// Satıcı: kendi mağazası için flash satış yönetim ekranı.
/// - Aktif/geçmiş flash sale'ler
/// - "Yeni Flash Satış" butonu (ürün seç + fiyat + süre + stok)
class SellerFlashSalesScreen extends StatefulWidget {
  final String shopId;
  const SellerFlashSalesScreen({super.key, required this.shopId});

  @override
  State<SellerFlashSalesScreen> createState() => _SellerFlashSalesScreenState();
}

class _SellerFlashSalesScreenState extends State<SellerFlashSalesScreen> {
  final _service = FlashSaleService();
  final _productService = ProductService();
  List<FlashSale> _sales = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await _service.getMyShopFlashSales(widget.shopId);
      if (mounted) {
        setState(() {
          _sales = list;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _showCreateDialog() async {
    final products = await _productService.getShopProducts(widget.shopId);
    if (!mounted) return;
    if (products.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mağazada ürün yok, önce ürün ekleyin')),
      );
      return;
    }
    await showDialog(
      context: context,
      builder: (_) => _CreateFlashSaleDialog(
        shopId: widget.shopId,
        products: products,
      ),
    );
    _load();
  }

  Future<void> _deactivate(FlashSale sale) async {
    try {
      await _service.deactivateFlashSale(sale.id);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('⚡ Flash Satış Yönetimi'),
        backgroundColor: const Color(0xFFE53935),
        foregroundColor: Colors.white,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateDialog,
        backgroundColor: const Color(0xFFE53935),
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Yeni Flash Satış', style: TextStyle(color: Colors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sales.isEmpty
              ? _emptyView()
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: _sales.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, i) => _saleTile(_sales[i]),
                  ),
                ),
    );
  }

  Widget _emptyView() {
    return ListView(
      children: const [
        SizedBox(height: 100),
        Icon(Icons.flash_off, size: 60, color: Colors.grey),
        SizedBox(height: 12),
        Center(
          child: Text(
            'Henüz flash satış oluşturmadınız',
            style: TextStyle(color: Colors.grey),
          ),
        ),
        SizedBox(height: 4),
        Center(
          child: Text(
            'Sağ alttaki buton ile yeni flash satış oluşturabilirsiniz',
            style: TextStyle(color: Colors.grey, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _saleTile(FlashSale sale) {
    final dateFmt = DateFormat('dd.MM.yyyy HH:mm');
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: SizedBox(
                width: 56,
                height: 56,
                child: sale.productImageUrl != null
                    ? CachedNetworkImage(
                        imageUrl: sale.productImageUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          color: Colors.grey.shade200,
                          child: const Icon(Icons.image),
                        ),
                      )
                    : Container(
                        color: Colors.grey.shade200,
                        child: const Icon(Icons.image),
                      ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    sale.productName ?? 'Ürün',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    '${sale.flashPrice.toStringAsFixed(2)} ₺ (eski ${sale.originalPrice.toStringAsFixed(2)} ₺)',
                    style: const TextStyle(
                      color: Color(0xFFE53935),
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 6,
                    children: [
                      _statusChip(sale),
                      Text(
                        'Stok: ${sale.remainingStock}/${sale.stockLimit}',
                        style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                      ),
                    ],
                  ),
                  Text(
                    'Bitiş: ${dateFmt.format(sale.endAt.toLocal())}',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              onSelected: (v) {
                if (v == 'deactivate') _deactivate(sale);
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: 'deactivate',
                  child: Row(
                    children: [
                      Icon(Icons.pause, color: Colors.orange),
                      SizedBox(width: 8),
                      Text('Durdur'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statusChip(FlashSale sale) {
    final now = DateTime.now();
    Color bg;
    String text;
    if (!sale.isActive) {
      bg = Colors.grey;
      text = 'PASİF';
    } else if (now.isBefore(sale.startAt)) {
      bg = Colors.blue;
      text = 'YAKINDA';
    } else if (now.isAfter(sale.endAt)) {
      bg = Colors.grey;
      text = 'BİTTİ';
    } else {
      bg = const Color(0xFFE53935);
      text = 'AKTİF';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// Yeni flash satış oluşturma dialog'ı.
class _CreateFlashSaleDialog extends StatefulWidget {
  final String shopId;
  final List<Product> products;
  const _CreateFlashSaleDialog({
    required this.shopId,
    required this.products,
  });

  @override
  State<_CreateFlashSaleDialog> createState() => _CreateFlashSaleDialogState();
}

class _CreateFlashSaleDialogState extends State<_CreateFlashSaleDialog> {
  final _service = FlashSaleService();
  Product? _selected;
  final _flashPriceCtrl = TextEditingController();
  final _stockCtrl = TextEditingController();
  Duration _duration = const Duration(hours: 6);
  bool _saving = false;

  @override
  void dispose() {
    _flashPriceCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_selected == null) {
      _snack('Ürün seçin');
      return;
    }
    final flashPrice = double.tryParse(_flashPriceCtrl.text);
    final stock = int.tryParse(_stockCtrl.text);
    if (flashPrice == null || flashPrice <= 0 || flashPrice >= _selected!.price) {
      _snack('Flash fiyat, mevcut fiyattan düşük olmalı');
      return;
    }
    if (stock == null || stock <= 0) {
      _snack('Geçerli bir stok girin');
      return;
    }
    setState(() => _saving = true);
    try {
      final now = DateTime.now();
      await _service.createFlashSale(
        productId: _selected!.id,
        shopId: widget.shopId,
        originalPrice: _selected!.price,
        flashPrice: flashPrice,
        stockLimit: stock,
        startAt: now,
        endAt: now.add(_duration),
      );
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Flash satış başlatıldı!')),
        );
      }
    } catch (e) {
      setState(() => _saving = false);
      _snack('Hata: $e');
    }
  }

  void _snack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                '⚡ Yeni Flash Satış',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<Product>(
                value: _selected,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Ürün seçin',
                  border: OutlineInputBorder(),
                ),
                items: widget.products
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(
                            '${p.name} (${p.effectivePrice.toStringAsFixed(2)} ₺)',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (v) => setState(() => _selected = v),
              ),
              if (_selected != null) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'Mevcut fiyat: ${_selected!.price.toStringAsFixed(2)} ₺\n'
                    'Mevcut stok: ${_selected!.stockQuantity}',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _flashPriceCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Flash fiyat (₺)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _stockCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Stok adedi',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              const Text('Süre:', style: TextStyle(fontWeight: FontWeight.w600)),
              Wrap(
                spacing: 6,
                children: [
                  _durationChip('1 Saat', const Duration(hours: 1)),
                  _durationChip('6 Saat', const Duration(hours: 6)),
                  _durationChip('12 Saat', const Duration(hours: 12)),
                  _durationChip('1 Gün', const Duration(days: 1)),
                  _durationChip('3 Gün', const Duration(days: 3)),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: _saving ? null : () => Navigator.of(context).pop(),
                      child: const Text('İptal'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton.icon(
                      onPressed: _saving ? null : _save,
                      icon: _saving
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.flash_on, size: 18),
                      label: Text(_saving ? 'Oluşturuluyor...' : 'Başlat'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFE53935),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _durationChip(String label, Duration d) {
    final selected = _duration == d;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setState(() => _duration = d),
      selectedColor: const Color(0xFFE53935).withOpacity(0.2),
    );
  }
}