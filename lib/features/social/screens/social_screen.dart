// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/models/post_model.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/widgets/settings_sidebar.dart';
import '../../../core/utils/image_compression_helper.dart';
import '../services/post_service.dart';
import '../services/story_service.dart';
import '../services/post_report_service.dart';
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
  final PostReportService _postReportService = PostReportService();
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

  /// Gönderi Şikayet Dialog - Apple Guideline 1.2
  void _showPostReportDialog(Post post) {
    String? selectedReason;
    final descriptionController = TextEditingController();
    bool isSubmitting = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) {
          return Container(
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
            ),
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.orange.shade50,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.flag_rounded, color: Colors.orange.shade700),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text('Gönderiyi Şikayet Et', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        post.content ?? 'Görsel içerik',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text('Şikayet Nedeni', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 10),
                    ...PostReportService.reportReasons.entries.map((entry) {
                      return RadioListTile<String>(
                        value: entry.key,
                        groupValue: selectedReason,
                        onChanged: (v) => setSheetState(() => selectedReason = v),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(entry.value, style: const TextStyle(fontSize: 14)),
                        activeColor: Colors.orange,
                      );
                    }),
                    const SizedBox(height: 16),
                    const Text('Açıklama (opsiyonel)', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descriptionController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Daha fazla bilgi verin...',
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.all(12),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.amber.shade50,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.info_outline, color: Colors.amber.shade700, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Şikayetiniz ekibimiz tarafından incelenecek.',
                              style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(context),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: const Text('İptal'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          flex: 2,
                          child: ElevatedButton(
                            onPressed: selectedReason == null || isSubmitting
                                ? null
                                : () async {
                                    setSheetState(() => isSubmitting = true);
                                    final result = await _postReportService.reportPost(
                                      reportedPostId: post.id,
                                      reason: selectedReason!,
                                      description: descriptionController.text.trim().isEmpty ? null : descriptionController.text.trim(),
                                    );
                                    if (!context.mounted) return;
                                    Navigator.pop(context);
                                    if (result == 'success') {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Şikayetiniz alındı. Teşekkürler!'), backgroundColor: Colors.green),
                                      );
                                    } else if (result == 'duplicate') {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Bu gönderiyi zaten şikayet etmişsiniz.'), backgroundColor: Colors.orange),
                                      );
                                    } else {
                                      // Hata detayını göster
                                      final errorMsg = result.toString().replaceAll('error: ', '');
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(content: Text('Şikayet gönderilemedi: $errorMsg'), backgroundColor: Colors.red, duration: const Duration(seconds: 5)),
                                      );
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: isSubmitting
                                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                : const Text('Şikayet Et'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
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
    // Instagram tarzı story oluşturma bottom sheet'i aç
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _InstagramStoryCreator(
        imagePicker: _imagePicker,
        onMediaSelected: (media, mediaType) async {
          // Seçilen medyayı yükle
          await _uploadAndCreateStory(media, mediaType);
        },
      ),
    );
  }

  Future<void> _uploadAndCreateStory(XFile media, String mediaType) async {
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
        debugPrint('Story fotoğrafı işleniyor...');
        
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
          debugPrint('Web story boyutu: ${(imageBytes.length / 1024 / 1024).toStringAsFixed(2)} MB');
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
          debugPrint('Mobile story boyutu: ${(imageBytes.length / 1024 / 1024).toStringAsFixed(2)} MB');
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
        
        debugPrint('Story fotoğrafı yüklendi: $mediaUrl');
        
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
                      PopupMenuButton<String>(
                        icon: Icon(
                          Icons.more_horiz,
                          color: Colors.grey.shade500,
                          size: 18,
                        ),
                        onSelected: (value) {
                          if (value == 'delete') {
                            _deletePost(post.id);
                          } else if (value == 'report') {
                            _showPostReportDialog(post);
                          }
                        },
                        itemBuilder: (context) => [
                          if (!isOwnPost)
                            const PopupMenuItem(
                              value: 'report',
                              child: Row(
                                children: [
                                  Icon(Icons.flag_outlined, color: Colors.orange, size: 20),
                                  SizedBox(width: 12),
                                  Text('Şikayet Et'),
                                ],
                              ),
                            ),
                          if (isOwnPost)
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
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);
    
    String dateStr;
    if (dateOnly == today) {
      dateStr = 'Bugün';
    } else if (dateOnly == yesterday) {
      dateStr = 'Dün';
    } else if (date.year == now.year) {
      // Aynı yıl ise gün ve ay göster
      const aylar = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
      dateStr = '${date.day} ${aylar[date.month - 1]}';
    } else {
      // Farklı yıl ise tam tarih
      dateStr = '${date.day}.${date.month.toString().padLeft(2, '0')}.${date.year}';
    }
    
    final hour = date.hour.toString().padLeft(2, '0');
    final minute = date.minute.toString().padLeft(2, '0');
    return '$dateStr $hour:$minute';
  }
}

// Instagram tarzı story oluşturma widget'ı
class _InstagramStoryCreator extends StatefulWidget {
  final ImagePicker imagePicker;
  final Function(XFile, String) onMediaSelected;

  const _InstagramStoryCreator({
    required this.imagePicker,
    required this.onMediaSelected,
  });

  @override
  State<_InstagramStoryCreator> createState() => _InstagramStoryCreatorState();
}

class _InstagramStoryCreatorState extends State<_InstagramStoryCreator> {
  XFile? _selectedMedia;
  String? _mediaType; // 'image' veya 'video'
  bool _isUploading = false;

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: screenSize.height * 0.92,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A1A) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Üst kısım: Kapat butonu, başlık, İleri butonu
          _buildTopBar(isDark),
          // Ana alan: Önizleme veya kamera/galeri placeholder
          Expanded(
            child: _buildPreviewArea(isDark),
          ),
        ],
      ),
    );
  }

  Widget _buildTopBar(bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.black.withValues(alpha: 0.6),
            Colors.transparent,
          ],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Kapat (X) butonu
            IconButton(
              onPressed: _isUploading ? null : () => Navigator.pop(context),
              icon: const Icon(Icons.close, color: Colors.white, size: 28),
              padding: const EdgeInsets.all(12),
              constraints: const BoxConstraints(),
            ),
            // Başlık
            const Text(
              'Hikaye Oluştur',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
              ),
            ),
            // İleri butonu
            IconButton(
              onPressed: _selectedMedia != null && !_isUploading ? _onNext : null,
              icon: Icon(
                Icons.arrow_forward,
                color: _selectedMedia != null && !_isUploading
                    ? Colors.white
                    : Colors.white38,
                size: 28,
              ),
              padding: const EdgeInsets.all(12),
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPreviewArea(bool isDark) {
    if (_selectedMedia != null) {
      return _buildMediaPreview(isDark);
    }

    // Varsayılan durum: Kamera/galeri placeholder
    return Container(
      color: isDark ? const Color(0xFF2A2A2A) : const Color(0xFF1A1A2E),
      child: Stack(
        children: [
          // Arka plan gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF667eea).withValues(alpha: 0.3),
                  const Color(0xFF764ba2).withValues(alpha: 0.3),
                  const Color(0xFFf093fb).withValues(alpha: 0.2),
                ],
              ),
            ),
          ),
          // Şeffaf gradient overlay (üst kısım)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 120,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.black.withValues(alpha: 0.4),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
          // İçerik
          Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Büyük kamera ikonu
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white30, width: 2),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withValues(alpha: 0.15),
                        Colors.white.withValues(alpha: 0.05),
                      ],
                    ),
                  ),
                  child: const Icon(
                    Icons.camera_alt_outlined,
                    color: Colors.white70,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Hikaye Oluştur',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Fotoğraf veya video seçerek başla',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.7),
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 40),
                // Hızlı seçim butonları
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildQuickOption(
                      icon: Icons.photo_library_outlined,
                      label: 'Galeri',
                      onTap: () => _pickFromGallery(),
                      isDark: isDark,
                    ),
                    const SizedBox(width: 24),
                    if (!kIsWeb) ...[
                      _buildQuickOption(
                        icon: Icons.camera_alt,
                        label: 'Kamera',
                        onTap: () => _pickFromCamera(),
                        isDark: isDark,
                      ),
                      const SizedBox(width: 24),
                    ],
                    _buildQuickOption(
                      icon: Icons.videocam_outlined,
                      label: 'Video',
                      onTap: () => _pickVideo(),
                      isDark: isDark,
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Alt gradient overlay
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            height: 100,
            child: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    Colors.black.withValues(alpha: 0.3),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required bool isDark,
  }) {
    return GestureDetector(
      onTap: _isUploading ? null : onTap,
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withValues(alpha: 0.12),
              border: Border.all(color: Colors.white24, width: 1.5),
            ),
            child: Icon(
              icon,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaPreview(bool isDark) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Medya önizlemesi
        Container(
          color: Colors.black,
          child: kIsWeb
              ? _buildWebPreview()
              : _buildMobilePreview(),
        ),
        // Üst gradient overlay
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: 80,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.5),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
        // Alt gradient overlay
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
                  Colors.black.withValues(alpha: 0.5),
                ],
              ),
            ),
          ),
        ),
        // Medya türü badge'i
        Positioned(
          top: 16,
          left: 16,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white24, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  _mediaType == 'video' ? Icons.videocam : Icons.photo,
                  color: Colors.white,
                  size: 16,
                ),
                const SizedBox(width: 6),
                Text(
                  _mediaType == 'video' ? 'Video' : 'Fotoğraf',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
        // Değiştir butonu
        Positioned(
          bottom: 100,
          right: 16,
          child: GestureDetector(
            onTap: _isUploading ? null : _clearSelection,
            child: Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black54,
                border: Border.all(color: Colors.white24),
              ),
              child: const Icon(
                Icons.refresh,
                color: Colors.white,
                size: 24,
              ),
            ),
          ),
        ),
        // Yükleniyor overlay
        if (_isUploading)
          Container(
            color: Colors.black54,
            child: const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(color: Colors.white),
                  SizedBox(height: 16),
                  Text(
                    'Yükleniyor...',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildWebPreview() {
    // Web'de dosya yolu blob URL olabilir
    return FutureBuilder<Uint8List>(
      future: _selectedMedia!.readAsBytes(),
      builder: (context, snapshot) {
        if (snapshot.hasData) {
          if (_mediaType == 'video') {
            // Web'de video önizlemesi için placeholder
            return Container(
              color: Colors.black87,
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.videocam, color: Colors.white70, size: 64),
                  SizedBox(height: 16),
                  Text(
                    'Video Önizleme',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            );
          }
          return Image.memory(
            snapshot.data!,
            fit: BoxFit.contain,
          );
        }
        return const Center(
          child: CircularProgressIndicator(color: Colors.white),
        );
      },
    );
  }

  Widget _buildMobilePreview() {
    if (_mediaType == 'video') {
      // Video için küçük resim
      return Container(
        color: Colors.black87,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.play_circle_outline, color: Colors.white70, size: 80),
            SizedBox(height: 16),
            Text(
              'Video Önizleme',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );
    }
    return Image.file(
      File(_selectedMedia!.path),
      fit: BoxFit.contain,
    );
  }

  // ---- Medya seçim metodları ----

  /// Fotoğraf galerisi izni reddedildiğinde gösterilecek dialog
  void _showPhotosPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.photo_library, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Expanded(child: Text('Fotoğraf Galerisi İzni Gerekli')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CizreApp\'in fotoğraf galerinize erişmesi gerekiyor; böylece galerinizden fotoğraf seçip gönderi veya hikaye paylaşabilir, ürün fotoğraflarını mağazanıza yükleyebilir ve profil fotoğrafınızı değiştirebilirsiniz.',
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  /// Kamera izni reddedildiğinde gösterilecek dialog
  void _showCameraPermissionDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.camera_alt, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            const Expanded(child: Text('Kamera İzni Gerekli')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'CizreApp\'in kamera erişimine ihtiyacı var; böylece fotoğraf çekip profil fotoğrafınızı güncelleyebilir, gönderi ve hikaye paylaşabilir, satışa sunmak istediğiniz ürünlerin fotoğraflarını çekebilirsiniz.',
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tamam'),
          ),
        ],
      ),
    );
  }

  Future<void> _pickFromGallery() async {
    try {
      // İzin kontrolü
      final permissionService = PermissionService();
      final isGranted = await permissionService.isPhotosGranted();
      if (!isGranted) {
        if (!mounted) return;
        final result = await permissionService.checkAndRequestAllPermissions();
        final photosResult = result['photos'];
        if (photosResult != null && !photosResult.isGranted) {
          if (mounted) {
            _showPhotosPermissionDialog();
          }
          return;
        }
      }
      
      final XFile? image = await widget.imagePicker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1080,
        maxHeight: 1920,
        imageQuality: 92,
      );
      if (image != null) {
        setState(() {
          _selectedMedia = image;
          _mediaType = 'image';
        });
      }
    } catch (e) {
      debugPrint('Galeriden fotoğraf seçme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fotoğraf seçilemedi: $e')),
        );
      }
    }
  }

  Future<void> _pickFromCamera() async {
    if (kIsWeb) return; // Web'de kamera desteği yok
    try {
      // İzin kontrolü
      final permissionService = PermissionService();
      final isGranted = await permissionService.isCameraGranted();
      if (!isGranted) {
        if (!mounted) return;
        final result = await permissionService.checkAndRequestAllPermissions();
        final cameraResult = result['camera'];
        if (cameraResult != null && !cameraResult.isGranted) {
          if (mounted) {
            _showCameraPermissionDialog();
          }
          return;
        }
      }
      
      final XFile? photo = await widget.imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1080,
        maxHeight: 1920,
        imageQuality: 92,
      );
      if (photo != null) {
        setState(() {
          _selectedMedia = photo;
          _mediaType = 'image';
        });
      }
    } catch (e) {
      debugPrint('Kamera çekim hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Kamera çekimi başarısız: $e')),
        );
      }
    }
  }

  Future<void> _pickVideo() async {
    try {
      // İzin kontrolü (video seçmek için galeri izni gerekli)
      final permissionService = PermissionService();
      final isGranted = await permissionService.isPhotosGranted();
      if (!isGranted) {
        if (!mounted) return;
        final result = await permissionService.checkAndRequestAllPermissions();
        final photosResult = result['photos'];
        if (photosResult != null && !photosResult.isGranted) {
          if (mounted) {
            _showPhotosPermissionDialog();
          }
          return;
        }
      }
      
      final XFile? video = await widget.imagePicker.pickVideo(
        source: ImageSource.gallery,
        maxDuration: const Duration(seconds: 30),
      );
      if (video != null) {
        setState(() {
          _selectedMedia = video;
          _mediaType = 'video';
        });
      }
    } catch (e) {
      debugPrint('Video seçme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Video seçilemedi: $e')),
        );
      }
    }
  }

  void _clearSelection() {
    setState(() {
      _selectedMedia = null;
      _mediaType = null;
    });
  }

  Future<void> _onNext() async {
    if (_selectedMedia == null) return;

    setState(() => _isUploading = true);

    // Bottom sheet'i kapat
    Navigator.pop(context);

    // Mevcut story oluşturma akışını başlat
    widget.onMediaSelected(_selectedMedia!, _mediaType ?? 'image');
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
