import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../features/admin/widgets/admin_ui.dart';
import '../widgets/sehirici_common_widgets.dart';

/// Şehiriçi admin ekranlarının ortak görsel araçları. Panelin genel diliyle
/// ([AdminUi]: mor marka rengi, yuvarlatılmış beyaz kartlar) uyumludur; yalnızca
/// bu modüle özgü parçalar (renk paleti, form alanı stili, alt sayfa iskeleti)
/// burada tanımlıdır.

/// Hatlar için hazır renk paleti (haritada birbirinden ayrışan, koyu/açık
/// zeminde okunaklı tonlar).
const List<Color> kSehiriciLinePalette = [
  Color(0xFF1976D2), // mavi
  Color(0xFFE53935), // kırmızı
  Color(0xFF2E9E5B), // yeşil
  Color(0xFFF59E0B), // kehribar
  Color(0xFF8E24AA), // mor
  Color(0xFF00897B), // deniz yeşili
  Color(0xFFF4511E), // turuncu
  Color(0xFF3949AB), // çivit
  Color(0xFFD81B60), // pembe
  Color(0xFF546E7A), // mavi-gri
  Color(0xFF6D4C41), // kahve
  Color(0xFF00ACC1), // turkuaz
];

/// Türkçe harfleri sadeleştirip küçültür ("Çarşı" ile "carsi" eşleşsin).
String sehiriciFold(String input) {
  const map = {
    'İ': 'i', 'I': 'i', 'ı': 'i', 'Ş': 's', 'ş': 's', 'Ğ': 'g', 'ğ': 'g', //
    'Ü': 'u', 'ü': 'u', 'Ö': 'o', 'ö': 'o', 'Ç': 'c', 'ç': 'c',
  };
  final b = StringBuffer();
  for (final r in input.runes) {
    final ch = String.fromCharCode(r);
    b.write(map[ch] ?? ch.toLowerCase());
  }
  return b.toString();
}

/// Türkçe büyük harf: i→İ, ı→I. Dart'ın `toUpperCase()` yerel ayar bilmediği
/// için "harita" → "HARITA" (noktasız) olurdu.
String sehiriciUpper(String input) =>
    input.replaceAll('i', 'İ').replaceAll('ı', 'I').toUpperCase();

/// Girdi kutusu stili: dolgulu, yuvarlak, etiket üstte kayan.
InputDecoration sehiriciInput(
  String label, {
  String? hint,
  IconData? icon,
  String? suffix,
  String? helper,
}) {
  final border = OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: AdminUi.line),
  );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    helperText: helper,
    // Uzun açıklama tek satırda "…" ile kesilmesin.
    helperMaxLines: 3,
    suffixText: suffix,
    prefixIcon: icon == null ? null : Icon(icon, size: 20),
    filled: true,
    fillColor: Colors.white,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    border: border,
    enabledBorder: border,
    focusedBorder: border.copyWith(
      borderSide: BorderSide(color: AdminUi.brand, width: 1.6),
    ),
    errorBorder: border.copyWith(
      borderSide: const BorderSide(color: Color(0xFFDC2626)),
    ),
    focusedErrorBorder: border.copyWith(
      borderSide: const BorderSide(color: Color(0xFFDC2626), width: 1.6),
    ),
  );
}

/// Bildirim: başarı yeşil, hata kırmızı; kayan, yuvarlak.
void sehiriciSnack(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        backgroundColor: error ? const Color(0xFFB91C1C) : const Color(0xFF15803D),
        duration: Duration(seconds: error ? 5 : 3),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
}

/// Onay penceresi. [destructive] true ise onay düğmesi kırmızıdır.
Future<bool> sehiriciConfirm(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Onayla',
  bool destructive = false,
  IconData? icon,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      icon: icon == null
          ? null
          : Icon(icon,
              size: 30,
              color: destructive ? const Color(0xFFDC2626) : AdminUi.brand),
      title: Text(title, textAlign: icon == null ? null : TextAlign.center),
      content: Text(message, style: const TextStyle(height: 1.4)),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: destructive ? const Color(0xFFDC2626) : AdminUi.brand,
          ),
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return result == true;
}

/// Alt sayfa aç: yüksekliği ekranın [heightFactor] kadarı, klavye açılınca
/// yukarı kayar, kaydırılarak kapanır.
Future<T?> showSehiriciSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  double heightFactor = 0.92,
  bool enableDrag = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    enableDrag: enableDrag,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final media = MediaQuery.of(ctx);
      return Padding(
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: FractionallySizedBox(
          heightFactor: heightFactor,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(26)),
            child: Material(color: AdminUi.page, child: builder(ctx)),
          ),
        ),
      );
    },
  );
}

/// Alt sayfa iskeleti: tutamaç + başlık + kaydırılan içerik + sabit alt çubuk.
class SehiriciSheetScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget child;
  final Widget? bottomBar;
  final List<Widget> actions;

  const SehiriciSheetScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    required this.child,
    this.bottomBar,
    this.actions = const [],
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          color: Colors.white,
          padding: const EdgeInsets.fromLTRB(16, 8, 6, 10),
          child: Column(
            children: [
              Container(
                width: 40,
                height: 4.5,
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              Row(
                children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 12)],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AdminUi.ink,
                          ),
                        ),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            style: const TextStyle(
                                fontSize: 12.5, color: AdminUi.muted),
                          ),
                      ],
                    ),
                  ),
                  ...actions,
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: 'Kapat',
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: AdminUi.line),
        Expanded(child: child),
        if (bottomBar != null)
          Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              border: Border(top: BorderSide(color: AdminUi.line)),
            ),
            padding: EdgeInsets.fromLTRB(
              16,
              12,
              16,
              12 + MediaQuery.of(context).padding.bottom * 0,
            ),
            child: SafeArea(top: false, child: bottomBar!),
          ),
      ],
    );
  }
}

/// Form bölümü başlığı (küçük, harfleri açık, gri).
class SehiriciFormSection extends StatelessWidget {
  final String title;
  final Widget child;
  final String? hint;

  const SehiriciFormSection({
    super.key,
    required this.title,
    required this.child,
    this.hint,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              sehiriciUpper(title),
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: AdminUi.muted,
              ),
            ),
          ),
          child,
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 6),
              child: Text(hint!,
                  style: const TextStyle(fontSize: 12, color: AdminUi.muted)),
            ),
        ],
      ),
    );
  }
}

/// Renk seçici: hazır palet + özel #RRGGBB alanı.
class SehiriciColorPicker extends StatefulWidget {
  final Color value;
  final ValueChanged<Color> onChanged;

  const SehiriciColorPicker({
    super.key,
    required this.value,
    required this.onChanged,
  });

  @override
  State<SehiriciColorPicker> createState() => _SehiriciColorPickerState();
}

class _SehiriciColorPickerState extends State<SehiriciColorPicker> {
  late final TextEditingController _hex =
      TextEditingController(text: sehiriciColorHex(widget.value));
  String? _error;

  @override
  void didUpdateWidget(covariant SehiriciColorPicker old) {
    super.didUpdateWidget(old);
    final current = sehiriciColorHex(widget.value);
    if (_hex.text.toUpperCase() != current && _error == null) {
      _hex.text = current;
    }
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final c in kSehiriciLinePalette)
              GestureDetector(
                onTap: () {
                  setState(() => _error = null);
                  _hex.text = sehiriciColorHex(c);
                  widget.onChanged(c);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: c,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: widget.value.toARGB32() == c.toARGB32()
                          ? AdminUi.ink
                          : Colors.white,
                      width: 3,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: c.withValues(alpha: 0.4),
                        blurRadius: 6,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                  child: widget.value.toARGB32() == c.toARGB32()
                      ? const Icon(Icons.check_rounded,
                          color: Colors.white, size: 20)
                      : null,
                ),
              ),
          ],
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: 190,
          child: TextField(
            controller: _hex,
            textCapitalization: TextCapitalization.characters,
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[#0-9a-fA-F]')),
              LengthLimitingTextInputFormatter(7),
            ],
            decoration: sehiriciInput(
              'Özel renk',
              hint: '#1976D2',
              icon: Icons.colorize_rounded,
            ).copyWith(
              errorText: _error,
              // Boyutsuz Container alanı doldurup yazıyı ezerdi: sabit ölçü.
              suffixIcon: Padding(
                padding: const EdgeInsets.all(12),
                child: Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: widget.value,
                    shape: BoxShape.circle,
                    border: Border.all(color: AdminUi.line),
                  ),
                ),
              ),
            ),
            onChanged: (text) {
              final t = text.startsWith('#') ? text : '#$text';
              final valid = RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(t);
              setState(() => _error = valid || t.length < 7 ? null : 'Geçersiz');
              if (valid) widget.onChanged(sehiriciParseColor(t));
            },
          ),
        ),
      ],
    );
  }
}

/// Yatay segment düğmeleri (küçük sayıda seçenek için).
class SehiriciSegmented<T> extends StatelessWidget {
  final List<({T value, String label, IconData? icon})> items;
  final T selected;
  final ValueChanged<T> onChanged;

  const SehiriciSegmented({
    super.key,
    required this.items,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          for (final item in items)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(item.value),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: item.value == selected ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: item.value == selected
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.08),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : null,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (item.icon != null) ...[
                        Icon(item.icon,
                            size: 16,
                            color: item.value == selected
                                ? AdminUi.brand
                                : AdminUi.muted),
                        const SizedBox(width: 5),
                      ],
                      Flexible(
                        child: Text(
                          item.label,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: item.value == selected
                                ? AdminUi.brand
                                : AdminUi.muted,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Arama kutusu (temizle düğmeli).
class SehiriciSearchField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  const SehiriciSearchField({
    super.key,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: sehiriciInput(hint, icon: Icons.search_rounded).copyWith(
        labelText: null,
        hintText: hint,
        suffixIcon: ValueListenableBuilder<TextEditingValue>(
          valueListenable: controller,
          builder: (_, v, __) => v.text.isEmpty
              ? const SizedBox.shrink()
              : IconButton(
                  icon: const Icon(Icons.close_rounded, size: 18),
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                ),
        ),
      ),
    );
  }
}

/// Sekme içeriği: yükleniyor / hata / boş / içerik durumlarını tek yerde yönetir.
class SehiriciAsyncBody extends StatelessWidget {
  final bool loading;
  final String? error;
  final VoidCallback? onRetry;
  final Widget child;

  const SehiriciAsyncBody({
    super.key,
    required this.loading,
    required this.error,
    required this.child,
    this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    if (error != null) {
      return AdminEmpty(
        icon: Icons.cloud_off_rounded,
        title: 'Veriler yüklenemedi',
        subtitle: error,
        action: onRetry == null
            ? null
            : FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Tekrar dene'),
                style: FilledButton.styleFrom(backgroundColor: AdminUi.brand),
              ),
      );
    }
    if (loading) {
      return const Center(child: CircularProgressIndicator());
    }
    return child;
  }
}

/// Kart içi satırlarda kullanılan küçük etiketli bilgi (ikon + metin).
class SehiriciInfoTag extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color? color;

  const SehiriciInfoTag({
    super.key,
    required this.icon,
    required this.text,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AdminUi.muted;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: c),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 12, color: c, fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}

/// Kartın altındaki eylem çubuğu düğmesi (ikonlu, kompakt).
class SehiriciCardAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final Color? color;

  const SehiriciCardAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AdminUi.brand;
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18, color: onTap == null ? AdminUi.muted : c),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w700,
          color: onTap == null ? AdminUi.muted : c,
        ),
      ),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }
}
