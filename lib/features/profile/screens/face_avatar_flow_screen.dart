// "Yüzünden Avatar Oluştur" akışı.
//
// Akış: selfie → cihazda ölçüm → AVATAR HAZIR (sonuç ekranı). Kullanıcı
// isterse "Kullan" deyip çıkar; beğenmezse Yüz/Ten/Saç/Kaş/Göz/Kirpik/
// Sakal/Gözlük sekmelerinden değiştirir, zar butonuyla rastgele kombinasyon
// dener ya da yeniden çeker.
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

  /// Ölçülen yüz oranlarını ve fotoğraftan gelen renkleri koruyarak stilleri
  /// rastgele değiştirir.
  void _shuffle() {
    setState(() {
      _config = _config.copyWith(
        hair: _random.nextInt(kHairStyles.length),
        hairColor: kHairColors[_random.nextInt(kHairColors.length)],
        brow: _random.nextInt(kBrowStyles.length),
        eye: _random.nextInt(kEyeStyles.length),
        lash: _random.nextInt(kLashStyles.length),
        beard: _random.nextInt(kBeardStyles.length),
        glasses: _random.nextInt(kGlassesStyles.length),
        clothingColor: kClothingColors[_random.nextInt(kClothingColors.length)],
        isSuggested: false,
      );
    });
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
          FaceAvatarPreview(config: _config, size: 150),
          const SizedBox(height: 16),
          _buildCategoryTabs(),
          const SizedBox(height: 14),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              child: _buildOptionsForCategory(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoryTabs() {
    const items = <(FaceAvatarCategory, String, IconData)>[
      (FaceAvatarCategory.faceShape, 'Yüz', Icons.face_outlined),
      (FaceAvatarCategory.skin, 'Ten', Icons.palette_outlined),
      (FaceAvatarCategory.hair, 'Saç', Icons.content_cut),
      (FaceAvatarCategory.brow, 'Kaş', Icons.horizontal_rule),
      (FaceAvatarCategory.eye, 'Göz', Icons.visibility_outlined),
      (FaceAvatarCategory.lash, 'Kirpik', Icons.auto_awesome_outlined),
      (FaceAvatarCategory.beard, 'Sakal', Icons.face_retouching_natural),
      (FaceAvatarCategory.glasses, 'Gözlük', Icons.remove_red_eye_outlined),
    ];
    final primaryColor = Theme.of(context).colorScheme.primary;

    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (category, label, icon) = items[index];
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

  Widget _buildOptionsForCategory() {
    switch (_activeCategory) {
      case FaceAvatarCategory.faceShape:
        return _styleRow(
          count: kFaceShapes.length,
          labelAt: (i) => kFaceShapes[i].label,
          configAt: (i) => _config.copyWith(faceShape: i),
          selectedIndex: _config.faceShape,
          onPick: (i) => _update(_config.copyWith(faceShape: i)),
        );

      case FaceAvatarCategory.skin:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _colorRow(
              label: 'Ten Tonu',
              colors: kSkinTones,
              current: _config.skinTone,
              onPick: (c) => _update(_config.copyWith(skinTone: c)),
            ),
            const SizedBox(height: 20),
            _colorRow(
              label: 'Kıyafet Rengi',
              colors: kClothingColors,
              current: _config.clothingColor,
              onPick: (c) => _update(_config.copyWith(clothingColor: c)),
            ),
          ],
        );

      case FaceAvatarCategory.hair:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _styleRow(
              count: kHairStyles.length,
              labelAt: (i) => kHairStyles[i].label,
              configAt: (i) => _config.copyWith(hair: i),
              selectedIndex: _config.hair,
              onPick: (i) => _update(_config.copyWith(hair: i)),
            ),
            const SizedBox(height: 18),
            _colorRow(
              label: 'Saç Rengi',
              colors: kHairColors,
              current: _config.hairColor,
              onPick: (c) => _update(_config.copyWith(hairColor: c)),
            ),
          ],
        );

      case FaceAvatarCategory.brow:
        return _styleRow(
          count: kBrowStyles.length,
          labelAt: (i) => kBrowStyles[i].label,
          configAt: (i) => _config.copyWith(brow: i),
          selectedIndex: _config.brow,
          onPick: (i) => _update(_config.copyWith(brow: i)),
        );

      case FaceAvatarCategory.eye:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _styleRow(
              count: kEyeStyles.length,
              labelAt: (i) => kEyeStyles[i].label,
              configAt: (i) => _config.copyWith(eye: i),
              selectedIndex: _config.eye,
              onPick: (i) => _update(_config.copyWith(eye: i)),
            ),
            const SizedBox(height: 18),
            _colorRow(
              label: 'Göz Rengi',
              colors: kEyeColors,
              current: _config.eyeColor,
              onPick: (c) => _update(_config.copyWith(eyeColor: c)),
            ),
          ],
        );

      case FaceAvatarCategory.lash:
        return _styleRow(
          count: kLashStyles.length,
          labelAt: (i) => kLashStyles[i].label,
          configAt: (i) => _config.copyWith(lash: i),
          selectedIndex: _config.lash,
          onPick: (i) => _update(_config.copyWith(lash: i)),
        );

      case FaceAvatarCategory.beard:
        return _styleRow(
          count: kBeardStyles.length,
          labelAt: (i) => kBeardStyles[i].label,
          configAt: (i) => _config.copyWith(beard: i),
          selectedIndex: _config.beard,
          onPick: (i) => _update(_config.copyWith(beard: i)),
        );

      case FaceAvatarCategory.glasses:
        return _styleRow(
          count: kGlassesStyles.length,
          labelAt: (i) => kGlassesStyles[i].label,
          configAt: (i) => _config.copyWith(glasses: i),
          selectedIndex: _config.glasses,
          onPick: (i) => _update(_config.copyWith(glasses: i)),
        );
    }
  }

  /// Her seçenek, o seçenek uygulanmış küçük bir avatar önizlemesi olarak
  /// gösterilir — kullanıcı sonucu tahmin etmek zorunda kalmaz.
  Widget _styleRow({
    required int count,
    required String Function(int) labelAt,
    required FaceAvatarConfig Function(int) configAt,
    required int selectedIndex,
    required void Function(int) onPick,
  }) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 92,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: count,
        separatorBuilder: (_, _) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final selected = index == selectedIndex;
          return GestureDetector(
            onTap: () => onPick(index),
            child: Column(
              children: [
                Container(
                  width: 66,
                  height: 66,
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
                    child: CustomPaint(painter: FaceAvatarPainter(configAt(index), detailed: false)),
                  ),
                ),
                const SizedBox(height: 6),
                SizedBox(
                  width: 74,
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
          spacing: 12,
          runSpacing: 12,
          children: colors.map((c) {
            final selected = c.toARGB32() == current.toARGB32();
            return GestureDetector(
              onTap: () => onPick(c),
              child: Container(
                width: 34,
                height: 34,
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
          top: MediaQuery.of(context).padding.top + 18,
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
