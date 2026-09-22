// "Yüzünden Avatar Oluştur" akışı.
//
// Akış: selfie → cihazda ölçüm → AVATAR HAZIR (sonuç ekranı). Kullanıcı
// isterse "Kullan" deyip çıkar; beğenmezse Saç/Yüz/Ten/Kaş/Göz/Makyaj/Burun/
// Dudak/Sakal/Gözlük/Başlık/Takı/Detay/Kıyafet/Arka Plan sekmelerinden değiştirir,
// zar butonuyla rastgele kombinasyon dener ya da yeniden çeker.
//
// Sonuç PNG bayt olarak `Navigator.pop` ile döner (iptalde null).
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/services/permission_service.dart';
import '../models/face_avatar_config.dart';
import '../services/face_avatar_analyzer.dart';
import '../widgets/face_avatar_painter.dart';

enum _Phase { scanning, result, building }

class FaceAvatarFlowScreen extends StatefulWidget {
  final String imagePath;
  final Uint8List photoBytes;

  const FaceAvatarFlowScreen({super.key, required this.imagePath, required this.photoBytes});

  @override
  State<FaceAvatarFlowScreen> createState() => _FaceAvatarFlowScreenState();
}

class _FaceAvatarFlowScreenState extends State<FaceAvatarFlowScreen> {
  _Phase _phase = _Phase.scanning;
  late Uint8List _photoBytes;
  late String _imagePath;
  FaceAvatarConfig _config = FaceAvatarConfig.defaultConfig;
  FaceAvatarCategory _activeCategory = FaceAvatarCategory.hair;
  HairGroup? _hairGroup;
  bool _saving = false;
  final _random = math.Random();

  @override
  void initState() {
    super.initState();
    _photoBytes = widget.photoBytes;
    _imagePath = widget.imagePath;
    _runAnalysis();
  }

  Future<void> _runAnalysis() async {
    final stopwatch = Stopwatch()..start();
    final config = await FaceAvatarAnalyzer.analyze(imagePath: _imagePath, photoBytes: _photoBytes);
    final remaining = 1100 - stopwatch.elapsedMilliseconds;
    if (remaining > 0) await Future.delayed(Duration(milliseconds: remaining));
    if (!mounted) return;
    setState(() {
      _config = config;
      _phase = _Phase.result;
    });
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
        duration: const Duration(milliseconds: 320),
        child: switch (_phase) {
          _Phase.scanning => _ScanningView(key: const ValueKey('scan'), photoBytes: _photoBytes),
          _Phase.result => _buildResult(key: const ValueKey('result')),
          _Phase.building => _buildEditor(key: const ValueKey('edit')),
        },
      ),
    );
  }

  // ------------------------------------------------------------------ sonuç
  Widget _buildResult({required Key key}) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return SafeArea(
      key: key,
      child: Column(
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              onPressed: () => Navigator.of(context).pop(null),
              icon: const Icon(Icons.close),
            ),
          ),
          const Spacer(),
          Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 262,
                height: 262,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [primaryColor.withValues(alpha: 0.16), primaryColor.withValues(alpha: 0.0)],
                  ),
                ),
              ),
              FaceAvatarPreview(config: _config, size: 224),
            ],
          ),
          const SizedBox(height: 22),
          const Text('Avatarın hazır', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              'Yüz şeklin ${_config.faceShapeSpec.label.toLowerCase()}, '
              'gözlerin ${_config.eyeSpec.label.toLowerCase()}, '
              'kaşların ${_config.browSpec.label.toLowerCase()} olarak ölçüldü.',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13, color: Color(0xFF6B7280), height: 1.35),
            ),
          ),
          const Spacer(flex: 2),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _saving ? null : _save,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: _saving
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Text(
                            'Bu Avatarı Kullan',
                            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                          ),
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

  ButtonStyle get _secondaryButtonStyle => OutlinedButton.styleFrom(
    foregroundColor: const Color(0xFF374151),
    padding: const EdgeInsets.symmetric(vertical: 13),
    side: const BorderSide(color: Color(0xFFD1D5DB)),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                  'Avatarını Özelleştir',
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
                border: Border.all(color: selected ? primaryColor : const Color(0xFFE5E7EB)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 17, color: selected ? Colors.white : const Color(0xFF6B7280)),
                  const SizedBox(height: 3),
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w600,
                      color: selected ? Colors.white : const Color(0xFF6B7280),
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
            colors: kSkinTones,
            current: _config.skinTone,
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
            colors: kHairColors,
            current: _config.hairColor,
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
          zoom: 1.15,
          focus: const Offset(100, 84),
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
          focus: const Offset(100, 86),
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
          focus: const Offset(100, 90),
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
          focus: const Offset(100, 90),
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
          focus: const Offset(100, 106),
        );
        break;

      case FaceAvatarCategory.lips:
        header.addAll([
          _colorRow(
            label: 'Ruj Rengi',
            colors: kLipColors.map((c) => c.a == 0 ? const Color(0xFFD9A08F) : c).toList(),
            current: kLipColors[_config.lipColor].a == 0
                ? const Color(0xFFD9A08F)
                : kLipColors[_config.lipColor],
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
          focus: const Offset(100, 122),
        );
        break;

      case FaceAvatarCategory.beard:
        grid = _grid(
          indices: List.generate(kBeardStyles.length, (i) => i),
          labelAt: (i) => kBeardStyles[i].label,
          configAt: (i) => _config.copyWith(beard: i),
          selectedIndex: _config.beard,
          onPick: (i) => _update(_config.copyWith(beard: i)),
          zoom: 1.8,
          focus: const Offset(100, 118),
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
          focus: const Offset(100, 92),
        );
        break;

      case FaceAvatarCategory.headwear:
        grid = _grid(
          indices: List.generate(kHeadwearStyles.length, (i) => i),
          labelAt: (i) => kHeadwearStyles[i].label,
          configAt: (i) => _config.copyWith(headwear: i),
          selectedIndex: _config.headwear,
          onPick: (i) => _update(_config.copyWith(headwear: i)),
          zoom: 1.45,
          focus: const Offset(100, 62),
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
          focus: const Offset(100, 118),
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
          focus: const Offset(100, 104),
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
          focus: const Offset(100, 138),
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
            side: BorderSide(color: selected ? primaryColor : const Color(0xFFE5E7EB)),
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
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B7280)),
        ),
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
                side: BorderSide(color: i == selected ? primaryColor : const Color(0xFFE5E7EB)),
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
                        color: selected ? primaryColor : const Color(0xFFE5E7EB),
                        width: selected ? 2.5 : 1,
                      ),
                    ),
                    child: ClipOval(
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: FaceAvatarPainter(
                            configAt(index),
                            detailed: false,
                            focus: focus,
                            zoom: zoom,
                          ),
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
                        color: selected ? const Color(0xFF111827) : const Color(0xFF9CA3AF),
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
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B7280)),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: colors.map((c) {
            final selected = c.toARGB32() == current.toARGB32();
            return GestureDetector(
              onTap: () => onPick(c),
              child: Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: c,
                  border: Border.all(
                    color: selected ? primaryColor : Colors.white,
                    width: selected ? 3 : 2,
                  ),
                  boxShadow: const [BoxShadow(color: Color(0x1F000000), blurRadius: 3)],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

class _ScanningView extends StatefulWidget {
  final Uint8List photoBytes;
  const _ScanningView({super.key, required this.photoBytes});

  @override
  State<_ScanningView> createState() => _ScanningViewState();
}

class _ScanningViewState extends State<_ScanningView> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1500))
      ..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        Image.memory(widget.photoBytes, fit: BoxFit.cover),
        Container(color: Colors.black.withValues(alpha: 0.5)),
        Center(
          child: FadeTransition(
            opacity: Tween(begin: 0.30, end: 0.95).animate(_controller),
            child: Container(
              width: 216,
              height: 280,
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFFFF6FAE), width: 2),
                borderRadius: BorderRadius.circular(140),
              ),
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.paddingOf(context).top + 18,
          left: 0,
          right: 0,
          child: const Text(
            'Yüzünden Avatar Oluştur',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
          ),
        ),
        Positioned(
          left: 40,
          right: 40,
          bottom: 90,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Yüz hatların ölçülüyor',
                style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: const LinearProgressIndicator(
                  minHeight: 6,
                  backgroundColor: Color(0x2EFFFFFF),
                  valueColor: AlwaysStoppedAnimation(Color(0xFFD91A73)),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Yüz şekli, göz, kaş, burun, dudak ve saç ölçülüyor',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white.withValues(alpha: 0.7), fontSize: 11.5),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
