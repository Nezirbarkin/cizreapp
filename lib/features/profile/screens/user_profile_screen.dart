// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:async';
import 'dart:io';
import '../../../core/models/post_model.dart';
import '../../../core/models/analytics_model.dart';
import '../../../core/services/profile_view_service.dart';
import '../../../core/services/post_view_service.dart';
import '../../../core/widgets/text_background.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../social/services/post_service.dart';
import '../../social/services/social_share_service.dart';
import '../../social/services/story_service.dart';
import '../../social/services/follow_service.dart';
import '../../social/models/follow_suggestion.dart' show FollowStatus;
import '../../../core/utils/app_error_handler.dart';
import '../../social/screens/post_likes_screen.dart';
import '../../social/screens/post_detail_screen.dart';
import '../../social/screens/story_viewer_screen.dart';
import '../services/profile_service.dart';
import '../services/follow_request_service.dart';
import 'followers_screen.dart';
import 'edit_profile_screen.dart';
import '../widgets/profile_shared_widgets.dart';
import '../../chat/models/chat_presence.dart';
import '../../chat/services/chat_service.dart';
import '../../chat/screens/chat_detail_screen.dart';
import '../../chat/widgets/presence_status_line.dart';
import '../../../kullaniciozellikler/widgets/profile_privileges.dart';
import '../../../kullaniciozellikler/widgets/cover_effect_frame.dart';
import '../widgets/profile_post_grid.dart';
import '../widgets/profile_share_sheet.dart';
import '../widgets/mutual_followers_line.dart';
import '../../social/widgets/heart_animation_overlay.dart';
import '../../social/widgets/social_post_card.dart';
import '../../social/widgets/impression_probe.dart';
import '../../social/widgets/post_insights_sheet.dart';
import '../../social/widgets/edit_post_sheet.dart';
import '../../social/services/muted_users_service.dart';
import '../../social/screens/hashtag_feed_screen.dart';
import '../../social/services/post_impression_tracker.dart';
import '../../social/widgets/send_to_friend_sheet.dart';

class UserProfileScreen extends StatefulWidget {
  final String userId;

  const UserProfileScreen({super.key, required this.userId});

  @override
  State<UserProfileScreen> createState() => _UserProfileScreenState();
}

class _UserProfileScreenState extends State<UserProfileScreen>
    with TickerProviderStateMixin {
  Map<String, dynamic>? _userProfile;
  bool _isLoading = true;
  bool _isFollowing = false;
  List<Post> _userPosts = [];
  bool _isLoadingPosts = true;
  // Gönderi ızgarası sayfalı (PostService.userPostsPageSize).
  bool _postsHasMore = false;
  bool _loadingMorePosts = false;
  final ScrollController _profileScroll = ScrollController();
  final _postService = PostService();
  final _storyService = StoryService();
  final _profileService = ProfileService();
  final _profileViewService = ProfileViewService();
  final _postViewService = PostViewService();
  final _chatService = ChatService();
  final _followRequestService = FollowRequestService();
  final _followService = FollowService();
  // Takip isteği sürerken ikinci dokunuş yok sayılır.
  bool _followBusy = false;
  // Sunucudaki etkin gönderi sayısı (gizli hesapta da doğru; null = henüz yok).
  int? _postsCount;
  int _followersCount = 0;
  int _followingCount = 0;
  int _friendsCount = 0;
  Set<String> _likedPostIds = {};
  Set<String> _savedPosts = {};
  List<Story> _userStories = [];
  bool _isBlocked = false;
  bool _isProfilePrivate = false; // Gizli profil mi?
  String _followRequestStatus = 'none'; // none, pending, accepted, rejected
  String?
  _incomingFollowRequestId; // Bu kullanıcıdan bize gelen bekleyen istek ID'si
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
    // Menüdeki "Sessize al / Sesi aç" için (oturumda bir kez yüklenir).
    MutedUsersService.instance.ensureLoaded();

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

    _profileScroll.addListener(_onProfileScroll);
    _statsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _statsAnimation = CurvedAnimation(
      parent: _statsAnimationController,
      curve: Curves.easeInOut,
    );

    // Verileri yükle
    // Hepsi aynı anda başlar; ilişki durumları (takip, istek, gelen istek,
    // engel) eskiden dört ayrı istek + dört ayrı setState idi, birbirini
    // ezebiliyordu — artık tek yüklemede.
    _loadUserProfile();
    _loadUserPosts();
    _loadFollowCounts();
    _loadRelationship();
    _loadUserStories();
    _trackProfileView();
    _loadAnalytics();
  }

  @override
  void dispose() {
    _statsAnimationController.dispose();
    _profileScroll.dispose();
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

      final (profileStats, postStats) = await (
        _profileViewService.getCurrentMonthStats(widget.userId),
        _postViewService.getCurrentMonthStats(widget.userId),
      ).wait;
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

  Future<void> _loadFollowCounts() async {
    try {
      final counts = await _profileService.getFollowCounts(widget.userId);
      if (!mounted) return;
      setState(() {
        _followersCount = counts.followers;
        _followingCount = counts.following;
        _friendsCount = counts.friends;
        _postsCount = counts.posts;
      });
    } catch (e) {
      debugPrint('Takipçi sayıları yüklenirken hata: $e');
    }
  }

  // Kayıtlı gönderiler tek kaynaktan (post_favorites) okunuyor; eskiden
  // SharedPreferences'tan okunduğu için buradan kaydedilen gönderinin
  // yer imi ikonu dolu görünmüyordu.
  Future<void> _loadSavedPosts() async {
    try {
      await _postService.migrateLegacyLocalSaves();
      final saved = await _postService.getSavedPostIds();
      if (!mounted) return;
      setState(() => _savedPosts = saved);
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
      // profiles tablosu RLS nedeniyle başka kullanıcıları döndürmez.
      // public_profiles_safe SECURITY DEFINER view; tüm public profilleri
      // RLS bypass ile okur. (cover_url ve website sütunları public view'da
      // zaten var.)
      final response = await Supabase.instance.client
          .from('public_profiles_safe')
          .select(
            'id, username, full_name, avatar_url, bio, cover_url, website, profile_is_public',
          )
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

  /// Benimle bu kişi arasındaki ilişki: takip ediyor muyum, bekleyen isteğim
  /// var mı, bana gelen bekleyen istek, engelledim mi. Tek doğru kaynak
  /// `follows`: eski bir "accepted" istek satırı takip anlamına gelmez
  /// (eskiden iki kontrol yarışıp düğmeyi kilitliyordu).
  Future<void> _loadRelationship() async {
    final me = Supabase.instance.client.auth.currentUser?.id;
    if (me == null || me == widget.userId) return;
    try {
      final (follow, requestStatus, incomingId, blocked) = await (
        Supabase.instance.client
            .from('follows')
            .select('id')
            .eq('follower_id', me)
            .eq('following_id', widget.userId)
            .maybeSingle(),
        _followRequestService.getFollowRequestStatus(widget.userId),
        _followRequestService.getIncomingFollowRequestId(widget.userId),
        _profileService.isUserBlocked(widget.userId),
      ).wait;
      if (!mounted) return;
      setState(() {
        _isFollowing = follow != null;
        _followRequestStatus = !_isFollowing && requestStatus == 'pending'
            ? 'pending'
            : 'none';
        _incomingFollowRequestId = incomingId;
        _isBlocked = blocked;
      });
    } catch (e) {
      debugPrint('Takip/engel durumu yüklenirken hata: $e');
    }
  }

  Future<void> _loadUserPosts() async {
    try {
      if (mounted) setState(() => _isLoadingPosts = true);
      // Kaydedilenler gönderilerden bağımsız: aynı anda başlar.
      final savedLoad = _loadSavedPosts();
      final posts = await _postService.getUserPosts(widget.userId);
      if (!mounted) return;

      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId != null && posts.isNotEmpty) {
        final postIds = posts.map((p) => p.id).toList();
        _likedPostIds = await _postService.getLikedPostIds(
          currentUserId,
          postIds,
        );
        if (!mounted) return;
      }

      await savedLoad;
      if (!mounted) return;

      setState(() {
        _userPosts = posts;
        _isLoadingPosts = false;
        _postsHasMore = posts.length >= PostService.userPostsPageSize;
      });
    } catch (e) {
      debugPrint('Kullanıcı gönderileri yüklenirken hata: $e');
      if (mounted) setState(() => _isLoadingPosts = false);
    }
  }

  /// Izgaranın sonraki sayfası (kaydırma sona yaklaşınca).
  Future<void> _loadMorePosts() async {
    if (_loadingMorePosts || !_postsHasMore || _isLoadingPosts) return;
    final targetUserId = widget.userId;
    setState(() => _loadingMorePosts = true);
    try {
      final more = await _postService.getUserPosts(
        targetUserId,
        offset: _userPosts.length,
      );
      final me = Supabase.instance.client.auth.currentUser?.id;
      final liked = me != null && more.isNotEmpty
          ? await _postService.getLikedPostIds(
              me,
              more.map((p) => p.id).toList(),
            )
          : <String>{};
      if (!mounted) return;
      final known = {for (final p in _userPosts) p.id};
      setState(() {
        _userPosts = [
          ..._userPosts,
          ...more.where((p) => !known.contains(p.id)),
        ];
        _likedPostIds = {..._likedPostIds, ...liked};
        _postsHasMore = more.length >= PostService.userPostsPageSize;
        _loadingMorePosts = false;
      });
    } catch (e) {
      debugPrint('Sonraki gönderiler yüklenemedi: $e');
      if (mounted) setState(() => _loadingMorePosts = false);
    }
  }

  void _onProfileScroll() {
    if (!_profileScroll.hasClients) return;
    final position = _profileScroll.position;
    if (position.extentAfter < 600) _loadMorePosts();
  }

  Future<void> _acceptFollowRequest() async {
    if (_incomingFollowRequestId == null) return;
    final messenger = ScaffoldMessenger.of(context);

    try {
      await _followRequestService.acceptFollowRequest(
        _incomingFollowRequestId!,
      );
      if (!mounted) return;

      // Bu kişi artık BENİ takip ediyor: onun "takip" sayısı artar (onun
      // takipçi sayısı değil). Benim ona gönderdiğim isteğin durumu
      // değişmez — eskiden burada "accepted" yazılıyor ve geri takip düğmesi
      // hiçbir şey yapmıyordu.
      setState(() {
        _incomingFollowRequestId = null;
        _followingCount += 1;
      });

      messenger.showSnackBar(
        SnackBar(
          content: const Text('Takip isteği kabul edildi'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          backgroundColor: Colors.green,
        ),
      );

      await _loadFollowCounts();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(AppErrorHandler.handleError(e)),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  /// Takip et / takibi bırak / isteği geri al — tek RPC (`social_follow`).
  /// Gizli hesapta sunucu istek açar, açık hesapta takip eder; düğme ve
  /// takipçi sayısı dönen sonuçtan kurulur. Eskiden tabloya doğrudan
  /// yazılıyordu: gizlilik bayrağı eskiyse ya da engel varsa RLS reddi ham
  /// "PostgrestException" olarak görünüyor, her dokunuşta iki tam takip
  /// listesi yeniden indiriliyordu.
  Future<void> _toggleFollow() async {
    // Messenger ilk await'ten ONCE yakalanir (deactive pencere tuzağı).
    final messenger = ScaffoldMessenger.of(context);
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null || _followBusy) return;

    final wasActive = _isFollowing || _followRequestStatus == 'pending';
    final wasFollowing = _isFollowing;
    setState(() => _followBusy = true);
    try {
      final result = wasActive
          ? await _followService.unfollow(widget.userId)
          : await _followService.follow(widget.userId);
      if (!mounted) return;

      setState(() {
        _isFollowing = result.status == FollowStatus.following;
        _followRequestStatus =
            result.status == FollowStatus.requested ? 'pending' : 'none';
        _followersCount = result.followersCount;
      });

      final message = switch (result.status) {
        FollowStatus.following => 'Takip edilmeye başlandı',
        FollowStatus.requested => 'Takip isteği gönderildi',
        FollowStatus.none => wasFollowing
            ? 'Takip bırakıldı'
            : 'Takip isteği iptal edildi',
      };
      messenger.showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      );

      // Gizli hesapta takip başlayınca/bitince gönderi ve hikâyelerin
      // görünürlüğü değişir (RLS).
      if (_isProfilePrivate && wasFollowing != _isFollowing) {
        _loadUserPosts();
        _loadUserStories();
      }
      // Arkadaş (karşılıklı) sayısı da değişebilir.
      unawaited(_loadFollowCounts());
    } on FollowException catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(e.message)));
      }
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text(AppErrorHandler.handleError(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _followBusy = false);
    }
  }

  Future<void> _deletePost(String postId) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.red.shade400,
              size: 28,
            ),
            const SizedBox(width: 10),
            const Text('Gönderiyi Sil'),
          ],
        ),
        content: const Text(
          'Bu gönderiyi silmek istediğinizden emin misiniz? Bu işlem geri alınamaz.',
        ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Silme başarısız: $e')));
      }
    }
  }

  void _showLikes(String postId) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => PostLikesScreen(postId: postId)),
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
              expandedHeight: 400,
              floating: false,
              pinned: true,
              backgroundColor: Colors.grey.shade100,
              flexibleSpace: FlexibleSpaceBar(
                background: Container(color: Colors.grey.shade200),
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
            SliverToBoxAdapter(child: Skeletons.grid(itemCount: 9)),
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
              Icon(
                Icons.person_off_outlined,
                size: 64,
                color: Colors.grey.shade400,
              ),
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

    return ProfilePrivilegesOverlay(
      userId: widget.userId,
      child: Scaffold(
        backgroundColor: Colors.grey.shade50,
        body: RefreshIndicator(
          onRefresh: _refreshAll,
          displacement: 60,
          child: CustomScrollView(
            controller: _profileScroll,
            slivers: [
              // ===== SLIVER APP BAR - KAPAK FOTOĞRAFI =====
              SliverAppBar(
                expandedHeight: 400,
                floating: false,
                pinned: true,
                backgroundColor: const Color(0xFF17232D),
                surfaceTintColor: Colors.transparent,
                title: Text(
                  '@$username',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                leading: IconButton(
                  icon: const Icon(
                    Icons.arrow_back,
                    color: Colors.white,
                    size: 20,
                  ),
                  onPressed: () => Navigator.pop(context),
                ),
                actions: [
                  // Paylaşım butonu (hem kendi profili hem başkasının profili için)
                  IconButton(
                    icon: const Icon(
                      Icons.share_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                    // QR kodlu paylaşım sayfası (link kopyala / paylaş / QR).
                    onPressed: () => showProfileShareSheet(
                      context,
                      username: username,
                      fullName: _userProfile?['full_name']?.toString(),
                      avatarUrl: _userProfile?['avatar_url']?.toString(),
                    ),
                    tooltip: 'Profili Paylaş',
                  ),
                  if (!isOwnProfile)
                    IconButton(
                      icon: const Icon(
                        Icons.more_vert,
                        color: Colors.white,
                        size: 23,
                      ),
                      onPressed: () => _showProfileMenu(context),
                    ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: CoverEffectFrame(
                    userId: widget.userId,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        // Kapak fotoğrafı
                        if (coverUrl != null && coverUrl.isNotEmpty)
                          GestureDetector(
                            onTap: () => showFullScreenImage(context, coverUrl),
                            child: CachedNetworkImage(
                              memCacheWidth: 1000,
                              imageUrl: coverUrl,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) {
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
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          child: ProfileHeroHeader(
                            userId: widget.userId,
                            username: username,
                            avatarUrl: avatarUrl,
                            hasStories: _userStories.isNotEmpty,
                            postsCount: _postsCount ?? _userPosts.length,
                            followersCount: _followersCount,
                            followingCount: _followingCount,
                            friendsCount: _friendsCount,
                            onAvatarTap: _userStories.isNotEmpty
                                ? _openStories
                                : () => showFullScreenImage(context, avatarUrl),
                            onFollowersTap: () =>
                                _navigateToFollowList(FollowListType.followers),
                            onFollowingTap: () =>
                                _navigateToFollowList(FollowListType.following),
                            onFriendsTap: () =>
                                _navigateToFollowList(FollowListType.friends),
                          ),
                        ),
                      ],
                    ),
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
                      ProfileIdentityHeader(
                        userId: widget.userId,
                        username: username,
                        fullName: fullName,
                        avatarUrl: avatarUrl,
                        bio: bio,
                        hasStories: _userStories.isNotEmpty,
                        postsCount: _postsCount ?? _userPosts.length,
                        followersCount: _followersCount,
                        followingCount: _followingCount,
                        friendsCount: _friendsCount,
                        onAvatarTap: _userStories.isNotEmpty
                            ? _openStories
                            : () => showFullScreenImage(context, avatarUrl),
                        onFollowersTap: () =>
                            _navigateToFollowList(FollowListType.followers),
                        onFollowingTap: () =>
                            _navigateToFollowList(FollowListType.following),
                        onFriendsTap: () =>
                            _navigateToFollowList(FollowListType.friends),
                        website: _buildWebsiteChip(),
                        // Kendi profilimde gösterilmez. Kimin neyi göreceğine sunucu
                        // karar verir (engel, gizli hesap, hayalet, "son görülmeyi
                        // gizle", yönetici ayarı, 7 gün sınırı).
                        presenceLine: isOwnProfile
                            ? null
                            : PresenceStatusLine(
                                userId: widget.userId,
                                presenceContext: PresenceContext.profile,
                                style: PresenceLineStyle.onLight,
                                fontSize: 12.5,
                                showClockIcon: true,
                              ),
                        showHero: false,
                        statusBadge: _isBlocked
                            ? Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFEE2E2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  'Engelli',
                                  style: TextStyle(
                                    color: Color(0xFFB91C1C),
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              )
                            : ProfilePrivilegeBadges(userId: widget.userId),
                      ),

                      // "X, Y ve N kişi daha takip ediyor" (ortak kimse yoksa boş).
                      if (!isOwnProfile) MutualFollowersLine(userId: widget.userId),

                      const SizedBox(height: 16),

                      // ===== BUTONLAR =====
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildActionButtons(
                          isOwnProfile,
                          fullName,
                          avatarUrl,
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ===== ANALİTİK BÖLÜMÜ (sadece kendi profili) =====
                      if (isOwnProfile &&
                          !_isLoadingAnalytics &&
                          (_profileViewStats != null || _postViewStats != null))
                        ProfileStatsSection(
                          animation: _statsAnimation,
                          profileStats: _profileViewStats,
                          postStats: _postViewStats,
                          onToggle: () {
                            setState(() {
                              _statsExpanded = !_statsExpanded;
                              if (_statsExpanded) {
                                _statsAnimationController.forward();
                              } else {
                                _statsAnimationController.reverse();
                              }
                            });
                          },
                        ),

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
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: _showGrid
                                            ? Colors.black
                                            : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.grid_on_rounded,
                                    color: _showGrid
                                        ? Colors.black
                                        : Colors.grey.shade400,
                                    size: 24,
                                  ),
                                ),
                              ),
                            ),
                            Expanded(
                              child: GestureDetector(
                                onTap: () => setState(() => _showGrid = false),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 14,
                                  ),
                                  decoration: BoxDecoration(
                                    border: Border(
                                      bottom: BorderSide(
                                        color: !_showGrid
                                            ? Colors.black
                                            : Colors.transparent,
                                        width: 2,
                                      ),
                                    ),
                                  ),
                                  child: Icon(
                                    Icons.view_agenda_outlined,
                                    color: !_showGrid
                                        ? Colors.black
                                        : Colors.grey.shade400,
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
                SliverToBoxAdapter(child: Skeletons.grid(itemCount: 6))
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

              if (_loadingMorePosts)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  ),
                ),
              const SliverToBoxAdapter(child: SizedBox(height: 100)),
            ],
          ),
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

  Widget? _buildWebsiteChip() {
    final website = _userProfile?['website']?.toString().trim() ?? '';
    if (website.isEmpty) return null;

    return InkWell(
      onTap: () => _launchURL(website),
      borderRadius: BorderRadius.circular(11),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 270),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: const Color(0xFFE5E7EB)),
          boxShadow: const [
            BoxShadow(
              color: Color(0x18000000),
              blurRadius: 7,
              offset: Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.link_rounded, size: 17, color: Color(0xFF374151)),
            const SizedBox(width: 7),
            Flexible(
              child: Text(
                website,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF111827),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateToFollowList(FollowListType listType) {
    final me = Supabase.instance.client.auth.currentUser?.id;
    // Gizli hesabın takipçi/takip listesi yalnız takipçilerine açık
    // (Instagram davranışı); sayılar görünmeye devam eder.
    if (_isProfilePrivate && !_isFollowing && me != widget.userId) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bu hesap gizli. Listeyi görmek için takip etmelisin.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    final username = _userProfile?['username'] ?? 'Kullanıcı';
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FollowListScreen(
          userId: widget.userId,
          listType: listType,
          username: username,
        ),
      ),
    ).then((_) {
      // Listede takip/çıkarma yapılmış olabilir.
      if (mounted) _loadFollowCounts();
    });
  }

  /// Kendi profilini düzenleme ekranına yönlendir. Dönüşte profil yenilenir.
  void _editProfile() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const EditProfileScreen()),
    );

    if (result == true && mounted) {
      _loadUserProfile();
      _loadUserPosts();
    }
  }

  Widget _buildActionButtons(
    bool isOwnProfile,
    String fullName,
    String? avatarUrl,
  ) {
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
        // Takip ediliyorsa buton aksiyonu belirtir: takipten çıkar
        followButtonText = 'Takipten Çık';
        followButtonIcon = Icons.person_remove_outlined;
        showGradient = false;
      }

      return Row(
        children: [
          Expanded(
            child: ProfileActionButton(
              label: followButtonText,
              icon: followButtonIcon,
              onTap: hasIncomingRequest
                  ? _acceptFollowRequest
                  : (_followBusy ? () {} : _toggleFollow),
              gradientColors: hasIncomingRequest
                  ? const [Color(0xFF16A36A), Color(0xFF0E7C50)]
                  : (showGradient
                        ? const [Color(0xFF087DB4), Color(0xFF126796)]
                        : null),
              backgroundColor: const Color(0xFFF3F4F6),
              foregroundColor: showGradient || hasIncomingRequest
                  ? Colors.white
                  : const Color(0xFF374151),
              borderColor: showGradient || hasIncomingRequest
                  ? null
                  : const Color(0xFFD1D5DB),
              shadowColor: hasIncomingRequest
                  ? const Color(0x3516A36A)
                  : (showGradient
                        ? const Color(0x40087DB4)
                        : const Color(0x18000000)),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: ProfileActionButton(
              label: 'Mesaj',
              icon: Icons.chat_bubble_outline_rounded,
              onTap: () => _startChat(fullName, avatarUrl),
              gradientColors: const [Color(0xFF737B84), Color(0xFF59616A)],
            ),
          ),
        ],
      );
    }

    // Kendi profil butonları
    return Row(
      children: [
        Expanded(
          child: ProfileActionButton(
            label: 'Profili Düzenle',
            icon: Icons.edit_outlined,
            onTap: _editProfile,
            gradientColors: const [Color(0xFF087DB4), Color(0xFF126796)],
            shadowColor: const Color(0x40087DB4),
          ),
        ),
      ],
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
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  // ===== GRID GÖRÜNÜMÜ =====
  // ===== GRID GÖRÜNÜMÜ =====
  // Izgara tasarımı iki profil ekranında ortak: ProfilePostGrid.
  // (Gönderi konumu bu görünümde ne okunur ne gösterilir - konum
  // davranışı bilinçli olarak değiştirilmedi.)
  Widget _buildGridView() {
    return ProfilePostGrid(
      posts: _userPosts,
      likedPostIds: _likedPostIds,
      onTap: _navigateToPostDetail,
      onDoubleTap: (post) {
        _showLikeAnimation(context);
        if (!_likedPostIds.contains(post.id)) {
          _toggleLike(post);
        }
      },
    );
  }

  // ===== LİSTE GÖRÜNÜMÜ =====
  Widget _buildListView(bool isOwnProfile) {
    final username = _userProfile?['username'] ?? 'Kullanıcı';
    final fullName = _userProfile?['full_name'] ?? username;
    final avatarUrl = _userProfile?['avatar_url'];

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final post = _userPosts[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: ImpressionProbe(
              id: post.id,
              onSeen: () => PostImpressionTracker.instance.markSeen(
                post.id,
                authorId: post.userId,
              ),
              child: SocialPostCard(
              post: post,
              fullName: fullName,
              username: username,
              avatarUrl: avatarUrl,
              authorRole: AuthorRole.unknown,
              isVerified: post.authorIsVerified,
              isLiked: _likedPostIds.contains(post.id),
              isSaved: _savedPosts.contains(post.id),
              showOwnPinBadge: true,
              onTap: () => _navigateToPostDetail(post),
              onAuthorTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => UserProfileScreen(userId: post.userId),
                ),
              ),
              onLike: () => _toggleLike(post),
              onComment: () => _navigateToPostDetail(post),
              onSend: () => sendPostToFriend(context, post),
              onSave: () => _savePost(post),
              onShare: () => _sharePost(post),
              onViewsTap: isOwnProfile
                  ? () => showPostInsightsSheet(context, post)
                  : null,
              onHashtagTap: (tag) => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => HashtagFeedScreen(tag: tag)),
              ),
              trailing: isOwnProfile
                  ? PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_horiz,
                        color: Colors.grey.shade500,
                        size: 20,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      onSelected: (value) {
                        if (value == 'delete') _deletePost(post.id);
                        if (value == 'insights') {
                          showPostInsightsSheet(context, post);
                        }
                        if (value == 'edit') _editPost(post);
                      },
                      itemBuilder: (context) => const [
                        PopupMenuItem(
                          value: 'edit',
                          child: Row(
                            children: [
                              Icon(Icons.edit_outlined, size: 20),
                              SizedBox(width: 12),
                              Text('Düzenle'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'insights',
                          child: Row(
                            children: [
                              Icon(Icons.insights_rounded, color: Color(0xFF7C3AED), size: 20),
                              SizedBox(width: 12),
                              Text('İstatistikler'),
                            ],
                          ),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, color: Colors.red, size: 20),
                              SizedBox(width: 12),
                              Text('Sil'),
                            ],
                          ),
                        ),
                      ],
                    )
                  : null,
              ),
            ),
          );
        }, childCount: _userPosts.length),
      ),
    );
  }

  Future<void> _toggleMute(bool currentlyMuted) async {
    final username = _userProfile?['username'] ?? 'kullanıcı';
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (currentlyMuted) {
        await MutedUsersService.instance.unmute(widget.userId);
      } else {
        await MutedUsersService.instance.mute(widget.userId);
      }
      if (!mounted) return;
      setState(() {});
      messenger.showSnackBar(
        SnackBar(
          content: Text(currentlyMuted ? '@$username sesi açıldı' : '@$username sessize alındı'),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(AppErrorHandler.handleError(e))),
      );
    }
  }

  Future<void> _editPost(Post post) async {
    final updated = await showEditPostSheet(context, post);
    if (updated == null || !mounted) return;
    setState(() {
      final i = _userPosts.indexWhere((p) => p.id == post.id);
      if (i != -1) {
        _userPosts[i] = _userPosts[i].copyWith(
          content: updated.content,
          editedAt: updated.editedAt,
        );
      }
    });
  }

  Future<void> _toggleLike(Post post) async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null || !mounted) return;

    final isLiked = _likedPostIds.contains(post.id);

    // İyimser güncelleme; sayı sunucudan yeniden okunmaz (beğeni başına ek
    // bir istek demekti).
    setState(() {
      if (isLiked) {
        _likedPostIds.remove(post.id);
      } else {
        _likedPostIds.add(post.id);
      }
      _bumpLikes(post.id, isLiked ? -1 : 1);
    });

    try {
      if (isLiked) {
        await _postService.unlikePost(post.id, currentUserId);
      } else {
        await _postService.likePost(post.id, currentUserId);
      }
    } catch (e) {
      // Hata olursa geri al
      if (!mounted) return;
      setState(() {
        if (isLiked) {
          _likedPostIds.add(post.id);
        } else {
          _likedPostIds.remove(post.id);
        }
        _bumpLikes(post.id, isLiked ? 1 : -1);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppErrorHandler.handleError(e))),
      );
    }
  }

  void _bumpLikes(String postId, int delta) {
    final index = _userPosts.indexWhere((p) => p.id == postId);
    if (index == -1) return;
    final p = _userPosts[index];
    _userPosts[index] =
        p.copyWith(likesCount: (p.likesCount + delta).clamp(0, 1 << 30));
  }

  void _navigateToPostDetail(Post post) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => PostDetailScreen(post: post)),
    ).then((result) {
      // Yalnız değişen gönderiyi yama; eskiden her dönüşte tüm gönderiler
      // + beğeniler + kaydedilenler yeniden indiriliyordu.
      if (result is! PostDetailResult || !mounted) return;
      setState(() {
        if (result.isLiked) {
          _likedPostIds.add(result.postId);
        } else {
          _likedPostIds.remove(result.postId);
        }
        final index = _userPosts.indexWhere((p) => p.id == result.postId);
        if (index != -1) _userPosts[index] = result.applyTo(_userPosts[index]);
      });
    });
  }

  void _openStories() {
    if (_userStories.isEmpty) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            StoryViewerScreen(stories: _userStories, initialIndex: 0),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Link açılamadı: $url')));
      }
    }
  }

  Future<void> _startChat(String fullName, String? avatarUrl) async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Mesaj göndermek için giriş yapmalısınız'),
        ),
      );
      return;
    }

    // Kullanıcının mesaj alma özelliğini kontrol et
    // public_profiles_chat SECURITY DEFINER view; RLS bypass ile
    // messages_enabled sütununu okur.
    final targetProfile = await Supabase.instance.client
        .from('public_profiles_chat')
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

    final conversation = await _chatService.getOrCreateConversation(
      widget.userId,
    );
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
    final profileUrl = username.isNotEmpty
        ? 'https://cizreapp.com/u/@$username'
        : '';

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
                child: Icon(
                  Icons.flag_outlined,
                  color: Colors.orange.shade400,
                  size: 20,
                ),
              ),
              title: const Text(
                'Şikayet Et / Bildir',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
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
                  color: _isBlocked
                      ? Colors.green.shade400
                      : Colors.red.shade400,
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
            // Sessize al: gönderi/hikâyeleri akıştan çıkar, karşı taraf fark etmez.
            if (!_isBlocked)
              Builder(builder: (context) {
                final muted = MutedUsersService.instance.isMuted(widget.userId);
                return ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blueGrey.shade50,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      muted ? Icons.volume_up_outlined : Icons.volume_off_outlined,
                      color: Colors.blueGrey.shade400,
                      size: 20,
                    ),
                  ),
                  title: Text(
                    muted ? 'Sesi aç' : 'Sessize al',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: muted
                      ? null
                      : const Text('Gönderileri ve hikâyeleri akışında görünmez'),
                  onTap: () {
                    Navigator.pop(context);
                    _toggleMute(muted);
                  },
                );
              }),
            const Divider(),
            if (profileUrl.isNotEmpty)
              ListTile(
                leading: Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.share_outlined,
                    color: Colors.blue.shade400,
                    size: 20,
                  ),
                ),
                title: const Text(
                  'Profili Paylaş',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  profileUrl,
                  style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                ),
                trailing: Icon(
                  Icons.chevron_right,
                  color: Colors.grey.shade400,
                ),
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
            const Text(
              'Kullanıcıyı Şikayet Et',
              style: TextStyle(fontSize: 18),
            ),
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
                      Icon(
                        Icons.info_outline,
                        color: Colors.orange.shade700,
                        size: 20,
                      ),
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
                const Text(
                  'Şikayet Nedeni:',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
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
                const Text(
                  'Kanıt Görseller (Opsiyonel):',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
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
                                        child: const Icon(
                                          Icons.broken_image,
                                          color: Colors.grey,
                                        ),
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
                                    child: const Icon(
                                      Icons.close,
                                      size: 14,
                                      color: Colors.white,
                                    ),
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
                          selectedImages.addAll(
                            images.take(3 - selectedImages.length),
                          );
                        });
                      }
                    },
                    icon: const Icon(Icons.add_photo_alternate, size: 18),
                    label: Text(
                      selectedImages.isEmpty
                          ? 'Görsel Ekle (Maks. 3)'
                          : '${3 - selectedImages.length} görsel daha',
                      style: const TextStyle(fontSize: 12),
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 36),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
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
                  final currentUserId =
                      Supabase.instance.client.auth.currentUser?.id;
                  if (currentUserId != null) {
                    for (int i = 0; i < selectedImages.length; i++) {
                      if (!mounted) return;

                      final image = selectedImages[i];
                      final bytes = await image.readAsBytes();
                      if (!mounted) return;

                      final extension = image.path
                          .split('.')
                          .last
                          .toLowerCase();
                      final fileName =
                          '${currentUserId}_${DateTime.now().millisecondsSinceEpoch}_$i.$extension';

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
                    message =
                        'Şikayetiniz alındı. En kısa sürede değerlendirilecektir.';
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
                    message =
                        'Şikayet gönderilemedi. Lütfen tekrar deneyin. (Kod: RPT-ERR)';
                    backgroundColor = Colors.red;
                    break;
                  default:
                    message =
                        'Bilinmeyen hata: $result. Lütfen destek ile iletişime geçin.';
                    backgroundColor = Colors.red;
                }

                ScaffoldMessenger.of(this.context).showSnackBar(
                  SnackBar(
                    content: Text(message),
                    backgroundColor: backgroundColor,
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
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
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
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
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
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
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(willBeBlocked ? 'Engelle' : 'Engeli Kaldır'),
            ),
          ],
        ),
      );

      if (confirm == true && mounted) {
        if (willBeBlocked) {
          await _profileService.block(widget.userId);
        } else {
          await _profileService.unblock(widget.userId);
        }
        if (!mounted) return;
        final success = willBeBlocked;

        setState(() {
          _isBlocked = success;
          // Engelde iki yöndeki takip/istek sunucuda silindi.
          if (success) {
            _isFollowing = false;
            _followRequestStatus = 'none';
            _incomingFollowRequestId = null;
          }
        });
        unawaited(_loadFollowCounts());

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                success
                    ? '@$username engellendi'
                    : '@$username engeli kaldırıldı',
              ),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppErrorHandler.handleError(e))),
        );
      }
    }
  }

  /// Gönderiyi sistem paylaşım sayfasıyla paylaşır (metin + gönderi linki);
  /// paylaşıldıysa paylaşım sayısı bir artar. Eskiden yalnız WhatsApp /
  /// bağlantı kopyalama sunan ve hiç çağrılmayan bir sayfa vardı.
  Future<void> _sharePost(Post post) async {
    final name = (post.authorFullName?.trim().isNotEmpty ?? false)
        ? post.authorFullName!.trim()
        : (post.authorUsername ?? 'Kullanıcı');
    try {
      final count = await SocialShareService().sharePost(post, authorName: name);
      if (count == null || !mounted) return;
      setState(() {
        final index = _userPosts.indexWhere((p) => p.id == post.id);
        if (index != -1) {
          _userPosts[index] = _userPosts[index].copyWith(sharesCount: count);
        }
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Paylaşım yapılamadı')),
      );
    }
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Bağlantı kopyalandi')));
  }

  Future<void> _savePost(Post post) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Lütfen giriş yapın')));
        }
        return;
      }

      // Akışla aynı yol: ekranın bildiği durumun tersi istenir (idempotent).
      final isFavorited = !_savedPosts.contains(post.id);
      await _postService.setPostSaved(post.id, isFavorited);

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
            content: Text(
              isFavorited
                  ? 'Gönderi kaydedildi'
                  : 'Gönderi kaydedilenlerden kaldırıldı',
            ),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Hata: $e')));
      }
    }
  }

  /// Instagram tarzı animasyonlu kalp efekti göster
  void _showLikeAnimation(BuildContext context) {
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final size = renderBox.size;

    // Kalp ikonu overlay'i oluştur
    final entry = OverlayEntry(
      builder: (context) =>
          HeartAnimationOverlay(key: UniqueKey(), parentSize: size),
    );

    overlay.insert(entry);

    // 1.5 saniye sonra overlay'i kaldır
    Future.delayed(const Duration(milliseconds: 1500), () {
      entry.remove();
    });
  }
}
