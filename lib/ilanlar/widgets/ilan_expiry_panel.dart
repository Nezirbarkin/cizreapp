import 'package:flutter/material.dart';

import '../models/ilan_models.dart';
import '../utils/ilan_ui.dart';

/// İlan sahibine yayın bitişi + "Süreyi Uzat" / "Yeniden Yayınla" (Görev 3.9).
///
/// * süresi dolmuş  → kırmızı kutu, "Yeniden Yayınla"
/// * son 7 gün      → turuncu kutu, "Süreyi Uzat"
/// * daha uzun süre → yalnız bitiş tarihi (uzatma son 7 günde açılır)
/// Satıldı/arşiv gibi uzatılamayan durumlarda hiçbir şey çizmez.
class IlanExpiryPanel extends StatelessWidget {
  const IlanExpiryPanel({
    super.key,
    required this.ilan,
    required this.onExtend,
    this.busy = false,
    this.extensionDays,
    this.now,
  });

  final Ilan ilan;
  final VoidCallback onExtend;
  final bool busy;

  /// Uzatmanın ekleyeceği gün (ayarlardaki varsayılan süre); bilinmiyorsa null.
  final int? extensionDays;
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) {
    final current = (now ?? DateTime.now)();
    final expired = IlanUi.isExpired(ilan, current);
    final expiresAt = ilan.expiresAt;
    if (!expired && (ilan.status != IlanStatus.published || expiresAt == null)) {
      return const SizedBox.shrink();
    }
    final canExtend = IlanUi.canExtend(ilan, current);
    final date = expiresAt == null ? null : IlanUi.longDate(expiresAt);
    final days = extensionDays;

    final (Color bg, Color border, Color fg, IconData icon, String title) = expired
        ? (const Color(0xFFFEF2F2), const Color(0xFFFCA5A5), const Color(0xFFB91C1C), Icons.timer_off_outlined, 'Süresi doldu')
        : canExtend
        ? (const Color(0xFFFFF7ED), const Color(0xFFFDBA74), const Color(0xFFC2410C), Icons.hourglass_bottom, IlanUi.remainingLabel(ilan) ?? 'Süresi doluyor')
        : (const Color(0xFFF3F4F6), const Color(0xFFE5E7EB), const Color(0xFF4B5563), Icons.event_available_outlined, IlanUi.remainingLabel(ilan) ?? 'Yayında');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: fg, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(title, style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: fg)),
              ),
            ],
          ),
          if (date != null) ...[
            const SizedBox(height: 4),
            Text(
              expired ? 'İlan $date tarihinde yayından kalktı.' : 'Yayın bitişi: $date',
              style: TextStyle(fontSize: 12.5, color: fg.withValues(alpha: 0.9)),
            ),
          ],
          if (!canExtend) ...[
            const SizedBox(height: 4),
            Text(
              'Bitimine 7 günden az kalınca süreyi uzatabilirsin.',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ] else ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: busy ? null : onExtend,
                style: FilledButton.styleFrom(
                  backgroundColor: fg,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
                icon: busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : Icon(expired ? Icons.replay : Icons.more_time),
                label: Text(
                  [
                    expired ? 'Yeniden Yayınla' : 'Süreyi Uzat',
                    if (days != null) '($days gün)',
                  ].join(' '),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
