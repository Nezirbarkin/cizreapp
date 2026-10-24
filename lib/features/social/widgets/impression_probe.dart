import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Kaydırılabilir listedeki bir öğeyi saran görünürlük yoklayıcısı: öğenin en
/// az yarısı (uzun kartta görünür alanın yarısı) ekrandayken [onSeen] BİR KEZ
/// çağrılır.
///
/// Paket kullanmaz (zamanlayıcısı yok, widget testlerinde bekleyen Timer
/// bırakmaz): ilk karede ve her kaydırma DURDUĞUNDA ölçer. Sekme arka plandayken
/// (`TickerMode` kapalı, ör. LazyTabStack) saymaz.
class ImpressionProbe extends StatefulWidget {
  const ImpressionProbe({
    super.key,
    required this.id,
    required this.onSeen,
    required this.child,
  });

  /// Öğenin kimliği; değişirse yeniden sayılabilir.
  final String id;
  final VoidCallback onSeen;
  final Widget child;

  @override
  State<ImpressionProbe> createState() => _ImpressionProbeState();
}

class _ImpressionProbeState extends State<ImpressionProbe> {
  bool _reported = false;
  bool _active = true;
  ScrollPosition? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _active = TickerMode.of(context);
    final position = Scrollable.maybeOf(context)?.position;
    if (!identical(position, _position)) {
      _position?.isScrollingNotifier.removeListener(_onScrollingChanged);
      _position = position;
      _position?.isScrollingNotifier.addListener(_onScrollingChanged);
    }
    _scheduleCheck();
  }

  @override
  void didUpdateWidget(covariant ImpressionProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _reported = false;
      _scheduleCheck();
    }
  }

  @override
  void dispose() {
    _position?.isScrollingNotifier.removeListener(_onScrollingChanged);
    super.dispose();
  }

  // Kaydırma bittiği anda yerleşim henüz yeni ofsete göre güncellenmemiş
  // olabilir: ölçüm bir sonraki karenin sonuna bırakılır.
  void _onScrollingChanged() {
    if (!(_position?.isScrollingNotifier.value ?? false)) _scheduleCheck();
  }

  void _scheduleCheck() {
    if (_reported) return;
    WidgetsBinding.instance.addPostFrameCallback((_) => _check());
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _check() {
    if (_reported || !_active || !mounted) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return;
    final scrollable = Scrollable.maybeOf(context);
    final viewBox = scrollable?.context.findRenderObject();
    if (viewBox is! RenderBox || !viewBox.attached || !viewBox.hasSize) return;

    final item = box.localToGlobal(Offset.zero) & box.size;
    final view = viewBox.localToGlobal(Offset.zero) & viewBox.size;
    final visible = item.intersect(view);
    if (visible.isEmpty || visible.height <= 0 || visible.width <= 0) return;

    final base = math.min(item.height, view.height);
    if (base <= 0 || visible.height / base < 0.5) return;
    _reported = true;
    widget.onSeen();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
