import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../features/admin/widgets/admin_ui.dart';
import '../models/sehirici_models.dart';
import '../providers/sehirici_provider.dart';
import '../services/sehirici_city_service.dart';
import '../services/sehirici_errors.dart';
import 'sehirici_admin_controller.dart';
import 'sehirici_admin_kit.dart';
import 'sehirici_location_picker_dialog.dart';

/// Şehir oluştur / düzenle alt sayfası. Sonuç: kaydedildi/silindiyse `true`.
Future<bool> showSehiriciCityEditor(
  BuildContext context, {
  required SehiriciAdminController controller,
  SehiriciCity? city,
}) async {
  final changed = await showSehiriciSheet<bool>(
    context,
    heightFactor: 0.9,
    builder: (_) => SehiriciCityEditorSheet(controller: controller, city: city),
  );
  return changed == true;
}

class SehiriciCityEditorSheet extends StatefulWidget {
  final SehiriciAdminController controller;
  final SehiriciCity? city;

  const SehiriciCityEditorSheet({
    super.key,
    required this.controller,
    this.city,
  });

  @override
  State<SehiriciCityEditorSheet> createState() =>
      _SehiriciCityEditorSheetState();
}

class _SehiriciCityEditorSheetState extends State<SehiriciCityEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name =
      TextEditingController(text: widget.city?.name ?? '');
  late final TextEditingController _slug =
      TextEditingController(text: widget.city?.slug ?? '');
  late final TextEditingController _lat = TextEditingController(
      text: widget.city == null ? '' : widget.city!.centerLat.toStringAsFixed(6));
  late final TextEditingController _lng = TextEditingController(
      text: widget.city == null ? '' : widget.city!.centerLng.toStringAsFixed(6));
  late double _zoom = (widget.city?.zoomLevel ?? 14).toDouble();
  late bool _active = widget.city?.isActive ?? true;
  bool _slugEdited = false;
  bool _saving = false;
  String? _formError;

  bool get _isNew => widget.city == null;

  @override
  void initState() {
    super.initState();
    _slugEdited = !_isNew;
    _name.addListener(() {
      if (_slugEdited) return;
      final slug = SehiriciCityService.slugify(_name.text);
      _slug.text = _name.text.trim().isEmpty ? '' : slug;
    });
  }

  @override
  void dispose() {
    _name.dispose();
    _slug.dispose();
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  double? _parse(String t) => double.tryParse(t.trim().replaceAll(',', '.'));

  Future<void> _pickOnMap() async {
    final picked = await SehiriciLocationPickerDialog.pickSingle(
      context,
      initialLat: _parse(_lat.text) ?? 39.0,
      initialLng: _parse(_lng.text) ?? 35.0,
      initialZoom: _parse(_lat.text) == null ? 5.5 : _zoom,
    );
    if (picked != null && mounted) {
      setState(() {
        _lat.text = picked.latitude.toStringAsFixed(6);
        _lng.text = picked.longitude.toStringAsFixed(6);
      });
    }
  }

  Future<void> _save() async {
    setState(() => _formError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    try {
      await widget.controller.cityService.saveCity(SehiriciCity(
        id: widget.city?.id ?? '',
        name: _name.text.trim(),
        slug: _slug.text.trim(),
        centerLat: _parse(_lat.text)!,
        centerLng: _parse(_lng.text)!,
        zoomLevel: _zoom.round(),
        isActive: _active,
      ));
      await widget.controller.reloadCities();
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
    final city = widget.city!;
    final isCurrent = widget.controller.cityId == city.id;
    final ok = await sehiriciConfirm(
      context,
      icon: Icons.delete_forever_rounded,
      title: '${city.name} silinsin mi?',
      message: 'Şehir ile birlikte TÜM hatları, durakları ve rotaları kalıcı '
          'olarak silinir'
          '${isCurrent ? ' (${widget.controller.lines.length} hat, ${widget.controller.stops.length} durak)' : ''}.'
          '\n\nBu işlem geri alınamaz.',
      confirmLabel: 'Şehri Sil',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.controller.cityService.deleteCityOrThrow(city.id);
      await Future.wait([
        widget.controller.reloadCities(),
        widget.controller.reloadDrivers(),
      ]);
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

  String? _validateCoord(String? v, {required bool isLat}) {
    final n = _parse(v ?? '');
    if (n == null) return isLat ? 'Enlem gerekli' : 'Boylam gerekli';
    if (isLat && n.abs() > 90) return '−90 ile 90 arası';
    if (!isLat && n.abs() > 180) return '−180 ile 180 arası';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return SehiriciSheetScaffold(
      title: _isNew ? 'Yeni Şehir' : 'Şehri Düzenle',
      subtitle: 'Şehiriçi servislerin çalışacağı şehir',
      leading: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: AdminUi.brandSoft,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(Icons.location_city_rounded, color: AdminUi.brand),
      ),
      bottomBar: Row(
        children: [
          if (!_isNew) ...[
            IconButton.outlined(
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
              color: const Color(0xFFDC2626),
              tooltip: 'Şehri sil',
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
              label: Text(_isNew ? 'Şehri Ekle' : 'Kaydet'),
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
                child: Text(_formError!,
                    style: const TextStyle(
                        color: Color(0xFF991B1B), fontWeight: FontWeight.w600)),
              ),
            SehiriciFormSection(
              title: 'Şehir',
              child: Column(
                children: [
                  TextFormField(
                    controller: _name,
                    textCapitalization: TextCapitalization.words,
                    validator: (v) =>
                        (v ?? '').trim().isEmpty ? 'Şehir adı gerekli' : null,
                    decoration: sehiriciInput('Şehir adı', hint: 'Cizre'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _slug,
                    onChanged: (_) => _slugEdited = true,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[a-z0-9-]')),
                    ],
                    decoration: sehiriciInput(
                      'Bağlantı adı (slug)',
                      hint: 'cizre',
                      helper: 'Addan otomatik üretilir; benzersiz olmalı.',
                    ),
                  ),
                ],
              ),
            ),
            SehiriciFormSection(
              title: 'Harita merkezi',
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
                  SizedBox(
                    width: double.infinity,
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
                ],
              ),
            ),
            SehiriciFormSection(
              title: 'Açılış yakınlığı',
              hint: 'Harita açıldığında şehrin ne kadar yakından '
                  'gösterileceği. 16 ≈ mahalle, 13 ≈ tüm şehir.',
              child: AdminCard(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                child: Row(
                  children: [
                    const Icon(Icons.zoom_in_map_rounded,
                        size: 20, color: AdminUi.muted),
                    Expanded(
                      child: Slider(
                        value: _zoom,
                        min: 8,
                        max: 19,
                        divisions: 11,
                        activeColor: AdminUi.brand,
                        onChanged: (v) => setState(() => _zoom = v),
                      ),
                    ),
                    SizedBox(
                      width: 30,
                      child: Text(
                        '${_zoom.round()}',
                        textAlign: TextAlign.end,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
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
                title: const Text('Şehir aktif',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text('Kapalıysa kullanıcılar bu şehri göremez.'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
