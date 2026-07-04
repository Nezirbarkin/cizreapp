import 'package:flutter/material.dart';

/// Üst barda kullanılan, başlık ile slogan arasında geçiş yapan animasyonlu widget.
///
/// Animasyon akışı (döngüsel):
///   1. Önce [primaryText] (varsayılan: "CizreApp") fade/slide ile belirir.
///   2. [primaryDuration] kadar ekranda kalır.
///   3. Soldan sağa kayarak çıkar; yerine [secondaryText] (varsayılan:
///      "Her an her kapıda!") fade/slide ile gelir.
///   4. [secondaryDuration] kadar ekranda kalır.
///   5. Tam tersi yönde kayarak çıkar; başa dönülür ve döngü tekrarlanır.
///
/// Üç ana sekmede (AnaSayfa, Ürünler, Keşfet) tutarlı biçimde kullanılır.
/// Başlığa tıklanıldığında [onTap] çağrılır (örn: sayfayı en üste kaydır).
///
/// Tasarım notu: İki ayrı [_TitleItem] widget'ı `Stack` içinde konumlandırılır.
/// `IgnorePointer` ile sadece aktif widget dokunmatik olay alır; her biri kendi
/// `AnimationController`'ı ile fade+slide yapar. Layout her iki widget için de
/// `Align` + `Text` ile sabit kaldığından `hasSize` hatası oluşmaz.
class AnimatedAppTitle extends StatefulWidget {
  /// Birincil metin (varsayılan: "CizreApp").
  final String primaryText;

  /// İkincil metin / slogan (varsayılan: "Her an her kapıda!").
  final String secondaryText;

  /// Birincil metnin font boyutu.
  final double primaryFontSize;

  /// İkincil metnin font boyutu.
  final double secondaryFontSize;

  /// Yazı rengi (varsayılan: beyaz).
  final Color color;

  /// Birincil metnin ekranda görünür kalma süresi.
  final Duration primaryDuration;

  /// İkincil metnin ekranda görünür kalma süresi.
  final Duration secondaryDuration;

  /// Geçiş animasyonunun süresi.
  final Duration transitionDuration;

  /// Üstüne tıklandığında çağrılacak callback.
  final VoidCallback? onTap;

  const AnimatedAppTitle({
    super.key,
    this.primaryText = 'CizreApp',
    this.secondaryText = 'Her an her kapıda!',
    this.primaryFontSize = 22,
    this.secondaryFontSize = 14,
    this.color = Colors.white,
    this.primaryDuration = const Duration(milliseconds: 6000),
    this.secondaryDuration = const Duration(milliseconds: 3000),
    this.transitionDuration = const Duration(milliseconds: 700),
    this.onTap,
  });

  /// Veritabanı ayarlarından oluşturucu (daha kolay kullanım için)
  factory AnimatedAppTitle.fromSettings({
    Key? key,
    required String primaryText,
    required String secondaryText,
    required int primaryDurationMs,
    required int secondaryDurationMs,
    required int transitionDurationMs,
    double primaryFontSize = 22,
    double secondaryFontSize = 14,
    Color color = Colors.white,
    VoidCallback? onTap,
  }) {
    return AnimatedAppTitle(
      key: key,
      primaryText: primaryText,
      secondaryText: secondaryText,
      primaryDuration: Duration(milliseconds: primaryDurationMs),
      secondaryDuration: Duration(milliseconds: secondaryDurationMs),
      transitionDuration: Duration(milliseconds: transitionDurationMs),
      primaryFontSize: primaryFontSize,
      secondaryFontSize: secondaryFontSize,
      color: color,
      onTap: onTap,
    );
  }

  @override
  State<AnimatedAppTitle> createState() => _AnimatedAppTitleState();
}

class _AnimatedAppTitleState extends State<AnimatedAppTitle> {
  bool _showingPrimary = true;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _runCycle();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  Future<void> _runCycle() async {
    if (_disposed) return;

    while (!_disposed) {
      // Birincil metin ekranda kalsın
      await Future<void>.delayed(widget.primaryDuration);
      if (_disposed) return;

      // İkincil metne geç
      if (mounted) setState(() => _showingPrimary = false);

      // İkincil metin ekranda kalsın
      await Future<void>.delayed(widget.secondaryDuration);
      if (_disposed) return;

      // Tekrar birincil metne dön
      if (mounted) setState(() => _showingPrimary = true);
    }
  }

  TextStyle _styleFor(double fontSize, FontWeight weight) {
    return TextStyle(
      fontSize: fontSize,
      fontWeight: weight,
      color: widget.color,
      letterSpacing: 0.6,
      height: 1.05,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: SizedBox(
        height: 28,
        // Stack: iki item üst üste konumlanır. Her biri kendi animasyonunu yönetir.
        // Her iki item daima layout'a dahil edilir (IgnorePointer ile sadece
        // görünen olan dokunmatik olay alır). Bu sayede Stack layout aşamasında
        // her zaman hasSize alır.
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            // Birincil metin (CizreApp)
            _TitleItem(
              key: const ValueKey('primary'),
              text: widget.primaryText,
              style: _styleFor(widget.primaryFontSize, FontWeight.w900),
              visible: _showingPrimary,
              transitionDuration: widget.transitionDuration,
            ),
            // İkincil metin (slogan)
            _TitleItem(
              key: const ValueKey('secondary'),
              text: widget.secondaryText,
              style: _styleFor(widget.secondaryFontSize, FontWeight.w600),
              visible: !_showingPrimary,
              transitionDuration: widget.transitionDuration,
            ),
          ],
        ),
      ),
    );
  }
}

/// Tek bir metin item'ı. Kendi animasyonunu yönetir; `visible` değiştiğinde
/// fade + slide ile belirir/kaybolur. Görünür değilken `IgnorePointer` ile
/// dokunmatik olayları geçirmez.
class _TitleItem extends StatefulWidget {
  final String text;
  final TextStyle style;
  final bool visible;
  final Duration transitionDuration;

  const _TitleItem({
    super.key,
    required this.text,
    required this.style,
    required this.visible,
    required this.transitionDuration,
  });

  @override
  State<_TitleItem> createState() => _TitleItemState();
}

class _TitleItemState extends State<_TitleItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.transitionDuration,
      value: widget.visible ? 1.0 : 0.0,
    );
  }

  @override
  void didUpdateWidget(covariant _TitleItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
    if (widget.transitionDuration != oldWidget.transitionDuration) {
      _controller.duration = widget.transitionDuration;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // visible=true ise aşağıdan yukarı kayarak belirsin (0.35 → 0)
        // visible=false ise yukarıya doğru kayarak kaybolsun (0 → -0.35)
        final begin = widget.visible ? const Offset(0, 0.35) : Offset.zero;
        final end = widget.visible ? Offset.zero : const Offset(0, -0.35);
        final slide = Tween<Offset>(begin: begin, end: end).animate(
          CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
        );
        return Opacity(
          opacity: _controller.value,
          child: SlideTransition(
            position: slide,
            child: IgnorePointer(
              ignoring: !widget.visible,
              child: child,
            ),
          ),
        );
      },
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          widget.text,
          style: widget.style,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}