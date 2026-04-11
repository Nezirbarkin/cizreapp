import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/post_model.dart';
import '../../../core/services/post_view_service.dart';
import '../../../core/widgets/mention_autocomplete_field.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/utils/app_error_handler.dart';
import '../services/post_service.dart';
import '../../profile/services/profile_service.dart';
import '../../profile/screens/user_profile_screen.dart';

class PostDetailScreen extends StatefulWidget {
  final Post post;

  const PostDetailScreen({super.key, required this.post});

  @override
  State<PostDetailScreen> createState() => _PostDetailScreenState();
}

class _PostDetailScreenState extends State<PostDetailScreen> {
  final PostService _postService = PostService();
  final _profileService = ProfileService();
  final _postViewService = PostViewService();
  final _commentController = TextEditingController();
  List<PostComment> _comments = [];
  Map<String, Map<String, dynamic>> _userProfiles = {};
  Map<String, dynamic>? _currentUserProfile;
  bool _isLoading = true;
  bool _isCommenting = false;
  bool _isLiked = false;
  int _likesCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadCurrentUserProfile();
    _trackPostView();
    _loadLikeStatus();
  }

  Future<void> _loadLikeStatus() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      try {
        final isLiked = await _postService.hasUserLiked(widget.post.id, userId);
        setState(() {
          _isLiked = isLiked;
          _likesCount = widget.post.likesCount;
        });
      } catch (e) {
        setState(() {
          _likesCount = widget.post.likesCount;
        });
      }
    } else {
      setState(() {
        _likesCount = widget.post.likesCount;
      });
    }
  }

  Future<void> _toggleLike() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final wasLiked = _isLiked;
    
    // Sadece liked durumunu güncelle
    setState(() {
      _isLiked = !wasLiked;
    });

    try {
      if (wasLiked) {
        await _postService.unlikePost(widget.post.id, userId);
      } else {
        await _postService.likePost(widget.post.id, userId);
      }
      
      // Başarılıysa post'u yeniden yükle (count trigger'dan güncellenmiş olacak)
      final updatedPost = await _postService.getPostById(widget.post.id);
      if (updatedPost != null && mounted) {
        setState(() {
          _likesCount = updatedPost.likesCount;
        });
      }
    } catch (e) {
      // Hata olursa liked durumunu geri al
      setState(() {
        _isLiked = wasLiked;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppErrorHandler.handleError(e))),
        );
      }
    }
  }

  Future<void> _trackPostView() async {
    // Post görüntülemesini kaydet
    await _postViewService.trackPostView(postId: widget.post.id);
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _loadCurrentUserProfile() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId != null) {
      try {
        final profile = await _profileService.getUserProfile(userId);
        setState(() {
          _currentUserProfile = profile;
        });
      } catch (e) {
        // Hata durumunda profil resmi gösterilmez
      }
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      // Yorumları ve profilleri paralel yükle
      final results = await Future.wait([
        _postService.getComments(widget.post.id),
        _profileService.getUserProfile(widget.post.userId),
      ]);

      final comments = results[0] as List<PostComment>;
      final postAuthorProfile = results[1] as Map<String, dynamic>;
      
      // Tüm yorum yapan kullanıcıların profillerini yükle
      final userIds = <String>{widget.post.userId};
      for (var comment in comments) {
        userIds.add(comment.userId);
      }

      // Batch profile fetch
      final profiles = <String, Map<String, dynamic>>{
        widget.post.userId: postAuthorProfile
      };
      
      for (var id in userIds) {
        if (id == widget.post.userId) continue; // Zaten yüklendi
        try {
          final profile = await _profileService.getUserProfile(id);
          profiles[id] = profile;
        } catch (e) {
          // Profil yüklenemezse default data kullan
        }
      }

      setState(() {
        _comments = comments;
        _userProfiles = profiles;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Yorumlar yüklenirken bir sorun oluştu. ${AppErrorHandler.handleError(e)}')),
        );
      }
    }
  }

  Future<void> _addComment() async {
    if (_commentController.text.isEmpty) return;

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    setState(() => _isCommenting = true);

    try {
      await _postService.addComment(
        widget.post.id,
        userId,
        _commentController.text,
      );

      _commentController.clear();
      _loadData();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppErrorHandler.handleError(e))),
        );
      }
    } finally {
      setState(() => _isCommenting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gönderi Detayı'),
      ),
      body: Column(
        children: [
          // Post Content
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Post Header
                  ListTile(
                    onTap: () {
                      // Kullanıcıya tıklayınca profil ekranına git
                      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
                      if (widget.post.userId == currentUserId) {
                        // Kendi profili
                        Navigator.of(context).pushNamed('/main');
                      } else {
                        // Başka kullanıcının profili
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => UserProfileScreen(userId: widget.post.userId),
                          ),
                        );
                      }
                    },
                    leading: CircleAvatar(
                      radius: 20,
                      backgroundImage: _userProfiles[widget.post.userId]?['avatar_url'] != null
                          ? NetworkImage(_userProfiles[widget.post.userId]!['avatar_url'])
                          : null,
                      child: _userProfiles[widget.post.userId]?['avatar_url'] == null
                          ? Text(
                              () {
                                final username = _userProfiles[widget.post.userId]?['username'] ?? 'U';
                                return username.length >= 2
                                    ? username.substring(0, 2).toUpperCase()
                                    : username.toUpperCase();
                              }(),
                              style: const TextStyle(fontSize: 14),
                            )
                          : null,
                    ),
                    title: Text(
                      _userProfiles[widget.post.userId]?['full_name'] ??
                      _userProfiles[widget.post.userId]?['username'] ??
                      'Kullanıcı',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      '@${_userProfiles[widget.post.userId]?['username'] ?? 'user'} • ${_formatDate(widget.post.createdAt)}',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: Icon(Icons.chevron_right, size: 18, color: Colors.grey),
                  ),

                  // Content
                  if (widget.post.content != null && widget.post.content!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: _buildCommentWithMentions(widget.post.content!),
                    ),

                  // Images
                  if (widget.post.images.isNotEmpty)
                    SizedBox(
                      height: 300,
                      child: PageView.builder(
                        itemCount: widget.post.images.length,
                        itemBuilder: (context, index) {
                          return Image.network(
                            widget.post.images[index],
                            fit: BoxFit.cover,
                          );
                        },
                      ),
                    ),

                  // Stats - Sadece sayı göster, beğeni butonu aşağıda ayrı
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Icon(Icons.favorite, size: 20, color: _isLiked ? Colors.red.shade400 : Colors.grey.shade400),
                        const SizedBox(width: 4),
                        Text('$_likesCount beğeni'),
                        const SizedBox(width: 24),
                        const Icon(Icons.comment, size: 20, color: Colors.grey),
                        const SizedBox(width: 4),
                        Text('${widget.post.commentsCount} yorum'),
                      ],
                    ),
                  ),

                  // Beğeni butonu
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    child: Row(
                      children: [
                        IconButton(
                          icon: Icon(
                            _isLiked ? Icons.favorite : Icons.favorite_border,
                            color: _isLiked ? Colors.red : Colors.grey.shade700,
                            size: 28,
                          ),
                          onPressed: _toggleLike,
                          tooltip: _isLiked ? 'Beğeniyi kaldır' : 'Beğen',
                        ),
                        Text(
                          _isLiked ? 'Beğenildi' : 'Beğen',
                          style: TextStyle(
                            color: _isLiked ? Colors.red : Colors.grey.shade700,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const Divider(),

                  // Comments Section
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'Yorumlar',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),

                  if (_isLoading)
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Yorumlar için skeleton (3 tane)
                          Skeletons.comment(),
                          const SizedBox(height: 12),
                          Skeletons.comment(),
                          const SizedBox(height: 12),
                          Skeletons.comment(),
                        ],
                      ),
                    )
                  else if (_comments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                        child: Text('Henüz yorum yok'),
                      ),
                    )
                  else
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _comments.length,
                      itemBuilder: (context, index) {
                        final comment = _comments[index];
                        final userProfile = _userProfiles[comment.userId];
                        final userId = comment.userId;
                        final username = userProfile?['username'] ?? userId.substring(0, userId.length >= 8 ? 8 : userId.length);
                        final fullName = userProfile?['full_name'] ?? username;
                        final avatarUrl = userProfile?['avatar_url'];
                        
                        return ListTile(
                          onTap: () {
                            // Kullanıcıya tıklayınca profil ekranına git
                            final currentUserId = Supabase.instance.client.auth.currentUser?.id;
                            if (comment.userId == currentUserId) {
                              // Kendi profili
                              Navigator.of(context).pushNamed('/main');
                            } else {
                              // Başka kullanıcının profili
                              Navigator.of(context).push(
                                MaterialPageRoute(
                                  builder: (context) => UserProfileScreen(userId: comment.userId),
                                ),
                              );
                            }
                          },
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                            child: avatarUrl == null
                                ? Text(
                                    username.length >= 2
                                        ? username.substring(0, 2).toUpperCase()
                                        : username.toUpperCase(),
                                    style: const TextStyle(fontSize: 12),
                                  )
                                : null,
                          ),
                          title: Text(
                            fullName,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              _buildCommentWithMentions(comment.content),
                              const SizedBox(height: 4),
                              Text(
                                _formatDate(comment.createdAt),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade600,
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ),

          // Comment Input
          const Divider(height: 1),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundImage: _currentUserProfile?['avatar_url'] != null
                        ? NetworkImage(_currentUserProfile!['avatar_url'])
                        : null,
                    child: _currentUserProfile?['avatar_url'] == null
                        ? Text(
                            (_currentUserProfile?['username']?.length ?? 0) >= 2
                                ? _currentUserProfile!['username'].substring(0, 2).toUpperCase()
                                : 'U',
                            style: const TextStyle(fontSize: 12),
                          )
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: MentionAutocompleteField(
                      controller: _commentController,
                      decoration: InputDecoration(
                        hintText: 'Yorum yaz... (@kullanıcı ile bahset)',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      maxLines: null,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton(
                    icon: _isCommenting
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.send),
                    onPressed: _isCommenting ? null : _addComment,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    // Veritabanındaki tarih zaten doğru saat diliminde (UTC+3), direkt kullan
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  /// Yorum içeriğindeki @mention'ları siyah renkli olarak göster
  Widget _buildCommentWithMentions(String content) {
    final spans = <TextSpan>[];
    final regex = RegExp(r'@(\w+)');
    int lastMatchEnd = 0;

    for (final match in regex.allMatches(content)) {
      // Match'den önceki metni ekle
      if (match.start > lastMatchEnd) {
        spans.add(TextSpan(
          text: content.substring(lastMatchEnd, match.start),
        ));
      }
      // @mention'ı siyah ve bold olarak ekle
      spans.add(TextSpan(
        text: '@${match.group(1)}',
        style: const TextStyle(
          color: Colors.black,
          fontWeight: FontWeight.bold,
        ),
      ));
      lastMatchEnd = match.end;
    }

    // Kalan metni ekle
    if (lastMatchEnd < content.length) {
      spans.add(TextSpan(
        text: content.substring(lastMatchEnd),
      ));
    }

    // Eğer hiç mention yoksa düz metin döndür
    if (spans.isEmpty) {
      return Text(content);
    }

    return Text.rich(
      TextSpan(
        children: spans,
        style: const TextStyle(color: Colors.black87),
      ),
    );
  }
}
