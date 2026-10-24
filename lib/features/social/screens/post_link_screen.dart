import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/models/post_model.dart';
import '../services/post_service.dart';
import '../widgets/social_post_card.dart';
import 'post_detail_screen.dart';

/// Paylaşılan gönderi linki: `https://cizreapp.com/post/<id>` (web adres
/// çubuğu, uygulama linki ya da `onGenerateRoute('/post/<id>')`).
///
/// * Üye: gönderi yüklenir ve bu ekran [PostDetailScreen] ile değiştirilir
///   (görünürlük RLS'te: gizli hesap / engel varsa "görüntülenemiyor").
/// * Misafir: `public_post_by_id` RPC'sinden salt-okunur önizleme + giriş
///   çağrısı. RPC, Keşfet'in misafir anahtarı kapalıysa ya da yazar gizli
///   hesapsa boş döner.
class PostLinkScreen extends StatefulWidget {
  final String postId;

  const PostLinkScreen({super.key, required this.postId});

  @override
  State<PostLinkScreen> createState() => _PostLinkScreenState();
}

class _PostLinkScreenState extends State<PostLinkScreen> {
  bool _loading = true;
  bool _notFound = false;
  Post? _guestPost;

  bool get _isGuest => Supabase.instance.client.auth.currentUser == null;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    setState(() {
      _loading = true;
      _notFound = false;
    });
    try {
      if (!_isGuest) {
        final post = await PostService().getPostById(widget.postId);
        if (!mounted) return;
        if (post == null) {
          setState(() {
            _loading = false;
            _notFound = true;
          });
          return;
        }
        _openDetail(post);
        return;
      }

      final rows = await Supabase.instance.client.rpc<List<dynamic>>(
        'public_post_by_id',
        params: {'p_post_id': widget.postId},
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _guestPost = rows.isEmpty
            ? null
            : Post.fromJson((rows.first as Map).cast<String, dynamic>());
        _notFound = _guestPost == null;
      });
    } catch (e) {
      debugPrint('Gönderi linki çözülemedi: $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _notFound = true;
      });
    }
  }

  /// Bu ekranı detay ile değiştirir. Uygulamanın ilk ekranıysa (web'de
  /// doğrudan linkle açılış) altına ana ekran konur: geri tuşu boşluğa
  /// değil ana sayfaya dönsün.
  void _openDetail(Post post) {
    final navigator = Navigator.of(context);
    final route = MaterialPageRoute(builder: (_) => PostDetailScreen(post: post));
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

  void _askLogin() {
    final navigator = Navigator.of(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Beğenmek, yorum yapmak ve paylaşmak için giriş yap'),
        action: SnackBarAction(
          label: 'Giriş Yap',
          onPressed: () {
            if (navigator.mounted) navigator.pushNamed('/login');
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F8),
      appBar: AppBar(
        title: const Text('Gönderi'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _goHome,
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _notFound
              ? _buildNotFound()
              : _buildGuestPreview(_guestPost!),
    );
  }

  Widget _buildNotFound() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported_outlined, size: 56, color: Colors.grey.shade400),
            const SizedBox(height: 14),
            const Text(
              'Bu gönderi artık görüntülenemiyor',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              _isGuest
                  ? 'Silinmiş ya da gizli bir hesaba ait olabilir. Giriş yapıp tekrar deneyebilirsin.'
                  : 'Silinmiş ya da gizli bir hesaba ait olabilir.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 18),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (_isGuest)
                  FilledButton(
                    onPressed: () => Navigator.of(context).pushNamed('/login'),
                    child: const Text('Giriş Yap'),
                  ),
                OutlinedButton(onPressed: _goHome, child: const Text('Ana sayfa')),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuestPreview(Post post) {
    final name = (post.authorFullName?.trim().isNotEmpty ?? false)
        ? post.authorFullName!.trim()
        : (post.authorUsername ?? 'CizreApp kullanıcısı');
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 24),
      children: [
        SocialPostCard(
          post: post,
          fullName: name,
          username: post.authorUsername ?? 'kullanici',
          avatarUrl: post.authorAvatarUrl,
          authorRole: AuthorRole.unknown,
          isVerified: post.authorIsVerified,
          showPrivilegeBadges: false,
          onTap: _askLogin,
          onAuthorTap: _askLogin,
          onLike: _askLogin,
          onComment: _askLogin,
          onSend: _askLogin,
          onSave: _askLogin,
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              const Text(
                'Yorumları görmek ve katılmak için giriş yap',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pushReplacementNamed('/main'),
                      child: const Text("Keşfet'e göz at"),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.of(context).pushNamed('/login'),
                      child: const Text('Giriş Yap'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}
