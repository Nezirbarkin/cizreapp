// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/price_alert_model.dart';
import '../services/price_alert_service.dart';
import 'product_detail_screen.dart';

/// Kullanıcının tüm aktif fiyat alarmlarını listeleyen ekran.
/// Favoriler altında veya cüzdandan erişilebilir.
class MyPriceAlertsScreen extends StatefulWidget {
  const MyPriceAlertsScreen({super.key});

  @override
  State<MyPriceAlertsScreen> createState() => _MyPriceAlertsScreenState();
}

class _MyPriceAlertsScreenState extends State<MyPriceAlertsScreen> {
  final _service = PriceAlertService();
  List<PriceAlert> _alerts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final list = await _service.getUserAlerts();
      if (!mounted) return;
      setState(() {
        _alerts = list;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Alarmlar yüklenemedi';
        _loading = false;
      });
    }
  }

  Future<void> _remove(PriceAlert alert) async {
    try {
      await _service.deactivateAlert(alert.id);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kaldırılamadı: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('🔔 Fiyat Alarmlarım'),
        backgroundColor: const Color(0xFF1B5E20),
        foregroundColor: Colors.white,
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _errorView()
                : _alerts.isEmpty
                    ? _emptyView()
                    : ListView.separated(
                        padding: const EdgeInsets.all(12),
                        itemCount: _alerts.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, i) => _alertTile(_alerts[i]),
                      ),
      ),
    );
  }

  Widget _errorView() {
    return ListView(
      children: [
        const SizedBox(height: 80),
        const Icon(Icons.error_outline, size: 60, color: Colors.grey),
        const SizedBox(height: 12),
        Center(
          child: Text(_error!, style: const TextStyle(color: Colors.grey)),
        ),
        const SizedBox(height: 16),
        Center(
          child: ElevatedButton.icon(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
            label: const Text('Tekrar Dene'),
          ),
        ),
      ],
    );
  }

  Widget _emptyView() {
    return ListView(
      children: const [
        SizedBox(height: 100),
        Icon(Icons.notifications_off, size: 60, color: Colors.grey),
        SizedBox(height: 12),
        Center(
          child: Text(
            'Aktif fiyat alarmın yok',
            style: TextStyle(color: Colors.grey),
          ),
        ),
        SizedBox(height: 4),
        Center(
          child: Text(
            'Ürün sayfasından "🔔 Fiyat Alarmı Kur" butonu ile alarm kurabilirsin',
            style: TextStyle(color: Colors.grey, fontSize: 12),
            textAlign: TextAlign.center,
          ),
        ),
      ],
    );
  }

  Widget _alertTile(PriceAlert alert) {
    final currentPrice = alert.productCurrentPrice ?? alert.currentPriceAtCreation;
    final dropPercent = alert.currentPriceAtCreation > 0
        ? ((alert.currentPriceAtCreation - currentPrice) /
                alert.currentPriceAtCreation *
                100)
            : 0.0;
    final alreadyBelow = currentPrice <= alert.targetPrice;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProductDetailScreen(productId: alert.productId),
            ),
          );
          _load();
        },
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Ürün görseli
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 72,
                  height: 72,
                  child: alert.productImageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: alert.productImageUrl!,
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
                      alert.productName ?? 'Ürün',
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        const Icon(Icons.flag, size: 14, color: Color(0xFF1B5E20)),
                        const SizedBox(width: 4),
                        Text(
                          'Hedef: ${alert.targetPrice.toStringAsFixed(2)} ₺',
                          style: const TextStyle(
                            fontSize: 12,
                            color: Color(0xFF1B5E20),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        const Icon(Icons.local_offer, size: 14, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text(
                          'Şu an: ${currentPrice.toStringAsFixed(2)} ₺',
                          style: TextStyle(
                            fontSize: 12,
                            color: alreadyBelow
                                ? const Color(0xFFE53935)
                                : Colors.grey.shade700,
                            fontWeight:
                                alreadyBelow ? FontWeight.bold : FontWeight.normal,
                            decoration: alreadyBelow
                                ? null
                                : TextDecoration.lineThrough,
                          ),
                        ),
                        if (alreadyBelow) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: const Color(0xFFE53935),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: const Text(
                              'HEDEFE ULAŞTI',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (dropPercent > 0) ...[
                      const SizedBox(height: 2),
                      Text(
                        '%${dropPercent.toStringAsFixed(0)} düşüş',
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.notifications_off_outlined),
                tooltip: 'Alarmı kaldır',
                onPressed: () => _remove(alert),
              ),
            ],
          ),
        ),
      ),
    );
  }
}