// ignore_for_file: deprecated_member_use, duplicate_ignore

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/post_model.dart';
import '../../../core/utils/app_error_handler.dart';
import '../services/story_service.dart';
import 'story_viewers_screen.dart';
import '../../chat/services/chat_service.dart';
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
  final ChatService _chatService = ChatService();
  final TextEditingController _replyController = TextEditingController();
  final FocusNode _replyFocusNode = FocusNode();
  double _dragOffset = 0.0;
  bool _isLiking = false;
  bool _isSendingReply = false;
  /// Emoji seçim çubuğu açık mı (kalp butonuna uzun basınca açılır).
  bool _showReactionPicker = false;
  /// Ekranın ortasında beliren tepki animasyonu için (null = animasyon yok).
  String? _burstEmoji;
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
    _syncMyReaction(_stories[_currentIndex]);

    // İLK story videoysa da başlatılmalı. Önceden yalnızca onPageChanged'de
    // başlatıldığı için ilk açılışta video oynamıyor, başka story'ye geçip
    // dönünce oynuyordu. Burada ilk story tipine göre başlatıyoruz.
    final firstStory = _stories[_currentIndex];
    if (firstStory.isVideo) {
      _initializeVideo(firstStory.imageUrl);
    } else {
      _startAutoPlay();
    }

    // Listener'ı sadece bir kez ekle
    _animationController.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _nextStory();
      }
    });

    // Yanıt kutusuna odaklanılınca hikaye ilerlemesi dursun; klavye açıkken
    // hikaye kayıp gitmesin.
    _replyFocusNode.addListener(() {
      if (_replyFocusNode.hasFocus) {
        _pauseStory();
      } else if (!_showReactionPicker) {
        _resumeStory();
      }
    });
  }

  /// Bu hikayeye daha önce verdiğim tepkiyi sunucudan çekip ekrana yansıtır.
  ///
  /// Hikaye listesi bazı ekranlardan (bildirimler, profil) tepki bilgisi
  /// OLMADAN geliyor; bu senkron olmadan daha önce kalp attığım bir hikayede
  /// buton boş görünüyor ve tekrar dokununca tepki kaldırılmış oluyordu.
  Future<void> _syncMyReaction(Story story) async {
    if (_reactionSynced.contains(story.id)) return;
    _reactionSynced.add(story.id);

    try {
      final reaction = await _storyService.getMyReaction(story.id);
      if (!mounted || reaction == story.myReaction) return;
      setState(() {
        final index = _stories.indexWhere((s) => s.id == story.id);
        if (index != -1) {
          _stories[index] = _stories[index].copyWith(
            myReaction: reaction,
            isLikedByCurrentUser: reaction != null,
          );
        }
      });
    } catch (e) {
      debugPrint('Story tepkisi okunamadi: $e');
    }
  }

  /// Hikaye ilerlemesini duraklat (yanıt yazarken / emoji seçerken).
  void _pauseStory() {
    _animationController.stop();
    if (_videoController?.value.isPlaying ?? false) {
      _videoController?.pause();
    }
  }

  /// Duraklatılan hikayeyi kaldığı yerden sürdür.
  void _resumeStory() {
    if (!mounted) return;
    final story = _stories[_currentIndex];
    if (story.isVideo) {
      if (_isVideoInitialized) _videoController?.play();
    } else if (!_animationController.isAnimating &&
        _animationController.value < 1.0) {
      _animationController.forward();
    }
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

  // Tepki bilgisi sunucudan çekilen hikayeler (tekrar tekrar sorgulamamak için)
  final Set<String> _reactionSynced = {};

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

  /// Hikayeye tepki ver / tepkiyi kaldir.
  ///
  /// Ayni emojiye tekrar basmak tepkiyi geri alir (Instagram davranisi).
  /// Farkli bir emoji secmek mevcut tepkiyi gunceller; begeni sayaci artmaz.
  Future<void> _react(String storyId, String emoji) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tepki vermek icin giris yapmalisiniz')),
        );
      }
      return;
    }

    final storyIndex = _stories.indexWhere((s) => s.id == storyId);
    if (storyIndex == -1) return;

    final story = _stories[storyIndex];
    final previous = story.myReaction;
    final willRemove = previous == emoji;

    setState(() {
      _isLiking = true;
      _showReactionPicker = false;
      // Optimistik guncelleme: tepki degisince sayac yalnizca
      // "yok -> var" ve "var -> yok" gecislerinde degisir.
      _stories[storyIndex] = story.copyWith(
        myReaction: willRemove ? null : emoji,
        isLikedByCurrentUser: !willRemove,
        likesCount: willRemove
            ? (story.likesCount - 1).clamp(0, 1 << 30)
            : (previous == null ? story.likesCount + 1 : story.likesCount),
      );
      _burstEmoji = willRemove ? null : emoji;
    });

    if (!willRemove) {
      // Kisa bir "emoji ucusu" animasyonu; 900ms sonra temizlenir.
      Future.delayed(const Duration(milliseconds: 900), () {
        if (mounted) setState(() => _burstEmoji = null);
      });
    }

    try {
      await _storyService.setStoryReaction(storyId, emoji: emoji);
    } catch (e) {
      // Hata: optimistik degisikligi geri al
      if (mounted) {
        setState(() {
          final i = _stories.indexWhere((s) => s.id == storyId);
          if (i != -1) _stories[i] = story;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppErrorHandler.handleError(e))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLiking = false);
        _resumeStory();
      }
    }
  }

  /// Hikayeye yazili yanit gonder (DM olarak hikaye sahibine gider).
  Future<void> _sendReply() async {
    final text = _replyController.text.trim();
    if (text.isEmpty || _isSendingReply) return;

    final story = _stories[_currentIndex];
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Yanitlamak icin giris yapmalisiniz')),
      );
      return;
    }

    setState(() => _isSendingReply = true);
    _replyFocusNode.unfocus();

    try {
      final conversation =
          await _chatService.getOrCreateConversation(story.userId);
      if (conversation == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Sohbet baslatilamadi (karsi taraf mesajlari kapatmis olabilir).',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final sent = await _chatService.sendStoryReply(
        conversationId: conversation.id,
        text: text,
        storyIsVideo: story.isVideo,
      );

      if (!mounted) return;
      if (sent == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Yanit gonderilemedi'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }

      _replyController.clear();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Yanit gonderildi'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppErrorHandler.handleError(e))),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSendingReply = false);
        _resumeStory();
      }
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
    _replyController.dispose();
    _replyFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      // Hikaye medyası tam ekran kalsın diye Scaffold klavyeye göre
      // KÜÇÜLTÜLMÜYOR; bunun yerine yalnızca alt çubuk viewInsets kadar
      // yukarı taşınıyor (aşağıdaki Positioned). Her ikisi birden açık olsaydı
      // çubuk klavyenin iki katı yukarı kayardı.
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          _buildStoryStack(context),
          // Alt aksiyon çubuğu ekranın geri kalanını kaplayan dokunma
          // alanının DIŞINDA: aynı Stack içinde kalsaydı yanıt kutusuna
          // dokunmak hikayeyi bir sonrakine geçiriyordu.
          Positioned(
            left: 0,
            right: 0,
            bottom: MediaQuery.of(context).viewInsets.bottom,
            child: _buildBottomBar(),
          ),
        ],
      ),
    );
  }

  Widget _buildStoryStack(BuildContext context) {
    return GestureDetector(
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
                   _syncMyReaction(story);
                   
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
                      CachedNetworkImage(
                        imageUrl: story.imageUrl,
                        fit: BoxFit.cover,
                        placeholder: (context, url) {
                          return Container(
                            color: Colors.grey.shade900,
                            child: const Center(
                              child: CircularProgressIndicator(color: Colors.white),
                            ),
                          );
                        },
                        errorWidget: (context, url, error) {
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
            
            // Ortada beliren tepki animasyonu
            if (_burstEmoji != null)
              Positioned.fill(
                child: IgnorePointer(
                  child: Center(
                    child: TweenAnimationBuilder<double>(
                      key: ValueKey(_burstEmoji),
                      tween: Tween(begin: 0.4, end: 1.6),
                      duration: const Duration(milliseconds: 900),
                      curve: Curves.easeOutBack,
                      builder: (context, value, child) => Opacity(
                        opacity: (1.6 - value).clamp(0.0, 1.0),
                        child: Transform.scale(scale: value, child: child),
                      ),
                      child: Text(
                        _burstEmoji!,
                        style: const TextStyle(fontSize: 96),
                      ),
                    ),
                  ),
                ),
              ),

          ],
        ),
          ),
        );
  }

  /// Hikaye ekraninin alt cubugu.
  ///
  /// Kendi hikayemizde: tepki ozeti (kac tepki geldi).
  /// Baskasinin hikayesinde: yanit kutusu + hizli tepki emojileri.
  Widget _buildBottomBar() {
    final story = _stories[_currentIndex];
    final isOwner = _isStoryOwner();
    final myReaction = story.myReaction;

    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.transparent, Color(0xCC000000)],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Emoji secim cubugu (kalbe uzun basinca acilir)
            if (!isOwner && _showReactionPicker)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(28),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    for (final emoji in StoryService.quickReactions)
                      GestureDetector(
                        onTap: _isLiking ? null : () => _react(story.id, emoji),
                        child: AnimatedScale(
                          duration: const Duration(milliseconds: 150),
                          scale: myReaction == emoji ? 1.3 : 1.0,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              emoji,
                              style: const TextStyle(fontSize: 30),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),

            if (isOwner)
              // Kendi hikayem: tepki ozeti
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.favorite, color: Colors.redAccent, size: 18),
                  const SizedBox(width: 6),
                  Text(
                    story.likesCount > 0
                        ? '${_formatLikeCount(story.likesCount)} tepki'
                        : 'Henuz tepki yok',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              )
            else
              Row(
                children: [
                  // Yanit kutusu
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white38),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        controller: _replyController,
                        focusNode: _replyFocusNode,
                        style: const TextStyle(color: Colors.white, fontSize: 14),
                        cursorColor: Colors.white,
                        textInputAction: TextInputAction.send,
                        minLines: 1,
                        maxLines: 3,
                        maxLength: 500,
                        onSubmitted: (_) => _sendReply(),
                        decoration: const InputDecoration(
                          counterText: '',
                          isDense: true,
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                          hintText: 'Hikayeye yanit yaz...',
                          hintStyle:
                              TextStyle(color: Colors.white54, fontSize: 14),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),

                  // Gonder butonu (yalnizca metin varken gorunur)
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _replyController,
                    builder: (context, value, _) {
                      final hasText = value.text.trim().isNotEmpty;
                      if (!hasText) return const SizedBox.shrink();
                      return IconButton(
                        onPressed: _isSendingReply ? null : _sendReply,
                        icon: _isSendingReply
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const Icon(Icons.send_rounded,
                                color: Colors.white),
                      );
                    },
                  ),

                  // Tepki butonu: tek dokunus = kalp, uzun bas = emoji secici
                  GestureDetector(
                    onTap: _isLiking
                        ? null
                        : () => _react(story.id, StoryService.defaultReaction),
                    onLongPress: () {
                      setState(
                          () => _showReactionPicker = !_showReactionPicker);
                      if (_showReactionPicker) {
                        _pauseStory();
                      } else {
                        _resumeStory();
                      }
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: Colors.white38),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (myReaction != null)
                            Text(
                              myReaction,
                              style: const TextStyle(fontSize: 20),
                            )
                          else
                            const Icon(
                              Icons.favorite_border,
                              size: 20,
                              color: Colors.white,
                            ),
                          if (story.likesCount > 0) ...[
                            const SizedBox(width: 6),
                            Text(
                              _formatLikeCount(story.likesCount),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ],
              ),
          ],
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
