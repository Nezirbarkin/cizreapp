import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/fraud_signal.dart';
import '../services/fraud_detection_service.dart';

class FraudSignalsContent extends StatefulWidget {
  const FraudSignalsContent({super.key});

  @override
  State<FraudSignalsContent> createState() => _FraudSignalsContentState();
}

class _FraudSignalsContentState extends State<FraudSignalsContent> {
  final _service = FraudDetectionService();
  List<FraudSignal> _signals = const [];
  FraudSignalStatus? _status;
  FraudSignalType? _type;
  bool _loading = true;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final signals = await _service.listSignals(status: _status, type: _type);
      if (mounted) setState(() => _signals = signals);
    } catch (error) {
      _showMessage('Sinyaller yüklenemedi: $error', error: true);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _scan() async {
    setState(() => _scanning = true);
    try {
      final result = await _service.scan();
      _showMessage(
        '${result.detected} risk göstergesi tespit edildi/güncellendi.',
      );
      await _load();
    } catch (error) {
      _showMessage('Tarama tamamlanamadı: $error', error: true);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _review(FraudSignal signal) async {
    var selectedStatus = signal.status;
    final noteController = TextEditingController(text: signal.adminNote);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Sinyali İncele'),
          content: SizedBox(
            width: 520,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  signal.title,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(signal.description),
                const SizedBox(height: 16),
                DropdownButtonFormField<FraudSignalStatus>(
                  initialValue: selectedStatus,
                  decoration: const InputDecoration(
                    labelText: 'İnceleme durumu',
                    border: OutlineInputBorder(),
                  ),
                  items: FraudSignalStatus.values
                      .map(
                        (status) => DropdownMenuItem(
                          value: status,
                          child: Text(status.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setDialogState(() => selectedStatus = value);
                    }
                  },
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: noteController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Admin notu',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Vazgeç'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.review(
        signalId: signal.id,
        status: selectedStatus,
        note: noteController.text.trim(),
      );
      _showMessage('İnceleme kaydedildi.');
      await _load();
    } catch (error) {
      _showMessage('İnceleme kaydedilemedi: $error', error: true);
    } finally {
      noteController.dispose();
    }
  }

  void _showMessage(String message, {bool error = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: error ? Colors.red.shade700 : Colors.green.shade700,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 180,
                child: DropdownButtonFormField<FraudSignalStatus?>(
                  initialValue: _status,
                  decoration: const InputDecoration(
                    labelText: 'Durum',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tümü')),
                    ...FraudSignalStatus.values.map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.label),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    _status = value;
                    _load();
                  },
                ),
              ),
              SizedBox(
                width: 210,
                child: DropdownButtonFormField<FraudSignalType?>(
                  initialValue: _type,
                  decoration: const InputDecoration(
                    labelText: 'Sinyal türü',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('Tümü')),
                    ...FraudSignalType.values.map(
                      (value) => DropdownMenuItem(
                        value: value,
                        child: Text(value.label),
                      ),
                    ),
                  ],
                  onChanged: (value) {
                    _type = value;
                    _load();
                  },
                ),
              ),
              FilledButton.icon(
                onPressed: _scanning ? null : _scan,
                icon: _scanning
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.radar),
                label: Text(
                  _scanning ? 'Taranıyor...' : 'Risk Taraması Başlat',
                ),
              ),
              IconButton(
                onPressed: _loading ? null : _load,
                icon: const Icon(Icons.refresh),
                tooltip: 'Yenile',
              ),
            ],
          ),
        ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _signals.isEmpty
              ? const _EmptyState()
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  itemCount: _signals.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, index) => _SignalCard(
                    signal: _signals[index],
                    onReview: () => _review(_signals[index]),
                  ),
                ),
        ),
      ],
    );
  }
}

class _SignalCard extends StatelessWidget {
  const _SignalCard({required this.signal, required this.onReview});
  final FraudSignal signal;
  final VoidCallback onReview;

  @override
  Widget build(BuildContext context) {
    final color = signal.riskScore >= 80
        ? Colors.red
        : signal.riskScore >= 60
        ? Colors.deepOrange
        : signal.riskScore >= 40
        ? Colors.orange
        : Colors.blue;
    final date = DateFormat(
      'dd.MM.yyyy HH:mm',
    ).format(signal.lastDetectedAt.toLocal());
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onReview,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    backgroundColor: color.withValues(alpha: .12),
                    child: Text(
                      '${signal.riskScore}',
                      style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          signal.title,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          signal.userName ?? signal.userEmail ?? signal.userId,
                          style: TextStyle(color: Colors.grey.shade700),
                        ),
                      ],
                    ),
                  ),
                  Chip(label: Text(signal.status.label)),
                ],
              ),
              const SizedBox(height: 10),
              Text(signal.description),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  Chip(
                    avatar: const Icon(Icons.category, size: 16),
                    label: Text(signal.signalType.label),
                  ),
                  Chip(
                    avatar: const Icon(Icons.repeat, size: 16),
                    label: Text('${signal.occurrenceCount} tespit'),
                  ),
                  Chip(
                    avatar: const Icon(Icons.schedule, size: 16),
                    label: Text(date),
                  ),
                ],
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Teknik kanıtlar'),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SelectableText(
                      const JsonEncoder.withIndent(
                        '  ',
                      ).convert(signal.evidence),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: onReview,
                  icon: const Icon(Icons.fact_check),
                  label: const Text('İncele'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();
  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.verified_user_outlined, size: 64, color: Colors.green),
        SizedBox(height: 12),
        Text('Filtreye uygun dolandırıcılık sinyali yok.'),
      ],
    ),
  );
}
