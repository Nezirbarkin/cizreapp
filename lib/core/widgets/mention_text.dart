import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../services/mention_service.dart';

/// @mention'ları highlight eden ve tıklanabilir yapan Text widget
class MentionText extends StatelessWidget {
  final String text;
  final TextStyle? baseStyle;
  final TextStyle? mentionStyle;
  final Function(String username)? onMentionTap;
  final TextAlign textAlign;
  final int? maxLines;
  final TextOverflow overflow;

  const MentionText(
    this.text, {
    super.key,
    this.baseStyle,
    this.mentionStyle,
    this.onMentionTap,
    this.textAlign = TextAlign.start,
    this.maxLines,
    this.overflow = TextOverflow.clip,
  });

  @override
  Widget build(BuildContext context) {
    final mentionService = MentionService();
    final spans = mentionService.getMentionSpans(text);

    if (spans.isEmpty) {
      // Mention yok, normal text
      return Text(
        text,
        style: baseStyle,
        textAlign: textAlign,
        maxLines: maxLines,
        overflow: overflow,
      );
    }

    // Mention'ları highlight et
    final textSpans = <TextSpan>[];
    int lastEnd = 0;

    for (final span in spans) {
      // Mention öncesi normal metin
      if (span.start > lastEnd) {
        textSpans.add(
          TextSpan(
            text: text.substring(lastEnd, span.start),
            style: baseStyle,
          ),
        );
      }

      // Mention - mavi renk ve gesture
      textSpans.add(
        TextSpan(
          text: span.fullText,
          style: mentionStyle ??
              TextStyle(
                color: Colors.blue.shade600,
                fontWeight: FontWeight.w600,
                decoration: TextDecoration.underline,
              ),
          recognizer: TapGestureRecognizer()
            ..onTap = () {
              onMentionTap?.call(span.username);
              debugPrint('👤 Mention tıklandı: @${span.username}');
            },
        ),
      );

      lastEnd = span.end;
    }

    // Son kalan metin
    if (lastEnd < text.length) {
      textSpans.add(
        TextSpan(
          text: text.substring(lastEnd),
          style: baseStyle,
        ),
      );
    }

    return RichText(
      text: TextSpan(children: textSpans),
      textAlign: textAlign,
      maxLines: maxLines,
      overflow: overflow,
    );
  }
}

/// Kullanıcıyı mention etme için autocomplete tooltip
class MentionAutocomplete extends StatefulWidget {
  final TextEditingController controller;
  final Function(String username, String userId)? onMentionSelected;
  final Color backgroundColor;
  final Color textColor;

  const MentionAutocomplete({
    super.key,
    required this.controller,
    this.onMentionSelected,
    this.backgroundColor = Colors.white,
    this.textColor = Colors.black87,
  });

  @override
  State<MentionAutocomplete> createState() => _MentionAutocompleteState();
}

class _MentionAutocompleteState extends State<MentionAutocomplete> {
  final mentionService = MentionService();
  List<Map<String, dynamic>> _suggestions = [];
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() async {
    final text = widget.controller.text;
    final cursorPos = widget.controller.selection.baseOffset;

    // Son @ işaretinden sonraki metni bul
    final lastAtIndex = text.lastIndexOf('@', cursorPos - 1);

    if (lastAtIndex != -1 && lastAtIndex < cursorPos - 1) {
      // @ işareti bulundu
      final query = text.substring(lastAtIndex + 1, cursorPos).trim();

      if (query.isNotEmpty && query.isNotEmpty) {
        // Kullanıcı ara
        final suggestions = await mentionService.searchMentionableUsers(query);

        if (mounted) {
          setState(() {
            _suggestions = suggestions;
            _showSuggestions = suggestions.isNotEmpty;
          });
        }
      } else {
        setState(() {
          _showSuggestions = false;
          _suggestions = [];
        });
      }
    } else {
      setState(() {
        _showSuggestions = false;
        _suggestions = [];
      });
    }
  }

  void _selectMention(String username, String userId) {
    final text = widget.controller.text;
    final cursorPos = widget.controller.selection.baseOffset;

    // Son @ işaretini bul
    final lastAtIndex = text.lastIndexOf('@', cursorPos - 1);

    if (lastAtIndex != -1) {
      // @ işaretinden sonraki metni username ile değiştir
      final newText =
          '${text.substring(0, lastAtIndex)}@$username ${text.substring(cursorPos)}';

      widget.controller.text = newText;
      widget.controller.selection =
          TextSelection.collapsed(offset: lastAtIndex + username.length + 2);

      widget.onMentionSelected?.call(username, userId);

      setState(() {
        _showSuggestions = false;
        _suggestions = [];
      });

      debugPrint('✅ Mention seçildi: @$username');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_showSuggestions || _suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      decoration: BoxDecoration(
        color: widget.backgroundColor,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            // ignore: deprecated_member_use
            color: Colors.black.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      constraints: const BoxConstraints(maxHeight: 200),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: _suggestions.length,
        itemBuilder: (context, index) {
          final user = _suggestions[index];
          final username = user['username'] ?? 'Kullanıcı';
          final fullName = user['full_name'] ?? username;
          final avatarUrl = user['avatar_url'];

          return ListTile(
            onTap: () => _selectMention(username, user['id']),
            leading: CircleAvatar(
              backgroundImage: avatarUrl != null
                  ? NetworkImage(avatarUrl)
                  : const AssetImage('assets/default_avatar.png')
                      as ImageProvider,
              child: avatarUrl == null
                  ? const Icon(Icons.person, size: 18)
                  : null,
            ),
            title: Text(
              '@$username',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: widget.textColor,
              ),
            ),
            subtitle: Text(
              fullName,
              style: const TextStyle(fontSize: 12),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          );
        },
      ),
    );
  }
}
