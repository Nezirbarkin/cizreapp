// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/post_model.dart';
import '../../features/social/services/story_service.dart';

class StoryModel {
  final String id;
  final String userName;
  final String userAvatar;
  final String imageUrl;
  final String timeAgo;
  final String storyType; // 'user' or 'live'

  StoryModel({
    required this.id,
    required this.userName,
    required this.userAvatar,
    required this.imageUrl,
    required this.timeAgo,
    required this.storyType,
  });
}

class StoryCard extends StatelessWidget {
  final StoryModel story;
  final VoidCallback? onTap;
  final bool isCompact;

  const StoryCard({
    super.key,
    required this.story,
    this.onTap,
    this.isCompact = false,
  });

  @override
  Widget build(BuildContext context) {
    if (isCompact) {
      // Market ekranında compact story gösterimi
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 68,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(
            children: [
              Container(
                width: 68,
                height: 68,
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: story.storyType == 'live'
                      ? const LinearGradient(
                          colors: [
                            Color(0xFFD4E157),
                            Color(0xFFFF6F00),
                            Color(0xFFD81B60),
                          ],
                        )
                      : LinearGradient(
                          colors: [
                            Colors.green.shade400,
                            Colors.green.shade600,
                          ],
                        ),
                ),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.green.shade600,
                      width: 3,
                    ),
                    image: DecorationImage(
                      image: NetworkImage(story.imageUrl),
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                story.userName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    } else {
      // Tam ekran story gösterimi - gradient gölge yok
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: 140,
          height: 200,
          margin: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            image: DecorationImage(
              image: NetworkImage(story.imageUrl),
              fit: BoxFit.cover,
            ),
          ),
          child: Stack(
            children: [
              // Kullanıcı bilgisi - Gradient yok, sadece text shadow
              Positioned(
                top: 12,
                left: 12,
                child: Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white,
                          width: 2,
                        ),
                        image: DecorationImage(
                          image: NetworkImage(story.userAvatar),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          story.userName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            shadows: [
                              Shadow(
                                color: Colors.black45,
                                blurRadius: 3,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          story.timeAgo,
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: 10,
                            shadows: [
                              Shadow(
                                color: Colors.black45,
                                blurRadius: 3,
                                offset: Offset(0, 1),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              
              // Live badge
              if (story.storyType == 'live')
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.red,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.circle,
                          size: 6,
                          color: Colors.white,
                        ),
                        SizedBox(width: 4),
                        Text(
                          'CANLIDA',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 8,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    }
  }
}

class StoriesSection extends StatefulWidget {
  final bool isCompact;
  final Function(int)? onStoryTap;
  final bool forceCompact; // Scroll durumuna göre zorla compact yap

  const StoriesSection({
    super.key,
    this.isCompact = false,
    this.onStoryTap,
    this.forceCompact = false,
  });

  @override
  State<StoriesSection> createState() => _StoriesSectionState();
}

class _StoriesSectionState extends State<StoriesSection> {
  late ScrollController _scrollController;
  final StoryService _storyService = StoryService();
  List<Story> _stories = [];
  Map<String, String> _usernames = {}; // userId -> username mapping
  Map<String, String?> _userAvatars = {}; // userId -> avatar_url mapping
  bool _isLoading = true;
  final Set<String> _likingStories = {}; // Beğenme işlemi devam eden story'ler

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _loadStories();
  }

  Future<void> _loadStories() async {
    try {
      // Misafirler de story'leri görebilir
      final stories = await _storyService.getStories();
      
      // Tüm story'lerin user ID'lerini topla
      final userIds = stories.map((s) => s.userId).toSet().toList();
      
      // Profil bilgilerini yükle
      Map<String, String> usernamesMap = {};
      Map<String, String?> userAvatarsMap = {};
      
      if (userIds.isNotEmpty) {
        try {
          final profiles = await Supabase.instance.client
              .from('profiles')
              .select('id, full_name, username, avatar_url')
              .inFilter('id', userIds);
          
          for (final profile in profiles) {
            usernamesMap[profile['id']] = profile['full_name'] ?? profile['username'] ?? 'Bilinmiyor';
            userAvatarsMap[profile['id']] = profile['avatar_url'] as String?;
          }
        } catch (e) {
          debugPrint('Profil bilgileri yüklenirken hata: $e');
        }
      }

      setState(() {
        _stories = stories;
        _usernames = usernamesMap;
        _userAvatars = userAvatarsMap;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      debugPrint('Hikayeler yüklenirken hata: $e');
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final localDate = date.toLocal();
    final difference = now.difference(localDate);

    if (difference.inSeconds < 60) {
      return 'Şimdi';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}dk';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}s';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}g';
    } else {
      final weeks = (difference.inDays / 7).floor();
      return '${weeks}h';
    }
  }

  // Beğeni sayısını formatla (1.2B, 1.5M, 1.5K vb.)
  String _formatLikeCount(int count) {
    if (count >= 1000000000) {
      return '${(count / 1000000000).toStringAsFixed(1)}B';
    } else if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return '$count';
  }

  // Story beğenisini toggle et
  Future<void> _toggleLike(String storyId) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Beğenmek için giriş yapmalısınız')),
                        );
      }
      return;
    }

    setState(() => _likingStories.add(storyId));

    try {
      // Optimistik güncelleme - UI'ı hemen güncelle
      final storyIndex = _stories.indexWhere((s) => s.id == storyId);
      if (storyIndex != -1) {
        final story = _stories[storyIndex];
        final wasLiked = story.isLikedByCurrentUser;
        
        setState(() {
          _stories[storyIndex] = story.copyWith(
            isLikedByCurrentUser: !wasLiked,
            likesCount: wasLiked ? story.likesCount - 1 : story.likesCount + 1,
          );
        });
      }

      // API çağrısı
      await _storyService.toggleStoryLike(storyId);
    } catch (e) {
      // Hata durumunda geri al
      final storyIndex = _stories.indexWhere((s) => s.id == storyId);
      if (storyIndex != -1) {
        final story = _stories[storyIndex];
        setState(() {
          _stories[storyIndex] = story.copyWith(
            isLikedByCurrentUser: !story.isLikedByCurrentUser,
            likesCount: story.isLikedByCurrentUser
                ? story.likesCount - 1
                : story.likesCount + 1,
          );
        });
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İşlem başarısız: $e')),
        );
      }
    } finally {
      setState(() => _likingStories.remove(storyId));
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final shouldBeCompact = widget.isCompact || widget.forceCompact;
    
    if (_isLoading) {
      return SizedBox(
        height: shouldBeCompact ? 105 : 240,
        child: const Center(child: CircularProgressIndicator()),
      );
    }
    
    if (shouldBeCompact) {
      // Compact stories (Market ekranında) - Story içeriği önizlemesi
      return SizedBox(
        height: 95,
        child: ListView.builder(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 4),
          itemCount: _stories.length,
          itemBuilder: (context, index) {
            final story = _stories[index];
            final username = _usernames[story.userId] ?? 'Bilinmiyor';
            
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () {
                  if (widget.onStoryTap != null) {
                    widget.onStoryTap!(index);
                  }
                },
                child: SizedBox(
                  width: 70,
                  child: Column(
                    children: [
                      // Story içeriği önizlemesi (daire içinde)
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Container(
                        width: 70,
                        height: 70,
                        padding: const EdgeInsets.all(2.5),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: story.isViewedByCurrentUser
                              ? null // İzlendiyse gradient yok (gri)
                              : LinearGradient( // İzlenmediyse renkli gradient
                                  colors: [
                                    Colors.purple.shade400,
                                    Colors.pink.shade400,
                                    Colors.orange.shade400,
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                          color: story.isViewedByCurrentUser
                              ? Colors.grey.shade300 // İzlendiyse gri
                              : null, // İzlenmediyse gradient kullan
                        ),
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2.5),
                          ),
                          child: ClipOval(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // Story içerik thumbnail (video önizlemesi)
                                Image.network(
                                  story.displayUrl,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      color: Colors.grey.shade800,
                                      child: const Icon(
                                        Icons.play_circle_outline,
                                        size: 28,
                                        color: Colors.white54,
                                      ),
                                    );
                                  },
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Container(
                                      color: Colors.grey.shade800,
                                      child: const Center(
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            valueColor: AlwaysStoppedAnimation(Colors.white),
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                        ),
                        if (story.isPinned)
                          Positioned(
                              top: -4,
                              right: -4,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade700,
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black.withOpacity(0.2),
                                      blurRadius: 3,
                                      offset: const Offset(0, 1),
                                    ),
                                  ],
                                ),
                                child: const Icon(
                                  Icons.star,
                                  size: 12,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      // Kullanıcı adı
                      SizedBox(
                        height: 14,
                        child: Text(
                          username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w500,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      );
    } else {
      // Full stories (Social ekranında - fakat bu burada gösterilmemeli)
      return LayoutBuilder(
        builder: (context, constraints) {
          // Ekran genişliğine göre hesaplama - 3 story görünecek şekilde
          final screenWidth = constraints.maxWidth;
          final horizontalPadding = 16.0; // toplam padding (sağ + sol)
          final spacingBetweenCards = 8.0; // kartlar arası boşluk (2 kart arası = 8px)
          final availableWidth = screenWidth - horizontalPadding - spacingBetweenCards;
          final cardWidth = availableWidth / 3; // 3 kart için
          
          return SizedBox(
            height: 200,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              itemCount: _stories.length,
              itemBuilder: (context, index) {
                final story = _stories[index];
                final username = _usernames[story.userId] ?? 'Bilinmiyor';
                final avatarUrl = _userAvatars[story.userId];
                
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: GestureDetector(
                    onTap: () {
                      if (widget.onStoryTap != null) {
                        widget.onStoryTap!(index);
                      }
                    },
                    child: Container(
                      width: cardWidth,
                      height: 180,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Story içerik önizlemesi (displayUrl kullanıyoruz - video thumbnail varsa onu gösterir)
                            Image.network(
                              story.displayUrl,
                              fit: BoxFit.cover,
                              errorBuilder: (context, error, stackTrace) {
                                return Container(
                                  color: Colors.grey.shade800,
                                  child: const Icon(
                                    Icons.play_circle_outline,
                                    size: 48,
                                    color: Colors.white54,
                                  ),
                                );
                              },
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Container(
                                  color: Colors.grey.shade800,
                                  child: const Center(
                                    child: CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation(Colors.white),
                                    ),
                                  ),
                                );
                              },
                            ),
                            // Sponsor badge
                            if (story.isPinned)
                              Positioned(
                                bottom: 8,
                                left: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.shade700,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.star,
                                        size: 10,
                                        color: Colors.white,
                                      ),
                                      SizedBox(width: 3),
                                      Text(
                                        'Sponsor',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          shadows: [
                                            Shadow(
                                              color: Colors.black45,
                                              blurRadius: 2,
                                              offset: Offset(0, 1),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            // Beğeni butonu - aşağıda sağda
                            Positioned(
                              bottom: 8,
                              right: 8,
                              child: GestureDetector(
                                onTap: () => _toggleLike(story.id),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    // ignore: deprecated_member_use
                                    color: Colors.black.withOpacity(0.6),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        story.isLikedByCurrentUser ? Icons.favorite : Icons.favorite_border,
                                        size: 14,
                                        color: story.isLikedByCurrentUser ? Colors.red : Colors.white,
                                      ),
                                      if (story.likesCount > 0) ...[
                                        const SizedBox(width: 4),
                                        Text(
                                          _formatLikeCount(story.likesCount),
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 11,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            // Kullanıcı bilgisi - Gölge yok, sadece text shadow
                            Positioned(
                              top: 0,
                              left: 0,
                              right: 0,
                              child: Container(
                                padding: const EdgeInsets.all(8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    // Profil resmi
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.white,
                                          width: 2,
                                        ),
                                      ),
                                      child: ClipOval(
                                        child: avatarUrl != null && avatarUrl.isNotEmpty
                                            ? Image.network(
                                                avatarUrl,
                                                fit: BoxFit.cover,
                                                errorBuilder: (context, error, stackTrace) {
                                                  return Container(
                                                    color: Colors.grey.shade600,
                                                    child: Center(
                                                      child: Text(
                                                        username.isNotEmpty
                                                            ? username.substring(0, 1).toUpperCase()
                                                            : '?',
                                                        style: const TextStyle(
                                                          color: Colors.white,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: 14,
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                },
                                              )
                                            : Container(
                                                color: Colors.grey.shade600,
                                                child: Center(
                                                  child: Text(
                                                    username.isNotEmpty
                                                        ? username.substring(0, 1).toUpperCase()
                                                        : '?',
                                                    style: const TextStyle(
                                                      color: Colors.white,
                                                      fontWeight: FontWeight.bold,
                                                      fontSize: 14,
                                                    ),
                                                  ),
                                                ),
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Ad ve zaman bilgisi
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            username.isNotEmpty ? username : 'Bilinmiyor',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                              shadows: [
                                                Shadow(
                                                  color: Colors.black45,
                                                  blurRadius: 3,
                                                  offset: Offset(0, 1),
                                                ),
                                              ],
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _formatDate(story.createdAt),
                                            style: TextStyle(
                                              color: Colors.white70,
                                              fontSize: 10,
                                              shadows: [
                                                Shadow(
                                                  color: Colors.black45,
                                                  blurRadius: 3,
                                                  offset: Offset(0, 1),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      );
    }
  }
}
