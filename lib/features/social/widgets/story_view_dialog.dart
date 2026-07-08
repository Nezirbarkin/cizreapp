import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import '../../../core/models/post_model.dart';
import '../screens/story_viewers_screen.dart';
import 'heart_animation_overlay.dart';

// Story görüntüleme dialog widget'ı
class StoryViewDialog extends StatefulWidget {
  final Story story;
  final Map<String, dynamic>? userProfile;
  final bool isOwner;
  final VoidCallback? onDelete;

  const StoryViewDialog({
    super.key,
    required this.story,
    this.userProfile,
    this.isOwner = false,
    this.onDelete,
  });

  @override
  State<StoryViewDialog> createState() => _StoryViewDialogState();
}

class _StoryViewDialogState extends State<StoryViewDialog> {
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  Map<String, dynamic>? _userProfile;

  @override
  void initState() {
    super.initState();
    _userProfile = widget.userProfile;
    _loadProfile();
    
    if (widget.story.isVideo) {
      _initializeVideo();
    } else {
      // Fotoğraflar için otomatik kapanma
      _autoClose();
    }
  }

  Future<void> _loadProfile() async {
    if (_userProfile != null) {
      return;
    }

    try {
      final profiles = await Supabase.instance.client
          .from('profiles')
          .select('id, username, full_name, avatar_url')
          .eq('id', widget.story.userId)
          .maybeSingle();

      if (mounted) {
        setState(() {
          _userProfile = profiles;
        });
      }
    } catch (e) {
      debugPrint('Profil yüklenirken hata: $e');
      if (mounted) {
      }
    }
  }

  Future<void> _initializeVideo() async {
    _videoController = VideoPlayerController.networkUrl(Uri.parse(widget.story.imageUrl));
    try {
      await _videoController!.initialize();
      await _videoController!.setLooping(true);
      await _videoController!.play();
      setState(() {
        _isVideoInitialized = true;
      });
      // Video süresi kadar bekle ve kapat
      _autoClose();
    } catch (e) {
      debugPrint('Video yüklenirken hata: $e');
    }
  }

  Future<void> _autoClose() async {
    // Video için 30 saniye, fotoğraf için 5 saniye
    final duration = widget.story.isVideo
        ? const Duration(seconds: 30)
        : const Duration(seconds: 5);
    
    await Future.delayed(duration);
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final username = _userProfile?['username'] ?? widget.story.userId.substring(0, 8);
    final fullName = _userProfile?['full_name'] ?? username;
    final avatarUrl = _userProfile?['avatar_url'];

    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: EdgeInsets.zero,
      child: Stack(
        children: [
          // Media content (video or image)
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: SizedBox(
              width: double.infinity,
              height: double.infinity,
              child: widget.story.isVideo
                  ? _isVideoInitialized && _videoController != null
                      ? VideoPlayer(_videoController!)
                      : const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        )
                  : CachedNetworkImage(
                      imageUrl: widget.story.imageUrl,
                      fit: BoxFit.contain,
                      placeholder: (context, url) {
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        );
                      },
                      errorWidget: (context, url, error) {
                        return const Center(
                          child: Icon(Icons.error, color: Colors.white, size: 48),
                        );
                      },
                    ),
            ),
          ),

          // User info overlay
          Positioned(
            top: 48,
            left: 16,
            right: 16,
            child: SafeArea(
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                    backgroundColor: Colors.grey,
                    child: avatarUrl == null
                        ? Text(
                            username.length >= 2
                                ? username.substring(0, 2).toUpperCase()
                                : username.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          )
                        : null,
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        fullName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      Text(
                        '@$username',
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const Spacer(),
                  // Hikaye sahibi ise "Sil" butonu
                  if (widget.isOwner)
                    IconButton(
                      onPressed: widget.onDelete,
                      icon: const Icon(Icons.delete, color: Colors.white70),
                      tooltip: 'Sil',
                    ),
                   // Hikaye sahibi ise "Görüntüleyenler" butonu
                   if (widget.isOwner)
                    IconButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => StoryViewersScreen(
                              storyId: widget.story.id,
                              totalViews: widget.story.viewsCount,
                            ),
                          ),
                        );
                      },
                      icon: const Icon(Icons.visibility, color: Colors.white),
                      tooltip: 'Görüntüleyenler',
                    ),
                  // Video ise play/pause butonu
                  if (widget.story.isVideo && _isVideoInitialized) ...[
                    IconButton(
                      onPressed: () {
                        setState(() {
                          if (_videoController!.value.isPlaying) {
                            _videoController!.pause();
                          } else {
                            _videoController!.play();
                          }
                        });
                      },
                      icon: Icon(
                        _videoController!.value.isPlaying
                            ? Icons.pause
                            : Icons.play_arrow,
                        color: Colors.white,
                      ),
                    ),
                  ],
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),

          // Progress bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: LinearProgressIndicator(
              value: 1.0,
              backgroundColor: Colors.white24,
              valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
            ),
          ),

          // Media type indicator
          Positioned(
            top: 60,
            right: 16,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    widget.story.isVideo ? Icons.videocam : Icons.image,
                    color: Colors.white,
                    size: 16,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    widget.story.isVideo ? 'Video' : 'Fotoğraf',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
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

  /// Instagram tarzı animasyonlu kalp efekti göster
  void _showLikeAnimation(BuildContext context) {
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final size = renderBox.size;
    
    // Kalp ikonu overlay'i oluştur
    final entry = OverlayEntry(
      builder: (context) => HeartAnimationOverlay(
        key: UniqueKey(),
        parentSize: size,
      ),
    );

    overlay.insert(entry);
    
    // 1.5 saniye sonra overlay'i kaldır
    Future.delayed(const Duration(milliseconds: 1500), () {
      entry.remove();
    });
  }
}
