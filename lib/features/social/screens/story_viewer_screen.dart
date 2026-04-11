// ignore_for_file: deprecated_member_use, duplicate_ignore

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/post_model.dart';
import '../../../core/utils/app_error_handler.dart';
import '../services/story_service.dart';
import 'story_viewers_screen.dart';
import '../../profile/screens/user_profile_screen.dart';

class StoryViewerScreen extends StatefulWidget {
  final List<Story> stories;
  final int initialIndex;

  const StoryViewerScreen({
    super.key,
    required this.stories,
    this.initialIndex = 0,
  });

  @override
  State<StoryViewerScreen> createState() => _StoryViewerScreenState();
}

class _StoryViewerScreenState extends State<StoryViewerScreen>
    with TickerProviderStateMixin {
  late PageController _pageController;
  late AnimationController _animationController;
  late int _currentIndex;
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  final StoryService _storyService = StoryService();
  double _dragOffset = 0.0;
  bool _isLiking = false;
  List<Story> _stories = [];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _stories = List.from(widget.stories);
    _pageController = PageController(initialPage: _currentIndex);
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 5),
    );
    _markStoryAsViewed(_stories[_currentIndex]);
    _startAutoPlay();
    
    // Listener'ı sadece bir kez ekle
    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _nextStory();
      }
    });
  }

  // Profil bilgilerini Story'den al (artık getStories ile birlikte geliyor)
  Map<String, dynamic> get _currentUserProfile {
    final story = _stories[_currentIndex];
    return {
      'id': story.userId,
      'username': story.username,
      'full_name': story.fullName,
      'avatar_url': story.avatarUrl,
    };
  }

  // Story görüntüleme kaydı yap (her story için sadece bir kez)
  final Set<String> _viewedStories = {};

  // Story görüntüleme kaydı yap
  Future<void> _markStoryAsViewed(Story story) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    // Kendi story'sini görüntüleme olarak kaydetme
    if (story.userId == userId) return;

    // Daha önce görüntülendiyse atla
    if (_viewedStories.contains(story.id)) return;

    try {
      await _storyService.viewStory(story.id, userId);
      _viewedStories.add(story.id); // Görüntülendi olarak işaretle
    } catch (e) {
      debugPrint('Story görüntüleme kaydı hatası: $e');
    }
  }

  void _startAutoPlay() {
    if (_animationController.isAnimating || _animationController.isCompleted) {
      _animationController.reset();
    }
    _animationController.forward();
  }

  void _nextStory() {
    try {
      if (_currentIndex < _stories.length - 1) {
        _pageController.nextPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      } else {
        // Son hikaye - ekranı kapat
        if (mounted) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      debugPrint('Next story error: $e');
    }
  }

  void _previousStory() {
    try {
      if (_currentIndex > 0) {
        _pageController.previousPage(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
        );
      }
    } catch (e) {
      debugPrint('Previous story error: $e');
    }
  }

  Future<void> _initializeVideo(String videoUrl) async {
    if (_videoController != null) {
      await _videoController!.dispose();
    }

    _videoController = VideoPlayerController.networkUrl(Uri.parse(videoUrl));
    try {
      await _videoController!.initialize();
      await _videoController!.setLooping(true);
      await _videoController!.play();
      if (mounted) {
        setState(() {
          _isVideoInitialized = true;
        });
      }
      _animationController.stop();
    } catch (e) {
      debugPrint('Video yüklenirken hata: $e');
      if (mounted) {
        setState(() {
          _isVideoInitialized = false;
        });
      }
    }
  }

  bool _isStoryOwner() {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    return currentUserId != null && _stories[_currentIndex].userId == currentUserId;
  }


  // Beğeni sayısını formatla
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

    setState(() => _isLiking = true);

    try {
      final storyIndex = _stories.indexWhere((s) => s.id == storyId);
      if (storyIndex != -1) {
        final story = _stories[storyIndex];
        final wasLiked = story.isLikedByCurrentUser;
        
        // Optimistik güncelleme
        setState(() {
          _stories[storyIndex] = story.copyWith(
            isLikedByCurrentUser: !wasLiked,
            likesCount: wasLiked ? story.likesCount - 1 : story.likesCount + 1,
          );
        });

        // API çağrısı
        await _storyService.toggleStoryLike(storyId);
      }
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
          SnackBar(content: Text(AppErrorHandler.handleError(e))),
        );
      }
    } finally {
      setState(() => _isLiking = false);
    }
  }

  Future<void> _deleteStory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Hikayeyi Sil'),
        content: const Text('Bu hikayeyi silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await _storyService.deleteStory(_stories[_currentIndex].id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hikaye silindi'),
            backgroundColor: Colors.green,
          ),
        );
        // Story listesinden çıkar ve kapat
        Navigator.pop(context, 'deleted');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppErrorHandler.handleError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _togglePinStory() async {
    try {
      final storyId = _stories[_currentIndex].id;
      final newPinStatus = await _storyService.togglePinStory(storyId);
      
      if (mounted) {
        setState(() {
          final storyIndex = _stories.indexWhere((s) => s.id == storyId);
          if (storyIndex != -1) {
            _stories[storyIndex] = _stories[storyIndex].copyWith(isPinned: newPinStatus);
          }
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(newPinStatus ? 'Hikaye sabitlendi' : 'Sabitleme kaldırıldı'),
            backgroundColor: newPinStatus ? Colors.amber : Colors.grey,
            duration: const Duration(seconds: 1),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppErrorHandler.handleError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    _animationController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        onVerticalDragUpdate: (details) {
          setState(() {
            _dragOffset += details.delta.dy;
          });
        },
        onVerticalDragEnd: (details) {
          if (_dragOffset < -100) {
            // Yukarı kaydırıldı - görüntüleyenler ekranını aç
            if (_isStoryOwner()) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => StoryViewersScreen(
                    storyId: widget.stories[_currentIndex].id,
                    totalViews: widget.stories[_currentIndex].viewsCount,
                  ),
                ),
              );
            }
          }
          setState(() {
            _dragOffset = 0;
          });
        },
        onTapDown: (details) {
          final width = MediaQuery.of(context).size.width;
          if (details.globalPosition.dx < width / 3) {
            _previousStory();
          } else if (details.globalPosition.dx > width * 2 / 3) {
            _nextStory();
          }
        },
        child: Transform.translate(
          offset: Offset(0, _dragOffset),
          child: Stack(
          children: [
            // Story content
            PageView.builder(
             controller: _pageController,
             onPageChanged: (index) {
               try {
                 if (index >= 0 && index < _stories.length) {
                   final story = _stories[index];
                   setState(() {
                     _currentIndex = index;
                     _animationController.reset();
                     
                     if (story.isVideo) {
                       _isVideoInitialized = false;
                       _videoController?.pause();
                     } else {
                       _videoController?.pause();
                       _isVideoInitialized = false;
                     }
                   });
                   
                   // Asynchronous işlemleri setState dışında yap
                   // Profil bilgileri artık Story içinde geliyor, ek sorgu gerekmiyor!
                   _markStoryAsViewed(story);
                   
                   if (story.isVideo) {
                     _initializeVideo(story.imageUrl);
                   } else {
                     _startAutoPlay();
                   }
                 }
               } catch (e) {
                 debugPrint('Page changed error: $e');
               }
             },
             itemCount: _stories.length,
              itemBuilder: (context, index) {
                if (index < 0 || index >= _stories.length) {
                  return Container(
                    color: Colors.black,
                    child: const Center(
                      child: Icon(Icons.error, color: Colors.white, size: 48),
                    ),
                  );
                }
                
                final story = _stories[index];
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    // Image or video background
                    if (story.isVideo && _isVideoInitialized && _videoController != null)
                      Center(
                        child: AspectRatio(
                          aspectRatio: _videoController!.value.aspectRatio,
                          child: VideoPlayer(_videoController!),
                        ),
                      )
                    else if (story.isVideo)
                      Container(
                        color: Colors.grey.shade900,
                        child: const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        ),
                      )
                    else
                      Image.network(
                        story.imageUrl,
                        fit: BoxFit.cover,
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            color: Colors.grey.shade900,
                            child: const Center(
                              child: CircularProgressIndicator(color: Colors.white),
                            ),
                          );
                        },
                        errorBuilder: (context, error, stackTrace) {
                          debugPrint('Image load error: $error');
                          return Container(
                            color: Colors.grey.shade900,
                            child: const Center(
                              child: Icon(Icons.error, color: Colors.white, size: 48),
                            ),
                          );
                        },
                      ),
                    
                    // Gradient üst kısım
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        height: 120,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              // ignore: deprecated_member_use
                              Colors.black.withOpacity(0.7),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
            
            // Progress bars
            Positioned(
              top: 48,
              left: 16,
              right: 16,
              child: Row(
                children: List.generate(
                  _stories.length,
                  (index) => Expanded(
                    child: Container(
                      height: 3,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: Colors.white30,
                        borderRadius: BorderRadius.circular(1.5),
                      ),
                      child: index == _currentIndex
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(1.5),
                              child: LinearProgressIndicator(
                                value: _animationController.value,
                                valueColor: const AlwaysStoppedAnimation<Color>(
                                  Colors.white,
                                ),
                              ),
                            )
                          : SizedBox(
                              height: 3,
                              child: Container(
                                decoration: BoxDecoration(
                                  color: index < _currentIndex
                                      ? Colors.white
                                      : Colors.white30,
                                  borderRadius: BorderRadius.circular(1.5),
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
              ),
            ),
            
            // User info
            Positioned(
              top: 60,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  // Profil resmi - Tıklanabilir
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => UserProfileScreen(
                            userId: _stories[_currentIndex].userId,
                            ),
                        ),
                      );
                    },
                    child: CircleAvatar(
                      radius: 18,
                      backgroundImage: _currentUserProfile['avatar_url'] != null
                          ? NetworkImage(_currentUserProfile['avatar_url'])
                          : null,
                      backgroundColor: Colors.white24,
                      child: _currentUserProfile['avatar_url'] == null
                          ? Text(
                              (_currentUserProfile['username']?.toString() ?? '?').substring(0, 1).toUpperCase(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            )
                          : null,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _currentUserProfile['full_name'] ?? _currentUserProfile['username'] ?? 'Kullanıcı',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                      Text(
                        _formatDate(_stories[_currentIndex].createdAt),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Story sahibi ise silme butonu
                  if (_isStoryOwner())
                    IconButton(
                      onPressed: _deleteStory,
                      icon: const Icon(Icons.delete_outline, color: Colors.white70, size: 20),
                      padding: EdgeInsets.zero,
                      splashRadius: 18,
                      constraints: const BoxConstraints(),
                    ),
                  // Görüntüleyenler butonu + sayı
                  if (_isStoryOwner())
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: GestureDetector(
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => StoryViewersScreen(
                                storyId: _stories[_currentIndex].id,
                                totalViews: _stories[_currentIndex].viewsCount,
                              ),
                            ),
                          );
                        },
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.visibility_outlined, color: Colors.white, size: 20),
                            const SizedBox(width: 4),
                            Text(
                              _stories[_currentIndex].viewsCount.toString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  // Video kontrolü
                  if (_stories[_currentIndex].isVideo && _isVideoInitialized)
                    IconButton(
                      onPressed: () {
                        setState(() {
                          if (_videoController!.value.isPlaying) {
                            _videoController!.pause();
                            _animationController.stop();
                          } else {
                            _videoController!.play();
                            _animationController.forward();
                          }
                        });
                      },
                      icon: Icon(
                        _videoController!.value.isPlaying ? Icons.pause : Icons.play_arrow,
                        color: Colors.white,
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      splashRadius: 18,
                      constraints: const BoxConstraints(),
                    ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                    padding: EdgeInsets.zero,
                    splashRadius: 18,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),
            
            // Beğeni butonu - aşağıda sağda
            Positioned(
              bottom: 100,
              right: 16,
              child: GestureDetector(
                onTap: _isLiking ? null : () => _toggleLike(_stories[_currentIndex].id),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.6),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _stories[_currentIndex].isLikedByCurrentUser ? Icons.favorite : Icons.favorite_border,
                        size: 20,
                        color: _stories[_currentIndex].isLikedByCurrentUser ? Colors.red : Colors.white,
                      ),
                      if (_stories[_currentIndex].likesCount > 0) ...[
                        const SizedBox(width: 6),
                        Text(
                          _formatLikeCount(_stories[_currentIndex].likesCount),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
          ),
        ),
      );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final localDate = date.toLocal();
    final difference = now.difference(localDate);

    if (difference.inSeconds < 60) {
      return 'Şimdi';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}dk önce';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}s önce';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}g önce';
    } else {
      final weeks = (difference.inDays / 7).floor();
      return '${weeks}h önce';
    }
  }
}
