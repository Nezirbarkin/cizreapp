// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../../../core/models/price_alert_model.dart';
import '../services/price_alert_service.dart';

/// Ürün detayda "🔔 Fiyat Alarmı Kur" butonuna basınca açılan modal.
/// Hedef fiyat slider'ı + mevcut fiyat referansı + kaydet.
class PriceAlertDialog extends StatefulWidget {
  final String productId;
  final String productName;
  final double currentPrice;

  const PriceAlertDialog({
    super.key,
    required this.productId,
    required this.productName,
    required this.currentPrice,
  });

  @override
  State<PriceAlertDialog> createState() => _PriceAlertDialogState();
}

class _PriceAlertDialogState extends State<PriceAlertDialog> {
  final _service = PriceAlertService();
  late double _targetPrice;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    // Mevcut fiyatın %10 altı varsayılan hedef
    _targetPrice = (widget.currentPrice * 0.9).clamp(1, widget.currentPrice - 1);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      await _service.setAlert(
        productId: widget.productId,
        targetPrice: _targetPrice,
        currentPrice: widget.currentPrice,
      );
      if (!mounted) return;
      final messenger = ScaffoldMessenger.of(context);
      Navigator.of(context).pop(true);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            '🔔 Alarm kuruldu: ${_targetPrice.toStringAsFixed(2)} ₺ altında bildirim alacaksınız',
          ),
          backgroundColor: const Color(0xFF1B5E20),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final diff = widget.currentPrice - _targetPrice;
    final diffPercent = (diff / widget.currentPrice) * 100;

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active,
                    color: Color(0xFF1B5E20), size: 24),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'Fiyat Alarmı Kur',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(false),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.productName,
              style: const TextStyle(color: Colors.grey, fontSize: 13),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Mevcut fiyat:'),
                      Text(
                        '${widget.currentPrice.toStringAsFixed(2)} ₺',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Hedef fiyat:'),
                      Text(
                        '${_targetPrice.toStringAsFixed(2)} ₺',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFE53935),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text('Kazanç:'),
                      Text(
                        '${diff.toStringAsFixed(2)} ₺ (%${diffPercent.toStringAsFixed(0)})',
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Slider(
              min: (widget.currentPrice * 0.3)
                  .clamp(1, widget.currentPrice - 1)
                  .toDouble(),
              max: (widget.currentPrice - 1).toDouble(),
              divisions: 30,
              value: _targetPrice,
              label: '${_targetPrice.toStringAsFixed(2)} ₺',
              activeColor: const Color(0xFF1B5E20),
              onChanged: (v) => setState(() => _targetPrice = v),
            ),
            const Text(
              'Slider ile hedef fiyatı seçin. Ürün bu fiyata düştüğünde bildirim alacaksınız.',
              style: TextStyle(fontSize: 11, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: TextButton(
                    onPressed: _saving
                        ? null
                        : () => Navigator.of(context).pop(false),
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
                        : const Icon(Icons.notifications_active, size: 18),
                    label: Text(_saving ? 'Kaydediliyor...' : 'Alarmı Kur'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1B5E20),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}