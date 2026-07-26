// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../services/flash_sale_service.dart';
import '../screens/flash_sales_screen.dart';

/// MarketScreen ana sayfasında gösterilen "Flash Satış" girişi bandı.
/// Aktif flash sale varsa görünür, tıklayınca FlashSalesScreen'e gider.
/// Realtime ile stok değişse de sadece sayfa açınca güncellenir (basit yaklaşım).
class FlashSaleEntryBanner extends StatefulWidget {
  const FlashSaleEntryBanner({super.key});

  @override
  State<FlashSaleEntryBanner> createState() => _FlashSaleEntryBannerState();
}

class _FlashSaleEntryBannerState extends State<FlashSaleEntryBanner> {
  final _service = FlashSaleService();
  bool _hasActive = false;
  bool _checked = false;

  @override
  void initState() {
    super.initState();
    _checkActive();
  }

  Future<void> _checkActive() async {
    try {
      final sales = await _service.getActiveFlashSales(limit: 1);
      if (mounted) {
        setState(() {
          _hasActive = sales.isNotEmpty;
          _checked = true;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _checked = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Aktif flash sale yoksa hiçbir şey gösterme
    if (!_checked || !_hasActive) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FlashSalesScreen()),
            );
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFFFF5252), Color(0xFFE53935)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.red.withOpacity(0.3),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.flash_on, color: Colors.white, size: 26),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: const [
                      Text(
                        '⚡ Flash Satış Başladı!',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        'Sınırlı süre ve sınırlı stok — kaçırma!',
                        style: TextStyle(color: Colors.white70, fontSize: 11),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}