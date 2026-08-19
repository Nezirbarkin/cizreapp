// ignore_for_file: curly_braces_in_flow_control_structures

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../features/chat/screens/chat_detail_screen.dart';
import '../../features/chat/services/chat_service.dart';
import '../models/ilan_models.dart';
import '../services/ilan_service.dart';
import '../utils/ilan_ui.dart';

class IlanDetailScreen extends StatefulWidget {
  const IlanDetailScreen({super.key, required this.ilanId});
  final String ilanId;

  @override
  State<IlanDetailScreen> createState() => _IlanDetailScreenState();
}

class _IlanDetailScreenState extends State<IlanDetailScreen> {
  final _service = IlanService();
  final _chatService = ChatService();
  late Future<Ilan> _future;
  bool _favorite = false;
  int _currentImage = 0;

  @override
  void initState() {
    super.initState();
    _future = _service.getById(widget.ilanId);
    _service.incrementView(widget.ilanId);
    _service.isFavorite(widget.ilanId).then((value) {
      if (mounted) setState(() => _favorite = value);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('İlan Detayı'),
        actions: [
          IconButton(
            tooltip: 'Paylaş',
            onPressed: () => _shareCurrent(),
            icon: const Icon(Icons.share_outlined),
          ),
          IconButton(
            tooltip: 'Favori',
            onPressed: () async {
              if (Supabase.instance.client.auth.currentUser == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Favoriye eklemek için giriş yapmalısınız.'),
                  ),
                );
                return;
              }
              final value = await _service.toggleFavorite(
                widget.ilanId,
                _favorite,
              );
              if (mounted) setState(() => _favorite = value);
            },
            icon: Icon(
              _favorite ? Icons.favorite : Icons.favorite_border,
              color: _favorite ? Colors.red : null,
            ),
          ),
        ],
      ),
      body: FutureBuilder<Ilan>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting)
            return const Center(child: CircularProgressIndicator());
          if (snapshot.hasError || !snapshot.hasData)
            return const Center(child: Text('İlan yüklenemedi.'));
          final ilan = snapshot.data!;
          final color = IlanUi.color(ilan.category?.colorHex ?? '#6D28D9');
          final images = ilan.images.isNotEmpty
              ? ilan.images.map((image) => image.url).toList()
              : [if (ilan.coverImageUrl != null) ilan.coverImageUrl!];
          return ListView(
            children: [
              if (images.isNotEmpty)
                SizedBox(
                  height: 300,
                  child: Stack(
                    children: [
                      PageView.builder(
                        itemCount: images.length,
                        onPageChanged: (index) =>
                            setState(() => _currentImage = index),
                        itemBuilder: (_, index) => CachedNetworkImage(
                          imageUrl: images[index],
                          fit: BoxFit.cover,
                          errorWidget: (_, __, ___) => _imagePlaceholder(color),
                        ),
                      ),
                      if (images.length > 1)
                        Positioned(
                          bottom: 12,
                          left: 0,
                          right: 0,
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              images.length,
                              (index) => AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 3,
                                ),
                                width: index == _currentImage ? 20 : 6,
                                height: 6,
                                decoration: BoxDecoration(
                                  color: index == _currentImage
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.white70,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                )
              else
                SizedBox(height: 240, child: _imagePlaceholder(color)),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: .1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            ilan.category?.name ?? 'İlan',
                            style: TextStyle(
                              color: color,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        if (ilan.status != IlanStatus.published)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: IlanUi.statusColor(
                                ilan.status,
                              ).withValues(alpha: .12),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Text(
                              IlanUi.status(ilan.status),
                              style: TextStyle(
                                color: IlanUi.statusColor(ilan.status),
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (ilan.status == IlanStatus.rejected &&
                        ilan.rejectionReason?.trim().isNotEmpty == true) ...[
                      const SizedBox(height: 10),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: IlanUi.statusColor(
                            ilan.status,
                          ).withValues(alpha: .08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: IlanUi.statusColor(
                              ilan.status,
                            ).withValues(alpha: .25),
                          ),
                        ),
                        child: Text(
                          'Gerekçe: ${ilan.rejectionReason}',
                          style: TextStyle(
                            fontSize: 12,
                            color: IlanUi.statusColor(ilan.status),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      ilan.title,
                      style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        height: 1.15,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      IlanUi.price(ilan),
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: ilan.hasPrice ? color : Colors.black54,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _info(Icons.location_on_outlined, ilan.locationText),
                        if (ilan.itemCondition != null)
                          _info(Icons.verified_outlined, ilan.itemCondition!),
                        _info(
                          Icons.visibility_outlined,
                          '${ilan.viewCount + 1} görüntülenme',
                        ),
                        if (IlanUi.remainingLabel(ilan) case final label?)
                          _info(Icons.schedule_outlined, label),
                      ],
                    ),
                    const Divider(height: 34),
                    const Text(
                      'Açıklama',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 9),
                    Text(
                      ilan.description,
                      style: const TextStyle(fontSize: 15, height: 1.55),
                    ),
                    const Divider(height: 34),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: CircleAvatar(
                        backgroundImage: ilan.ownerAvatarUrl == null
                            ? null
                            : NetworkImage(ilan.ownerAvatarUrl!),
                        child: ilan.ownerAvatarUrl == null
                            ? const Icon(Icons.person)
                            : null,
                      ),
                      title: Text(
                        ilan.ownerName ?? 'CizreApp Kullanıcısı',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      subtitle: const Text('İlan sahibi'),
                    ),
                    const SizedBox(height: 18),
                    if (Supabase.instance.client.auth.currentUser?.id ==
                        ilan.ownerId)
                      _ownerActions(ilan)
                    else ...[
                      _kaporaWarning(),
                      const SizedBox(height: 14),
                      ..._contactButtons(ilan, color),
                    ],
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _shareCurrent() async {
    final ilan = await _future;
    await SharePlus.instance.share(
      ShareParams(
        text: '${ilan.title}\n${IlanUi.price(ilan)}\n${ilan.locationText}',
      ),
    );
  }

  Widget _imagePlaceholder(Color color) => ColoredBox(
    color: color.withValues(alpha: .08),
    child: Center(
      child: Icon(
        Icons.image_outlined,
        size: 70,
        color: color.withValues(alpha: .6),
      ),
    ),
  );

  Widget _info(IconData icon, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.black12),
    ),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 16, color: Colors.black54),
        const SizedBox(width: 5),
        Text(text, style: const TextStyle(fontSize: 12)),
      ],
    ),
  );

  Widget _kaporaWarning() => Container(
    width: double.infinity,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.orange.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: Colors.orange.withValues(alpha: .3)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            IlanUi.kaporaWarning,
            style: const TextStyle(fontSize: 12, color: Colors.black87),
          ),
        ),
      ],
    ),
  );

  Widget _ownerActions(Ilan ilan) => SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      onPressed: () => _deleteIlan(ilan),
      icon: const Icon(Icons.delete_outline),
      label: const Text('İlanı Sil'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.red,
        side: const BorderSide(color: Colors.red),
        padding: const EdgeInsets.symmetric(vertical: 15),
      ),
    ),
  );

  Future<void> _deleteIlan(Ilan ilan) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('İlanı sil'),
        content: Text('"${ilan.title}" ilanını silmek istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await _service.deleteIlan(ilan.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(IlanUi.friendlyError(error))));
    }
  }

  List<Widget> _contactButtons(Ilan ilan, Color color) {
    final hasWhatsApp =
        (ilan.contactPreference == 'phone' ||
            ilan.contactPreference == 'both') &&
        ilan.contactPhone?.trim().isNotEmpty == true;
    final hasMessage =
        ilan.contactPreference == 'app' || ilan.contactPreference == 'both';

    final buttons = <Widget>[];
    if (hasWhatsApp) {
      buttons.add(
        Expanded(
          child: FilledButton.icon(
            onPressed: () => _openWhatsApp(ilan),
            icon: const Icon(Icons.chat_rounded),
            label: const Text('WhatsApp'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF25D366),
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
          ),
        ),
      );
    }
    if (hasMessage) {
      buttons.add(
        Expanded(
          child: FilledButton.icon(
            onPressed: () => _openAppChat(ilan),
            icon: const Icon(Icons.chat_bubble_outline),
            label: const Text('Mesaj'),
            style: FilledButton.styleFrom(
              backgroundColor: color,
              padding: const EdgeInsets.symmetric(vertical: 15),
            ),
          ),
        ),
      );
    }
    return [
      Row(
        children: [
          for (var index = 0; index < buttons.length; index++) ...[
            if (index > 0) const SizedBox(width: 10),
            buttons[index],
          ],
        ],
      ),
    ];
  }

  Future<void> _openWhatsApp(Ilan ilan) async {
    var digits = ilan.contactPhone!.replaceAll(RegExp(r'\D'), '');
    if (digits.startsWith('00')) digits = digits.substring(2);
    if (digits.startsWith('0')) digits = '90${digits.substring(1)}';
    if (digits.length == 10) digits = '90$digits';
    final message =
        'Merhaba, CizreApp’teki "${ilan.title}" ilanınız hakkında bilgi almak istiyorum.\nİlan no: ${ilan.id}';
    final uri = Uri.https('wa.me', '/$digits', {'text': message});
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('WhatsApp açılamadı.')));
  }

  Future<void> _openAppChat(Ilan ilan) async {
    final currentUser = Supabase.instance.client.auth.currentUser;
    if (currentUser == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mesaj göndermek için giriş yapmalısınız.'),
        ),
      );
      return;
    }
    if (currentUser.id == ilan.ownerId) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Bu ilan size ait.')));
      return;
    }

    final conversation = await _chatService.getOrCreateConversation(
      ilan.ownerId,
    );
    if (conversation == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('İlan sahibi şu anda mesaj kabul etmiyor.'),
        ),
      );
      return;
    }

    final message = await _chatService.sendSharedIlan(
      conversationId: conversation.id,
      ilanId: ilan.id,
      title: ilan.title,
      priceText: IlanUi.price(ilan),
      locationText: ilan.locationText,
      imageUrl: ilan.coverImageUrl,
    );
    if (!mounted) return;
    if (message == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('İlan sohbete gönderilemedi.')),
      );
      return;
    }

    final profile = conversation.otherUser;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatDetailScreen(
          conversationId: conversation.id,
          otherUserId: ilan.ownerId,
          otherUserName:
              (profile?['full_name'] ?? profile?['username'] ?? ilan.ownerName)
                  as String? ??
              'İlan Sahibi',
          otherUserAvatar:
              profile?['avatar_url'] as String? ?? ilan.ownerAvatarUrl,
        ),
      ),
    );
  }
}
