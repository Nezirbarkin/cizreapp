import 'package:flutter/widgets.dart';

/// Alt gezinme çubuğu için TEMBEL + SEÇİCİ KORUMALI sekme gövdesi.
///
/// - Bir sekme, ilk kez seçilene kadar hiç oluşturulmaz (açılış maliyeti yok).
/// - [retained] içindeki sekmeler bir kez açıldıktan sonra [IndexedStack]
///   içinde yaşamaya devam eder: başka sekmeye geçip dönünce veri yeniden
///   çekilmez, kaydırma konumu ve canlı abonelikler korunur. Gizliyken
///   animasyonları ([TickerMode]) durur.
/// - [retained] dışındaki sekmeler eskisi gibi davranır: seçildiğinde kurulur,
///   ayrılınca atılır (her girişte güncel veri gerektiren ekranlar için).
/// - Korunan bir sekmeden [maxAway]'den uzun süre ayrı kalınırsa kopyası bayat
///   sayılır ve dönüşte sıfırdan kurulur (eski fiyat/stok/akış göstermemek için).
class LazyTabStack extends StatefulWidget {
  const LazyTabStack({
    super.key,
    required this.index,
    required this.count,
    required this.tabBuilder,
    this.retained = const <int>{},
    this.maxAway = const Duration(minutes: 5),
    this.clock = DateTime.now,
  });

  /// Görünen sekme.
  final int index;

  /// Toplam sekme sayısı.
  final int count;

  /// Sekme içeriğini üretir. Aynı widget örneğini döndürmesi (önbellek) önerilir.
  final Widget Function(int index) tabBuilder;

  /// Sekmeler arası geçişte durumu korunacak sekme dizinleri.
  final Set<int> retained;

  /// Korunan sekmeden bu süreden uzun ayrı kalınırsa yeniden kurulur.
  final Duration maxAway;

  /// Testlerde zamanı taklit etmek için.
  final DateTime Function() clock;

  @override
  State<LazyTabStack> createState() => _LazyTabStackState();
}

class _LazyTabStackState extends State<LazyTabStack> {
  final Set<int> _built = {};
  final Map<int, DateTime> _leftAt = {};
  final Map<int, int> _generation = {};

  @override
  void didUpdateWidget(LazyTabStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index == widget.index) return;

    final now = widget.clock();
    _leftAt[oldWidget.index] = now;

    final target = widget.index;
    final leftAt = _leftAt[target];
    if (widget.retained.contains(target) &&
        leftAt != null &&
        now.difference(leftAt) > widget.maxAway) {
      // Bayat kopya: anahtarı değiştir → eski State atılır, yenisi yüklenir.
      _built.remove(target);
      _generation[target] = (_generation[target] ?? 0) + 1;
    }
  }

  @override
  Widget build(BuildContext context) {
    return IndexedStack(
      index: widget.index,
      sizing: StackFit.expand,
      children: [for (var i = 0; i < widget.count; i++) _buildTab(i)],
    );
  }

  Widget _buildTab(int index) {
    final active = index == widget.index;

    if (!widget.retained.contains(index)) {
      return active ? widget.tabBuilder(index) : const SizedBox.shrink();
    }

    if (active) _built.add(index);
    if (!_built.contains(index)) return const SizedBox.shrink();

    return KeyedSubtree(
      key: ValueKey('lazy-tab-$index-${_generation[index] ?? 0}'),
      // Gizli sekmenin animasyonları (ticker) durur; pil/CPU harcamaz.
      child: TickerMode(enabled: active, child: widget.tabBuilder(index)),
    );
  }
}
