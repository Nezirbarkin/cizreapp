import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../profile/screens/user_profile_screen.dart';

class PostLikesScreen extends StatefulWidget {
  final String postId;

  const PostLikesScreen({
    super.key,
    required this.postId,
  });

  @override
  State<PostLikesScreen> createState() => _PostLikesScreenState();
}

class _PostLikesScreenState extends State<PostLikesScreen> {
  List<Map<String, dynamic>> _likes = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadLikes();
  }

  Future<void> _loadLikes() async {
    try {
      final response = await Supabase.instance.client
          .from('post_likes')
          .select('''
            user_id,
            created_at,
            profiles:user_id (
              id,
              username,
              full_name,
              avatar_url
            )
          ''')
          .eq('post_id', widget.postId)
          .order('created_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _likes = List<Map<String, dynamic>>.from(response);
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Beğeniler yüklenirken hata: $e');
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Beğeniler'),
        elevation: 0,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _likes.isEmpty
              ? const Center(
                  child: Text('Henüz beğeni yok'),
                )
              : ListView.builder(
                  itemCount: _likes.length,
                  itemBuilder: (context, index) {
                    final like = _likes[index];
                    // Profili silinmiş kullanıcılarda embed null gelir;
                    // eskiden burada null dereference ile TÜM liste
                    // (kırmızı hata ekranı olarak) çöküyordu.
                    final profile = like['profiles'] as Map<String, dynamic>?;
                    final username =
                        (profile?['username'] as String?)?.trim().isNotEmpty == true
                            ? profile!['username'] as String
                            : 'kullanici';
                    final fullName =
                        (profile?['full_name'] as String?)?.trim().isNotEmpty == true
                            ? profile!['full_name'] as String
                            : username;
                    final avatarUrl = profile?['avatar_url'] as String?;
                    final likeUserId =
                        (profile?['id'] as String?) ?? like['user_id'] as String?;

                    return ListTile(
                      leading: CircleAvatar(
                        backgroundImage: avatarUrl != null
                            ? NetworkImage(avatarUrl)
                            : null,
                        backgroundColor: Theme.of(context).colorScheme.primary,
                        child: avatarUrl == null
                            ? Text(
                                username.isNotEmpty
                                    ? username.substring(0, 1).toUpperCase()
                                    : '?',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                      ),
                      title: Text(
                        fullName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('@$username'),
                      onTap: likeUserId == null
                          ? null
                          : () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) =>
                                      UserProfileScreen(userId: likeUserId),
                                ),
                              );
                            },
                    );
                  },
                ),
    );
  }
}
