// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import '../../../core/models/post_model.dart';
import '../../../core/models/analytics_model.dart';
import '../../../core/services/profile_view_service.dart';
import '../../../core/services/post_view_service.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../social/services/post_service.dart';
import '../../social/services/story_service.dart';
import '../../social/screens/post_likes_screen.dart';
import '../../social/screens/post_detail_screen.dart';
import '../../social/screens/story_viewer_screen.dart';
import '../services/profile_service.dart';
import '../services/follow_request_service.dart';
import '../../chat/services/chat_service.dart';
import '../../chat/screens/chat_detail_screen.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;

  const UserProfileScreen({
    super.key,
    required this.userId,
  });

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen> with TickerProviderStateMixin {
  Map<String, dynamic>? _userProfile;
  bool _isLoading = true;
  bool _isFollowing = false;
  List<Post> _userPosts = [];
  bool _isLoadingPosts = true;
  final _postService = PostService();
  final _storyService = StoryService();
  final _profileService = ProfileService();
  final _profileViewService = ProfileViewService();
  final _postViewService = PostViewService();
  final _chatService = ChatService();
  final _followRequestService = FollowRequestService();
  int _followersCount = 0;
  int _followingCount = 0;
  int _friendsCount = 0;
  Set<String> _likedPostIds = {};
  Set<String> _savedPosts = {};
  List<Story> _userStories = [];
  bool _isBlocked = false;
  bool _isProfilePrivate = false; // Gizli profil mi?
  String _followRequestStatus = 'none'; // none, pending, accepted, rejected
  String? _incomingFollowRequestId; // Bu kullanıcıdan bize gelen bekleyen istek ID'si
  CurrentMonthViewStats? _profileViewStats;
  CurrentMonthViewStats? _postViewStats;
  bool _isLoadingAnalytics = true;
  bool _showGrid = true;
  
  late AnimationController _statsAnimationController;
  late Animation<double> _statsAnimation;
  bool _statsExpanded = false;

  @override
  void initState() {
    super.initState();
    
    // Önceki verileri temizle - stale data sorununu önlemek için
    // Aynı sayfa tekrar açıldığında eski verilerin gösterilmesini engeller
    _userProfile = null;
    _userPosts.clear();
    _likedPostIds.clear();
    _savedPosts.clear();
    _userStories.clear();
    _followersCount = 0;
    _followingCount = 0;
    _friendsCount = 0;
    _isFollowing = false;
    _isProfilePrivate = false;
    _followRequestStatus = 'none';
    _incomingFollowRequestId = null;
    _isBlocked = false;
    _isLoading = true;
    _isLoadingPosts = true;
    _isLoadingAnalytics = true;
    
    _statsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _statsAnimation = CurvedAnimation(
      parent: _statsAnimationController,
      curve: Curves.easeInOut,
    );
    
    // Verileri yükle
    _loadUserProfile();
    _loadUserPosts();
    _loadFollowCounts(); // Takipçi sayısı için önce yükle
    _checkIfFollowing(); // Takip durumunu kontrol et
    _initializeFollowRequestStatus(); // Gizlilik kontrolü sonrası takip isteği kontrolü
    _loadUserStories();
    _checkIfBlocked();
    _trackProfileView();
    _loadAnalytics();
    _checkIncomingFollowRequest();
  }

  @override
  void dispose() {
    _statsAnimationController.dispose();
    super.dispose();
  }

  Future<void> _trackProfileView() async {
    await _profileViewService.trackProfileView(profileId: widget.userId);
  }

  Future<void> _loadAnalytics() async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isOwnProfile = currentUserId == widget.userId;

    if (!isOwnProfile) {
      if (mounted) setState(() => _isLoadingAnalytics = false);
      return;
    }

    try {
      if (mounted) setState(() => _isLoadingAnalytics = true);
      
      final profileStats = await _profileViewService.getCurrentMonthStats(widget.userId);
      if (!mounted) return;
      
      final postStats = await _postViewService.getCurrentMonthStats(widget.userId);
      if (!mounted) return;
      
      setState(() {
        _profileViewStats = profileStats;
        _postViewStats = postStats;
        _isLoadingAnalytics = false;
      });
    } catch (e) {
      if (mounted) setState(() => _isLoadingAnalytics = false);
    }
  }

  Future<void> _checkIfBlocked() async {
    try {
      final isBlocked = await _profileService.isUserBlocked(widget.userId);
      if (!mounted) return;
      setState(() => _isBlocked = isBlocked);
    } catch (e) {
      debugPrint('Engelleme durumu kontrol edilirken hata: $e');
    }
  }

  Future<void> _loadFollowCounts() async {
    try {
      final followersResponse = await Supabase.instance.client
          .from('follows')
          .select('follower_id')
          .eq('following_id', widget.userId);
      if (!mounted) return;

      final followingResponse = await Supabase.instance.client
          .from('follows')
          .select('following_id')
          .eq('follower_id', widget.userId);
      if (!mounted) return;

      // Karşılıklı takip edenler = Arkadaşlar
      final followers = (followersResponse as List).map((e) => e['follower_id'] as String).toSet();
      final following = (followingResponse as List).map((e) => e['following_id'] as String).toSet();
      final friends = followers.intersection(following);

      setState(() {
        _followersCount = followers.length;
        _followingCount = following.length;
        _friendsCount = friends.length;
      });
    } catch (e) {
      debugPrint('Takipçi sayıları yüklenirken hata: $e');
    }
  }

  Future<void> _loadSavedPosts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPosts = prefs.getStringList('saved_posts') ?? [];
      if (!mounted) return;
      setState(() => _savedPosts = savedPosts.toSet());
    } catch (e) {
      debugPrint('Kaydedilen gönderiler yüklenirken hata: $e');
    }
  }

  Future<void> _loadUserStories() async {
    try {
      final stories = await _storyService.getUserStories(widget.userId);
      if (!mounted) return;
      setState(() {
        _userStories = stories;
      });
    } catch (e) {
      debugPrint('Kullanıcı hikayeleri yüklenirken hata: $e');
    }
  }

  Future<void> _loadUserProfile() async {
    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('id, username, full_name, avatar_url, bio, cover_url, website, profile_is_public')
          .eq('id', widget.userId)
          .maybeSingle();
      if (!mounted) return;

      setState(() {
        _userProfile = response;
        _isProfilePrivate = response?['profile_is_public'] == false;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Profil yüklenirken hata: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _checkProfilePrivacy() async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null || currentUserId == widget.userId) return;

      // Önce _userProfile'dan kontrol et (zaten yüklenmiş olabilir)
      if (_userProfile != null) {
        final isPrivate = _userProfile!['profile_is_public'] == false;
        if (mounted) setState(() => _isProfilePrivate = isPrivate);
        return;
      }

      // Profil henüz yüklenmediyse service kullan
      final isPrivate = await _followRequestService.isProfilePrivate(widget.userId);
      if (!mounted) return;

      setState(() => _isProfilePrivate = isPrivate);
    } catch (e) {
      debugPrint('Profil gizliliği kontrol edilirken hata: $e');
    }
  }

  /// Gizlilik kontrolü sonrası takip isteği durumunu kontrol et
  Future<void> _initializeFollowRequestStatus() async {
    // Önce profil gizliliğini kontrol et
    await _checkProfilePrivacy();
    // Sonra takip isteği durumunu kontrol et (eğer gizli profil ise)
    if (_isProfilePrivate) {
      await _checkFollowRequestStatus();
    }
  }

  Future<void> _checkFollowRequestStatus() async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null || currentUserId == widget.userId) return;

      if (!_isProfilePrivate) {
        if (mounted) setState(() => _followRequestStatus = 'none');
        return;
      }

      final status = await _followRequestService.getFollowRequestStatus(widget.userId);
      if (!mounted) return;

      setState(() {
        _followRequestStatus = status;
        // İstek kabul edildiyse, follows tablosuna da eklenmiş demektir (SQL trigger)
        // Bu yüzden _isFollowing'i de true yapmalıyız
        if (status == 'accepted') {
          _isFollowing = true;
        }
      });
    } catch (e) {
      debugPrint('Takip isteği durumu kontrol edilirken hata: $e');
    }
  }

  Future<void> _loadUserPosts() async {
    try {
      if (mounted) setState(() => _isLoadingPosts = true);
      final posts = await _postService.getUserPosts(widget.userId);
      if (!mounted) return;
      
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId != null && posts.isNotEmpty) {
        final postIds = posts.map((p) => p.id).toList();
        _likedPostIds = await _postService.getLikedPostIds(currentUserId, postIds);
        if (!mounted) return;
      }
      
      // Kaydedilen gönderileri yükle
      await _loadSavedPosts();
      if (!mounted) return;
      
      setState(() {
        _userPosts = posts;
        _isLoadingPosts = false;
      });
    } catch (e) {
      debugPrint('Kullanıcı gönderileri yüklenirken hata: $e');
      if (mounted) setState(() => _isLoadingPosts = false);
    }
  }

  Future<void> _checkIfFollowing() async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null || currentUserId == widget.userId) return;

      final response = await Supabase.instance.client
          .from('follows')
          .select('id')
          .eq('follower_id', currentUserId)
          .eq('following_id', widget.userId)
          .maybeSingle();
      if (!mounted) return;

      setState(() => _isFollowing = response != null);
    } catch (e) {
      debugPrint('Takip durumu kontrol edilirken hata: $e');
    }
  }

  Future<void> _checkIncomingFollowRequest() async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null || currentUserId == widget.userId) return;

      final requestId = await _followRequestService.getIncomingFollowRequestId(widget.userId);
      if (!mounted) return;

      setState(() => _incomingFollowRequestId = requestId);
    } catch (e) {
      debugPrint('Gelen takip isteği kontrol edilirken hata: $e');
    }
  }

  Future<void> _acceptFollowRequest() async {
    if (_incomingFollowRequestId == null) return;

    try {
      await _followRequestService.acceptFollowRequest(_incomingFollowRequestId!);
      if (!mounted) return;

      // Durumu güncelle - takipçi sayısını hemen artır (optimistic update)
      setState(() {
        _incomingFollowRequestId = null;
        // NOT: _isFollowing burada true yapılMAMALI - bu, mevcut kullanıcının
        // karşı tarafı takip ettiği anlamına gelir. Ama burada karşı taraf BİZİ
        // takip etmeye başlıyor. _isFollowing sadece BİZİM onu takip etmemiz durumunda true olmalı.
        _followersCount += 1; // Optimistic: follows'a eklendi
        _followRequestStatus = 'accepted';
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Takip isteği kabul edildi'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            backgroundColor: Colors.green,
          ),
        );
      }

      // follows tablosuna eklendi, veritabanından gerçek sayıları al
      // Not: followRequestService zaten follows'a ekliyor, gecikmeye gerek yok
      if (mounted) {
        await _loadFollowCounts();
        await _checkIfFollowing();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('İşlem başarısız: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleFollow() async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null || !mounted) return;

      // Gizli profil kontrolü
      if (_isProfilePrivate && !_isFollowing) {
        // İstek zaten kabul edildiyse, durumu güncelle ve işlem yapma
        if (_followRequestStatus == 'accepted') {
          // Follows tablosuna eklenmiş olmalı, _isFollowing'i güncelle
          await _checkIfFollowing();
          await _loadFollowCounts();
          return;
        }
        // Gizli profil için takip isteği gönder
        if (_followRequestStatus == 'pending') {
          // Zaten bekleyen istek var, iptal et
          await _followRequestService.cancelFollowRequest(widget.userId);
          if (!mounted) return;
          setState(() => _followRequestStatus = 'none');
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Takip isteği iptal edildi'),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
          }
        } else {
          // Takip isteği gönder
          await _followRequestService.sendFollowRequest(widget.userId);
          if (!mounted) return;
          setState(() => _followRequestStatus = 'pending');
          
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Takip isteği gönderildi'),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
          }
        }
        return;
      }

      // Normal takip/takibi bırak işlemi (public profil veya zaten takip ediyor)
      if (_isFollowing) {
        await Supabase.instance.client
            .from('follows')
            .delete()
            .eq('follower_id', currentUserId)
            .eq('following_id', widget.userId);
        if (!mounted) return;

        // Gizli profillerde follow_requests kaydını da sil (tekrar istek atılabilsin)
        if (_isProfilePrivate) {
          await Supabase.instance.client
              .from('follow_requests')
              .delete()
              .eq('follower_id', currentUserId)
              .eq('following_id', widget.userId);
          if (!mounted) return;
          _followRequestStatus = 'none';
        }
      } else {
        // Önce zaten takip ediliyor mu kontrol et (duplicate key hatası önle)
        final existingFollow = await Supabase.instance.client
            .from('follows')
            .select('id')
            .eq('follower_id', currentUserId)
            .eq('following_id', widget.userId)
            .maybeSingle();
        
        if (existingFollow == null) {
          await Supabase.instance.client.from('follows').insert({
            'follower_id': currentUserId,
            'following_id': widget.userId,
          });
          if (!mounted) return;
          
          // Takip bildirimi gönder (trigger zaten gönderiyor ama yedek olarak)
          // NOT: SQL trigger 'notify_new_follower_trigger' zaten bildirim gönderiyor
        }
        if (!mounted) return;
      }

      setState(() => _isFollowing = !_isFollowing);
      await _loadFollowCounts();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _isFollowing ? 'Takip edilmeye başlandı' : 'Takip bırakıldı',
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İşlem başarısız: $e')),
        );
      }
    }
  }

  Future<void> _deletePost(String postId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade400, size: 28),
            const SizedBox(width: 10),
            const Text('Gönderiyi Sil'),
          ],
        ),
        content: const Text('Bu gönderiyi silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await _postService.deletePost(postId);
      if (!mounted) return;
      
      setState(() {
        _userPosts.removeWhere((post) => post.id == postId);
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Gönderi silindi'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Silme başarısız: $e')),
        );
      }
    }
  }

  void _showLikes(String postId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PostLikesScreen(postId: postId),
      ),
    );
  }

  Future<void> _refreshAll() async {
    await Future.wait([
      _loadUserProfile(),
      _loadUserPosts(),
      _loadUserStories(),
      _loadFollowCounts(),
      _loadAnalytics(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.black),
            onPressed: () => Navigator.pop(context),
          ),
          title: const Text('Profil', style: TextStyle(color: Colors.black)),
        ),
        body: CustomScrollView(
          slivers: [
            // Cover skeleton
            SliverAppBar(
              expandedHeight: 280,
              floating: false,
              pinned: true,
              backgroundColor: Colors.grey.shade100,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(
                  color: Colors.grey.shade200,
                ),
              ),
            ),
            // Profile info skeleton
            SliverToBoxAdapter(
              child: Container(
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Row(
                        children: [
                          // Profile avatar skeleton
                          SkeletonLoader.avatar(size: 88),
                          const SizedBox(width: 24),
                          // Stats skeleton
                          Expanded(
                            child: Column(
                              children: [
                                SkeletonLoader.text(width: 40),
                                const SizedBox(height: 4),
                                SkeletonLoader.text(width: 40, height: 12),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Name and bio skeleton
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SkeletonLoader.text(width: 120),
                          const SizedBox(height: 8),
                          SkeletonLoader.text(height: 14),
                          const SizedBox(height: 4),
                          SkeletonLoader.text(width: 200, height: 14),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Posts grid skeleton
            SliverToBoxAdapter(
              child: Skeletons.grid(itemCount: 9),
            ),
          ],
        ),
      );
    }

    if (_userProfile == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Profil'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_off_outlined, size: 64, color: Colors.grey.shade400),
              const SizedBox(height: 16),
              Text(
                'Profil bulunamadı',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final username = _userProfile?['username'] ?? 'Kullanıcı';
    final fullName = _userProfile?['full_name'] ?? username;
    final avatarUrl = _userProfile?['avatar_url'];
    final coverUrl = _userProfile?['cover_url'];
    final bio = _userProfile?['bio'];
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isOwnProfile = currentUserId == widget.userId;

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: RefreshIndicator(
        onRefresh: _refreshAll,
        displacement: 60,
        child: CustomScrollView(
          slivers: [
            // ===== SLIVER APP BAR - KAPAK FOTOĞRAFI =====
            SliverAppBar(
              expandedHeight: 280,
              floating: false,
              pinned: true,
              backgroundColor: Colors.white,
              surfaceTintColor: Colors.transparent,
              title: Text(
                '@$username',
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              leading: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black, size: 20),
                onPressed: () => Navigator.pop(context),
              ),
              actions: [
                // Paylaşım butonu (hem kendi profili hem başkasının profili için)
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.share_outlined, color: Colors.white, size: 20),
                  ),
                  onPressed: () {
                    final profileUrl = 'https://cizreapp.com/u/@$username';
                    Clipboard.setData(ClipboardData(text: profileUrl));
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Profil linki kopyalandı: $profileUrl'),
                        behavior: SnackBarBehavior.floating,
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  tooltip: 'Profili Paylaş',
                ),
                if (!isOwnProfile)
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.more_vert, color: Colors.white, size: 20),
                    ),
                    onPressed: () => _showProfileMenu(context),
                  ),
              ],
              flexibleSpace: FlexibleSpaceBar(
                background: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Kapak fotoğrafı
                    if (coverUrl != null && coverUrl.isNotEmpty)
                      GestureDetector(
                        onTap: () => _showFullScreenImage(coverUrl),
                        child: Image.network(
                          coverUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return _buildDefaultCover(context);
                          },
                        ),
                      )
                    else
                      _buildDefaultCover(context),
                    // Gradient overlay
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 120,
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.6),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Username overlay
                    Positioned(
                      bottom: 16,
                      left: 20,
                      child: Row(
                        children: [
                          Text(
                            '@$username',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.5,
                              shadows: [
                                Shadow(color: Colors.black54, blurRadius: 8),
                              ],
                            ),
                          ),
                          if (_isBlocked) ...[
                            const SizedBox(width: 10),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: Colors.red.withOpacity(0.8),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'Engelli',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ===== PROFİL BİLGİLERİ =====
            SliverToBoxAdapter(
              child: Container(
                color: Colors.white,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profil resmi + İstatistikler
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Row(
                        children: [
                          // Profil Resmi - Story çemberi ile
                          GestureDetector(
                            onTap: _userStories.isNotEmpty 
                              ? () => _openStories() 
                              : () => _showFullScreenImage(avatarUrl),
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: _userStories.isNotEmpty
                                    ? const LinearGradient(
                                        colors: [
                                          Color(0xFF833AB4),
                                          Color(0xFFE1306C),
                                          Color(0xFFF77737),
                                        ],
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                      )
                                    : null,
                                color: _userStories.isEmpty ? Colors.grey.shade200 : null,
                                boxShadow: _userStories.isNotEmpty ? [
                                  BoxShadow(
                                    color: Colors.pink.withOpacity(0.3),
                                    blurRadius: 12,
                                    spreadRadius: 2,
                                  ),
                                ] : [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    blurRadius: 8,
                                    spreadRadius: 1,
                                  ),
                                ],
                              ),
                              padding: const EdgeInsets.all(3),
                              child: CircleAvatar(
                                radius: 44,
                                backgroundColor: Colors.white,
                                child: CircleAvatar(
                                  radius: 42,
                                  backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                                  backgroundColor: Colors.grey.shade100,
                                  child: avatarUrl == null
                                      ? Text(
                                          username.isNotEmpty
                                              ? username.substring(0, 1).toUpperCase()
                                              : '?',
                                          style: TextStyle(
                                            fontSize: 36,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.grey.shade600,
                                          ),
                                        )
                                      : null,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 24),
                          // İstatistikler
                          Expanded(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: [
                                _buildStatItem('${_userPosts.length}', 'Gönderi'),
                                _buildStatItem('$_followersCount', 'Takipçi'),
                                _buildStatItem('$_followingCount', 'Takip'),
                                _buildStatItem('$_friendsCount', 'Arkadaş'),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // İsim ve bio
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            fullName,
                            style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.2,
                            ),
                          ),
                          if (bio != null && bio.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              bio,
                              style: TextStyle(
                                fontSize: 14,
                                height: 1.5,
                                color: Colors.grey.shade700,
                              ),
                            ),
                          ],
                          if (_userProfile!['website'] != null && _userProfile!['website'].toString().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () => _launchURL(_userProfile!['website']),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE3F2FD),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.link_rounded, size: 16, color: Colors.blue.shade700),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        _userProfile!['website'],
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: Colors.blue.shade700,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),

                    // ===== BUTONLAR =====
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      child: _buildActionButtons(isOwnProfile, fullName, avatarUrl),
                    ),

                    const SizedBox(height: 16),

                    // ===== ANALİTİK BÖLÜMÜ (sadece kendi profili) =====
                    if (isOwnProfile && !_isLoadingAnalytics && (_profileViewStats != null || _postViewStats != null))
                      _buildStatsSection(),

                    // ===== TAB BAR =====
                    Container(
                      decoration: BoxDecoration(
                        border: Border(
                          bottom: BorderSide(color: Colors.grey.shade200),
                        ),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _showGrid = true),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: _showGrid ? Colors.black : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                child: Icon(
                                  Icons.grid_on_rounded,
                                  color: _showGrid ? Colors.black : Colors.grey.shade400,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: GestureDetector(
                              onTap: () => setState(() => _showGrid = false),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 14),
                                decoration: BoxDecoration(
                                  border: Border(
                                    bottom: BorderSide(
                                      color: !_showGrid ? Colors.black : Colors.transparent,
                                      width: 2,
                                    ),
                                  ),
                                ),
                                child: Icon(
                                  Icons.view_agenda_outlined,
                                  color: !_showGrid ? Colors.black : Colors.grey.shade400,
                                  size: 24,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ===== GÖNDERİLER =====
            // Gizli profil ve takip edilmiyorsa gizli profil mesajı göster
            if (_isProfilePrivate && !_isFollowing && !isOwnProfile)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: _buildPrivateProfileMessage(),
                ),
              )
            else if (_isLoadingPosts)
              SliverToBoxAdapter(
                child: Skeletons.grid(itemCount: 6),
              )
            else if (_userPosts.isEmpty)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: _buildEmptyState(),
                ),
              )
            else if (_showGrid)
              _buildGridView()
            else
              _buildListView(isOwnProfile),

            const SliverToBoxAdapter(
              child: SizedBox(height: 100),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDefaultCover(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.indigo.shade400,
            Colors.purple.shade300,
            Colors.pink.shade200,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Center(
        child: Icon(
          Icons.photo_camera_outlined,
          size: 48,
          color: Colors.white.withOpacity(0.5),
        ),
      ),
    );
  }

  Widget _buildStatItem(String count, String label) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          count,
          style: const TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 13,
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildActionButtons(bool isOwnProfile, String fullName, String? avatarUrl) {
    if (!isOwnProfile) {
      // Gelen takip isteği var mı kontrol et
      final hasIncomingRequest = _incomingFollowRequestId != null;
      
      // Gizli profil ve takip edilmiyor kontrolü için buton metnini belirle
      String followButtonText = 'Takip Et';
      IconData followButtonIcon = Icons.person_add_outlined;
      bool showGradient = true;
      
      if (hasIncomingRequest) {
        followButtonText = 'Onayla';
        followButtonIcon = Icons.check_circle_outline;
        showGradient = false;
      } else if (_isProfilePrivate && !_isFollowing) {
        if (_followRequestStatus == 'pending') {
          followButtonText = 'İstek Gönderildi';
          followButtonIcon = Icons.schedule;
          showGradient = false;
        } else {
          followButtonText = 'Takip İsteği Gönder';
          followButtonIcon = Icons.person_add_outlined;
        }
      } else if (_isFollowing) {
        followButtonText = 'Takip Ediliyor';
        followButtonIcon = Icons.check;
        showGradient = false;
      }
      
      return Row(
        children: [
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                gradient: !hasIncomingRequest && showGradient && _followRequestStatus != 'pending'
                    ? LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.primary,
                          Theme.of(context).colorScheme.primary.withOpacity(0.8),
                        ],
                      )
                    : null,
                color: hasIncomingRequest
                    ? Colors.green.shade50
                    : (!showGradient || _followRequestStatus == 'pending'
                        ? Colors.grey.shade100
                        : null),
                borderRadius: BorderRadius.circular(12),
                border: !hasIncomingRequest && (!showGradient || _followRequestStatus == 'pending')
                    ? Border.all(color: Colors.grey.shade300)
                    : (hasIncomingRequest ? Border.all(color: Colors.green.shade300) : null),
                boxShadow: !hasIncomingRequest && showGradient && _followRequestStatus != 'pending'
                    ? [
                        BoxShadow(
                          color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                          blurRadius: 8,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : [],
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: hasIncomingRequest ? _acceptFollowRequest : _toggleFollow,
                  borderRadius: BorderRadius.circular(12),
                  child: Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          followButtonIcon,
                          size: 18,
                          color: hasIncomingRequest
                              ? Colors.green.shade700
                              : (showGradient && _followRequestStatus != 'pending'
                                  ? Colors.white
                                  : Colors.black87),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          followButtonText,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: hasIncomingRequest
                                ? Colors.green.shade700
                                : (showGradient && _followRequestStatus != 'pending'
                                    ? Colors.white
                                    : Colors.black87),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => _startChat(fullName, avatarUrl),
                  borderRadius: BorderRadius.circular(12),
                  child: const Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 18, color: Colors.black87),
                        SizedBox(width: 6),
                        Text(
                          'Mesaj',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.black87,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    // Kendi profil butonları
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () {},
                borderRadius: BorderRadius.circular(12),
                child: const Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.edit_outlined, size: 18, color: Colors.black87),
                      SizedBox(width: 8),
                      Text(
                        'Profili Düzenle',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: Colors.black87,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStatsSection() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.purple.shade50, Colors.pink.shade50],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.purple.shade100),
        boxShadow: [
          BoxShadow(
            color: Colors.purple.withOpacity(0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          InkWell(
            onTap: () {
              setState(() {
                _statsExpanded = !_statsExpanded;
                if (_statsExpanded) {
                  _statsAnimationController.forward();
                } else {
                  _statsAnimationController.reverse();
                }
              });
            },
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Colors.purple.shade400, Colors.pink.shade400],
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(Icons.bar_chart_rounded, color: Colors.white, size: 16),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Bu Ay İstatistiklerim',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: _statsAnimation,
                    builder: (context, child) {
                      return Transform.rotate(
                        angle: _statsAnimation.value * 3.14159,
                        child: Icon(
                          Icons.expand_more,
                          color: Colors.purple.shade700,
                          size: 20,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          SizeTransition(
            sizeFactor: _statsAnimation,
            axisAlignment: -1.0,
            child: FadeTransition(
              opacity: _statsAnimation,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  children: [
                    Divider(color: Colors.purple.shade100, height: 1),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        if (_profileViewStats != null)
                          Expanded(
                            child: _buildAnalyticsCard(
                              icon: Icons.visibility_rounded,
                              title: 'Profil Ziyaret',
                              count: _profileViewStats!.totalViews,
                              subtitle: '${_profileViewStats!.uniqueViewers} benzersiz',
                              color: Colors.blue,
                            ),
                          ),
                        if (_profileViewStats != null && _postViewStats != null)
                          const SizedBox(width: 12),
                        if (_postViewStats != null)
                          Expanded(
                            child: _buildAnalyticsCard(
                              icon: Icons.auto_graph_rounded,
                              title: 'Post Görüntüleme',
                              count: _postViewStats!.totalViews,
                              subtitle: '${_postViewStats!.uniqueViewers} benzersiz',
                              color: Colors.purple,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnalyticsCard({
    required IconData icon,
    required String title,
    required int count,
    required String subtitle,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: color, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey.shade700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            count.toString(),
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: color,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildPrivateProfileMessage() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.lock_outlined,
              size: 48,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Bu Hesap Gizli',
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w800,
              color: Colors.grey.shade800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Gönderilerini ve hikayelerini görmek için\ntakip isteği gönder.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
              height: 1.5,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 20),
          if (_followRequestStatus == 'pending')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.orange.shade200),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.schedule, size: 18, color: Colors.orange.shade700),
                  const SizedBox(width: 8),
                  Text(
                    'Takip isteği gönderildi',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.orange.shade700,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.camera_alt_outlined,
              size: 48,
              color: Colors.grey.shade400,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Henüz gönderi yok',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: Colors.grey.shade700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Bu kullanıcı henüz gönderi paylaşmadı.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ===== GRID GÖRÜNÜMÜ =====
  Widget _buildGridView() {
    return SliverPadding(
      padding: const EdgeInsets.all(2),
      sliver: SliverGrid(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          mainAxisSpacing: 2,
          crossAxisSpacing: 2,
          childAspectRatio: 1.0,
        ),
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final post = _userPosts[index];
            final firstImage = post.images.isNotEmpty ? post.images.first : null;
            
            return GestureDetector(
              onTap: () => _navigateToPostDetail(post),
              child: Container(
                color: Colors.grey.shade200,
                child: firstImage != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            firstImage,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                color: Colors.grey.shade200,
                                child: Icon(Icons.broken_image, color: Colors.grey.shade400),
                              );
                            },
                          ),
                          if (post.images.length > 1)
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Container(
                                padding: const EdgeInsets.all(3),
                                decoration: BoxDecoration(
                                  color: Colors.black.withOpacity(0.6),
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: const Icon(
                                  Icons.photo_library,
                                  color: Colors.white,
                                  size: 14,
                                ),
                              ),
                            ),
                          Positioned(
                            bottom: 0,
                            left: 0,
                            right: 0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                  colors: [
                                    Colors.black.withOpacity(0.5),
                                    Colors.transparent,
                                  ],
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.favorite, color: Colors.white, size: 12),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${post.likesCount}',
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.chat_bubble, color: Colors.white, size: 12),
                                  const SizedBox(width: 3),
                                  Text(
                                    '${post.commentsCount}',
                                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (post.content != null)
                              Padding(
                                padding: const EdgeInsets.all(6),
                                child: Text(
                                  post.content!,
                                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
            );
          },
          childCount: _userPosts.length,
        ),
      ),
    );
  }

  // ===== LİSTE GÖRÜNÜMÜ =====
  Widget _buildListView(bool isOwnProfile) {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final username = _userProfile?['username'] ?? 'Kullanıcı';
    final avatarUrl = _userProfile?['avatar_url'];

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final post = _userPosts[index];
            final firstImage = post.images.isNotEmpty ? post.images.first : null;
            
            return Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Card(
                elevation: 2,
                shadowColor: Colors.black.withOpacity(0.1),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Profil başlığı
                    Padding(
                      padding: const EdgeInsets.all(14),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 20,
                            backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                            backgroundColor: Colors.grey.shade200,
                            child: avatarUrl == null
                                ? Text(
                                    username.isNotEmpty
                                        ? username.substring(0, 1).toUpperCase()
                                        : '?',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade700,
                                    ),
                                  )
                                : null,
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  username,
                                  style: const TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                Text(
                                  _formatDate(post.createdAt),
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade500,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Resim
                    if (firstImage != null)
                      GestureDetector(
                        onTap: () => _navigateToPostDetail(post),
                        child: ClipRRect(
                          child: Image.network(
                            firstImage,
                            width: double.infinity,
                            height: 350,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
                              return Container(
                                height: 200,
                                color: Colors.grey.shade100,
                                child: const Icon(Icons.error_outline, size: 48),
                              );
                            },
                          ),
                        ),
                      ),
                    // İçerik
                    if (post.content != null && post.content!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                        child: Text(
                          post.content!,
                          style: TextStyle(
                            fontSize: 15,
                            height: 1.5,
                            color: Colors.grey.shade800,
                          ),
                        ),
                      ),
                    // Aksiyon butonları
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      child: Row(
                        children: [
                          IconButton(
                            icon: Icon(
                              _likedPostIds.contains(post.id)
                                  ? Icons.favorite
                                  : Icons.favorite_border,
                              color: _likedPostIds.contains(post.id) ? Colors.red : Colors.grey.shade700,
                              size: 26,
                            ),
                            onPressed: currentUserId != null
                                ? () => _toggleLike(post)
                                : null,
                          ),
                          InkWell(
                            onTap: () => _showLikes(post.id),
                            child: Text(
                              '${post.likesCount}',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.grey.shade800,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 16),
                          IconButton(
                            icon: Icon(
                              Icons.chat_bubble_outline,
                              color: Colors.grey.shade700,
                              size: 24,
                            ),
                            onPressed: () => _navigateToPostDetail(post),
                          ),
                          Text(
                            '${post.commentsCount}',
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.grey.shade800,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const Spacer(),
                          if (isOwnProfile)
                            IconButton(
                              icon: const Icon(Icons.delete_outline, color: Colors.red, size: 22),
                              onPressed: () => _deletePost(post.id),
                            ),
                          IconButton(
                            icon: Icon(
                              _savedPosts.contains(post.id) ? Icons.bookmark : Icons.bookmark_border,
                              color: _savedPosts.contains(post.id) ? Colors.amber : Colors.grey.shade700,
                              size: 22,
                            ),
                            onPressed: () => _savePost(post),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.send_outlined,
                              color: Colors.grey.shade700,
                              size: 22,
                            ),
                            onPressed: () => _sendToFriend(post),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.share_outlined,
                              color: Colors.grey.shade700,
                              size: 22,
                            ),
                            onPressed: () => _sharePost(post),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
          childCount: _userPosts.length,
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    
    if (diff.inMinutes < 1) return 'Az önce';
    if (diff.inMinutes < 60) return '${diff.inMinutes}dk önce';
    if (diff.inHours < 24) return '${diff.inHours}sa önce';
    if (diff.inDays < 7) return '${diff.inDays}g önce';
    
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '${date.day}/${date.month} $hour:$minute';
  }

  Future<void> _toggleLike(Post post) async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null || !mounted) return;

    final isLiked = _likedPostIds.contains(post.id);

    // Sadece liked durumunu güncelle
    setState(() {
      if (isLiked) {
        _likedPostIds.remove(post.id);
      } else {
        _likedPostIds.add(post.id);
      }
    });

    try {
      if (isLiked) {
        await _postService.unlikePost(post.id, currentUserId);
      } else {
        await _postService.likePost(post.id, currentUserId);
      }
      
      // Başarılıysa post'u yeniden yükle (count trigger'dan güncellenmiş olacak)
      final updatedPost = await _postService.getPostById(post.id);
      if (updatedPost != null && mounted) {
        setState(() {
          final index = _userPosts.indexWhere((p) => p.id == post.id);
          if (index != -1) {
            _userPosts[index] = updatedPost;
          }
        });
      }
    } catch (e) {
      // Hata olursa liked durumunu geri al
      if (mounted) {
        setState(() {
          if (isLiked) {
            _likedPostIds.add(post.id);
          } else {
            _likedPostIds.remove(post.id);
          }
        });
      }
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İşlem başarısız: $e')),
        );
      }
    }
  }

  void _navigateToPostDetail(Post post) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PostDetailScreen(post: post),
      ),
    ).then((_) {
      if (mounted) _loadUserPosts();
    });
  }

  void _openStories() {
    if (_userStories.isEmpty) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => StoryViewerScreen(
          stories: _userStories,
          initialIndex: 0,
        ),
      ),
    ).then((_) {
      if (mounted) _loadUserStories();
    });
  }

  Future<void> _launchURL(String url) async {
    String finalUrl = url;
    if (!url.startsWith('http://') && !url.startsWith('https://')) {
      finalUrl = 'https://$url';
    }
    
    final uri = Uri.parse(finalUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Link açılamadı: $url')),
        );
      }
    }
  }

  void _showFullScreenImage(String? imageUrl) {
    if (imageUrl == null || imageUrl.isEmpty) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            iconTheme: const IconThemeData(color: Colors.white),
            elevation: 0,
          ),
          body: Center(
            child: InteractiveViewer(
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.network(
                imageUrl,
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) {
                  return const Icon(
                    Icons.error_outline,
                    color: Colors.white,
                    size: 48,
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _startChat(String fullName, String? avatarUrl) async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Mesaj göndermek için giriş yapmalısınız')),
      );
      return;
    }
     
    // Kullanıcının mesaj alma özelliğini kontrol et
    final targetProfile = await Supabase.instance.client
        .from('profiles')
        .select('messages_enabled')
        .eq('id', widget.userId)
        .maybeSingle();
    
    if (targetProfile != null && targetProfile['messages_enabled'] == false) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Bu kullanıcının mesaj alma özelliği kapalı'),
            duration: Duration(seconds: 3),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }
    
    final conversation = await _chatService.getOrCreateConversation(widget.userId);
    if (conversation != null && mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ChatDetailScreen(
            conversationId: conversation.id,
            otherUserId: widget.userId,
            otherUserName: fullName,
            otherUserAvatar: avatarUrl,
          ),
        ),
      );
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Konuşma açılamadı. Lütfen tekrar deneyin.'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  void _showProfileMenu(BuildContext context) {
    final username = _userProfile?['username'] ?? '';
    final profileUrl = username.isNotEmpty ? 'https://cizreapp.com/u/@$username' : '';
    
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.flag_outlined, color: Colors.orange.shade400, size: 20),
              ),
              title: const Text('Şikayet Et / Bildir', style: TextStyle(fontWeight: FontWeight.w600)),
              trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
              onTap: () {
                Navigator.pop(context);
                _showReportDialog();
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _isBlocked ? Colors.green.shade50 : Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  _isBlocked ? Icons.check_circle_outline : Icons.block,
                  color: _isBlocked ? Colors.green.shade400 : Colors.red.shade400,
                  size: 20,
                ),
              ),
              title: Text(
                _isBlocked ? 'Engeli Kaldır' : 'Engelle',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
              onTap: () {
                Navigator.pop(context);
                _toggleBlock();
              },
            ),
            const Divider(),
            if (profileUrl.isNotEmpty)
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.share_outlined, color: Colors.blue.shade400, size: 20),
                ),
                title: const Text('Profili Paylaş', style: TextStyle(fontWeight: FontWeight.w600)),
                subtitle: Text(profileUrl, style: TextStyle(fontSize: 11, color: Colors.grey.shade600)),
                trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
                onTap: () {
                  Navigator.pop(context);
                  _copyToClipboard(profileUrl);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Profil linki kopyalandı'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
              ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.close, color: Colors.grey.shade500, size: 20),
              ),
              title: const Text('İptal'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  void _showReportDialog() {
    String selectedReason = 'spam';
    final reasonController = TextEditingController();
    final List<XFile> selectedImages = [];
    
    const Map<String, String> reportReasons = {
      'spam': 'Spam/Reklam',
      'harassment': 'Taciz/Rahatsızlık',
      'fake': 'Sahte Hesap',
      'inappropriate': 'Uygunsuz İçerik',
      'hate_speech': 'Nefret Söylemi',
      'violence': 'Şiddet/Tehdit',
      'impersonation': 'Kimliğe Bürünme',
      'scam': 'Dolandırıcılık',
      'other': 'Diğer',
    };
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.flag, color: Colors.orange.shade700, size: 24),
            ),
            const SizedBox(width: 12),
            const Text('Kullanıcıyı Şikayet Et', style: TextStyle(fontSize: 18)),
          ],
        ),
        content: StatefulBuilder(
          builder: (context, setStateDialog) => SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Uyarı mesajı
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Şikayetiniz ekibimiz tarafından incelenecek. Yanlış veya kötü niyetli şikayetler hesabınızın askıya alınmasına neden olabilir.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.orange.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Şikayet Nedeni:', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String>(
                      value: selectedReason,
                      isExpanded: true,
                      items: reportReasons.entries.map((entry) {
                        return DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        );
                      }).toList(),
                      onChanged: (value) {
                        if (value != null) {
                          setStateDialog(() => selectedReason = value);
                        }
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: reasonController,
                  maxLines: 3,
                  decoration: InputDecoration(
                    labelText: 'Açıklama (opsiyonel)',
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Kanıt Görseller (Opsiyonel):', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                if (selectedImages.isNotEmpty)
                  SizedBox(
                    height: 80,
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      scrollDirection: Axis.horizontal,
                      itemCount: selectedImages.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              SizedBox(
                                width: 80,
                                height: 80,
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.file(
                                    File(selectedImages[index].path),
                                    width: 80,
                                    height: 80,
                                    fit: BoxFit.cover,
                                    gaplessPlayback: true,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        width: 80,
                                        height: 80,
                                        color: Colors.grey.shade300,
                                        child: const Icon(Icons.broken_image, color: Colors.grey),
                                      );
                                    },
                                  ),
                                ),
                              ),
                              Positioned(
                                top: -4,
                                right: -4,
                                child: GestureDetector(
                                  onTap: () {
                                    setStateDialog(() {
                                      selectedImages.removeAt(index);
                                    });
                                  },
                                  child: Container(
                                    padding: const EdgeInsets.all(2),
                                    decoration: const BoxDecoration(
                                      color: Colors.red,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.close, size: 14, color: Colors.white),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                if (selectedImages.isNotEmpty) const SizedBox(height: 8),
                if (selectedImages.length < 3)
                  OutlinedButton.icon(
                    onPressed: () async {
                      final picker = ImagePicker();
                      final images = await picker.pickMultiImage(
                        maxWidth: 1920,
                        maxHeight: 1080,
                        imageQuality: 85,
                      );
                      if (images.isNotEmpty) {
                        setStateDialog(() {
                          selectedImages.addAll(images.take(3 - selectedImages.length));
                        });
                      }
                    },
                    icon: const Icon(Icons.add_photo_alternate, size: 18),
                    label: Text(
                      selectedImages.isEmpty ? 'Görsel Ekle (Maks. 3)' : '${3 - selectedImages.length} görsel daha',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 36),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              if (!mounted) return;
              
              // Loading dialog
              showDialog(
                context: this.context,
                barrierDismissible: false,
                builder: (loadingContext) => PopScope(
                  canPop: false,
                  child: AlertDialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    content: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(width: 16),
                        Text('Şikayet gönderiliyor...'),
                      ],
                    ),
                  ),
                ),
              );
              
              try {
                List<String> imageUrls = [];
                if (selectedImages.isNotEmpty) {
                  final currentUserId = Supabase.instance.client.auth.currentUser?.id;
                  if (currentUserId != null) {
                    for (int i = 0; i < selectedImages.length; i++) {
                      if (!mounted) return;
                      
                      final image = selectedImages[i];
                      final bytes = await image.readAsBytes();
                      if (!mounted) return;
                      
                      final extension = image.path.split('.').last.toLowerCase();
                      final fileName = '${currentUserId}_${DateTime.now().millisecondsSinceEpoch}_$i.$extension';
                      
                      await Supabase.instance.client.storage
                          .from('user_reports')
                          .uploadBinary(fileName, bytes);
                      if (!mounted) return;
                      
                      final publicUrl = Supabase.instance.client.storage
                          .from('user_reports')
                          .getPublicUrl(fileName);
                      
                      imageUrls.add(publicUrl);
                    }
                  }
                }
                
                if (!mounted) return;
                
                final result = await _profileService.reportUser(
                  reportedUserId: widget.userId,
                  reason: selectedReason,
                  description: reasonController.text.trim().isEmpty
                      ? null
                      : reasonController.text.trim(),
                  images: imageUrls.isNotEmpty ? imageUrls : null,
                );
                
                if (mounted && Navigator.canPop(this.context)) {
                  Navigator.pop(this.context);
                }
                
                if (!mounted) return;
                
                String message;
                Color backgroundColor;
                
                switch (result) {
                  case 'success':
                    message = 'Şikayetiniz alındı. En kısa sürede değerlendirilecektir.';
                    backgroundColor = Colors.green;
                    break;
                  case 'duplicate':
                    message = 'Bu kullanıcıyı daha önce şikayet etmişsiniz.';
                    backgroundColor = Colors.orange;
                    break;
                  case 'not_logged_in':
                    message = 'Lütfen giriş yapın.';
                    backgroundColor = Colors.red;
                    break;
                  case 'error':
                    message = 'Şikayet gönderilemedi. Lütfen tekrar deneyin. (Kod: RPT-ERR)';
                    backgroundColor = Colors.red;
                    break;
                  default:
                    message = 'Bilinmeyen hata: $result. Lütfen destek ile iletişime geçin.';
                    backgroundColor = Colors.red;
                }
                
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text(message),
                    backgroundColor: backgroundColor,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                );
              } catch (e) {
                if (mounted && Navigator.canPop(this.context)) {
                  Navigator.pop(this.context);
                }
                
                if (!mounted) return;
                
                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text('Şikayet gönderilemedi: $e'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Şikayet Et'),
          ),
        ],
      ),
    );
  }

  Future<void> _toggleBlock() async {
    try {
      final username = _userProfile?['username'] ?? 'Kullanıcı';
      final willBeBlocked = !_isBlocked;
      
      final confirm = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(
                willBeBlocked ? Icons.block : Icons.check_circle_outline,
                color: willBeBlocked ? Colors.red : Colors.green,
                size: 28,
              ),
              const SizedBox(width: 10),
              Text(willBeBlocked ? 'Engelle' : 'Engeli Kaldır'),
            ],
          ),
          content: Text(
            willBeBlocked
                ? '@$username kullanıcısını engellemek istediğinize emin misiniz? Engellediğiniz kullanıcılar sizin profilinizi ve gönderilerinizi göremez.'
                : '@$username kullanıcısının engelini kaldırmak istediğinize emin misiniz?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('İptal'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: willBeBlocked ? Colors.red : Colors.green,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(willBeBlocked ? 'Engelle' : 'Engeli Kaldır'),
            ),
          ],
        ),
      );

      if (confirm == true && mounted) {
        final success = await _profileService.blockUser(widget.userId);
        if (!mounted) return;
        
        setState(() => _isBlocked = success);
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success
                    ? '@$username engellendi'
                    : '@$username engeli kaldırıldı',
              ),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    }
  }

  // Paylaşım özellikleri
  Future<void> _sharePost(Post post) async {
    final postUrl = 'https://cizreapp.com/post/${post.id}';
    
    if (!mounted) return;
    
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => Container(
        decoration: BoxDecoration(
          color: Theme.of(context).scaffoldBackgroundColor,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Paylaş',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.chat, color: Colors.green.shade700),
                ),
                title: const Text('WhatsApp'),
                onTap: () {
                  Navigator.pop(context);
                  final whatsappUrl = 'https://wa.me/?text=${Uri.encodeComponent(postUrl)}';
                  launchUrl(Uri.parse(whatsappUrl), mode: LaunchMode.externalApplication);
                },
              ),
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.link, color: Colors.grey.shade700),
                ),
                title: const Text('Bağlantıyı Kopyala'),
                onTap: () {
                  Navigator.pop(context);
                  _copyToClipboard(postUrl);
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _sendToFriend(Post post) async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    try {
      final followingResponse = await Supabase.instance.client
          .from('follows')
          .select('following_id, profiles!inner(id, username, avatar_url)')
          .eq('follower_id', currentUserId);

      final following = (followingResponse as List).cast<Map<String, dynamic>>();

      if (!mounted) return;

      if (following.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Takip ettiğiniz kimse yok')),
        );
        return;
      }

      showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (context) => Container(
          height: MediaQuery.of(context).size.height * 0.6,
          decoration: BoxDecoration(
            color: Theme.of(context).scaffoldBackgroundColor,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  'Gönder',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: following.length,
                  itemBuilder: (context, index) {
                    final user = following[index];
                    final profile = user['profiles'] as Map<String, dynamic>?;
                    final username = profile?['username'] ?? 'kullanıcı';
                    final avatarUrl = profile?['avatar_url'];

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                        child: avatarUrl == null ? const Icon(Icons.person) : null,
                      ),
                      title: Text('@$username'),
                      onTap: () {
                        Navigator.pop(context);
                        _sendPostToFriend(profile?['id'], post);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      debugPrint('Takip listesi yüklenirken hata: $e');
    }
  }

  Future<void> _sendPostToFriend(String? targetUserId, Post post) async {
    if (targetUserId == null) return;

    try {
      await Supabase.instance.client.from('notifications').insert({
        'user_id': targetUserId,
        'type': 'post_share',
        'actor_id': Supabase.instance.client.auth.currentUser?.id,
        'post_id': post.id,
        'created_at': DateTime.now().toIso8601String(),
      });

      if (!mounted) return;

      // Push notification gönder
      await Supabase.instance.client.functions.invoke(
        'send-push',
        body: {
          'userId': targetUserId,
          'title': 'Gönderi Paylaşımı',
          'body': '${_userProfile?['username'] ?? 'Bir kullanıcı'} bir gönderi sizinle paylaştı',
          'data': {'type': 'post_share', 'postId': post.id},
        },
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gönderi paylaşildi')),
      );
    } catch (e) {
      debugPrint('Gönderi paylaşılırken hata: $e');
    }
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bağlantı kopyalandi')),
    );
  }

  Future<void> _savePost(Post post) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Lütfen giriş yapın')),
          );
        }
        return;
      }

      final result = await Supabase.instance.client.rpc('toggle_post_favorite', params: {
        'p_user_id': userId,
        'p_post_id': post.id,
      });

      final isFavorited = result as bool? ?? false;
      
      if (mounted) {
        setState(() {
          if (isFavorited) {
            _savedPosts.add(post.id);
          } else {
            _savedPosts.remove(post.id);
          }
        });
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isFavorited ? 'Gönderi kaydedildi' : 'Gönderi kaydedilenlerden kaldırıldı'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    }
  }
}
