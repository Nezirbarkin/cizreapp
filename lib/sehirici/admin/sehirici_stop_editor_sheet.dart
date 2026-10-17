import 'package:flutter/foundation.dart' show setEquals;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../core/services/location_disclosure_service.dart';
import '../../features/admin/widgets/admin_ui.dart';
import '../models/sehirici_models.dart';
import '../providers/sehirici_provider.dart';
import '../services/sehirici_errors.dart';
import '../services/sehirici_street_namer.dart';
import '../utils/sehirici_line_stop_plan.dart';
import '../utils/sehirici_stop_naming.dart';
import '../widgets/sehirici_common_widgets.dart';
import 'sehirici_admin_controller.dart';
import 'sehirici_admin_kit.dart';
import 'sehirici_location_picker_dialog.dart';

/// Durak formunun sonucu: listede gösterilecek bildirim.
typedef SehiriciStopEditorResult = ({String message, bool warning});

/// Durak oluştur / düzenle alt sayfası. Kaydedildi/silindiyse bildirim metni
/// döner; vazgeçildiyse null.
Future<SehiriciStopEditorResult?> showSehiriciStopEditor(
  BuildContext context, {
  required SehiriciAdminController controller,
  SehiriciStop? stop,
}) {
  return showSehiriciSheet<SehiriciStopEditorResult>(
    context,
    builder: (_) => SehiriciStopEditorSheet(controller: controller, stop: stop),
  );
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

  /// Yeni durağın kimliği baştan üretilir: kayıt yarıda kalıp yeniden
  /// denenirse (ör. hat bağlantısı hata verdi) aynı durak güncellenir,
  /// kopya oluşmaz. "Ekle ve devam et"ten sonra yenilenir.
  String _newId = const Uuid().v4();

  /// Durağın bağlı olduğu hatlar (formda) ve açılıştaki hâli.
  late final Set<String> _initialLineIds = {
    for (final l in widget.controller.linesByStop[widget.stop?.id] ?? const <SehiriciLine>[])
      l.id,
  };
  late Set<String> _lineIds = {..._initialLineIds};

  /// Sokak adı önerisi. [_autoName]/[_autoAddress] son otomatik yazılan
  /// değerlerdir: alan hâlâ onlarla aynıysa yeni konumda yeniden yazılır,
  /// admin değiştirdiyse dokunulmaz.
  SehiriciStreetSuggestion? _suggestion;
  bool _naming = false;
  int _namingSeq = 0;
  String? _autoName;
  String? _autoAddress;

  /// "Ekle ve devam et" ile bu oturumda eklenen durakların adları.
  final List<String> _addedNames = [];

  bool get _isNew => widget.stop == null;

  SehiriciAdminController get _c => widget.controller;

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

  LatLng? get _position {
    final lat = _parse(_lat.text);
    final lng = _parse(_lng.text);
    if (lat == null || lng == null || lat.abs() > 90 || lng.abs() > 180) {
      return null;
    }
    return LatLng(lat, lng);
  }

  String? _validateCoord(String? v, {required bool isLat}) {
    final n = _parse(v ?? '');
    if (n == null) return isLat ? 'Enlem gerekli' : 'Boylam gerekli';
    if (isLat && n.abs() > 90) return '−90 ile 90 arası';
    if (!isLat && n.abs() > 180) return '−180 ile 180 arası';
    return null;
  }

  // ── Ad önerisi ───────────────────────────────────────────────

  /// Numaralandırmada dolu sayılan adlar (bu durak hariç).
  List<String> get _takenNames => [
        for (final s in _c.stops)
          if (s.id != widget.stop?.id) s.name,
        ..._addedNames,
      ];

  String _numbered(String? base) => sehiriciNextNumberedName(
      base ?? kSehiriciFallbackStopBase, _takenNames);

  bool get _nameIsAuto =>
      _name.text.trim().isEmpty || (_autoName != null && _name.text == _autoName);

  /// Konumdaki sokağı bulur; ad boşsa ya da hâlâ otomatikse "Sokak N" yazar,
  /// adres boşsa doldurur. [force]: admin "öner"e bastı, ad her hâlükârda
  /// değişir.
  Future<void> _suggestName({bool force = false}) async {
    final pos = _position;
    if (pos == null) return;
    final seq = ++_namingSeq;
    setState(() => _naming = true);
    final suggestion = await SehiriciStreetNamer.instance.lookup(pos);
    if (!mounted || seq != _namingSeq) return;
    setState(() {
      _naming = false;
      _suggestion = suggestion;
      if (force || _nameIsAuto) {
        final name = _numbered(suggestion?.base);
        _name.text = name;
        _autoName = name;
      }
      final address = suggestion?.address;
      if (address != null &&
          (_address.text.trim().isEmpty || _address.text == _autoAddress)) {
        _address.text = address;
        _autoAddress = address;
      }
    });
  }

  void _useSuggestion(String? base) {
    final name = _numbered(base);
    setState(() {
      _name.text = name;
      _autoName = name;
    });
  }

  // ── Konum ────────────────────────────────────────────────────

  Future<void> _pickOnMap() async {
    final city = _c.city;
    // Boş formda son eklenen durağın yanından açılır: admin kaldığı yerden
    // devam eder.
    final resume = _c.lastAddedStopAt;
    final startLat =
        _parse(_lat.text) ?? resume?.latitude ?? city?.centerLat ?? 37.0;
    final startLng =
        _parse(_lng.text) ?? resume?.longitude ?? city?.centerLng ?? 41.0;
    final picked = await SehiriciLocationPickerDialog.pickSingle(
      context,
      initialLat: startLat,
      initialLng: startLng,
      initialZoom: (city?.zoomLevel ?? 15).toDouble(),
      existingStops: _c.stops.where((s) => s.id != widget.stop?.id).toList(),
    );
    if (picked != null && mounted) {
      setState(() {
        _lat.text = picked.latitude.toStringAsFixed(6);
        _lng.text = picked.longitude.toStringAsFixed(6);
      });
      _suggestName();
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
        _suggestName();
      }
    } catch (e) {
      if (mounted) sehiriciSnack(context, 'Konum alınamadı: $e', error: true);
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  // ── Kaydet ───────────────────────────────────────────────────

  /// Durağı yazar, hat bağlantılarını uygular. Başarılıysa bildirim metni,
  /// formda hata gösterildiyse null döner.
  Future<SehiriciStopEditorResult?> _persist() async {
    setState(() => _formError = null);
    if (!(_formKey.currentState?.validate() ?? false)) return null;
    final cityId = _c.cityId;
    if (cityId == null) return null;
    setState(() => _saving = true);
    final name = _name.text.trim();
    final pos = _position!;
    final address = _address.text.trim().isEmpty ? null : _address.text.trim();
    final code = _code.text.trim().isEmpty ? null : _code.text.trim();
    var stopSaved = false;
    try {
      final id = await _c.lineService.saveStop(
        id: widget.stop?.id ?? _newId,
        cityId: cityId,
        name: name,
        code: code,
        lat: pos.latitude,
        lng: pos.longitude,
        address: address,
        isActive: _active,
      );
      stopSaved = true;
      if (_isNew) _c.lastAddedStopAt = pos;

      final added = _lineIds.difference(_initialLineIds);
      final removed = _initialLineIds.difference(_lineIds);
      var warnings = const <String>[];
      if (added.isNotEmpty || removed.isNotEmpty) {
        warnings = await _c.setStopLines(
          SehiriciStop(
            id: id,
            name: name,
            code: code,
            lat: pos.latitude,
            lng: pos.longitude,
            address: address,
            isActive: _active,
          ),
          _lineIds,
        );
      }
      await _c.reloadCityData();
      _refreshUserSide();

      final parts = <String>[
        _isNew ? '“$name” eklendi.' : '“$name” güncellendi.',
        if (added.isNotEmpty) '${_lineLabels(added)} hattına bağlandı.',
        if (removed.isNotEmpty) '${_lineLabels(removed)} hattından çıkarıldı.',
        for (final w in warnings) '$w.',
      ];
      return (message: parts.join(' '), warning: warnings.isNotEmpty);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _formError = stopSaved
              ? 'Durak kaydedildi ama hat bağlantısı yapılamadı: '
                  '${sehiriciErrorMessage(e)} Tekrar kaydetmeyi deneyin.'
              : sehiriciErrorMessage(e);
        });
      }
      // Durak yazıldıysa hat bilgisi tazelensin (yeniden denemede doğru fark).
      if (stopSaved) await _c.reloadCityData();
      return null;
    }
  }

  String _lineLabels(Set<String> ids) => [
        for (final l in _c.lines)
          if (ids.contains(l.id)) l.code.isEmpty ? l.name : l.code,
      ].join(', ');

  Future<void> _save() async {
    final result = await _persist();
    if (result != null && mounted) Navigator.of(context).pop(result);
  }

  /// Kaydeder ve formu bir sonraki durak için boşaltır: hat seçimi ve aktiflik
  /// korunur, harita son eklenen durağın yanından açılır, ad numarası devam
  /// eder.
  Future<void> _saveAndContinue() async {
    final result = await _persist();
    if (result == null || !mounted) return;
    setState(() {
      _addedNames.add(_name.text.trim());
      _newId = const Uuid().v4();
      _name.clear();
      _code.clear();
      _address.clear();
      _lat.clear();
      _lng.clear();
      _autoName = null;
      _autoAddress = null;
      _suggestion = null;
      _saving = false;
      _formError = result.warning ? result.message : null;
    });
  }

  Future<void> _delete() async {
    final stop = widget.stop!;
    final used = _c.linesByStop[stop.id] ?? const [];
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
      await _c.lineService.deleteStopOrThrow(stop.id);
      await _c.reloadCityData();
      _refreshUserSide();
      if (mounted) {
        Navigator.of(context)
            .pop((message: '“${stop.name}” silindi.', warning: false));
      }
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

  // ── Arayüz ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final used = widget.stop == null
        ? const <SehiriciLine>[]
        : (_c.linesByStop[widget.stop!.id] ?? const []);
    return SehiriciSheetScaffold(
      title: _isNew ? 'Yeni Durak' : 'Durağı Düzenle',
      subtitle: _addedNames.isEmpty
          ? _c.city?.name
          : '${_c.city?.name ?? ''} · bu oturumda ${_addedNames.length} durak eklendi',
      leading: SehiriciStopIcon(
        height: 44,
        lineColors: used.map((l) => l.color).take(3).toList(),
      ),
      bottomBar: _bottomBar(),
      child: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            if (_formError != null) _errorBox(_formError!),
            if (_addedNames.isNotEmpty && _formError == null)
              _addedBanner(),
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
            _locationSection(),
            _infoSection(),
            if (_c.lines.isNotEmpty) _linesSection(),
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

  Widget _errorBox(String text) {
    return Container(
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
            child: Text(text,
                style: const TextStyle(
                    color: Color(0xFF991B1B), fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _addedBanner() {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFDCFCE7),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded,
              color: Color(0xFF15803D), size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '“${_addedNames.last}” eklendi. Sıradaki durağın konumunu seçin; '
              'ad ve numara kendiliğinden gelir.',
              style: const TextStyle(
                  color: Color(0xFF166534), fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  /// Konum önce: seçilince ad ve adres sokaktan kendiliğinden dolar.
  Widget _locationSection() {
    return SehiriciFormSection(
      title: 'Konum',
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _saving ? null : _pickOnMap,
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
                  onPressed: _locating || _saving ? null : _useMyLocation,
                  icon: _locating
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
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
          const SizedBox(height: 10),
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
                  onChanged: (_) => setState(() {}),
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
                  onChanged: (_) => setState(() {}),
                  decoration: sehiriciInput('Boylam'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _infoSection() {
    final suggestion = _suggestion;
    final bases = suggestion?.bases ?? const <String>[];
    final current = _name.text.trim();
    return SehiriciFormSection(
      title: 'Durak bilgisi',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            validator: (v) =>
                (v ?? '').trim().isEmpty ? 'Durak adı gerekli' : null,
            onChanged: (_) => setState(() {}),
            decoration: sehiriciInput(
              'Durak adı',
              hint: 'Konum seçince sokaktan gelir · Ör. Yafes Cad. 1',
              icon: Icons.signpost_outlined,
            ).copyWith(
              suffixIcon: _naming
                  ? const Padding(
                      padding: EdgeInsets.all(14),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      tooltip: 'Sokak adından öner',
                      icon: const Icon(Icons.auto_awesome_rounded),
                      color: AdminUi.brand,
                      onPressed: _position == null
                          ? null
                          : () => _suggestName(force: true),
                    ),
            ),
          ),
          if (_naming)
            const Padding(
              padding: EdgeInsets.only(top: 8, left: 4),
              child: Text('Sokak adı aranıyor…',
                  style: TextStyle(color: AdminUi.muted, fontSize: 12.5)),
            )
          else if (suggestion != null || _autoName != null) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final base in bases)
                  _suggestionChip(_numbered(base), current, () => _useSuggestion(base)),
                _suggestionChip(
                    _numbered(null), current, () => _useSuggestion(null)),
              ],
            ),
          ],
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
    );
  }

  Widget _suggestionChip(String label, String current, VoidCallback onTap) {
    final selected = label == current;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      avatar: Icon(
        selected ? Icons.check_rounded : Icons.signpost_outlined,
        size: 16,
        color: selected ? Colors.white : AdminUi.brand,
      ),
      showCheckmark: false,
      selectedColor: AdminUi.brand,
      labelStyle: TextStyle(
        color: selected ? Colors.white : AdminUi.ink,
        fontWeight: FontWeight.w700,
        fontSize: 12.5,
      ),
      backgroundColor: Colors.white,
      side: BorderSide(color: selected ? AdminUi.brand : AdminUi.line),
      visualDensity: VisualDensity.compact,
    );
  }

  /// Hatlara bağla: seçilen hatlarda durak en az sapmalı sıraya girer.
  Widget _linesSection() {
    final pos = _position;
    final added = [
      for (final l in _c.lines)
        if (_lineIds.contains(l.id) && !_initialLineIds.contains(l.id)) l,
    ];
    return SehiriciFormSection(
      title: 'Hatlar',
      hint: _isNew
          ? 'Durağı eklerken hatlara da bağlayın; hattın en uygun sırasına yerleşir.'
          : 'Bu durağın geçtiği hatlar. Kaydedince eklenir / çıkarılır.',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final l in _c.lines)
                FilterChip(
                  key: ValueKey('stop-line-${l.id}'),
                  selected: _lineIds.contains(l.id),
                  onSelected: _saving
                      ? null
                      : (v) => setState(() {
                            if (v) {
                              _lineIds.add(l.id);
                            } else {
                              _lineIds.remove(l.id);
                            }
                          }),
                  showCheckmark: true,
                  checkmarkColor: AdminUi.brand,
                  selectedColor: AdminUi.brand.withValues(alpha: 0.10),
                  backgroundColor: Colors.white,
                  side: BorderSide(
                    color: _lineIds.contains(l.id) ? AdminUi.brand : AdminUi.line,
                  ),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SehiriciLineBadge.forLine(l, height: 20, minWidth: 30),
                      const SizedBox(width: 6),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 150),
                        child: Text(
                          l.name.isEmpty ? 'Adsız hat' : l.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          for (final l in added)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Row(
                children: [
                  Icon(Icons.subdirectory_arrow_right_rounded,
                      size: 18, color: AdminUi.brand),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      '${l.code.isEmpty ? l.name : l.code}: '
                      '${pos == null ? 'konum seçilince yerleştirilir' : _placement(l, pos)}',
                      style: const TextStyle(
                          fontSize: 12.5,
                          color: AdminUi.muted,
                          fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Hattın neresine gireceğinin açıklaması.
  String _placement(SehiriciLine line, LatLng pos) {
    final ordered = [
      for (final s in line.stops)
        if (s.stopId != widget.stop?.id) s.asStop,
    ];
    if (ordered.isEmpty) return 'hattın ilk durağı olur';
    final i = sehiriciBestInsertIndex(ordered, pos.latitude, pos.longitude);
    if (i == 0) return '1. durak olur (${ordered.first.name} öncesi)';
    if (i == ordered.length) {
      return '${i + 1}. durak olur (${ordered.last.name} sonrası)';
    }
    return '${i + 1}. durak olur (${ordered[i - 1].name} ile ${ordered[i].name} arası)';
  }

  Widget _bottomBar() {
    final spinner = const SizedBox(
      width: 18,
      height: 18,
      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
    );
    final linesChanged = !setEquals(_lineIds, _initialLineIds);
    return Row(
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
        if (_isNew) ...[
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _saving ? null : _saveAndContinue,
              icon: const Icon(Icons.playlist_add_rounded),
              label: const FittedBox(
                fit: BoxFit.scaleDown,
                child: Text('Ekle ve devam et', maxLines: 1, softWrap: false),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: AdminUi.brand,
                side: BorderSide(color: AdminUi.brand.withValues(alpha: 0.5)),
                minimumSize: const Size.fromHeight(52),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16)),
              ),
            ),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving ? spinner : const Icon(Icons.check_rounded),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                _isNew
                    ? 'Durağı Ekle'
                    : (linesChanged ? 'Kaydet · hatlar' : 'Kaydet'),
                maxLines: 1,
                softWrap: false,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: AdminUi.brand,
              minimumSize: const Size.fromHeight(52),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      ],
    );
  }
}
