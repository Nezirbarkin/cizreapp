import 'package:flutter/material.dart';

import '../services/chat_media_service.dart';
import '../widgets/chat_media_bubbles.dart';

/// Sohbet fotoğrafını tam ekran, yakınlaştırılabilir gösterir (Görev 3.1).
class ChatImageViewerScreen extends StatelessWidget {
  const ChatImageViewerScreen({
    super.key,
    required this.path,
    required this.title,
    this.subtitle,
    this.caption,
    this.media,
  });

  /// `chat_attachments` kovasındaki yol.
  final String path;

  /// Gönderen ("Sen" ya da karşı tarafın adı).
  final String title;

  /// Gönderim zamanı.
  final String? subtitle;
  final String? caption;
  final ChatMediaService? media;

  @override
  Widget build(BuildContext context) {
    final hasCaption = caption != null && caption!.trim().isNotEmpty;
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: const Color(0x66000000),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 16)),
            if (subtitle != null)
              Text(subtitle!, style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 1,
              maxScale: 5,
              child: Center(
                child: ChatAttachmentImage(path: path, fit: BoxFit.contain, media: media),
              ),
            ),
          ),
          if (hasCaption)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [Color(0x00000000), Color(0xB3000000)],
                  ),
                ),
                padding: EdgeInsets.fromLTRB(
                  20,
                  36,
                  20,
                  16 + MediaQuery.paddingOf(context).bottom,
                ),
                child: Text(
                  caption!.trim(),
                  style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
