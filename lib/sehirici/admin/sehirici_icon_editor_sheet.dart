import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/utils/map_vehicle_painters.dart';
import '../../core/widgets/map_vehicle_thumb.dart';
import '../../features/admin/widgets/admin_ui.dart';
import '../models/sehirici_icon_models.dart';
import '../services/sehirici_errors.dart';
import '../services/sehirici_icon_service.dart';
import '../utils/sehirici_marker_bitmaps.dart';
import '../widgets/sehirici_common_widgets.dart';
import 'sehirici_admin_controller.dart';
import 'sehirici_admin_kit.dart';

/// "Taksi" → "taksi", "Servis Aracı" → "servis_araci". Anahtar kuralı:
/// harfle başlar, yalnız a-z 0-9 _, en çok 28 karakter (durak öneki hariç).
String sehiriciIconKeyFromName(String name) {
  var key = sehiriciFold(name)
      .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
      .replaceAll(RegExp(r'^_+|_+$'), '');
  if (key.isEmpty) return '';
  if (!RegExp(r'^[a-z]').hasMatch(key)) key = 'x_$key';
  return key.length > 28 ? key.substring(0, 28) : key;
}

/// İkon oluştur / düzenle alt sayfası. Sonuç: kaydedildi/silindiyse `true`.
Future<bool> showSehiriciIconEditor(
  BuildContext context, {
  required SehiriciAdminController controller,
  required SehiriciIconKind kind,
  SehiriciMarkerIcon? icon,
}) async {
  final changed = await showSehiriciSheet<bool>(
    context,
    heightFactor: 0.95,
    builder: (_) => SehiriciIconEditorSheet(
      controller: controller,
      kind: kind,
      icon: icon,
    ),
  );
  return changed == true;
}

class SehiriciIconEditorSheet extends StatefulWidget {
  final SehiriciAdminController controller;
  final SehiriciIconKind kind;

  /// null → yeni ikon.
  final SehiriciMarkerIcon? icon;

  /// Testlerde görsel seçimini taklit etmek için.
  final Future<({Uint8List bytes, String name})?> Function()? imagePicker;

  const SehiriciIconEditorSheet({
    super.key,
    required this.controller,
    required this.kind,
    this.icon,
    this.imagePicker,
  });

  @override
  State<SehiriciIconEditorSheet> createState() =>
      _SehiriciIconEditorSheetState();
}

class _SehiriciIconEditorSheetState extends State<SehiriciIconEditorSheet> {
  late final TextEditingController _label =
      TextEditingController(text: widget.icon?.label ?? '');
  late final TextEditingController _key =
      TextEditingController(text: widget.icon?.key.replaceFirst('stop_', '') ?? '');
  bool _keyEdited = false;

  late String _shape = widget.icon?.builtinShape ??
      (widget.kind == SehiriciIconKind.vehicle ? 'minibus' : 'sign');
  late int _rotation = widget.icon?.imageRotation ?? 0;
  late double _scale = widget.icon?.scale ?? 1.0;
  late bool _anchorBottom = widget.icon?.anchorBottom ?? false;
  late bool _active = widget.icon?.isActive ?? true;

  // Görsel durumu: mevcut (sunucudaki) + yeni seçilen (henüz yüklenmemiş).
  late String? _imageUrl = widget.icon?.imageUrl;
  late String? _imagePath = widget.icon?.imagePath;
  Uint8List? _pendingBytes;
  String? _pendingName;
  bool _removeImage = false;

  bool _saving = false;
  bool _busyDefault = false;
  String? _formError;

  bool get _isNew => widget.icon == null;
  bool get _isVehicle => widget.kind == SehiriciIconKind.vehicle;
  bool get _hasCustomImage =>
      _pendingBytes != null || (_imageUrl != null && !_removeImage);

  @override
  void initState() {
    super.initState();
    _label.addListener(_autoKey);
  }

  @override
  void dispose() {
    _label.removeListener(_autoKey);
    _label.dispose();
    _key.dispose();
    super.dispose();
  }

  /// Yeni ikonda anahtar, kullanıcı elle dokunana dek addan üretilir.
  void _autoKey() {
    if (!_isNew || _keyEdited) return;
    final suggested = sehiriciIconKeyFromName(_label.text);
    if (_key.text != suggested) {
      _key.value = TextEditingValue(
        text: suggested,
        selection: TextSelection.collapsed(offset: suggested.length),
      );
    }
    setState(() {});
  }

  String get _fullKey =>
      _isVehicle ? _key.text.trim() : 'stop_${_key.text.trim()}';

  String? _keyError() {
    if (!_isNew) return null;
    final k = _key.text.trim();
    if (k.isEmpty) return null;
    if (!RegExp(r'^[a-z][a-z0-9_]{1,31}$').hasMatch(_fullKey)) {
      return 'Harfle başlamalı; yalnız küçük harf, rakam ve alt çizgi';
    }
    if (widget.controller.icons.any((i) => i.key == _fullKey)) {
      return 'Bu anahtar zaten kullanılıyor';
    }
    return null;
  }

  // ── Görsel seçimi ────────────────────────────────────────────

  Future<void> _pickImage() async {
    try {
      final picked = widget.imagePicker != null
          ? await widget.imagePicker!()
          : await _defaultPicker();
      if (picked == null || !mounted) return;
      if (picked.bytes.length > SehiriciIconService.maxImageBytes) {
        setState(() => _formError =
            'Görsel çok büyük (${(picked.bytes.length / 1024).round()} KB). '
            'En fazla 1 MB olmalı — daha küçük bir PNG/WebP seçin.');
        return;
      }
      final name = picked.name.toLowerCase();
      if (!(name.endsWith('.png') ||
          name.endsWith('.webp') ||
          name.endsWith('.jpg') ||
          name.endsWith('.jpeg'))) {
        setState(() => _formError = 'Yalnızca PNG, WebP veya JPEG seçin.');
        return;
      }
      setState(() {
        _pendingBytes = picked.bytes;
        _pendingName = picked.name;
        _removeImage = false;
        _formError = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _formError = 'Görsel seçilemedi: $e');
      }
    }
  }

  Future<({Uint8List bytes, String name})?> _defaultPicker() async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
    );
    if (file == null) return null;
    return (bytes: await file.readAsBytes(), name: file.name);
  }

  void _removeCustomImage() {
    setState(() {
      _pendingBytes = null;
      _pendingName = null;
      _removeImage = true;
      _rotation = 0;
    });
  }

  // ── Kaydet / sil ─────────────────────────────────────────────

  Future<void> _save() async {
    setState(() => _formError = null);
    final label = _label.text.trim();
    if (label.isEmpty) {
      setState(() => _formError = 'İkon adı gerekli.');
      return;
    }
    if (_isNew) {
      if (_key.text.trim().isEmpty) {
        setState(() => _formError = 'Anahtar gerekli (adı yazınca otomatik gelir).');
        return;
      }
      final err = _keyError();
      if (err != null) {
        setState(() => _formError = err);
        return;
      }
    }

    final service = widget.controller.iconService;
    setState(() => _saving = true);
    String? uploadedPath;
    try {
      String? url = _removeImage ? null : _imageUrl;
      String? path = _removeImage ? null : _imagePath;
      if (_pendingBytes != null) {
        final uploaded = await service.uploadImage(
          bytes: _pendingBytes!,
          fileName: _pendingName ?? 'icon.png',
          key: _isNew ? _fullKey : widget.icon!.key,
        );
        url = uploaded.url;
        path = uploaded.path;
        uploadedPath = uploaded.path;
      }

      await service.saveIcon(SehiriciMarkerIconDraft(
        id: widget.icon?.id,
        kind: widget.kind,
        key: _isNew ? _fullKey : widget.icon!.key,
        label: label,
        builtinShape: _shape,
        imageUrl: url,
        imagePath: path,
        imageRotation: url == null ? 0 : _rotation,
        tintWithLineColor: true,
        scale: double.parse(_scale.toStringAsFixed(2)),
        anchorBottom: _anchorBottom,
        isActive: _active,
        sortOrder: _isNew ? _nextSortOrder() : null,
      ));

      // Görsel değiştirildi/kaldırıldıysa eski dosyayı temizle (yalnız bu
      // ikon kullanıyordu; URL başka yere kopyalanmaz).
      final oldPath = widget.icon?.imagePath;
      if (oldPath != null && oldPath != path) {
        await service.removeFile(oldPath);
      }
      await widget.controller.reloadIcons();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      // Kayıt başarısızsa az önce yüklenen yetim dosyayı geri al.
      if (uploadedPath != null) await service.removeFile(uploadedPath);
      if (mounted) {
        setState(() {
          _saving = false;
          _formError = sehiriciErrorMessage(e);
        });
      }
    }
  }

  int _nextSortOrder() {
    final same = widget.controller.icons.where((i) => i.kind == widget.kind);
    if (same.isEmpty) return 10;
    return same.map((i) => i.sortOrder).reduce((a, b) => a > b ? a : b) + 10;
  }

  Future<void> _delete() async {
    final icon = widget.icon!;
    final used = _isVehicle
        ? widget.controller.lines.where((l) => l.vehicleKey == icon.key).length
        : 0;
    if (used > 0) {
      setState(() => _formError =
          '$used hat bu ikonu kullanıyor. Önce o hatların araç türünü değiştirin.');
      return;
    }
    final ok = await sehiriciConfirm(
      context,
      icon: Icons.delete_forever_rounded,
      title: '“${icon.label}” silinsin mi?',
      message: 'Bu ikon ve yüklenmiş görseli kalıcı olarak silinir.',
      confirmLabel: 'İkonu Sil',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _saving = true);
    try {
      await widget.controller.iconService.deleteIcon(icon);
      await widget.controller.reloadIcons();
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

  Future<void> _makeDefault() async {
    final icon = widget.icon!;
    setState(() => _busyDefault = true);
    try {
      await widget.controller.iconService.setDefault(icon.id);
      await widget.controller.reloadIcons();
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busyDefault = false;
          _formError = sehiriciErrorMessage(e);
        });
      }
    }
  }

  // ── Arayüz ───────────────────────────────────────────────────

  /// Önizlemedeki ikon: yeni seçilen görsel > mevcut görsel > hazır çizim.
  Widget _previewIcon({required Color color, required double scale,
      double rotate = 0, bool dark = false}) {
    if (_isVehicle) {
      final height = (_hasCustomImage
              ? SehiriciMarkerBitmaps.vehicleImageLongSide
              : mapVehicleLogicalSize(
                      MapVehicleShape.fromKey(_shape) ?? MapVehicleShape.car)
                  .height) *
          scale;
      return Transform.rotate(
        angle: rotate * 3.14159265 / 180,
        child: _imageOrPainted(
          height: height,
          painted: MapVehicleThumb(
            shape: MapVehicleShape.fromKey(_shape) ?? MapVehicleShape.car,
            color: color,
            height: height,
          ),
        ),
      );
    }
    final style = MapStopStyle.fromKey(_shape) ?? MapStopStyle.sign;
    final height = (_hasCustomImage ? 44.0 : mapStopLogicalSize(style, MapStopDetail.near).height) * scale;
    return _imageOrPainted(
      height: height,
      painted: MapStopThumb(
        style: style,
        lineColors: [color],
        height: height,
      ),
    );
  }

  Widget _imageOrPainted({required double height, required Widget painted}) {
    if (!_hasCustomImage) return painted;
    final quarter = (_rotation ~/ 90) % 4;
    Widget image;
    if (_pendingBytes != null) {
      image = Image.memory(_pendingBytes!, height: height, fit: BoxFit.contain,
          gaplessPlayback: true);
    } else {
      image = Image.network(
        _imageUrl!,
        height: height,
        fit: BoxFit.contain,
        gaplessPlayback: true,
        errorBuilder: (_, __, ___) => painted,
      );
    }
    return SizedBox(
      height: height,
      child: RotatedBox(quarterTurns: quarter, child: image),
    );
  }

  @override
  Widget build(BuildContext context) {
    final icon = widget.icon;
    final isDefault = icon?.isDefault ?? false;
    final used = (_isVehicle && icon != null)
        ? widget.controller.lines.where((l) => l.vehicleKey == icon.key).length
        : 0;

    return SehiriciSheetScaffold(
      title: _isNew
          ? (_isVehicle ? 'Yeni Araç İkonu' : 'Yeni Durak İkonu')
          : 'İkonu Düzenle',
      subtitle: _isVehicle ? 'Haritadaki araç görünümü' : 'Haritadaki durak görünümü',
      bottomBar: Row(
        children: [
          if (!_isNew && !icon!.isBuiltin && !isDefault) ...[
            IconButton.outlined(
              onPressed: _saving ? null : _delete,
              icon: const Icon(Icons.delete_outline_rounded),
              color: const Color(0xFFDC2626),
              tooltip: 'İkonu sil',
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
              label: Text(_isNew ? 'İkonu Ekle' : 'Kaydet'),
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
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: [
          // ── Önizleme ──
          _buildPreview(),
          const SizedBox(height: 18),
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
          if (icon != null && (icon.isBuiltin || isDefault || used > 0))
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  if (icon.isBuiltin)
                    const AdminBadge(
                        label: 'Yerleşik', color: Colors.indigo, icon: Icons.lock_outline),
                  if (isDefault)
                    const AdminBadge(
                        label: 'Varsayılan',
                        color: Color(0xFF16A34A),
                        icon: Icons.star_rounded),
                  if (used > 0)
                    AdminBadge(
                        label: '$used hat kullanıyor',
                        color: AdminUi.brand,
                        icon: Icons.alt_route_rounded),
                ],
              ),
            ),
          // ── Ad + anahtar ──
          SehiriciFormSection(
            title: 'Ad',
            child: Column(
              children: [
                TextField(
                  controller: _label,
                  textCapitalization: TextCapitalization.words,
                  maxLength: 40,
                  decoration: sehiriciInput(
                    _isVehicle ? 'Araç türü adı' : 'İkon adı',
                    hint: _isVehicle ? 'Ör. Taksi, Servis' : 'Ör. Modern iğne',
                  ).copyWith(counterText: ''),
                ),
                if (_isNew) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _key,
                    onChanged: (_) => setState(() => _keyEdited = true),
                    decoration: sehiriciInput(
                      'Anahtar',
                      hint: 'taksi',
                      helper: 'Hatlar bu anahtarla ikonu seçer; sonradan '
                          'değiştirilemez.',
                    ).copyWith(
                      prefixText: _isVehicle ? null : 'stop_',
                      errorText: _keyError(),
                    ),
                  ),
                ],
              ],
            ),
          ),
          // ── Hazır çizim ──
          SehiriciFormSection(
            title: 'Hazır çizim',
            hint: _hasCustomImage
                ? 'Yüklediğiniz görsel bunun yerine gösterilir; görseli '
                    'kaldırırsanız bu çizime dönülür.'
                : 'Uygulamanın kendi tepeden görünüm çizimi.',
            child: SizedBox(
              height: _isVehicle ? 116 : 92,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: _isVehicle
                    ? MapVehicleShape.values.length
                    : MapStopStyle.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) {
                  final key = _isVehicle
                      ? MapVehicleShape.values[i].name
                      : MapStopStyle.values[i].name;
                  final label = _isVehicle
                      ? MapVehicleShape.values[i].label
                      : MapStopStyle.values[i].label;
                  final selected = key == _shape;
                  return GestureDetector(
                    onTap: () => setState(() => _shape = key),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      width: 92,
                      padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
                      decoration: BoxDecoration(
                        color: selected
                            ? AdminUi.brand.withValues(alpha: 0.08)
                            : Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: selected ? AdminUi.brand : AdminUi.line,
                          width: selected ? 2 : 1,
                        ),
                      ),
                      child: Column(
                        children: [
                          Expanded(
                            child: Center(
                              child: _isVehicle
                                  ? MapVehicleThumb(
                                      shape: MapVehicleShape.values[i],
                                      color: const Color(0xFF1976D2),
                                      height: 60,
                                    )
                                  : MapStopThumb(
                                      style: MapStopStyle.values[i],
                                      lineColors: const [Color(0xFF1976D2)],
                                      height: 44,
                                    ),
                            ),
                          ),
                          Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: selected ? AdminUi.brand : AdminUi.ink,
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
          // ── Kendi görselim ──
          SehiriciFormSection(
            title: 'Kendi görselim',
            hint: _isVehicle
                ? 'Aracı TEPEDEN gösteren, arka planı şeffaf PNG/WebP; burnu '
                    'yukarı bakmalı (değilse aşağıdan yönü düzeltin). En fazla 1 MB.'
                : 'Şeffaf arka planlı PNG/WebP. En fazla 1 MB.',
            child: AdminCard(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 54,
                        height: 54,
                        decoration: BoxDecoration(
                          color: AdminUi.brandSoft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Icon(
                          _hasCustomImage
                              ? Icons.image_rounded
                              : Icons.add_photo_alternate_outlined,
                          color: AdminUi.brand,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              _hasCustomImage
                                  ? (_pendingName ?? 'Yüklü görsel')
                                  : 'Görsel yüklenmedi',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.w800),
                            ),
                            Text(
                              _pendingBytes != null
                                  ? 'Kaydedince yüklenecek · '
                                      '${(_pendingBytes!.length / 1024).round()} KB'
                                  : (_hasCustomImage
                                      ? 'Haritada bu görsel kullanılıyor'
                                      : 'Hazır çizim kullanılıyor'),
                              style: const TextStyle(
                                  fontSize: 12.5, color: AdminUi.muted),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.tonalIcon(
                          onPressed: _saving ? null : _pickImage,
                          icon: const Icon(Icons.upload_rounded, size: 19),
                          label: Text(_hasCustomImage ? 'Değiştir' : 'Görsel yükle'),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size.fromHeight(44),
                          ),
                        ),
                      ),
                      if (_hasCustomImage) ...[
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _saving ? null : _removeCustomImage,
                            icon: const Icon(Icons.undo_rounded, size: 19),
                            label: const Text('Hazır çizime dön'),
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (_hasCustomImage) ...[
                    const SizedBox(height: 16),
                    const Text('Yön düzeltme',
                        style: TextStyle(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    SehiriciSegmented<int>(
                      items: const [
                        (value: 0, label: 'Yukarı', icon: Icons.arrow_upward_rounded),
                        (value: 90, label: 'Sağa', icon: Icons.arrow_forward_rounded),
                        (value: 180, label: 'Aşağı', icon: Icons.arrow_downward_rounded),
                        (value: 270, label: 'Sola', icon: Icons.arrow_back_rounded),
                      ],
                      selected: _rotation,
                      onChanged: (v) => setState(() => _rotation = v),
                    ),
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Görselin burnu hangi yöne bakıyorsa onu seçin.',
                        style: TextStyle(fontSize: 12, color: AdminUi.muted),
                      ),
                    ),
                    if (!_isVehicle) ...[
                      const SizedBox(height: 8),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        value: _anchorBottom,
                        onChanged: (v) => setState(() => _anchorBottom = v),
                        activeTrackColor: AdminUi.brand,
                        activeThumbColor: Colors.white,
                        title: const Text('Alt ucu durağa otursun',
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        subtitle: const Text('İğne ve levha görselleri için açın.'),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          // ── Boyut ──
          SehiriciFormSection(
            title: 'Boyut',
            child: AdminCard(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.zoom_out_map_rounded,
                          size: 18, color: AdminUi.muted),
                      Expanded(
                        child: Slider(
                          value: _scale,
                          min: 0.6,
                          max: 1.6,
                          divisions: 20,
                          activeColor: AdminUi.brand,
                          onChanged: (v) => setState(() => _scale = v),
                        ),
                      ),
                      SizedBox(
                        width: 48,
                        child: Text(
                          '×${_scale.toStringAsFixed(2)}',
                          textAlign: TextAlign.end,
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          // ── Durum ──
          AdminCard(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            child: Column(
              children: [
                SwitchListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                  value: isDefault ? true : _active,
                  onChanged: isDefault ? null : (v) => setState(() => _active = v),
                  activeTrackColor: AdminUi.brand,
                  activeThumbColor: Colors.white,
                  title: const Text('Seçilebilir',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: Text(isDefault
                      ? 'Varsayılan ikon her zaman açıktır.'
                      : (_isVehicle
                          ? 'Kapalıysa yeni hatlarda seçilemez; mevcut hatlar etkilenmez.'
                          : 'Kapalıysa admin listesinde gizlenir.')),
                ),
                if (!_isNew && !isDefault) ...[
                  const Divider(height: 1, color: AdminUi.line),
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    leading: _busyDefault
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(Icons.star_outline_rounded,
                            color: AdminUi.brand),
                    title: Text(
                      _isVehicle ? 'Varsayılan araç ikonu yap' : 'Haritada bunu kullan',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    subtitle: Text(_isVehicle
                        ? 'Türü bilinmeyen hatlar bu ikonla çizilir.'
                        : 'Tüm duraklar haritada bu ikonla görünür.'),
                    onTap: _busyDefault || _saving ? null : _makeDefault,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Açık ve koyu harita zemininde, gerçek marker boyutunda önizleme.
  Widget _buildPreview() {
    final colors = _isVehicle
        ? const [Color(0xFF1976D2), Color(0xFFE53935), Color(0xFF2E9E5B)]
        : const [Color(0xFF1976D2)];
    Widget tile(Color bg, bool dark) => Expanded(
          child: Container(
            height: _isVehicle ? 178 : 132,
            decoration: BoxDecoration(
              color: bg,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AdminUi.line),
            ),
            child: Column(
              children: [
                Expanded(
                  child: Center(
                    child: _isVehicle
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              for (var i = 0; i < colors.length; i++)
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 5),
                                  child: _previewIcon(
                                    color: colors[i],
                                    scale: _scale * (i == 0 ? 1 : 0.62),
                                    rotate: i == 0 ? 0 : (i == 1 ? 24 : -24),
                                    dark: dark,
                                  ),
                                ),
                            ],
                          )
                        : _previewIcon(color: colors.first, scale: _scale, dark: dark),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    dark ? 'Koyu harita' : 'Açık harita',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: dark ? Colors.white54 : AdminUi.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
    return Row(
      children: [
        tile(const Color(0xFFF2F1ED), false),
        const SizedBox(width: 10),
        tile(const Color(0xFF1A1D23), true),
      ],
    );
  }
}
