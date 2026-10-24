import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/models/post_model.dart';
import '../../../core/utils/app_error_handler.dart';
import '../services/post_service.dart';

/// Gönderi metnini düzenleme sayfası. Kaydedilirse güncellenmiş [Post] döner
/// (sunucu `edited_at`'i damgalar; kartta "düzenlendi" yazar).
Future<Post?> showEditPostSheet(
  BuildContext context,
  Post post, {
  PostService? service,
}) {
  return showModalBottomSheet<Post>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => EditPostSheet(post: post, service: service),
  );
}

class EditPostSheet extends StatefulWidget {
  const EditPostSheet({super.key, required this.post, this.service});

  final Post post;
  final PostService? service;

  /// Oluşturma ekranıyla aynı sınır (create_post_screen).
  static const int maxLength = 500;

  @override
  State<EditPostSheet> createState() => _EditPostSheetState();
}

class _EditPostSheetState extends State<EditPostSheet> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.post.content ?? '');
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _changed => _controller.text.trim() != (widget.post.content ?? '').trim();

  bool get _canSave =>
      !_saving &&
      _changed &&
      (_controller.text.trim().isNotEmpty || widget.post.images.isNotEmpty);

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final updated = await (widget.service ?? PostService())
          .updatePostContent(widget.post, _controller.text);
      if (mounted) Navigator.of(context).pop(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = AppErrorHandler.handleError(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Gönderiyi düzenle',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                      ),
                    ),
                    TextButton(
                      onPressed: _saving ? null : () => Navigator.of(context).pop(),
                      child: const Text('Vazgeç'),
                    ),
                    const SizedBox(width: 4),
                    FilledButton(
                      onPressed: _canSave ? _save : null,
                      child: _saving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Text('Kaydet'),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  minLines: 4,
                  maxLines: 10,
                  maxLength: EditPostSheet.maxLength,
                  inputFormatters: [
                    LengthLimitingTextInputFormatter(EditPostSheet.maxLength),
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Ne düşünüyorsun? #etiket ekleyebilirsin',
                    filled: true,
                    fillColor: const Color(0xFFF4F6F8),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
                Row(
                  children: [
                    Icon(Icons.info_outline_rounded, size: 14, color: Colors.grey.shade500),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        'Düzenlenen gönderide "düzenlendi" yazar. Fotoğraflar değiştirilemez.',
                        style: TextStyle(fontSize: 11.5, color: Colors.grey.shade600),
                      ),
                    ),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      _error!,
                      style: TextStyle(color: Colors.red.shade700, fontWeight: FontWeight.w600),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
