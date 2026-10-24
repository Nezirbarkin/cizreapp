// ignore_for_file: deprecated_member_use, use_build_context_synchronously

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../core/models/post_model.dart';
import '../../../core/services/notification_service.dart';
import '../../../core/services/storage_service.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/utils/image_url.dart';
import '../../../core/widgets/settings_sidebar.dart';
import '../../../core/widgets/skeleton_loader.dart';
import '../../../core/widgets/text_background.dart';
import '../../chat/services/chat_service.dart';
import '../services/post_service.dart';
import '../services/story_service.dart';
import '../services/post_report_service.dart';
import '../services/social_share_service.dart';
import '../../market/screens/search_screen.dart';
import '../../market/screens/notifications_screen.dart';
import '../../../core/models/live_shopping_model.dart';
import '../../market/screens/live_host_screen.dart';
import '../../market/screens/live_viewer_screen.dart';
import '../../market/services/live_shopping_service.dart';
import '../../market/widgets/live_stream_widgets.dart' show kLiveRed, LiveShopAvatar;
import 'create_post_screen.dart';
import 'post_detail_screen.dart';
import 'story_viewers_screen.dart';
import 'story_viewer_screen.dart';
import '../../profile/screens/user_profile_screen.dart';
import '../../profile/services/profile_service.dart';
import '../../../core/widgets/animated_app_title.dart';
import '../../../core/services/app_about_service.dart';
import '../widgets/instagram_story_creator.dart';
import '../widgets/social_balance_badge.dart';
import '../widgets/social_post_card.dart';
import '../widgets/impression_probe.dart';
import '../widgets/post_insights_sheet.dart';
import '../widgets/edit_post_sheet.dart';
import '../services/post_impression_tracker.dart';
import '../services/muted_users_service.dart';
import 'hashtag_feed_screen.dart';
import '../../music/music.dart';
import '../../../kullaniciozellikler/services/profile_feature_service.dart';

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
  StreamSubscription<String>? _blockedSub;
  StreamSubscription<String>? _mutedSub;
  // Bu oturumda gizlenen gönderiler: kart yerinde "Gizlendi · Geri al".
  final Map<String, String> _hiddenPosts = {};

  List<Post> _posts = [];
  List<Story> _stories = [];
  List<Story> _userStories = []; // Kullanıcının kendi hikayeleri

  /// Hikaye şeridinin başında gösterilen şu an canlı yayınlar (kullanıcı ve
  /// mağaza; gizlilik sunucuda süzülür). Dakikada bir tazelenir.
  final LiveShoppingService _liveService = LiveShoppingService();
  List<LiveSession> _liveSessions = [];
  Timer? _liveTimer;
  // Sekme görünür mü (MainScreen IndexedStack'te arkadaysa TickerMode kapalı).
  bool _tabActive = true;
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

  /// Misafir (giriş yapmamış) modda mıyız? Bu mod yalnız admin ayarı
  /// `explore_public_access` açıkken devreye girer; akış salt okunurdur ve
  /// veriler `public_explore_feed()` RPC'sinden gelir (misafirin `profiles`
  /// tablosuna SELECT yetkisi olmadığı için normal feed yolu kullanılamaz).
  bool _isGuest = false;

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

  /// Her tam yüklemede (ilk açılış, aşağı çekip yenileme) artar. Uçuştaki bir
  /// "daha fazla" isteği döndüğünde nesil değişmişse sonucu atılır: eskiden
  /// yenileme sırasında biten eski sayfa yeni listeye ekleniyor, sayfa sayacı
  /// karışıp aynı sayfa ikinci kez yükleniyordu.
  int _feedGeneration = 0;

  /// Sürmekte olan beğeni / kaydetme istekleri (gönderi id'si). Çift dokunuşta
  /// ikinci istek gitmez; art arda giden ekle/sil istekleri sırasız varıp
  /// kalbi sunucudan farklı bırakıyordu.
  final Set<String> _likeInFlight = {};
  final Set<String> _saveInFlight = {};

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController()..addListener(_onScroll);
    _blockedSub = ProfileService.onUserBlocked.listen(_onUserBlocked);
    _mutedSub = MutedUsersService.onUserMuted.listen(_onUserBlocked);
    _loadData();
    // Dakikalık yoklama yalnız sekme görünür ve uygulama ön plandayken:
    // eskiden gizli sekmede / arka planda da ağa gidip tüm ekranı çiziyordu.
    _liveTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      final resumed = WidgetsBinding.instance.lifecycleState ==
          AppLifecycleState.resumed;
      if (_tabActive && resumed) _loadLive();
    });

    // ⚡ iOS PERFORMANCE: Bildirim sayısını paralel yükle
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadNotificationCount().catchError((_) {});
    });
  }

  @override
  void dispose() {
    _liveTimer?.cancel();
    _blockedSub?.cancel();
    _mutedSub?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  /// Şu an canlı yayınlar (kendi yayınım hariç). Hata sessiz: şerit eski
  /// listeyle kalır.
  Future<void> _loadLive() async {
    try {
      final feed = await _liveService.fetchFeed(limit: 20);
      if (!mounted) return;
      final me = _liveService.currentUserId;
      final next = feed.live.where((s) => s.hostUserId != me).toList();
      // Liste aynıysa yeniden çizme (2500 satırlık ekran her dakika çiziliyordu).
      final same = next.length == _liveSessions.length &&
          [for (var i = 0; i < next.length; i++) next[i].id == _liveSessions[i].id]
              .every((x) => x);
      if (same) return;
      setState(() => _liveSessions = next);
    } catch (e) {
      debugPrint('Sosyal canlı yayın şeridi: $e');
    }
  }

  void _openLive(LiveSession session) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LiveViewerScreen(session: session)),
    ).then((_) => _loadLive());
  }

  /// Hikaye oluşturucudaki "Canlı": sayfayı kapatıp yayıncı ekranını açar.
  void _goLive(BuildContext sheetContext) {
    Navigator.pop(sheetContext);
    final name = _currentUserProfile?['username']?.toString() ?? '';
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => LiveHostScreen(shopName: name)),
    ).then((_) => _loadLive());
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      if (_hasMore && !_isLoadingMore && !_isLoading) {
        _loadMorePosts();
      }
    }
  }

  /// Akışı baştan yükler. [silent] (aşağı çekip yenileme, gönderi paylaşma
  /// dönüşü): eldeki liste iskelete dönmeden yerinde kalır, yeni sonuç gelince
  /// değiştirilir — eskiden her yenileme listeyi silip kaydırmayı başa alıyordu.
  Future<void> _loadData({bool silent = false}) async {
    if (!mounted) return;
    final generation = ++_feedGeneration;
    final showSkeleton = !silent || _posts.isEmpty;
    setState(() {
      if (showSkeleton) _isLoading = true;
      _isLoadingMore = false;
      _loadError = null;
    });
    unawaited(_loadLive());

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        await _loadGuestFeed(generation: generation);
        return;
      }
      if (_isGuest && mounted) setState(() => _isGuest = false);

      // Kaydedilenler akıştan bağımsız: akışla AYNI ANDA başlar (eskiden
      // akış geldikten sonra ayrı bir ağ turu bekleniyordu). Hatayı kendi
      // yutar; ilk çizimden önce aşağıda beklenir.
      final savedPostsLoad = _loadSavedPosts();
      // Sessize alınanlar (oturumda bir kez; hikâye şeridini süzmek için).
      final mutedLoad = MutedUsersService.instance.ensureLoaded();

      // ⚡ iOS PERFORMANCE: Feed, stories ve userStories'yi PARALEL yükle.
      // Hikâyeler akıştan bağımsız: hikâye tarafındaki bir hata (bozuk satır,
      // ağ) artık gönderi akışını da boş/hatalı göstermez, şerit boş kalır.
      final results = await Future.wait([
        _postService.getFeed(limit: _pageSize, offset: 0),
        // Sessiz yenilemede (aşağı çekme) paylaşılan sonuç atlanır.
        _storyService.getStories(forceRefresh: silent).catchError((Object e) {
          debugPrint('Hikayeler yüklenemedi: $e');
          return <Story>[];
        }),
        _storyService.getUserStories(userId).catchError((Object e) {
          debugPrint('Kendi hikayelerim yüklenemedi: $e');
          return <Story>[];
        }),
      ]);
      if (generation != _feedGeneration) return;

      final posts = _dedupeById(results[0] as List<Post>);
      await mutedLoad;
      final allStories = MutedUsersService.instance
          .filterStories(results[1] as List<Story>, (s) => s.userId);
      final userStories = results[2] as List<Story>;

      // HasMore kontrolü - eğer dönen veri pageSize'dan azsa, başka sayfa yok
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

      // Kartların avatar efekti/rozetleri için yazar başına ayrı RPC yerine
      // tek istek. Beklenmez: kartlar sonucu kendileri bekler.
      unawaited(
        ProfileFeatureService().prefetchUserFeatures(
          posts.map((p) => p.userId),
        ),
      );

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
      await savedPostsLoad;

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

      if (!mounted || generation != _feedGeneration) return;
      setState(() {
        _posts = posts;
        _stories = otherStories;
        _userStories = userStories;
        _userProfiles = profiles;
        _likedPosts = likedStatus;
        _currentPage = 0;
        _hasMore = posts.length >= _pageSize;
        _isLoading = false;
        _loadError = null;
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
      if (mounted && generation == _feedGeneration) {
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
        // Ekranda eski liste duruyorsa (sessiz yenileme) hata durumu
        // görünmez; kullanıcıya kısa bir uyarı yeter.
        if (_posts.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(friendlyMessage)),
          );
        }
      }
    }
  }

  /// Aynı gönderi iki sayfada gelirse (sayfalar arasında yeni gönderi
  /// paylaşılınca kayan ofset) bir kez gösterilir.
  List<Post> _dedupeById(Iterable<Post> posts, {Set<String>? existing}) {
    final seen = <String>{...?existing};
    return [
      for (final post in posts)
        if (seen.add(post.id)) post,
    ];
  }

  /// Yalnız hikâye şeridini tazeler (hikâye izleme/paylaşma dönüşü). Eskiden
  /// bunun için tüm akış iskelete dönüp baştan yükleniyordu.
  Future<void> _refreshStories() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || _isGuest) return;
    try {
      final results = await Future.wait([
        _storyService.getStories(forceRefresh: true),
        _storyService.getUserStories(userId),
      ]);
      final others = results[0].where((s) => s.userId != userId).toList();

      // Şeride yeni giren yazarların adı/avatarı (halka etiketi bunlardan).
      final missing = {
        for (final s in others)
          if (!_userProfiles.containsKey(s.userId)) s.userId,
      };
      final fetched = missing.isEmpty
          ? const <Map<String, dynamic>>[]
          : await Supabase.instance.client
              .from('profiles')
              .select('id, username, full_name, avatar_url')
              .inFilter('id', missing.toList());

      if (!mounted) return;
      setState(() {
        for (final p in fetched) {
          _userProfiles[p['id'] as String] = p;
        }
        _stories = others;
        _userStories = results[1];
      });
    } catch (e) {
      debugPrint('Hikaye şeridi tazelenemedi: $e');
    }
  }

  /// Misafir akışı. `public_explore_feed()` RPC'si sunucu tarafında
  /// `explore_public_access` ayarını kontrol eder: ayar kapalıysa BOŞ liste
  /// döner. Yani istemciyi kurcalamak kapalı bir Keşfet'i açmaz.
  Future<void> _loadGuestFeed({int page = 0, required int generation}) async {
    try {
      final rows = await Supabase.instance.client.rpc<List<dynamic>>(
        'public_explore_feed',
        params: {'p_limit': _pageSize, 'p_offset': page * _pageSize},
      );
      if (generation != _feedGeneration) return;

      final fetched = rows
          .map((e) => Post.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      final posts = _dedupeById(
        fetched,
        existing: page == 0 ? null : {for (final p in _posts) p.id},
      );
      unawaited(
        ProfileFeatureService().prefetchUserFeatures(
          posts.map((p) => p.userId),
        ),
      );

      // Misafirde yazar bilgisi doğrudan RPC satırından gelir; ayrı bir
      // profiles sorgusu yapılmaz (misafirin o tabloda SELECT yetkisi yok).
      final profiles = <String, Map<String, dynamic>>{};
      for (final post in posts) {
        profiles[post.userId] = {
          'id': post.userId,
          'username': post.authorUsername,
          'full_name': post.authorFullName,
          'avatar_url': post.authorAvatarUrl,
        };
      }

      if (!mounted) return;
      setState(() {
        _isGuest = true;
        if (page == 0) {
          _posts = posts;
          _userProfiles = profiles;
        } else {
          _posts.addAll(posts);
          _userProfiles.addAll(profiles);
        }
        _stories = [];
        _userStories = [];
        _likedPosts = {};
        _savedPosts = {};
        _hasMore = fetched.length >= _pageSize;
        _currentPage = page;
        _isLoading = false;
        _isLoadingMore = false;
        _loadError = null;
      });
    } catch (e) {
      debugPrint('❌ Misafir keşfet akışı yüklenemedi: $e');
      if (!mounted || generation != _feedGeneration) return;
      setState(() {
        _isGuest = true;
        _isLoading = false;
        _isLoadingMore = false;
        _loadError = 'Keşfet şu anda yüklenemedi. Lütfen tekrar deneyin.';
      });
    }
  }

  /// Misafirin etkileşim denemelerinde giriş ekranına yönlendiren tek kapı.
  /// true dönerse çağıran işleme devam ETMEMELİDİR.
  bool _blockGuest() {
    if (!_isGuest) return false;
    // Snackbar kök ScaffoldMessenger'da yaşar; "Giriş Yap"a bu ekran
    // kapandıktan sonra da basılabilir. O anda State.context ölüdür ve
    // `Navigator.of(context)` release'te "Null check operator used on a null
    // value" veriyordu (admin Loglar) — Navigator burada yakalanır.
    final navigator = Navigator.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Bu özellik için giriş yapmalısınız'),
        action: SnackBarAction(
          label: 'Giriş Yap',
          onPressed: () {
            if (navigator.mounted) navigator.pushNamed('/login');
          },
        ),
        duration: const Duration(seconds: 4),
      ),
    );
    return true;
  }

  Future<void> _loadMorePosts() async {
    if (_isLoadingMore || !mounted) return;

    final generation = _feedGeneration;
    final nextPage = _currentPage + 1;
    setState(() => _isLoadingMore = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        await _loadGuestFeed(page: nextPage, generation: generation);
        return;
      }

      final fetched = await _postService.getFeed(
        limit: _pageSize,
        offset: nextPage * _pageSize,
      );
      // Bu arada liste yenilendiyse bu sayfa eski listeye aittir: at.
      if (generation != _feedGeneration) return;
      final newPosts = _dedupeById(
        fetched,
        existing: {for (final p in _posts) p.id},
      );

      // Yeni profilleri yükle
      final userIds = <String>{};
      for (var post in newPosts) {
        userIds.add(post.userId);
      }
      unawaited(ProfileFeatureService().prefetchUserFeatures(userIds));

      // Profiller ve beğeni durumları birbirinden bağımsız: paralel yükle
      // (eskiden art arda iki ağ turu bekleniyordu).
      Future<void> loadProfiles() async {
        if (userIds.isEmpty) return;
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

      Future<Set<String>> loadLikes() async {
        if (newPosts.isEmpty) return <String>{};
        return _postService.getLikedPostIds(
          userId,
          newPosts.map((p) => p.id).toList(),
        );
      }

      // loadProfiles hatayı kendi yutar; beğeni hatası eskisi gibi aşağıdaki
      // catch'e (sayfayı geri alma) düşer.
      final profilesLoad = loadProfiles();
      final likedPostIds = await loadLikes();
      await profilesLoad;

      // Beğeni durumlarını işle
      final likedStatus = <String, bool>{};
      for (var post in newPosts) {
        likedStatus[post.id] = likedPostIds.contains(post.id);
      }

      if (!mounted || generation != _feedGeneration) return;
      setState(() {
        _posts.addAll(newPosts);
        _likedPosts.addAll(likedStatus);
        _currentPage = nextPage;
        // Sayfa dolu geldiyse devamı olabilir (tekilleştirilenler sayılmaz).
        _hasMore = fetched.length >= _pageSize;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (mounted && generation == _feedGeneration) {
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
        // Yalnız bu kartı çıkar; tüm akışı yeniden yüklemek kaydırmayı ve
        // yüklenmiş sayfaları kaybettiriyordu.
        setState(() {
          _posts.removeWhere((p) => p.id == postId);
          _likedPosts.remove(postId);
        });
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

  /// [postId] kartını [update] ile değiştirir (yoksa bir şey yapmaz).
  void _patchPost(String postId, Post Function(Post) update) {
    final index = _posts.indexWhere((p) => p.id == postId);
    if (index != -1) _posts[index] = update(_posts[index]);
  }

  /// "İlgilenmiyorum": gönderi kart yerinde "Gizlendi · Geri al" olur;
  /// sunucu sonraki yüklemelerde akıştan süzer.
  Future<void> _hidePost(Post post) async {
    if (_blockGuest()) return;
    setState(() => _hiddenPosts[post.id] = 'not_interested');
    try {
      await _postService.hidePost(post.id, reason: 'not_interested');
    } catch (e) {
      if (!mounted) return;
      setState(() => _hiddenPosts.remove(post.id));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gönderi gizlenemedi')),
      );
    }
  }

  Future<void> _unhidePost(String postId) async {
    setState(() => _hiddenPosts.remove(postId));
    try {
      await _postService.unhidePost(postId);
    } catch (_) {
      if (mounted) setState(() => _hiddenPosts[postId] = 'not_interested');
    }
  }

  /// Yazarı sessize alır: gönderileri ve hikâyeleri akıştan çıkar (profili,
  /// mesajları etkilenmez; karşı taraf fark etmez). Geri alınabilir.
  Future<void> _muteAuthor(Post post, String username) async {
    if (_blockGuest()) return;
    final messenger = ScaffoldMessenger.of(context);
    try {
      await MutedUsersService.instance.mute(post.userId);
      messenger.showSnackBar(
        SnackBar(
          content: Text('@$username sessize alındı'),
          action: SnackBarAction(
            label: 'Geri al',
            onPressed: () async {
              await MutedUsersService.instance.unmute(post.userId);
              if (mounted) _loadData(silent: true);
            },
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Sessize alınamadı')),
      );
    }
  }

  /// Kendi gönderisinin metnini düzenler; liste yalnız o gönderiyi yamar.
  Future<void> _editPost(Post post) async {
    final updated = await showEditPostSheet(context, post);
    if (updated == null || !mounted) return;
    setState(() => _patchPost(
          post.id,
          (p) => p.copyWith(content: updated.content, editedAt: updated.editedAt),
        ));
  }

  /// Gönderi Şikayet Dialog - Apple Guideline 1.2
  void _showPostReportDialog(Post post) {
    if (_blockGuest()) return;
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
              bottom: MediaQuery.viewInsetsOf(context).bottom,
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
    if (_blockGuest()) return;
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || !_likeInFlight.add(post.id)) return;

    final isLiked = _likedPosts[post.id] ?? false;
    int bump(int count, int delta) => (count + delta).clamp(0, 1 << 30);

    // İyimser güncelleme. Sayı sunucudan yeniden okunmaz (beğeni başına ek bir
    // istek demekti); sayacı tetikleyici tutar.
    setState(() {
      _likedPosts[post.id] = !isLiked;
      _patchPost(
        post.id,
        (p) => p.copyWith(likesCount: bump(p.likesCount, isLiked ? -1 : 1)),
      );
    });

    try {
      if (isLiked) {
        await _postService.unlikePost(post.id, userId);
      } else {
        await _postService.likePost(post.id, userId);
      }
    } catch (e) {
      if (!mounted) return;
      // Hata olursa geri al
      setState(() {
        _likedPosts[post.id] = isLiked;
        _patchPost(
          post.id,
          (p) => p.copyWith(likesCount: bump(p.likesCount, isLiked ? 1 : -1)),
        );
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppErrorHandler.handleError(e))),
      );
    } finally {
      _likeInFlight.remove(post.id);
    }
  }

  // Kaydedilen gönderiler post_favorites tablosunda tutuluyor (eskiden
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
    if (_blockGuest()) return;
    if (!_saveInFlight.add(post.id)) return;
    // Optimistik güncelleme; hata olursa geri alınır.
    final wasSaved = _savedPosts.contains(post.id);
    final isSaved = !wasSaved;
    setState(() {
      if (wasSaved) {
        _savedPosts.remove(post.id);
      } else {
        _savedPosts.add(post.id);
      }
    });

    try {
      // Ekranın bildiği durumun tersini iste (idempotent): "oku sonra
      // ekle/sil" yarışı ve tekil kısıt hatası olmaz.
      await _postService.setPostSaved(post.id, isSaved);

      if (!mounted) return;
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
    } finally {
      _saveInFlight.remove(post.id);
    }
  }

  Future<void> _sendToFriend(Post post) async {
    if (_blockGuest()) return;
    // Seçim sayfası kapandıktan SONRA da mesaj göstereceğiz: sayfanın kendi
    // context'i o anda ölü olur (ScaffoldMessenger.of onu kullanınca
    // "deactivated widget" fırlatıyor, gönderildi onayı hiç görünmüyordu).
    final messenger = ScaffoldMessenger.of(context);
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
          height: MediaQuery.sizeOf(context).height * 0.6,
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
                        backgroundImage: avatarImage(friendAvatar),
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
                            {
                              messenger.showSnackBar(
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

                          if (sent != null) {
                            unawaited(
                              SocialShareService().recordShare(
                                post.id,
                                channel: 'chat',
                              ),
                            );
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('$friendName\'e gönderildi!'),
                                behavior: SnackBarBehavior.floating,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            );
                          } else {
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('Gönderilemedi'),
                                backgroundColor: Colors.red,
                              ),
                            );
                          }
                        } catch (e) {
                          debugPrint('Mesaj gönderme hatası: $e');
                          {
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text(AppErrorHandler.handleError(e)),
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
    if (_blockGuest()) return;
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => PostDetailScreen(post: post)),
    );

    // Detayda beğeni/yorum değiştiyse yalnız bu kartı yama (eskiden tüm akış
    // yeniden yükleniyordu; detaydaki beğeni ise akışa hiç yansımıyordu).
    if (result is PostDetailResult && mounted) {
      setState(() {
        _likedPosts[result.postId] = result.isLiked;
        _patchPost(result.postId, result.applyTo);
      });
    }
  }

  Future<void> _createPost() async {
    if (_blockGuest()) return;
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const CreatePostScreen()),
    );
    // Yalnız gerçekten paylaşıldıysa yenile; vazgeçince akış yerinde kalır.
    if (created == true) unawaited(_loadData(silent: true));
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

      // Metin + gönderi linki (link uygulamada/web'de gönderiyi açar);
      // paylaşıldıysa sayaç bir artar (kişi başına bir kez).
      final count = await SocialShareService().sharePost(
        post,
        authorName: username,
      );
      if (count != null && mounted) {
        setState(() => _patchPost(post.id, (p) => p.copyWith(sharesCount: count)));
      }
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
    _tabActive = TickerMode.of(context);
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
                            onRefresh: () => _loadData(silent: true),
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
                                            if (_hiddenPosts.containsKey(post.id)) {
                                              return Padding(
                                                padding: const EdgeInsets.only(bottom: 12),
                                                child: _HiddenPostPlaceholder(
                                                  onUndo: () => _unhidePost(post.id),
                                                ),
                                              );
                                            }
                                            return Padding(
                                              padding: const EdgeInsets.only(
                                                bottom: 12,
                                              ),
                                              // Akışta görülme = görüntülenme
                                              // (toplu gönderilir, günde bir).
                                              child: ImpressionProbe(
                                                id: post.id,
                                                onSeen: () =>
                                                    PostImpressionTracker.instance.markSeen(
                                                      post.id,
                                                      authorId: post.userId,
                                                    ),
                                                child: _buildTwitterPostCard(post),
                                              ),
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
          // Yüzen + butonu (Profil ikonunun üzerinde, FloatingMessageButton gibi).
          // Misafirde gizlenir: paylaşım için zaten giriş gerekiyor, düğmeyi
          // göstermek boş bir vaat olurdu.
          if (!_isGuest)
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
    final screenSize = MediaQuery.sizeOf(context);
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
      final safePadding = MediaQuery.paddingOf(context).top;
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
          // Stories section — misafirde hikaye yerine giriş çağrısı gösterilir
          // (hikayeler yalnız üyelere açık ve misafir akışına hiç yüklenmez).
          if (_isGuest) _buildGuestLoginBanner() else _buildStoriesSection(),
        ],
      ),
    );
  }

  /// Misafir modunda hikaye şeridinin yerini alan bilgi/çağrı bandı.
  Widget _buildGuestLoginBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.25)),
        ),
        child: Row(
          children: [
            const Icon(Icons.visibility_outlined, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Misafir olarak geziyorsun. Beğenmek, yorum yapmak ve '
                'paylaşmak için giriş yap.',
                style: TextStyle(color: Colors.white, fontSize: 12.5),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              style: TextButton.styleFrom(
                backgroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
              onPressed: () => Navigator.of(context).pushNamed('/login'),
              child: const Text('Giriş Yap', style: TextStyle(fontSize: 12.5)),
            ),
          ],
        ),
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
            // "Hikayem" + şu an canlı yayınlar + hikayeler
            itemCount: _stories.length + _liveSessions.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return _buildMyStoryButtonDynamic(storyWidth);
              }
              final liveIndex = index - 1;
              if (liveIndex < _liveSessions.length) {
                return _buildLiveStoryDynamic(_liveSessions[liveIndex], storyWidth);
              }
              return _buildStoryCardDynamic(_stories[liveIndex - _liveSessions.length], storyWidth);
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
    required Story story,
    required String? avatarUrl,
    required double size,
  }) {
    // Metin hikayesinde görsel yok: zemin + kırpık yazı çizilir. Aksi halde
    // CachedNetworkImage boş URL ile hata durumuna düşer ve halkanın içi gri
    // bir kutu olarak görünürdü.
    if (story.isText) {
      return TextBackgroundCanvas(
        background: textBackgroundOrDefault(story.background),
        text: (story.textContent ?? '').trim(),
        maxLines: 3,
        fontScale: 0.85,
        padding: const EdgeInsets.all(6),
      );
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        CachedNetworkImage(
          memCacheWidth: 480,
          imageUrl: story.displayUrl,
          fit: BoxFit.cover,
          errorWidget: (context, url, error) => Container(
            color: Colors.grey.shade300,
            child: avatarUrl != null
                ? CachedNetworkImage(memCacheWidth: 240, imageUrl: avatarUrl, fit: BoxFit.cover)
                : Icon(Icons.person, size: size * 0.4, color: Colors.grey),
          ),
          placeholder: (context, url) => Container(color: Colors.grey.shade200),
        ),
        if (story.isVideo)
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
                          story: latestStory,
                          avatarUrl: avatarUrl,
                          size: size,
                        )
                      : Container(
                          color: primaryColor.withValues(alpha: 0.1),
                          child: avatarUrl != null
                              // Hareketli (GIF) avatarın her karesi sabit
                              // üst bölümün tamamını yeniden boyatıyordu
                              // (Keşfet boştayken ~26 kare/sn × 2 ms).
                              ? RepaintBoundary(
                                  child: CachedNetworkImage(
                                    memCacheWidth: 240,
                                    imageUrl: avatarUrl,
                                    fit: BoxFit.cover,
                                  ),
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

  /// Canlı yayın halkası: kırmızı çerçeve, yayıncının/mağazanın görseli ve
  /// altta "CANLI" rozeti. Dokununca yayın izleyicisi açılır.
  Widget _buildLiveStoryDynamic(LiveSession session, double size) {
    const ringWidth = 2.6;
    final innerSize = size - (ringWidth + 2) * 2;
    return Padding(
      key: ValueKey('social-live-${session.id}'),
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () => _openLive(session),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomCenter,
              children: [
                Container(
                  width: size,
                  height: size,
                  decoration: const BoxDecoration(shape: BoxShape.circle, color: kLiveRed),
                  padding: const EdgeInsets.all(ringWidth),
                  child: Container(
                    decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.white),
                    padding: const EdgeInsets.all(2),
                    child: LiveShopAvatar(
                      logoUrl: session.displayAvatarUrl,
                      name: session.displayName,
                      size: innerSize,
                    ),
                  ),
                ),
                Positioned(
                  bottom: -4,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                    decoration: BoxDecoration(
                      color: kLiveRed,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white, width: 1.5),
                    ),
                    child: const Text(
                      'CANLI',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          _buildStoryLabel(session.displayName, size),
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
                story: story,
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
    if (_blockGuest()) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(userId: userId),
      ),
    );
  }

  /// Bir profilde (hangi yoldan açılmış olursa olsun) engellenen kişinin
  /// ekrandaki eski gönderi/hikâyeleri elle yenilemeyi beklemeden çıkar;
  /// sunucu sonraki yüklemelerde zaten süzüyor.
  void _onUserBlocked(String userId) {
    if (!mounted) return;
    setState(() {
      _posts.removeWhere((p) => p.userId == userId);
      _stories.removeWhere((s) => s.userId == userId);
    });
  }

  Future<void> _addStory() async {
    if (_blockGuest()) return;
    // Instagram tarzı story oluşturma bottom sheet'i aç
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => InstagramStoryCreator(
        imagePicker: _imagePicker,
        onGoLive: () => _goLive(sheetContext),
        liveAvailable: _liveService.canStartUserStream,
        onMediaSelected: (media, mediaType, music) async {
          // Seçilen medyayı yükle
          await _uploadAndCreateStory(media, mediaType, music);
        },
        onTextStory: (text, backgroundId, music) async {
          await _createTextStory(text, backgroundId, music);
        },
      ),
    );
  }

  /// Arka planlı metin hikayesi: yüklenecek dosya yok, doğrudan satır açılır.
  Future<void> _createTextStory(
    String text,
    String backgroundId, [
    AttachedMusic? music,
  ]) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final story = await _storyService.createTextStory(
        userId: userId,
        text: text,
        background: backgroundId,
        music: music,
      );

      // createTextStory null dönerse (RLS/insert hatası) "paylaşıldı" demek
      // yanıltıcı olur; hikaye listede görünmüyor ama kullanıcı başarılı sandı.
      if (story == null) {
        throw Exception('Hikaye kaydedilemedi, lütfen tekrar deneyin');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Hikaye paylaşıldı!')),
      );
      await _refreshStories();
    } catch (e) {
      debugPrint('Metin hikayesi oluşturulamadı: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppErrorHandler.handleError(e))),
      );
    }
  }

  Future<void> _uploadAndCreateStory(
    XFile media,
    String mediaType, [
    AttachedMusic? music,
  ]) async {
    // Yükleme diyaloğu açık mı? Hata yolunda yalnız AÇIKSA kapatılır: eskiden
    // diyalog zaten kapandıktan sonra gelen hatada ikinci bir pop altındaki
    // ekranı (ör. /main ile açılmış ana ekranı) kapatıyordu.
    var dialogOpen = false;
    ValueNotifier<double>? progressNotifier;
    void closeDialog() {
      if (dialogOpen && mounted) Navigator.of(context).pop();
      dialogOpen = false;
    }

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      String? thumbnailUrl; // Video thumbnail URL
      String mediaUrl;

      if (mediaType == 'image') {
        // Fotoğraf için progress dialog göster
        if (!mounted) return;
        dialogOpen = true;
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

        closeDialog();
      } else {
        // Video için progress tracking StateNotifier kullan
        if (!mounted) return;

        // Video progress dialog'u aç
        final notifier = progressNotifier = ValueNotifier<double>(0.0);

        dialogOpen = true;
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
                      valueListenable: notifier,
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
            notifier.value = p;
          },
        );

        closeDialog();

        if (result == null || result['videoUrl'] == null) {
          throw Exception('Video yüklenirken hata oluştu');
        }

        mediaUrl = result['videoUrl']!;
        final thumb = result['thumbnailUrl'];
        thumbnailUrl = (thumb != null && thumb.isNotEmpty) ? thumb : null;
        debugPrint('Video URL: $mediaUrl');
        debugPrint('Thumbnail URL: $thumbnailUrl');
      }

      debugPrint('Story oluşturuluyor: mediaType=$mediaType, url=$mediaUrl');

      final newStory = await _storyService.createStory(
        userId: userId,
        imageUrl: mediaUrl,
        mediaType: mediaType,
        thumbnailUrl: thumbnailUrl, // Video için thumbnail URL'ini geçir
        music: music,
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
        // Yalnız hikâye şeridini tazele (akış yerinde kalır)
        await _refreshStories();
      }
    } catch (e) {
      debugPrint('Story yüklenirken hata: $e');
      closeDialog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppErrorHandler.handleError(e))),
        );
      }
    } finally {
      // Diyalog kapanış animasyonu bitince bırak (hemen dispose edilirse
      // kapanırken çizilen ValueListenableBuilder hata verir).
      final notifier = progressNotifier;
      if (notifier != null) {
        Future.delayed(const Duration(seconds: 1), notifier.dispose);
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
      // Görüldü halkaları için yalnız hikâye şeridini tazele
      unawaited(_refreshStories());
    }
  }

  Future<void> _viewUserStories() async {
    if (_blockGuest()) return;
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
      unawaited(_refreshStories());
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

  /// Keşfet akışındaki gönderi kartı. Uygulamadaki TÜM gönderi listeleri
  /// (favoriler, profil) bu tasarımı SocialPostCard üzerinden paylaşır —
  /// kart tasarımı değişirse tek yerden (social_post_card.dart) güncellenir.
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
    final avatarUrl = isOrphanPost
        ? null
        : (post.authorAvatarUrl ?? userProfile?['avatar_url']);
    final authorRole = isOrphanPost ? AuthorRole.unknown : post.authorRole;
    final isVerified = isOrphanPost ? false : post.authorIsVerified;
    final isLiked = _likedPosts[post.id] ?? false;
    final isSaved = _savedPosts.contains(post.id);
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    final isOwnPost = !isOrphanPost && post.userId == currentUserId;

    return SocialPostCard(
      post: post,
      fullName: fullName,
      username: username,
      avatarUrl: avatarUrl,
      authorRole: authorRole,
      isVerified: isVerified,
      showPrivilegeBadges: !isOrphanPost,
      isLiked: isLiked,
      isSaved: isSaved,
      // _showComments kullanılıyor: detay ekranından "yorum eklendi/silindi"
      // sonucu dönerse feed'deki yorum sayacı da tazeleniyor.
      onTap: () => _showComments(post),
      onAuthorTap: () => _viewUserProfile(post.userId),
      onLike: () => _toggleLike(post),
      onComment: () => _showComments(post),
      onSend: () => _sendToFriend(post),
      onSave: () => _savePost(post),
      onShare: () {
        if (_blockGuest()) return;
        _sharePost(post);
      },
      onViewsTap: isOwnPost ? () => showPostInsightsSheet(context, post) : null,
      onHashtagTap: (tag) {
        if (_blockGuest()) return;
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => HashtagFeedScreen(tag: tag)),
        );
      },
      trailing: PopupMenuButton<String>(
        icon: Icon(Icons.more_horiz, color: Colors.grey.shade500, size: 20),
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
          } else if (value == 'insights') {
            showPostInsightsSheet(context, post);
          } else if (value == 'edit') {
            _editPost(post);
          } else if (value == 'not_interested') {
            _hidePost(post);
          } else if (value == 'mute') {
            _muteAuthor(post, username);
          }
        },
        itemBuilder: (context) => [
          if (isOwnPost)
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('Düzenle'),
                ],
              ),
            ),
          if (isOwnPost)
            const PopupMenuItem(
              value: 'insights',
              child: Row(
                children: [
                  Icon(Icons.insights_rounded, color: Color(0xFF7C3AED), size: 20),
                  SizedBox(width: 12),
                  Text('İstatistikler'),
                ],
              ),
            ),
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
          if (!isOwnPost && !_isGuest)
            const PopupMenuItem(
              value: 'not_interested',
              child: Row(
                children: [
                  Icon(Icons.visibility_off_outlined, size: 20),
                  SizedBox(width: 12),
                  Text('İlgilenmiyorum'),
                ],
              ),
            ),
          if (!isOwnPost && !_isGuest && !isOrphanPost)
            PopupMenuItem(
              value: 'mute',
              child: Row(
                children: [
                  const Icon(Icons.volume_off_outlined, size: 20),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      '@$username sessize al',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
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
      ),
    );
  }
}

/// "İlgilenmiyorum" denen gönderinin akıştaki yer tutucusu (geri alınabilir).
class _HiddenPostPlaceholder extends StatelessWidget {
  const _HiddenPostPlaceholder({required this.onUndo});

  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE9EDF1)),
      ),
      child: Row(
        children: [
          Icon(Icons.visibility_off_outlined, size: 20, color: Colors.grey.shade500),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Gönderi akışından kaldırıldı.',
              style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
            ),
          ),
          TextButton(onPressed: onUndo, child: const Text('Geri al')),
        ],
      ),
    );
  }
}
