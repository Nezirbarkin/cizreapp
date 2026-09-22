import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart' show TapGestureRecognizer;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/providers/theme_provider.dart';

/// Giriş / kayıt / şifre sıfırlama ekranlarının ortak görsel dili.
///
/// Bu dosyadaki her şey tek bir kuralı izler: renkler `ThemeProvider`'ın
/// seçili marka renginden ve `Theme.of(context).brightness`'tan türetilir.
/// Böylece kullanıcı temayı (yeşil / mavi / pembe) veya koyu modu
/// değiştirdiğinde auth ekranları da uygulamanın geri kalanıyla birlikte
/// değişir; eskiden olduğu gibi turkuaz/mavi sabit kodlu kalmaz.

/// Marka renginden türetilmiş, açık/koyu moda duyarlı renk paleti.
class AuthPalette {
  const AuthPalette({
    required this.isDark,
    required this.brand,
    required this.accent,
    required this.band,
    required this.onBand,
    required this.onBandSoft,
    required this.sheet,
    required this.field,
    required this.text,
    required this.textSoft,
    required this.textMuted,
    required this.border,
    required this.danger,
    required this.success,
    required this.warning,
  });

  /// Koyu tema aktif mi.
  final bool isDark;

  /// Ham marka rengi — dolu butonlar için.
  final Color brand;

  /// Metin/ikon üzerindeki marka vurgusu. Koyu temada okunabilirlik için
  /// [brand]'den daha açıktır.
  final Color accent;

  /// Üst bandın rengi.
  final Color band;
  final Color onBand;
  final Color onBandSoft;

  /// Bandın üzerine binen yüzey.
  final Color sheet;
  final Color field;
  final Color text;
  final Color textSoft;
  final Color textMuted;
  final Color border;
  final Color danger;
  final Color success;
  final Color warning;

  /// [listen] yalnızca `build` içinde true olmalıdır. SnackBar gösterimi gibi
  /// build dışı çağrılarda `context.watch` istisna fırlatacağından `false`
  /// geçilir.
  factory AuthPalette.of(BuildContext context, {bool listen = true}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final brand = Provider.of<ThemeProvider>(
      context,
      listen: listen,
    ).primaryColor;

    return AuthPalette(
      isDark: isDark,
      brand: brand,
      accent: isDark ? _shade(brand, 0.18) : brand,
      band: isDark ? _shade(brand, -0.16) : brand,
      onBand: Colors.white,
      onBandSoft: Colors.white.withValues(alpha: 0.78),
      sheet: isDark ? const Color(0xFF181818) : Colors.white,
      field: isDark ? const Color(0xFF262626) : const Color(0xFFF4F5F7),
      text: isDark ? const Color(0xFFF5F5F5) : const Color(0xFF1A1A1A),
      textSoft: isDark ? const Color(0xFFD1D5DB) : const Color(0xFF4B5563),
      textMuted: isDark ? const Color(0xFF9CA3AF) : const Color(0xFF8A8F98),
      border: isDark ? const Color(0xFF3A3A3A) : const Color(0xFFE5E7EB),
      danger: isDark ? const Color(0xFFF87171) : const Color(0xFFDC2626),
      success: isDark ? const Color(0xFF4ADE80) : const Color(0xFF16A34A),
      warning: isDark ? const Color(0xFFFBBF24) : const Color(0xFFB45309),
    );
  }

  /// Bir rengin açıklığını [amount] kadar kaydırır (negatif = koyulaştırır).
  static Color _shade(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }
}

/// Auth ekranlarının ortak iskeleti: marka renkli üst bant + üzerine binen
/// yuvarlak köşeli yüzey.
///
/// Yüzeyin üst köşeleri `Scaffold`'un bant rengindeki arka planını gösterdiği
/// için ekstra bir üst üste binme hilesine gerek kalmaz. İçerik
/// `CustomScrollView` içinde olduğundan klavye açıldığında bant yukarı kayar
/// ve alanlar görünür kalır.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.showLogo = false,
    this.stepIndex,
    this.stepCount,
    this.onBack,
    this.footer,
  });

  final String title;
  final String? subtitle;

  /// Bandın üstünde uygulama logosunu göster (giriş ekranı).
  final bool showLogo;

  /// 1 tabanlı adım numarası; [stepCount] ile birlikte ilerleme çubuğunu çizer.
  final int? stepIndex;
  final int? stepCount;

  /// Bantta sol üstte geri oku gösterir.
  final VoidCallback? onBack;

  /// Yüzeyin en altına sabitlenen içerik (ör. "Hesabın yok mu? Kayıt ol").
  final Widget? footer;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final p = AuthPalette.of(context);

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: p.band,
        body: SafeArea(
          bottom: false,
          child: CustomScrollView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(child: _buildBand(context, p)),

              // Yüzey doğal yüksekliğiyle çizilir: içerik ekrandan uzunsa
              // (kısa telefonlar, klavye açıkken) taşmak yerine kayar.
              // `SliverFillRemaining(hasScrollBody: false)` çocuğunu kalan
              // alana sıkıştırdığı için burada kullanılamaz — taşma verir.
              SliverToBoxAdapter(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: p.sheet,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  padding: EdgeInsets.fromLTRB(
                    24,
                    24,
                    24,
                    24 + MediaQuery.paddingOf(context).bottom,
                  ),
                  child: _constrained(
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        child,
                        if (footer != null) ...[
                          const SizedBox(height: 20),
                          footer!,
                        ],
                      ],
                    ),
                  ),
                ),
              ),

              // İçerik kısaysa yüzey rengini ekranın altına kadar uzatır;
              // uzunsa sıfır yükseklik alır.
              SliverFillRemaining(
                hasScrollBody: false,
                child: ColoredBox(color: p.sheet),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Geniş ekranlarda (web / tablet) içeriği okunabilir bir genişlikte tutar.
  ///
  /// İçteki `SizedBox` şart: `Center` tek başına çocuğu daraltır ve banttaki
  /// sola hizalı başlık ortaya kayardı.
  static Widget _constrained(Widget child) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }

  Widget _buildBand(BuildContext context, AuthPalette p) {
    final hasSteps = stepIndex != null && stepCount != null;

    return Padding(
      padding: EdgeInsets.fromLTRB(20, onBack != null ? 4 : 16, 20, 28),
      child: _constrained(
        Column(
          crossAxisAlignment: showLogo
              ? CrossAxisAlignment.center
              : CrossAxisAlignment.start,
          children: [
            if (onBack != null)
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  onPressed: onBack,
                  icon: Icon(Icons.arrow_back_rounded, color: p.onBand),
                  tooltip: 'Geri',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 40,
                    minHeight: 40,
                  ),
                ),
              ),
            if (showLogo) ...[const AuthLogoMark(), const SizedBox(height: 12)],
            Text(
              title,
              textAlign: showLogo ? TextAlign.center : TextAlign.start,
              style: TextStyle(
                color: p.onBand,
                fontSize: showLogo ? 24 : 21,
                fontWeight: FontWeight.w700,
                letterSpacing: -0.2,
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                textAlign: showLogo ? TextAlign.center : TextAlign.start,
                style: TextStyle(
                  color: p.onBandSoft,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
            if (hasSteps) ...[
              const SizedBox(height: 14),
              Row(
                children: List.generate(stepCount!, (i) {
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(
                        right: i == stepCount! - 1 ? 0 : 6,
                      ),
                      decoration: BoxDecoration(
                        color: i < stepIndex!
                            ? p.onBand
                            : p.onBand.withValues(alpha: 0.32),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  );
                }),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Uygulama logosu. Kaynak görselin (aslında JPEG olan `app_logo.png`)
/// etrafındaki opak siyah çerçeveyi kırpmak için hafifçe büyütülüp yeniden
/// yuvarlatılır; bandın üzerinde okunması için beyaz bir kutu içine alınır.
class AuthLogoMark extends StatelessWidget {
  const AuthLogoMark({super.key, this.size = 76});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.08),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.24),
        child: Transform.scale(
          scale: 1.14,
          child: Image.asset(
            'assets/logos/app_logo.png',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          ),
        ),
      ),
    );
  }
}

/// Auth ekranlarının ortak metin alanı.
class AuthField extends StatelessWidget {
  const AuthField({
    super.key,
    required this.controller,
    required this.hint,
    required this.icon,
    this.validator,
    this.onChanged,
    this.onSubmitted,
    this.obscure = false,
    this.onToggleObscure,
    this.suffix,
    this.keyboardType,
    this.inputFormatters,
    this.textInputAction,
    this.autofillHints,
    this.focusNode,
    this.helper,
    this.helperColor,
    this.enabled = true,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final String? Function(String?)? validator;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final bool obscure;
  final VoidCallback? onToggleObscure;
  final Widget? suffix;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final TextInputAction? textInputAction;
  final Iterable<String>? autofillHints;
  final FocusNode? focusNode;

  /// Alanın altında gösterilen açıklama. Eski tasarımdaki büyük satır içi
  /// uyarı kutularının yerini alır.
  final String? helper;
  final Color? helperColor;
  final bool enabled;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final p = AuthPalette.of(context);

    OutlineInputBorder border(Color color, double width) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: width == 0
          ? BorderSide.none
          : BorderSide(color: color, width: width),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: controller,
          focusNode: focusNode,
          validator: validator,
          onChanged: onChanged,
          onFieldSubmitted: onSubmitted,
          obscureText: obscure,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          textInputAction: textInputAction,
          autofillHints: autofillHints,
          enabled: enabled,
          autofocus: autofocus,
          style: TextStyle(fontSize: 15, color: p.text),
          cursorColor: p.accent,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: p.textMuted, fontSize: 14),
            prefixIcon: Icon(icon, color: p.accent, size: 20),
            suffixIcon:
                suffix ??
                (onToggleObscure != null
                    ? IconButton(
                        onPressed: onToggleObscure,
                        icon: Icon(
                          obscure
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          size: 20,
                          color: p.textMuted,
                        ),
                        tooltip: obscure ? 'Şifreyi göster' : 'Şifreyi gizle',
                      )
                    : null),
            filled: true,
            fillColor: p.field,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 16,
            ),
            border: border(Colors.transparent, 0),
            enabledBorder: border(Colors.transparent, 0),
            focusedBorder: border(p.accent, 1.5),
            errorBorder: border(p.danger, 1),
            focusedErrorBorder: border(p.danger, 1.5),
            errorStyle: TextStyle(color: p.danger, fontSize: 12),
          ),
        ),
        if (helper != null)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 6),
            child: Text(
              helper!,
              style: TextStyle(
                fontSize: 12,
                height: 1.35,
                color: helperColor ?? p.textMuted,
              ),
            ),
          ),
      ],
    );
  }
}

/// Dolu marka renkli birincil buton.
class AuthPrimaryButton extends StatelessWidget {
  const AuthPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final p = AuthPalette.of(context);
    final enabled = onPressed != null && !isLoading;

    return SizedBox(
      width: double.infinity,
      height: 54,
      child: ElevatedButton(
        onPressed: enabled ? onPressed : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: p.brand,
          foregroundColor: Colors.white,
          disabledBackgroundColor: p.brand.withValues(
            alpha: p.isDark ? 0.28 : 0.38,
          ),
          disabledForegroundColor: Colors.white.withValues(alpha: 0.75),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 18),
                    const SizedBox(width: 8),
                  ],
                  // Uzun etiket ya da yüksek metin ölçeğinde taşmamak için
                  // esnek: satır sığmazsa kısaltılır.
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Google / Apple gibi sağlayıcılar için çerçeveli buton.
class AuthSocialButton extends StatelessWidget {
  const AuthSocialButton({
    super.key,
    required this.label,
    required this.icon,
    required this.onPressed,
    this.iconColor,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final p = AuthPalette.of(context);

    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          foregroundColor: p.text,
          side: BorderSide(color: p.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: iconColor ?? p.text),
            const SizedBox(width: 10),
            Text(
              label,
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

/// Apple ile Giriş yalnızca Apple platformlarında sunulur; diğer yerlerde
/// sağlayıcı zaten çalışmaz.
bool get authAppleSignInAvailable {
  if (kIsWeb) return false;
  return Platform.isIOS || Platform.isMacOS;
}

/// "veya" ayracı.
class AuthDivider extends StatelessWidget {
  const AuthDivider({super.key, this.label = 'veya'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final p = AuthPalette.of(context);

    return Row(
      children: [
        Expanded(child: Divider(color: p.border, height: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            label,
            style: TextStyle(fontSize: 12, color: p.textMuted),
          ),
        ),
        Expanded(child: Divider(color: p.border, height: 1)),
      ],
    );
  }
}

/// Onay kutusu satırı. Altı çizili bağlantı metni [onLinkTap]'i açar, satırın
/// geri kalanına dokunmak onay kutusunu değiştirir.
///
/// `TapGestureRecognizer` `build` içinde üretilirse dispose edilmediği için
/// sızdırır; bu yüzden widget stateful ve tanıyıcının ömrü burada yönetilir.
class AuthConsentRow extends StatefulWidget {
  const AuthConsentRow({
    super.key,
    required this.value,
    required this.onChanged,
    required this.linkText,
    required this.restText,
    required this.onLinkTap,
  });

  final bool value;
  final ValueChanged<bool> onChanged;
  final String linkText;
  final String restText;
  final VoidCallback onLinkTap;

  @override
  State<AuthConsentRow> createState() => _AuthConsentRowState();
}

class _AuthConsentRowState extends State<AuthConsentRow> {
  late final TapGestureRecognizer _linkRecognizer;

  @override
  void initState() {
    super.initState();
    _linkRecognizer = TapGestureRecognizer()..onTap = () => widget.onLinkTap();
  }

  @override
  void dispose() {
    _linkRecognizer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = AuthPalette.of(context);

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 24,
          height: 24,
          child: Checkbox(
            value: widget.value,
            onChanged: (v) => widget.onChanged(v ?? false),
            activeColor: p.brand,
            side: BorderSide(color: p.textMuted, width: 1.4),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(5),
            ),
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onChanged(!widget.value),
            child: Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text.rich(
                TextSpan(
                  style: TextStyle(
                    fontSize: 13,
                    color: p.textSoft,
                    height: 1.4,
                  ),
                  children: [
                    TextSpan(
                      text: widget.linkText,
                      style: TextStyle(
                        color: p.accent,
                        fontWeight: FontWeight.w600,
                        decoration: TextDecoration.underline,
                        decorationColor: p.accent,
                      ),
                      recognizer: _linkRecognizer,
                    ),
                    TextSpan(text: widget.restText),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// 6 haneli OTP giriş satırı.
///
/// Kutular `Expanded` olduğu için dar ekranlarda taşmaz, yapıştırılan kodu
/// otomatik dağıtır ve geri silmede bir önceki kutuya döner. Eskiden
/// kullanılan `RawKeyboardListener` yerine güncel `KeyboardListener`
/// kullanılır.
class AuthOtpInput extends StatefulWidget {
  const AuthOtpInput({
    super.key,
    required this.controllers,
    required this.focusNodes,
    this.onChanged,
    this.onCompleted,
  });

  final List<TextEditingController> controllers;
  final List<FocusNode> focusNodes;
  final VoidCallback? onChanged;
  final VoidCallback? onCompleted;

  @override
  State<AuthOtpInput> createState() => _AuthOtpInputState();
}

class _AuthOtpInputState extends State<AuthOtpInput> {
  late final List<FocusNode> _keyNodes;

  int get _count => widget.controllers.length;

  @override
  void initState() {
    super.initState();
    _keyNodes = List.generate(_count, (_) => FocusNode(skipTraversal: true));
    for (final node in widget.focusNodes) {
      node.addListener(_onFocusChanged);
    }
  }

  @override
  void dispose() {
    for (final node in widget.focusNodes) {
      node.removeListener(_onFocusChanged);
    }
    for (final node in _keyNodes) {
      node.dispose();
    }
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted) setState(() {});
  }

  String get _code => widget.controllers.map((c) => c.text).join();

  void _handleChanged(int index, String value) {
    if (value.length > 1) {
      _distribute(index, value.replaceAll(RegExp(r'\D'), ''));
      return;
    }

    if (value.isNotEmpty && index < _count - 1) {
      widget.focusNodes[index + 1].requestFocus();
    }

    setState(() {});
    widget.onChanged?.call();

    if (_code.length == _count) {
      FocusScope.of(context).unfocus();
      widget.onCompleted?.call();
    }
  }

  /// Yapıştırılan (ya da hızlı yazılan) rakamları [start]'tan itibaren dağıtır.
  void _distribute(int start, String digits) {
    var index = start;
    for (final char in digits.split('')) {
      if (index >= _count) break;
      widget.controllers[index].value = TextEditingValue(
        text: char,
        selection: const TextSelection.collapsed(offset: 1),
      );
      index++;
    }

    if (index >= _count) {
      FocusScope.of(context).unfocus();
    } else {
      widget.focusNodes[index].requestFocus();
    }

    setState(() {});
    widget.onChanged?.call();
    if (_code.length == _count) widget.onCompleted?.call();
  }

  void _handleKey(int index, KeyEvent event) {
    if (event is! KeyDownEvent) return;
    if (event.logicalKey != LogicalKeyboardKey.backspace) return;
    if (widget.controllers[index].text.isNotEmpty || index == 0) return;

    widget.controllers[index - 1].clear();
    widget.focusNodes[index - 1].requestFocus();
    setState(() {});
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final p = AuthPalette.of(context);

    return Row(
      children: List.generate(_count, (i) {
        final isFocused = widget.focusNodes[i].hasFocus;
        final isFilled = widget.controllers[i].text.isNotEmpty;

        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: i == _count - 1 ? 0 : 8),
            child: AspectRatio(
              aspectRatio: 0.78,
              child: Container(
                decoration: BoxDecoration(
                  color: p.field,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isFocused
                        ? p.accent
                        : (isFilled ? p.border : Colors.transparent),
                    width: isFocused ? 1.8 : 1,
                  ),
                ),
                child: KeyboardListener(
                  focusNode: _keyNodes[i],
                  onKeyEvent: (event) => _handleKey(i, event),
                  child: TextField(
                    controller: widget.controllers[i],
                    focusNode: widget.focusNodes[i],
                    textAlign: TextAlign.center,
                    textAlignVertical: TextAlignVertical.center,
                    keyboardType: TextInputType.number,
                    autofillHints: i == 0
                        ? const [AutofillHints.oneTimeCode]
                        : null,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: p.text,
                    ),
                    cursorColor: p.accent,
                    decoration: const InputDecoration(
                      counterText: '',
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                    ),
                    onChanged: (value) => _handleChanged(i, value),
                  ),
                ),
              ),
            ),
          ),
        );
      }),
    );
  }
}

/// Şifre gücü değerlendirmesi.
class AuthPasswordStrength {
  const AuthPasswordStrength(this.level, this.label, this.hint);

  /// 0 = boş, 1 = zayıf, 2 = orta, 3 = güçlü.
  final int level;
  final String label;
  final String? hint;

  static AuthPasswordStrength of(String password) {
    if (password.isEmpty) return const AuthPasswordStrength(0, '', null);
    if (password.length < 6) {
      return const AuthPasswordStrength(1, 'Zayıf', 'En az 6 karakter gerekli');
    }

    final hasDigit = RegExp(r'\d').hasMatch(password);
    final hasSymbol = RegExp(r'[^A-Za-z0-9ÇĞİÖŞÜçğıöşü]').hasMatch(password);
    final hasMixedCase =
        RegExp(r'[A-ZÇĞİÖŞÜ]').hasMatch(password) &&
        RegExp(r'[a-zçğıöşü]').hasMatch(password);
    final hasLetter = RegExp(r'[A-Za-zÇĞİÖŞÜçğıöşü]').hasMatch(password);

    var score = 0;
    if (password.length >= 8) score++;
    if (password.length >= 12) score++;
    if (hasLetter && hasDigit) score++;
    if (hasMixedCase) score++;
    if (hasSymbol) score++;

    if (score >= 4) return const AuthPasswordStrength(3, 'Güçlü', null);
    if (score >= 2) {
      return AuthPasswordStrength(
        2,
        'Orta',
        hasSymbol
            ? 'Daha uzun olursa daha güçlü olur'
            : 'Noktalama işareti eklersen daha güçlü olur',
      );
    }
    return AuthPasswordStrength(
      1,
      'Zayıf',
      hasDigit ? 'Daha uzun bir şifre seç' : 'Bir rakam ekle',
    );
  }
}

/// Şifre gücünü gösteren üç bölmeli çubuk.
class AuthPasswordStrengthBar extends StatelessWidget {
  const AuthPasswordStrengthBar({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    final p = AuthPalette.of(context);
    final strength = AuthPasswordStrength.of(password);

    if (strength.level == 0) return const SizedBox.shrink();

    final color = switch (strength.level) {
      3 => p.success,
      2 => p.warning,
      _ => p.danger,
    };

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(3, (i) {
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(right: i == 2 ? 0 : 6),
                  decoration: BoxDecoration(
                    color: i < strength.level ? color : p.border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          Text(
            strength.hint == null
                ? strength.label
                : '${strength.label} — ${strength.hint}',
            style: TextStyle(fontSize: 12, color: color),
          ),
        ],
      ),
    );
  }
}

/// Auth ekranlarının alt bağlantısı ("Hesabın yok mu? Kayıt ol").
class AuthFooterLink extends StatelessWidget {
  const AuthFooterLink({
    super.key,
    required this.question,
    required this.action,
    required this.onPressed,
  });

  final String question;
  final String action;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final p = AuthPalette.of(context);

    // `Wrap`: dar ekranda veya büyük metin ölçeğinde soru ve bağlantı alt
    // alta geçer, `Row` gibi taşmaz.
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(question, style: TextStyle(color: p.textMuted, fontSize: 13)),
        TextButton(
          onPressed: onPressed,
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: p.accent,
          ),
          child: Text(
            action,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          ),
        ),
      ],
    );
  }
}

/// Auth ekranlarının ortak hata bildirimi.
void showAuthError(BuildContext context, String message) {
  final p = AuthPalette.of(context, listen: false);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: p.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
}

/// Auth ekranlarının ortak başarı bildirimi.
void showAuthSuccess(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 4),
}) {
  final p = AuthPalette.of(context, listen: false);
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: p.success,
        behavior: SnackBarBehavior.floating,
        duration: duration,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
}
