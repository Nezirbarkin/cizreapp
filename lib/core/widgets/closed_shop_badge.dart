// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';

/// Dükkan geçici kapalıyken ürün kartlarında / detayında gösterilen
/// küçük rozet. Ürün listelerinde "Sepete Ekle" butonu yanında veya
/// ürün adının altında kullanılır.
///
/// [global] true ise global sipariş alımı kapalıdır; rozet "Siparişler Kapalı"
/// metniyle amber tonunda gösterilir. Aksi halde dükkan kapalıdır ve
/// "Geçici Kapalı" metniyle kırmızı tonunda gösterilir.
class ClosedShopBadge extends StatelessWidget {
  final bool global;

  const ClosedShopBadge({super.key, this.global = false});

  @override
  Widget build(BuildContext context) {
    final color = global ? Colors.amber.shade700 : Colors.red.shade700;
    final bgColor = global ? Colors.amber.shade100 : Colors.red.shade50;
    final label = global ? 'Siparişler Kapalı' : 'Geçici Kapalı';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.4), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_clock, size: 12, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}

/// Ürün detayı / dükkan detayı üstünde gösterilen, daha belirgin tam genişlik
/// banner. [global] true ise global kapatma mesajını, false ise dükkan kapalı
/// mesajını gösterir. shop_detail_screen.dart'taki banner ile aynı görsel dil.
class ClosedShopBanner extends StatelessWidget {
  final bool global;

  const ClosedShopBanner({super.key, this.global = false});

  @override
  Widget build(BuildContext context) {
    final color = global ? Colors.amber : Colors.orange;
    final icon = global ? Icons.block : Icons.lock_clock;
    final title = global ? '🚫 Sipariş Alma Geçici Olarak Kapalı' : '🕒 Geçici Kapalı';
    final subtitle = global
        ? 'Tüm mağazalarda sipariş alma geçici olarak durduruldu.'
        : 'Bu dükkan şu anda sipariş almıyor. Dükkan açıldığında ürünleri sepete ekleyebilirsiniz.';

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.shade200),
      ),
      child: Row(
        children: [
          Icon(icon, color: color.shade700, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: color.shade700,
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: color.shade800,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}