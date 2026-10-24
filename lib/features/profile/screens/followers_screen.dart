// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../social/models/follow_suggestion.dart' show FollowStatus;
import '../../social/services/follow_service.dart';
import 'user_profile_screen.dart';
import '../../../core/utils/app_error_handler.dart';
import '../../../core/utils/image_url.dart';

/// Takipçi, Takip Edilen ve Arkadaş listesi ekranı
enum FollowListType { followers, following, friends }

/// Listedeki bir kişiyle benim ilişkim.
enum _Relation { none, following, requested }

class FollowListScreen extends StatefulWidget {
  final String userId;
  final FollowListType listType;
  final String? username;

  const FollowListScreen({
    super.key,
    required this.userId,
    required this.listType,
    this.username,
  });

  /// Sayfa boyutu: liste kaydırıldıkça bu kadar kişi daha yüklenir.
  static const int pageSize = 30;

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  static const _profileColumns = 'id, username, full_name, avatar_url, bio';

  final _followService = FollowService();
  final _scrollController = ScrollController();

  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  List<Map<String, dynamic>> _users = [];
  String? _error;

  /// Benim bu listedeki kişilerle ilişkim (takip / bekleyen istek). Sayfa
  /// başına TEK sorguyla dolar; eskiden her satır kendi takip sorgusunu
  /// atıyordu (N+1).
  final Map<String, _Relation> _relations = {};
  Set<String> _pendingIds = const {};

  /// İşlemi süren satırlar (çift dokunuş yok sayılır).
  final Set<String> _busy = {};

  /// Arkadaş listesi istemcide kesişimle bulunur; profiller sayfa sayfa çekilir.
  List<String>? _friendIds;

  /// Yükleme nesli: yenileme sırasında dönen eski sayfa atılır.
  int _generation = 0;

  String? get _me => Supabase.instance.client.auth.currentUser?.id;

  /// Kendi takipçi listem mi? ("Çıkar" yalnız burada.)
  bool get _isMyFollowersList =>
      widget.listType == FollowListType.followers && widget.userId == _me;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _loadUsers();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 300 &&
        _hasMore &&
        !_isLoadingMore &&
        !_isLoading) {
      _loadMore();
    }
  }

  Future<void> _loadUsers() async {
    // Takip işlemlerinden sonra await ardından da çağrılıyor; ekran o arada
    // kapanmış olabilir (admin Loglar: "setState() called after dispose()").
    if (!mounted) return;
    final generation = ++_generation;
    setState(() {
      _isLoading = _users.isEmpty;
      _error = null;
    });

    try {
      if (_me == null) {
        setState(() {
          _error = 'Kullanıcı giriş yapmamış';
          _isLoading = false;
        });
        return;
      }

      _friendIds = null;
      final pending = _followService.pendingRequestIds().catchError(
        (Object e) => <String>{},
      );
      final users = await _fetchPage(0);
      final pendingIds = await pending;
      final relations = await _relationsFor(users, pendingIds);
      if (!mounted || generation != _generation) return;

      setState(() {
        _pendingIds = pendingIds;
        _users = users;
        _relations
          ..clear()
          ..addAll(relations);
        _hasMore = users.length >= FollowListScreen.pageSize;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = AppErrorHandler.handleError(e);
        _isLoading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    final generation = _generation;
    setState(() => _isLoadingMore = true);
    try {
      final more = await _fetchPage(_users.length);
      final relations = await _relationsFor(more, _pendingIds);
      if (!mounted || generation != _generation) return;
      final known = {for (final u in _users) u['id']};
      setState(() {
        _users.addAll(more.where((u) => !known.contains(u['id'])));
        _relations.addAll(relations);
        _hasMore = more.length >= FollowListScreen.pageSize;
        _isLoadingMore = false;
      });
    } catch (e) {
      if (!mounted || generation != _generation) return;
      setState(() => _isLoadingMore = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppErrorHandler.handleError(e))),
      );
    }
  }

  /// [offset]'ten başlayan bir sayfa kişi (profil satırları).
  Future<List<Map<String, dynamic>>> _fetchPage(int offset) async {
    final client = Supabase.instance.client;
    const size = FollowListScreen.pageSize;

    List<Map<String, dynamic>> fromJoin(List rows) => [
          for (final item in rows)
            if (item['profiles'] is Map)
              Map<String, dynamic>.from(item['profiles'] as Map),
        ];

    switch (widget.listType) {
      case FollowListType.followers:
        final rows = await client
            .from('follows')
            .select(
              'follower_id, profiles!follows_follower_id_fkey ($_profileColumns)',
            )
            .eq('following_id', widget.userId)
            .order('created_at', ascending: false)
            .range(offset, offset + size - 1);
        return fromJoin(rows);
      case FollowListType.following:
        final rows = await client
            .from('follows')
            .select(
              'following_id, profiles!follows_following_id_fkey ($_profileColumns)',
            )
            .eq('follower_id', widget.userId)
            .order('created_at', ascending: false)
            .range(offset, offset + size - 1);
        return fromJoin(rows);
      case FollowListType.friends:
        // Karşılıklı takip: iki kimlik listesi (yalnız id) aynı anda gelir,
        // kesişim bir kez hesaplanır; profiller sayfa sayfa çekilir.
        _friendIds ??= await () async {
          final (followers, following) = await (
            client
                .from('follows')
                .select('follower_id')
                .eq('following_id', widget.userId),
            client
                .from('follows')
                .select('following_id')
                .eq('follower_id', widget.userId),
          ).wait;
          final followerIds = {
            for (final e in followers) e['follower_id'] as String,
          };
          return [
            for (final e in following)
              if (followerIds.contains(e['following_id'])) e['following_id'] as String,
          ];
        }();
        final ids = _friendIds!.skip(offset).take(size).toList();
        if (ids.isEmpty) return [];
        // public_profiles_safe: tüm public profiller okunabilir.
        final rows = await client
            .from('public_profiles_safe')
            .select(_profileColumns)
            .inFilter('id', ids);
        final byId = {for (final r in rows) r['id']: r};
        return [
          for (final id in ids)
            if (byId[id] != null) Map<String, dynamic>.from(byId[id] as Map),
        ];
    }
  }

  /// [users] için benim takip ilişkim — TEK sorgu.
  Future<Map<String, _Relation>> _relationsFor(
    List<Map<String, dynamic>> users,
    Set<String> pendingIds,
  ) async {
    final me = _me;
    final ids = [
      for (final u in users)
        if (u['id'] != me) u['id'] as String,
    ];
    if (me == null || ids.isEmpty) return {};

    final rows = await Supabase.instance.client
        .from('follows')
        .select('following_id')
        .eq('follower_id', me)
        .inFilter('following_id', ids);
    final followed = {for (final r in rows) r['following_id'] as String};
    return {
      for (final id in ids)
        id: followed.contains(id)
            ? _Relation.following
            : (pendingIds.contains(id) ? _Relation.requested : _Relation.none),
    };
  }

  String _getTitle() {
    switch (widget.listType) {
      case FollowListType.followers:
        return 'Takipçiler';
      case FollowListType.following:
        return 'Takip Edilenler';
      case FollowListType.friends:
        return 'Arkadaşlar';
    }
  }

  /// Takip et / bırak / isteği geri al — tek RPC. Satırın düğmesi sonuca göre
  /// çizilir (gizli hesapta "İstek Gönderildi"); hata olursa hiçbir şey
  /// değişmez. Eskiden düğme sonuçtan bağımsız ters çevriliyordu.
  Future<void> _toggleFollow(String targetUserId) async {
    if (!_busy.add(targetUserId)) return;
    final messenger = ScaffoldMessenger.of(context);
    final current = _relations[targetUserId] ?? _Relation.none;
    setState(() {});

    try {
      final result = current == _Relation.none
          ? await _followService.follow(targetUserId)
          : await _followService.unfollow(targetUserId);
      if (!mounted) return;
      final next = switch (result.status) {
        FollowStatus.following => _Relation.following,
        FollowStatus.requested => _Relation.requested,
        FollowStatus.none => _Relation.none,
      };
      setState(() => _relations[targetUserId] = next);
      messenger.showSnackBar(
        SnackBar(
          content: Text(switch (next) {
            _Relation.following => 'Takip edildi',
            _Relation.requested => 'Takip isteği gönderildi',
            _Relation.none => current == _Relation.requested
                ? 'Takip isteği iptal edildi'
                : 'Takip bırakıldı',
          }),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    } on FollowException catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(AppErrorHandler.handleError(e)),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      _busy.remove(targetUserId);
      if (mounted) setState(() {});
    }
  }

  /// Kendi takipçi listemden birini çıkarır (sessiz: karşı tarafa bildirim
  /// gitmez). Gizli hesabımda o kişi artık gönderilerimi göremez; açık
  /// hesapta isterse yeniden takip edebilir.
  Future<void> _removeFollower(String followerId, String username) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Takipçiyi çıkar'),
        content: Text(
          '@$username takipçilerinden çıkarılsın mı? Kendisine bildirim '
          'gönderilmez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Çıkar'),
          ),
        ],
      ),
    );
    final me = _me;
    if (confirm != true || me == null || !mounted) return;
    if (!_busy.add(followerId)) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {});

    try {
      // follows DELETE politikası takip edilen tarafa da izin verir; RLS
      // sessizce 0 satır yaparsa bunu hata say.
      final deleted = await Supabase.instance.client
          .from('follows')
          .delete()
          .eq('follower_id', followerId)
          .eq('following_id', me)
          .select('id');
      if ((deleted as List).isEmpty) {
        throw Exception('Takipçi çıkarılamadı');
      }
      if (!mounted) return;
      setState(() => _users.removeWhere((u) => u['id'] == followerId));
      messenger.showSnackBar(
        SnackBar(
          content: Text('@$username takipçilerinden çıkarıldı'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(AppErrorHandler.handleError(e)),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      _busy.remove(followerId);
      if (mounted) setState(() {});
    }
  }

  void _navigateToProfile(String userId) {
    // Profil ekranına yönlendir. '/profile' adında kayıtlı bir route olmadığı
    // için doğrudan UserProfileScreen widget'ını push ediyoruz (uygulamadaki
    // tüm diğer profil yönlendirmeleriyle aynı pattern).
    // pushReplacement: listeyi profil ekranıyla değiştirir, böylece Geri tuşu
    // doğrudan bu listeyi açan profil ekranına döner.
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => UserProfileScreen(userId: userId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          _getTitle(),
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.error_outline, size: 64, color: Colors.grey.shade400),
                      const SizedBox(height: 16),
                      Text(
                        _error!,
                        style: TextStyle(color: Colors.grey.shade600),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 16),
                      ElevatedButton(
                        onPressed: _loadUsers,
                        child: const Text('Tekrar Dene'),
                      ),
                    ],
                  ),
                )
              : _users.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _getListIcon(),
                            size: 64,
                            color: Colors.grey.shade300,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _getEmptyMessage(),
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadUsers,
                      child: ListView.separated(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _users.length + (_isLoadingMore ? 1 : 0),
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          if (index >= _users.length) {
                            return const Padding(
                              padding: EdgeInsets.symmetric(vertical: 16),
                              child: Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                ),
                              ),
                            );
                          }
                          final user = _users[index];
                          final userId = user['id'] as String;
                          final username = user['username'] as String? ?? 'Kullanıcı';
                          final fullName = user['full_name'] as String? ?? username;
                          final isOwnProfile = userId == _me;

                          return _UserListItem(
                            username: username,
                            fullName: fullName,
                            avatarUrl: user['avatar_url'] as String?,
                            bio: user['bio'] as String?,
                            isOwnProfile: isOwnProfile,
                            relation: _relations[userId] ?? _Relation.none,
                            busy: _busy.contains(userId),
                            onTap: () => _navigateToProfile(userId),
                            onToggleFollow: () => _toggleFollow(userId),
                            onRemove: _isMyFollowersList && !isOwnProfile
                                ? () => _removeFollower(userId, username)
                                : null,
                          );
                        },
                      ),
                    ),
    );
  }

  IconData _getListIcon() {
    switch (widget.listType) {
      case FollowListType.followers:
        return Icons.people_outline;
      case FollowListType.following:
        return Icons.person_add_outlined;
      case FollowListType.friends:
        return Icons.group_outlined;
    }
  }

  String _getEmptyMessage() {
    switch (widget.listType) {
      case FollowListType.followers:
        return 'Henüz takipçi yok';
      case FollowListType.following:
        return 'Kimseyi takip etmiyorsun';
      case FollowListType.friends:
        return 'Arkadaşın yok';
    }
  }
}

class _UserListItem extends StatelessWidget {
  final String username;
  final String fullName;
  final String? avatarUrl;
  final String? bio;
  final bool isOwnProfile;
  final _Relation relation;
  final bool busy;
  final VoidCallback onTap;
  final VoidCallback onToggleFollow;

  /// Kendi takipçi listemde "Çıkar"; null ise takip düğmesi gösterilir.
  final VoidCallback? onRemove;

  const _UserListItem({
    required this.username,
    required this.fullName,
    required this.avatarUrl,
    required this.bio,
    required this.isOwnProfile,
    required this.relation,
    required this.busy,
    required this.onTap,
    required this.onToggleFollow,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    // Kendi takipçi listemde geri takip etmediğim kişi için adın yanında
    // küçük bir "Takip Et" (Instagram'daki gibi); ana düğme "Çıkar".
    final showInlineFollow = onRemove != null && relation == _Relation.none;

    return InkWell(
      onTap: onTap,
      splashColor: primary.withValues(alpha: 0.1),
      highlightColor: Colors.grey.shade50,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 26,
              backgroundImage: avatarImage(avatarUrl),
              backgroundColor: Colors.grey.shade200,
              child: avatarUrl == null
                  ? Text(
                      username.isNotEmpty ? username.substring(0, 1).toUpperCase() : '?',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.grey.shade600,
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 14),
            // Kullanıcı bilgisi
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (showInlineFollow && !busy)
                        GestureDetector(
                          onTap: onToggleFollow,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Text(
                              '· Takip Et',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: primary,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@$username',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  if (bio != null && bio!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      bio!,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            // Aksiyon butonu
            if (!isOwnProfile)
              SizedBox(
                width: 104,
                height: 36,
                child: busy
                    ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                    : onRemove != null
                        ? _ActionPill(
                            label: 'Çıkar',
                            filled: false,
                            onTap: onRemove!,
                          )
                        : _ActionPill(
                            label: switch (relation) {
                              _Relation.following => 'Takipten Çık',
                              _Relation.requested => 'İstek Gönderildi',
                              _Relation.none => 'Takip Et',
                            },
                            filled: relation == _Relation.none,
                            onTap: onToggleFollow,
                          ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionPill extends StatelessWidget {
  final String label;
  final bool filled;
  final VoidCallback onTap;

  const _ActionPill({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return Ink(
      decoration: BoxDecoration(
        gradient: filled
            ? LinearGradient(
                colors: [primary, primary.withValues(alpha: 0.8)],
              )
            : null,
        color: filled ? null : Colors.grey.shade100,
        borderRadius: BorderRadius.circular(10),
        border: filled ? null : Border.all(color: Colors.grey.shade300),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        splashColor: Colors.white.withValues(alpha: 0.3),
        child: Center(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: filled ? Colors.white : Colors.black87,
            ),
          ),
        ),
      ),
    );
  }
}
