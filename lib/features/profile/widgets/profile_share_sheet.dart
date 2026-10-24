import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/utils/image_url.dart';
import '../../social/services/social_share_service.dart';

/// Profil paylaşım sayfası: profil linkinin QR kodu + profil kartı, "Linki
/// kopyala", "Paylaş" ve "QR'ı paylaş" (kartın görüntüsü PNG olarak).
///
/// QR telefonun kamerasıyla okutulunca `https://cizreapp.com/u/@...` açılır:
/// uygulama yüklüyse uygulamada (Android/iOS uygulama linkleri), değilse web
/// sürümünde profil kartı. Eskiden paylaş düğmesi yalnız linki panoya
/// kopyalıyordu.
Future<void> showProfileShareSheet(
  BuildContext context, {
  required String username,
  String? fullName,
  String? avatarUrl,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ProfileShareSheet(
      username: username,
      fullName: fullName,
      avatarUrl: avatarUrl,
    ),
  );
}

class ProfileShareSheet extends StatefulWidget {
  final String username;
  final String? fullName;
  final String? avatarUrl;

  const ProfileShareSheet({
    super.key,
    required this.username,
    this.fullName,
    this.avatarUrl,
  });

  @override
  State<ProfileShareSheet> createState() => _ProfileShareSheetState();
}

class _ProfileShareSheetState extends State<ProfileShareSheet> {
  static const _ink = Color(0xFF17232D);

  final GlobalKey _cardKey = GlobalKey();
  bool _copied = false;
  bool _sharingImage = false;

  /// Sayfa içi bilgi şeridi (SnackBar alt sayfanın arkasında kalıyordu).
  String? _notice;

  String get _link => SocialShareService.profileLink(widget.username);

  /// Ekranda okunur hâli (Türkçe harfler yüzde kodsuz); kopyalanan/QR'daki
  /// link kodludur.
  String get _displayLink =>
      'cizreapp.com/u/@${widget.username.trim().replaceFirst(RegExp(r'^@+'), '')}';

  String get _displayName => (widget.fullName?.trim().isNotEmpty ?? false)
      ? widget.fullName!.trim()
      : '@${widget.username}';

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _link));
    if (!mounted) return;
    setState(() {
      _copied = true;
      _notice = null;
    });
  }

  Future<void> _shareLink() async {
    try {
      await SocialShareService().shareProfile(
        username: widget.username,
        fullName: widget.fullName,
      );
    } catch (e) {
      debugPrint('Profil paylaşılamadı: $e');
      if (mounted) setState(() => _notice = 'Paylaşım açılamadı; linki kopyalayabilirsin.');
    }
  }

  /// Kartı (QR + ad) PNG'ye çevirip paylaşır.
  Future<void> _shareQrImage() async {
    if (_sharingImage) return;
    setState(() {
      _sharingImage = true;
      _notice = null;
    });
    try {
      final boundary =
          _cardKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
      if (boundary == null) throw StateError('kart çizilmedi');
      final image = await boundary.toImage(pixelRatio: 3);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (data == null) throw StateError('png üretilemedi');

      await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              data.buffer.asUint8List(),
              mimeType: 'image/png',
              name: 'cizreapp_${widget.username}.png',
            ),
          ],
          text: SocialShareService.profileShareText(
            username: widget.username,
            fullName: widget.fullName,
          ),
        ),
      );
    } catch (e) {
      debugPrint('QR paylaşılamadı: $e');
      if (mounted) setState(() => _notice = 'QR görseli paylaşılamadı; linki kopyalayabilirsin.');
    } finally {
      if (mounted) setState(() => _sharingImage = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final avatar = avatarImage(widget.avatarUrl);
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        16 + MediaQuery.paddingOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'Profili Paylaş',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          // Görsel olarak paylaşılan kart: beyaz zemin, QR, ad.
          RepaintBoundary(
            key: _cardKey,
            child: Container(
              width: 260,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  QrImageView(
                    data: _link,
                    size: 200,
                    padding: EdgeInsets.zero,
                    backgroundColor: Colors.white,
                    eyeStyle: const QrEyeStyle(
                      eyeShape: QrEyeShape.circle,
                      color: _ink,
                    ),
                    dataModuleStyle: const QrDataModuleStyle(
                      dataModuleShape: QrDataModuleShape.circle,
                      color: _ink,
                    ),
                    semanticsLabel: 'Profil QR kodu',
                  ),
                  const SizedBox(height: 14),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircleAvatar(
                        radius: 14,
                        backgroundColor: Colors.grey.shade200,
                        backgroundImage: avatar,
                        child: avatar == null
                            ? Text(
                                widget.username.isNotEmpty
                                    ? widget.username.characters.first.toUpperCase()
                                    : '?',
                                style: const TextStyle(fontSize: 12),
                              )
                            : null,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          _displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: _ink,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${widget.username} · CizreApp',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          SelectableText(
            _displayLink,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 12.5, color: Colors.grey.shade700),
          ),
          if (_notice != null) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                _notice!,
                style: TextStyle(fontSize: 12.5, color: Colors.orange.shade900),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _SheetAction(
                  icon: _copied ? Icons.check_rounded : Icons.link_rounded,
                  label: _copied ? 'Kopyalandı' : 'Linki kopyala',
                  onTap: _copy,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SheetAction(
                  icon: Icons.ios_share_rounded,
                  label: 'Paylaş',
                  onTap: _shareLink,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _SheetAction(
                  icon: Icons.qr_code_2_rounded,
                  label: "QR'ı paylaş",
                  busy: _sharingImage,
                  onTap: _shareQrImage,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool busy;

  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFF3F4F6),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            children: [
              busy
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(icon, size: 22, color: const Color(0xFF374151)),
              const SizedBox(height: 6),
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF374151),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
