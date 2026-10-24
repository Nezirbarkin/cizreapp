import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/post_model.dart';
import '../../profile/screens/user_profile_screen.dart';
import '../services/post_impression_tracker.dart';
import '../services/post_service.dart';
import '../services/social_share_service.dart';
import '../widgets/impression_probe.dart';
import '../widgets/post_insights_sheet.dart';
import '../widgets/send_to_friend_sheet.dart';
import '../widgets/social_post_card.dart';
import 'post_detail_screen.dart';

/// `#etiket` içeren gönderiler (yeniden eskiye, sayfalı). Kart ve
/// etkileşimler akıştakiyle aynı; gizli hesap / engel sunucuda süzülür.
class HashtagFeedScreen extends StatefulWidget {
  const HashtagFeedScreen({super.key, required this.tag, this.service});

  /// Katlanmış etiket (ör. "cizre"), `#` olmadan.
  final String tag;
  final PostService? service;

  @override
  State<HashtagFeedScreen> createState() => _HashtagFeedScreenState();
}

class _HashtagFeedScreenState extends State<HashtagFeedScreen> {
  static const int _pageSize = 20;

  late final PostService _service = widget.service ?? PostService();
  final ScrollController _scroll = ScrollController();
  final List<Post> _posts = [];
  final Set<String> _liked = {};
  final Set<String> _saved = {};
  final Set<String> _inFlight = {};
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  String? _error;
  int _generation = 0;

  String? get _uid => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(() {
      if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) _loadMore();
    });
    _load();
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final gen = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final posts = await _service.getPostsByHashtag(widget.tag, limit: _pageSize);
      final uid = _uid;
      final liked = uid == null
          ? <String>{}
          : await _service.getLikedPostIds(uid, posts.map((p) => p.id).toList());
      final saved = uid == null ? <String>{} : await _service.getSavedPostIds();
      if (!mounted || gen != _generation) return;
      setState(() {
        _posts
          ..clear()
          ..addAll(posts);
        _liked
          ..clear()
          ..addAll(liked);
        _saved
          ..clear()
          ..addAll(saved);
        _hasMore = posts.length >= _pageSize;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = 'Gönderiler yüklenemedi';
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loading || _loadingMore || !_hasMore) return;
    final gen = _generation;
    setState(() => _loadingMore = true);
    try {
      final more = await _service.getPostsByHashtag(
        widget.tag,
        limit: _pageSize,
        offset: _posts.length,
      );
      final uid = _uid;
      final liked = uid == null
          ? <String>{}
          : await _service.getLikedPostIds(uid, more.map((p) => p.id).toList());
      if (!mounted || gen != _generation) return;
      final known = _posts.map((p) => p.id).toSet();
      setState(() {
        _posts.addAll(more.where((p) => !known.contains(p.id)));
        _liked.addAll(liked);
        _hasMore = more.length >= _pageSize;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _patch(String id, Post Function(Post p) f) {
    final i = _posts.indexWhere((p) => p.id == id);
    if (i != -1) _posts[i] = f(_posts[i]);
  }

  Future<void> _toggleLike(Post post) async {
    final uid = _uid;
    if (uid == null || !_inFlight.add(post.id)) return;
    final liked = _liked.contains(post.id);
    setState(() {
      liked ? _liked.remove(post.id) : _liked.add(post.id);
      _patch(post.id, (p) => p.copyWith(likesCount: (p.likesCount + (liked ? -1 : 1)).clamp(0, 1 << 31).toInt()));
    });
    try {
      liked ? await _service.unlikePost(post.id, uid) : await _service.likePost(post.id, uid);
    } catch (_) {
      if (mounted) {
        setState(() {
          liked ? _liked.add(post.id) : _liked.remove(post.id);
          _patch(post.id, (p) => p.copyWith(likesCount: (p.likesCount + (liked ? 1 : -1)).clamp(0, 1 << 31).toInt()));
        });
      }
    } finally {
      _inFlight.remove(post.id);
    }
  }

  Future<void> _toggleSave(Post post) async {
    if (_uid == null) return;
    final save = !_saved.contains(post.id);
    setState(() => save ? _saved.add(post.id) : _saved.remove(post.id));
    try {
      await _service.setPostSaved(post.id, save);
    } catch (_) {
      if (mounted) setState(() => save ? _saved.remove(post.id) : _saved.add(post.id));
    }
  }

  Future<void> _share(Post post) async {
    final name = (post.authorFullName?.trim().isNotEmpty ?? false)
        ? post.authorFullName!.trim()
        : (post.authorUsername ?? 'Kullanıcı');
    try {
      final count = await SocialShareService().sharePost(post, authorName: name);
      if (count == null || !mounted) return;
      setState(() => _patch(post.id, (p) => p.copyWith(sharesCount: count)));
    } catch (_) {}
  }

  Future<void> _openDetail(Post post) async {
    final result = await Navigator.of(context).push<PostDetailResult?>(
      MaterialPageRoute(builder: (_) => PostDetailScreen(post: post)),
    );
    if (result == null || !mounted) return;
    setState(() {
      _patch(post.id, result.applyTo);
      result.isLiked ? _liked.add(post.id) : _liked.remove(post.id);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        title: Text('#${widget.tag}'),
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF11181C),
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      body: RefreshIndicator(onRefresh: _load, child: _body()),
    );
  }

  Widget _body() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null || _posts.isEmpty) {
      return ListView(
        children: [
          const SizedBox(height: 120),
          Icon(
            _error != null ? Icons.cloud_off_rounded : Icons.tag_rounded,
            size: 48,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              _error ?? '#${widget.tag} etiketiyle henüz gönderi yok',
              style: TextStyle(color: Colors.grey.shade600),
            ),
          ),
        ],
      );
    }
    final uid = _uid;
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
      itemCount: _posts.length + (_loadingMore ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= _posts.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        }
        final post = _posts[i];
        final name = (post.authorFullName?.trim().isNotEmpty ?? false)
            ? post.authorFullName!.trim()
            : (post.authorUsername ?? 'Kullanıcı');
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: ImpressionProbe(
            id: post.id,
            onSeen: () => PostImpressionTracker.instance.markSeen(post.id, authorId: post.userId),
            child: SocialPostCard(
              post: post,
              fullName: name,
              username: post.authorUsername ?? 'kullanici',
              avatarUrl: post.authorAvatarUrl,
              authorRole: post.authorRole,
              isVerified: post.authorIsVerified,
              isLiked: _liked.contains(post.id),
              isSaved: _saved.contains(post.id),
              onTap: () => _openDetail(post),
              onAuthorTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => UserProfileScreen(userId: post.userId)),
              ),
              onLike: () => _toggleLike(post),
              onComment: () => _openDetail(post),
              onSend: () => sendPostToFriend(context, post),
              onSave: () => _toggleSave(post),
              onShare: () => _share(post),
              onHashtagTap: (tag) {
                if (tag == widget.tag) return;
                Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => HashtagFeedScreen(tag: tag)),
                );
              },
              onViewsTap: post.userId == uid ? () => showPostInsightsSheet(context, post) : null,
            ),
          ),
        );
      },
    );
  }
}
