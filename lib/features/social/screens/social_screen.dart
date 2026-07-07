// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/models/post_model.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/permission_service.dart';
import '../../../core/widgets/settings_sidebar.dart';
import '../../chat/services/chat_service.dart';
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
import '../../../core/services/balance_service.dart';
import '../../../core/widgets/balance_header_widget.dart';
import '../../../core/widgets/animated_app_title.dart';
import '../../wallet/screens/wallet_screen.dart';
import '../../../core/services/app_about_service.dart';

class SocialScreen extends StatefulWidget {
  const SocialScreen({super.key});

  @override
  State<SocialScreen> createState() => _SocialScreenState();
}

class _SocialScreenState extends State<SocialScreen> {
  // Animasyon ayarları için service
  final _aboutService = AppAboutService();

  final PostService _postService = PostService();
  final StoryService _storyService = StoryService();
  final PostReportService _postReportService = PostReportService();
  final ImagePicker _imagePicker = ImagePicker();
  final NotificationService _notificationService = NotificationService();
  final ChatService _chatService = ChatService();
  late ScrollController _scrollController;

  List<Post> _posts = [];
  List<Story> _stories = [];
  List<Story> _userStories = []; // Kullanıcının kendi hikayeleri
  Map<String, bool> _likedPosts = {};
  Map<String, Map<String, dynamic>> _userProfiles = {}; // user_id -> profile
  Map<String, dynamic>? _currentUserProfile; // Mevcut kullanıcı profili
  Set<String> _savedPosts = {}; // Kaydedilen gönderiler
  int _unreadNotificationCount = 0;
  bool _isLoading = true;

  // Animasyon ayarları
  String _appSlogan = 'Her an her kapıda!';
  int _animationPrimaryDurationMs = 6000;
  int _animationSecondaryDurationMs = 3000;
  int _animationTransitionDurationMs = 700;
  
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
    
    // ⚡ iOS PERFORMANCE: Bildirim sayısını paralel yükle
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadNotificationCount().catchError((_) {});
    });
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

      // ⚡ iOS PERFORMANCE: Feed, stories ve userStories'yi PARALEL yükle
      final results = await Future.wait([
        _postService.getFeed(limit: _pageSize, offset: 0),
        _storyService.getStories(),
        _storyService.getUserStories(userId),
      ]);
      
      final posts = results[0] as List<Post>;
      final allStories = results[1] as List<Story>;
      final userStories = results[2] as List<Story>;

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

      // Kaydedilen gönderileri yükle
      await _loadSavedPosts();

      // ⚡ iOS PERFORMANCE: Profiller ve beğeni durumlarını PARALEL yükle
      final profileAndLikes = await Future.wait([
        // Profilleri yükle
        Supabase.instance.client
            .from('profiles')
            .select('id, username, full_name, avatar_url')
            .inFilter('id', userIds.toList())
            .catchError((e) {
              debugPrint('Profiller yüklenirken hata: $e');
              return <Map<String, dynamic>>[];
            }),
        // Beğeni durumlarını yükle
        posts.isNotEmpty
            ? _postService.getLikedPostIds(userId, posts.map((p) => p.id).toList())
                .catchError((e) {
                  debugPrint('Beğeni durumları yüklenirken hata: $e');
                  return <String>{};
                })
            : Future.value(<String>{}),
      ]);

      // Profilleri işle
      final profiles = <String, Map<String, dynamic>>{};
      final profilesData = profileAndLikes[0] as List;
      for (var profileData in profilesData) {
        profiles[profileData['id']] = profileData;
        if (profileData['id'] == userId) {
          _currentUserProfile = profileData;
        }
      }

      // Beğeni durumlarını işle
      final likedStatus = <String, bool>{};
      final likedPostIds = profileAndLikes[1] as Set<String>;
      for (var post in posts) {
        likedStatus[post.id] = likedPostIds.contains(post.id);
      }

      setState(() {
        _posts = posts;
        _stories = otherStories;
        _userStories = userStories;
        _userProfiles = profiles;
        _likedPosts = likedStatus;
        _isLoading = false;
      });

      // Animasyon ayarlarını yükle
      try {
        final appAbout = await _aboutService.getAboutSettings();
        if (appAbout != null && mounted) {
          setState(() {
            _appSlogan = appAbout.appSlogan;
            _animationPrimaryDurationMs = appAbout.animationPrimaryDurationMs;
            _animationSecondaryDurationMs = appAbout.animationSecondaryDurationMs;
            _animationTransitionDurationMs = appAbout.animationTransitionDurationMs;
          });
        }
      } catch (e) {
        debugPrint('Animasyon ayarları yüklenirken hata: $e');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ SocialScreen _loadData hatası: $e');
      debugPrint('Stack trace: $stackTrace');
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

  Future<void> _savePost(Post post) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedPosts = prefs.getStringList('saved_posts') ?? [];
      
      setState(() {
        if (_savedPosts.contains(post.id)) {
          _savedPosts.remove(post.id);
          savedPosts.remove(post.id);
        } else {
          _savedPosts.add(post.id);
          savedPosts.add(post.id);
        }
      });
      
      await prefs.setStringList('saved_posts', savedPosts);
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _savedPosts.contains(post.id) ? 'Gönderi kaydedildi' : 'Kayıt kaldırıldı',
            ),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      debugPrint('Gönderi kaydetme hatası: $e');
    }
  }

  Future<void> _sendToFriend(Post post) async {
    try {
      // Arkadaş listesini getir
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) return;
      
      final friendsResponse = await Supabase.instance.client
          .from('follows')
          .select('following_id')
          .eq('follower_id', currentUserId);
      
      final followingIds = (friendsResponse as List).map((e) => e['following_id'] as String).toList();
      
      if (followingIds.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Henüz arkadaşınız yok'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
        return;
      }
      
      // Arkadaşların profillerini getir
      final friendsProfiles = await Supabase.instance.client
          .from('profiles')
          .select('id, username, full_name, avatar_url')
          .inFilter('id', followingIds);
      
      if (!mounted) return;
      
      // Arkadaş seçme dialog'u göster
      await showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (context) => Container(
          height: MediaQuery.of(context).size.height * 0.6,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    const Icon(Icons.send, color: Colors.blue),
                    const SizedBox(width: 10),
                    const Text(
                      'Arkadaşına Gönder',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      onPressed: () => Navigator.pop(context),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(),
              Expanded(
                child: ListView.builder(
                  itemCount: friendsProfiles.length,
                  itemBuilder: (context, index) {
                    final friend = friendsProfiles[index];
                    final friendName = friend['full_name'] ?? friend['username'] ?? 'Kullanıcı';
                    final friendAvatar = friend['avatar_url'];
                    
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: friendAvatar != null ? NetworkImage(friendAvatar) : null,
                        child: friendAvatar == null
                            ? Text(friendName.isNotEmpty ? friendName.substring(0, 1).toUpperCase() : '?')
                            : null,
                      ),
                      title: Text(friendName),
                      subtitle: Text('@${friend['username'] ?? ''}'),
                      onTap: () async {
                        Navigator.pop(context);
                        // PROJE_HAVIZA notu: conversations tablosu şu kolonlara
                        // sahiptir -> user_id, other_user_id, last_message,
                        // last_message_time, unread_count. Eski kod user1_id/
                        // user2_id/last_message_sender_id/last_message_at
                        // kullanıyordu; bu kolonlar tabloda yoktu ve
                        // "Gönderilemedi" hatasına yol açıyordu. Çözüm:
                        // ChatService.getOrCreateConversation + sendSharedPost
                        // kullan (chat_service.dart zaten doğru şemayı biliyor).
                        try {
                          final otherUserId = friend['id'] as String;
                          final postImageUrl = post.images.isNotEmpty
                              ? post.images.first
                              : null;

                          // Mevcut conversation'ı al veya oluştur
                          final conversation = await _chatService
                              .getOrCreateConversation(otherUserId);
                          if (conversation == null) {
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text(
                                      'Sohbet başlatılamadı (karşı taraf mesajları kapatmış olabilir).'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                            }
                            return;
                          }

                          // Gönderiyi mesaj olarak yolla (SHARED_POST:... formatı).
                          // sendSharedPost sender_id'yi auth.currentUser'dan alır;
                          // authorName için profil sorgusu gerekir, burada null
                          // geçmek ChatService'in profile fallback'ini tetikler.
                          final sent = await _chatService.sendSharedPost(
                            conversationId: conversation.id,
                            postId: post.id,
                            postContent: post.content ?? '',
                            postImageUrl: postImageUrl,
                            authorName: null,
                          );

                          if (sent != null && mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('$friendName\'e gönderildi!'),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            );
                          } else if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Gönderilemedi'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        } catch (e) {
                          debugPrint('Mesaj gönderme hatası: $e');
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Bir hata oluştu: $e'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
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
      debugPrint('Arkadaşlara gönder hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Bir hata oluştu: $e'),
            behavior: SnackBarBehavior.floating,
          ),
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
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              AnimatedAppTitle.fromSettings(
                primaryText: 'CizreApp',
                secondaryText: _appSlogan,
                primaryDurationMs: _animationPrimaryDurationMs,
                secondaryDurationMs: _animationSecondaryDurationMs,
                transitionDurationMs: _animationTransitionDurationMs,
                primaryFontSize: 24,
                secondaryFontSize: 14,
                onTap: () {
                  // Sayfayı en üste scroll et
                  _scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                  );
                },
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // BAKİYE - İKONLARLA AYNI BOYUT VE HİZADA
                  SizedBox(
                    height: 30,
                    child: Center(
                      child: Builder(
                        builder: (context) => _SocialBalanceBadge(),
                      ),
                    ),
                  ),
                  // Arama ikonu
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: IconButton(
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
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      splashRadius: 18,
                      constraints: const BoxConstraints(),
                    ),
                  ),
                  // Bildirim ikonu
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: GestureDetector(
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
                      child: Stack(
                        clipBehavior: Clip.none,
                        alignment: Alignment.center,
                        children: [
                          const Icon(
                            Icons.notifications_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
                          // Bildirim badge'i
                          if (_unreadNotificationCount > 0)
                            Positioned(
                              top: -1,
                              right: -1,
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
                  // Ayarlar ikonu
                  SizedBox(
                    width: 30,
                    height: 30,
                    child: IconButton(
                      onPressed: () {
                        showSettingsSidebar(context);
                      },
                      icon: const Icon(
                        Icons.settings_outlined,
                        color: Colors.white,
                        size: 20,
                      ),
                      padding: EdgeInsets.zero,
                      splashRadius: 18,
                      constraints: const BoxConstraints(),
                    ),
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
                                CachedNetworkImage(
                                  imageUrl: latestStory.displayUrl,
                                  width: size - 4,
                                  height: size - 4,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) {
                                    return Container(
                                      width: size - 4,
                                      height: size - 4,
                                      color: Colors.grey.shade300,
                                      child: avatarUrl != null
                                          ? CachedNetworkImage(imageUrl: avatarUrl, fit: BoxFit.cover)
                                          : Icon(Icons.person, size: size * 0.4, color: Colors.grey),
                                    );
                                  },
                                  placeholder: (context, url) {
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
                                  ? CachedNetworkImage(imageUrl: avatarUrl, fit: BoxFit.cover)
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
          // Story circle - çemberli (sabitlenmişse altın rengi çember)
          GestureDetector(
            onTap: () => _viewStory(story),
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: story.isPinned
                    ? const LinearGradient( // Sabitlendiyse altın rengi
                        colors: [Color(0xFFFFD700), Color(0xFFFFA500), Color(0xFFFF8C00)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      )
                    : story.isViewedByCurrentUser
                        ? null // İzlendiyse gradient yok (gri)
                        : const LinearGradient( // İzlenmediyse renkli gradient
                            colors: [Colors.purple, Colors.pink, Colors.orange],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                color: !story.isPinned && story.isViewedByCurrentUser
                    ? Colors.grey.shade300 // İzlendiyse gri
                    : null,
              ),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: ClipOval(
                  child: Stack(
                    children: [
                      // Story içerik önizlemesi - displayUrl kullanıyoruz (thumbnail varsa onu gösterir)
                      CachedNetworkImage(
                        imageUrl: story.displayUrl,
                        width: size - 4,
                        height: size - 4,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) {
                          return Container(
                            width: size - 4,
                            height: size - 4,
                            color: Colors.grey.shade300,
                            child: avatarUrl != null
                                ? CachedNetworkImage(imageUrl: avatarUrl, fit: BoxFit.cover)
                                : Icon(Icons.person, size: size * 0.4, color: Colors.grey),
                          );
                        },
                        placeholder: (context, url) {
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

        // Fotoğrafı ORİJİNAL boyutuyla yükle (yeniden boyutlandırma/sıkıştırma yok).
        // Kullanıcı isteği: görsel hangi boyuttaysa olduğu gibi paylaşılsın.
        debugPrint('Story fotoğrafı orijinal boyutuyla işleniyor...');

        final Uint8List imageBytes = await media.readAsBytes();
        final String fileExt = media.name.split('.').last.toLowerCase();
        debugPrint('Story boyutu (orijinal): ${(imageBytes.length / 1024 / 1024).toStringAsFixed(2)} MB');

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
      onDoubleTap: () {
        _showLikeAnimation(context);
        if (!(_likedPosts[post.id] ?? false)) {
          _toggleLike(post);
        }
      },
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
                  // User info row - Sadece isim
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // İsim - Tıklanabilir
                      Expanded(
                        child: GestureDetector(
                          onTap: () => _viewUserProfile(post.userId),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      fullName,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 15,
                                        color: Colors.black87,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                    ),
                                  ),
                                  if (post.adminPinned) ...[
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 5,
                                        vertical: 1,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.amber.shade700,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: const Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.push_pin,
                                            size: 9,
                                            color: Colors.white,
                                          ),
                                          SizedBox(width: 2),
                                          Text(
                                            'Sabit',
                                            style: TextStyle(
                                              color: Colors.white,
                                              fontSize: 8,
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
                                overflow: TextOverflow.ellipsis,
                                maxLines: 1,
                              ),
                            ],
                          ),
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
                      maxLines: 8,
                      overflow: TextOverflow.ellipsis,
                    ),

                  const SizedBox(height: 8),

                  // Post image - sadece geçerli URL varsa göster.
                  // Çoklu görselde yatay swipe carousel + nokta indikatör (Instagram tarzı).
                  if (post.images.isNotEmpty && post.images.first.isNotEmpty)
                    _PostImageCarousel(
                      imageUrls: post.images,
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PostDetailScreen(post: post),
                        ),
                      ),
                    ),

                  // Location
                  if (post.location != null) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.location_on, size: 14, color: Colors.grey.shade500),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            post.location!,
                            style: TextStyle(
                              fontSize: 13,
                              color: Colors.grey.shade500,
                            ),
                            overflow: TextOverflow.ellipsis,
                            maxLines: 1,
                          ),
                        ),
                      ],
                    ),
                  ],

                  const SizedBox(height: 12),

                  // Tarih - İçerik ile aksiyon butonları arasında
                  Text(
                    _formatDate(post.createdAt),
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade500,
                    ),
                  ),

                  const SizedBox(height: 8),

                  // Action buttons
                  Container(
                    constraints: const BoxConstraints(maxWidth: 500),
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

                        // Arkadaşa Gönder
                        _buildActionButton(
                          icon: Icons.send,
                          count: null,
                          onTap: () => _sendToFriend(post),
                          color: Colors.blue.shade400,
                        ),

                        // Like
                        _buildActionButton(
                          icon: isLiked ? Icons.favorite : Icons.favorite_border,
                          count: post.likesCount,
                          onTap: () => _toggleLike(post),
                          color: Colors.red,
                          isActive: isLiked,
                        ),

                        // Kaydet
                        _buildActionButton(
                          icon: _savedPosts.contains(post.id) ? Icons.bookmark : Icons.bookmark_border,
                          count: null,
                          onTap: () => _savePost(post),
                          color: _savedPosts.contains(post.id) ? Colors.orange : Colors.grey.shade600,
                          isActive: _savedPosts.contains(post.id),
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

  /// Instagram tarzı animasyonlu kalp efekti göster
  void _showLikeAnimation(BuildContext context) {
    final overlay = Overlay.of(context);
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final size = renderBox.size;
    
    // Kalp ikonu overlay'i oluştur
    final entry = OverlayEntry(
      builder: (context) => _HeartAnimationOverlay(
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
  VideoPlayerController? _videoController;

  @override
  void dispose() {
    _videoController?.dispose();
    super.dispose();
  }

  /// Seçilen video için oynatıcıyı hazırla (gerçek önizleme).
  Future<void> _initVideoController(XFile file) async {
    // Önceki controller'ı temizle
    final old = _videoController;
    _videoController = null;
    if (mounted) setState(() {});
    await old?.dispose();

    try {
      final controller = kIsWeb
          ? VideoPlayerController.networkUrl(Uri.parse(file.path))
          : VideoPlayerController.file(File(file.path));
      await controller.initialize();
      await controller.setLooping(true);
      await controller.play();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _videoController = controller);
    } catch (e) {
      debugPrint('Video önizleme başlatılamadı: $e');
    }
  }

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
            return _buildVideoPreview();
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
      return _buildVideoPreview();
    }
    return Image.file(
      File(_selectedMedia!.path),
      fit: BoxFit.contain,
    );
  }

  /// Seçilen videonun gerçek oynatılan önizlemesi (dokununca duraklat/oynat).
  Widget _buildVideoPreview() {
    final controller = _videoController;
    if (controller == null || !controller.value.isInitialized) {
      return Container(
        color: Colors.black87,
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(color: Colors.white70),
              SizedBox(height: 16),
              Text(
                'Video hazırlanıyor...',
                style: TextStyle(color: Colors.white70, fontSize: 15),
              ),
            ],
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: () {
        setState(() {
          controller.value.isPlaying ? controller.pause() : controller.play();
        });
      },
      child: Container(
        color: Colors.black,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Center(
              child: AspectRatio(
                aspectRatio: controller.value.aspectRatio,
                child: VideoPlayer(controller),
              ),
            ),
            // İlerleme çubuğu
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: VideoProgressIndicator(
                controller,
                allowScrubbing: true,
                colors: const VideoProgressColors(
                  playedColor: Colors.white,
                  bufferedColor: Colors.white30,
                  backgroundColor: Colors.white12,
                ),
              ),
            ),
            // Duraklatıldığında oynat ikonu
            if (!controller.value.isPlaying)
              Container(
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                padding: const EdgeInsets.all(12),
                child: const Icon(Icons.play_arrow,
                    color: Colors.white, size: 48),
              ),
          ],
        ),
      ),
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
      
      // Orijinal boyut korunsun: maxWidth/maxHeight/imageQuality verilmiyor.
      final XFile? image = await widget.imagePicker.pickImage(
        source: ImageSource.gallery,
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
      
      // Orijinal boyut korunsun: maxWidth/maxHeight/imageQuality verilmiyor.
      final XFile? photo = await widget.imagePicker.pickImage(
        source: ImageSource.camera,
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
        // Gerçek video önizlemesini başlat
        _initVideoController(video);
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
    final old = _videoController;
    _videoController = null;
    old?.dispose();
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
      builder: (context) => _HeartAnimationOverlay(
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

/// Instagram tarzı animasyonlu kalp efekti widget'ı
class _HeartAnimationOverlay extends StatefulWidget {
  final Size parentSize;

  const _HeartAnimationOverlay({
    super.key,
    required this.parentSize,
  });

  @override
  State<_HeartAnimationOverlay> createState() => _HeartAnimationOverlayState();
}

class _HeartAnimationOverlayState extends State<_HeartAnimationOverlay>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    
    _controller = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );

    // Ölçek animasyonu: 0 -> 1.2 -> 1.0
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.3)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.3, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 70,
      ),
    ]).animate(_controller);

    // Opaklık animasyonu: 1 -> 0
    _opacityAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0),
        weight: 20,
      ),
      TweenSequenceItem(
        tween: ConstantTween(1.0),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 30,
      ),
    ]).animate(_controller);

    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: Center(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Transform.scale(
                scale: _scaleAnimation.value,
                child: Opacity(
                  opacity: _opacityAnimation.value,
                  child: Container(
                    width: 120,
                    height: 120,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.9),
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.2),
                          blurRadius: 20,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                    child: const Center(
                      child: Icon(
                        Icons.favorite,
                        color: Colors.red,
                        size: 60,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// Çoklu görsel için yatay swipe carousel + nokta indikatör (Instagram tarzı).
/// Keşfet feed kartında post.images listesini gezilebilir şekilde gösterir.
/// Tek görselde carousel/nokta gösterilmez (eski tek-görsel davranışı korunur).
class _PostImageCarousel extends StatefulWidget {
  final List<String> imageUrls;
  final VoidCallback? onTap;

  const _PostImageCarousel({required this.imageUrls, this.onTap});

  @override
  State<_PostImageCarousel> createState() => _PostImageCarouselState();
}

class _PostImageCarouselState extends State<_PostImageCarousel> {
  late PageController _pageController;
  int _currentIndex = 0;

  @override
  void initState() {
    super.initState();
    _pageController = PageController();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final images = widget.imageUrls.where((u) => u.isNotEmpty).toList();
    if (images.isEmpty) return const SizedBox.shrink();

    final isSingle = images.length == 1;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(
        children: [
          // PageView: tek görselde swipe'a gerek yok ama tutarlı render için kullanılır.
          SizedBox(
            height: 200,
            child: PageView.builder(
              controller: _pageController,
              physics: isSingle
                  ? const NeverScrollableScrollPhysics() // tek görselde swipe kapalı
                  : const PageScrollPhysics(),
              itemCount: images.length,
              onPageChanged: (index) {
                setState(() => _currentIndex = index);
              },
              itemBuilder: (context, index) {
                return GestureDetector(
                  onTap: widget.onTap,
                  child: CachedNetworkImage(
                    imageUrl: images[index],
                    width: double.infinity,
                    height: 200,
                    fit: BoxFit.cover,
                    errorWidget: (context, url, error) {
                      // Görsel yüklenemezse gri placeholder
                      return Container(
                        width: double.infinity,
                        height: 200,
                        color: Colors.grey.shade200,
                        child: const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.grey,
                          size: 40,
                        ),
                      );
                    },
                    placeholder: (context, url) {
                      return Container(
                        width: double.infinity,
                        height: 200,
                        color: Colors.grey.shade100,
                        child: const Center(
                          child: SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
          // Çoklu görsel göstergesi (sağ üst) - "1/N"
          if (!isSingle)
            Positioned(
              top: 8,
              right: 8,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.photo_library, color: Colors.white, size: 14),
                    const SizedBox(width: 4),
                    Text(
                      '${_currentIndex + 1}/${images.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Nokta indikatörleri (alt orta) - Instagram tarzı
          if (!isSingle)
            Positioned(
              bottom: 8,
              left: 0,
              right: 0,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(images.length, (index) {
                  final isActive = index == _currentIndex;
                  return AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    width: isActive ? 8 : 6,
                    height: isActive ? 8 : 6,
                    decoration: BoxDecoration(
                      color: isActive ? Colors.white : Colors.white.withOpacity(0.5),
                      shape: BoxShape.circle,
                    ),
                  );
                }),
              ),
            ),
        ],
      ),
    );
  }
}

// Sosyal ekran için bakiye badge
class _SocialBalanceBadge extends StatefulWidget {
  const _SocialBalanceBadge();

  @override
  State<_SocialBalanceBadge> createState() => _SocialBalanceBadgeState();
}

class _SocialBalanceBadgeState extends State<_SocialBalanceBadge> {
  final BalanceService _balanceService = BalanceService();
  double? _balance;
  bool _isLoading = true;
  bool _showBalance = true;

  @override
  void initState() {
    super.initState();
    _checkShowBalance();
  }

  Future<void> _checkShowBalance() async {
    try {
      final shouldShow = await BalanceHeaderWidget.getShowBalance();
      if (mounted) {
        setState(() => _showBalance = shouldShow);
        if (shouldShow) {
          _loadBalance();
        } else {
          setState(() => _isLoading = false);
        }
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadBalance() async {
    try {
      final balance = await _balanceService.getBalance();
      if (mounted) {
        setState(() {
          _balance = balance?.availableBalance ?? 0;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _navigateToWallet() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const WalletScreen()),
    ).then((_) => _loadBalance());
  }

  @override
  Widget build(BuildContext context) {
    if (!_showBalance) return const SizedBox.shrink();

    if (_isLoading) {
      return const SizedBox(
        width: 14,
        height: 14,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.white,
        ),
      );
    }

    return GestureDetector(
      onTap: _navigateToWallet,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          '₺${(_balance ?? 0).toStringAsFixed(2)}',
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}
