// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/services/privacy_service.dart';
import '../../profile/screens/user_profile_screen.dart';

class MembersScreen extends StatefulWidget {
  const MembersScreen({super.key});

  @override
  State<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends State<MembersScreen> {
  List<Map<String, dynamic>> _allUsers = [];
  List<Map<String, dynamic>> _filteredUsers = [];
  bool _isLoading = true;
  String _searchQuery = '';
  Set<String> _followingIds = {};
  Map<String, bool> _isLoadingFollow = {};

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    try {
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) {
        setState(() => _isLoading = false);
        return;
      }

      // Tüm kullanıcıları getir (ghost mode dahil)
      // Sıralama: En yeni kullanıcılar önce
      final response = await Supabase.instance.client
          .from('profiles')
          .select('id, full_name, username, avatar_url, last_seen, is_online, is_ghost_mode, created_at, bio')
          .neq('id', currentUserId)
          .order('created_at', ascending: false) // En yeni kullanıcılar önce
          .limit(500); // Daha fazla kullanıcı getir

      // Takip edilen kullanıcıları getir
      final followingResponse = await Supabase.instance.client
          .from('follows')
          .select('following_id')
          .eq('follower_id', currentUserId);

      final followingIds = <String>{};
      for (var f in followingResponse) {
        followingIds.add(f['following_id'] as String);
      }

      final users = (response as List).cast<Map<String, dynamic>>();

      // Aktiflik durumunu hesapla
      for (var user in users) {
        final isOnline = user['is_online'] as bool? ?? false;
        final lastSeen = _parseDateTime(user['last_seen']);
        user['_isActive'] = PrivacyService.isUserTrulyActive(isOnline, lastSeen);
      }

      // Aktif ve inaktif kullanıcıları ayır
      final activeUsers = users.where((u) => u['_isActive'] == true).toList();
      final inactiveUsers = users.where((u) => u['_isActive'] != true).toList();

      // Her grubu içinde rastgele sırala (yenilendiğinde sıralama değişsin)
      activeUsers.shuffle();
      inactiveUsers.shuffle();

      // Aktifler öne, inaktifler arkaya
      users
        ..clear()
        ..addAll([...activeUsers, ...inactiveUsers]);

      if (mounted) {
        setState(() {
          _allUsers = users;
          _followingIds = followingIds;
          _filteredUsers = users;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Kullanıcılar yüklenirken hata: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _filterUsers(String query) {
    setState(() {
      _searchQuery = query;
      if (query.isEmpty) {
        _filteredUsers = _allUsers;
      } else {
        final lowerQuery = query.toLowerCase();
        _filteredUsers = _allUsers.where((user) {
          final fullName = (user['full_name'] as String? ?? '').toLowerCase();
          final username = (user['username'] as String? ?? '').toLowerCase();
          return fullName.contains(lowerQuery) || username.contains(lowerQuery);
        }).toList();
      }
    });
  }

  Future<void> _toggleFollow(String userId, bool isFollowing) async {
    final currentUserId = Supabase.instance.client.auth.currentUser?.id;
    if (currentUserId == null) return;

    setState(() => _isLoadingFollow[userId] = true);

    try {
      if (isFollowing) {
        // Takipten çıkar
        await Supabase.instance.client
            .from('follows')
            .delete()
            .eq('follower_id', currentUserId)
            .eq('following_id', userId);
      } else {
        // Takip et
        await Supabase.instance.client.from('follows').insert({
          'follower_id': currentUserId,
          'following_id': userId,
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      if (mounted) {
        setState(() {
          if (isFollowing) {
            _followingIds.remove(userId);
          } else {
            _followingIds.add(userId);
          }
          _isLoadingFollow[userId] = false;
        });
      }
    } catch (e) {
      debugPrint('Takip hatası: $e');
      if (mounted) {
        setState(() => _isLoadingFollow[userId] = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(isFollowing ? 'Takipten çıkarılamadı' : 'Takip edilemedi'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  DateTime? _parseDateTime(dynamic value) {
    if (value == null) return null;
    try {
      if (value is String) return DateTime.parse(value);
      if (value is DateTime) return value;
    } catch (e) {
      debugPrint('DateTime parse hatası: $e');
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Arkadaş Ekle'),
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 2,
      ),
      body: Column(
        children: [
          // Arama çubuğu
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  offset: const Offset(0, 2),
                  blurRadius: 4,
                  color: Colors.black.withOpacity(0.08),
                ),
              ],
            ),
            child: TextField(
              onChanged: _filterUsers,
              decoration: InputDecoration(
                hintText: 'İsim veya kullanıcı adı ara...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.grey),
                        onPressed: () {
                          _filterUsers('');
                          FocusScope.of(context).unfocus();
                        },
                      )
                    : null,
                filled: true,
                fillColor: Colors.grey[100],
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
          // Kullanıcı listesi
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredUsers.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.person_search,
                              size: 64,
                              color: Colors.grey[400],
                            ),
                            const SizedBox(height: 16),
                            Text(
                              _searchQuery.isEmpty
                                  ? 'Henüz kullanıcı yok'
                                  : '"$_searchQuery" bulunamadı',
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadUsers,
                        child: ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: _filteredUsers.length,
                          itemBuilder: (context, index) {
                            final user = _filteredUsers[index];
                            return _buildUserTile(user);
                          },
                        ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildUserTile(Map<String, dynamic> user) {
    final userId = user['id'] as String;
    final avatarUrl = user['avatar_url'] as String?;
    final fullName = user['full_name'] as String? ?? 'Kullanıcı';
    final username = user['username'] as String?;
    final bio = user['bio'] as String?;
    final isActive = user['_isActive'] as bool? ?? false;
    final isFollowing = _followingIds.contains(userId);
    final isFollowLoading = _isLoadingFollow[userId] == true;

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => UserProfileScreen(userId: userId),
          ),
        ).then((_) {
          // Profil ekranından dönünce takip durumunu güncelle
          _loadUsers();
        });
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            // Avatar
            Stack(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: Colors.deepPurple[100],
                  backgroundImage: avatarUrl != null ? NetworkImage(avatarUrl) : null,
                  child: avatarUrl == null
                      ? Text(
                          fullName.isNotEmpty ? fullName[0].toUpperCase() : '?',
                          style: TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                            color: Colors.deepPurple[700],
                          ),
                        )
                      : null,
                ),
                if (isActive)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: const BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.fromBorderSide(
                          BorderSide(color: Colors.white, width: 2),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 12),
            // İsim ve kullanıcı adı
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    fullName,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (username != null && username.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      '@$username',
                      style: TextStyle(
                        fontSize: 13,
                        color: Colors.grey[600],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  if (isActive)
                    Text(
                      'Çevrimiçi',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.green[700],
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  if (bio != null && bio.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      bio,
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                        fontStyle: FontStyle.italic,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Takip et / Takipte butonu (Instagram tarzı)
            _buildFollowButton(userId, isFollowing, isFollowLoading),
          ],
        ),
      ),
    );
  }

  Widget _buildFollowButton(String userId, bool isFollowing, bool isLoading) {
    if (isLoading) {
      return const SizedBox(
        width: 24,
        height: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }

    if (isFollowing) {
      // Takip ediliyor durumu - gri buton
      return OutlinedButton(
        onPressed: () => _toggleFollow(userId, true),
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.grey[700],
          side: BorderSide(color: Colors.grey[300]!),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          minimumSize: const Size(90, 32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: const Text(
          'Takipte',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      );
    } else {
      // Takip et butonu - mavi buton (Instagram tarzı)
      return ElevatedButton(
        onPressed: () => _toggleFollow(userId, false),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF0095F6), // Instagram blue
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          minimumSize: const Size(90, 32),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          elevation: 0,
        ),
        child: const Text(
          'Takip Et',
          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        ),
      );
    }
  }
}