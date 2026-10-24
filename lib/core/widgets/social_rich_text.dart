import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../utils/hashtags.dart';

final RegExp _mentionPattern = RegExp(r'@(\w+)');

/// Gönderi / yorum metni: `#etiket`ler vurgulu ve dokunulabilir.
///
/// Etiket yoksa düz [Text] döner (testler ve erişilebilirlik için metin
/// birebir aynı kalır). Dokunma tanıyıcıları widget'la birlikte bırakılır.
class SocialRichText extends StatefulWidget {
  const SocialRichText(
    this.text, {
    super.key,
    this.style,
    this.maxLines,
    this.overflow,
    this.onHashtagTap,
    this.tagColor,
    this.boldMentions = false,
  });

  final String text;
  final TextStyle? style;
  final int? maxLines;
  final TextOverflow? overflow;

  /// Katlanmış etiketle çağrılır (ör. "cizre"); null ise etiket yalnız renkli.
  final ValueChanged<String>? onHashtagTap;
  final Color? tagColor;

  /// true: `@kullanici` kalın yazılır (yorumlar).
  final bool boldMentions;

  @override
  State<SocialRichText> createState() => _SocialRichTextState();
}

class _SocialRichTextState extends State<SocialRichText> {
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final text = widget.text;
    final matches = <Match>[
      ...hashtagPattern.allMatches(text),
      if (widget.boldMentions) ..._mentionPattern.allMatches(text),
    ]..sort((a, b) => a.start.compareTo(b.start));
    if (matches.isEmpty) {
      return Text(
        text,
        style: widget.style,
        maxLines: widget.maxLines,
        overflow: widget.overflow,
      );
    }

    final tagStyle = TextStyle(
      color: widget.tagColor ?? const Color(0xFF1D9BF0),
      fontWeight: FontWeight.w600,
    );
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in matches) {
      if (m.start < last) continue; // çakışan eşleşme
      if (m.start > last) spans.add(TextSpan(text: text.substring(last, m.start)));
      if (m.pattern == _mentionPattern) {
        spans.add(TextSpan(
          text: text.substring(m.start, m.end),
          style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ));
        last = m.end;
        continue;
      }
      final tag = foldHashtag(m.group(1)!);
      TapGestureRecognizer? recognizer;
      if (widget.onHashtagTap != null) {
        recognizer = TapGestureRecognizer()..onTap = () => widget.onHashtagTap!(tag);
        _recognizers.add(recognizer);
      }
      spans.add(TextSpan(
        text: text.substring(m.start, m.end),
        style: tagStyle,
        recognizer: recognizer,
      ));
      last = m.end;
    }
    if (last < text.length) spans.add(TextSpan(text: text.substring(last)));

    return Text.rich(
      TextSpan(children: spans),
      style: widget.style,
      maxLines: widget.maxLines,
      overflow: widget.overflow,
    );
  }
}
