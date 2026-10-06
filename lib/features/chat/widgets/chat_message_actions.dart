import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chat_bubble.dart';

enum _ChatMessageAction { copy, select, reply }

/// Mesaja uzun basınca açılan menü: Kopyala, Metni seç, Yanıtla.
///
/// Balon yazıları düz [Text]'tir (kaydırarak yanıtlama ve dokunma
/// hareketleriyle çakışmasın diye seçilebilir yapılmadı); kopyalama bu
/// menüden yapılır. "Metni seç" mesajın yalnız bir parçasını kopyalamak için
/// yazıyı seçilebilir bir pencerede açar. Yazı kutusuna yapıştırma zaten
/// sistemin kendi menüsüyle çalışır.
abstract final class ChatMessageActions {
  static Future<void> show(
    BuildContext context, {
    required String text,
    VoidCallback? onReply,
  }) async {
    HapticFeedback.selectionClick();
    final action = await showModalBottomSheet<_ChatMessageAction>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                text,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 14, color: Color(0xFF6B6680)),
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.copy_rounded, color: ChatPalette.accent),
              title: const Text('Kopyala'),
              onTap: () => Navigator.pop(sheetContext, _ChatMessageAction.copy),
            ),
            ListTile(
              leading: const Icon(
                Icons.text_fields_rounded,
                color: ChatPalette.accent,
              ),
              title: const Text('Metni seç'),
              onTap: () => Navigator.pop(sheetContext, _ChatMessageAction.select),
            ),
            if (onReply != null)
              ListTile(
                leading: const Icon(Icons.reply_rounded, color: ChatPalette.accent),
                title: const Text('Yanıtla'),
                onTap: () => Navigator.pop(sheetContext, _ChatMessageAction.reply),
              ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
    if (!context.mounted || action == null) return;
    switch (action) {
      case _ChatMessageAction.copy:
        await copy(context, text);
      case _ChatMessageAction.select:
        await _showSelectable(context, text);
      case _ChatMessageAction.reply:
        onReply?.call();
    }
  }

  static Future<void> copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Mesaj kopyalandı'),
          duration: Duration(seconds: 2),
        ),
      );
  }

  static Future<void> _showSelectable(BuildContext context, String text) {
    return showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Metni seç'),
        content: SingleChildScrollView(
          child: SelectableText(
            text,
            style: const TextStyle(
              fontSize: 15.5,
              height: 1.35,
              color: ChatPalette.text,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Kapat'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              copy(context, text);
            },
            child: const Text('Tümünü kopyala'),
          ),
        ],
      ),
    );
  }
}
