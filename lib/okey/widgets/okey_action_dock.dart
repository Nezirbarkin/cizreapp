import 'package:flutter/material.dart';

import '../services/okey_sound_service.dart';
import '../theme/okey_theme.dart';

/// Istakanın SAĞ UCUNDAKİ DİKEY HAMLE DOCK'U.
///
/// ## Neden konsoldaki yatay şeridin yerine (düzen v5, 2026-09-20)
///
/// v4'te dört hamle düğmesi masanın ALT kenarında, yatay bir şeritteydi.
/// Üç ayrı sorunu vardı:
///
///  1. **Yükseklik yiyordu.** Konsol ekranın %11,5'iydi ve içindeki tek iş
///     dört düğmeydi. Masa yatay tutulur; dikey piksel en kıt kaynaktır ve
///     o şerit doğrudan per tablasından ve taş boyundan kısılıyordu.
///  2. **Parmak orada değil.** Telefon yan tutulurken SAĞ baş parmak ekranın
///     sağ kenarında durur, alt kenarının ortasında değil. Dört düğme
///     ekranın solundan ortasına yayıldığı için her hamlede el kayıyordu —
///     üstelik sol el o sırada ıstakadan taş sürüklüyor.
///  3. **Dördü de hep oradaydı, üçü sönük.** Hangi düğmenin canlı olduğu
///     ancak DENEYEREK anlaşılıyordu.
///
/// Dock bu üçünü birden çözer: dikey olduğu için masadan yükseklik ÇALMAZ
/// (ıstakayla aynı şeritte, onun sağında durur), baş parmağın altındadır ve
/// **yalnızca o an yapılabilen hamleleri** gösterir.
///
/// ## Sıralama kuralı: en alttaki en sık yapılan
///
/// Dikey bir dock'ta baş parmağa en yakın yer ALTTIR. TAŞI AT her turda
/// yapılır, İŞLE bazen, AÇ elde bir kez. Düğmeler bu sıklığa göre aşağıdan
/// yukarıya dizilir ve en alttaki aynı zamanda EN BÜYÜKTÜR.
///
/// ## Saf widget
///
/// Provider bilmez: her şey açık bayrak ve geri çağırma olarak gelir
/// (bkz. [OkeyTableScaffold] ile aynı gerekçe). Böylece dock'un dört
/// aşamadaki hali widget testiyle doğrulanabilir.
class OkeyActionDock extends StatelessWidget {
  /// TAŞ ÇEKME aşaması mı? true ise dock TEK bir büyük düğmeye dönüşür.
  final bool drawPhase;

  /// Çekme düğmesinin altındaki açıklama ("Desteden ya da soldan").
  final String drawSubtitle;
  final VoidCallback? onDraw;

  /// Yandan alınan taşı geri koyma — yalnızca hâlâ mümkünken görünür.
  final VoidCallback? onUndoSideDraw;

  /// AÇ: seri ya da çiftle açma. İkisi aynı anda asla yapılamaz, o yüzden
  /// tek düğme; dokununca [onOpen] seçim sayfasını açar.
  final bool canOpen;

  /// AÇ düğmesinin rozeti: açılmadan önce "103/101", açıldıktan sonra per
  /// sayısı.
  final String? openBadge;
  final VoidCallback? onOpen;
  final VoidCallback? onOpenBlocked;

  final bool canProcess;

  /// Hiç taş seçili değilken otomatik işlenecek taş sayısı (0 ise rozet yok).
  final int autoProcessCount;
  final VoidCallback? onProcess;
  final VoidCallback? onProcessBlocked;

  final bool canDiscard;

  /// Bu atış eli BİTİRİYOR mu? Düğme "AT — BİTİR"e döner.
  final bool isWinningDiscard;

  /// Atılacak taş MASADA İŞLENİYOR mu? true ise düğme kızıl kenar alır:
  /// bedel, basmadan ÖNCE görünür (onay için bkz. ekranın _confirmRiskyDiscard).
  final bool isRiskyDiscard;

  final VoidCallback? onDiscard;
  final VoidCallback? onDiscardBlocked;

  const OkeyActionDock({
    super.key,
    required this.drawPhase,
    this.drawSubtitle = '',
    this.onDraw,
    this.onUndoSideDraw,
    this.canOpen = false,
    this.openBadge,
    this.onOpen,
    this.onOpenBlocked,
    this.canProcess = false,
    this.autoProcessCount = 0,
    this.onProcess,
    this.onProcessBlocked,
    this.canDiscard = false,
    this.isWinningDiscard = false,
    this.isRiskyDiscard = false,
    this.onDiscard,
    this.onDiscardBlocked,
  });

  @override
  Widget build(BuildContext context) {
    return MediaQuery.withNoTextScaling(
      child: LayoutBuilder(
        builder: (context, c) {
          final h = c.hasBoundedHeight && c.maxHeight.isFinite
              ? c.maxHeight
              : 150.0;
          final pad = (h * 0.045).clamp(4.0, 9.0).toDouble();
          final gap = (h * 0.035).clamp(3.0, 7.0).toDouble();

          return Container(
            padding: EdgeInsets.all(pad),
            decoration: BoxDecoration(
              color: OkeyV3.surface,
              borderRadius: BorderRadius.circular(OkeyV3.radius + 4),
              border: Border.all(color: OkeyV3.border),
              boxShadow: OkeyV3.lift,
            ),
            child: drawPhase
                ? _DockButton(
                    title: 'TAŞ ÇEK',
                    subtitle: drawSubtitle,
                    icon: Icons.download_rounded,
                    tone: _DockTone.primary,
                    enabled: onDraw != null,
                    onPressed: onDraw,
                  )
                : _playColumn(gap),
          );
        },
      ),
    );
  }

  Widget _playColumn(double gap) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // GERİ KOY — rutin değil, bir KAÇIŞ yolu. Yalnızca yandan alınan taş
        // hâlâ geri konabilirken ve EN ÜSTTE, yani parmaktan en uzakta:
        // yanlışlıkla basılması en pahalı olan düğme, en zor ulaşılan yerde.
        if (onUndoSideDraw != null) ...[
          Expanded(
            flex: 16,
            child: _DockButton(
              title: 'GERİ KOY',
              icon: Icons.undo_rounded,
              tone: _DockTone.tool,
              enabled: true,
              onPressed: onUndoSideDraw,
            ),
          ),
          SizedBox(height: gap),
        ],
        Expanded(
          flex: 22,
          child: _DockButton(
            title: 'AÇ',
            icon: Icons.open_in_new_rounded,
            badge: openBadge,
            trailingChevron: true,
            tone: canOpen ? _DockTone.ready : _DockTone.normal,
            enabled: canOpen,
            onPressed: onOpen,
            onBlockedTap: onOpenBlocked,
          ),
        ),
        SizedBox(height: gap),
        Expanded(
          flex: 22,
          child: _DockButton(
            title: 'İŞLE',
            icon: Icons.playlist_add_rounded,
            badge: autoProcessCount > 0 ? '$autoProcessCount' : null,
            badgeColor: const Color(0xFF9BE87C),
            tone: _DockTone.normal,
            enabled: canProcess,
            onPressed: onProcess,
            onBlockedTap: onProcessBlocked,
          ),
        ),
        SizedBox(height: gap),
        // EN ALT, EN BÜYÜK: her turun kapanış hamlesi.
        Expanded(
          flex: 32,
          child: _DockButton(
            title: isWinningDiscard ? 'AT — BİTİR' : 'TAŞI AT',
            icon: isWinningDiscard
                ? Icons.emoji_events_rounded
                : Icons.arrow_downward_rounded,
            tone: isWinningDiscard ? _DockTone.winning : _DockTone.primary,
            danger: isRiskyDiscard,
            enabled: canDiscard,
            onPressed: onDiscard,
            onBlockedTap: onDiscardBlocked,
          ),
        ),
      ],
    );
  }
}

/// Dock düğmesinin görsel tonu — renk keyfi değil, hamlenin ağırlığı.
enum _DockTone {
  /// Rutin hamle, şu an yapılabilir (İŞLE).
  normal,

  /// Turun kapanış hamlesi — pirinç dolgu (TAŞ ÇEK, TAŞI AT).
  primary,

  /// Nadir ve yüksek değerli, ŞU AN yapılabilir (AÇ, baraj geçilmişken).
  ready,

  /// Eli bitiren hamle.
  winning,

  /// Istaka aracı / kaçış yolu — turkuaz (GERİ KOY).
  tool,
}

class _DockButton extends StatelessWidget {
  final String title;
  final String? subtitle;
  final IconData icon;
  final String? badge;
  final Color? badgeColor;
  final bool trailingChevron;
  final _DockTone tone;
  final bool enabled;

  /// Kırmızı kenar: hamle yapılabilir ama BEDELLİ (işlek taş atma).
  final bool danger;

  final VoidCallback? onPressed;
  final VoidCallback? onBlockedTap;

  const _DockButton({
    required this.title,
    required this.icon,
    required this.tone,
    required this.enabled,
    this.subtitle,
    this.badge,
    this.badgeColor,
    this.trailingChevron = false,
    this.danger = false,
    this.onPressed,
    this.onBlockedTap,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final h = c.hasBoundedHeight && c.maxHeight.isFinite
            ? c.maxHeight
            : 44.0;
        final w = c.hasBoundedWidth ? c.maxWidth : 96.0;

        // İKON ve YAZI kutuya göre ölçeklenir; dar bir telefonda da geniş bir
        // tablette de düğme aynı oranda görünür.
        final iconSize = (h * 0.30).clamp(13.0, 24.0).toDouble();
        final fontSize = (w * 0.155).clamp(9.0, 14.0).toDouble();

        final (List<Color>? gradient, Color fg, Color? glow) = switch (tone) {
          _ when !enabled => (null, OkeyV3.textDisabled, null),
          _DockTone.primary => (OkeyV3.gold, OkeyV3.onGold, OkeyV3.goldGlow),
          _DockTone.winning => (
            OkeyV3.goldBright,
            OkeyV3.onGold,
            OkeyV3.goldGlow,
          ),
          _DockTone.ready => (OkeyV3.gold, OkeyV3.onGold, OkeyV3.goldGlow),
          _DockTone.tool => (OkeyV3.tool, OkeyV3.onTool, null),
          _DockTone.normal => (null, OkeyV3.text, null),
        };

        final borderColor = danger && enabled
            ? const Color(0xFFE05A4E)
            : (enabled ? OkeyV3.borderStrong : OkeyV3.borderDisabled);

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          // KAPALI DÜĞME DE DOKUNULABİLİR: dokunuş hiçbir şey yapmasaydı
          // düğme bozuk sanılırdı. Kapalıyken SEBEBİNİ söyler.
          onTap: enabled ? withOkeyTapSound(onPressed ?? () {}) : onBlockedTap,
          child: Container(
            decoration: BoxDecoration(
              color: gradient == null
                  ? (enabled ? OkeyV3.surfaceRaised : OkeyV3.surfaceDisabled)
                  : null,
              gradient: gradient == null
                  ? null
                  : LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: gradient,
                    ),
              borderRadius: BorderRadius.circular(OkeyV3.radius),
              border: Border.all(
                color: borderColor,
                width: danger && enabled ? 1.6 : 1,
              ),
              boxShadow: [
                ...OkeyV3.lift,
                if (glow != null && enabled)
                  BoxShadow(color: glow, blurRadius: 12),
                if (danger && enabled)
                  const BoxShadow(color: Color(0x66E05A4E), blurRadius: 12),
              ],
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(icon, size: iconSize, color: fg),
                          if (trailingChevron) ...[
                            SizedBox(width: iconSize * 0.15),
                            Icon(
                              Icons.chevron_right_rounded,
                              size: iconSize * 0.8,
                              color: fg,
                            ),
                          ],
                        ],
                      ),
                      SizedBox(height: h * 0.05),
                      Text(
                        title,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: fontSize,
                          height: 1.0,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.4,
                          color: fg,
                        ),
                      ),
                      if (badge != null) ...[
                        SizedBox(height: h * 0.05),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1.5,
                          ),
                          decoration: BoxDecoration(
                            color: gradient == null
                                ? OkeyV3.surface
                                : const Color(0x33000000),
                            borderRadius: BorderRadius.circular(
                              OkeyV3.radiusSm,
                            ),
                          ),
                          child: Text(
                            badge!,
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: fontSize * 0.74,
                              height: 1.0,
                              fontWeight: FontWeight.w800,
                              color: badgeColor ?? fg,
                            ),
                          ),
                        ),
                      ],
                      if (subtitle != null && subtitle!.isNotEmpty) ...[
                        SizedBox(height: h * 0.05),
                        Text(
                          subtitle!,
                          maxLines: 2,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: fontSize * 0.68,
                            height: 1.15,
                            fontWeight: FontWeight.w600,
                            color: fg.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
