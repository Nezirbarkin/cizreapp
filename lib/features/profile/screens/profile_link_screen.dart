import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/image_url.dart';
import '../../social/services/social_share_service.dart';
import 'user_profile_screen.dart';

/// Paylaşılan profil linki: `https://cizreapp.com/u/@<kullanıcıadı>`.
///
/// Kullanıcı adı `public_profile_by_username` RPC'siyle çözülür (misafir de
/// çağırabilir; eskiden misafir `profiles`'ı okuyamadığı için web'de
/// "Bir hata oluştu" görünüyordu).
/// * Üye: bu ekran [UserProfileScreen] ile değiştirilir.
/// * Misafir: herkese açık profil kartı (ad, kullanıcı adı, biyografi,
///   sayılar) + giriş çağrısı. Hayalet/silinmiş/engelli hesap "bulunamadı".
class ProfileLinkScreen extends StatefulWidget {
  final String username;

  const ProfileLinkScreen({super.key, required this.username});

  @override
  State<ProfileLinkScreen> createState() => _ProfileLinkScreenState();
}

class _ProfileLinkScreenState extends State<ProfileLinkScreen> {
  bool _loading = true;
  Map<String, dynamic>? _profile;

  bool get _isGuest => Supabase.instance.client.auth.currentUser == null;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    setState(() => _loading = true);
    Map<String, dynamic>? profile;
    try {
      final data = await Supabase.instance.client.rpc(
        'public_profile_by_username',
        params: {'p_username': widget.username},
      );
      if (data is Map) profile = Map<String, dynamic>.from(data);
    } catch (e) {
      debugPrint('Profil linki çözülemedi: $e');
    }
    if (!mounted) return;

    final userId = profile?['id'] as String?;
    if (userId != null && !_isGuest) {
      _openProfile(userId);
      return;
    }
    setState(() {
      _profile = profile;
      _loading = false;
    });
  }

  /// İlk ekransa (web'de doğrudan linkle açılış) altına ana ekran konur.
  void _openProfile(String userId) {
    final navigator = Navigator.of(context);
    final route = MaterialPageRoute(builder: (_) => UserProfileScreen(userId: userId));
    if (navigator.canPop()) {
      navigator.pushReplacement(route);
    } else {
      navigator.pushReplacementNamed('/main');
      navigator.push(route);
    }
  }

  void _goHome() {
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      navigator.pushReplacementNamed('/main');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        title: Text('@${widget.username}'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goHome,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _profile == null
              ? _buildNotFound()
              : _buildPreview(_profile!),
    );
  }

  Widget _buildNotFound() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.person_off_outlined, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 14),
            const Text(
              'Kullanıcı bulunamadı',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              'Hesap kaldırılmış ya da kullanıcı adı değişmiş olabilir.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 18),
            OutlinedButton(onPressed: _goHome, child: const Text('Ana sayfa')),
          ],
        ),
      ),
    );
  }

  Widget _buildPreview(Map<String, dynamic> p) {
    final username = p['username']?.toString() ?? widget.username;
    final fullName = (p['full_name']?.toString().trim().isNotEmpty ?? false)
        ? p['full_name'].toString().trim()
        : '@$username';
    final bio = p['bio']?.toString().trim() ?? '';
    final avatar = p['avatar_url'] as String?;
    final isPrivate = p['profile_is_public'] == false;
    final verified = p['is_verified'] == true;

    Widget stat(String label, Object? value) => Expanded(
          child: Column(
            children: [
              Text(
                '${value ?? 0}',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 2),
              Text(label, style: TextStyle(fontSize: 12.5, color: Colors.grey.shade600)),
            ],
          ),
        );

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            children: [
              CircleAvatar(
                radius: 44,
                backgroundColor: Colors.grey.shade200,
                backgroundImage: avatarImage(avatar),
                child: avatarImage(avatar) == null
                    ? Text(
                        username.isNotEmpty ? username.characters.first.toUpperCase() : '?',
                        style: TextStyle(fontSize: 30, color: Colors.grey.shade600),
                      )
                    : null,
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Flexible(
                    child: Text(
                      fullName,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                    ),
                  ),
                  if (verified) ...[
                    const SizedBox(width: 5),
                    const Icon(Icons.verified, size: 18, color: Color(0xFF1D9BF0)),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text('@$username', style: TextStyle(color: Colors.grey.shade600)),
              if (bio.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(bio, textAlign: TextAlign.center),
              ],
              const SizedBox(height: 16),
              Row(
                children: [
                  stat('Gönderi', p['posts']),
                  stat('Takipçi', p['followers']),
                  stat('Takip', p['following']),
                ],
              ),
              if (isPrivate) ...[
                const SizedBox(height: 14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.lock_outline, size: 16, color: Colors.grey.shade600),
                    const SizedBox(width: 6),
                    Text(
                      'Bu hesap gizli',
                      style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pushNamed('/login'),
          icon: const Icon(Icons.login_rounded, size: 18),
          label: Text(isPrivate ? 'Takip isteği için giriş yap' : 'Takip etmek için giriş yap'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: () => SocialShareService().shareProfile(
            username: username,
            fullName: p['full_name']?.toString(),
          ),
          icon: const Icon(Icons.ios_share, size: 18),
          label: const Text('Profili paylaş'),
        ),
      ],
    );
  }
}
