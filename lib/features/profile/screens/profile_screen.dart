// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/post_model.dart';
import '../../../core/models/analytics_model.dart';
import '../../../core/services/profile_view_service.dart';
import '../../../core/services/post_view_service.dart';
import '../../social/services/post_service.dart';
import '../../social/services/story_service.dart';
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

class ProfileScreen extends StatefulWidget {
  final String? userId;
  
  const ProfileScreen({super.key, this.userId});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> with TickerProviderStateMixin {
  final _profileService = ProfileService();
  final _postService = PostService();
  final _storyService = StoryService();
  final _profileViewService = ProfileViewService();
  final _postViewService = PostViewService();
  final _chatService = ChatService();
  
  Map<String, dynamic>? _profileData;
  List<Post> _userPosts = [];
  List<Story> _userStories = [];
  bool _isLoading = true;
  bool _isLoadingPosts = true;
  bool _isFollowing = false;
  bool _isOwnProfile = false;
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
    super.dispose();
  }

  Future<void> _loadAnalytics() async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final targetUserId = widget.userId ?? currentUserId;
    
    if (targetUserId == null || currentUserId == null) {
      setState(() => _isLoadingAnalytics = false);
      return;
    }

    final isOwnProfile = targetUserId == currentUserId;

    if (!isOwnProfile) {
      setState(() => _isLoadingAnalytics = false);
      return;
    }

    try {
      setState(() => _isLoadingAnalytics = true);
      
      final profileStats = await _profileViewService.getCurrentMonthStats(targetUserId);
      final postStats = await _postViewService.getCurrentMonthStats(targetUserId);
      
      setState(() {
        _profileViewStats = profileStats;
        _postViewStats = postStats;
        _isLoadingAnalytics = false;
      });
    } catch (e) {
      setState(() => _isLoadingAnalytics = false);
    }
  }

  Future<void> _loadFollowCounts() async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final targetUserId = widget.userId ?? currentUserId;
    if (targetUserId == null) return;
    
    try {
      final followersResponse = await Supabase.instance.client
          .from('follows')
          .select('follower_id')
          .eq('following_id', targetUserId);

      final followingResponse = await Supabase.instance.client
          .from('follows')
          .select('following_id')
          .eq('follower_id', targetUserId);

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

  Future<void> _loadUserStories() async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final targetUserId = widget.userId ?? currentUserId;
    if (targetUserId == null) return;
    
    try {
      final stories = await _storyService.getUserStories(targetUserId);
      setState(() {
        _userStories = stories;
      });
    } catch (e) {
      debugPrint('Kullanıcı hikayeleri yüklenirken hata: $e');
    }
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);
    
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      final targetUserId = widget.userId ?? currentUserId;
      
      if (targetUserId == null) {
        setState(() => _isLoading = false);
        return;
      }
      
      _isOwnProfile = targetUserId == currentUserId;
      
      final profile = await _profileService.getUserProfile(targetUserId);
      setState(() {
        _profileData = profile;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Profil yüklenirken hata: $e');
      
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      final targetUserId = widget.userId ?? currentUserId;
      
      if (_isOwnProfile && targetUserId == currentUserId && currentUserId != null) {
        await _createDefaultProfile(currentUserId);
      } else {
        setState(() => _isLoading = false);
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
      
      final existingProfile = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .maybeSingle();
          
      if (existingProfile != null) {
        debugPrint('✅ Profil bulundu, yükleniyor...');
        await _loadProfile();
      } else {
        debugPrint('⚠️ Profil trigger ile oluşturulamadı, manuel oluşturuluyor...');
        
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
      setState(() => _isLoading = false);
      
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
      setState(() => _isLoadingPosts = true);
      final posts = await _postService.getUserPosts(targetUserId);
      
      if (currentUserId != null && posts.isNotEmpty) {
        final postIds = posts.map((p) => p.id).toList();
        _likedPostIds = await _postService.getLikedPostIds(currentUserId, postIds);
      }
      
      // Kaydedilen gönderileri yükle
      if (currentUserId != null) {
        await _loadSavedPosts();
      }
      
      setState(() {
        _userPosts = posts;
        _isLoadingPosts = false;
      });
    } catch (e) {
      debugPrint('Kullanıcı gönderileri yüklenirken hata: $e');
      setState(() => _isLoadingPosts = false);
    }
  }

  Future<void> _loadSavedPosts() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPosts = prefs.getStringList('saved_posts') ?? [];
      if (mounted) {
        setState(() {
          _savedPosts = savedPosts.toSet();
        });
      }
    } catch (e) {
      debugPrint('Kaydedilen gönderiler yüklenirken hata: $e');
    }
  }

  Future<void> _checkIfFollowing() async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final targetUserId = widget.userId ?? currentUserId;
    if (currentUserId == null || targetUserId == null || currentUserId == targetUserId) return;

    try {
      final response = await Supabase.instance.client
          .from('follows')
          .select('id')
          .eq('follower_id', currentUserId)
          .eq('following_id', targetUserId)
          .maybeSingle();

      setState(() => _isFollowing = response != null);
    } catch (e) {
      debugPrint('Takip durumu kontrol edilirken hata: $e');
    }
  }

  Future<void> _toggleFollow() async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final targetUserId = widget.userId ?? currentUserId;
    if (currentUserId == null || targetUserId == null) return;

    try {
      // Gizli profil kontrolü - hedef kullanıcının profil bilgisini al
      final targetProfile = await Supabase.instance.client
          .from('profiles')
          .select('is_private')
          .eq('id', targetUserId)
          .maybeSingle();

      final isTargetPrivate = targetProfile?['is_private'] == true;

      // Gizli profil ve takip etmiyorsa, takip isteği kontrolü
      if (isTargetPrivate && !_isFollowing) {
        // Bekleyen takip isteği var mı kontrol et
        final existingRequest = await Supabase.instance.client
            .from('follow_requests')
            .select('id, status')
            .eq('follower_id', currentUserId)
            .eq('following_id', targetUserId)
            .maybeSingle();

        // İstek kabul edildiyse, artık takip ediliyordur (SQL trigger follows'a eklemiştir)
        if (existingRequest != null && existingRequest['status'] == 'accepted') {
          // _isFollowing'i güncelle ve takipçi sayılarını yeniden yükle
          setState(() => _isFollowing = true);
          await _loadFollowCounts();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Takip isteğiniz kabul edildi, artık bu kullanıcıyı takip ediyorsunuz'),
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            );
          }
          return;
        }

        if (existingRequest != null && existingRequest['status'] == 'pending') {
          // Zaten bekleyen istek var, iptal et
          await Supabase.instance.client
              .from('follow_requests')
              .delete()
              .eq('follower_id', currentUserId)
              .eq('following_id', targetUserId);

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
          // Yeni takip isteği gönder (duplicate'i önler)
          await Supabase.instance.client.rpc('upsert_follow_request', params: {
            'p_follower_id': currentUserId,
            'p_following_id': targetUserId,
          });

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

      // Normal takip/takibi bırak işlemi
      if (_isFollowing) {
        await Supabase.instance.client
            .from('follows')
            .delete()
            .eq('follower_id', currentUserId)
            .eq('following_id', targetUserId);

        // Gizli profillerde follow_requests kaydını da sil (tekrar istek atılabilsin)
        if (isTargetPrivate) {
          await Supabase.instance.client
              .from('follow_requests')
              .delete()
              .eq('follower_id', currentUserId)
              .eq('following_id', targetUserId);
        }
      } else {
        await Supabase.instance.client.from('follows').insert({
          'follower_id': currentUserId,
          'following_id': targetUserId,
        });
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

    if (confirm != true) return;

    try {
      await _postService.deletePost(postId);
      
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
      _loadProfile(),
      _loadUserPosts(),
      _loadUserStories(),
      _loadFollowCounts(),
      _loadAnalytics(),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading || _profileData == null) {
      return Scaffold(
        resizeToAvoidBottomInset: false,
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

    return Scaffold(
      resizeToAvoidBottomInset: false,
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
              leading: !isOwnProfile ? IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.black, size: 20),
                onPressed: () => Navigator.pop(context),
              ) : null,
              actions: [
                if (isOwnProfile)
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.4),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.add_box_outlined, color: Colors.white, size: 20),
                    ),
                    onPressed: _createPost,
                    tooltip: 'Gönderi Oluştur',
                  ),
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
                    final username = _profileData?['username'] ?? '';
                    if (username.isNotEmpty) {
                      final profileUrl = 'https://cizreapp.com/u/@$username';
                      Clipboard.setData(ClipboardData(text: profileUrl));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Profil linki kopyalandı: $profileUrl'),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                  tooltip: 'Profili Paylaş',
                ),
                IconButton(
                  icon: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.4),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.more_vert, color: Colors.white, size: 20),
                  ),
                  onPressed: isOwnProfile ? _showSettingsMenu : null,
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
                    // Username overlay
                    Positioned(
                      bottom: 16,
                      left: 20,
                      child: Text(
                        '@$username',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 0.5,
                          shadows: [
                            Shadow(
                              color: Colors.black54,
                              blurRadius: 8,
                            ),
                          ],
                        ),
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
                    // Profil resmi + İstatistikler satırı
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
                                _buildStatItem('${_userPosts.length}', 'Gönderi', null),
                                _buildStatItem('$_followersCount', 'Takipçi', () => _navigateToFollowList(FollowListType.followers)),
                                _buildStatItem('$_followingCount', 'Takip', () => _navigateToFollowList(FollowListType.following)),
                                _buildStatItem('$_friendsCount', 'Arkadaş', () => _navigateToFollowList(FollowListType.friends)),
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
                          if (_profileData!['website'] != null && _profileData!['website'].toString().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () => _launchUrl(_profileData!['website'].toString()),
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
                                        _profileData!['website'],
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
                      child: _buildActionButtons(isOwnProfile),
                    ),

                    const SizedBox(height: 16),

                    // ===== ANALİTİK BÖLÜMÜ =====
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
            if (_isLoadingPosts)
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

  Widget _buildStatItem(String count, String label, VoidCallback? onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
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
      return Row(
        children: [
          Expanded(
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                gradient: _isFollowing
                    ? null
                    : LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.primary,
                          Theme.of(context).colorScheme.primary.withOpacity(0.8),
                        ],
                      ),
                color: _isFollowing ? Colors.grey.shade100 : null,
                borderRadius: BorderRadius.circular(12),
                border: _isFollowing ? Border.all(color: Colors.grey.shade300) : null,
                boxShadow: !_isFollowing
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
                  onTap: _toggleFollow,
                  borderRadius: BorderRadius.circular(12),
                  child: Center(
                    child: Text(
                      _isFollowing ? 'Takip Ediliyor' : 'Takip Et',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _isFollowing ? Colors.black87 : Colors.white,
                      ),
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
                  onTap: _startChat,
                  borderRadius: BorderRadius.circular(12),
                  child: const Center(
                    child: Text(
                      'Mesaj',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: Colors.black87,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

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
                onTap: _editProfile,
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
        const SizedBox(width: 10),
        Container(
          height: 44,
          width: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primary,
                Theme.of(context).colorScheme.primary.withOpacity(0.8),
              ],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _createPost,
              borderRadius: BorderRadius.circular(12),
              child: const Icon(Icons.add, color: Colors.white, size: 22),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Container(
          height: 44,
          width: 44,
          decoration: BoxDecoration(
            color: Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.grey.shade300),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: _showSettingsMenu,
              borderRadius: BorderRadius.circular(12),
              child: Icon(Icons.settings_outlined, color: Colors.grey.shade700, size: 22),
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
          colors: [
            Colors.purple.shade50,
            Colors.pink.shade50,
          ],
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
            isOwnProfile ? 'İlk gönderinizi paylaşın!' : 'Bu kullanıcı henüz gönderi paylaşmadı.',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
            textAlign: TextAlign.center,
          ),
          if (isOwnProfile) ...[
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _createPost,
              style: ElevatedButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.add, size: 20),
              label: const Text('Gönderi Oluştur', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ],
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
                          // Çoklu resim ikonu
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
                          // Beğeni ve yorum overlay
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
                        child: Stack(
                          children: [
                            Center(
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
                            // Beğeni ve yorum overlay (metin gönderileri için)
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
                                    Icon(
                                      _likedPostIds.contains(post.id) ? Icons.favorite : Icons.favorite_border,
                                      color: Colors.white,
                                      size: 12,
                                    ),
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
    final username = _profileData!['username'] ?? 'Kullanıcı';
    final avatarUrl = _profileData!['avatar_url'];

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
                elevation: post.isPinned ? 4 : 2,
                shadowColor: Colors.black.withOpacity(0.1),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: post.isPinned ? BorderSide(color: Colors.amber.shade400, width: 2) : BorderSide.none,
                ),
                child: Stack(
                  children: [
                    Column(
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
                                Row(
                                  children: [
                                    Text(
                                      username,
                                      style: const TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (post.isPinned) ...[
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 6,
                                          vertical: 2,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.amber.shade700,
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: const Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.star,
                                              size: 10,
                                              color: Colors.white,
                                            ),
                                            SizedBox(width: 2),
                                            Text(
                                              'Sabitlendi',
                                              style: TextStyle(
                                                color: Colors.white,
                                                fontSize: 9,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ],
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
                          if (isOwnProfile)
                            IconButton(
                              icon: Icon(Icons.more_horiz, color: Colors.grey.shade600, size: 22),
                              onPressed: () => _showPostMenu(post.id),
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
                          // Arkadaşa Gönder
                          IconButton(
                            icon: Icon(
                              Icons.send,
                              color: Colors.grey.shade700,
                              size: 22,
                            ),
                            onPressed: () => _sendToFriend(post),
                          ),
                          // Share
                          IconButton(
                            icon: Icon(
                              Icons.share,
                              color: Colors.grey.shade700,
                              size: 22,
                            ),
                            onPressed: () => _sharePost(post),
                          ),
                          // Kaydet
                          IconButton(
                            icon: Icon(
                              _savedPosts.contains(post.id) ? Icons.bookmark : Icons.bookmark_border,
                              color: _savedPosts.contains(post.id) ? Colors.orange : Colors.grey.shade700,
                              size: 22,
                            ),
                            onPressed: () => _savePost(post),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                // Pinned Badge - Stack içinde overlay olarak
                if (post.isPinned)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade700,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.push_pin, size: 10, color: Colors.white),
                          SizedBox(width: 2),
                          Text('Sabitlendi', style: TextStyle(fontSize: 9, color: Colors.white, fontWeight: FontWeight.bold)),
                        ],
                      ),
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
            // Sabitleme seçeneği
            FutureBuilder<Post?>(
              future: _postService.getPostById(postId),
              builder: (context, snapshot) {
                if (!snapshot.hasData || snapshot.data == null) {
                  return const SizedBox.shrink();
                }
                final post = snapshot.data!;
                return ListTile(
                  leading: Icon(
                    post.isPinned ? Icons.push_pin_outlined : Icons.push_pin,
                    color: post.isPinned ? Colors.amber : Colors.grey,
                  ),
                  title: Text(post.isPinned ? 'Sabitlemeyi Kaldır' : 'Sabitle'),
                  onTap: () async {
                    Navigator.pop(context);
                    try {
                      await _postService.togglePinPost(postId);
                      setState(() {}); // UI'ı yenile
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(post.isPinned ? 'Sabitleme kaldırıldı' : 'Gönderi sabitlendi'),
                            backgroundColor: post.isPinned ? Colors.grey : Colors.amber,
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
                  },
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: Colors.red),
              title: const Text('Gönderiyi Sil', style: TextStyle(color: Colors.red)),
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
    if (currentUserId == null) return;

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
      setState(() {
        if (isLiked) {
          _likedPostIds.add(post.id);
        } else {
          _likedPostIds.remove(post.id);
        }
      });
      
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
      _loadUserPosts();
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
      _loadUserStories();
    });
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

  Future<void> _createPost() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CreatePostScreen(),
      ),
    );
    
    if (result == true) {
      _loadUserPosts();
    }
  }

  void _editProfile() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const EditProfileScreen(),
      ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('URL açılamadı')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('URL açılırken hata: $e')),
        );
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
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.block, color: Colors.red.shade400, size: 20),
              ),
              title: const Text('Engellenenler', style: TextStyle(fontWeight: FontWeight.w600)),
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
                child: Icon(Icons.flag_outlined, color: Colors.orange.shade400, size: 20),
              ),
              title: const Text('Şikayetlerim', style: TextStyle(fontWeight: FontWeight.w600)),
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
    
    if (currentUserId == null || targetUserId == null || currentUserId == targetUserId) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Konuşma başlatılamadı')),
        );
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

      final conversation = await _chatService.getOrCreateConversation(targetUserId);
      
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
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Konuşma başlatılamadı')),
        );
      }
    } catch (e) {
      debugPrint('Konuşma başlatılırken hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Konuşma başlatılamadı: $e')),
        );
      }
    }
  }

  /// Gönderiyi arkadaşa gönder
  Future<void> _sendToFriend(Post post) async {
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Lütfen giriş yapın')),
          );
        }
        return;
      }

      // Takip edilen kullanıcıları getir
      final following = await Supabase.instance.client
          .from('follows')
          .select('following_id, profiles!follows_following_id_fkey(full_name, avatar_url)')
          .eq('follower_id', currentUserId)
          .order('created_at', ascending: false);

      if (!mounted) return;

      if (following.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Takip ettiğiniz kimse yok')),
          );
        }
        return;
      }

      // Takipçi seçim dialogu göster
      await showModalBottomSheet(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Arkadaşına Gönder',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: following.length,
                  itemBuilder: (context, index) {
                    final user = following[index];
                    final profile = user['profiles'] as Map<String, dynamic>?;
                    final name = profile?['full_name'] as String? ?? 'Kullanıcı';
                    final avatar = profile?['avatar_url'] as String?;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: avatar != null ? NetworkImage(avatar) : null,
                        child: avatar == null ? Text(name[0].toUpperCase()) : null,
                      ),
                      title: Text(name),
                      onTap: () async {
                        await _sendPostToFriend(user['following_id'], post);
                        if (mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('$name adlı kullanıcıya gönderildi')),
                          );
                        }
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
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e')),
        );
      }
    }
  }

  /// Arkadaşa gönderi bildirimi gönder (Push notification ile)
  Future<void> _sendPostToFriend(String targetUserId, Post post) async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    
    await Supabase.instance.client.from('notifications').insert({
      'user_id': targetUserId,
      'type': 'post_share',
      'title': 'Gönderi Paylaşıldı',
      'content': '${Supabase.instance.client.auth.currentUser?.userMetadata?['full_name'] ?? 'Bir arkadaşınız'} size bir gönderi paylaştı.',
      'entity_id': post.id,
      'entity_type': 'post',
    });
    
    // Push notification gönder
    try {
      await Supabase.instance.client.functions.invoke(
        'send-push',
        body: {
          'userId': targetUserId,
          'title': 'Gönderi Paylaşımı',
          'body': '${Supabase.instance.client.auth.currentUser?.userMetadata?['full_name'] ?? 'Bir arkadaşınız'} size bir gönderi paylaştı',
          'data': {'type': 'post_share', 'postId': post.id, 'senderId': currentUserId},
        },
      );
    } catch (e) {
      debugPrint('Push notification gönderilemedi: $e');
    }
  }

  /// Gönderiyi paylaş (Sadece WhatsApp ve Bağlantı Kopyala)
  Future<void> _sharePost(Post post) async {
    try {
      final postUrl = 'https://cizreapp.com/post/${post.id}';
      final shareText = '${post.content ?? ''}\n\n$postUrl';
      
      await showModalBottomSheet(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.all(16.0),
                child: Text(
                  'Gönderiyi Paylaş',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              ListTile(
                leading: Icon(Icons.message, color: Colors.green[700]),
                title: const Text('WhatsApp'),
                onTap: () async {
                  final url = Uri.parse('https://wa.me/?text=${Uri.encodeComponent(shareText)}');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url, mode: LaunchMode.externalApplication);
                  }
                  if (mounted) Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(Icons.link, color: Colors.blue),
                title: const Text('Bağlantıyı Kopyala'),
                onTap: () async {
                  await _copyToClipboard(postUrl);
                  if (mounted) Navigator.pop(context);
                },
              ),
              ListTile(
                leading: Icon(Icons.close, color: Colors.grey[600]),
                title: const Text('İptal'),
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Paylaşım hatası: $e')),
        );
      }
    }
  }

  Future<void> _copyToClipboard(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Link panoya kopyalandı!')),
      );
    }
  }

  /// Gönderiyi kaydet (Supabase post_favorites tablosu)
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
