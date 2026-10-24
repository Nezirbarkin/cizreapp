import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../market/services/shop_review_service.dart';
import '../../market/services/product_review_service.dart';
import '../../../core/models/shop_review_model.dart';
import '../../../core/models/product_review_model.dart';
import '../widgets/common/seller_empty_state.dart';
import '../widgets/common/seller_list_skeleton.dart';
import '../widgets/common/seller_section_card.dart';
import '../../../core/utils/image_url.dart';

class SellerReviewsScreen extends StatefulWidget {
  const SellerReviewsScreen({super.key});

  @override
  State<SellerReviewsScreen> createState() => _SellerReviewsScreenState();
}

class _SellerReviewsScreenState extends State<SellerReviewsScreen> {
  /// Supabase client'ı güvenli şekilde al (lazy)
  SupabaseClient get _supabase {
    try {
      return Supabase.instance.client;
    } catch (e) {
      debugPrint('⚠️ Supabase henüz başlatılmadı: $e');
      rethrow;
    }
  }
  final _reviewService = ShopReviewService();
  final _productReviewService = ProductReviewService();

  bool _isLoading = true;
  List<ShopReview> _reviews = [];
  Map<String, dynamic>? _shopInfo;
  Map<String, dynamic>? _stats;

  // "Ürün yorumları" sekmesi: ilk açılışta yüklenir.
  bool _showProductReviews = false;
  bool _loadingProductReviews = false;
  List<ProductReview>? _productReviews;
  final Set<String> _replyBusy = {};

  @override
  void initState() {
    super.initState();
    _loadReviews();
  }

  /// UTC tarihi Türkiye saatine çevir
  DateTime _toTurkeyTime(DateTime utcDate) {
    // UTC zaten ise, UTC+3 ekle
    return utcDate.add(const Duration(hours: 3));
  }

  /// Tarih formatla (timeago benzeri) - Türkiye saati
  String _formatTimeAgo(DateTime dateTime) {
    // Tarih UTC ise Türkiye saatine çevir
    final turkeyTime = dateTime.isUtc ? _toTurkeyTime(dateTime) : dateTime;
    final now = DateTime.now();
    final difference = now.difference(turkeyTime);

    if (difference.inDays > 365) {
      final years = (difference.inDays / 365).floor();
      return '$years yıl önce';
    } else if (difference.inDays > 30) {
      final months = (difference.inDays / 30).floor();
      return '$months ay önce';
    } else if (difference.inDays > 7) {
      final weeks = (difference.inDays / 7).floor();
      return '$weeks hafta önce';
    } else if (difference.inDays > 0) {
      return '${difference.inDays} gün önce';
    } else if (difference.inHours > 0) {
      return '${difference.inHours} saat önce';
    } else if (difference.inMinutes > 0) {
      return '${difference.inMinutes} dakika önce';
    } else {
      return 'Az önce';
    }
  }

  /// Tam tarih formatla - Türkiye saati (örn: 05.02.2026 23:37)
  String _formatFullDate(DateTime dateTime) {
    final turkeyTime = dateTime.isUtc ? _toTurkeyTime(dateTime) : dateTime;
    final day = turkeyTime.day.toString().padLeft(2, '0');
    final month = turkeyTime.month.toString().padLeft(2, '0');
    final year = turkeyTime.year;
    final hour = turkeyTime.hour.toString().padLeft(2, '0');
    final minute = turkeyTime.minute.toString().padLeft(2, '0');
    return '$day.$month.$year $hour:$minute';
  }

  Future<void> _loadReviews() async {
    setState(() => _isLoading = true);

    try {
      final userId = _supabase.auth.currentUser?.id;
      if (userId == null) return;

      // Satıcının mağazasını bul
      final shopResponse = await _supabase
          .from('shops')
          .select('id, name, rating, total_reviews')
          .eq('owner_id', userId)
          .maybeSingle();

      if (shopResponse == null) {
        setState(() {
          _isLoading = false;
          _shopInfo = null;
        });
        return;
      }

      _shopInfo = Map<String, dynamic>.from(shopResponse);

      // Yorumları yükle
      _reviews = await _reviewService.getSellerShopReviews(shopResponse['id']);

      // İstatistikleri hesapla
      _calculateStats();

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Yorumlar yüklenirken hata: $e');
      setState(() => _isLoading = false);
    }
  }

  void _calculateStats() {
    if (_reviews.isEmpty) {
      _stats = {
        'total': 0,
        'averageRating': 0.0,
        'withReply': 0,
        'withoutReply': 0,
        'distribution': {1: 0, 2: 0, 3: 0, 4: 0, 5: 0},
      };
      return;
    }

    int withReply = 0;
    double totalRating = 0;
    Map<int, int> distribution = {1: 0, 2: 0, 3: 0, 4: 0, 5: 0};

    for (var review in _reviews) {
      if (review.hasSellerReply) withReply++;
      totalRating += review.rating;
      distribution[review.rating] = (distribution[review.rating] ?? 0) + 1;
    }

    _stats = {
      'total': _reviews.length,
      'averageRating': totalRating / _reviews.length,
      'withReply': withReply,
      'withoutReply': _reviews.length - withReply,
      'distribution': distribution,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Yorumlar'),
      ),
      body: _isLoading
          ? const SellerListSkeleton()
          : _shopInfo == null
              ? _buildNoShopView()
              : RefreshIndicator(
                  onRefresh: () => _showProductReviews ? _loadProductReviews() : _loadReviews(),
                  child: _buildContent(),
                ),
    );
  }

  Widget _buildNoShopView() {
    return const SellerEmptyState(
      icon: Icons.store_outlined,
      message: 'Mağaza bulunamadı',
    );
  }

  Future<void> _loadProductReviews() async {
    final shopId = _shopInfo?['id'] as String?;
    if (shopId == null) return;
    setState(() => _loadingProductReviews = true);
    try {
      final list = await _productReviewService.getSellerProductReviews(shopId);
      if (!mounted) return;
      setState(() {
        _productReviews = list;
        _loadingProductReviews = false;
      });
    } catch (e) {
      debugPrint('Ürün yorumları yüklenemedi: $e');
      if (mounted) setState(() => _loadingProductReviews = false);
    }
  }

  Widget _buildModeSwitch() {
    return SegmentedButton<bool>(
      segments: const [
        ButtonSegment(value: false, icon: Icon(Icons.storefront_outlined), label: Text('Mağaza')),
        ButtonSegment(value: true, icon: Icon(Icons.inventory_2_outlined), label: Text('Ürünler')),
      ],
      selected: {_showProductReviews},
      onSelectionChanged: (s) {
        setState(() => _showProductReviews = s.first);
        if (s.first && _productReviews == null) _loadProductReviews();
      },
    );
  }

  /// Ürün yorumuna cevap yaz / düzenle / sil (yorum sahibine bildirim gider).
  Future<void> _replyToProductReview(ProductReview review) async {
    final controller = TextEditingController(text: review.sellerReply ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(review.hasSellerReply ? 'Cevabı düzenle' : 'Yoruma cevap ver'),
        content: TextField(
          controller: controller,
          autofocus: true,
          minLines: 3,
          maxLines: 6,
          maxLength: 1000,
          decoration: const InputDecoration(
            hintText: 'Müşterine teşekkür et ya da sorununu çöz…',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          if (review.hasSellerReply)
            TextButton(
              onPressed: () => Navigator.pop(ctx, ''),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('Cevabı sil'),
            ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Vazgeç')),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isNotEmpty) Navigator.pop(ctx, text);
            },
            child: const Text('Gönder'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (result == null || !mounted || !_replyBusy.add(review.id)) return;
    setState(() {});
    try {
      await _productReviewService.addSellerReply(reviewId: review.id, reply: result);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result.isEmpty ? 'Cevap silindi' : 'Cevabın gönderildi')),
      );
      await _loadProductReviews();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cevap kaydedilemedi: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _replyBusy.remove(review.id));
    }
  }

  Widget _buildProductReviewCard(ProductReview review) {
    return SellerSectionCard(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if ((review.productName ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                children: [
                  Icon(Icons.inventory_2_outlined, size: 14, color: Colors.grey.shade600),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      review.productName!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade700, fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Text(
                  review.userName ?? 'Müşteri',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Text(review.starDisplay, style: const TextStyle(color: Colors.amber)),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            _formatFullDate(review.createdAt),
            style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
          ),
          if ((review.comment ?? '').isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(review.comment!),
          ],
          if (review.helpfulCount > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(Icons.thumb_up_alt_outlined, size: 14, color: Colors.green.shade700),
                const SizedBox(width: 4),
                Text(
                  '${review.helpfulCount} kişi yararlı buldu',
                  style: TextStyle(fontSize: 12, color: Colors.green.shade700),
                ),
              ],
            ),
          ],
          if (review.hasSellerReply) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(review.sellerReply!, style: const TextStyle(fontSize: 13)),
            ),
          ],
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _replyBusy.contains(review.id) ? null : () => _replyToProductReview(review),
              icon: const Icon(Icons.reply_rounded, size: 18),
              label: Text(review.hasSellerReply ? 'Cevabı düzenle' : 'Cevap ver'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductReviewsContent() {
    final list = _productReviews;
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _buildModeSwitch(),
          ),
        ),
        if (_loadingProductReviews && list == null)
          const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
        else if (list == null || list.isEmpty)
          const SliverFillRemaining(
            child: SellerEmptyState(
              icon: Icons.rate_review_outlined,
              message: 'Ürünlerine henüz yorum yapılmadı',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildProductReviewCard(list[index]),
                childCount: list.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildContent() {
    if (_showProductReviews) return _buildProductReviewsContent();
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: _buildModeSwitch(),
          ),
        ),
        // İstatistikler
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                _buildStatsCard(),
                const SizedBox(height: 16),
                _buildRatingDistribution(),
              ],
            ),
          ),
        ),

        // Yorumlar listesi
        if (_reviews.isEmpty)
          const SliverFillRemaining(
            child: SellerEmptyState(
              icon: Icons.rate_review_outlined,
              message: 'Henüz yorum yok',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.all(16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => _buildReviewCard(_reviews[index]),
                childCount: _reviews.length,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildStatsCard() {
    return SellerSectionCard(
      margin: EdgeInsets.zero,
      child: Row(
        children: [
          Icon(Icons.star, color: Colors.amber, size: 40),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (_stats?['averageRating'] ?? 0.0).toStringAsFixed(1),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                '${_stats?['total'] ?? 0} değerlendirme',
                style: TextStyle(color: Colors.grey.shade600),
              ),
            ],
          ),
          const Spacer(),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.green, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '${_stats?['withReply'] ?? 0} cevaplandı',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.pending, color: Colors.orange, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    '${_stats?['withoutReply'] ?? 0} bekliyor',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRatingDistribution() {
    final distribution = _stats?['distribution'] as Map<int, int>? ?? {};
    final total = _stats?['total'] as int? ?? 1;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Puan Dağılımı',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...List.generate(5, (index) {
              final star = 5 - index;
              final count = distribution[star] ?? 0;
              final percentage = total > 0 ? (count / total) : 0.0;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Text('$star'),
                    const SizedBox(width: 4),
                    Icon(Icons.star, color: Colors.amber, size: 16),
                    const SizedBox(width: 8),
                    Expanded(
                      child: LinearProgressIndicator(
                        value: percentage,
                        backgroundColor: Colors.grey.shade200,
                        valueColor: AlwaysStoppedAnimation(Colors.amber),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 30,
                      child: Text(
                        '$count',
                        textAlign: TextAlign.right,
                        style: TextStyle(color: Colors.grey.shade600),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _buildReviewCard(ShopReview review) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Kullanıcı bilgisi ve puan
            Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundImage: review.userAvatar != null
                      ? avatarImage(review.userAvatar!)
                      : null,
                  child: review.userAvatar == null
                      ? const Icon(Icons.person)
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        review.userName ?? 'Kullanıcı',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      Text(
                        '${_formatTimeAgo(review.createdAt)} • ${_formatFullDate(review.createdAt)}',
                        style: TextStyle(
                          color: Colors.grey.shade600,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Row(
                  children: List.generate(
                    5,
                    (index) => Icon(
                      index < review.rating ? Icons.star : Icons.star_border,
                      color: Colors.amber,
                      size: 18,
                    ),
                  ),
                ),
              ],
            ),

            // Yorum
            if (review.comment != null && review.comment!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                review.comment!,
                style: const TextStyle(fontSize: 14),
              ),
            ],

            // Satıcı cevabı
            if (review.hasSellerReply) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.store, size: 16, color: Colors.orange.shade700),
                        const SizedBox(width: 6),
                        Text(
                          'Satıcı Cevabı',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.orange.shade700,
                            fontSize: 13,
                          ),
                        ),
                        const Spacer(),
                        if (review.sellerRepliedAt != null)
                          Text(
                            _formatTimeAgo(review.sellerRepliedAt!),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade600,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      review.sellerReply!,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ],

            // Aksiyon butonları
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (!review.hasSellerReply)
                  OutlinedButton.icon(
                    onPressed: () => _showReplyDialog(review),
                    icon: const Icon(Icons.reply, size: 16),
                    label: const Text('Cevapla'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Theme.of(context).colorScheme.primary,
                    ),
                  )
                else
                  Row(
                    children: [
                      TextButton.icon(
                        onPressed: () => _showReplyDialog(review),
                        icon: const Icon(Icons.edit, size: 16),
                        label: const Text('Düzenle'),
                      ),
                      TextButton.icon(
                        onPressed: () => _deleteReply(review),
                        icon: const Icon(Icons.delete, size: 16),
                        label: const Text('Sil'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showReplyDialog(ShopReview review) {
    final controller = TextEditingController(text: review.sellerReply ?? '');
    final primary = Theme.of(context).colorScheme.primary;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(review.hasSellerReply ? 'Cevabı Düzenle' : 'Cevap Ver'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            hintText: 'Cevabınızı yazın...',
            border: OutlineInputBorder(),
          ),
          maxLines: 4,
          textCapitalization: TextCapitalization.sentences,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final reply = controller.text.trim();
              if (reply.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Lütfen bir cevap yazın')),
                );
                return;
              }

              try {
                await _reviewService.addSellerReply(
                  reviewId: review.id,
                  reply: reply,
                );

                if (context.mounted) {
                  final messenger = ScaffoldMessenger.of(context);
                  Navigator.pop(context);
                  messenger.showSnackBar(
                    const SnackBar(
                      content: Text('Cevabınız kaydedildi'),
                      backgroundColor: Colors.green,
                    ),
                  );
                  _loadReviews();
                }
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Hata: $e')),
                  );
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteReply(ShopReview review) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Cevabı Sil'),
        content: const Text('Cevabınızı silmek istediğinizden emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await _reviewService.deleteSellerReply(review.id);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Cevap silindi'),
              backgroundColor: Colors.green,
            ),
          );
          _loadReviews();
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Hata: $e')),
          );
        }
      }
    }
  }
}
