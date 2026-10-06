// "Yüzünden Bitmoji Oluştur" akışı.
//
// Akış: selfie → TARAMA (fotoğrafın üstünde gerçekten bulunan yüz konturları
// çizilir) → SONUÇ ("Sen → Bitmoji'n" karşılaştırması, ölçülen özellikler,
// ifade ve benzer saç önerileri) → istenirse 15 sekmeli ÖZELLEŞTİRME.
// Kullanıcı zar butonuyla rastgele kombinasyon dener ya da yeniden çeker.
//
// Sonuç PNG bayt olarak `Navigator.pop` ile döner (iptalde null).
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/permission_service.dart';
import '../models/face_avatar_config.dart';
import '../services/face_avatar_analyzer.dart';
import '../widgets/face_avatar_painter.dart';

enum _Phase { scanning, result, building }

const Color _ink = Color(0xFF111827);
const Color _muted = Color(0xFF6B7280);
const Color _line = Color(0xFFE5E7EB);
const Color _scanAccent = Color(0xFFFF6FAE);

class FaceAvatarFlowScreen extends StatefulWidget {
  final String imagePath;
  final Uint8List photoBytes;

  /// Testlerde ML Kit yerine sahte analiz vermek için.
  @visibleForTesting
  final Future<FaceAnalysis> Function(String imagePath, Uint8List photoBytes)? analyzer;

  const FaceAvatarFlowScreen({super.key, required this.imagePath, required this.photoBytes, this.analyzer});

  @override
  State<FaceAvatarFlowScreen> createState() => _FaceAvatarFlowScreenState();
}

class _FaceAvatarFlowScreenState extends State<FaceAvatarFlowScreen> {
  _Phase _phase = _Phase.scanning;
  late Uint8List _photoBytes;
  late String _imagePath;
  ui.Image? _photo;
  FaceAnalysis? _analysis;
  FaceAvatarConfig _config = FaceAvatarConfig.defaultConfig;
  FaceAvatarCategory _activeCategory = FaceAvatarCategory.hair;
  HairGroup? _hairGroup;
  bool _saving = false;
  int _runId = 0;
  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    _photoBytes = widget.photoBytes;
    _imagePath = widget.imagePath;
    _runAnalysis();
  }

  @override
  void dispose() {
    _photo?.dispose();
    super.dispose();
  }

  Future<void> _runAnalysis() async {
    final run = ++_runId;
    final stopwatch = Stopwatch()..start();
    _decodePhoto(_photoBytes, run);
    final analysis = await (widget.analyzer?.call(_imagePath, _photoBytes) ??
        FaceAvatarAnalyzer.analyze(imagePath: _imagePath, photoBytes: _photoBytes));
    // Tarama animasyonu en az bir tur dönsün.
    final remaining = 1100 - stopwatch.elapsedMilliseconds;
    if (remaining > 0) await Future.delayed(Duration(milliseconds: remaining));
    if (!mounted || run != _runId) return;
    setState(() => _analysis = analysis);
    // Bulunan konturlar fotoğrafın üstünde çizilsin, sonra sonuç.
    await Future.delayed(Duration(milliseconds: analysis.overlay.isEmpty ? 250 : 1500));
    if (!mounted || run != _runId) return;
    setState(() {
      _config = analysis.config;
      _phase = _Phase.result;
    });
  }

  Future<void> _decodePhoto(Uint8List bytes, int run) async {
    try {
      final codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      if (!mounted || run != _runId) {
        frame.image.dispose();
        return;
      }
      setState(() {
        _photo?.dispose();
        _photo = frame.image;
      });
    } catch (e) {
      debugPrint('ℹ️ Selfie önizlemesi çözülemedi: $e');
    }
  }

  Future<void> _rescan() async {
    final permissionService = PermissionService();
    if (!await permissionService.isCameraGranted()) {
      final result = await permissionService.checkAndRequestAllPermissions();
      final cameraResult = result['camera'];
      if (cameraResult != null && !cameraResult.isGranted) return;
    }
    if (!mounted) return;

    final picked = await ImagePicker().pickImage(
      source: ImageSource.camera,
      preferredCameraDevice: CameraDevice.front,
      maxWidth: 1600,
      maxHeight: 1600,
      imageQuality: 92,
    );
    if (picked == null || !mounted) return;

    final bytes = await picked.readAsBytes();
    setState(() {
      _photoBytes = bytes;
      _imagePath = picked.path;
      _analysis = null;
      _phase = _Phase.scanning;
    });
    _runAnalysis();
  }

  void _update(FaceAvatarConfig next) {
    setState(() => _config = next.copyWith(isSuggested: false));
  }

  /// Ölçülen yüz oranlarını ve fotoğraftan gelen ten/göz rengini koruyarak
  /// stilleri rastgele değiştirir (uyumsuz kombinasyonlar elenir).
  void _shuffle() {
    setState(() => _config = _config.shuffled(_random));
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    try {
      final bytes = await renderFaceAvatarToPng(_config);
      if (mounted) Navigator.of(context).pop(bytes);
    } catch (e) {
      if (mounted) {
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Avatar oluşturulamadı: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _phase == _Phase.scanning ? Colors.black : const Color(0xFFF5F7FA),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 360),
        child: switch (_phase) {
          _Phase.scanning => _ScanningView(
              key: ValueKey('scan$_runId'),
              photoBytes: _photoBytes,
              photo: _photo,
              analysis: _analysis,
              onClose: () => Navigator.of(context).pop(null),
            ),
          _Phase.result => _buildResult(key: const ValueKey('result')),
          _Phase.building => _buildEditor(key: const ValueKey('edit')),
        },
      ),
    );
  }

  // ------------------------------------------------------------------ sonuç
  Widget _buildResult({required Key key}) {
    final primary = Theme.of(context).colorScheme.primary;
    final a = _analysis;
    final found = a?.faceFound ?? false;
    return SafeArea(
      key: key,
      child: Column(
        children: [
          Row(
            children: [
              IconButton(onPressed: () => Navigator.of(context).pop(null), icon: const Icon(Icons.close)),
              const Spacer(),
              IconButton(tooltip: 'Rastgele', onPressed: _shuffle, icon: const Icon(Icons.casino_outlined)),
            ],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              children: [
                _ResultHero(config: _config, photo: _photo, faceBox: a?.faceBox, accent: primary),
                const SizedBox(height: 18),
                Text(
                  found ? "Bitmoji'n hazır" : 'Varsayılan avatar',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w800, color: _ink),
                ),
                const SizedBox(height: 6),
                Text(
                  found
                      ? 'Yüz hatların, ten, saç ve göz rengin fotoğrafından ölçülerek çizildi.'
                      : (a?.hint ?? 'Yüz ölçülemedi.'),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: _muted, height: 1.35),
                ),
                if (found && a?.hint != null) ...[
                  const SizedBox(height: 12),
                  _HintBanner(text: a!.hint!),
                ],
                if (found && a!.traits.isNotEmpty) ...[
                  const SizedBox(height: 16),
                  _TraitWrap(traits: a.traits),
                ],
                const SizedBox(height: 18),
                _sectionTitle('İfade'),
                const SizedBox(height: 8),
                _expressionRow(),
                if (found && a!.hairCandidates.length > 1) ...[
                  const SizedBox(height: 18),
                  _sectionTitle(kHairStyles[a.hairCandidates.first].covered ? 'Diğer örtüler' : 'Benzer saç modelleri'),
                  const SizedBox(height: 8),
                  _hairSuggestions(a.hairCandidates),
                ],
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: _saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Text('Bu Avatarı Kullan', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() => _phase = _Phase.building),
                        icon: const Icon(Icons.tune, size: 18),
                        label: const Text('Özelleştir'),
                        style: _secondaryButtonStyle,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _rescan,
                        icon: const Icon(Icons.camera_alt_outlined, size: 18),
                        label: const Text('Yeniden Çek'),
                        style: _secondaryButtonStyle,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(String text) => Text(
        text,
        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: _ink),
      );

  static const _expressions = <(String, double)>[('Doğal', 0.30), ('Gülümseme', 0.62), ('Kahkaha', 0.96)];

  Widget _expressionRow() {
    final primary = Theme.of(context).colorScheme.primary;
    final smile = _config.metrics.smile;
    var current = 0;
    for (var i = 0; i < _expressions.length; i++) {
      if ((smile - _expressions[i].$2).abs() < (smile - _expressions[current].$2).abs()) current = i;
    }
    return Row(
      children: [
        for (var i = 0; i < _expressions.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          Expanded(
            child: GestureDetector(
              onTap: () => _update(_config.copyWith(metrics: _config.metrics.withSmile(_expressions[i].$2))),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 6),
                decoration: BoxDecoration(
                  color: i == current ? primary.withValues(alpha: 0.10) : Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: i == current ? primary : _line, width: i == current ? 1.6 : 1),
                ),
                child: Column(
                  children: [
                    ClipOval(
                      child: CustomPaint(
                        painter: FaceAvatarPainter(
                          _config.copyWith(metrics: _config.metrics.withSmile(_expressions[i].$2)),
                          detailed: false,
                          focus: FaceAvatarFocus.lips,
                          zoom: 2.2,
                        ),
                        size: const Size.square(44),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _expressions[i].$1,
                      style: TextStyle(fontSize: 11.5, fontWeight: i == current ? FontWeight.w700 : FontWeight.w500, color: i == current ? _ink : _muted),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _hairSuggestions(List<int> candidates) {
    final primary = Theme.of(context).colorScheme.primary;
    final items = candidates.take(6).toList();
    return SizedBox(
      height: 96,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final index = items[i];
          final selected = _config.hair == index;
          return GestureDetector(
            onTap: () => _update(_config.copyWith(hair: index)),
            child: SizedBox(
              width: 70,
              child: Column(
                children: [
                  Container(
                    width: 66,
                    height: 66,
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(color: selected ? primary : _line, width: selected ? 2.5 : 1),
                    ),
                    child: ClipOval(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: FaceAvatarPainter(_config.copyWith(hair: index), detailed: false, focus: FaceAvatarFocus.hair, zoom: 1.12),
                          size: const Size.square(61),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    kHairStyles[index].label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 10.5, fontWeight: selected ? FontWeight.bold : FontWeight.normal, color: selected ? _ink : const Color(0xFF9CA3AF)),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  ButtonStyle get _secondaryButtonStyle => OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFF374151),
        padding: const EdgeInsets.symmetric(vertical: 13),
        side: const BorderSide(color: Color(0xFFD1D5DB)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      );

  // -------------------------------------------------------------- düzenleme
  Widget _buildEditor({required Key key}) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return SafeArea(
      key: key,
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                onPressed: () => setState(() => _phase = _Phase.result),
                icon: const Icon(Icons.arrow_back_ios_new, size: 20),
              ),
              const Expanded(
                child: Text(
                  "Bitmoji'ni Özelleştir",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                tooltip: 'Rastgele',
                onPressed: _shuffle,
                icon: const Icon(Icons.casino_outlined, size: 22),
              ),
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: TextButton(
                  onPressed: _saving ? null : _save,
                  style: TextButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                        )
                      : const Text('Kaydet', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
          FaceAvatarPreview(config: _config, size: 168),
          const SizedBox(height: 12),
          _buildCategoryTabs(),
          const SizedBox(height: 8),
          Expanded(child: _buildOptionsForCategory()),
        ],
      ),
    );
  }

  static const _categoryItems = <(FaceAvatarCategory, String, IconData)>[
    (FaceAvatarCategory.hair, 'Saç', Icons.content_cut),
    (FaceAvatarCategory.faceShape, 'Yüz', Icons.face_outlined),
    (FaceAvatarCategory.skin, 'Ten', Icons.palette_outlined),
    (FaceAvatarCategory.brow, 'Kaş', Icons.horizontal_rule),
    (FaceAvatarCategory.eye, 'Göz', Icons.visibility_outlined),
    (FaceAvatarCategory.lash, 'Makyaj', Icons.auto_awesome_outlined),
    (FaceAvatarCategory.nose, 'Burun', Icons.air),
    (FaceAvatarCategory.lips, 'Dudak', Icons.mood_outlined),
    (FaceAvatarCategory.beard, 'Sakal', Icons.face_retouching_natural),
    (FaceAvatarCategory.glasses, 'Gözlük', Icons.remove_red_eye_outlined),
    (FaceAvatarCategory.headwear, 'Başlık', Icons.checkroom_outlined),
    (FaceAvatarCategory.jewelry, 'Takı', Icons.diamond_outlined),
    (FaceAvatarCategory.detail, 'Detay', Icons.blur_on),
    (FaceAvatarCategory.clothing, 'Kıyafet', Icons.dry_cleaning_outlined),
    (FaceAvatarCategory.background, 'Arka Plan', Icons.wallpaper_outlined),
  ];

  Widget _buildCategoryTabs() {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: _categoryItems.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (category, label, icon) = _categoryItems[index];
          final selected = category == _activeCategory;
          return InkWell(
            onTap: () => setState(() => _activeCategory = category),
            borderRadius: BorderRadius.circular(16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: selected ? primaryColor : Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: selected ? primaryColor : _line),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 17, color: selected ? Colors.white : _muted),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                      color: selected ? Colors.white : _muted,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  /// Paletin başına fotoğraftan ölçülen rengi ekler (paletin içinde değilse).
  List<Color> _withPhoto(List<Color> palette, Color? photo) {
    if (photo == null || palette.any((c) => c.toARGB32() == photo.toARGB32())) return palette;
    return [photo, ...palette];
  }

  /// Seçenek alanı: üstte renk/filtre satırları, altında lazy oluşturulan ızgara.
  Widget _buildOptionsForCategory() {
    final List<Widget> header = [];
    Widget? grid;

    switch (_activeCategory) {
      case FaceAvatarCategory.faceShape:
        grid = _grid(
          indices: List.generate(kFaceShapes.length, (i) => i),
          labelAt: (i) => kFaceShapes[i].label,
          configAt: (i) => _config.copyWith(faceShape: i),
          selectedIndex: _config.faceShape,
          onPick: (i) => _update(_config.copyWith(faceShape: i)),
        );
        break;

      case FaceAvatarCategory.skin:
        header.addAll([
          _colorRow(
            label: 'Ten Tonu',
            colors: _withPhoto(kSkinTones, _analysis?.photoSkin),
            current: _config.skinTone,
            photo: _analysis?.photoSkin,
            onPick: (c) => _update(_config.copyWith(skinTone: c)),
          ),
          const SizedBox(height: 16),
          _chipRow(
            label: 'Yaş görünümü',
            options: const ['Genç', 'Orta yaş', 'Olgun', 'Yaşlı'],
            selected: _config.age,
            onPick: (i) => _update(_config.copyWith(age: i)),
          ),
        ]);
        break;

      case FaceAvatarCategory.hair:
        header.addAll([
          _hairGroupChips(),
          const SizedBox(height: 12),
          _colorRow(
            label: 'Saç Rengi',
            colors: _withPhoto(kHairColors, _analysis?.photoHair),
            current: _config.hairColor,
            photo: _analysis?.photoHair,
            onPick: (c) => _update(_config.copyWith(hairColor: c)),
          ),
          const SizedBox(height: 14),
        ]);
        final indices = <int>[
          for (var i = 0; i < kHairStyles.length; i++)
            if (_hairGroup == null || kHairStyles[i].group == _hairGroup) i,
        ];
        grid = _grid(
          indices: indices,
          labelAt: (i) => kHairStyles[i].label,
          configAt: (i) => _config.copyWith(hair: i),
          selectedIndex: _config.hair,
          onPick: (i) => _update(_config.copyWith(hair: i)),
          zoom: 1.12,
          focus: FaceAvatarFocus.hair,
        );
        break;

      case FaceAvatarCategory.brow:
        grid = _grid(
          indices: List.generate(kBrowStyles.length, (i) => i),
          labelAt: (i) => kBrowStyles[i].label,
          configAt: (i) => _config.copyWith(brow: i),
          selectedIndex: _config.brow,
          onPick: (i) => _update(_config.copyWith(brow: i)),
          zoom: 2.3,
          focus: FaceAvatarFocus.brows,
        );
        break;

      case FaceAvatarCategory.eye:
        header.addAll([
          _colorRow(
            label: 'Göz Rengi',
            colors: kEyeColors,
            current: _config.eyeColor,
            onPick: (c) => _update(_config.copyWith(eyeColor: c)),
          ),
          const SizedBox(height: 14),
        ]);
        grid = _grid(
          indices: List.generate(kEyeStyles.length, (i) => i),
          labelAt: (i) => kEyeStyles[i].label,
          configAt: (i) => _config.copyWith(eye: i),
          selectedIndex: _config.eye,
          onPick: (i) => _update(_config.copyWith(eye: i)),
          zoom: 2.3,
          focus: FaceAvatarFocus.eyes,
        );
        break;

      case FaceAvatarCategory.lash:
        grid = _grid(
          indices: List.generate(kLashStyles.length, (i) => i),
          labelAt: (i) => kLashStyles[i].label,
          configAt: (i) => _config.copyWith(lash: i),
          selectedIndex: _config.lash,
          onPick: (i) => _update(_config.copyWith(lash: i)),
          zoom: 2.3,
          focus: FaceAvatarFocus.eyes,
        );
        break;

      case FaceAvatarCategory.nose:
        grid = _grid(
          indices: List.generate(kNoseStyles.length, (i) => i),
          labelAt: (i) => kNoseStyles[i].label,
          configAt: (i) => _config.copyWith(nose: i),
          selectedIndex: _config.nose,
          onPick: (i) => _update(_config.copyWith(nose: i)),
          zoom: 2.4,
          focus: FaceAvatarFocus.nose,
        );
        break;

      case FaceAvatarCategory.lips:
        header.addAll([
          _colorRow(
            label: 'Ruj Rengi',
            colors: kLipColors.map((c) => c.a == 0 ? const Color(0xFFD9A08F) : c).toList(),
            current: kLipColors[_config.lipColor].a == 0 ? const Color(0xFFD9A08F) : kLipColors[_config.lipColor],
            onPick: (c) {
              final idx = kLipColors.indexWhere((k) => k.toARGB32() == c.toARGB32());
              _update(_config.copyWith(lipColor: idx < 0 ? 0 : idx));
            },
          ),
          const SizedBox(height: 14),
        ]);
        grid = _grid(
          indices: List.generate(kLipStyles.length, (i) => i),
          labelAt: (i) => kLipStyles[i].label,
          configAt: (i) => _config.copyWith(lips: i),
          selectedIndex: _config.lips,
          onPick: (i) => _update(_config.copyWith(lips: i)),
          zoom: 2.5,
          focus: FaceAvatarFocus.lips,
        );
        break;

      case FaceAvatarCategory.beard:
        grid = _grid(
          indices: List.generate(kBeardStyles.length, (i) => i),
          labelAt: (i) => kBeardStyles[i].label,
          configAt: (i) => _config.copyWith(beard: i),
          selectedIndex: _config.beard,
          onPick: (i) => _update(_config.copyWith(beard: i)),
          zoom: 1.7,
          focus: FaceAvatarFocus.beard,
        );
        break;

      case FaceAvatarCategory.glasses:
        grid = _grid(
          indices: List.generate(kGlassesStyles.length, (i) => i),
          labelAt: (i) => kGlassesStyles[i].label,
          configAt: (i) => _config.copyWith(glasses: i),
          selectedIndex: _config.glasses,
          onPick: (i) => _update(_config.copyWith(glasses: i)),
          zoom: 2.0,
          focus: FaceAvatarFocus.glasses,
        );
        break;

      case FaceAvatarCategory.headwear:
        grid = _grid(
          indices: List.generate(kHeadwearStyles.length, (i) => i),
          labelAt: (i) => kHeadwearStyles[i].label,
          configAt: (i) => _config.copyWith(headwear: i),
          selectedIndex: _config.headwear,
          onPick: (i) => _update(_config.copyWith(headwear: i)),
          zoom: 1.4,
          focus: FaceAvatarFocus.headwear,
        );
        break;

      case FaceAvatarCategory.jewelry:
        grid = _grid(
          indices: List.generate(kJewelryStyles.length, (i) => i),
          labelAt: (i) => kJewelryStyles[i].label,
          configAt: (i) => _config.copyWith(jewelry: i),
          selectedIndex: _config.jewelry,
          onPick: (i) => _update(_config.copyWith(jewelry: i)),
          zoom: 1.5,
          focus: FaceAvatarFocus.jewelry,
        );
        break;

      case FaceAvatarCategory.detail:
        header.addAll([
          _chipRow(
            label: 'Yaş görünümü',
            options: const ['Genç', 'Orta yaş', 'Olgun', 'Yaşlı'],
            selected: _config.age,
            onPick: (i) => _update(_config.copyWith(age: i)),
          ),
          const SizedBox(height: 14),
        ]);
        grid = _grid(
          indices: List.generate(kDetailStyles.length, (i) => i),
          labelAt: (i) => kDetailStyles[i].label,
          configAt: (i) => _config.copyWith(detail: i),
          selectedIndex: _config.detail,
          onPick: (i) => _update(_config.copyWith(detail: i)),
          zoom: 1.7,
          focus: FaceAvatarFocus.detail,
        );
        break;

      case FaceAvatarCategory.clothing:
        header.addAll([
          _colorRow(
            label: 'Kıyafet / Başörtüsü Rengi',
            colors: kClothingColors,
            current: _config.clothingColor,
            onPick: (c) => _update(_config.copyWith(clothingColor: c)),
          ),
          const SizedBox(height: 14),
        ]);
        grid = _grid(
          indices: List.generate(kClothingStyles.length, (i) => i),
          labelAt: (i) => kClothingStyles[i].label,
          configAt: (i) => _config.copyWith(clothing: i),
          selectedIndex: _config.clothing,
          onPick: (i) => _update(_config.copyWith(clothing: i)),
          zoom: 1.3,
          focus: FaceAvatarFocus.clothing,
        );
        break;

      case FaceAvatarCategory.background:
        grid = _grid(
          indices: List.generate(kBackgrounds.length, (i) => i),
          labelAt: (i) => kBackgrounds[i].label,
          configAt: (i) => _config.copyWith(background: i),
          selectedIndex: _config.background,
          onPick: (i) => _update(_config.copyWith(background: i)),
        );
        break;
    }

    return CustomScrollView(
      key: ValueKey(_activeCategory),
      slivers: [
        if (header.isNotEmpty)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
            sliver: SliverToBoxAdapter(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: header),
            ),
          ),
        if (grid != null) grid,
        const SliverToBoxAdapter(child: SizedBox(height: 28)),
      ],
    );
  }

  Widget _hairGroupChips() {
    final primaryColor = Theme.of(context).colorScheme.primary;
    final groups = <HairGroup?>[null, ...HairGroup.values];
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: groups.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final g = groups[i];
          final selected = g == _hairGroup;
          final label = g == null ? 'Hepsi (${kHairStyles.length})' : kHairGroupLabels[g]!;
          return ChoiceChip(
            label: Text(label, style: TextStyle(fontSize: 12, color: selected ? Colors.white : const Color(0xFF374151))),
            selected: selected,
            showCheckmark: false,
            selectedColor: primaryColor,
            backgroundColor: Colors.white,
            side: BorderSide(color: selected ? primaryColor : _line),
            onSelected: (_) => setState(() => _hairGroup = g),
          );
        },
      ),
    );
  }

  Widget _chipRow({
    required String label,
    required List<String> options,
    required int selected,
    required void Function(int) onPick,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _muted)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (var i = 0; i < options.length; i++)
              ChoiceChip(
                label: Text(options[i], style: TextStyle(fontSize: 12, color: i == selected ? Colors.white : const Color(0xFF374151))),
                selected: i == selected,
                showCheckmark: false,
                selectedColor: primaryColor,
                backgroundColor: Colors.white,
                side: BorderSide(color: i == selected ? primaryColor : _line),
                onSelected: (_) => onPick(i),
              ),
          ],
        ),
      ],
    );
  }

  /// Her seçenek, o seçenek uygulanmış küçük bir avatar önizlemesi olarak
  /// gösterilir — kullanıcı sonucu tahmin etmek zorunda kalmaz. Izgara lazy
  /// oluşturulur; yüzlerce seçenek olsa da yalnız görünenler çizilir.
  Widget _grid({
    required List<int> indices,
    required String Function(int) labelAt,
    required FaceAvatarConfig Function(int) configAt,
    required int selectedIndex,
    required void Function(int) onPick,
    double zoom = 1.0,
    Offset? focus,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 88,
          mainAxisExtent: 98,
          crossAxisSpacing: 6,
          mainAxisSpacing: 4,
        ),
        delegate: SliverChildBuilderDelegate(
          childCount: indices.length,
          (context, k) {
            final index = indices[k];
            final selected = index == selectedIndex;
            return GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onPick(index),
              child: Column(
                children: [
                  Container(
                    width: 68,
                    height: 68,
                    padding: const EdgeInsets.all(2.5),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.white,
                      border: Border.all(
                        color: selected ? primaryColor : _line,
                        width: selected ? 2.5 : 1,
                      ),
                    ),
                    child: ClipOval(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: FaceAvatarPainter(configAt(index), detailed: false, focus: focus, zoom: zoom),
                          size: const Size.square(63),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 5),
                  SizedBox(
                    width: 80,
                    child: Text(
                      labelAt(index),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                        color: selected ? _ink : const Color(0xFF9CA3AF),
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _colorRow({
    required String label,
    required List<Color> colors,
    required Color current,
    required void Function(Color) onPick,
    Color? photo,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _muted)),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: colors.map((c) {
            final selected = c.toARGB32() == current.toARGB32();
            final fromPhoto = photo != null && c.toARGB32() == photo.toARGB32();
            return Tooltip(
              message: fromPhoto ? 'Fotoğraftan' : '',
              child: GestureDetector(
                onTap: () => onPick(c),
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: c,
                    border: Border.all(color: selected ? primaryColor : Colors.white, width: selected ? 3 : 2),
                    boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 3)],
                  ),
                  child: fromPhoto
                      ? Icon(Icons.photo_camera, size: 14, color: c.computeLuminance() > 0.4 ? Colors.black54 : Colors.white70)
                      : null,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

// ============================================================ sonuç parçaları
/// Büyük avatar + köşede selfie'den kırpılmış yüz ("Sen → Bitmoji'n").
class _ResultHero extends StatelessWidget {
  final FaceAvatarConfig config;
  final ui.Image? photo;
  final Rect? faceBox;
  final Color accent;
  const _ResultHero({required this.config, required this.photo, required this.faceBox, required this.accent});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 262,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Container(
            width: 262,
            height: 262,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(colors: [accent.withValues(alpha: 0.18), accent.withValues(alpha: 0.0)]),
            ),
          ),
          FaceAvatarPreview(config: config, size: 228),
          if (photo != null && faceBox != null)
            Positioned(
              left: 0,
              right: 0,
              bottom: 4,
              child: Align(
                alignment: const Alignment(-0.78, 1),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 70,
                      height: 70,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 3),
                        boxShadow: const [BoxShadow(color: Color(0x33000000), blurRadius: 8, offset: Offset(0, 3))],
                      ),
                      child: ClipOval(child: CustomPaint(painter: _FaceCropPainter(photo!, faceBox!))),
                    ),
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(color: _ink, borderRadius: BorderRadius.circular(10)),
                      child: const Text('Sen', style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _FaceCropPainter extends CustomPainter {
  final ui.Image image;
  final Rect faceBox;
  _FaceCropPainter(this.image, this.faceBox);

  @override
  void paint(Canvas canvas, Size size) {
    final w = image.width.toDouble(), h = image.height.toDouble();
    final c = Offset(faceBox.center.dx * w, faceBox.center.dy * h - faceBox.height * h * 0.06);
    final side = math.max(faceBox.width * w, faceBox.height * h) * 1.35;
    final src = Rect.fromCenter(center: c, width: side, height: side);
    canvas.drawImageRect(image, src, Offset.zero & size, Paint()..filterQuality = FilterQuality.medium);
  }

  @override
  bool shouldRepaint(covariant _FaceCropPainter old) => old.image != image || old.faceBox != faceBox;
}

class _HintBanner extends StatelessWidget {
  final String text;
  const _HintBanner({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7E6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCD9A0)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.lightbulb_outline, size: 18, color: Color(0xFFB7791F)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, color: Color(0xFF7A4B0B), height: 1.3))),
        ],
      ),
    );
  }
}

class _TraitWrap extends StatelessWidget {
  final List<FaceTrait> traits;
  const _TraitWrap({required this.traits});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final t in traits)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: _line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (t.swatch != null) ...[
                  Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(color: t.swatch, shape: BoxShape.circle, border: Border.all(color: Colors.black12)),
                  ),
                  const SizedBox(width: 6),
                ],
                Text('${t.label}: ', style: const TextStyle(fontSize: 12, color: _muted)),
                Text(t.value, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: _ink)),
              ],
            ),
          ),
      ],
    );
  }
}

// =================================================================== tarama
class _ScanningView extends StatefulWidget {
  final Uint8List photoBytes;
  final ui.Image? photo;
  final FaceAnalysis? analysis;
  final VoidCallback onClose;
  const _ScanningView({super.key, required this.photoBytes, required this.photo, required this.analysis, required this.onClose});

  @override
  State<_ScanningView> createState() => _ScanningViewState();
}

class _ScanningViewState extends State<_ScanningView> with TickerProviderStateMixin {
  late final AnimationController _scan;
  late final AnimationController _reveal;

  static const _steps = ['Yüz hatları', 'Ten ve saç rengi', 'Saç modeli', 'Göz, kaş ve dudak', 'Sakal ve gözlük'];

  @override
  void initState() {
    super.initState();
    _scan = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600))..repeat();
    _reveal = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200));
    if (widget.analysis != null) _reveal.forward();
  }

  @override
  void didUpdateWidget(covariant _ScanningView old) {
    super.didUpdateWidget(old);
    if (old.analysis == null && widget.analysis != null) _reveal.forward(from: 0);
  }

  @override
  void dispose() {
    _scan.dispose();
    _reveal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.photo;
    final overlay = widget.analysis?.overlay ?? const <List<Offset>>[];
    return Stack(
      fit: StackFit.expand,
      children: [
        if (photo != null)
          FittedBox(
            fit: BoxFit.cover,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: photo.width.toDouble(),
              height: photo.height.toDouble(),
              child: AnimatedBuilder(
                animation: Listenable.merge([_scan, _reveal]),
                builder: (context, _) => CustomPaint(
                  painter: _ScanPainter(photo, overlay, _reveal.value, _scan.value, widget.analysis == null),
                ),
              ),
            ),
          )
        else
          Image.memory(widget.photoBytes, fit: BoxFit.cover, gaplessPlayback: true),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0x99000000), Color(0x22000000), Color(0x33000000), Color(0xDD000000)],
              stops: [0.0, 0.25, 0.6, 1.0],
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 4,
          left: 4,
          child: IconButton(onPressed: widget.onClose, icon: const Icon(Icons.close, color: Colors.white)),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 16,
          left: 0,
          right: 0,
          child: const Text(
            "Yüzünden Bitmoji Oluştur",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ),
        Positioned(
          left: 28,
          right: 28,
          bottom: MediaQuery.paddingOf(context).bottom + 36,
          child: AnimatedBuilder(
            animation: Listenable.merge([_scan, _reveal]),
            builder: (context, _) {
              final done = widget.analysis != null;
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    done ? (widget.analysis!.faceFound ? 'Yüzün ölçüldü' : 'Yüz bulunamadı') : 'Yüz hatların ölçülüyor',
                    style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 14),
                  for (var i = 0; i < _steps.length; i++)
                    _StepRow(
                      label: _steps[i],
                      state: done
                          ? (_reveal.value * (_steps.length + 1) > i + 1 ? 2 : 1)
                          : ((_scan.value * _steps.length).floor() == i ? 1 : 0),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class _StepRow extends StatelessWidget {
  final String label;

  /// 0 bekliyor, 1 ölçülüyor, 2 tamam.
  final int state;
  const _StepRow({required this.label, required this.state});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 18,
            child: state == 2
                ? const Icon(Icons.check_circle, size: 16, color: Color(0xFF4ADE80))
                : Icon(Icons.radio_button_unchecked, size: 14, color: Colors.white.withValues(alpha: state == 1 ? 0.95 : 0.4)),
          ),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(color: Colors.white.withValues(alpha: state == 0 ? 0.55 : 0.95), fontSize: 12.5, fontWeight: state == 2 ? FontWeight.w600 : FontWeight.w400),
          ),
        ],
      ),
    );
  }
}

/// Fotoğraf + tarama çizgisi + bulunan kontur noktaları (yavaşça belirir).
class _ScanPainter extends CustomPainter {
  final ui.Image photo;
  final List<List<Offset>> overlay;
  final double reveal;
  final double scan;
  final bool scanning;
  _ScanPainter(this.photo, this.overlay, this.reveal, this.scan, this.scanning);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawImage(photo, Offset.zero, Paint()..filterQuality = FilterQuality.medium);
    final unit = size.shortestSide / 360;

    if (scanning || overlay.isEmpty) {
      // Yukarıdan aşağı süpüren ışık çizgisi.
      final y = size.height * (0.12 + 0.76 * scan);
      final band = Rect.fromLTWH(0, y - 40 * unit, size.width, 80 * unit);
      canvas.drawRect(
        band,
        Paint()
          ..shader = ui.Gradient.linear(
            band.topCenter,
            band.bottomCenter,
            [_scanAccent.withValues(alpha: 0.0), _scanAccent.withValues(alpha: 0.28), _scanAccent.withValues(alpha: 0.0)],
            const [0.0, 0.5, 1.0],
          ),
      );
      canvas.drawLine(Offset(0, y), Offset(size.width, y), Paint()
        ..color = _scanAccent.withValues(alpha: 0.85)
        ..strokeWidth = 2 * unit);
      return;
    }

    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6 * unit
      ..strokeJoin = StrokeJoin.round
      ..color = Colors.white.withValues(alpha: 0.85);
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5 * unit
      ..color = _scanAccent.withValues(alpha: 0.35)
      ..maskFilter = MaskFilter.blur(BlurStyle.normal, 3 * unit);
    final dot = Paint()..color = _scanAccent;

    for (var k = 0; k < overlay.length; k++) {
      final pts = overlay[k].map((p) => Offset(p.dx * size.width, p.dy * size.height)).toList();
      if (pts.length < 2) continue;
      // Konturlar sırayla belirir.
      final local = ((reveal * (overlay.length + 2) - k) / 2).clamp(0.0, 1.0);
      if (local <= 0) continue;
      final closed = k == 0 || k == 3 || k == 4;
      final n = (pts.length * local).ceil().clamp(1, pts.length);
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (final p in pts.sublist(1, n)) {
        path.lineTo(p.dx, p.dy);
      }
      if (closed && local >= 1) path.close();
      canvas.drawPath(path, glow);
      canvas.drawPath(path, line);
      for (final p in pts.sublist(0, n)) {
        canvas.drawCircle(p, 2.2 * unit, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ScanPainter old) =>
      old.photo != photo || old.overlay != overlay || old.reveal != reveal || old.scan != scan || old.scanning != scanning;
}
