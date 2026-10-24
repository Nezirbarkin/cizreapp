// ignore_for_file: deprecated_member_use, use_build_context_synchronously, curly_braces_in_flow_control_structures

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/post_model.dart';
import '../../../core/models/analytics_model.dart';
import '../../../core/services/profile_view_service.dart';
import '../../../core/services/post_view_service.dart';
import '../../../core/widgets/text_background.dart';
import '../../social/services/post_service.dart';
import '../../social/services/social_share_service.dart';
import '../../social/services/story_service.dart';
import '../../social/services/follow_service.dart';
import '../../social/models/follow_suggestion.dart' show FollowStatus;
import '../../../core/utils/app_error_handler.dart';
import '../services/follow_request_service.dart';
import '../../social/screens/post_likes_screen.dart';
import '../../social/screens/post_detail_screen.dart';
import '../../social/screens/story_viewer_screen.dart';
import '../services/profile_service.dart';
import 'edit_profile_screen.dart';
import '../../social/screens/create_post_screen.dart';
import 'blocked_users_screen.dart';
import 'my_reports_screen.dart';
import '../../chat/services/chat_service.dart';
import '../../chat/screens/chat_detail_screen.dart';
import 'followers_screen.dart';
import '../widgets/profile_shared_widgets.dart';
import '../../../kullaniciozellikler/widgets/profile_privileges.dart';
import '../../../kullaniciozellikler/widgets/cover_effect_frame.dart';
import '../../../kullaniciozellikler/screens/my_profile_features_screen.dart';
import '../../../ilanlar/screens/my_ilanlar_screen.dart';
import '../widgets/profile_post_grid.dart';
import '../widgets/profile_share_sheet.dart';
import '../../social/widgets/social_post_card.dart';
import '../../social/widgets/send_to_friend_sheet.dart';
import 'user_profile_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String? userId;

  const ProfileScreen({super.key, this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen>
    with TickerProviderStateMixin {
  final _profileService = ProfileService();
  final _postService = PostService();
  final _storyService = StoryService();
  final _profileViewService = ProfileViewService();
  final _postViewService = PostViewService();
  final _chatService = ChatService();
  final _followRequestService = FollowRequestService();
  final _followService = FollowService();

  Map<String, dynamic>? _profileData;
  // Profil yüklenemedi / bulunamadı (başkasının profili): sonsuz dönen
  // yükleniyor ekranı yerine hata durumu gösterilir.
  bool _loadFailed = false;
  bool _followBusy = false;
  // Sunucudaki etkin gönderi sayısı (null = henüz yok).
  int? _postsCount;
  List<Post> _userPosts = [];
  List<Story> _userStories = [];
  bool _isLoading = true;
  bool _isLoadingPosts = true;
  // Gönderi ızgarası sayfalı (PostService.userPostsPageSize).
  bool _postsHasMore = false;
  bool _loadingMorePosts = false;
  final ScrollController _profileScroll = ScrollController();
  bool _isFollowing = false;
  bool _isOwnProfile = false;
  bool _isProfilePrivate =
      false; // Hedef profil gizli mi (profile_is_public == false)
  String _followRequestStatus = 'none'; // none, pending, accepted, rejected
  int _followersCount = 0;
  int _followingCount = 0;
  int _friendsCount = 0;
  Set<String> _likedPostIds = {};
  Set<String> _savedPosts = {}; // Kaydedilen gönderiler
  CurrentMonthViewStats? _profileViewStats;
  CurrentMonthViewStats? _postViewStats;
  bool _isLoadingAnalytics = true;
  bool _showGrid = true; // Grid/Liste geçişi
  late TabController _tabController;
  late AnimationController _statsAnimationController;
  late Animation<double> _statsAnimation;
  bool _statsExpanded = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _profileScroll.addListener(_onProfileScroll);
    _statsAnimationController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _statsAnimation = CurvedAnimation(
      parent: _statsAnimationController,
      curve: Curves.easeInOut,
    );

    // Kendi profilimi mi yoksa başkasınınkini mi görüntülediğimi kontrol et
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final targetUserId = widget.userId ?? currentUserId;
    _isOwnProfile = targetUserId == currentUserId;

    _loadProfile();
    _loadUserPosts();
    _loadUserStories();
    _checkIfFollowing();
    _loadFollowCounts();
    _loadAnalytics();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _statsAnimationController.dispose();
    _profileScroll.dispose();
    super.dispose();
  }

  Future<void> _loadAnalytics() async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final targetUserId = widget.userId ?? currentUserId;

    if (targetUserId == null || currentUserId == null) {
      if (mounted) setState(() => _isLoadingAnalytics = false);
      return;
    }

    final isOwnProfile = targetUserId == currentUserId;

    if (!isOwnProfile) {
      if (mounted) setState(() => _isLoadingAnalytics = false);
      return;
    }

    try {
      // İki istek bağımsız: aynı anda.
      final (profileStats, postStats) = await (
        _profileViewService.getCurrentMonthStats(targetUserId),
        _postViewService.getCurrentMonthStats(targetUserId),
      ).wait;

      // await'lerden sonra ekran kapanmış olabilir; korumasız setState
      // "setState() called after dispose(): _ProfileScreenState" fırlatıyordu.
      if (!mounted) return;
      setState(() {
        _profileViewStats = profileStats;
        _postViewStats = postStats;
        _isLoadingAnalytics = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoadingAnalytics = false);
    }
  }

  Future<void> _loadFollowCounts() async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final targetUserId = widget.userId ?? currentUserId;
    if (targetUserId == null) return;

    try {
      // Tek RPC: eskiden tüm takip satırları (iki sıralı sorgu) indirilip
      // telefonda sayılıyordu; 1000 satırda sayılar takılıyordu.
      final counts = await _profileService.getFollowCounts(targetUserId);
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

  Future<void> _loadUserStories() async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final targetUserId = widget.userId ?? currentUserId;
    if (targetUserId == null) return;

    try {
      final stories = await _storyService.getUserStories(targetUserId);
      if (!mounted) return;
      setState(() {
        _userStories = stories;
      });
    } catch (e) {
      debugPrint('Kullanıcı hikayeleri yüklenirken hata: $e');
    }
  }

  /// [silent]: aşağı çekip yenileme — ekran yükleniyor görünümüne dönmez.
  /// Eskiden yenileme `_isLoading`'i açıp tüm kaydırma görünümünü (ve
  /// yenileme göstergesini) söküyordu: titreme + kaydırma kaybı.
  Future<void> _loadProfile({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _isLoading = true;
        _loadFailed = false;
      });
    }

    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      final targetUserId = widget.userId ?? currentUserId;

      if (targetUserId == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      _isOwnProfile = targetUserId == currentUserId;

      final profile = await _profileService.getUserProfile(targetUserId);
      if (!mounted) return;
      setState(() {
        _profileData = profile;
        // Gizlilik: profile_is_public == false ise gizli. (Eski kod olmayan
        // is_private sütununu kontrol ediyordu → her zaman null → gizli
        // hesaplar asla gizli sanılmıyordu.)
        _isProfilePrivate = profile['profile_is_public'] == false;
        _isLoading = false;
        _loadFailed = false;
      });

      // Başka kullanıcının gizli profili ise takip isteği durumunu kontrol et
      if (!_isOwnProfile && _isProfilePrivate) {
        _checkFollowRequestStatus();
      }
    } catch (e) {
      debugPrint('Profil yüklenirken hata: $e');

      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      final targetUserId = widget.userId ?? currentUserId;

      if (_isOwnProfile &&
          targetUserId == currentUserId &&
          currentUserId != null) {
        await _createDefaultProfile(currentUserId);
      } else {
        // catch bloğuna gelene kadar await'ler geçti; ekran kapanmış olabilir.
        if (!mounted) return;
        setState(() {
          _isLoading = false;
          _loadFailed = _profileData == null;
        });
      }
    }
  }

  Future<void> _createDefaultProfile(String userId) async {
    try {
      debugPrint('🔧 Profil kontrol ediliyor: $userId');

      // Profil SQL trigger tarafından otomatik oluşturulmalı
      // Burada sadece kontrol ediyoruz, trigger henüz çalışmadıysa bekliyoruz

      // 1.5 saniye bekle ve tekrar dene (trigger'ın çalışması için zaman tanı)
      await Future.delayed(const Duration(milliseconds: 1500));

      // Yalnizca varlik kontrolu; tum satiri cekmeye gerek yok.
      // `select()` (SELECT *) sutun bazli GRANT ile calismaz.
      final existingProfile = await Supabase.instance.client
          .from('profiles')
          .select('id')
          .eq('id', userId)
          .maybeSingle();

      if (existingProfile != null) {
        debugPrint('✅ Profil bulundu, yükleniyor...');
        await _loadProfile();
      } else {
        debugPrint(
          '⚠️ Profil trigger ile oluşturulamadı, manuel oluşturuluyor...',
        );

        // Fallback: Profil'i manuel oluştur
        final user = Supabase.instance.client.auth.currentUser;
        final meta = user?.userMetadata ?? {};

        await Supabase.instance.client.from('profiles').upsert({
          'id': userId,
          'email': user?.email ?? '',
          'username': (meta['username'] as String?) ?? '',
          'full_name': (meta['full_name'] as String?) ?? '',
          'gender': meta['gender'] as String?,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        }, onConflict: 'id');

        debugPrint('✅ Profil manuel olarak oluşturuldu');
        await _loadProfile();
      }
    } catch (e) {
      debugPrint('❌ Profil kontrol/oluşturma hatası: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _loadFailed = _profileData == null;
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Profil oluşturulamadı: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _loadUserPosts() async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final targetUserId = widget.userId ?? currentUserId;
    if (targetUserId == null) return;

    try {
      // Eldeki ızgara yenilemede iskelete dönmez.
      if (_userPosts.isEmpty) setState(() => _isLoadingPosts = true);
      // Kaydedilenler gönderilerden bağımsız: aynı anda başlar.
      final savedLoad =
          currentUserId != null ? _loadSavedPosts() : Future<void>.value();
      final posts = await _postService.getUserPosts(targetUserId);

      if (currentUserId != null && posts.isNotEmpty) {
        final postIds = posts.map((p) => p.id).toList();
        _likedPostIds = await _postService.getLikedPostIds(
          currentUserId,
          postIds,
        );
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
    final targetUserId = widget.userId ?? Supabase.instance.client.auth.currentUser?.id;
    if (targetUserId == null) return;
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

  // Kayıtlı gönderiler tek kaynaktan (post_favorites) okunuyor; eskiden
  // SharedPreferences'tan okunduğu için profilden kaydedilen gönderinin
  // yer imi ikonu dolu görünmüyordu.
  Future<void> _loadSavedPosts() async {
    try {
      await _postService.migrateLegacyLocalSaves();
      final saved = await _postService.getSavedPostIds();
      if (mounted) {
        setState(() {
          _savedPosts = saved;
        });
      }
    } catch (e) {
      debugPrint('Kaydedilen gönderiler yüklenirken hata: $e');
    }
  }

  Future<void> _checkIfFollowing() async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final targetUserId = widget.userId ?? currentUserId;
    if (currentUserId == null ||
        targetUserId == null ||
        currentUserId == targetUserId)
      return;

    try {
      final response = await Supabase.instance.client
          .from('follows')
          .select('id')
          .eq('follower_id', currentUserId)
          .eq('following_id', targetUserId)
          .maybeSingle();
      if (!mounted) return;

      setState(() => _isFollowing = response != null);
    } catch (e) {
      debugPrint('Takip durumu kontrol edilirken hata: $e');
    }
  }

  /// Gizli profil için mevcut takip isteği durumunu kontrol et.
  /// İstek kabul edildiyse follows tablosuna SQL trigger tarafından eklenmiş
  /// demektir; bu yüzden _isFollowing'i de true yapar.
  Future<void> _checkFollowRequestStatus() async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) return;
      final targetUserId = widget.userId ?? currentUserId;
      if (currentUserId == targetUserId) return;

      if (!_isProfilePrivate) {
        if (mounted) setState(() => _followRequestStatus = 'none');
        return;
      }

      final status = await _followRequestService.getFollowRequestStatus(
        targetUserId,
      );
      if (!mounted) return;

      // Tek doğru kaynak follows (_checkIfFollowing): eski bir "accepted"
      // satırı takip anlamına gelmez.
      setState(() {
        _followRequestStatus =
            !_isFollowing && status == 'pending' ? 'pending' : 'none';
      });
    } catch (e) {
      debugPrint('Takip isteği durumu kontrol edilirken hata: $e');
    }
  }

  /// Takip et / bırak / isteği geri al — tek RPC (`social_follow`).
  /// Gizli hesapta sunucu istek açar. Düğme ve sayı dönen sonuçtan kurulur;
  /// eskiden istek gönder/iptal dallarında etiket hiç güncellenmiyordu.
  Future<void> _toggleFollow() async {
    final messenger = ScaffoldMessenger.of(context);
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final targetUserId = widget.userId ?? currentUserId;
    if (currentUserId == null || targetUserId == null || _followBusy) return;

    final wasActive = _isFollowing || _followRequestStatus == 'pending';
    final wasFollowing = _isFollowing;
    setState(() => _followBusy = true);
    try {
      final result = wasActive
          ? await _followService.unfollow(targetUserId)
          : await _followService.follow(targetUserId);
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
      if (_isProfilePrivate && wasFollowing != _isFollowing) {
        _loadUserPosts();
        _loadUserStories();
      }
      unawaited(_loadFollowCounts());
    } on FollowException catch (e) {
      if (mounted) messenger.showSnackBar(SnackBar(content: Text(e.message)));
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

    if (confirm != true) return;

    try {
      await _postService.deletePost(postId);
      if (!mounted) return;

      setState(() {
        if (_postsCount != null && _postsCount! > 0) {
          _postsCount = _postsCount! - 1;
        }
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
      _loadProfile(silent: true),
      _loadUserPosts(),
      _loadUserStories(),
      _loadFollowCounts(),
      _loadAnalytics(),
    ]);
  }

  Widget _buildLoadFailed() {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: const Color(0xFF111827),
        elevation: 0,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.person_off_outlined, size: 56, color: Colors.grey.shade400),
              const SizedBox(height: 14),
              Text(
                'Profil yüklenemedi',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey.shade800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Hesap kaldırılmış olabilir ya da bağlantı kesildi.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600),
              ),
              const SizedBox(height: 18),
              FilledButton.icon(
                onPressed: _loadProfile,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text('Tekrar Dene'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loadFailed && _profileData == null) return _buildLoadFailed();
    if (_isLoading || _profileData == null) {
      return Scaffold(
        backgroundColor: Colors.white,
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  shape: BoxShape.circle,
                ),
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Profil yükleniyor...',
                style: TextStyle(
                  color: Colors.grey.shade600,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final username = _profileData!['username'] ?? 'Kullanıcı';
    final fullName = _profileData!['full_name'] ?? username;
    final avatarUrl = _profileData!['avatar_url'];
    final coverUrl = _profileData!['cover_url'];
    final bio = _profileData!['bio'];
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final targetUserId = widget.userId ?? currentUserId;
    final isOwnProfile = targetUserId == currentUserId;

    return ProfilePrivilegesOverlay(
      userId: targetUserId!,
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
                leading: !isOwnProfile
                    ? IconButton(
                        icon: const Icon(
                          Icons.arrow_back,
                          color: Colors.white,
                          size: 20,
                        ),
                        onPressed: () => Navigator.pop(context),
                      )
                    : null,
                actions: [
                  if (isOwnProfile)
                    IconButton(
                      icon: const Icon(
                        Icons.add_box_outlined,
                        color: Colors.white,
                        size: 22,
                      ),
                      onPressed: _createPost,
                      tooltip: 'Gönderi Oluştur',
                    ),
                  // Paylaşım butonu (hem kendi profili hem başkasının profili için)
                  IconButton(
                    icon: const Icon(
                      Icons.share_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                    // QR kodlu paylaşım sayfası (link kopyala / paylaş / QR).
                    onPressed: () {
                      final username =
                          _profileData?['username']?.toString() ?? '';
                      if (username.isEmpty) return;
                      showProfileShareSheet(
                        context,
                        username: username,
                        fullName: _profileData?['full_name']?.toString(),
                        avatarUrl: _profileData?['avatar_url']?.toString(),
                      );
                    },
                    tooltip: 'Profili Paylaş',
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.more_vert,
                      color: Colors.white,
                      size: 23,
                    ),
                    onPressed: isOwnProfile ? _showSettingsMenu : null,
                  ),
                ],
                flexibleSpace: FlexibleSpaceBar(
                  background: CoverEffectFrame(
                    userId: targetUserId,
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
                        // Gradient overlay - alt kısım
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
                            userId: targetUserId,
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
                        userId: targetUserId,
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
                        statusBadge: ProfilePrivilegeBadges(
                          userId: targetUserId,
                        ),
                        showHero: false,
                      ),

                      const SizedBox(height: 16),

                      // ===== BUTONLAR =====
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: _buildActionButtons(isOwnProfile),
                      ),

                      const SizedBox(height: 16),

                      // ===== ANALİTİK BÖLÜMÜ =====
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
              if (!isOwnProfile && _isProfilePrivate && !_isFollowing)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: _buildPrivateProfileMessage(),
                  ),
                )
              else if (_isLoadingPosts)
                const SliverToBoxAdapter(
                  child: SizedBox(
                    height: 200,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (_userPosts.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: _buildEmptyState(isOwnProfile),
                  ),
                )
              else if (_showGrid)
                _buildGridView()
              else
                _buildListView(isOwnProfile),

              // Alt boşluk
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
            Theme.of(context).colorScheme.primary.withOpacity(0.8),
            Theme.of(context).colorScheme.primary.withOpacity(0.4),
            Colors.purple.shade200,
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
    final website = _profileData?['website']?.toString().trim() ?? '';
    if (website.isEmpty) return null;

    return InkWell(
      onTap: () => _launchUrl(website),
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
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final targetUserId = widget.userId ?? currentUserId;
    if (targetUserId == null) return;

    final username = _profileData?['username'] ?? 'Kullanıcı';

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => FollowListScreen(
          userId: targetUserId,
          listType: listType,
          username: username,
        ),
      ),
    ).then((_) {
      // Geri döndüğünde takip sayılarını güncelle
      _loadFollowCounts();
    });
  }

  Widget _buildActionButtons(bool isOwnProfile) {
    if (!isOwnProfile) {
      // Gizli profil için buton metni/durumu: user_profile_screen ile uyumlu.
      final isPending =
          _isProfilePrivate &&
          !_isFollowing &&
          _followRequestStatus == 'pending';
      final String followText = _isFollowing
          ? 'Takipten Çık'
          : (isPending
                ? 'İstek Gönderildi'
                : (_isProfilePrivate ? 'Takip İsteği Gönder' : 'Takip Et'));
      final bool showGradient = !_isFollowing && !isPending;

      return Row(
        children: [
          Expanded(
            child: ProfileActionButton(
              label: followText,
              icon: _isFollowing
                  ? Icons.person_remove_outlined
                  : (isPending
                        ? Icons.schedule_rounded
                        : Icons.person_add_alt_1_outlined),
              onTap: _toggleFollow,
              gradientColors: showGradient
                  ? const [Color(0xFF087DB4), Color(0xFF126796)]
                  : null,
              backgroundColor: const Color(0xFFF3F4F6),
              foregroundColor: showGradient
                  ? Colors.white
                  : const Color(0xFF374151),
              borderColor: showGradient ? null : const Color(0xFFD1D5DB),
              shadowColor: showGradient
                  ? const Color(0x40087DB4)
                  : const Color(0x18000000),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: ProfileActionButton(
              label: 'Mesaj',
              icon: Icons.chat_bubble_outline_rounded,
              onTap: _startChat,
              gradientColors: const [Color(0xFF737B84), Color(0xFF59616A)],
            ),
          ),
        ],
      );
    }

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
        const SizedBox(width: 12),
        Container(
          height: 40,
          width: 40,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFF737B84), Color(0xFF59616A)],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: const [
              BoxShadow(
                color: Color(0x30000000),
                blurRadius: 9,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _createPost,
              borderRadius: BorderRadius.circular(12),
              child: const Icon(
                Icons.add_rounded,
                color: Colors.white,
                size: 23,
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Container(
          height: 40,
          width: 40,
          decoration: BoxDecoration(
            color: const Color(0xFFF3F4F6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: const Color(0xFFD1D5DB)),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _showSettingsMenu,
              borderRadius: BorderRadius.circular(12),
              child: const Icon(
                Icons.settings_outlined,
                color: Color(0xFF4B5563),
                size: 21,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(bool isOwnProfile) {
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
            isOwnProfile
                ? 'İlk gönderinizi paylaşın!'
                : 'Bu kullanıcı henüz gönderi paylaşmadı.',
            style: TextStyle(fontSize: 14, color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
          if (isOwnProfile) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _createPost,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.add, size: 20),
              label: const Text(
                'Gönderi Oluştur',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
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
    );
  }

  // ===== LİSTE GÖRÜNÜMÜ =====
  Widget _buildListView(bool isOwnProfile) {
    final username = _profileData!['username'] ?? 'Kullanıcı';
    final fullName = _profileData!['full_name'] ?? username;
    final avatarUrl = _profileData!['avatar_url'];

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate((context, index) {
          final post = _userPosts[index];
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
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
              trailing: isOwnProfile
                  ? IconButton(
                      icon: Icon(
                        Icons.more_horiz,
                        color: Colors.grey.shade500,
                        size: 20,
                      ),
                      onPressed: () => _showPostMenu(post.id),
                    )
                  : null,
            ),
          );
        }, childCount: _userPosts.length),
      ),
    );
  }

  void _showPostMenu(String postId) {
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
            // Sabitleme seçeneği — gönderi zaten listede; eskiden menü her
            // açılışta gönderiyi sunucudan yeniden çekiyordu.
            Builder(
              builder: (context) {
                final index = _userPosts.indexWhere((p) => p.id == postId);
                if (index == -1) return const SizedBox.shrink();
                final post = _userPosts[index];
                return ListTile(
                  leading: Icon(
                    post.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                    color: post.isPinned ? Colors.amber : Colors.grey,
                  ),
                  title: Text(post.isPinned ? 'Sabitlemeyi Kaldır' : 'Sabitle'),
                  onTap: () async {
                    // Sayfa kapandıktan sonra onun context'i ölü olur.
                    final messenger = ScaffoldMessenger.of(this.context);
                    Navigator.pop(context);
                    try {
                      final pinned = await _postService.togglePinPost(postId);
                      if (!mounted) return;
                      setState(() => _setPinned(postId, pinned));
                      messenger.showSnackBar(
                        SnackBar(
                          content: Text(
                            pinned ? 'Gönderi sabitlendi' : 'Sabitleme kaldırıldı',
                          ),
                          backgroundColor: pinned ? Colors.amber : Colors.grey,
                        ),
                      );
                    } catch (e) {
                      messenger.showSnackBar(
                        SnackBar(content: Text(AppErrorHandler.handleError(e))),
                      );
                    }
                  },
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text(
                'Gönderiyi Sil',
                style: TextStyle(color: Colors.red),
              ),
              onTap: () {
                Navigator.pop(context);
                _deletePost(postId);
              },
            ),
            ListTile(
              leading: Icon(Icons.close, color: Colors.grey.shade600),
              title: const Text('İptal'),
              onTap: () => Navigator.pop(context),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleLike(Post post) async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    final isLiked = _likedPostIds.contains(post.id);

    // İyimser güncelleme; sayı sunucudan yeniden okunmaz.
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

  /// Sabitlenen gönderi ızgaranın başına, kaldırılan tarih sırasına döner
  /// (sunucu da `is_pinned desc, created_at desc` sıralar).
  void _setPinned(String postId, bool pinned) {
    final index = _userPosts.indexWhere((p) => p.id == postId);
    if (index == -1) return;
    _userPosts[index] = _userPosts[index].copyWith(isPinned: pinned);
    _userPosts.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      return b.createdAt.compareTo(a.createdAt);
    });
  }

  void _navigateToPostDetail(Post post) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => PostDetailScreen(post: post)),
    ).then((result) {
      // Yalnız değişen gönderiyi yama (eskiden her dönüşte hepsi yeniden).
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

  /// Gizli profil mesajı — başkasının gizli profilini görüntülerken
  /// gönderi/hikaye yerine gösterilir. user_profile_screen ile aynı içerik.
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

  Future<void> _createPost() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CreatePostScreen()),
    );

    if (result == true) {
      _loadUserPosts();
    }
  }

  void _editProfile() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const EditProfileScreen()),
    );

    if (result == true) {
      _loadProfile();
    }
  }

  Future<void> _launchUrl(String url) async {
    try {
      String formattedUrl = url;
      if (!url.startsWith('http://') && !url.startsWith('https://')) {
        formattedUrl = 'https://$url';
      }

      final uri = Uri.parse(formattedUrl);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('URL açılamadı')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('URL açılırken hata: $e')));
      }
    }
  }

  void _showSettingsMenu() {
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
                  color: Colors.deepPurple.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.auto_awesome_rounded,
                  color: Colors.deepPurple.shade400,
                  size: 20,
                ),
              ),
              title: const Text(
                'Profil Özelliklerim',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: const Text('Efektlerini ve ikonlarını aç veya kapat'),
              trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MyProfileFeaturesScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.block, color: Colors.red.shade400, size: 20),
              ),
              title: const Text(
                'Engellenenler',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const BlockedUsersScreen(),
                  ),
                );
              },
            ),
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
                'Şikayetlerim',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MyReportsScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.teal.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.campaign_outlined,
                  color: Colors.teal.shade400,
                  size: 20,
                ),
              ),
              title: const Text(
                'İlanlarım',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              trailing: Icon(Icons.chevron_right, color: Colors.grey.shade400),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const MyIlanlarScreen(),
                  ),
                );
              },
            ),
            const Divider(),
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

  Future<void> _startChat() async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final targetUserId = widget.userId ?? currentUserId;

    if (currentUserId == null ||
        targetUserId == null ||
        currentUserId == targetUserId) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Konuşma başlatılamadı')));
      }
      return;
    }

    try {
      // Kullanıcının mesaj alma özelliklerini kontrol et
      final targetProfile = await Supabase.instance.client
          .from('profiles')
          .select('messages_enabled')
          .eq('id', targetUserId)
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
        targetUserId,
      );

      if (conversation != null && mounted) {
        final otherUser = conversation.otherUser;
        final fullName = otherUser?['full_name'] as String? ?? 'Kullanıcı';
        final avatarUrl = otherUser?['avatar_url'] as String?;

        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatDetailScreen(
              conversationId: conversation.id,
              otherUserId: targetUserId,
              otherUserName: fullName,
              otherUserAvatar: avatarUrl,
            ),
          ),
        );
      } else if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Konuşma başlatılamadı')));
      }
    } catch (e) {
      debugPrint('Konuşma başlatılırken hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Konuşma başlatılamadı: $e')));
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
    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Link panoya kopyalandı!')));
    }
  }

  /// Gönderiyi kaydet (Supabase post_favorites tablosu)
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
}
