import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';

import '../../core/services/location_disclosure_service.dart';
import '../../features/admin/widgets/admin_ui.dart';
import '../models/sehirici_models.dart';
import '../providers/sehirici_provider.dart';
import '../services/sehirici_errors.dart';
import '../widgets/sehirici_common_widgets.dart';
import 'sehirici_admin_controller.dart';
import 'sehirici_admin_kit.dart';
import 'sehirici_location_picker_dialog.dart';

/// Durak oluştur / düzenle alt sayfası. Sonuç: kaydedildi/silindiyse `true`.
Future<bool> showSehiriciStopEditor(
  BuildContext context, {
  required SehiriciAdminController controller,
  SehiriciStop? stop,
}) async {
  final changed = await showSehiriciSheet<bool>(
    context,
    builder: (_) => SehiriciStopEditorSheet(controller: controller, stop: stop),
  );
  return changed == true;
}

class SehiriciStopEditorSheet extends StatefulWidget {
  final SehiriciAdminController controller;

  /// null → yeni durak.
  final SehiriciStop? stop;

  const SehiriciStopEditorSheet({
    super.key,
    required this.controller,
    this.stop,
  });

  @override
  State<SehiriciStopEditorSheet> createState() =>
      _SehiriciStopEditorSheetState();
}

class _SehiriciStopEditorSheetState extends State<SehiriciStopEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.stop?.name ?? '');
  late final TextEditingController _code =
      TextEditingController(text: widget.stop?.code ?? '');
  late final TextEditingController _address =
      TextEditingController(text: widget.stop?.address ?? '');
  late final TextEditingController _lat = TextEditingController(
      text: widget.stop == null ? '' : widget.stop!.lat.toStringAsFixed(6));
  late final TextEditingController _lng = TextEditingController(
      text: widget.stop == null ? '' : widget.stop!.lng.toStringAsFixed(6));
  late bool _active = widget.stop?.isActive ?? true;
  bool _saving = false;
  bool _locating = false;
  String? _formError;

  bool get _isNew => widget.stop == null;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _address.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  double? _parse(String text) =>
      double.tryParse(text.trim().replaceAll(',', '.'));

  String? _validateCoord(String? v, {required bool isLat}) {
    final n = _parse(v ?? '');
    if (n == null) return isLat ? 'Enlem gerekli' : 'Boylam gerekli';
    if (isLat && n.abs() > 90) return '−90 ile 90 arası';
    if (!isLat && n.abs() > 180) return '−180 ile 180 arası';
    return null;
  }

  Future<void> _pickOnMap() async {
    final controller = widget.controller;
    final city = controller.city;
    final startLat = _parse(_lat.text) ?? city?.centerLat ?? 37.0;
    final startLng = _parse(_lng.text) ?? city?.centerLng ?? 41.0;
    final picked = await SehiriciLocationPickerDialog.pickSingle(
      context,
      initialLat: startLat,
      initialLng: startLng,
      initialZoom: (city?.zoomLevel ?? 15).toDouble(),
      existingStops:
          controller.stops.where((s) => s.id != widget.stop?.id).toList(),
    );
    if (picked != null && mounted) {
      setState(() {
        _lat.text = picked.latitude.toStringAsFixed(6);
        _lng.text = picked.longitude.toStringAsFixed(6);
      });
    }
  }

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        if (mounted) sehiriciSnack(context, 'Konum servisleri kapalı.', error: true);
        return;
      }
      if (!mounted) return;
      // Prominent disclosure + sistem izni (tek seferlik okuma).
      final allowed =
          await LocationDisclosureService.ensure(context, LocationPurpose.nearby);
      if (!allowed) {
        if (mounted) sehiriciSnack(context, 'Konum izni verilmedi.', error: true);
        return;
      }
      final pos = await Geolocator.getCurrentPosition(
        locationSettings:
            const LocationSettings(accuracy: LocationAccuracy.high),
      );
      if (mounted) {
        setState(() {
          _lat.text = pos.latitude.toStringAsFixed(6);
          _lng.text = pos.longitude.toStringAsFixed(6);
        });
      }
    } catch (e) {
      if (mounted) sehiriciSnack(context, 'Konum alınamadı: $e', error: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _save() async {
    setState(() => _formError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final controller = widget.controller;
    final cityId = controller.cityId;
    if (cityId == null) return;
    setState(() => _saving = true);
    try {
      await controller.lineService.saveStop(
        id: widget.stop?.id,
        cityId: cityId,
        name: _name.text.trim(),
        code: _code.text.trim().isEmpty ? null : _code.text.trim(),
        lat: _parse(_lat.text)!,
        lng: _parse(_lng.text)!,
        address: _address.text.trim().isEmpty ? null : _address.text.trim(),
        isActive: _active,
      );
      await controller.reloadCityData();
      _refreshUserSide();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _formError = sehiriciErrorMessage(e);
        });
      }
    }
  }

  Future<void> _delete() async {
    final stop = widget.stop!;
    final used = widget.controller.linesByStop[stop.id] ?? const [];
    final ok = await sehiriciConfirm(
      context,
      icon: Icons.delete_forever_rounded,
      title: '“${stop.name}” silinsin mi?',
      message: used.isEmpty
          ? 'Bu durak hiçbir hatta bağlı değil; kalıcı olarak silinir.'
          : 'Bu durak ${used.length} hatta kullanılıyor '
              '(${used.map((l) => l.code).join(', ')}). Silinirse bu hatların '
              'durak listesinden de çıkar ve rotaları eski kalabilir.',
      confirmLabel: 'Durağı Sil',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.controller.lineService.deleteStopOrThrow(stop.id);
      await widget.controller.reloadCityData();
      _refreshUserSide();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _formError = sehiriciErrorMessage(e);
        });
      }
    }
  }

  void _refreshUserSide() {
    try {
      context.read<SehiriciProvider>().invalidateAllCaches();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final used = widget.stop == null
        ? const <SehiriciLine>[]
        : (widget.controller.linesByStop[widget.stop!.id] ?? const []);
    return SehiriciSheetScaffold(
      title: _isNew ? 'Yeni Durak' : 'Durağı Düzenle',
      subtitle: widget.controller.city?.name,
      leading: SehiriciStopIcon(
        height: 44,
        lineColors: used.map((l) => l.color).take(3).toList(),
      ),
      bottomBar: Row(
        children: [
          if (!_isNew) ...[
            IconButton.outlined(
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
              color: const Color(0xFFDC2626),
              tooltip: 'Durağı sil',
              style: IconButton.styleFrom(
                side: const BorderSide(color: Color(0xFFFCA5A5)),
                minimumSize: const Size(52, 52),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.check_rounded),
              label: Text(_isNew ? 'Durağı Ekle' : 'Kaydet'),
              style: FilledButton.styleFrom(
                backgroundColor: AdminUi.brand,
                minimumSize: const Size.fromHeight(52),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
        ],
      ),
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            if (_formError != null)
              Container(
                margin: const EdgeInsets.only(bottom: 14),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline_rounded,
                        color: Color(0xFFB91C1C), size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(_formError!,
                          style: const TextStyle(
                              color: Color(0xFF991B1B),
                              fontWeight: FontWeight.w600)),
                    ),
                  ],
                ),
              ),
            if (used.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    const Text('Bu duraktan geçen hatlar:',
                        style: TextStyle(
                            color: AdminUi.muted, fontWeight: FontWeight.w600)),
                    for (final l in used)
                      SehiriciLineBadge.forLine(l, height: 24),
                  ],
                ),
              ),
            SehiriciFormSection(
              title: 'Durak bilgisi',
              child: Column(
                children: [
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Durak adı gerekli' : null,
                    decoration: sehiriciInput('Durak adı',
                        hint: 'Ör. Belediye Önü', icon: Icons.signpost_outlined),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      SizedBox(
                        width: 120,
                        child: TextFormField(
                          controller: _code,
                          textCapitalization: TextCapitalization.characters,
                          decoration: sehiriciInput('Kod', hint: 'A01'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _address,
                          textCapitalization: TextCapitalization.sentences,
                          decoration: sehiriciInput('Adres (isteğe bağlı)'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SehiriciFormSection(
              title: 'Konum',
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _lat,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true, signed: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
                          ],
                          validator: (v) => _validateCoord(v, isLat: true),
                          decoration: sehiriciInput('Enlem'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _lng,
                          keyboardType: const TextInputType.numberWithOptions(
                              decimal: true, signed: true),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[0-9.,\-]')),
                          ],
                          validator: (v) => _validateCoord(v, isLat: false),
                          decoration: sehiriciInput('Boylam'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickOnMap,
                          icon: const Icon(Icons.map_outlined, size: 19),
                          label: const Text('Haritadan seç'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                            foregroundColor: AdminUi.brand,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _locating ? null : _useMyLocation,
                          icon: _locating
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                )
                              : const Icon(Icons.my_location_rounded, size: 19),
                          label: const Text('Konumumu al'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(46),
                            foregroundColor: AdminUi.brand,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            AdminCard(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
                activeTrackColor: AdminUi.brand,
                activeThumbColor: Colors.white,
                title: const Text('Durak aktif',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('Kapalıysa kullanıcı haritasında görünmez.'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
