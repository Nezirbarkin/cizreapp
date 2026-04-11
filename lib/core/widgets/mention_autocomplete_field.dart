// ignore_for_file: deprecated_member_use, unused_field

import 'package:flutter/material.dart';
import '../services/mention_service.dart';

/// Mention desteği ile TextField
/// @kullaniciadi yazınca otomatik tamamlama önerileri gösterir
class MentionAutocompleteField extends StatefulWidget {
  final TextEditingController controller;
  final InputDecoration? decoration;
  final int? maxLines;
  final bool obscureText;
  final TextInputType? keyboardType;
  final TextStyle? style;
  final TextCapitalization textCapitalization;

  const MentionAutocompleteField({
    super.key,
    required this.controller,
    this.decoration,
    this.maxLines,
    this.obscureText = false,
    this.keyboardType,
    this.style,
    this.textCapitalization = TextCapitalization.none,
  });

  @override
  State<MentionAutocompleteField> createState() => _MentionAutocompleteFieldState();
}

class _MentionAutocompleteFieldState extends State<MentionAutocompleteField> {
  final MentionService _mentionService = MentionService();
  final LayerLink _layerLink = LayerLink();
  final GlobalKey _textFieldKey = GlobalKey();
  OverlayEntry? _overlayEntry;
  List<Map<String, dynamic>> _suggestions = [];
  bool _showSuggestions = false;
  String? _currentMentionQuery;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _removeOverlay();
    super.dispose();
  }

  void _onTextChanged() {
    final text = widget.controller.text;
    final cursorPos = widget.controller.selection.baseOffset;

    debugPrint('🔍 Text changed: "$text", cursorPos: $cursorPos');

    // Son @ işaretinden sonraki metni bul
    final lastAtIndex = text.lastIndexOf('@', cursorPos);

    debugPrint('📍 Last @ index: $lastAtIndex');

    if (lastAtIndex != -1) {
      // @ işareti bulundu
      final query = text.substring(lastAtIndex + 1, cursorPos).trim();

      debugPrint('🔎 Query: "$query"');

      // Boşluk varsa @mention sona erdi
      if (query.isEmpty && cursorPos > lastAtIndex + 1) {
        _hideSuggestions();
        return;
      }

      if (query.isNotEmpty) {
        _currentMentionQuery = query;
        _performUserSearch(query);
      } else {
        // @ yazıldı ama henüz query yok
        debugPrint('⏳ @ yazıldı, query bekleniyor');
      }
    } else {
      _hideSuggestions();
    }
  }

  Future<void> _performUserSearch(String query) async {
    debugPrint('🔍 Searching for: "$query"');
    
    // Kullanıcı ara
    final suggestions = await _mentionService.searchMentionableUsers(query);

    debugPrint('📋 Found ${suggestions.length} users');

    if (mounted && _currentMentionQuery == query) {
      setState(() {
        _suggestions = suggestions;
        _showSuggestions = suggestions.isNotEmpty;
      });
      if (_showSuggestions) {
        debugPrint('✅ Showing overlay with ${suggestions.length} suggestions');
        _showOverlay();
      } else {
        debugPrint('❌ No suggestions, hiding overlay');
        _removeOverlay();
      }
    }
  }

  void _hideSuggestions() {
    _currentMentionQuery = null;
    if (_showSuggestions) {
      setState(() {
        _showSuggestions = false;
        _suggestions = [];
      });
      _removeOverlay();
    }
  }

  void _showOverlay() {
    _removeOverlay();

    debugPrint('🎨 Creating overlay...');

    // TextField'in pozisyonunu al
    final RenderBox? renderBox =
        _textFieldKey.currentContext?.findRenderObject() as RenderBox?;
    
    if (renderBox == null) {
      debugPrint('❌ RenderBox null!');
      return;
    }

    final size = renderBox.size;
    final offset = renderBox.localToGlobal(Offset.zero);

    debugPrint('📐 TextField pos: ${offset.dx}, ${offset.dy}, size: ${size.width}x${size.height}');

    // Overlay yüksekliğini hesapla (her item ~60px)
    final estimatedHeight = _suggestions.length * 60.0;
    final maxHeight = 200.0;
    final overlayHeight = estimatedHeight > maxHeight ? maxHeight : estimatedHeight;

    _overlayEntry = OverlayEntry(
      builder: (context) => Stack(
        children: [
          Positioned(
            left: offset.dx,
            top: offset.dy - overlayHeight - 5, // TextField'in ÜSTÜNE
            width: size.width,
            child: Material(
              elevation: 8,
              borderRadius: BorderRadius.circular(12),
              color: Colors.transparent,
              child: Container(
                constraints: const BoxConstraints(maxHeight: 200, minWidth: 200),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF2C2C2C)
                      : Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: _suggestions.length,
                  itemBuilder: (context, index) {
                    final user = _suggestions[index];
                    final username = user['username'] ?? 'Kullanıcı';
                    final fullName = user['full_name'] ?? username;
                    final avatarUrl = user['avatar_url'];

                    debugPrint('👤 User $index: @$username ($fullName)');

                    return InkWell(
                      onTap: () => _selectMention(username, user['id']),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundImage: avatarUrl != null
                                  ? NetworkImage(avatarUrl)
                                  : null,
                              child: avatarUrl == null
                                  ? const Icon(Icons.person, size: 16)
                                  : null,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '@$username',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: Colors.black,
                                    ),
                                  ),
                                  if (fullName != username) ...[
                                    const SizedBox(height: 2),
                                    Text(
                                      fullName,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context).brightness == Brightness.dark
                                            ? Colors.grey[400]
                                            : Colors.grey[600],
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ],
      ),
    );

    _insertOverlay();
    debugPrint('✅ Overlay created and inserted');
  }

  void _insertOverlay() {
    final overlay = Overlay.of(context);
    overlay.insert(_overlayEntry!);
    debugPrint('✅ Overlay inserted to overlay layer');
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  void _selectMention(String username, String userId) {
    final text = widget.controller.text;
    final cursorPos = widget.controller.selection.baseOffset;

    // Son @ işaretini bul
    final lastAtIndex = text.lastIndexOf('@', cursorPos);

    if (lastAtIndex != -1) {
      // @ işaretinden sonraki metni username ile değiştir
      final newText =
          '${text.substring(0, lastAtIndex)}@$username ${text.substring(cursorPos)}';

      widget.controller.text = newText;
      widget.controller.selection =
          TextSelection.collapsed(offset: lastAtIndex + username.length + 2);

      _hideSuggestions();

      debugPrint('✅ Mention seçildi: @$username');
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      key: _textFieldKey,
      controller: widget.controller,
      decoration: widget.decoration,
      maxLines: widget.maxLines,
      obscureText: widget.obscureText,
      keyboardType: widget.keyboardType,
      style: widget.style,
      textCapitalization: widget.textCapitalization,
    );
  }
}
