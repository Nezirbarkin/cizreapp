import 'package:flutter/material.dart';

import '../../../core/utils/app_error_handler.dart' show AppErrorHandler;
import '../services/stock_alert_service.dart';

/// Tükenen ürünün detayında "Stoğa gelince haber ver" düğmesi.
///
/// Abonelik varsa "Stoğa gelince bildirim alacaksınız" şeridi ve iptal
/// düğmesi gösterilir (fiyat alarmı şeridiyle aynı düzen).
class StockAlertButton extends StatefulWidget {
  const StockAlertButton({super.key, required this.productId, this.service});

  final String productId;

  /// Testte sahte servis vermek için; boşsa gerçek servis.
  final StockAlertService? service;

  @override
  State<StockAlertButton> createState() => _StockAlertButtonState();
}

class _StockAlertButtonState extends State<StockAlertButton> {
  static const _color = Color(0xFF1565C0);

  late final StockAlertService _service =
      widget.service ?? StockAlertService();

  /// null: yükleniyor.
  bool? _subscribed;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var subscribed = false;
    try {
      subscribed = await _service.isSubscribed(widget.productId);
    } catch (_) {
      // Okunamazsa düğme abone değilmiş gibi görünür; dokunuş yine çalışır.
    }
    if (mounted) setState(() => _subscribed = subscribed);
  }

  Future<void> _toggle() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    if (!_service.isSignedIn) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Stok bildirimi için giriş yapmalısınız')),
      );
      return;
    }
    final subscribe = _subscribed != true;
    setState(() => _busy = true);
    try {
      if (subscribe) {
        await _service.subscribe(widget.productId);
      } else {
        await _service.unsubscribe(widget.productId);
      }
      if (!mounted) return;
      setState(() => _subscribed = subscribe);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            subscribe
                ? '🔔 Ürün stoğa gelince bildirim alacaksınız'
                : 'Stok bildirimi kapatıldı',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(AppErrorHandler.handleError(e))),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subscribed = _subscribed;
    if (subscribed == null) return const SizedBox.shrink();

    if (subscribed) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: _color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: _color),
        ),
        child: Row(
          children: [
            const Icon(Icons.notifications_active, color: _color, size: 18),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'Stoğa gelince bildirim alacaksınız',
                style: TextStyle(
                  color: _color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            IconButton(
              tooltip: 'Stok bildirimini kapat',
              icon: const Icon(Icons.close, size: 18),
              color: _color,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
              onPressed: _busy ? null : _toggle,
            ),
          ],
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: _busy ? null : _toggle,
      icon: _busy
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.notifications_outlined, size: 18),
      label: const Text('Stoğa gelince haber ver'),
      style: OutlinedButton.styleFrom(
        foregroundColor: _color,
        side: const BorderSide(color: _color),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      ),
    );
  }
}
