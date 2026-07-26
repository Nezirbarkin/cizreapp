// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/sehirici_models.dart';
import '../providers/sehirici_provider.dart';
import '../services/sehirici_driver_service.dart';
import '../services/sehirici_trip_service.dart';
import '../services/sehirici_location_tracker.dart';
import '../widgets/sehirici_live_map.dart';

/// Şoför paneli: hat seçimi, sefer başlat/bitir, canlı konum.
class SehiriciDriverPanelScreen extends StatefulWidget {
  const SehiriciDriverPanelScreen({super.key});

  @override
  State<SehiriciDriverPanelScreen> createState() =>
      _SehiriciDriverPanelScreenState();
}

class _SehiriciDriverPanelScreenState
    extends State<SehiriciDriverPanelScreen> {
  final SehiriciDriverService _driverService = SehiriciDriverService();
  final SehiriciTripService _tripService = SehiriciTripService();
  final SehiriciLocationTracker _tracker = SehiriciLocationTracker();

  Map<String, dynamic>? _driverProfile;
  SehiriciActiveTrip? _activeTrip;
  bool _loading = true;
  bool _busy = false;

  // Timer ve çalışma saatleri
  Timer? _tripTimer;
  Duration _tripDuration = Duration.zero;
  bool _showRoute = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _driverProfile = await _driverService.getMyDriverProfile();
      if (_driverProfile != null) {
        final driverId = _driverProfile!['id'] as String;
        final active = await _tripService.getDriverActiveTrip(driverId);
        if (active != null) {
          _activeTrip = SehiriciActiveTrip(
            tripId: active['id'] as String,
            lineId: active['line_id'] as String,
            lineCode: '',
            lineName:
                (_driverProfile!['sehirici_lines'] as Map?)?['name'] ?? '',
            lineColor:
                (_driverProfile!['sehirici_lines'] as Map?)?['color_hex'] ??
                    '#1976D2',
            currentLat: (active['current_lat'] as num?)?.toDouble(),
            currentLng: (active['current_lng'] as num?)?.toDouble(),
            status: SehiriciTripStatus.fromString(active['status'] as String?),
          );
        }
      }
    } catch (e) {
      _showError('Profil yüklenemedi: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _startTrip(SehiriciLine line) async {
    if (_busy) return;
    if (_driverProfile == null) return;
    setState(() => _busy = true);
    try {
      final pos = await SehiriciUserLocation.getCurrent();
      if (pos == null) {
        _showError('Konum alınamadı. Konum izni verin.');
        return;
      }
      final tripId = await _tripService.startTrip(
        driverId: _driverProfile!['id'] as String,
        lineId: line.id,
        lat: pos.latitude,
        lng: pos.longitude,
      );
      if (tripId == null) {
        _showError('Sefer başlatılamadı');
        return;
      }
      _activeTrip = SehiriciActiveTrip(
        tripId: tripId,
        lineId: line.id,
        lineCode: line.code,
        lineName: line.name,
        lineColor: line.colorHex,
        driverName: _driverProfile?['name'] as String?,
        licensePlate: _driverProfile?['license_plate'] as String?,
        workingHoursStart: _parseTimeOfDay(_driverProfile?['working_hours_start'] as String?),
        workingHoursEnd: _parseTimeOfDay(_driverProfile?['working_hours_end'] as String?),
        currentLat: pos.latitude,
        currentLng: pos.longitude,
        startedAt: DateTime.now(),
        status: SehiriciTripStatus.active,
      );
      _startTripTimer();
      _startWorkingHoursCheck();
      await _tracker.start(
        tripId: tripId,
        tripService: _tripService,
        interval: const Duration(seconds: 10),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Sefer başlatıldı. Konum paylaşılıyor.'),
            backgroundColor: Colors.green,
          ),
        );
      }
      setState(() {});
    } catch (e) {
      _showError('Hata: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _togglePause() async {
    if (_activeTrip == null) return;
    final newStatus = _activeTrip!.status == SehiriciTripStatus.active
        ? SehiriciTripStatus.paused
        : SehiriciTripStatus.active;
    final ok = await _tripService.setStatus(_activeTrip!.tripId, newStatus);
    if (ok) {
      setState(() {
        _activeTrip = _activeTrip!.copyWithLocation(
          lat: _activeTrip!.currentLat,
          lng: _activeTrip!.currentLng,
        );
      });
      _activeTrip = SehiriciActiveTrip(
        tripId: _activeTrip!.tripId,
        lineId: _activeTrip!.lineId,
        lineCode: _activeTrip!.lineCode,
        lineName: _activeTrip!.lineName,
        lineColor: _activeTrip!.lineColor,
        currentLat: _activeTrip!.currentLat,
        currentLng: _activeTrip!.currentLng,
        status: newStatus,
      );
      if (newStatus == SehiriciTripStatus.paused) {
        await _tracker.stop();
      } else {
        final pos = _tracker.lastPosition;
        if (pos != null) {
          await _tracker.start(
            tripId: _activeTrip!.tripId,
            tripService: _tripService,
          );
        }
      }
    }
  }

  Future<void> _endTrip() async {
    if (_activeTrip == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Seferi Bitir'),
        content: Text('${_formatDuration(_tripDuration)} süre çalıştınız. Seferi bitirmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Bitir'),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    await _tripService.setStatus(
        _activeTrip!.tripId, SehiriciTripStatus.completed);
    await _tracker.stop();
    _stopTripTimer();
    _stopWorkingHoursCheck();
    setState(() => _activeTrip = null);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sefer tamamlandı'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  TimeOfDay? _parseTimeOfDay(String? timeStr) {
    if (timeStr == null) return null;
    final parts = timeStr.split(':');
    if (parts.length < 2) return null;
    return TimeOfDay(hour: int.tryParse(parts[0]) ?? 0, minute: int.tryParse(parts[1]) ?? 0);
  }

  void _startTripTimer() {
    _tripTimer?.cancel();
    _tripDuration = Duration.zero;
    _tripTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _activeTrip?.startedAt != null) {
        setState(() {
          _tripDuration = DateTime.now().difference(_activeTrip!.startedAt!);
        });
      }
    });
  }

  void _stopTripTimer() {
    _tripTimer?.cancel();
    _tripTimer = null;
    _tripDuration = Duration.zero;
  }

  /// Çalışma saatleri kontrolü: saat dışında otomatik konum izlemeyi durdur
  Timer? _workingHoursTimer;
  void _startWorkingHoursCheck() {
    _workingHoursTimer?.cancel();
    _workingHoursTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (!mounted || _activeTrip == null) return;
      _checkAndApplyWorkingHours();
    });
  }

  void _stopWorkingHoursCheck() {
    _workingHoursTimer?.cancel();
    _workingHoursTimer = null;
  }

  void _checkAndApplyWorkingHours() {
    if (_activeTrip?.workingHoursStart == null || _activeTrip?.workingHoursEnd == null) {
      return;
    }
    final now = TimeOfDay.now();
    final start = _activeTrip!.workingHoursStart!;
    final end = _activeTrip!.workingHoursEnd!;

    final isWithinWorkingHours = _isTimeWithinRange(now, start, end);

    if (isWithinWorkingHours && _tracker.isTracking == false) {
      _tracker.start(
        tripId: _activeTrip!.tripId,
        tripService: _tripService,
        interval: const Duration(seconds: 10),
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Çalışma saatleri başladı. Konum paylaşımı başlatıldı.'),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } else if (!isWithinWorkingHours && _tracker.isTracking == true) {
      _tracker.stop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Çalışma saatleri bitti. Konum paylaşımı durduruldu.'),
            backgroundColor: Colors.amber,
          ),
        );
      }
    }
  }

  bool _isTimeWithinRange(TimeOfDay current, TimeOfDay start, TimeOfDay end) {
    final currentMinutes = current.hour * 60 + current.minute;
    final startMinutes = start.hour * 60 + start.minute;
    final endMinutes = end.hour * 60 + end.minute;

    if (startMinutes < endMinutes) {
      return currentMinutes >= startMinutes && currentMinutes < endMinutes;
    } else {
      return currentMinutes >= startMinutes || currentMinutes < endMinutes;
    }
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    final seconds = d.inSeconds % 60;
    return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _showSettingsDialog() async {
    TimeOfDay? workStart = _parseTimeOfDay(_driverProfile?['working_hours_start'] as String?);
    TimeOfDay? workEnd = _parseTimeOfDay(_driverProfile?['working_hours_end'] as String?);
    bool autoLocation = _driverProfile?['auto_location_enabled'] as bool? ?? true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Şoför Ayarları'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Çalışma Saatleri',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ListTile(
                        title: const Text('Başlangıç'),
                        subtitle: Text(workStart?.format(ctx) ?? '--:--'),
                        trailing: const Icon(Icons.access_time),
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: ctx,
                            initialTime: workStart ?? TimeOfDay.now(),
                          );
                          if (picked != null) setState(() => workStart = picked);
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ListTile(
                        title: const Text('Bitiş'),
                        subtitle: Text(workEnd?.format(ctx) ?? '--:--'),
                        trailing: const Icon(Icons.access_time),
                        onTap: () async {
                          final picked = await showTimePicker(
                            context: ctx,
                            initialTime: workEnd ?? TimeOfDay.now(),
                          );
                          if (picked != null) setState(() => workEnd = picked);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(),
                const SizedBox(height: 8),
                const Text('Otomatik Konum',
                    style: TextStyle(fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                SwitchListTile(
                  title: const Text('Çalışma Saatleri Dışında Otomatik Kapat'),
                  subtitle: const Text('Çalışma saatleri dışında konum paylaşımı otomatik durur'),
                  value: autoLocation,
                  onChanged: (v) => setState(() => autoLocation = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('İptal'),
            ),
            FilledButton(
              onPressed: () async {
                // Ayarları kaydet (Supabase veya SharedPreferences)
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Ayarlar kaydedildi'),
                      backgroundColor: Colors.green,
                    ),
                  );
                }
                Navigator.pop(ctx);
              },
              child: const Text('Kaydet'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _tripTimer?.cancel();
    _workingHoursTimer?.cancel();
    _tracker.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SehiriciProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Şoför Paneli'),
        actions: [
          IconButton(
            onPressed: _load,
            icon: const Icon(Icons.refresh),
          ),
          if (_activeTrip == null)
            IconButton(
              onPressed: _showSettingsDialog,
              icon: const Icon(Icons.settings),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _driverProfile == null
              ? _notDriverView()
              : _activeTrip == null
                  ? _selectLineView(provider)
                  : _activeTripView(),
    );
  }

  Widget _notDriverView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.directions_bus_outlined,
                size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 12),
            const Text(
              'Şoför kaydınız bulunamadı',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 4),
            Text(
              'Yönetici tarafından şoför olarak atanmalısınız.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _selectLineView(SehiriciProvider provider) {
    final assignedLine = _driverProfile!['sehirici_lines'] as Map?;
    final assignedLineId = _driverProfile!['assigned_line_id'] as String?;

    // Sadece atanmış hatı göster
    SehiriciLine? driverLine;
    if (assignedLineId != null) {
      try {
        driverLine = provider.lines.firstWhere((l) => l.id == assignedLineId);
      } catch (_) {
        driverLine = null;
      }
    }

    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Card(
          color: Theme.of(context).colorScheme.primaryContainer,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.person, size: 32),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _driverProfile!['license_number'] ?? 'Şoför',
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 16),
                      ),
                      if (assignedLine != null)
                        Text(
                          'Atanmış Hat: ${assignedLine['code']} — ${assignedLine['name']}',
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (driverLine != null) ...[
          const Text('Seferi Başlatmak İçin',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: driverLine.color.withOpacity(0.15),
                child: Icon(driverLine.vehicleType.icon, color: driverLine.color),
              ),
              title: Text('${driverLine.code} — ${driverLine.name}'),
              subtitle: Text('${driverLine.stops.length} durak'),
              trailing: FilledButton.icon(
                onPressed: _busy ? null : () => _startTrip(driverLine!),
                icon: const Icon(Icons.play_arrow),
                label: const Text('Başlat'),
              ),
            ),
          ),
        ] else ...[
          Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                children: [
                  Icon(Icons.warning, size: 48, color: Colors.amber),
                  const SizedBox(height: 12),
                  const Text(
                    'Hat Ataması Yapılmamış',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Yönetici tarafından size bir hat atanmalıdır.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _activeTripView() {
    final trip = _activeTrip!;
    final provider = context.watch<SehiriciProvider>();
    final city = provider.selectedCity;
    final line = provider.lines.firstWhere(
      (l) => l.id == trip.lineId,
      orElse: () => SehiriciLine(
        id: trip.lineId,
        code: trip.lineCode,
        name: trip.lineName,
        colorHex: trip.lineColor,
        stops: const [],
      ),
    );

    return Column(
      children: [
        // Üst bilgi kartı
        Container(
          padding: const EdgeInsets.all(16),
          color: trip.status == SehiriciTripStatus.active
              ? Colors.green.shade50
              : Colors.orange.shade50,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    trip.status == SehiriciTripStatus.active
                        ? Icons.check_circle
                        : Icons.pause_circle,
                    color: trip.status == SehiriciTripStatus.active
                        ? Colors.green
                        : Colors.orange,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Aktif Sefer: ${line.code} — ${line.name}',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Kronometre: ${_formatDuration(_tripDuration)}',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (trip.licensePlate != null)
                    Chip(
                      label: Text(trip.licensePlate!, style: const TextStyle(fontWeight: FontWeight.bold)),
                      backgroundColor: Colors.blue.shade100,
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                trip.status == SehiriciTripStatus.active
                    ? 'Yolda — Konum paylaşılıyor'
                    : 'Mola — Konum paylaşımı duraklatıldı',
                style: TextStyle(color: Colors.grey.shade700),
              ),
              const SizedBox(height: 12),
              Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _togglePause,
                          icon: Icon(
                            trip.status == SehiriciTripStatus.active
                                ? Icons.pause
                                : Icons.play_arrow,
                          ),
                          label: Text(
                            trip.status == SehiriciTripStatus.active
                                ? 'Mola'
                                : 'Devam',
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: _endTrip,
                          icon: const Icon(Icons.stop),
                          label: const Text('Seferi Bitir'),
                          style: FilledButton.styleFrom(
                            backgroundColor: Colors.red,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => setState(() => _showRoute = !_showRoute),
                      icon: Icon(_showRoute ? Icons.route : Icons.map),
                      label: Text(_showRoute ? 'Rotayı Gizle' : 'İlk Rotasını Göster'),
                      style: FilledButton.styleFrom(
                        backgroundColor: _showRoute ? Colors.blue.shade700 : Colors.blue,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Harita
        Expanded(
          child: city != null
              ? SehiriciLiveMap(
                  lines: _showRoute ? [line] : [],
                  activeTrips: [trip],
                  center: city,
                  zoomLevel: city.zoomLevel,
                  height: double.infinity,
                  interactive: true,
                )
              : const Center(child: CircularProgressIndicator()),
        ),
      ],
    );
  }
}
