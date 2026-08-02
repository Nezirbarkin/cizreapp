import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/models/reward_points_model.dart';
import '../../../core/services/reward_points_service.dart';

class PointHistoryScreen extends StatefulWidget {
  const PointHistoryScreen({super.key});

  @override
  State<PointHistoryScreen> createState() => _PointHistoryScreenState();
}

class _PointHistoryScreenState extends State<PointHistoryScreen> {
  final _service = RewardPointsService();
  late Future<List<PointLedgerEntry>> _future = _service.getMyLedger();

  Future<void> _refresh() async {
    setState(() => _future = _service.getMyLedger());
    await _future;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Puan Geçmişi')),
      body: FutureBuilder<List<PointLedgerEntry>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: FilledButton.icon(
                onPressed: _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Puan geçmişini yeniden yükle'),
              ),
            );
          }
          final entries = snapshot.data ?? const <PointLedgerEntry>[];
          if (entries.isEmpty) {
            return const Center(child: Text('Henüz puan işlemi yok.'));
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: entries.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final entry = entries[index];
                final isCredit = entry.direction == PointLedgerDirection.credit;
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor: (isCredit ? Colors.green : Colors.orange)
                        .withValues(alpha: 0.12),
                    child: Icon(
                      isCredit ? Icons.add_rounded : Icons.remove_rounded,
                      color: isCredit ? Colors.green : Colors.orange,
                    ),
                  ),
                  title: Text(entry.entryType.label),
                  subtitle: Text(
                    DateFormat(
                      'dd.MM.yyyy HH:mm',
                    ).format(entry.createdAt.toLocal()),
                  ),
                  trailing: Text(
                    entry.signedPointsLabel,
                    semanticsLabel: entry.signedPointsLabel,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: isCredit ? Colors.green : Colors.orange,
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
