import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/favorites_provider.dart';
// ignore: unused_import
import '../../../core/models/favorite_models.dart';
import '../../../core/models/product_model.dart';
import '../../../core/widgets/product_extras_widgets.dart';
import '../../../core/models/post_model.dart' show Post, firstNonEmpty;
import '../../market/screens/product_detail_screen.dart';
import '../../market/screens/my_price_alerts_screen.dart';
import '../../market/screens/flash_sales_screen.dart';
import '../../market/screens/live_sessions_screen.dart';
import '../../market/widgets/flash_sale_entry_banner.dart';
import '../../profile/screens/user_profile_screen.dart';
import '../../social/screens/post_detail_screen.dart';
import '../../social/services/post_service.dart';
import '../../social/widgets/social_post_card.dart';
import '../../social/widgets/send_to_friend_sheet.dart';
import '../../../shared/widgets/flash_discount_badge.dart';
import '../../market/widgets/flash_aware_price_row.dart';

/// Favorilerim Ekranı - Ürün ve Gönderi favorilerini gösterir
class FavoritesScreen extends StatefulWidget {
  const FavoritesScreen({super.key});

  @override
  State<FavoritesScreen> createState() => _FavoritesScreenState();
}

class _FavoritesScreenState extends State<FavoritesScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    // Favorileri yükle
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<FavoritesProvider>().loadFavorites();
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Favorilerim'),
        actions: [
          IconButton(
            icon: const Icon(Icons.live_tv_outlined),
            tooltip: 'Canlı Yayınlar',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const LiveSessionsScreen()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.notifications_active_outlined),
            tooltip: 'Fiyat Alarmlarım',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const MyPriceAlertsScreen()),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Ürünler', icon: Icon(Icons.shopping_bag_outlined)),
            Tab(text: 'Gönderiler', icon: Icon(Icons.article_outlined)),
          ],
        ),
      ),
      body: Column(
        children: [
          // Aktif flash sale varsa giriş bandı
          const FlashSaleEntryBanner(),
          // Tüm Flash Satışları gör butonu (her zaman görünür değil ama banner varsa
          // yeterli; banner yoksa kompakt bir link)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LiveSessionsScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.live_tv, size: 18, color: Colors.red),
                  label: const Text(
                    'Canlı Yayınlar',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
                const SizedBox(width: 8),
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const FlashSalesScreen(),
                      ),
                    );
                  },
                  icon: const Icon(Icons.flash_on, size: 18),
                  label: const Text('Flash Satışlar'),
                ),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: const [_ProductFavoritesTab(), _PostFavoritesTab()],
            ),
          ),
        ],
      ),
    );
  }
}

/// Ürün Favorileri Tab
class _ProductFavoritesTab extends StatelessWidget {
  const _ProductFavoritesTab();

  @override
  Widget build(BuildContext context) {
    return Consumer<FavoritesProvider>(
      builder: (context, favoritesProvider, child) {
        if (favoritesProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final favoriteProducts = favoritesProvider.favoriteProducts;

        if (favoriteProducts.isEmpty) {
          return _buildEmptyState(
            context,
            icon: Icons.favorite_border,
            title: 'Favori Ürün Yok',
            message: 'Beğendiğiniz ürünler burada görünecek',
          );
        }

        return RefreshIndicator(
          onRefresh: () => favoritesProvider.loadProductFavorites(),
          child: GridView.builder(
            padding: const EdgeInsets.all(16),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.75,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: favoriteProducts.length,
            itemBuilder: (context, index) {
              final product = favoriteProducts[index];
              return _ProductCard(product: product);
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Gönderi Favorileri Tab
class _PostFavoritesTab extends StatefulWidget {
  const _PostFavoritesTab();

  @override
  State<_PostFavoritesTab> createState() => _PostFavoritesTabState();
}

class _PostFavoritesTabState extends State<_PostFavoritesTab> {
  final PostService _postService = PostService();
  Map<String, bool> _likedPosts = {};
  String? _likedPostsLoadedFor;

  /// Görünen gönderi listesi değiştiğinde beğeni durumunu tek seferde
  /// toplu çeker (her build'de tekrar sorgulamamak için imza ile önbellekler).
  Future<void> _loadLikedStatus(List<Post> posts) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null || posts.isEmpty) return;
    final signature = posts.map((p) => p.id).join(',');
    if (_likedPostsLoadedFor == signature) return;
    _likedPostsLoadedFor = signature;

    final liked = await _postService.getLikedPostIds(
      userId,
      posts.map((p) => p.id).toList(),
    );
    if (mounted) {
      setState(() => _likedPosts = {for (final id in liked) id: true});
    }
  }

  Future<void> _toggleLike(Post post) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final isLiked = _likedPosts[post.id] ?? false;
    setState(() => _likedPosts[post.id] = !isLiked);

    try {
      if (isLiked) {
        await _postService.unlikePost(post.id, userId);
      } else {
        await _postService.likePost(post.id, userId);
      }
    } catch (e) {
      if (mounted) setState(() => _likedPosts[post.id] = isLiked);
    }
  }

  Future<void> _openPostDetail(Post post) async {
    // PostDetailScreen yorum sayısı değiştiyse 'updated' ile döner
    // (bkz. post_detail_screen.dart _commentsChanged); favori listesindeki
    // önbelleklenmiş yorum sayacını tazelemek için listeyi yeniden yükleriz.
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => PostDetailScreen(post: post)),
    );
    if (result == 'updated' && mounted) {
      context.read<FavoritesProvider>().loadPostFavorites();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<FavoritesProvider>(
      builder: (context, favoritesProvider, child) {
        if (favoritesProvider.isLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        final favoritePosts = favoritesProvider.favoritePosts;

        if (favoritePosts.isEmpty) {
          return _buildEmptyState(
            context,
            icon: Icons.favorite_border,
            title: 'Favori Gönderi Yok',
            message: 'Beğendiğiniz gönderiler burada görünecek',
          );
        }

        _loadLikedStatus(favoritePosts);

        return RefreshIndicator(
          onRefresh: () => favoritesProvider.loadPostFavorites(),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: favoritePosts.length,
            itemBuilder: (context, index) {
              final post = favoritePosts[index];
              final isOrphanPost = !post.authorProfileExists;
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: SocialPostCard(
                  post: post,
                  fullName: firstNonEmpty([
                    post.authorFullName,
                    post.authorUsername,
                  ]),
                  username: post.authorUsername ?? 'kullanici',
                  avatarUrl: post.authorAvatarUrl,
                  authorRole: post.authorRole,
                  isVerified: post.authorIsVerified,
                  showPrivilegeBadges: !isOrphanPost,
                  isLiked: _likedPosts[post.id] ?? false,
                  isSaved: true,
                  onTap: () => _openPostDetail(post),
                  onAuthorTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          UserProfileScreen(userId: post.userId),
                    ),
                  ),
                  onLike: () => _toggleLike(post),
                  onComment: () => _openPostDetail(post),
                  onSend: () => sendPostToFriend(context, post),
                  onSave: () =>
                      favoritesProvider.togglePostFavorite(post.id),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildEmptyState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              message,
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Ürün Kartı
class _ProductCard extends StatelessWidget {
  final Product product;

  const _ProductCard({required this.product});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ProductDetailScreen(productId: product.id),
        ),
      ),
      child: Card(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        elevation: 2,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Ürün Resmi
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  product.imageUrl != null
                      ? CachedNetworkImage(
                          imageUrl: product.imageUrl!,
                          fit: BoxFit.cover,
                          memCacheWidth: 400,
                          errorWidget: (context, url, error) {
                            return Container(
                              color: Colors.grey[200],
                              child: const Icon(
                                Icons.image_not_supported,
                                size: 48,
                                color: Colors.grey,
                              ),
                            );
                          },
                        )
                      : Container(
                          color: Colors.grey[200],
                          child: const Icon(
                            Icons.image,
                            size: 48,
                            color: Colors.grey,
                          ),
                        ),
                  // İndirim rozeti (flaş indirim veya normal indirim)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: FlashAwareDiscountBadge(
                      product: product,
                      compact: false,
                    ),
                  ),
                  // Kalp ikonu (favori)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        // ignore: deprecated_member_use
                        color: Colors.white.withOpacity(0.9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.favorite,
                        color: Colors.red,
                        size: 16,
                      ),
                    ),
                  ),
                  if (product.isBuy2Get1BalanceCampaign)
                    const Positioned(
                      bottom: 8,
                      left: 8,
                      child: CampaignBadge(),
                    ),
                  // Satıcı rozetleri + ücretsiz kargo
                  // Kampanya rozeti alt sol köşeyi kullandığı için o varken
                  // bir kat yukarı kayar.
                  Positioned(
                    bottom: product.isBuy2Get1BalanceCampaign ? 26 : 8,
                    left: 8,
                    right: 8,
                    child: ProductCardTagStrip(product: product),
                  ),
                ],
              ),
            ),
            // Ürün Bilgileri
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.name,
                    style: Theme.of(context).textTheme.titleSmall,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  if (product.category != null)
                    Text(
                      product.category!,
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: Colors.grey[600]),
                    ),
                  const SizedBox(height: 8),
                  // Fiyat (flaş indirim bilinçli)
                  FlashAwarePriceRow(
                    product: product,
                    priceStyle: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.bold,
                    ),
                    oldPriceStyle: TextStyle(
                      decoration: TextDecoration.lineThrough,
                      color: Colors.grey[600],
                      fontSize: 12,
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
}
