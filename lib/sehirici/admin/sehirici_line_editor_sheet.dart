import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../features/admin/widgets/admin_ui.dart';
import '../models/sehirici_icon_models.dart';
import '../models/sehirici_models.dart';
import '../providers/sehirici_provider.dart';
import '../services/sehirici_errors.dart';
import '../widgets/sehirici_common_widgets.dart';
import 'sehirici_admin_controller.dart';
import 'sehirici_admin_kit.dart';

/// Hat oluştur / düzenle alt sayfası.
///
/// Sonuç: kaydedildi ya da silindiyse `true`.
Future<bool> showSehiriciLineEditor(
  BuildContext context, {
  required SehiriciAdminController controller,
  SehiriciLine? line,
}) async {
  final changed = await showSehiriciSheet<bool>(
    context,
    builder: (_) => SehiriciLineEditorSheet(controller: controller, line: line),
  );
  return changed == true;
}

class SehiriciLineEditorSheet extends StatefulWidget {
  final SehiriciAdminController controller;

  /// null → yeni hat.
  final SehiriciLine? line;

  const SehiriciLineEditorSheet({
    super.key,
    required this.controller,
    this.line,
  });

  @override
  State<SehiriciLineEditorSheet> createState() =>
      _SehiriciLineEditorSheetState();
}

class _SehiriciLineEditorSheetState extends State<SehiriciLineEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _code =
      TextEditingController(text: widget.line?.code ?? '');
  late final TextEditingController _name =
      TextEditingController(text: widget.line?.name ?? '');
  late final TextEditingController _minutes = TextEditingController(
      text: widget.line?.estimatedMinutes?.toString() ?? '');
  late final TextEditingController _fare = TextEditingController(
    text: (widget.line?.fareAmount ?? 0) == 0
        ? ''
        : widget.line!.fareAmount
            .toStringAsFixed(widget.line!.fareAmount % 1 == 0 ? 0 : 2),
  );
  late Color _color = widget.line?.color ?? kSehiriciLinePalette.first;
  late String _vehicleKey = widget.line?.vehicleKey ?? 'minibus';
  late bool _active = widget.line?.isActive ?? true;
  bool _saving = false;
  String? _formError;

  bool get _isNew => widget.line == null;

  @override
  void initState() {
    super.initState();
    // Yeni hatta ilk aktif araç ikonu seçili gelsin (kütüphanede "minibus"
    // yoksa/pasifse).
    if (_isNew) {
      final vehicles = _selectableVehicles;
      if (vehicles.isNotEmpty &&
          !vehicles.any((v) => v.key == _vehicleKey)) {
        _vehicleKey = vehicles.first.key;
      }
      // Yeni hat, mevcut hatlarda kullanılmayan bir renkle başlasın.
      final used = widget.controller.lines.map((l) => l.color.toARGB32()).toSet();
      for (final c in kSehiriciLinePalette) {
        if (!used.contains(c.toARGB32())) {
          _color = c;
          break;
        }
      }
    }
  }

  @override
  void dispose() {
    _code.dispose();
    _name.dispose();
    _minutes.dispose();
    _fare.dispose();
    super.dispose();
  }

  /// Seçilebilir araç ikonları: aktifler + hatta zaten seçili olan (pasife
  /// alınmış olsa da hattın türü kaybolmasın).
  List<SehiriciMarkerIcon> get _selectableVehicles => widget.controller.icons
      .where((i) => i.isVehicle && (i.isActive || i.key == widget.line?.vehicleKey))
      .toList()
    ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

  SehiriciMarkerIcon get _selectedIcon {
    for (final i in widget.controller.icons) {
      if (i.isVehicle && i.key == _vehicleKey) return i;
    }
    return SehiriciMarkerIcon.builtinDefaults.first;
  }

  String? _validateCode(String? v) {
    final code = (v ?? '').trim();
    if (code.isEmpty) return 'Hat kodu gerekli (ör. 4A)';
    if (code.length > 8) return 'En fazla 8 karakter';
    final clash = widget.controller.lines.any((l) =>
        l.id != widget.line?.id &&
        l.code.trim().toLowerCase() == code.toLowerCase());
    if (clash) return 'Bu kod bu şehirde zaten kullanılıyor';
    return null;
  }

  Future<void> _save() async {
    setState(() => _formError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final controller = widget.controller;
    final cityId = controller.cityId;
    if (cityId == null) {
      setState(() => _formError = 'Önce bir şehir seçin.');
      return;
    }
    final minutesText = _minutes.text.trim();
    final fareText = _fare.text.trim().replaceAll(',', '.');
    setState(() => _saving = true);
    try {
      await controller.lineService.saveLine(
        id: widget.line?.id,
        cityId: cityId,
        code: _code.text,
        name: _name.text,
        colorHex: sehiriciColorHex(_color),
        vehicleKey: _vehicleKey,
        estimatedMinutes: minutesText.isEmpty ? null : int.parse(minutesText),
        fareAmount: fareText.isEmpty ? 0 : double.parse(fareText),
        isActive: _active,
        // Düzenlemede sıra korunur (null); yeni hat listenin sonuna eklenir.
        displayOrder: null,
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
    final line = widget.line!;
    final driver = widget.controller.driverOfLine(line.id);
    final ok = await sehiriciConfirm(
      context,
      icon: Icons.delete_forever_rounded,
      title: '${line.code} hattı silinsin mi?',
      message: 'Hat, ${line.stops.length} durak bağı ve kayıtlı rotasıyla '
          'birlikte kalıcı olarak silinir.'
          '${driver != null ? '\n\n${driver.displayName} adlı şoförün hat ataması kaldırılır.' : ''}'
          '\n\nDuraklar silinmez, şehirde kalır.',
      confirmLabel: 'Hattı Sil',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.controller.lineService.deleteLineOrThrow(line.id);
      await Future.wait([
        widget.controller.reloadCityData(),
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

  /// Kullanıcı tarafındaki (sağlayıcıdaki) önbellekleri tazeler.
  void _refreshUserSide() {
    try {
      context.read<SehiriciProvider>().invalidateAllCaches();
    } catch (_) {
      // Sağlayıcı yoksa (test) sessizce geç.
    }
  }

  @override
  Widget build(BuildContext context) {
    return SehiriciSheetScaffold(
      title: _isNew ? 'Yeni Hat' : 'Hattı Düzenle',
      subtitle: widget.controller.city?.name,
      bottomBar: Row(
        children: [
          if (!_isNew) ...[
            IconButton.outlined(
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
              color: const Color(0xFFDC2626),
              tooltip: 'Hattı sil',
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
              label: Text(_isNew ? 'Hattı Oluştur' : 'Kaydet'),
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
            _PreviewCard(
              code: _code,
              name: _name,
              color: _color,
              icon: _selectedIcon,
            ),
            const SizedBox(height: 20),
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
            SehiriciFormSection(
              title: 'Kimlik',
              child: Column(
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 112,
                        child: TextFormField(
                          controller: _code,
                          textCapitalization: TextCapitalization.characters,
                          maxLength: 8,
                          validator: _validateCode,
                          decoration: sehiriciInput('Kod', hint: '4A')
                              .copyWith(counterText: ''),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _name,
                          textCapitalization: TextCapitalization.words,
                          validator: (v) => (v ?? '').trim().isEmpty
                              ? 'Hat adı gerekli'
                              : null,
                          decoration:
                              sehiriciInput('Hat adı', hint: 'Merkez – Hastane'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            SehiriciFormSection(
              title: 'Renk',
              hint: 'Haritada güzergâh çizgisi, araç gövdesi ve rozetler bu '
                  'renkte görünür.',
              child: SehiriciColorPicker(
                value: _color,
                onChanged: (c) => setState(() => _color = c),
              ),
            ),
            SehiriciFormSection(
              title: 'Araç ikonu',
              hint: 'Haritada bu hattın aracı olarak görünür. İkon '
                  'kütüphanesinden yeni türler ekleyebilir veya görselini '
                  'değiştirebilirsiniz.',
              child: SizedBox(
                height: 128,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _selectableVehicles.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (context, i) {
                    final icon = _selectableVehicles[i];
                    final selected = icon.key == _vehicleKey;
                    return GestureDetector(
                      onTap: () => setState(() => _vehicleKey = icon.key),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        width: 104,
                        padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
                        decoration: BoxDecoration(
                          color: selected
                              ? _color.withValues(alpha: 0.10)
                              : Colors.white,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: selected ? _color : AdminUi.line,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: Column(
                          children: [
                            Expanded(
                              child: Center(
                                child: SehiriciVehicleIcon(
                                  icon: icon,
                                  color: _color,
                                  height: 64,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              icon.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: selected ? _color : AdminUi.ink,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
            SehiriciFormSection(
              title: 'Sefer bilgisi',
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _minutes,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: sehiriciInput('Süre',
                          suffix: 'dk', icon: Icons.schedule_rounded),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextFormField(
                      controller: _fare,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                      ],
                      validator: (v) {
                        final t = (v ?? '').trim().replaceAll(',', '.');
                        if (t.isEmpty) return null;
                        return double.tryParse(t) == null ? 'Geçersiz tutar' : null;
                      },
                      decoration: sehiriciInput('Ücret',
                          suffix: '₺', icon: Icons.payments_outlined),
                    ),
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
                title: const Text('Hat aktif',
                    style: TextStyle(fontWeight: FontWeight.w800)),
                subtitle: const Text(
                    'Kapalıysa kullanıcılar haritada ve listede görmez.'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Düzenlenen hattın canlı önizlemesi: rozet + ad + haritadaki araç.
class _PreviewCard extends StatelessWidget {
  final TextEditingController code;
  final TextEditingController name;
  final Color color;
  final SehiriciMarkerIcon icon;

  const _PreviewCard({
    required this.code,
    required this.name,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([code, name]),
      builder: (context, _) {
        final codeText = code.text.trim();
        final nameText = name.text.trim();
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [color, Color.lerp(color, Colors.black, 0.3)!],
            ),
            borderRadius: BorderRadius.circular(22),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.35),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 5),
                      decoration: BoxDecoration(
                        color: sehiriciOnColor(color).withValues(alpha: 0.16),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        codeText.isEmpty ? 'KOD' : codeText.toUpperCase(),
                        style: TextStyle(
                          color: sehiriciOnColor(color),
                          fontWeight: FontWeight.w900,
                          fontSize: 20,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      nameText.isEmpty ? 'Hat adı' : nameText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: sehiriciOnColor(color),
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      icon.label,
                      style: TextStyle(
                        color: sehiriciOnColor(color).withValues(alpha: 0.85),
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              // Haritadaki görünüm: açık zemin, hafif dönük.
              Container(
                width: 92,
                height: 104,
                decoration: BoxDecoration(
                  color: const Color(0xFFF2F1ED),
                  borderRadius: BorderRadius.circular(18),
                ),
                alignment: Alignment.center,
                child: SehiriciVehicleIcon(
                  icon: icon,
                  color: color,
                  height: 84,
                  rotationDegrees: 28,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
