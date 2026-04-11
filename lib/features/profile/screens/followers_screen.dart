// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Takipçi, Takip Edilen ve Arkadaş listesi ekranı
enum FollowListType { followers, following, friends }

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

  @override
  State<FollowListScreen> createState() => _FollowListScreenState();
}

class _FollowListScreenState extends State<FollowListScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _users = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) {
        setState(() {
          _error = 'Kullanıcı giriş yapmamış';
          _isLoading = false;
        });
        return;
      }

      List<Map<String, dynamic>> users = [];

      if (widget.listType == FollowListType.followers) {
        // Takipçilerimi getir
        final response = await Supabase.instance.client
            .from('follows')
            .select('''
              follower_id,
              profiles!follows_follower_id_fkey (
                id,
                username,
                full_name,
                avatar_url,
                bio
              )
            ''')
            .eq('following_id', widget.userId)
            .order('created_at', ascending: false);

        for (var item in response) {
          final profile = item['profiles'] as Map<String, dynamic>?;
          if (profile != null) {
            users.add(profile);
          }
        }
      } else if (widget.listType == FollowListType.following) {
        // Takip ettiklerimi getir
        final response = await Supabase.instance.client
            .from('follows')
            .select('''
              following_id,
              profiles!follows_following_id_fkey (
                id,
                username,
                full_name,
                avatar_url,
                bio
              )
            ''')
            .eq('follower_id', widget.userId)
            .order('created_at', ascending: false);

        for (var item in response) {
          final profile = item['profiles'] as Map<String, dynamic>?;
          if (profile != null) {
            users.add(profile);
          }
        }
      } else if (widget.listType == FollowListType.friends) {
        // Arkadaşları getir (karşılıklı takip)
        final followersResponse = await Supabase.instance.client
            .from('follows')
            .select('follower_id')
            .eq('following_id', widget.userId);

        final followingResponse = await Supabase.instance.client
            .from('follows')
            .select('following_id')
            .eq('follower_id', widget.userId);

        final followers = (followersResponse as List)
            .map((e) => e['follower_id'] as String)
            .toSet();
        final following = (followingResponse as List)
            .map((e) => e['following_id'] as String)
            .toSet();

        final friendIds = followers.intersection(following).toList();

        if (friendIds.isNotEmpty) {
          final response = await Supabase.instance.client
              .from('profiles')
              .select('id, username, full_name, avatar_url, bio')
              .inFilter('id', friendIds);

          users = List<Map<String, dynamic>>.from(response);
        }
      }

      setState(() {
        _users = users;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Liste yüklenirken hata: $e';
        _isLoading = false;
      });
    }
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

  Future<void> _toggleFollow(String targetUserId, bool isCurrentlyFollowing) async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    try {
      // Hedef kullanıcının profilini kontrol et
      final targetProfile = await Supabase.instance.client
          .from('profiles')
          .select('profile_is_public')
          .eq('id', targetUserId)
          .maybeSingle();

      final isTargetPrivate = targetProfile?['profile_is_public'] == false;

      // Gizli profil ve takip etmiyorsak
      if (isTargetPrivate && !isCurrentlyFollowing) {
        // Bekleyen takip isteği var mı kontrol et
        final existingRequest = await Supabase.instance.client
            .from('follow_requests')
            .select('id, status')
            .eq('follower_id', currentUserId)
            .eq('following_id', targetUserId)
            .maybeSingle();

        // İstek kabul edildiyse, artık takip ediliyordur
        if (existingRequest != null && existingRequest['status'] == 'accepted') {
          await _loadUsers();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text('Takip isteğiniz zaten kabul edilmiş'),
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
        // Listeyi yenile
        await _loadUsers();
        return;
      }

      // Normal takip/takibi bırak işlemi
      if (isCurrentlyFollowing) {
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
        await Supabase.instance.client
            .from('follows')
            .insert({
              'follower_id': currentUserId,
              'following_id': targetUserId,
            });
      }

      // Listeyi yenile
      await _loadUsers();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isCurrentlyFollowing ? 'Takip bırakıldı' : 'Takip edildi'),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        );
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

  Future<bool> _checkIsFollowing(String targetUserId) async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return false;

    try {
      final response = await Supabase.instance.client
          .from('follows')
          .select('id')
          .eq('follower_id', currentUserId)
          .eq('following_id', targetUserId)
          .maybeSingle();

      return response != null;
    } catch (e) {
      return false;
    }
  }

  void _navigateToProfile(String userId) {
    Navigator.pop(context);
    // Profil ekranına yönlendir
    Navigator.pushNamed(
      context,
      '/profile',
      arguments: {'userId': userId},
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(_getTitle()),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black87,
        elevation: 0,
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
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _users.length,
                        separatorBuilder: (context, index) => const Divider(height: 1),
                        itemBuilder: (context, index) {
                          final user = _users[index];
                          final userId = user['id'] as String;
                          final username = user['username'] as String? ?? 'Kullanıcı';
                          final fullName = user['full_name'] as String? ?? username;
                          final avatarUrl = user['avatar_url'] as String?;
                          final bio = user['bio'] as String?;
                          final isOwnProfile = userId == Supabase.instance.client.auth.currentUser?.id;

                          return _UserListItem(
                            userId: userId,
                            username: username,
                            fullName: fullName,
                            avatarUrl: avatarUrl,
                            bio: bio,
                            isOwnProfile: isOwnProfile,
                            onTap: () => _navigateToProfile(userId),
                            onToggleFollow: (isFollowing) => _toggleFollow(userId, isFollowing),
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

class _UserListItem extends StatefulWidget {
  final String userId;
  final String username;
  final String fullName;
  final String? avatarUrl;
  final String? bio;
  final bool isOwnProfile;
  final VoidCallback onTap;
  final Function(bool) onToggleFollow;

  const _UserListItem({
    required this.userId,
    required this.username,
    required this.fullName,
    required this.avatarUrl,
    required this.bio,
    required this.isOwnProfile,
    required this.onTap,
    required this.onToggleFollow,
  });

  @override
  State<_UserListItem> createState() => _UserListItemState();
}

class _UserListItemState extends State<_UserListItem> {
  bool _isFollowing = false;
  bool _isLoadingFollow = false;

  @override
  void initState() {
    super.initState();
    _checkFollowStatus();
  }

  Future<void> _checkFollowStatus() async {
    if (widget.isOwnProfile) return;
    
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    try {
      final response = await Supabase.instance.client
          .from('follows')
          .select('id')
          .eq('follower_id', currentUserId)
          .eq('following_id', widget.userId)
          .maybeSingle();

      setState(() {
        _isFollowing = response != null;
      });
    } catch (e) {
      debugPrint('Takip durumu kontrol hatası: $e');
    }
  }

  Future<void> _handleToggleFollow() async {
    setState(() => _isLoadingFollow = true);
    
    await widget.onToggleFollow(_isFollowing);
    
    setState(() {
      _isFollowing = !_isFollowing;
      _isLoadingFollow = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: widget.onTap,
      splashColor: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
      highlightColor: Colors.grey.shade50,
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            // Avatar
            CircleAvatar(
              radius: 26,
              backgroundImage: widget.avatarUrl != null ? NetworkImage(widget.avatarUrl!) : null,
              backgroundColor: Colors.grey.shade200,
              child: widget.avatarUrl == null
                  ? Text(
                      widget.username.isNotEmpty ? widget.username.substring(0, 1).toUpperCase() : '?',
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
                  Text(
                    widget.fullName,
                    style: const TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '@${widget.username}',
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade600,
                    ),
                  ),
                  if (widget.bio != null && widget.bio!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.bio!,
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
            if (!widget.isOwnProfile)
              SizedBox(
                width: 90,
                height: 36,
                child: _isLoadingFollow
                    ? const Center(child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
                    : Ink(
                        decoration: BoxDecoration(
                          gradient: _isFollowing
                              ? null
                              : LinearGradient(
                                  colors: [
                                    Theme.of(context).colorScheme.primary,
                                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                                  ],
                                ),
                          color: _isFollowing ? Colors.grey.shade100 : null,
                          borderRadius: BorderRadius.circular(10),
                          border: _isFollowing ? Border.all(color: Colors.grey.shade300) : null,
                        ),
                        child: InkWell(
                          onTap: _handleToggleFollow,
                          borderRadius: BorderRadius.circular(10),
                          splashColor: Colors.white.withValues(alpha: 0.3),
                          child: Center(
                              child: Text(
                                _isFollowing ? 'Takip' : 'Takip Et',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: _isFollowing ? Colors.black87 : Colors.white,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
          ],
        ),
      ),
    );
  }
}
