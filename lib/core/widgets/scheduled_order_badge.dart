import 'package:flutter/material.dart';

import '../utils/schedule_format.dart';

/// "📅 Randevu: Yarın 14:00" rozeti (satıcı, müşteri ve kurye ekranları).
class ScheduledOrderBadge extends StatelessWidget {
  const ScheduledOrderBadge({
    super.key,
    required this.scheduledFor,
    this.isPickup = false,
    this.compact = false,
  });

  final DateTime scheduledFor;
  final bool isPickup;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final color = Colors.deepPurple;
    final label = isPickup ? 'Teslim alma' : 'Randevu';
    return Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 8 : 10, vertical: compact ? 3 : 4),
      decoration: BoxDecoration(
        color: color.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.shade200),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.event_available, size: compact ? 13 : 14, color: color.shade700),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              '$label: ${ScheduleFormat.full(scheduledFor)}',
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: compact ? 10.5 : 11,
                fontWeight: FontWeight.bold,
                color: color.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
