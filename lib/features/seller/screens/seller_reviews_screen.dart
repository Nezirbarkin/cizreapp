import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../market/services/shop_review_service.dart';
import '../../../core/models/shop_review_model.dart';

class SellerReviewsScreen extends StatefulWidget {
  const SellerReviewsScreen({super.key});

  @override
  State<SellerReviewsScreen> createState() => _SellerReviewsScreenState();
}

class _SellerReviewsScreenState extends State<SellerReviewsScreen> {
  final _supabase = Supabase.instance.client;
  final _reviewService = ShopReviewService();
  
  bool _isLoading = true;
  List<ShopReview> _reviews = [];
  Map<String, dynamic>? _shopInfo;
  Map<String, dynamic>? _stats;

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
        title: const Text('Mağaza Yorumları'),
        backgroundColor: Colors.orange.shade700,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _shopInfo == null
              ? _buildNoShopView()
              : RefreshIndicator(
                  onRefresh: _loadReviews,
                  child: _buildContent(),
                ),
    );
  }

  Widget _buildNoShopView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.store_outlined, size: 80, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              'Mağaza bulunamadı',
              style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return CustomScrollView(
      slivers: [
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
          SliverFillRemaining(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.rate_review_outlined,
                      size: 64, color: Colors.grey.shade400),
                  const SizedBox(height: 16),
                  Text(
                    'Henüz yorum yok',
                    style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
                  ),
                ],
              ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
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
          ],
        ),
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
                      ? NetworkImage(review.userAvatar!)
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
                      foregroundColor: Colors.orange.shade700,
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
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
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
              backgroundColor: Colors.orange.shade700,
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
