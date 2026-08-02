import 'package:flutter/material.dart';

import '../../../core/services/transfer_service.dart';
import '../../shop/services/cancellation_request_service.dart';

// ========== HAVALE ONAYLARI TAB ETİKETİ (bekleyen sayısı rozeti) ==========
class TransferConfirmationsTabLabel extends StatefulWidget {
  const TransferConfirmationsTabLabel({super.key});

  @override
  State<TransferConfirmationsTabLabel> createState() =>
      _TransferConfirmationsTabLabelState();
}

class _TransferConfirmationsTabLabelState
    extends State<TransferConfirmationsTabLabel> {
  final TransferService _service = TransferService();
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final count = await _service.getPendingCount();
    if (!mounted) return;
    setState(() => _pendingCount = count);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Havale Onayları'),
        if (_pendingCount > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$_pendingCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ========== İPTAL TALEPLERİ TAB ETİKETİ (bekleyen sayısı rozeti) ==========
class CancellationRequestsTabLabel extends StatefulWidget {
  const CancellationRequestsTabLabel({super.key});

  @override
  State<CancellationRequestsTabLabel> createState() =>
      _CancellationRequestsTabLabelState();
}

class _CancellationRequestsTabLabelState
    extends State<CancellationRequestsTabLabel> {
  final CancellationRequestService _service = CancellationRequestService();
  int _pendingCount = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final count = await _service.getPendingCount();
    if (!mounted) return;
    setState(() => _pendingCount = count);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('İptal Talepleri'),
        if (_pendingCount > 0) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: Colors.red,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '$_pendingCount',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ========== CÜZDAN YÖNETİMİ APPBAR ROZETİ (bekleyen işlem sayısı) ==========
// Cüzdan Yönetimi anabaşlığında sağ üstte bildirim zil ikonu + toplam badge gösterir.
// Havale onayları + iptal talepleri sayısını toplar.
class WalletNotificationBell extends StatefulWidget {
  const WalletNotificationBell({super.key});

  @override
  State<WalletNotificationBell> createState() => _WalletNotificationBellState();
}

class _WalletNotificationBellState extends State<WalletNotificationBell> {
  final TransferService _transferService = TransferService();
  final CancellationRequestService _cancellationService =
      CancellationRequestService();
  int _totalPending = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait<int>([
        _transferService.getPendingCount(),
        _cancellationService.getPendingCount(),
      ]);
      final transferCount = results[0];
      final cancellationCount = results[1];
      if (!mounted) return;
      setState(() => _totalPending = transferCount + cancellationCount);
    } catch (e) {
      debugPrint('WalletNotificationBell yüklenemedi: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        IconButton(
          icon: Icon(
            _totalPending > 0
                ? Icons.notifications_active
                : Icons.notifications_none,
            color: _totalPending > 0 ? Colors.red : Colors.grey,
          ),
          onPressed: () {
            // Bildirimler sayfasına git veya tab'ı Havale Onayları'na atla
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  _totalPending > 0
                      ? '$_totalPending bekleyen işlem var'
                      : 'Bekleyen işlem yok',
                ),
                duration: const Duration(seconds: 2),
              ),
            );
          },
        ),
        if (_totalPending > 0)
          Positioned(
            right: 6,
            top: 6,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(minWidth: 18),
              child: Text(
                _totalPending > 99 ? '99+' : '$_totalPending',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
                textAlign: TextAlign.center,
              ),
            ),
          ),
      ],
    );
  }
}
