import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Göndermeden önce fotoğraf önizlemesi + açıklama (Görev 3.1).
///
/// Yanlış fotoğrafın anında gitmesini önler; kullanıcı yakınlaştırıp bakar,
/// isterse açıklama yazar. Vazgeçerse null döner.
class ChatImageSendResult {
  const ChatImageSendResult({required this.caption});

  /// Boş olabilir (açıklamasız fotoğraf).
  final String caption;
}

Future<ChatImageSendResult?> showChatImageSendScreen(
  BuildContext context, {
  required Uint8List bytes,
  required String recipientName,
}) {
  return Navigator.of(context).push<ChatImageSendResult?>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ChatImageSendScreen(bytes: bytes, recipientName: recipientName),
    ),
  );
}

class ChatImageSendScreen extends StatefulWidget {
  const ChatImageSendScreen({
    super.key,
    required this.bytes,
    required this.recipientName,
  });

  final Uint8List bytes;
  final String recipientName;

  static const int maxCaptionLength = 500;

  @override
  State<ChatImageSendScreen> createState() => _ChatImageSendScreenState();
}

class _ChatImageSendScreenState extends State<ChatImageSendScreen> {
  final TextEditingController _caption = TextEditingController();

  @override
  void dispose() {
    _caption.dispose();
    super.dispose();
  }

  void _send() {
    Navigator.of(context).pop(ChatImageSendResult(caption: _caption.text.trim()));
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          tooltip: 'Vazgeç',
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Fotoğraf gönder', style: TextStyle(fontSize: 17)),
            Text(
              widget.recipientName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, color: Colors.white70),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: Image.memory(widget.bytes, fit: BoxFit.contain, gaplessPlayback: true),
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _caption,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      inputFormatters: [
                        LengthLimitingTextInputFormatter(ChatImageSendScreen.maxCaptionLength),
                      ],
                      style: const TextStyle(color: Colors.white, fontSize: 15.5),
                      cursorColor: Colors.white,
                      decoration: InputDecoration(
                        hintText: 'Açıklama ekle...',
                        hintStyle: const TextStyle(color: Colors.white54),
                        filled: true,
                        fillColor: const Color(0xFF1F1F24),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Material(
                    color: accent,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: _send,
                      child: const Tooltip(
                        message: 'Gönder',
                        child: Padding(
                          padding: EdgeInsets.all(13),
                          child: Icon(Icons.send_rounded, color: Colors.white, size: 22),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
