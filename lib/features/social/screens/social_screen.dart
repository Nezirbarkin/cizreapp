import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/models/post_model.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/widgets/settings_sidebar.dart';
import '../../../core/utils/image_compression_helper.dart';
import '../services/post_service.dart';
import '../services/story_service.dart';
import '../../market/screens/search_screen.dart';
import '../../market/screens/notifications_screen.dart';
import 'create_post_screen.dart';
import 'post_detail_screen.dart';
import 'story_viewers_screen.dart';
import 'story_viewer_screen.dart';
import '../../profile/screens/user_profile_screen.dart';

class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key});

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen> {
  final PostService _postService = PostService();
  final StoryService _storyService = StoryService();
  final ImagePicker _imagePicker = ImagePicker();
  final NotificationService _notificationService = NotificationService();
  late ScrollController _scrollController;

  List<Post> _posts = [];
  List<Story> _stories = [];
  List<Story> _userStories = []; // Kullanıcının kendi hikayeleri
  Map<String, bool> _likedPosts = {};
  Map<String, Map<String, dynamic>> _userProfiles = {}; // user_id -> profile
  Map<String, dynamic>? _currentUserProfile; // Mevcut kullanıcı profili
  int _unreadNotificationCount = 0;
  bool _isLoading = true;
  
  // Pagination variables
  int _currentPage = 0;
  static const int _pageSize = 20;
  bool _hasMore = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _loadData();
    _loadNotificationCount();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (_hasMore && !_isLoadingMore && !_isLoading) {
        _loadMorePosts();
      }
    }
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    _currentPage = 0;
    _hasMore = true;
    
    // Önceki cache'leri temizle - stale data sorununu önlemek için
    _posts.clear();
    _userProfiles.clear();
    _likedPosts.clear();

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Feed ve stories yükle - pagination için
      final posts = await _postService.getFeed(limit: _pageSize, offset: 0);
      final allStories = await _storyService.getStories();
      final userStories = await _storyService.getUserStories(userId);

      // HasMore kontrolü - eğer dönen veri pageSize'dan azsa, başka sayfa yok
      _hasMore = posts.length >= _pageSize;

      // Diğer kullanıcıların story'leri (kendi hikayeleri hariç)
      final otherStories = allStories.where((s) => s.userId != userId).toList();

      // Kullanıcı profillerini yükle (benzersiz user_id'ler)
      final userIds = <String>{userId};
      for (var post in posts) {
        userIds.add(post.userId);
      }
      for (var story in otherStories) {
        userIds.add(story.userId);
      }

      // Batch olarak profilleri yükle
      final profiles = <String, Map<String, dynamic>>{};
      try {
        final profilesData = await Supabase.instance.client
            .from('profiles')
            .select('id, username, full_name, avatar_url')
            .inFilter('id', userIds.toList());

        for (var profileData in profilesData) {
          profiles[profileData['id']] = profileData;
          // Mevcut kullanıcının profilini sakla
          if (profileData['id'] == userId) {
            _currentUserProfile = profileData;
          }
        }
      } catch (e) {
        debugPrint('Profiller yüklenirken hata: $e');
      }

      // ⚡ OPTİMİZE: Beğeni durumlarını tek sorguda kontrol et (N+1 query yerine 1 query)
      final likedStatus = <String, bool>{};
      if (posts.isNotEmpty) {
        final postIds = posts.map((p) => p.id).toList();
        final likedPostIds = await _postService.getLikedPostIds(userId, postIds);
        
        for (var post in posts) {
          likedStatus[post.id] = likedPostIds.contains(post.id);
        }
      }

      setState(() {
        _posts = posts;
        _stories = otherStories;
        _userStories = userStories;
        _userProfiles = profiles;
        _likedPosts = likedStatus;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        // Kullanıcı dostu hata mesajı
        String errorMsg = 'Veriler yüklenirken bir hata oluştu';
        if (e.toString().contains('İnternet bağlantınızı') || e.toString().contains('Bağlantı zaman aşımı')) {
          errorMsg = e.toString().replaceAll('Exception: ', '');
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errorMsg)),
        );
      }
    }
  }

  Future<void> _loadMorePosts() async {
    if (_isLoadingMore) return;

    setState(() => _isLoadingMore = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        setState(() => _isLoadingMore = false);
        return;
      }

      _currentPage++;
      final offset = _currentPage * _pageSize;
      final newPosts = await _postService.getFeed(limit: _pageSize, offset: offset);

      // Yeni profilleri yükle
      final userIds = <String>{};
      for (var post in newPosts) {
        userIds.add(post.userId);
      }

      if (userIds.isNotEmpty) {
        try {
          final profilesData = await Supabase.instance.client
              .from('profiles')
              .select('id, username, full_name, avatar_url')
              .inFilter('id', userIds.toList());

          for (var profileData in profilesData) {
            _userProfiles[profileData['id']] = profileData;
          }
        } catch (e) {
          debugPrint('Ek profiller yüklenirken hata: $e');
        }
      }

      // Beğeni durumlarını yükle
      final likedStatus = <String, bool>{};
      if (newPosts.isNotEmpty) {
        final postIds = newPosts.map((p) => p.id).toList();
        final likedPostIds = await _postService.getLikedPostIds(userId, postIds);
        
        for (var post in newPosts) {
          likedStatus[post.id] = likedPostIds.contains(post.id);
        }
      }

      setState(() {
        _posts.addAll(newPosts);
        _likedPosts.addAll(likedStatus);
        _hasMore = newPosts.length >= _pageSize;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() => _isLoadingMore = false);
      _currentPage--; // Hata olursa sayfayı geri al
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Daha fazla gönderi yüklenirken hata: $e')),
        );
      }
    }
  }

  Future<void> _loadNotificationCount() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;
    try {
      final count = await _notificationService.getUnreadCount(userId);
      if (mounted) {
        setState(() => _unreadNotificationCount = count);
      }
    } catch (e) {
      debugPrint('Bildirim sayısı yüklenirken hata: $e');
    }
  }

  Future<void> _deletePost(String postId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gönderiyi Sil'),
        content: const Text('Bu gönderiyi silmek istediğinizden emin misiniz?'),
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
      await _postService.deletePost(postId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gönderi silindi'),
            backgroundColor: Colors.green,
          ),
        );
        // Feed'i yenile
        _loadData();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gönderi silinirken hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _toggleLike(Post post) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final isLiked = _likedPosts[post.id] ?? false;
    
    // Optimistic update - UI'ı hemen güncelle
    setState(() {
      _likedPosts[post.id] = !isLiked;
      // Post'un like count'unu güncelle
      final index = _posts.indexWhere((p) => p.id == post.id);
      if (index != -1) {
        _posts[index] = _posts[index].copyWith(
          likesCount: isLiked ? _posts[index].likesCount - 1 : _posts[index].likesCount + 1,
        );
      }
    });

    try {
      if (isLiked) {
        await _postService.unlikePost(post.id, userId);
      } else {
        await _postService.likePost(post.id, userId);
      }
    } catch (e) {
      // Hata olursa geri al
      setState(() {
        _likedPosts[post.id] = isLiked;
        final index = _posts.indexWhere((p) => p.id == post.id);
        if (index != -1) {
          _posts[index] = _posts[index].copyWith(
            likesCount: isLiked ? _posts[index].likesCount + 1 : _posts[index].likesCount - 1,
          );
        }
      });
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Beğeni işlemi başarısız: $e')),
        );
      }
    }
  }

  Future<void> _showComments(Post post) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PostDetailScreen(post: post),
      ),
    );
    
    // ⚡ OPTİMİZE: Sadece post silinmişse veya değişmişse yenile
    // Yorumlar sadece detail screen'de görünür, ana feed'de değil
    if (result == 'deleted' || result == 'updated') {
      _loadData();
    }
  }

  Future<void> _createPost() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => const CreatePostScreen(),
      ),
    );
    // Gönderi oluşturduktan sonra feed'i yenile
    _loadData();
  }

  Future<void> _sharePost(Post post) async {
    try {
      final userProfile = _userProfiles[post.userId];
      final username = userProfile?['full_name'] ?? userProfile?['username'] ?? 'Bilinmeyen';
      
      // Paylaşım metni oluştur
      final StringBuffer shareText = StringBuffer();
      shareText.writeln('📱 CizreApp\'te $username paylaştı:');
      shareText.writeln();
      
      if (post.content != null && post.content!.isNotEmpty) {
        shareText.writeln(post.content!);
        shareText.writeln();
      }
      
      if (post.location != null && post.location!.isNotEmpty) {
        shareText.writeln('📍 ${post.location}');
      }
      
      shareText.writeln('CizreApp\'i indir ve sen de katıl! 🎉');
      
      await SharePlus.instance.share(
        ShareParams(
          text: shareText.toString(),
        ),
      );
    } catch (e) {
      debugPrint('Paylaşım hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Paylaşım yapılamadı')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      backgroundColor: primaryColor,
      body: Stack(
        children: [
          Column(
            children: [
          // Özel Header (Stories dahil)
          _buildHeader(context, primaryColor),

          // İçerik alanı
          Expanded(
            child: ClipRRect(
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(40),
                topRight: Radius.circular(40),
              ),
              child: Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                ),
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : RefreshIndicator(
                        onRefresh: _loadData,
                        color: primaryColor,
                        child: CustomScrollView(
                          controller: _scrollController,
                          slivers: [
                            // Posts
                            _posts.isEmpty
                                ? SliverFillRemaining(
                                    child: _buildEmptyState(),
                                  )
                                : SliverList(
                                    delegate: SliverChildBuilderDelegate(
                                      (context, index) {
                                        final post = _posts[index];
                                        return Column(
                                          children: [
                                            if (index == 0) const SizedBox(height: 4),
                                            _buildTwitterPostCard(post),
                                            if (index < _posts.length - 1)
                                              Divider(
                                                height: 1,
                                                thickness: 1,
                                                color: Colors.grey.shade200,
                                                indent: 72,
                                              ),
                                          ],
                                        );
                                      },
                                      childCount: _posts.length,
                                    ),
                                  ),
                            // Loading indicator
                            if (_isLoadingMore)
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 16),
                                  child: Center(
                                    child: SizedBox(
                                      width: 32,
                                      height: 32,
                                      child: CircularProgressIndicator(
                                        color: primaryColor,
                                        strokeWidth: 2,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            // No more posts indicator
                            if (!_hasMore && _posts.isNotEmpty)
                              SliverToBoxAdapter(
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 24),
                                  child: Center(
                                    child: Text(
                                      'Başka gönderi yok',
                                      style: TextStyle(
                                        color: Colors.grey.shade500,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
              ),
            ),
          ),
            ],
          ),
          // Yüzen + butonu (Profil ikonunun üzerinde, FloatingMessageButton gibi)
          Positioned(
            right: kIsWeb ? 28 : 20,
            bottom: kIsWeb ? 100 : 140,
            child: GestureDetector(
              onTap: _createPost,
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 10,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.add,
                  color: primaryColor,
                  size: 28,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, Color primaryColor) {
    // Platform'a göre topPadding hesapla (Market Screen ile aynı)
    final screenSize = MediaQuery.of(context).size;
    final isMobileWeb = kIsWeb && screenSize.width <= 600;
    
    double topPadding;
    if (isMobileWeb) {
      // Mobil web: minimal padding
      topPadding = 4.0;
    } else if (kIsWeb) {
      // Desktop web: normal padding
      topPadding = 20.0;
    } else {
      // Mobil uygulama: SafeArea padding + minimal padding
      final safePadding = MediaQuery.of(context).padding.top;
      topPadding = safePadding + 4.0;
    }
    
    return Container(
      padding: EdgeInsets.fromLTRB(20, topPadding, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık ve aksiyonlar
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              GestureDetector(
                onTap: () {
                  // Sayfayı en üste scroll et
                  _scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                  );
                },
                child: const Text(
                  'CizreApp',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w900,
                    color: Colors.white,
                    letterSpacing: 1.5,
                  ),
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Arama ikonu
                  IconButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const SearchScreen(),
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.search_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                    padding: EdgeInsets.zero,
                    splashRadius: 16,
                    constraints: const BoxConstraints(),
                  ),
                  const SizedBox(width: 1),
                  // Bildirim ikonu
                  GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const NotificationsScreen(),
                        ),
                      ).then((_) {
                        _loadNotificationCount();
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.all(1),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          const Icon(
                            Icons.notifications_outlined,
                            color: Colors.white,
                            size: 22,
                          ),
                          // Bildirim badge'i
                          if (_unreadNotificationCount > 0)
                            Positioned(
                              top: -3,
                              right: -3,
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: const BoxDecoration(
                                  color: Color(0xFFFF3D00),
                                  shape: BoxShape.circle,
                                ),
                                constraints: const BoxConstraints(
                                  minWidth: 13,
                                  minHeight: 13,
                                ),
                                child: Text(
                                  _unreadNotificationCount > 9 ? '9+' : '$_unreadNotificationCount',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 1),
                  // Ayarlar ikonu
                  IconButton(
                    onPressed: () {
                      showSettingsSidebar(context);
                    },
                    icon: const Icon(
                      Icons.settings_outlined,
                      color: Colors.white,
                      size: 22,
                    ),
                    padding: EdgeInsets.zero,
                    splashRadius: 16,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Stories section
          _buildStoriesSection(),
        ],
      ),
    );
  }

  Widget _buildStoriesSection() {
    // LayoutBuilder ile ekran genişliğine göre 3 hikaye gösterecek şekilde
    return LayoutBuilder(
      builder: (context, constraints) {
        // Ekran genişliği - yatay padding'ler
        final availableWidth = constraints.maxWidth;
        // Her story için genişlik (3 hikaye + "Hikayem" butonu = 4 item)
        final storyWidth = (availableWidth - 40) / 4; // 40 = toplam padding
        
        return SizedBox(
          height: storyWidth + 30, // Story circle + isim + padding
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            itemCount: _stories.length + 1, // +1 için "Hikayem" butonu
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildMyStoryButtonDynamic(storyWidth);
              } else {
                return _buildStoryCardDynamic(_stories[index - 1], storyWidth);
              }
            },
          ),
        );
      },
    );
  }



  Widget _buildMyStoryButtonDynamic(double size) {
    final username = _currentUserProfile?['username'] ?? 'Sen';
    final avatarUrl = _currentUserProfile?['avatar_url'];
    final hasStories = _userStories.isNotEmpty;
    final latestStory = hasStories ? _userStories.first : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          GestureDetector(
            onTap: () {
              if (hasStories) {
                _viewUserStories();
              } else {
                _addStory();
              }
            },
            child: Stack(
              children: [
                Container(
                  width: size,
                  height: size,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: hasStories
                        ? const LinearGradient(
                            colors: [Colors.purple, Colors.pink, Colors.orange],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    border: !hasStories
                        ? Border.all(color: Colors.grey.shade300, width: 2)
                        : null,
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(hasStories ? 2 : 0),
                    child: ClipOval(
                      child: hasStories && latestStory != null
                          ? Stack(
                              children: [
                                // En son story içeriğini göster - displayUrl kullanıyoruz
                                Image.network(
                                  latestStory.displayUrl,
                                  width: size - 4,
                                  height: size - 4,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) {
                                    return Container(
                                      width: size - 4,
                                      height: size - 4,
                                      color: Colors.grey.shade300,
                                      child: avatarUrl != null
                                          ? Image.network(avatarUrl, fit: BoxFit.cover)
                                          : Icon(Icons.person, size: size * 0.4, color: Colors.grey),
                                    );
                                  },
                                  loadingBuilder: (context, child, loadingProgress) {
                                    if (loadingProgress == null) return child;
                                    return Container(
                                      width: size - 4,
                                      height: size - 4,
                                      color: Colors.grey.shade200,
                                      child: Center(
                                        child: SizedBox(
                                          width: size * 0.3,
                                          height: size * 0.3,
                                          child: const CircularProgressIndicator(strokeWidth: 2),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                // Video indicator
                                if (latestStory.isVideo)
                                  Container(
                                    width: size - 4,
                                    height: size - 4,
                                    color: Colors.black26,
                                    child: Center(
                                      child: Icon(
                                        Icons.play_circle_filled,
                                        color: Colors.white,
                                        size: size * 0.35,
                                      ),
                                    ),
                                  ),
                              ],
                            )
                          : Container(
                              width: size,
                              height: size,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                // ignore: deprecated_member_use
                                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
                              ),
                              child: avatarUrl != null
                                  ? Image.network(avatarUrl, fit: BoxFit.cover)
                                  : Center(
                                      child: Text(
                                        username.isNotEmpty && username.length >= 1
                                            ? username.substring(0, 1).toUpperCase()
                                            : 'S',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: size * 0.3,
                                          color: Theme.of(context).colorScheme.primary,
                                        ),
                                      ),
                                    ),
                            ),
                    ),
                  ),
                ),
                if (!hasStories)
                  Positioned(
                    bottom: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Icon(
                        Icons.add,
                        size: size * 0.25,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: size,
            height: 14,
            child: const Text(
              'Hikayem',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: Colors.white),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStoryCardDynamic(Story story, double size) {
    final userProfile = _userProfiles[story.userId];
    final username = userProfile?['username'] ?? (story.userId.length >= 8 ? story.userId.substring(0, 8) : story.userId);
    final fullName = userProfile?['full_name'] ?? username;
    final avatarUrl = userProfile?['avatar_url'];
    
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        children: [
          // Story circle - çemberli
          GestureDetector(
            onTap: () => _viewStory(story),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: story.isViewedByCurrentUser
                    ? null // İzlendiyse gradient yok (gri)
                    : const LinearGradient( // İzlenmediyse renkli gradient
                        colors: [Colors.purple, Colors.pink, Colors.orange],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                color: story.isViewedByCurrentUser
                    ? Colors.grey.shade300 // İzlendiyse gri
                    : null, // İzlenmediyse gradient kullan
              ),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: ClipOval(
                  child: Stack(
                    children: [
                      // Story içerik önizlemesi - displayUrl kullanıyoruz (thumbnail varsa onu gösterir)
                      Image.network(
                        story.displayUrl,
                        width: size - 4,
                        height: size - 4,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: size - 4,
                            height: size - 4,
                            color: Colors.grey.shade300,
                            child: avatarUrl != null
                                ? Image.network(avatarUrl, fit: BoxFit.cover)
                                : Icon(Icons.person, size: size * 0.4, color: Colors.grey),
                          );
                        },
                        loadingBuilder: (context, child, loadingProgress) {
                          if (loadingProgress == null) return child;
                          return Container(
                            width: size - 4,
                            height: size - 4,
                            color: Colors.grey.shade200,
                            child: Center(
                              child: SizedBox(
                                width: size * 0.3,
                                height: size * 0.3,
                                child: const CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        },
                      ),
                      // Video indicator - play icon
                      if (story.isVideo)
                        Container(
                          width: size - 4,
                          height: size - 4,
                          color: Colors.black26,
                          child: Center(
                            child: Icon(
                              Icons.play_circle_filled,
                              color: Colors.white,
                              size: size * 0.35,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          // Tam ad
          SizedBox(
            width: size,
            child: Text(
              fullName.length > 10 ? '${fullName.substring(0, 10)}...' : fullName,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _viewUserProfile(String userId) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(userId: userId),
      ),
    );
  }

  Future<void> _addStory() async {
    // Direkt media picker'ı aç (image ve video birlikte)
    // Not: maxWidth/maxHeight kaldırıldı - orijinal aspect ratio korunsun
    final XFile? media = await _imagePicker.pickMedia();

    if (media == null) return;

    // Dosya uzantısından media type'ı belirle
    // Web'de media.path blob URL olabilir, media.name daha güvenilir
    final fileName = kIsWeb ? media.name : media.path;
    final ext = fileName.split('.').last.toLowerCase();
    final videoExtensions = ['mp4', 'mov', 'avi', 'mkv', 'webm', '3gp'];
    final mediaType = videoExtensions.contains(ext) ? 'video' : 'image';

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      String? thumbnailUrl; // Video thumbnail URL
      String mediaUrl;

      if (mediaType == 'image') {
        // Fotoğraf için progress dialog göster
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: Card(
              child: Padding(
                padding: EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text('Fotoğraf yükleniyor...'),
                  ],
                ),
              ),
            ),
          ),
        );

        // Fotoğrafı sıkıştır ve yükle (Web ve Mobile uyumlu)
        debugPrint('🖼️ Story fotoğrafı işleniyor...');
        
        Uint8List imageBytes;
        String fileExt;
        
        if (kIsWeb) {
          // Web: XFile'dan byte array al
          final compressedBytes = await ImageCompressionHelper.compressXFile(
            xFile: media,
            quality: 92,
            maxWidth: 1080,
            maxHeight: 1920,
          );
          imageBytes = compressedBytes ?? await media.readAsBytes();
          fileExt = media.name.split('.').last.toLowerCase();
          debugPrint('📏 Web story boyutu: ${(imageBytes.length / 1024 / 1024).toStringAsFixed(2)} MB');
        } else {
          // Mobile: XFile üzerinden sıkıştır
          final compressedBytes = await ImageCompressionHelper.compressXFile(
            xFile: media,
            quality: 92,
            maxWidth: 1080,
            maxHeight: 1920,
          );
          imageBytes = compressedBytes ?? await media.readAsBytes();
          fileExt = media.name.split('.').last.toLowerCase();
          debugPrint('📏 Mobile story boyutu: ${(imageBytes.length / 1024 / 1024).toStringAsFixed(2)} MB');
        }

        // Fotoğrafı yükle
        final fileName = 'story_${userId}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
        final filePath = 'stories/$fileName';

        await Supabase.instance.client.storage.from('stories').uploadBinary(
          filePath,
          imageBytes,
          fileOptions: FileOptions(contentType: 'image/$fileExt'),
        );
        mediaUrl = Supabase.instance.client.storage.from('stories').getPublicUrl(filePath);
        
        debugPrint('✅ Story fotoğrafı yüklendi: $mediaUrl');
        
        if (mounted) Navigator.pop(context); // Progress dialog'u kapat
      } else {
        // Video için progress tracking StateNotifier kullan
        if (!mounted) return;
        
        // Video progress dialog'u aç
        final progressNotifier = ValueNotifier<double>(0.0);
        
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => Center(
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ValueListenableBuilder<double>(
                      valueListenable: progressNotifier,
                      builder: (context, value, child) {
                        return Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(value: value),
                            const SizedBox(height: 16),
                            Text(
                              value < 0.30
                                  ? 'Thumbnail oluşturuluyor...'
                                  : 'Video yükleniyor...',
                            ),
                            const SizedBox(height: 8),
                            Text('${(value * 100).toInt()}%'),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        // Video için thumbnail ile yükle
        debugPrint('Video yükleniyor, thumbnail oluşturuluyor...');
        final result = await _storyService.uploadVideoWithThumbnail(
          videoPath: media.path,
          xFile: media,
          onProgress: (p) {
            progressNotifier.value = p;
          },
        );
        
        if (mounted) Navigator.pop(context); // Progress dialog'u kapat
        
        if (result == null || result['videoUrl'] == null) {
          throw Exception('Video yüklenirken hata oluştu');
        }

        mediaUrl = result['videoUrl']!;
        thumbnailUrl = result['thumbnailUrl']!.isNotEmpty ? result['thumbnailUrl']! : null;
        debugPrint('Video URL: $mediaUrl');
        debugPrint('Thumbnail URL: $thumbnailUrl');
      }

      debugPrint('Story oluşturuluyor: mediaType=$mediaType, url=$mediaUrl');

      final newStory = await _storyService.createStory(
        userId: userId,
        imageUrl: mediaUrl,
        mediaType: mediaType,
        thumbnailUrl: thumbnailUrl, // Video için thumbnail URL'ini geçir
      );

      debugPrint('Story oluşturuldu: ${newStory?.id}');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mediaType == 'image' ? 'Fotoğraf hikayesi paylaşıldı!' : 'Video hikayesi paylaşıldı!',
            ),
          ),
        );
        // Verileri yeniden yükle
        await _loadData();
        debugPrint('Veriler yenilendi, userStories count: ${_userStories.length}');
      }
    } catch (e) {
      debugPrint('Story yüklenirken hata: $e');
      // Eğer progress dialog açıksa kapat
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Story yüklenirken hata: $e')),
        );
      }
    }
  }


  // TODO: Story silme özelliği StoryViewerScreen'e eklenecek
  // Future<void> _deleteStory(String storyId) async {
  //   final confirmed = await showDialog<bool>(
  //     context: context,
  //     builder: (context) => AlertDialog(
  //       title: const Text('Hikayeyi Sil'),
  //       content: const Text('Bu hikayeyi silmek istediğinizden emin misiniz?'),
  //       actions: [
  //         TextButton(
  //           onPressed: () => Navigator.pop(context, false),
  //           child: const Text('İptal'),
  //         ),
  //         TextButton(
  //           onPressed: () => Navigator.pop(context, true),
  //           style: TextButton.styleFrom(foregroundColor: Colors.red),
  //           child: const Text('Sil'),
  //         ),
  //       ],
  //     ),
  //   );

  //   if (confirmed != true) return;

  //   try {
  //     await _storyService.deleteStory(storyId);
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         const SnackBar(
  //           content: Text('Hikaye silindi'),
  //           backgroundColor: Colors.green,
  //         ),
  //       );
  //       setState(() {
  //         _userStories.removeWhere((s) => s.id == storyId);
  //       });
  //     }
  //   } catch (e) {
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(
  //           content: Text('Hikaye silinirken hata: $e'),
  //           backgroundColor: Colors.red,
  //         ),
  //       );
  //     }
  //   }
  // }

  Future<void> _viewStory(Story story) async {
    // Tüm story'leri gösteren yeni viewer'ı aç
    if (_stories.isEmpty) return;

    // Tıklanan story'nin index'ini bul
    final initialIndex = _stories.indexWhere((s) => s.id == story.id);
    if (initialIndex == -1) return;

    // Görüntüleme kaydını story_viewer_screen'e bırak (çift kayıt önlemek için)

    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => StoryViewerScreen(
            stories: _stories,
            initialIndex: initialIndex,
          ),
        ),
      );
      // Verileri yenile
      _loadData();
    }
  }

  Future<void> _viewUserStories() async {
    // Kullanıcının kendi hikayelerini göster
    if (_userStories.isEmpty) return;

    if (mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => StoryViewerScreen(
            stories: _userStories,
            initialIndex: 0,
          ),
        ),
      );
      _loadData();
    }
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.feed_outlined,
            size: 64,
            color: Colors.grey.shade400,
          ),
          const SizedBox(height: 16),
          Text(
            'Henüz gönderi yok',
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey.shade600,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'İlk gönderiyi sen paylaş!',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTwitterPostCard(Post post) {
    final userProfile = _userProfiles[post.userId];
    final fullName = userProfile?['full_name'] ?? userProfile?['username'] ?? 'Kullanıcı';
    final username = userProfile?['username'] ?? post.userId.substring(0, 8);
    final handle = '@$username';
    final avatarUrl = userProfile?['avatar_url'];
    final isLiked = _likedPosts[post.id] ?? false;
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isOwnPost = post.userId == currentUserId;

    return GestureDetector(
      behavior: HitTestBehavior.opaque, // Tüm alanı tıklanabilir yap
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => PostDetailScreen(post: post),
        ),
      ),
      onDoubleTap: () => _toggleLike(post), // Double tap ile beğeni
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar - Tıklanabilir
            GestureDetector(
              onTap: () => _viewUserProfile(post.userId),
              child: Column(
                children: [
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                    child: avatarUrl == null
                        ? Text(
                            username.length >= 2
                                ? username.substring(0, 2).toUpperCase()
                                : username.toUpperCase(),
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          )
                        : null,
                  ),
                  if (post.images.isNotEmpty && post.images.first.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      width: 2,
                      height: 100,
                      color: Colors.grey.shade200,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),

            // Post content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User info row
                  Row(
                    children: [
                      // İsim ve username - Tıklanabilir (dikey olarak)
                      GestureDetector(
                        onTap: () => _viewUserProfile(post.userId),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  fullName,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: Colors.black87,
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
                              handle,
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey.shade600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '·',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDate(post.createdAt),
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 15,
                        ),
                      ),
                      const Spacer(),
                      if (isOwnPost)
                        PopupMenuButton<String>(
                          icon: Icon(
                            Icons.more_horiz,
                            color: Colors.grey.shade500,
                            size: 18,
                          ),
                          onSelected: (value) {
                            if (value == 'delete') {
                              _deletePost(post.id);
                            }
                          },
                          itemBuilder: (context) => [
                            const PopupMenuItem(
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
                      else
                        Icon(
                          Icons.more_horiz,
                          color: Colors.grey.shade500,
                          size: 18,
                        ),
                    ],
                  ),

                  const SizedBox(height: 4),

                  // Post content
                  if (post.content != null && post.content!.isNotEmpty)
                    Text(
                      post.content!,
                      style: const TextStyle(
                        fontSize: 15,
                        color: Colors.black87,
                        height: 1.4,
                      ),
                    ),

                  const SizedBox(height: 8),

                  // Post image - sadece geçerli URL varsa göster
                  if (post.images.isNotEmpty && post.images.first.isNotEmpty)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Image.network(
                        post.images.first,
                        width: double.infinity,
                        height: 200,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          // Görsel yüklenemezse hiçbir şey gösterme
                          return const SizedBox.shrink();
                        },
                      ),
                    ),

                  // Location
                  if (post.location != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.location_on, size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Text(
                          post.location!,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade500,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 12),

                  // Action buttons
                  Container(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Reply/Comment
                        _buildActionButton(
                          icon: Icons.chat_bubble_outline,
                          count: post.commentsCount,
                          onTap: () => _showComments(post),
                          color: Colors.blue,
                        ),

                        // Retweet
                        _buildActionButton(
                          icon: Icons.repeat,
                          count: null,
                          onTap: () {},
                          color: Colors.green,
                        ),

                        // Like
                        _buildActionButton(
                          icon: isLiked ? Icons.favorite : Icons.favorite_border,
                          count: post.likesCount,
                          onTap: () => _toggleLike(post),
                          color: Colors.red,
                          isActive: isLiked,
                        ),

                        // Share
                        _buildActionButton(
                          icon: Icons.share,
                          count: null,
                          onTap: () => _sharePost(post),
                          color: Colors.grey,
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
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required int? count,
    required VoidCallback onTap,
    required Color color,
    bool isActive = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        children: [
          Icon(
            icon,
            color: isActive ? color : Colors.grey.shade600,
            size: 18,
          ),
          if (count != null) ...[
            const SizedBox(width: 6),
            Text(
              count.toString(),
              style: TextStyle(
                color: isActive ? color : Colors.grey.shade600,
                fontSize: 14,
                fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
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
}

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
                  : Image.network(
                      widget.story.imageUrl,
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, loadingProgress) {
                        if (loadingProgress == null) return child;
                        return const Center(
                          child: CircularProgressIndicator(color: Colors.white),
                        );
                      },
                      errorBuilder: (context, error, stackTrace) {
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
}
