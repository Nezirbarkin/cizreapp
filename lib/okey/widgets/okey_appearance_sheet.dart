import 'package:flutter/material.dart';

import '../services/okey_sound_service.dart';
import '../theme/okey_ui.dart';
import 'okey_design_preview.dart';
import 'okey_table_settings_dialog.dart';

/// Lobideki GÖRÜNÜM sayfası: tasarım, masa teması ve ıstaka.
///
/// ## Kim neyi seçer
///
/// Tasarımı YÖNETİCİ belirler (Admin › 101 Okey › Tasarım). Yönetici
/// "oyuncular kendi seçsin" anahtarını açık bıraktıysa oyuncu bu cihazda
/// başka bir tasarım, masa ve ıstaka seçebilir; "Yöneticinin seçimine dön"
/// kendi seçimini siler. Anahtar kapalıysa sayfa yalnızca hangi tasarımın
/// geçerli olduğunu söyler.
///
/// ## Neden sayfa kendi kendini yeniden çiziyor
///
/// Tasarım seçildiğinde arkadaki lobi baştan kurulur ([OkeyDesignScope]),
/// ama bu sayfa lobinin ALTINDA değil Navigator'ın katmanında yaşar —
/// yeni renkleri kendisi dinlemezse eski tasarımla açık kalırdı.
class OkeyAppearanceSheet extends StatefulWidget {
  const OkeyAppearanceSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const OkeyAppearanceSheet(),
    );
  }

  @override
  State<OkeyAppearanceSheet> createState() => _OkeyAppearanceSheetState();
}

class _OkeyAppearanceSheetState extends State<OkeyAppearanceSheet> {
  /// Kart genişliği + ara boşluk (bkz. [_DesignChoice]).
  static const double _itemExtent = 128;

  /// Liste SEÇİLİ tasarımın hizasında açılır: yedinci tasarımı seçmiş oyuncu
  /// sayfayı açınca kendi seçimini ekran dışında aramasın.
  final ScrollController _designs = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_designs.hasClients) return;
      final i = OkeyDesign.all.indexOf(OkeyUI.design);
      final target = i * _itemExtent - _itemExtent * 0.5;
      _designs.jumpTo(target.clamp(0.0, _designs.position.maxScrollExtent));
    });
  }

  @override
  void dispose() {
    _designs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final prefs = OkeyDesignPrefs.instance;
    return ListenableBuilder(
      listenable: prefs.listenable,
      builder: (context, _) {
        final current = OkeyUI.design;
        final colors = OkeyPickerColors(
          text: OkeyUI.text,
          dim: OkeyUI.textDim,
          faint: OkeyUI.textFaint,
          accent: OkeyUI.accentInk,
          border: OkeyUI.cardBorder,
        );
        final adminDesign = OkeyDesign.byKey(prefs.adminConfig.designKey);
        final screen = MediaQuery.sizeOf(context);

        return SafeArea(
          top: false,
          child: Container(
            margin: const EdgeInsets.all(10),
            constraints: BoxConstraints(maxHeight: screen.height * 0.88),
            decoration: BoxDecoration(
              color: OkeyUI.cardFill,
              borderRadius: BorderRadius.circular(OkeyUI.radiusLg),
              border: Border.all(color: OkeyUI.cardBorder),
              boxShadow: [
                BoxShadow(
                  color: OkeyUI.isLight
                      ? OkeyUI.shadow
                      : const Color(0x99000000),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 6, 0),
                  child: Row(
                    children: [
                      Icon(Icons.palette_outlined, color: OkeyUI.accentInk),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Görünüm',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: OkeyUI.display(size: 20),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Kapat',
                        icon: Icon(Icons.close, color: OkeyUI.textFaint),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!prefs.userChoiceAllowed) ...[
                          Text(
                            'Okey görünümü yönetici tarafından '
                            '"${adminDesign.label}" olarak belirlendi.',
                            style: OkeyUI.body,
                          ),
                          const SizedBox(height: OkeyUI.gap),
                          SizedBox(
                            height: 220,
                            child: Center(
                              child: AspectRatio(
                                aspectRatio: 0.56,
                                child: OkeyDesignPreview(
                                  design: current,
                                  layout: OkeyUI.layout,
                                ),
                              ),
                            ),
                          ),
                        ] else ...[
                          Text(
                            'Lobi, masa ve ıstaka birlikte değişir. Seçimin '
                            'yalnızca bu cihazda geçerli.',
                            style: OkeyUI.body,
                          ),
                          const SizedBox(height: OkeyUI.gap),
                          SizedBox(
                            height: 236,
                            child: ListView.separated(
                              controller: _designs,
                              scrollDirection: Axis.horizontal,
                              itemCount: OkeyDesign.all.length,
                              separatorBuilder: (_, _) =>
                                  const SizedBox(width: 10),
                              itemBuilder: (context, i) {
                                final d = OkeyDesign.all[i];
                                return _DesignChoice(
                                  design: d,
                                  layout: prefs.adminConfig.layout ?? d.layout,
                                  selected: d.key == current.key,
                                  isAdminPick: d.key == adminDesign.key,
                                  onTap: () => prefs.selectByUser(d),
                                );
                              },
                            ),
                          ),
                          if (prefs.userDesignKey != null) ...[
                            const SizedBox(height: OkeyUI.gapSm),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton.icon(
                                onPressed: prefs.clearUserChoice,
                                icon: const Icon(Icons.restart_alt, size: 18),
                                label: Text(
                                  'Yöneticinin seçimine dön '
                                  '(${adminDesign.label})',
                                ),
                              ),
                            ),
                          ],
                          Divider(color: OkeyUI.cardBorder, height: 24),
                          OkeyTableThemePicker(colors: colors),
                          Divider(color: OkeyUI.cardBorder, height: 24),
                          OkeyRackStylePicker(colors: colors),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Tasarım seçim kartı: telefon önizlemesi + ad + düzen.
class _DesignChoice extends StatelessWidget {
  final OkeyDesign design;
  final OkeyLobbyLayout layout;
  final bool selected;
  final bool isAdminPick;
  final VoidCallback onTap;

  const _DesignChoice({
    required this.design,
    required this.layout,
    required this.selected,
    required this.isAdminPick,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: '${design.label} tasarımı',
      child: GestureDetector(
        onTap: withOkeyTapSound(onTap),
        child: SizedBox(
          width: 118,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: selected ? OkeyUI.brass : OkeyUI.cardBorder,
                      width: selected ? 2.5 : 1,
                    ),
                  ),
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: OkeyDesignPreview(
                          design: design,
                          layout: layout,
                        ),
                      ),
                      if (selected)
                        Positioned(
                          right: 4,
                          top: 4,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: BoxDecoration(
                              color: OkeyUI.brass,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              Icons.check,
                              size: 14,
                              color: OkeyUI.onGold,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                design.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: selected ? OkeyUI.accentInk : OkeyUI.text,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                isAdminPick ? '${layout.label} · varsayılan' : layout.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: OkeyUI.caption,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
