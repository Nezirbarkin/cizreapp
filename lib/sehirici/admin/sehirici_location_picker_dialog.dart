// ignore_for_file: deprecated_member_use

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/theme/app_map_style.dart';
import '../../core/utils/map_marker_icons.dart';
import '../../core/widgets/map_controls.dart';
import '../../features/admin/widgets/admin_ui.dart';
import '../models/sehirici_models.dart';
import '../services/sehirici_street_namer.dart';
import '../utils/sehirici_route_geometry.dart';
import '../utils/sehirici_stop_naming.dart';
import '../widgets/sehirici_common_widgets.dart';

/// Çoklu seçim modunda haritadan toplanan tek bir durak adayı.
class SehiriciPickedStop {
  SehiriciPickedStop({
    required this.position,
    required this.name,
    this.address,
    this.existing,
  });

  LatLng position;
  String name;

  /// Sokak/mahalleden üretilen kısa adres ("Nur Mah., Yafes Cad."); yoksa null.
  String? address;

  /// Hatta BAĞLANAN mevcut durak: yeni durak oluşturulmaz, bu durak hatta
  /// sırasıyla eklenir. null → yeni durak.
  final SehiriciStop? existing;

  bool get isExisting => existing != null;
}

/// [SehiriciLocationPickerDialog.pickMultiple] sonucu.
class SehiriciMultiPickResult {
  const SehiriciMultiPickResult({required this.stops, this.line});

  /// Sırasıyla: yeni duraklar ve (hat modunda) hatta bağlanan mevcut duraklar.
  final List<SehiriciPickedStop> stops;

  /// Seçicide "Hatta da ekle" ile seçilen hat (yoksa null).
  final SehiriciLine? line;
}

/// Admin'in konumu elle lat/lng yazmak yerine haritaya dokunarak (veya pini
/// sürükleyerek) seçmesini sağlayan ekran.
///
/// İki modda çalışır:
///  • **Tek seçim** ([SehiriciLocationPickerDialog.pickSingle]) — tek bir pin,
///    "Bu konumu kullan" ile [LatLng] döner. Durak ve şehir formundaki
///    "Haritadan seç" bunu kullanır.
///  • **Çoklu seçim** ([SehiriciLocationPickerDialog.pickMultiple]) — haritaya
///    her dokunuşta sıralı, NUMARALI bir durak pini eklenir. Ad pinin
///    durduğu sokaktan otomatik gelir ve aynı sokakta kaldığı yerden
///    numaralanır ("Yafes Cad. 1", "Yafes Cad. 2" …; bkz.
///    [SehiriciStreetNamer]). Adlar alttaki listeden değiştirilebilir.
///
/// **Hat modu** ([lineStops] dolu ya da "Hatta da ekle" ile hat seçili):
/// hattın mevcut durakları numaralı pinlerle çizilir, yeni duraklar
/// numarayı ve çizgiyi son duraktan DEVAM ettirir. Gri (başka) bir durağa
/// dokunmak onu hatta bağlar — yeni durak oluşturmadan.
///
/// [existingStops] şehirdeki mevcut duraklardır (gri nokta); yeni pin
/// bunlardan birine çok yakın düşerse uyarı verilir (yanlışlıkla kopya durak
/// oluşturmayı engeller).
class SehiriciLocationPickerDialog extends StatefulWidget {
  final double initialLat;
  final double initialLng;
  final double initialZoom;
  final bool multiSelect;
  final List<SehiriciStop> existingStops;

  /// Yeni pinlerin rengi (hat rengi). Verilmezse seçili hattın ya da admin
  /// marka rengi.
  final Color? lineColor;

  /// Hat modu: hattın şu anki durakları, sırasıyla (devam noktası).
  final List<SehiriciStop> lineStops;

  /// Gri duraklara dokununca hatta bağlansın mı (hat modu).
  final bool linkExisting;

  /// Doluysa üstte "Hatta da ekle" seçimi çıkar (Duraklar sekmesi).
  final List<SehiriciLine> lineChoices;
  final String? initialLineId;

  /// Sokak adı kaynağı; verilmezse [SehiriciStreetNamer.instance].
  final SehiriciStreetNamer? namer;

  const SehiriciLocationPickerDialog({
    super.key,
    required this.initialLat,
    required this.initialLng,
    this.initialZoom = 15,
    this.multiSelect = false,
    this.existingStops = const [],
    this.lineColor,
    this.lineStops = const [],
    this.linkExisting = false,
    this.lineChoices = const [],
    this.initialLineId,
    this.namer,
  });

  /// Tek konum seçtirir. İptal edilirse null döner.
  static Future<LatLng?> pickSingle(
    BuildContext context, {
    required double initialLat,
    required double initialLng,
    double initialZoom = 15,
    List<SehiriciStop> existingStops = const [],
    SehiriciStreetNamer? namer,
  }) async {
    final result = await showDialog<SehiriciMultiPickResult>(
      context: context,
      builder: (_) => SehiriciLocationPickerDialog(
        initialLat: initialLat,
        initialLng: initialLng,
        initialZoom: initialZoom,
        existingStops: existingStops,
        namer: namer,
      ),
    );
    if (result == null || result.stops.isEmpty) return null;
    return result.stops.first.position;
  }

  /// Sırayla birden çok durak seçtirir. İptal edilirse null döner.
  static Future<SehiriciMultiPickResult?> pickMultiple(
    BuildContext context, {
    required double initialLat,
    required double initialLng,
    double initialZoom = 15,
    List<SehiriciStop> existingStops = const [],
    Color? lineColor,
    List<SehiriciStop> lineStops = const [],
    bool linkExisting = false,
    List<SehiriciLine> lineChoices = const [],
    String? initialLineId,
    SehiriciStreetNamer? namer,
  }) {
    return showDialog<SehiriciMultiPickResult>(
      context: context,
      builder: (_) => SehiriciLocationPickerDialog(
        initialLat: initialLat,
        initialLng: initialLng,
        initialZoom: initialZoom,
        multiSelect: true,
        existingStops: existingStops,
        lineColor: lineColor,
        lineStops: lineStops,
        linkExisting: linkExisting,
        lineChoices: lineChoices,
        initialLineId: initialLineId,
        namer: namer,
      ),
    );
  }

  @override
  State<SehiriciLocationPickerDialog> createState() =>
      _SehiriciLocationPickerDialogState();
}

/// Listedeki bir aday + ad alanı + sokak adı çözümleme durumu.
class _Pick {
  _Pick(this.stop) : ctrl = TextEditingController(text: stop.name);

  final SehiriciPickedStop stop;

  /// Ad alanının controller'ı: liste State'i yeniden kullandığı için
  /// (silme/yeniden numaralama sonrası) metin açıkça güncellenir.
  final TextEditingController ctrl;

  /// Ad otomatik mi (sokak + numara)? Admin elle yazınca false olur ve bir
  /// daha dokunulmaz.
  bool autoName = true;

  /// Ad tabanı ("Yafes Cad."); null → "Durak".
  String? base;

  /// Seçilebilir diğer tabanlar (yakındaki yollar, mahalle).
  List<String> bases = const [];

  bool resolving = false;

  /// Son çözümleme isteğinin sırası (pin sürüklenince eski yanıt atılır).
  int seq = 0;
  Future<void>? pending;

  bool get isExisting => stop.isExisting;
}

enum _HitKind { fixed, pick, existing }

typedef _Hit = ({_HitKind kind, SehiriciStop? stop, int index, String name});

class _SehiriciLocationPickerDialogState
    extends State<SehiriciLocationPickerDialog> {
  /// Yeni bir pin, mevcut bir durağa veya başka bir yeni pine bu mesafeden
  /// yakın düşerse kopya sayılır (hat modunda o durağa dokunulmuş sayılır).
  static const double _kDuplicateRadiusMeters = 25;

  final Completer<GoogleMapController> _mapCtl =
      Completer<GoogleMapController>();

  late final SehiriciStreetNamer _namer =
      widget.namer ?? SehiriciStreetNamer.instance;

  /// Çoklu seçim adayları (tek seçimde boş).
  final List<_Pick> _picks = [];

  /// Tek seçim pini ve altındaki sokak.
  late LatLng _single = LatLng(widget.initialLat, widget.initialLng);
  String? _singleStreet;
  int _singleSeq = 0;

  /// "Hatta da ekle" ile seçilen hat.
  SehiriciLine? _line;

  /// Mevcut duraklar için küçük gri nokta ve numaralı pinler (async üretilir).
  BitmapDescriptor? _dot;
  final Map<String, BitmapDescriptor> _pins = {};

  /// Ekranın altında kısa süre görünen bildirim (SnackBar diyaloğun ARKASINDA
  /// kalırdı).
  String? _notice;
  bool _noticeIsWarning = true;
  Timer? _noticeTimer;

  bool _submitting = false;

  bool get _isMulti => widget.multiSelect;

  /// Seçici açılırken hat seçimi varsa hattın, yoksa verilen durak dizisi.
  List<SehiriciStop> get _fixed => widget.lineChoices.isEmpty
      ? widget.lineStops
      : [for (final s in _line?.stops ?? const <SehiriciLineStop>[]) s.asStop];

  bool get _canLink => widget.linkExisting || _line != null;

  Color get _pinColor => widget.lineColor ?? _line?.color ?? AdminUi.brand;

  @override
  void initState() {
    super.initState();
    for (final l in widget.lineChoices) {
      if (l.id == widget.initialLineId) _line = l;
    }
    _loadIcons();
    if (!_isMulti) _resolveSingle();
  }

  @override
  void dispose() {
    _noticeTimer?.cancel();
    for (final p in _picks) {
      p.ctrl.dispose();
    }
    super.dispose();
  }

  Future<void> _loadIcons() async {
    final dot = await MapMarkerIcons.stop(
      style: MapStopStyle.dot,
      detail: MapStopDetail.mid,
      lineColors: const [Color(0xFF64748B)],
    );
    if (!mounted) return;
    setState(() => _dot = dot);
    await _ensurePins();
  }

  String _pinKey(int? number, Color color) =>
      '${number ?? 'x'}_${color.toARGB32()}';

  /// Şu an gereken numaralı pinleri üretir (yoksa).
  Future<void> _ensurePins() async {
    final color = _pinColor;
    final wanted = _isMulti
        ? [for (var i = 1; i <= _fixed.length + _picks.length; i++) i]
        : const <int?>[null];
    var changed = false;
    for (final n in wanted) {
      final key = _pinKey(n, color);
      if (_pins.containsKey(key)) continue;
      _pins[key] = await MapMarkerIcons.numberedPin(
        number: n,
        color: color,
        large: !_isMulti,
      );
      changed = true;
    }
    if (changed && mounted) setState(() {});
  }

  // ── Ad ───────────────────────────────────────────────────────

  /// Numaralandırmada dolu sayılan adlar: şehirdeki duraklar, hattaki
  /// duraklar ve elle adlandırılmış / bağlanmış adaylar.
  List<String> _takenNames({_Pick? except}) => [
        for (final s in widget.existingStops) s.name,
        for (final s in _fixed) s.name,
        for (final p in _picks)
          if (p != except && (p.isExisting || !p.autoName)) p.stop.name,
      ];

  /// Otomatik adlı adaylara sırayla "Sokak N" verir; numara şehirde o
  /// sokakta kalınan yerden devam eder.
  ///
  /// Elle adlandırılan aday da kendi sokağındaki numara YERİNİ tutar: admin
  /// 1. pini yeniden adlandırınca 2. pin "… 2" olarak kalır, adı altında
  /// kaymaz (atlanan numara sonraki eklemelerde de boş kalır).
  void _relabel() {
    final used = _takenNames();
    for (final p in _picks) {
      if (p.isExisting) continue;
      final name = sehiriciNextNumberedName(
        p.base ?? kSehiriciFallbackStopBase,
        used,
      );
      used.add(name);
      if (!p.autoName) continue;
      p.stop.name = name;
      if (p.ctrl.text != name) p.ctrl.text = name;
    }
  }

  /// [base] seçilirse bu adayın alacağı ad (menü önizlemesi).
  String _previewName(_Pick p, String? base) {
    // [_relabel]'ın aynısı, yalnız bu adayın tabanı [base] olarak.
    final used = _takenNames(except: p);
    for (final o in _picks) {
      if (o.isExisting) continue;
      final name = sehiriciNextNumberedName(
        (o == p ? base : o.base) ?? kSehiriciFallbackStopBase,
        used,
      );
      if (o == p) return name;
      used.add(name);
    }
    return sehiriciNextNumberedName(base ?? kSehiriciFallbackStopBase, used);
  }

  void _startResolve(_Pick p) {
    p.pending = _resolve(p);
  }

  Future<void> _resolve(_Pick p) async {
    final seq = ++p.seq;
    setState(() => p.resolving = true);
    final suggestion = await _namer.lookup(p.stop.position);
    if (!mounted || seq != p.seq || !_picks.contains(p)) return;
    setState(() {
      p.resolving = false;
      p.base = suggestion?.base;
      p.bases = suggestion?.bases ?? const [];
      p.stop.address = suggestion?.address;
      _relabel();
    });
  }

  Future<void> _resolveSingle() async {
    final seq = ++_singleSeq;
    final suggestion = await _namer.lookup(_single);
    if (!mounted || seq != _singleSeq) return;
    setState(() => _singleStreet = suggestion?.base);
  }

  // ── Düzenleme ────────────────────────────────────────────────

  /// Mevcut duraklar (gri nokta): hattakiler ve bağlananlar hariç, tekrarsız.
  List<SehiriciStop> get _referenceStops {
    final hidden = <String>{
      for (final s in _fixed) s.id,
      for (final p in _picks)
        if (p.isExisting) p.stop.existing!.id,
    };
    return [
      for (final s in widget.existingStops)
        if (hidden.add(s.id)) s,
    ];
  }

  /// [target]'a [_kDuplicateRadiusMeters] içindeki hat durağı / aday / mevcut
  /// durak; yoksa null.
  _Hit? _hitAt(LatLng target, {_Pick? ignore}) {
    bool near(LatLng p) => distanceMeters(target, p) < _kDuplicateRadiusMeters;
    final fixed = _fixed;
    for (var i = 0; i < fixed.length; i++) {
      if (near(LatLng(fixed[i].lat, fixed[i].lng))) {
        return (kind: _HitKind.fixed, stop: fixed[i], index: i, name: fixed[i].name);
      }
    }
    for (var i = 0; i < _picks.length; i++) {
      final p = _picks[i];
      if (p == ignore) continue;
      if (near(p.stop.position)) {
        return (kind: _HitKind.pick, stop: p.stop.existing, index: i, name: p.stop.name);
      }
    }
    for (final s in _referenceStops) {
      if (near(LatLng(s.lat, s.lng))) {
        return (kind: _HitKind.existing, stop: s, index: -1, name: s.name);
      }
    }
    return null;
  }

  void _onMapTap(LatLng target) {
    if (!_isMulti) {
      setState(() {
        _single = target;
        _singleStreet = null;
      });
      _resolveSingle();
      return;
    }
    final hit = _hitAt(target);
    if (hit == null) {
      _addNew(target);
      return;
    }
    switch (hit.kind) {
      case _HitKind.fixed:
        _say('“${hit.name}” bu hatta zaten var (${hit.index + 1}. durak).');
      case _HitKind.pick:
        _say('Buraya çok yakın bir durak zaten var: ${hit.name}');
      case _HitKind.existing:
        if (_canLink) {
          _link(hit.stop!);
        } else {
          _say('Buraya çok yakın bir durak zaten var: ${hit.name}');
        }
    }
  }

  void _onExistingTap(SehiriciStop stop) {
    if (_canLink) {
      _link(stop);
    } else {
      _say('Mevcut durak: ${stop.name}', warning: false);
    }
  }

  void _addNew(LatLng target) {
    final pick = _Pick(SehiriciPickedStop(position: target, name: ''));
    setState(() {
      _picks.add(pick);
      _relabel();
    });
    _startResolve(pick);
    _ensurePins();
  }

  /// Mevcut bir durağı (yeni durak oluşturmadan) hatta sıradaki durak yapar.
  void _link(SehiriciStop stop) {
    if (!stop.isActive) {
      // Pasif durak yolcuya görünmez; hatta bağlamak sessiz bir boşluk açardı.
      _say('“${stop.name}” pasif bir durak; önce Duraklar sekmesinden '
          'aktifleştirin.');
      return;
    }
    final pick = _Pick(SehiriciPickedStop(
      position: LatLng(stop.lat, stop.lng),
      name: stop.name,
      address: stop.address,
      existing: stop,
    ))
      ..autoName = false;
    setState(() {
      _picks.add(pick);
      _relabel();
    });
    _say('“${stop.name}” hatta bağlandı.', warning: false);
    _ensurePins();
  }

  void _say(String message, {bool warning = true}) {
    _noticeTimer?.cancel();
    setState(() {
      _notice = message;
      _noticeIsWarning = warning;
    });
    _noticeTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) setState(() => _notice = null);
    });
  }

  void _onPinDragged(_Pick p, LatLng target) {
    final hit = _hitAt(target, ignore: p);
    if (hit != null) {
      _say('Buraya çok yakın bir durak zaten var: ${hit.name}');
      // Pin'i geri çekmek için setState yeterli: marker konumu
      // _picks'ten türetiliyor, sürükleme kalıcı olmuyor.
      setState(() {});
      return;
    }
    setState(() => p.stop.position = target);
    // Yeni yerdeki sokağa göre yeniden adlandır (elle verilmiş ad korunur,
    // adres yine güncellenir).
    _startResolve(p);
  }

  void _removeAt(int index) {
    setState(() {
      _picks.removeAt(index).ctrl.dispose();
      // Otomatik adlar yeniden numaralanır; elle yazılan adlara dokunulmaz.
      _relabel();
    });
  }

  void _selectLine(String? id) {
    SehiriciLine? line;
    for (final l in widget.lineChoices) {
      if (l.id == id) line = l;
    }
    if (line?.id == _line?.id) return;
    setState(() {
      _line = line;
      // Bağlanan mevcut duraklar yalnız hat seçiliyken anlamlı; yeni hatta
      // zaten olanlar da listeden düşer.
      final inLine = {for (final s in _fixed) s.id};
      for (final p in [..._picks]) {
        if (p.isExisting &&
            (line == null || inLine.contains(p.stop.existing!.id))) {
          _picks.remove(p);
          p.ctrl.dispose();
        }
      }
      _relabel();
    });
    _ensurePins();
    // Hattın son durağına git: oradan devam edilir.
    final fixed = _fixed;
    if (fixed.isNotEmpty) {
      _mapCtl.future.then((c) => c.animateCamera(
          CameraUpdate.newLatLng(LatLng(fixed.last.lat, fixed.last.lng))));
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;
    if (!_isMulti) {
      Navigator.of(context).pop(SehiriciMultiPickResult(
        stops: [SehiriciPickedStop(position: _single, name: '')],
      ));
      return;
    }
    if (_picks.isEmpty) return;
    if (_picks.any((p) => !p.isExisting && p.stop.name.trim().isEmpty)) {
      _say('Adı boş durak var. Tüm duraklara ad verin.');
      return;
    }
    // Sokak adı yolda olan adaylar varsa kısa süre bekle: ad "Durak N"
    // olarak kaydedilmesin.
    final pending = [
      for (final p in _picks)
        if (p.resolving && p.pending != null) p.pending!,
    ];
    if (pending.isNotEmpty) {
      setState(() => _submitting = true);
      await Future.wait(pending)
          .timeout(const Duration(seconds: 6), onTimeout: () => const []);
      if (!mounted) return;
    }
    Navigator.of(context).pop(SehiriciMultiPickResult(
      stops: [for (final p in _picks) p.stop],
      line: _line,
    ));
  }

  // ── Harita ───────────────────────────────────────────────────

  Set<Marker> _buildMarkers() {
    final markers = <Marker>{};
    final color = _pinColor;

    // Mevcut duraklar — referans; hat modunda dokununca bağlanır.
    for (final s in _referenceStops) {
      markers.add(Marker(
        markerId: MarkerId('existing_${s.id}'),
        position: LatLng(s.lat, s.lng),
        icon: _dot ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueAzure),
        anchor: const Offset(0.5, 0.5),
        alpha: 0.9,
        zIndexInt: 1,
        consumeTapEvents: true,
        infoWindow: InfoWindow(
          title: s.name,
          snippet: _canLink ? 'Dokun: hatta bağla' : 'Mevcut durak',
        ),
        onTap: () => _onExistingTap(s),
      ));
    }

    if (!_isMulti) {
      markers.add(Marker(
        markerId: const MarkerId('picked_0'),
        position: _single,
        draggable: true,
        onDragEnd: (pos) => _onMapTap(pos),
        icon: _pins[_pinKey(null, color)] ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        anchor: const Offset(0.5, 1),
        zIndexInt: 5,
      ));
      return markers;
    }

    // Hattın mevcut durakları: numaralı, soluk, sabit.
    final fixed = _fixed;
    for (var i = 0; i < fixed.length; i++) {
      final s = fixed[i];
      markers.add(Marker(
        markerId: MarkerId('line_${s.id}'),
        position: LatLng(s.lat, s.lng),
        icon: _pins[_pinKey(i + 1, color)] ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueViolet),
        anchor: const Offset(0.5, 1),
        alpha: 0.7,
        zIndexInt: 3,
        consumeTapEvents: true,
        infoWindow: InfoWindow(title: '${i + 1}. ${s.name}', snippet: 'Hatta'),
        onTap: () => _say('“${s.name}” bu hatta zaten var (${i + 1}. durak).'),
      ));
    }

    for (var i = 0; i < _picks.length; i++) {
      final p = _picks[i];
      final number = fixed.length + i + 1;
      markers.add(Marker(
        markerId: MarkerId('picked_$i'),
        position: p.stop.position,
        draggable: !p.isExisting,
        onDragEnd: (pos) => _onPinDragged(p, pos),
        icon: _pins[_pinKey(number, color)] ??
            BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
        anchor: const Offset(0.5, 1),
        zIndexInt: 5,
        infoWindow: InfoWindow(title: '$number. ${p.stop.name}'),
      ));
    }
    return markers;
  }

  /// Hattın mevcut kısmı (soluk) + son duraktan devam eden yeni kısım.
  Set<Polyline> _buildPolylines() {
    if (!_isMulti) return const {};
    final color = _pinColor;
    final fixed = [for (final s in _fixed) LatLng(s.lat, s.lng)];
    final fresh = [
      if (fixed.isNotEmpty) fixed.last,
      for (final p in _picks) p.stop.position,
    ];
    return {
      if (fixed.length >= 2)
        Polyline(
          polylineId: const PolylineId('line_existing'),
          points: fixed,
          color: color.withValues(alpha: 0.45),
          width: 4,
          jointType: JointType.round,
        ),
      if (fresh.length >= 2) ...{
        Polyline(
          polylineId: const PolylineId('picked_order_casing'),
          points: fresh,
          color: Colors.white.withValues(alpha: 0.9),
          width: 7,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
        Polyline(
          polylineId: const PolylineId('picked_order'),
          points: fresh,
          color: color.withValues(alpha: 0.9),
          width: 4,
          jointType: JointType.round,
          startCap: Cap.roundCap,
          endCap: Cap.roundCap,
        ),
      },
    };
  }

  /// Cam zoom butonları için ortak kamera hareketi.
  Future<void> _zoomBy(double delta) async {
    final c = await _mapCtl.future;
    await c.animateCamera(CameraUpdate.zoomBy(delta));
  }

  Widget _map() {
    // Harita görünümü (Otomatik/Açık/Koyu) harita üstündeki düğmeyle
    // değiştirilir; MapStyleBuilder tercihi anında uygular.
    return MapStyleBuilder(
      builder: (context, mapStyle) => _mapSurface(mapStyle),
    );
  }

  String get _hint {
    if (!_isMulti) return 'Konumun olacağı noktaya dokunun veya pini sürükleyin.';
    if (_fixed.isNotEmpty) {
      return 'Hattın son durağından devam edin: yeni noktaya dokunun; gri '
          'durağa dokunursanız hatta bağlanır.';
    }
    if (_canLink) {
      return 'Güzergâh sırasıyla dokunun; gri durağa dokunursanız hatta '
          'bağlanır, boş yere dokunursanız yeni durak olur.';
    }
    return 'Güzergâh üzerinde durak sırasıyla haritaya dokunun; ad sokaktan '
        'otomatik gelir. Pinleri sürükleyerek düzeltebilirsiniz.';
  }

  Widget _mapSurface(String mapStyle) {
    return Stack(
      children: [
        GoogleMap(
          style: mapStyle,
          initialCameraPosition: CameraPosition(
            target: LatLng(widget.initialLat, widget.initialLng),
            zoom: widget.initialZoom,
          ),
          onMapCreated: (c) {
            if (!_mapCtl.isCompleted) _mapCtl.complete(c);
          },
          onTap: _onMapTap,
          markers: _buildMarkers(),
          polylines: _buildPolylines(),
          myLocationButtonEnabled: false,
          // Gömülü gri zoom kutuları yerine cam kontroller.
          zoomControlsEnabled: false,
          mapToolbarEnabled: false,
          // Düz (2D) harita: eğim hareketi ve 3D bina kabartması kapalı.
          tiltGesturesEnabled: false,
          buildingsEnabled: false,
          mapType: MapType.normal,
        ),
        Positioned(
          right: 12,
          bottom: 64,
          child: MapZoomControls(
            onZoomIn: () => _zoomBy(1),
            onZoomOut: () => _zoomBy(-1),
            showThemeToggle: true,
          ),
        ),
        Positioned(
          left: 12,
          right: 12,
          bottom: 12,
          child: MapHintBar(
            text: _notice ?? _hint,
            icon: _notice == null
                ? Icons.touch_app
                : (_noticeIsWarning
                    ? Icons.info_outline_rounded
                    : Icons.check_circle_outline_rounded),
            accentColor: _notice == null
                ? null
                : (_noticeIsWarning
                    ? const Color(0xFFD97706)
                    : const Color(0xFF15803D)),
          ),
        ),
      ],
    );
  }

  // ── Arayüz ───────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final narrow = size.width < 720;
    final content = Column(
      children: [
        _header(),
        if (_isMulti && widget.lineChoices.isNotEmpty) _lineBar(),
        Expanded(child: _map()),
        if (_isMulti) _pickedList(),
        _footer(),
      ],
    );
    if (narrow) {
      // Telefonda tam ekran: haritaya en çok yer.
      return Dialog.fullscreen(
        backgroundColor: AdminUi.page,
        child: SafeArea(child: content),
      );
    }
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: AdminUi.page,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: 680,
        height: size.height < 700 ? size.height - 48 : 660,
        child: content,
      ),
    );
  }

  Widget _header() {
    final fixedCount = _fixed.length;
    final subtitle = !_isMulti
        ? 'Dokunun ya da pini sürükleyin'
        : fixedCount > 0
            ? 'Hatta $fixedCount durak · ${_picks.length} yeni'
            : '${_picks.length} durak · dokunarak ekleyin';
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 6, 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AdminUi.brand, const Color(0xFF3F1D7A)],
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Icon(
              _isMulti ? Icons.pin_drop_rounded : Icons.location_on_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isMulti ? 'Haritadan Çoklu Durak' : 'Haritadan Konum Seç',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 12.5),
                ),
              ],
            ),
          ),
          if (_isMulti && _picks.isNotEmpty)
            IconButton(
              tooltip: 'Son durağı geri al',
              icon: const Icon(Icons.undo_rounded, color: Colors.white),
              onPressed: () => _removeAt(_picks.length - 1),
            ),
          IconButton(
            tooltip: 'Kapat',
            icon: const Icon(Icons.close_rounded, color: Colors.white),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  /// "Hatta da ekle": seçilirse yeni duraklar o hattın sonuna eklenir.
  Widget _lineBar() {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: AdminUi.line)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 2, 10, 2),
      child: Row(
        children: [
          Icon(Icons.route_rounded, color: AdminUi.brand, size: 20),
          const SizedBox(width: 8),
          const Text(
            'Hatta da ekle',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                key: const ValueKey('sehirici-picker-line'),
                isExpanded: true,
                value: _line?.id ?? '',
                onChanged: _submitting ? null : _selectLine,
                items: [
                  const DropdownMenuItem(
                    value: '',
                    child: Text('Hayır, yalnız durak',
                        style: TextStyle(color: AdminUi.muted)),
                  ),
                  for (final l in widget.lineChoices)
                    DropdownMenuItem(
                      value: l.id,
                      child: Row(
                        children: [
                          SehiriciLineBadge.forLine(l, height: 22, minWidth: 34),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              l.name.isEmpty ? 'Adsız hat' : l.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Çoklu modda seçilen durakların düzenlenebilir listesi.
  Widget _pickedList() {
    if (_picks.isEmpty) {
      return Container(
        width: double.infinity,
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            const Icon(Icons.touch_app_rounded, color: AdminUi.muted, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _fixed.isNotEmpty
                    ? 'Hattın ${_fixed.length}. durağından devam edin — '
                        'haritaya dokunun.'
                    : 'Henüz durak eklenmedi — haritaya dokunarak başlayın.',
                style: const TextStyle(color: AdminUi.muted, fontSize: 13),
              ),
            ),
          ],
        ),
      );
    }
    final offset = _fixed.length;
    return Container(
      color: Colors.white,
      constraints: const BoxConstraints(maxHeight: 188),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
        itemCount: _picks.length,
        separatorBuilder: (_, __) => const SizedBox(height: 6),
        itemBuilder: (ctx, i) => _pickRow(_picks[i], i, offset + i + 1),
      ),
    );
  }

  Widget _pickRow(_Pick p, int index, int number) {
    final badge = Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(color: _pinColor, shape: BoxShape.circle),
      alignment: Alignment.center,
      child: Text(
        '$number',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
    final remove = IconButton(
      tooltip: 'Kaldır',
      icon: const Icon(Icons.close_rounded, size: 20),
      color: AdminUi.muted,
      onPressed: () => _removeAt(index),
    );
    if (p.isExisting) {
      return Row(
        children: [
          badge,
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.stop.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700),
                ),
                const Row(
                  children: [
                    Icon(Icons.link_rounded, size: 14, color: AdminUi.muted),
                    SizedBox(width: 4),
                    Text(
                      'Mevcut durak · hatta bağlanır',
                      style: TextStyle(fontSize: 12, color: AdminUi.muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
          remove,
        ],
      );
    }
    return Row(
      children: [
        badge,
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: p.ctrl,
            onChanged: (v) => setState(() {
              p.stop.name = v;
              p.autoName = false;
              _relabel();
            }),
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Durak adı',
              filled: true,
              fillColor: AdminUi.page,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              suffixIconConstraints:
                  const BoxConstraints(minWidth: 34, minHeight: 20),
              suffixIcon: p.resolving
                  ? const Padding(
                      padding: EdgeInsets.only(right: 10),
                      child: SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
            ),
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
        PopupMenuButton<String>(
          tooltip: 'Ad önerileri',
          icon: const Icon(Icons.auto_awesome_rounded, size: 19),
          color: Colors.white,
          enabled: !p.resolving,
          onSelected: (value) => setState(() {
            p.base = value.isEmpty ? null : value;
            p.autoName = true;
            _relabel();
          }),
          itemBuilder: (_) => [
            for (final b in p.bases)
              PopupMenuItem(
                value: b,
                child: Row(
                  children: [
                    Icon(Icons.signpost_outlined,
                        size: 18, color: AdminUi.brand),
                    const SizedBox(width: 10),
                    Text(_previewName(p, b)),
                  ],
                ),
              ),
            PopupMenuItem(
              value: '',
              child: Row(
                children: [
                  const Icon(Icons.tag_rounded, size: 18, color: AdminUi.muted),
                  const SizedBox(width: 10),
                  Text(_previewName(p, null)),
                ],
              ),
            ),
          ],
        ),
        remove,
      ],
    );
  }

  Widget _footer() {
    final canSubmit = _isMulti ? _picks.isNotEmpty : true;
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AdminUi.line)),
      ),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Row(
        children: [
          if (!_isMulti)
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_singleStreet != null)
                    Text(
                      _singleStreet!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  Text(
                    '${_single.latitude.toStringAsFixed(6)}, '
                    '${_single.longitude.toStringAsFixed(6)}',
                    style: const TextStyle(
                      color: AdminUi.muted,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          TextButton(
            onPressed: _submitting ? null : () => Navigator.of(context).pop(),
            child: const Text('Vazgeç'),
          ),
          const SizedBox(width: 8),
          if (_isMulti)
            Expanded(child: _submitButton(canSubmit))
          else
            _submitButton(canSubmit),
        ],
      ),
    );
  }

  Widget _submitButton(bool canSubmit) {
    final label = !_isMulti
        ? 'Bu konumu kullan'
        : _submitting
            ? 'Adlar alınıyor…'
            : (_picks.isEmpty ? 'Ekle' : '${_picks.length} durağı ekle');
    return FilledButton.icon(
      onPressed: canSubmit && !_submitting ? _submit : null,
      icon: _submitting
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            )
          : const Icon(Icons.check_rounded, size: 20),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: AdminUi.brand,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    );
  }
}
