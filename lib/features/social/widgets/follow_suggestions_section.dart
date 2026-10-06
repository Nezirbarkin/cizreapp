import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../profile/screens/user_profile_screen.dart';
import '../models/follow_suggestion.dart';
import '../services/follow_service.dart';

/// Ana sayfa "Önerilen Kişiler" kartları (Görev 3.5) — "En Son Gönderiler"in
/// altında yatay liste. Misafirde ve öneri yokken hiç çizilmez.
///
/// Kart: fotoğraf, ad, kullanıcı adı, neden önerildiği, takip düğmesi (açık
/// hesap: Takip Et / Geri Takip Et; gizli hesap: İstek Gönder) ve kaldır (✕).
/// Takip edilen kart listede kalır ("Takip Ediliyor"); dokununca geri alınır.
class HomeFollowSuggestionsSection extends StatefulWidget {
  const HomeFollowSuggestionsSection({
    super.key,
    this.service,
    this.refreshTick = 0,
    this.openProfile,
    this.limit = 10,
  });

  final FollowService? service;

  /// Değişince öneriler yeniden yüklenir (ana sayfa yenilendiğinde).
  final int refreshTick;
  final void Function(BuildContext context, String userId)? openProfile;
  final int limit;

  @override
  State<HomeFollowSuggestionsSection> createState() => _HomeFollowSuggestionsSectionState();
}

class _HomeFollowSuggestionsSectionState extends State<HomeFollowSuggestionsSection> {
  late final FollowService _service = widget.service ?? FollowService();
  List<FollowSuggestion> _items = const [];
  final Map<String, FollowStatus> _status = {};
  final Set<String> _busy = {};
  int _loadSeq = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant HomeFollowSuggestionsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.refreshTick != widget.refreshTick) _load();
  }

  Future<void> _load() async {
    if (_service.currentUserId == null) {
      if (_items.isNotEmpty) setState(() => _items = const []);
      return;
    }
    final seq = ++_loadSeq;
    try {
      final items = await _service.suggestions(limit: widget.limit);
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _items = items;
        _status.removeWhere((id, _) => items.every((s) => s.id != id));
      });
    } catch (e) {
      debugPrint('Önerilen kişiler yüklenemedi: $e');
    }
  }

  Future<void> _toggle(FollowSuggestion s) async {
    if (_busy.contains(s.id)) return;
    final current = _status[s.id] ?? FollowStatus.none;
    setState(() => _busy.add(s.id));
    try {
      final result = current == FollowStatus.none ? await _service.follow(s.id) : await _service.unfollow(s.id);
      if (!mounted) return;
      setState(() => _status[s.id] = result.status);
      if (result.status == FollowStatus.requested && current == FollowStatus.none) {
        _snack('${s.displayName} gizli hesap; takip isteği gönderildi.');
      }
    } catch (e) {
      _snack(FollowService.toException(e).message);
    } finally {
      if (mounted) setState(() => _busy.remove(s.id));
    }
  }

  Future<void> _dismiss(FollowSuggestion s) async {
    setState(() {
      _items = _items.where((x) => x.id != s.id).toList();
      _status.remove(s.id);
    });
    try {
      await _service.dismissSuggestion(s.id);
    } catch (e) {
      debugPrint('Öneri kaldırılamadı: $e');
    }
  }

  void _openProfile(String userId) {
    final open = widget.openProfile;
    if (open != null) {
      open(context, userId);
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => UserProfileScreen(userId: userId)));
  }

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Text(
                'Önerilen Kişiler',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Colors.black87),
              ),
              SizedBox(width: 4),
              Text('👋', style: TextStyle(fontSize: 16)),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 2, 16, 0),
          child: Text(
            'Tanıyor olabileceğin, takip etmeye değer hesaplar',
            style: TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 222,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: _items.length,
            itemBuilder: (context, i) {
              final s = _items[i];
              return _SuggestionCard(
                key: ValueKey('suggestion-${s.id}'),
                suggestion: s,
                status: _status[s.id] ?? FollowStatus.none,
                busy: _busy.contains(s.id),
                onToggle: () => _toggle(s),
                onDismiss: () => _dismiss(s),
                onOpen: () => _openProfile(s.id),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _SuggestionCard extends StatelessWidget {
  const _SuggestionCard({
    super.key,
    required this.suggestion,
    required this.status,
    required this.busy,
    required this.onToggle,
    required this.onDismiss,
    required this.onOpen,
  });

  final FollowSuggestion suggestion;
  final FollowStatus status;
  final bool busy;
  final VoidCallback onToggle;
  final VoidCallback onDismiss;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final s = suggestion;
    final primary = Theme.of(context).colorScheme.primary;
    return Container(
      width: 150,
      margin: const EdgeInsets.only(right: 10, bottom: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06), blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
            child: Column(
              children: [
                GestureDetector(
                  onTap: onOpen,
                  child: _Avatar(url: s.avatarUrl, name: s.displayName, size: 68),
                ),
                const SizedBox(height: 8),
                GestureDetector(
                  onTap: onOpen,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Flexible(
                        child: Text(
                          s.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14, color: Colors.black87),
                        ),
                      ),
                      if (s.isVerified) ...[
                        const SizedBox(width: 3),
                        Icon(Icons.verified, size: 14, color: primary),
                      ],
                      if (s.isPrivate) ...[
                        const SizedBox(width: 3),
                        const Icon(Icons.lock_outline, size: 13, color: Colors.black45),
                      ],
                    ],
                  ),
                ),
                if (s.username.isNotEmpty)
                  Text(
                    '@${s.username}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.black45),
                  ),
                const SizedBox(height: 4),
                Expanded(
                  child: Text(
                    s.reasonText,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 11.5,
                      height: 1.25,
                      color: s.reason == FollowSuggestionReason.followsYou ? primary : Colors.black54,
                      fontWeight: s.reason == FollowSuggestionReason.followsYou ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
                SizedBox(width: double.infinity, height: 34, child: _button(context, primary)),
              ],
            ),
          ),
          Positioned(
            top: 2,
            right: 2,
            child: IconButton(
              tooltip: 'Öneriyi kaldır',
              visualDensity: VisualDensity.compact,
              iconSize: 16,
              onPressed: onDismiss,
              icon: const Icon(Icons.close, color: Colors.black38),
            ),
          ),
        ],
      ),
    );
  }

  Widget _button(BuildContext context, Color primary) {
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(10));
    const textStyle = TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700);
    if (busy) {
      return const Center(child: SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)));
    }
    if (status == FollowStatus.none) {
      return FilledButton(
        onPressed: onToggle,
        style: FilledButton.styleFrom(backgroundColor: primary, shape: shape, padding: EdgeInsets.zero),
        child: Text(suggestion.followLabel, style: textStyle),
      );
    }
    return OutlinedButton(
      onPressed: onToggle,
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.black87,
        side: BorderSide(color: Colors.grey.shade300),
        shape: shape,
        padding: EdgeInsets.zero,
      ),
      child: Text(status == FollowStatus.following ? 'Takip Ediliyor' : 'İstek Gönderildi', style: textStyle),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.url, required this.name, required this.size});

  final String? url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
      ),
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.4,
          fontWeight: FontWeight.w800,
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
    final link = url;
    if (link == null) return fallback;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: link,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: (size * 3).round(),
        placeholder: (_, _) => fallback,
        errorWidget: (_, _, _) => fallback,
      ),
    );
  }
}
