// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:share_plus/share_plus.dart';
import '../../../core/models/post_model.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/widgets/settings_sidebar.dart';
import '../../../core/widgets/skeleton_loader.dart';
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
import '../../profile/screens/user_profile_screen.dart'
    hide HeartAnimationOverlay;
import '../../../core/widgets/animated_app_title.dart';
import '../../../core/services/app_about_service.dart';
import '../widgets/instagram_story_creator.dart';
import '../widgets/heart_animation_overlay.dart';
import '../widgets/post_image_carousel.dart';
import '../widgets/social_balance_badge.dart';
import '../../../kullaniciozellikler/widgets/privileged_avatar.dart';
import '../../../kullaniciozellikler/widgets/profile_privileges.dart';

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
  // Feed yüklemesi başarısız olursa kullanıcı dostu hata mesajı; null = hata yok.
  // _posts boşken bu doluysa "Henüz gönderi yok" yerine retry'lı hata durumu
  // gösterilir (ağ kopması / izin hatası vs.).
  String? _loadError;

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
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (_hasMore && !_isLoadingMore && !_isLoading) {
        _loadMorePosts();
      }
    }
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _loadError = null;
    });
    _currentPage = 0;
    _hasMore = true;

    // Önceki cache'leri temizle - stale data sorununu önlemek için
    _posts.clear();
    _userProfiles.clear();
    _likedPosts.clear();

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) setState(() => _isLoading = false);
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
            ? _postService
                  .getLikedPostIds(userId, posts.map((p) => p.id).toList())
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

      // 🐛 DEBUG BANNER KALDIRILDI - sorun çözüldü, banner'a gerek yok

      // ✅ Orphan post fix: Profil kaydı OLMAYAN yazarlar (eski user_id'ler
      //    silinmiş veya profiles'a hiç yazılmamış) için view'dan gelen
      //    author_* alanlarını _userProfiles map'ine enjekte et. Aksi halde
      //    avatar/isim/handle boş kalır ve post header'ı kaybolur.
      for (final post in posts) {
        if (post.userId.isEmpty) continue;
        if (profiles.containsKey(post.userId)) continue;
        if (!post.authorProfileExists) {
          profiles[post.userId] = {
            'id': post.userId,
            'username': post.authorUsername,
            'full_name': post.authorFullName,
            'avatar_url': post.authorAvatarUrl,
            '_orphan': true,
          };
        }
      }

      // Beğeni durumlarını işle
      final likedStatus = <String, bool>{};
      final likedPostIds = profileAndLikes[1] as Set<String>;
      for (var post in posts) {
        likedStatus[post.id] = likedPostIds.contains(post.id);
      }

      if (!mounted) return;
      setState(() {
        _posts = posts;
        _stories = otherStories;
        _userStories = userStories;
        _userProfiles = profiles;
        _likedPosts = likedStatus;
        _isLoading = false;
        _loadError = null;
        // _debugBanner zaten atandı (yukarıda) - setState rebuild tetikler
      });

      // Animasyon ayarlarını yükle
      try {
        final appAbout = await _aboutService.getAboutSettings();
        if (appAbout != null && mounted) {
          setState(() {
            _appSlogan = appAbout.appSlogan;
            _animationPrimaryDurationMs = appAbout.animationPrimaryDurationMs;
            _animationSecondaryDurationMs =
                appAbout.animationSecondaryDurationMs;
            _animationTransitionDurationMs =
                appAbout.animationTransitionDurationMs;
          });
        }
      } catch (e) {
        debugPrint('Animasyon ayarları yüklenirken hata: $e');
      }
    } catch (e, stackTrace) {
      debugPrint('❌ SocialScreen _loadData hatası: $e');
      debugPrint('Stack trace: $stackTrace');
      if (mounted) {
        // Hatayı merkezi işleyiciden kullanıcı dostu mesaja çevir:
        // ağ kopması → "İnternet bağlantınızı kontrol edin", izin hatası →
        // "yetkiniz bulunmuyor" vb. Persistent hata durumu olarak gösterilir
        // (aşağı doğru kaydırıp yenile veya "Tekrar Dene" butonu ile retry).
        // FriendlyException zaten dostane mesaj taşıdığından onu koru (üzerine
        // yazma); aksi halde handleError mesajı "Bir sorun oluştu"ya bozar.
        final friendlyMessage = e is FriendlyException
            ? e.message
            : AppErrorHandler.handleError(e, stackTrace);
        setState(() {
          _isLoading = false;
          _loadError = friendlyMessage;
        });
      }
    }
  }

  Future<void> _loadMorePosts() async {
    if (_isLoadingMore || !mounted) return;

    setState(() => _isLoadingMore = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        if (mounted) setState(() => _isLoadingMore = false);
        return;
      }

      _currentPage++;
      final offset = _currentPage * _pageSize;
      final newPosts = await _postService.getFeed(
        limit: _pageSize,
        offset: offset,
      );

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
        final likedPostIds = await _postService.getLikedPostIds(
          userId,
          postIds,
        );

        for (var post in newPosts) {
          likedStatus[post.id] = likedPostIds.contains(post.id);
        }
      }

      if (!mounted) return;
      setState(() {
        _posts.addAll(newPosts);
        _likedPosts.addAll(likedStatus);
        _hasMore = newPosts.length >= _pageSize;
        _isLoadingMore = false;
      });
    } catch (e) {
      _currentPage--; // Hata olursa sayfayı geri al
      if (mounted) {
        setState(() => _isLoadingMore = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(AppErrorHandler.handleError(e))));
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
                          child: Icon(
                            Icons.flag_rounded,
                            color: Colors.orange.shade700,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Gönderiyi Şikayet Et',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
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
                        style: TextStyle(
                          color: Colors.grey.shade700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Şikayet Nedeni',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 10),
                    ...PostReportService.reportReasons.entries.map((entry) {
                      return RadioListTile<String>(
                        value: entry.key,
                        groupValue: selectedReason,
                        onChanged: (v) =>
                            setSheetState(() => selectedReason = v),
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(
                          entry.value,
                          style: const TextStyle(fontSize: 14),
                        ),
                        activeColor: Colors.orange,
                      );
                    }),
                    const SizedBox(height: 16),
                    const Text(
                      'Açıklama (opsiyonel)',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: descriptionController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        hintText: 'Daha fazla bilgi verin...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
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
                          Icon(
                            Icons.info_outline,
                            color: Colors.amber.shade700,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Şikayetiniz ekibimiz tarafından incelenecek.',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.amber.shade900,
                              ),
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
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
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
                                    final result = await _postReportService
                                        .reportPost(
                                          reportedPostId: post.id,
                                          reason: selectedReason!,
                                          description:
                                              descriptionController.text
                                                  .trim()
                                                  .isEmpty
                                              ? null
                                              : descriptionController.text
                                                    .trim(),
                                        );
                                    if (!context.mounted) return;
                                    Navigator.pop(context);
                                    if (result == 'success') {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Şikayetiniz alındı. Teşekkürler!',
                                          ),
                                          backgroundColor: Colors.green,
                                        ),
                                      );
                                    } else if (result == 'duplicate') {
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        const SnackBar(
                                          content: Text(
                                            'Bu gönderiyi zaten şikayet etmişsiniz.',
                                          ),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                    } else {
                                      // Hata detayını göster
                                      final errorMsg = result
                                          .toString()
                                          .replaceAll('error: ', '');
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            'Şikayet gönderilemedi: $errorMsg',
                                          ),
                                          backgroundColor: Colors.red,
                                          duration: const Duration(seconds: 5),
                                        ),
                                      );
                                    }
                                  },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: isSubmitting
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
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
          likesCount: isLiked
              ? _posts[index].likesCount - 1
              : _posts[index].likesCount + 1,
        );
      }
    });

    try {
      if (isLiked) {
        await _postService.unlikePost(post.id, userId);
      } else {
        await _postService.likePost(post.id, userId);
      }

      // Başarılıysa gerçek sayıyı sunucudan al (trigger'dan güncellenmiş olacak)
      final updatedPost = await _postService.getPostById(post.id);
      if (updatedPost != null && mounted) {
        setState(() {
          final index = _posts.indexWhere((p) => p.id == post.id);
          if (index != -1) {
            _posts[index] = _posts[index].copyWith(
              likesCount: updatedPost.likesCount,
            );
          }
        });
      }
    } catch (e) {
      // Hata olursa geri al
      setState(() {
        _likedPosts[post.id] = isLiked;
        final index = _posts.indexWhere((p) => p.id == post.id);
        if (index != -1) {
          _posts[index] = _posts[index].copyWith(
            likesCount: isLiked
                ? _posts[index].likesCount + 1
                : _posts[index].likesCount - 1,
          );
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Beğeni işlemi başarısız: $e')));
      }
    }
  }

  // Kaydedilen gönderiler artık post_saves tablosunda tutuluyor (eskiden
  // SharedPreferences'taydı: uygulama silinince / cihaz değişince kayboluyordu).
  Future<void> _loadSavedPosts() async {
    try {
      // Eski sürümden kalan yerel kayıtları bir kereliğine sunucuya taşı
      await _postService.migrateLegacyLocalSaves();
      final saved = await _postService.getSavedPostIds();
      if (mounted) {
        setState(() => _savedPosts = saved);
      }
    } catch (e) {
      debugPrint('Kaydedilen gönderiler yüklenirken hata: $e');
    }
  }

  Future<void> _savePost(Post post) async {
    // Optimistik güncelleme; hata olursa geri alınır.
    final wasSaved = _savedPosts.contains(post.id);
    setState(() {
      if (wasSaved) {
        _savedPosts.remove(post.id);
      } else {
        _savedPosts.add(post.id);
      }
    });

    try {
      final isSaved = await _postService.toggleSavePost(post.id);

      if (!mounted) return;
      setState(() {
        if (isSaved) {
          _savedPosts.add(post.id);
        } else {
          _savedPosts.remove(post.id);
        }
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isSaved ? 'Gönderi kaydedildi' : 'Kayıt kaldırıldı'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      debugPrint('Gönderi kaydetme hatası: $e');
      if (!mounted) return;
      setState(() {
        if (wasSaved) {
          _savedPosts.add(post.id);
        } else {
          _savedPosts.remove(post.id);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppErrorHandler.handleError(e))),
      );
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

      final followingIds = (friendsResponse as List)
          .map((e) => e['following_id'] as String)
          .toList();

      if (followingIds.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Henüz arkadaşınız yok'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
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
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 8,
                ),
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
                    final friendName =
                        friend['full_name'] ??
                        friend['username'] ??
                        'Kullanıcı';
                    final friendAvatar = friend['avatar_url'];

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: friendAvatar != null
                            ? NetworkImage(friendAvatar)
                            : null,
                        child: friendAvatar == null
                            ? Text(
                                friendName.isNotEmpty
                                    ? friendName.substring(0, 1).toUpperCase()
                                    : '?',
                              )
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
                                    'Sohbet başlatılamadı (karşı taraf mesajları kapatmış olabilir).',
                                  ),
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
                                  borderRadius: BorderRadius.circular(12),
                                ),
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
      MaterialPageRoute(builder: (context) => PostDetailScreen(post: post)),
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
      MaterialPageRoute(builder: (context) => const CreatePostScreen()),
    );
    // Gönderi oluşturduktan sonra feed'i yenile
    _loadData();
  }

  Future<void> _sharePost(Post post) async {
    try {
      final userProfile = _userProfiles[post.userId];
      // ✅ UX FIX: Paylaşım metninde de UUID kırpıntısı göstermemek için
      //    jenerik fallback kullanıyoruz. Gerçek isim yoksa "Kullanıcı" de.
      final hasRealName =
          (userProfile?['full_name']?.toString().trim().isNotEmpty ?? false) ||
          (userProfile?['username']?.toString().trim().isNotEmpty ?? false);
      final username = hasRealName
          ? (userProfile!['full_name']?.toString().trim().isNotEmpty == true
                ? userProfile['full_name'].toString()
                : userProfile['username'].toString())
          : 'Kullanıcı';

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

      await SharePlus.instance.share(ShareParams(text: shareText.toString()));
    } catch (e) {
      debugPrint('Paylaşım hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Paylaşım yapılamadı')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primaryColor = theme.colorScheme.primary;

    return Scaffold(
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
                    decoration: const BoxDecoration(color: Color(0xFFF4F6F8)),
                    child: _isLoading
                        // Boş spinner yerine gerçek yerleşimi taklit eden
                        // iskelet kartlar: içerik "sıçramadan" yerine oturuyor.
                        ? ListView(
                            padding: const EdgeInsets.fromLTRB(12, 16, 12, 12),
                            children: [
                              Skeletons.postCard(),
                              const SizedBox(height: 12),
                              Skeletons.postCard(),
                              const SizedBox(height: 12),
                              Skeletons.postCard(),
                            ],
                          )
                        : RefreshIndicator(
                            onRefresh: _loadData,
                            color: primaryColor,
                            child: CustomScrollView(
                              controller: _scrollController,
                              // Liste boşken (veya hata durumunda) da aşağı
                              // çekerek yenileme çalışsın: varsayılan fizik
                              // içerik ekranı doldurmuyorsa kaydırmayı kapatıyor
                              // ve RefreshIndicator hiç tetiklenmiyordu.
                              physics: const AlwaysScrollableScrollPhysics(),
                              slivers: [
                                // Posts
                                _posts.isEmpty
                                    ? SliverFillRemaining(
                                        // Hata varsa (ağ/izin) retry'lı hata durumu;
                                        // yoksa gerçekten gönderi yok durumu.
                                        child: _loadError != null
                                            ? _buildErrorState(_loadError!)
                                            : _buildEmptyState(),
                                      )
                                    : SliverPadding(
                                        padding: const EdgeInsets.fromLTRB(
                                          12,
                                          14,
                                          12,
                                          0,
                                        ),
                                        sliver: SliverList(
                                          delegate: SliverChildBuilderDelegate((
                                            context,
                                            index,
                                          ) {
                                            final post = _posts[index];
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 12,
                                              ),
                                              child: _buildTwitterPostCard(post),
                                            );
                                          }, childCount: _posts.length),
                                        ),
                                      ),
                                // Loading indicator
                                if (_isLoadingMore)
                                  SliverToBoxAdapter(
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
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
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 24,
                                      ),
                                      child: Center(
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              Icons.check_circle_outline,
                                              size: 16,
                                              color: Colors.grey.shade400,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              'Hepsi bu kadar',
                                              style: TextStyle(
                                                color: Colors.grey.shade500,
                                                fontSize: 13,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                          ],
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
                child: Icon(Icons.add, color: primaryColor, size: 28),
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
                        builder: (context) => SocialBalanceBadge(),
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
                                  _unreadNotificationCount > 9
                                      ? '9+'
                                      : '$_unreadNotificationCount',
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
    // LayoutBuilder ile ekran genişliğine göre 4 item (Hikayem + 3 hikaye)
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableWidth = constraints.maxWidth;
        final storyWidth = (availableWidth - 40) / 4;

        return SizedBox(
          height: storyWidth + 32, // halka + isim + boşluk
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

  /// Hikaye halkası: dış gradyan çerçeve + beyaz iç boşluk + içerik.
  ///
  /// Beyaz iç halka (Instagram'daki gibi) eklendi; öncesinde gradyan doğrudan
  /// görselin kenarına yapışıyordu ve koyu görsellerde çerçeve kayboluyordu.
  Widget _buildStoryRing({
    required double size,
    required Widget child,
    required bool seen,
    bool pinned = false,
  }) {
    const unseenGradient = LinearGradient(
      colors: [Color(0xFF833AB4), Color(0xFFE1306C), Color(0xFFF77737)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
    const pinnedGradient = LinearGradient(
      colors: [Color(0xFFFFD700), Color(0xFFFFA500), Color(0xFFFF8C00)],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );

    final ringWidth = seen && !pinned ? 1.6 : 2.6;
    final innerSize = size - (ringWidth + 2) * 2;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: pinned
            ? pinnedGradient
            : (seen ? null : unseenGradient),
        color: !pinned && seen ? const Color(0x66FFFFFF) : null,
      ),
      padding: EdgeInsets.all(ringWidth),
      child: Container(
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white,
        ),
        padding: const EdgeInsets.all(2),
        child: ClipOval(
          child: SizedBox(
            width: innerSize,
            height: innerSize,
            child: child,
          ),
        ),
      ),
    );
  }

  /// Hikaye halkasının içindeki görsel (medya önizlemesi + video işareti).
  Widget _buildStoryThumb({
    required String imageUrl,
    required bool isVideo,
    required String? avatarUrl,
    required double size,
  }) {
    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          imageUrl: imageUrl,
          fit: BoxFit.cover,
          errorWidget: (context, url, error) => Container(
            color: Colors.grey.shade300,
            child: avatarUrl != null
                ? CachedNetworkImage(imageUrl: avatarUrl, fit: BoxFit.cover)
                : Icon(Icons.person, size: size * 0.4, color: Colors.grey),
          ),
          placeholder: (context, url) => Container(color: Colors.grey.shade200),
        ),
        if (isVideo)
          Container(
            color: Colors.black26,
            child: Center(
              child: Icon(
                Icons.play_circle_filled,
                color: Colors.white,
                size: size * 0.32,
              ),
            ),
          ),
      ],
    );
  }

  /// Hikaye başlığı (halkanın altındaki isim).
  Widget _buildStoryLabel(String text, double size) {
    return SizedBox(
      width: size,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          shadows: [Shadow(color: Color(0x66000000), blurRadius: 2)],
        ),
        textAlign: TextAlign.center,
        overflow: TextOverflow.ellipsis,
        maxLines: 1,
      ),
    );
  }

  Widget _buildMyStoryButtonDynamic(double size) {
    final username = _currentUserProfile?['username']?.toString() ?? 'Sen';
    final avatarUrl = _currentUserProfile?['avatar_url'] as String?;
    final hasStories = _userStories.isNotEmpty;
    final latestStory = hasStories ? _userStories.first : null;
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
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
              clipBehavior: Clip.none,
              children: [
                _buildStoryRing(
                  size: size,
                  seen: !hasStories,
                  child: hasStories && latestStory != null
                      ? _buildStoryThumb(
                          imageUrl: latestStory.displayUrl,
                          isVideo: latestStory.isVideo,
                          avatarUrl: avatarUrl,
                          size: size,
                        )
                      : Container(
                          color: primaryColor.withValues(alpha: 0.1),
                          child: avatarUrl != null
                              ? CachedNetworkImage(
                                  imageUrl: avatarUrl,
                                  fit: BoxFit.cover,
                                )
                              : Center(
                                  child: Text(
                                    username.isNotEmpty
                                        ? username.substring(0, 1).toUpperCase()
                                        : 'S',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: size * 0.3,
                                      color: primaryColor,
                                    ),
                                  ),
                                ),
                        ),
                ),
                // "+" rozeti: hikayem yoksa yeni hikaye eklemeye çağırır
                if (!hasStories)
                  Positioned(
                    bottom: -2,
                    right: -2,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: primaryColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Icon(
                        Icons.add,
                        size: size * 0.24,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          _buildStoryLabel(hasStories ? 'Hikayem' : 'Ekle', size),
        ],
      ),
    );
  }

  Widget _buildStoryCardDynamic(Story story, double size) {
    final userProfile = _userProfiles[story.userId];
    // ✅ UX FIX: Profil kaydı OLMAYAN eski story sahipleri için UUID kırpıntısı
    //    göstermek yerine jenerik "kullanici" fallback'i kullanıyoruz.
    final rawUsername = userProfile?['username']?.toString().trim();
    final hasRealUsername = rawUsername != null && rawUsername.isNotEmpty;
    final username = hasRealUsername ? rawUsername : 'kullanici';
    final fullName =
        (userProfile?['full_name']?.toString().trim().isNotEmpty ?? false)
        ? userProfile!['full_name'].toString()
        : username;
    final avatarUrl = userProfile?['avatar_url'] as String?;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => _viewStory(story),
            child: _buildStoryRing(
              size: size,
              seen: story.isViewedByCurrentUser,
              pinned: story.isPinned,
              child: _buildStoryThumb(
                imageUrl: story.displayUrl,
                isVideo: story.isVideo,
                avatarUrl: avatarUrl,
                size: size,
              ),
            ),
          ),
          const SizedBox(height: 5),
          _buildStoryLabel(fullName, size),
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
      builder: (context) => InstagramStoryCreator(
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
        debugPrint(
          'Story boyutu (orijinal): ${(imageBytes.length / 1024 / 1024).toStringAsFixed(2)} MB',
        );

        // Fotoğrafı yükle
        final fileName =
            'story_${userId}_${DateTime.now().millisecondsSinceEpoch}.$fileExt';
        final filePath = 'stories/$fileName';

        final uploadedMediaUrl = await StorageService().uploadBytes(
          bucket: 'stories',
          path: filePath,
          bytes: imageBytes,
          metadata: {'Content-Type': 'image/$fileExt'},
        );

        if (uploadedMediaUrl == null) {
          throw Exception('Story fotoğrafı depolamaya yüklenemedi');
        }
        mediaUrl = uploadedMediaUrl;

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
        thumbnailUrl = result['thumbnailUrl']!.isNotEmpty
            ? result['thumbnailUrl']!
            : null;
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

      // createStory null dönerse (RLS/insert hatası) "paylaşıldı" demek
      // yanıltıcı olur; hikaye listede görünmüyor ama kullanıcı başarılı sandı.
      if (newStory == null) {
        throw Exception('Hikaye kaydedilemedi, lütfen tekrar deneyin');
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mediaType == 'image'
                  ? 'Fotoğraf hikayesi paylaşıldı!'
                  : 'Video hikayesi paylaşıldı!',
            ),
          ),
        );
        // Verileri yeniden yükle
        await _loadData();
        debugPrint(
          'Veriler yenilendi, userStories count: ${_userStories.length}',
        );
      }
    } catch (e) {
      debugPrint('Story yüklenirken hata: $e');
      // Eğer progress dialog açıksa kapat
      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Story yüklenirken hata: $e')));
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
          builder: (context) =>
              StoryViewerScreen(stories: _stories, initialIndex: initialIndex),
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
          builder: (context) =>
              StoryViewerScreen(stories: _userStories, initialIndex: 0),
        ),
      );
      _loadData();
    }
  }

  Widget _buildEmptyState() {
    final primaryColor = Theme.of(context).colorScheme.primary;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: primaryColor.withValues(alpha: 0.08),
              ),
              child: Icon(
                Icons.auto_awesome_outlined,
                size: 44,
                color: primaryColor,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'Akış henüz boş',
              style: TextStyle(
                fontSize: 19,
                color: Color(0xFF11181C),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Cizre\'de olan biteni ilk paylaşan sen ol.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _createPost,
              icon: const Icon(Icons.edit_outlined, size: 18),
              label: const Text('Gönderi oluştur'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 22,
                  vertical: 13,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(24),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Feed yüklemesi başarısız olursa gösterilen hata durumu.
  /// [message] merkezi hata işleyiciden gelir (ör. "İnternet bağlantınızı
  /// kontrol edin ve tekrar deneyin"). Aşağı çekerek yenile veya "Tekrar Dene"
  /// butonuyla _loadData yeniden tetiklenir. "Henüz gönderi yok" yanıltıcılığı
  /// yerine gerçek nedeni gösterir.
  Widget _buildErrorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.wifi_off_rounded, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                color: Colors.grey.shade600,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _loadData,
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Tekrar Dene'),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Yazar rolüne göre rozet rengi
  Color _getAuthorRoleColor(AuthorRole role) {
    switch (role) {
      case AuthorRole.seller:
        return const Color(0xFFE91E63); // Pembe (Satıcı)
      case AuthorRole.courier:
        return const Color(0xFF4CAF50); // Yeşil (Kurye)
      case AuthorRole.driver:
        return const Color(0xFF2196F3); // Mavi (Sürücü)
      case AuthorRole.admin:
        return const Color(0xFF9C27B0); // Mor (Admin)
      default:
        return Colors.grey;
    }
  }

  /// Keşfet akışındaki gönderi kartı.
  ///
  /// Eski tasarım Twitter tarzı düz liste + ayırıcı çizgiydi (avatarın altına
  /// inen dikey çizgi dahil). Yeni tasarım: yumuşak gölgeli, köşeleri yuvarlak
  /// beyaz kart + hap biçimli aksiyon butonları.
  Widget _buildTwitterPostCard(Post post) {
    // ✅ Orphan post tespiti: profiles satırı olmayan yazarlar için
    //    avatar/isim/handle tamamen jenerik olur. post.authorProfileExists
    //    view'dan gelir (LEFT JOIN sonucu). user_id null/boş ise de orphan
    //    sayılır (silinmiş kullanıcı profili).
    final isOrphanPost = !post.authorProfileExists || post.userId.isEmpty;

    // ✅ Yazar bilgisi önce post modelinden alınır (view'dan geldi),
    //    fallback olarak eski _userProfiles map'i kullanılır (geriye uyumluluk)
    final userProfile = isOrphanPost ? null : _userProfiles[post.userId];
    final fullName = isOrphanPost
        ? 'Bilinmeyen Kullanıcı'
        : firstNonEmpty([
            post.authorFullName,
            userProfile?['full_name']?.toString(),
            post.authorUsername,
            userProfile?['username']?.toString(),
          ]);
    // ✅ UX FIX: Profil kaydı bulunmayan (orphan) eski yazarlar için UUID kırpıntısı
    //    (@e453djf gibi) göstermek yerine jenerik bir fallback kullanıyoruz.
    final hasRealName = isOrphanPost
        ? false
        : (post.authorFullName?.trim().isNotEmpty ?? false) ||
              (post.authorUsername?.trim().isNotEmpty ?? false) ||
              ((userProfile?['full_name']?.toString().trim().isNotEmpty ??
                  false)) ||
              ((userProfile?['username']?.toString().trim().isNotEmpty ??
                  false));
    final username = isOrphanPost
        ? 'kullanici'
        : (hasRealName
              ? (post.authorUsername ?? userProfile?['username'] ?? 'kullanici')
              : 'kullanici');
    final handle = '@$username';
    final avatarUrl = isOrphanPost
        ? null
        : (post.authorAvatarUrl ?? userProfile?['avatar_url']);
    final authorRole = isOrphanPost ? AuthorRole.unknown : post.authorRole;
    final isVerified = isOrphanPost ? false : post.authorIsVerified;
    final isLiked = _likedPosts[post.id] ?? false;
    final isSaved = _savedPosts.contains(post.id);
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isOwnPost = !isOrphanPost && post.userId == currentUserId;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      // _showComments kullanılıyor: detay ekranından "yorum eklendi/silindi"
      // sonucu dönerse feed'deki yorum sayacı da tazeleniyor.
      onTap: () => _showComments(post),
      onDoubleTap: () {
        _showLikeAnimation(context);
        if (!(_likedPosts[post.id] ?? false)) {
          _toggleLike(post);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE9EDF1)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 8, 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ---------------------------------------------------- başlık satırı
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                PrivilegedAvatar(
                  userId: post.userId,
                  username: username,
                  avatarUrl: avatarUrl,
                  radius: 22,
                  // Kullanıcı ikon/tikleri avatarın altında tekrar edilmez;
                  // paylaşım başlığında ismin yanında tek kez gösterilir.
                  showSocialPrivileges: false,
                  onTap: () => _viewUserProfile(post.userId),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _viewUserProfile(post.userId),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          spacing: 4,
                          runSpacing: 2,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              fullName,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                color: Color(0xFF11181C),
                              ),
                              softWrap: true,
                            ),
                            if (!isOrphanPost)
                              ProfilePrivilegeBadges(
                                userId: post.userId,
                                maximum: 3,
                              ),
                            // Legacy doğrulama; yeni katalog tikleri yoksa
                            // eski doğrulanmış hesap işareti korunur.
                            if (isVerified)
                              const Icon(
                                Icons.verified,
                                size: 15,
                                color: Color(0xFF1DA1F2),
                              ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Wrap(
                          spacing: 6,
                          runSpacing: 3,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text(
                              handle,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade600,
                              ),
                            ),
                            Text(
                              '\u00b7 ${_formatDate(post.createdAt)}',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: Colors.grey.shade500,
                              ),
                            ),
                            if (authorRole.isStaff)
                              _buildPostChip(
                                label: authorRole.displayLabel,
                                color: _getAuthorRoleColor(authorRole),
                              ),
                            if (post.adminPinned)
                              _buildPostChip(
                                label: 'Sabit',
                                color: Colors.amber.shade700,
                                icon: Icons.push_pin,
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  icon: Icon(
                    Icons.more_horiz,
                    color: Colors.grey.shade500,
                    size: 20,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  onSelected: (value) {
                    if (value == 'delete') {
                      _deletePost(post.id);
                    } else if (value == 'report') {
                      _showPostReportDialog(post);
                    } else if (value == 'share') {
                      _sharePost(post);
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'share',
                      child: Row(
                        children: [
                          Icon(Icons.ios_share, size: 20),
                          SizedBox(width: 12),
                          Text('Paylaş'),
                        ],
                      ),
                    ),
                    if (!isOwnPost)
                      const PopupMenuItem(
                        value: 'report',
                        child: Row(
                          children: [
                            Icon(
                              Icons.flag_outlined,
                              color: Colors.orange,
                              size: 20,
                            ),
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
                ),
              ],
            ),

            // ---------------------------------------------------------- içerik
            if (post.content != null && post.content!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 6, 8, 0),
                child: Text(
                  post.content!,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF1F2933),
                    height: 1.42,
                  ),
                  maxLines: 8,
                  overflow: TextOverflow.ellipsis,
                ),
              ),

            // --------------------------------------------------------- görsel
            if (post.images.isNotEmpty && post.images.first.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12, right: 6),
                // PostImageCarousel kendi ClipRRect'ini uyguluyor.
                child: PostImageCarousel(
                  imageUrls: post.images,
                  onTap: () => _showComments(post),
                ),
              ),

            // --------------------------------------------------------- konum
            if (post.location != null && post.location!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 10, left: 2),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      size: 15,
                      color: Colors.grey.shade500,
                    ),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        post.location!,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.grey.shade600,
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: 6),
            Divider(height: 14, color: Colors.grey.shade200),

            // -------------------------------------------------- aksiyon satırı
            Row(
              children: [
                _buildActionButton(
                  icon: isLiked ? Icons.favorite : Icons.favorite_border,
                  count: post.likesCount,
                  onTap: () => _toggleLike(post),
                  color: const Color(0xFFE0245E),
                  isActive: isLiked,
                ),
                const SizedBox(width: 4),
                _buildActionButton(
                  icon: Icons.mode_comment_outlined,
                  count: post.commentsCount,
                  onTap: () => _showComments(post),
                  color: const Color(0xFF1D9BF0),
                ),
                const SizedBox(width: 4),
                _buildActionButton(
                  icon: Icons.send_outlined,
                  count: null,
                  onTap: () => _sendToFriend(post),
                  color: const Color(0xFF17BF63),
                ),
                const Spacer(),
                _buildActionButton(
                  icon: isSaved ? Icons.bookmark : Icons.bookmark_border,
                  count: null,
                  onTap: () => _savePost(post),
                  color: const Color(0xFFF59E0B),
                  isActive: isSaved,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Başlık satırındaki küçük rozet (rol / sabitlenmiş).
  Widget _buildPostChip({
    required String label,
    required Color color,
    IconData? icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 10, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  /// Kart altındaki hap biçimli aksiyon butonu.
  /// Aktifken (beğenildi / kaydedildi) rengin açık tonu zemin olarak yanar.
  Widget _buildActionButton({
    required IconData icon,
    required int? count,
    required VoidCallback onTap,
    required Color color,
    bool isActive = false,
  }) {
    final foreground = isActive ? color : Colors.grey.shade600;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: EdgeInsets.symmetric(
            horizontal: count != null ? 10 : 8,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: isActive ? color.withValues(alpha: 0.10) : Colors.transparent,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: foreground, size: 19),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text(
                  _formatCount(count),
                  style: TextStyle(
                    color: foreground,
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// 1.2B / 3,4K gibi kısa sayaç biçimi (dört haneli sayılar kartı taşırıyordu).
  String _formatCount(int count) {
    if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    }
    if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}B';
    }
    return '$count';
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
      const aylar = [
        'Oca',
        'Şub',
        'Mar',
        'Nis',
        'May',
        'Haz',
        'Tem',
        'Ağu',
        'Eyl',
        'Eki',
        'Kas',
        'Ara',
      ];
      dateStr = '${date.day} ${aylar[date.month - 1]}';
    } else {
      // Farklı yıl ise tam tarih
      dateStr =
          '${date.day}.${date.month.toString().padLeft(2, '0')}.${date.year}';
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
