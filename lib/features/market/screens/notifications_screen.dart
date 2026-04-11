// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/models/notification_model.dart' as model;
import '../../../core/models/post_model.dart';
import '../../../core/services/notification_service.dart';
import '../../social/services/post_service.dart';
import '../../profile/screens/user_profile_screen.dart';
import '../../profile/services/follow_request_service.dart';
import '../../social/screens/post_detail_screen.dart';
import '../../social/screens/story_viewer_screen.dart';
import '../widgets/pending_review_dialog.dart';
import '../services/shop_review_service.dart';
import '../../shop/services/order_service.dart';
import '../../shop/screens/orders_screen.dart';
import '../../seller/screens/seller_orders_screen.dart';
import 'package:intl/intl.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  List<Map<String, dynamic>> _adminBroadcasts = [];
  final FollowRequestService _followRequestService = FollowRequestService();
  // Takip istekleri durumu (notification id -> status)
  final Map<String, String> _followRequestStatuses = {};

  bool _isLoading = true;
  final NotificationService _notificationService = NotificationService();
  List<model.NotificationModel> _notifications = [];
  // ignore: unused_field
  final PostService _postService = PostService();

  int _unreadCount = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  // Computed properties - bildirimleri ayır
  List<model.NotificationModel> get _followRequestNotifications {
    // Sadece henüz işlem yapılmamış (pending) takip istekleri
    return _notifications.where((n) => n.type == 'follow_request' && _followRequestStatuses[n.id] == null).toList();
  }

  List<model.NotificationModel> get _otherNotifications {
    // İşlem yapılmış takip istekleri dahil tüm diğer bildirimler
    return _notifications.where((n) => n.type != 'follow_request' || _followRequestStatuses[n.id] != null).toList();
  }

  Future<void> _loadData() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    
    setState(() => _isLoading = true);

    try {
      // Herkese açık admin duyurularını yükle (üye olmayan da görebilir)
      try {
        final broadcastsResponse = await Supabase.instance.client
            .from('admin_broadcasts')
            .select()
            .eq('is_active', true)
            .order('created_at', ascending: false)
            .limit(20);
        _adminBroadcasts = List<Map<String, dynamic>>.from(broadcastsResponse);
      } catch (e) {
        debugPrint('Admin broadcasts yüklenemedi (tablo yok olabilir): $e');
        _adminBroadcasts = [];
      }

      if (userId != null) {
        final notifications = await _notificationService.getNotifications(userId);
        final unreadCount = await _notificationService.getUnreadCount(userId);

        // Admin bildirimlerini kontrol et
        final adminNotifs = notifications.where((n) => n.entityId != null && n.entityId!.startsWith('admin_icon:')).toList();
        debugPrint('🔔 Toplam bildirim: ${notifications.length}');
        debugPrint('🔔 Admin bildirimleri: ${adminNotifs.length}');
        if (adminNotifs.isNotEmpty) {
          debugPrint('🔔 İlk admin bildirimi: ${adminNotifs.first.title}, entity_id: ${adminNotifs.first.entityId}');
        }

        if (mounted) {
          setState(() {
            _notifications = notifications;
            _unreadCount = unreadCount;
            _isLoading = false;
          });
        }

        // Follow request bildirimlerinin gerçek durumlarını kontrol et
        await _checkFollowRequestStatuses();
      } else {
        // Üye olmayan kullanıcı - sadece broadcasts gösterilecek
        if (mounted) {
          setState(() {
            _notifications = [];
            _unreadCount = 0;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Follow request bildirimlerinin follow_requests tablosundaki
  /// gerçek durumlarını kontrol eder. Onaylanmış/reddedilmiş istekler
  /// takip istekleri kartından çıkıp alttaki normal bildirimlere taşınır.
  Future<void> _checkFollowRequestStatuses() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    final followRequestNotifs = _notifications.where((n) => n.type == 'follow_request').toList();
    if (followRequestNotifs.isEmpty) return;

    try {
      for (final notif in followRequestNotifs) {
        if (notif.actorId == null) continue;
        // Zaten durumu biliyorsak tekrar sorgulamaya gerek yok
        if (_followRequestStatuses.containsKey(notif.id)) continue;

        final request = await Supabase.instance.client
            .from('follow_requests')
            .select('status')
            .eq('follower_id', notif.actorId!)
            .eq('following_id', userId)
            .maybeSingle();

        if (request != null && mounted) {
          final status = request['status'] as String?;
          if (status == 'accepted' || status == 'rejected') {
            setState(() {
              _followRequestStatuses[notif.id] = status!;
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Takip isteği durumları kontrol hatası: $e');
    }
  }

  Future<void> _markAsRead(model.NotificationModel notification) async {
    if (notification.isRead) return;

    try {
      await _notificationService.markAsRead(notification.id);
      
      if (mounted) {
        setState(() {
          // Okundu olarak işaretle
          final index = _notifications.indexWhere((n) => n.id == notification.id);
          if (index != -1) {
            _notifications[index] = model.NotificationModel(
              id: notification.id,
              userId: notification.userId,
              type: notification.type,
              title: notification.title,
              body: notification.body,
              actorId: notification.actorId,
              actorName: notification.actorName,
              actorAvatar: notification.actorAvatar,
              entityId: notification.entityId,
              entityType: notification.entityType,
              entityImage: notification.entityImage,
              metadata: notification.metadata,
              isRead: true,
              createdAt: notification.createdAt,
            );
          }
          if (_unreadCount > 0) {
            _unreadCount--;
          }
        });
      }
    } catch (e) {
      // Hata durumunda sessizce geç
    }
  }

  Future<void> _markAllAsRead() async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) return;

    try {
      await _notificationService.markAllAsRead(userId);
      
      if (mounted) {
        setState(() {
          // Tüm bildirimleri okundu yap
          _notifications = _notifications.map((n) => model.NotificationModel(
            id: n.id,
            userId: n.userId,
            type: n.type,
            title: n.title,
            body: n.body,
            actorId: n.actorId,
            actorName: n.actorName,
            actorAvatar: n.actorAvatar,
            entityId: n.entityId,
            entityType: n.entityType,
            entityImage: n.entityImage,
            metadata: n.metadata,
            isRead: true,
            createdAt: n.createdAt,
          )).toList();
          _unreadCount = 0;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İşlem başarısız: $e')),
        );
      }
    }
  }

  Future<void> _deleteNotification(model.NotificationModel notification) async {
    try {
      await _notificationService.deleteNotification(notification.id);
      
      if (mounted) {
        setState(() {
          _notifications.removeWhere((n) => n.id == notification.id);
          if (!notification.isRead && _unreadCount > 0) {
            _unreadCount--;
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Bildirim silinirken hata: $e')),
        );
      }
    }
  }

  Future<void> _handleFollowRequestAction(model.NotificationModel notification, bool accept) async {
    if (notification.actorId == null) return;
    
    try {
      // Önce follow_requests tablosundan ilgili isteğin ID'sini bul
      final currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (currentUserId == null) return;
      
      final request = await Supabase.instance.client
          .from('follow_requests')
          .select('id')
          .eq('follower_id', notification.actorId!)
          .eq('following_id', currentUserId)
          .eq('status', 'pending')
          .maybeSingle();
      
      if (request == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Takip isteği bulunamadı')),
          );
        }
        return;
      }
      
      final requestId = request['id'] as String;
      
      if (accept) {
        // Doğru requestId ile kabul et
        await _followRequestService.acceptFollowRequest(requestId);
        
        if (mounted) {
          setState(() {
            _followRequestStatuses[notification.id] = 'accepted';
            // Bildirim listede kalır ama takip istekleri kartından çıkar,
            // alttaki normal bildirimlerde "İstek onaylandı" olarak görünür
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Takip isteği kabul edildi'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      } else {
        // Doğru requestId ile reddet
        await _followRequestService.rejectFollowRequest(requestId);
        
        if (mounted) {
          setState(() {
            _followRequestStatuses[notification.id] = 'rejected';
            // Bildirim listede kalır ama takip istekleri kartından çıkar,
            // alttaki normal bildirimlerde "İstek reddedildi" olarak görünür
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('Takip isteği reddedildi'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('❌ Takip isteği işlem hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('İşlem başarısız: $e')),
        );
      }
    }
  }

  Future<void> _handleNotificationTap(model.NotificationModel notification) async {
    // Bildirimi okundu olarak işaretle
    await _markAsRead(notification);

    // Bildirim tipine göre yönlendir
    switch (notification.type) {
      case 'follow':
      case 'follow_request':
        // Takip/Takip isteği bildirimi - kullanıcı profiline git
        if (notification.actorId != null) {
          Navigator.push(
            // ignore: use_build_context_synchronously
            context,
            MaterialPageRoute(
              builder: (context) => UserProfileScreen(userId: notification.actorId!),
            ),
          );
        }
        break;

      case 'like':
        // Beğeni bildirimi - hikaye mi gönderi mi kontrol et
        if (notification.entityId != null) {
          try {
            // Önce story olup olmadığını kontrol et
            final storyData = await Supabase.instance.client
                .from('stories')
                .select()
                .eq('id', notification.entityId!)
                .maybeSingle();

            if (storyData != null) {
              // Story beğenisi - story viewer'a git
              final story = Story.fromJson(storyData);
              if (mounted) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => StoryViewerScreen(
                      stories: [story],
                      initialIndex: 0,
                    ),
                  ),
                );
              }
              return;
            }

            // Story değilse post kontrol et
            final postData = await Supabase.instance.client
                .from('posts')
                .select()
                .eq('id', notification.entityId!)
                .maybeSingle();

            if (postData == null) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('İçerik bulunamadı')),
                );
              }
              return;
            }

            // Post modelini oluştur
            final post = Post.fromJson(postData);
            
            if (mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PostDetailScreen(post: post),
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('İçerik yüklenirken hata: $e')),
              );
            }
          }
        }
        break;

      case 'comment':
        // Yorum bildirimi - gönderi detayına git
        if (notification.entityId != null) {
          try {
            // Post bilgilerini yükle
            final postData = await Supabase.instance.client
                .from('posts')
                .select()
                .eq('id', notification.entityId!)
                .maybeSingle();

            if (postData == null) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Gönderi bulunamadı')),
                );
              }
              return;
            }

            // Post modelini oluştur
            final post = Post.fromJson(postData);
            
            if (mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PostDetailScreen(post: post),
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Gönderi yüklenirken hata: $e')),
              );
            }
          }
        }
        break;

      case 'mention':
        // Mention bildirimi - gönderi detayına git (yorumda bahsedildi)
        if (notification.entityId != null) {
          try {
            // Post bilgilerini yükle
            final postData = await Supabase.instance.client
                .from('posts')
                .select()
                .eq('id', notification.entityId!)
                .maybeSingle();

            if (postData == null) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Gönderi bulunamadı')),
                );
              }
              return;
            }

            // Post modelini oluştur
            final post = Post.fromJson(postData);
            
            if (mounted) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PostDetailScreen(post: post),
                ),
              );
            }
          } catch (e) {
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Gönderi yüklenirken hata: $e')),
              );
            }
          }
        }
        break;

      case 'shop_review':
        // Yeni mağaza yorumu - satıcı paneli yorumlar ekranına git
        if (mounted) {
          Navigator.pushNamed(context, '/seller/reviews');
        }
        break;

      case 'shop_review_reply':
        // Satıcı cevabı - sipariş geçmişine git (kullanıcı için)
        if (mounted) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const OrdersScreen()));
        }
        break;

      case 'review_request':
      case 'review_pending':
        // Değerlendirme isteği - değerlendirme dialog'unu aç
        if (notification.entityId != null && mounted) {
          await _showReviewDialogForOrder(notification.entityId!);
        }
        break;

      case 'order_update':
      case 'order_status':
        // Sipariş durumu güncellendi - sipariş detayına git
        if (notification.entityId != null && !notification.entityId!.startsWith('admin_icon:') && mounted) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const OrdersScreen()));
        }
        break;

      case 'new_order':
        // Satıcıya yeni sipariş bildirimi - satıcı siparişlerine git
        if (mounted) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => const SellerOrdersScreen()));
        }
        break;

      default:
        // entity_id admin_icon: ile başlıyorsa admin bildirimidir, sadece okundu işaretle
        // Diğer bildirimler için sadece okundu işaretle
        break;
    }
  }

  /// Sipariş için değerlendirme dialog'unu aç
  Future<void> _showReviewDialogForOrder(String orderId) async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      // Sipariş detaylarını al
      final orderService = OrderService();
      final order = await orderService.getOrderById(orderId);
      
      if (order == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Sipariş bulunamadı')),
          );
        }
        return;
      }

      // Değerlendirme servisi ile bekleyen değerlendirmeleri al
      final reviewService = ShopReviewService();
      final pendingReviews = await reviewService.getPendingReviews(userId);
      
      // Bu sipariş için değerlendirme bilgisi bul
      final pendingReview = pendingReviews.firstWhere(
        (r) => r.orderId == orderId,
        orElse: () => PendingReview(
          orderId: order.id,
          shopId: order.shopId,
          shopName: order.shopName ?? 'Dükkan',
          shopLogo: null,
          orderDate: order.createdAt,
          deliveredAt: order.deliveredAt ?? DateTime.now(),
          productId: order.items.isNotEmpty ? order.items.first.productId : null,
          productName: order.items.isNotEmpty ? order.items.first.productName : null,
        ),
      );

      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (dialogContext) => PendingReviewDialog(
            pendingReview: pendingReview,
            onReviewSubmitted: () async {
              // Atlanan sipariş listesinden çıkar
              final prefs = await SharedPreferences.getInstance();
              final skippedOrders = prefs.getStringList('skipped_review_orders') ?? [];
              if (skippedOrders.contains(orderId)) {
                skippedOrders.remove(orderId);
                await prefs.setStringList('skipped_review_orders', skippedOrders);
              }
            },
            onSkipped: () async {
              // Atlandı olarak işaretle
              final prefs = await SharedPreferences.getInstance();
              final skippedOrders = prefs.getStringList('skipped_review_orders') ?? [];
              if (!skippedOrders.contains(orderId)) {
                skippedOrders.add(orderId);
                await prefs.setStringList('skipped_review_orders', skippedOrders);
              }
            },
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ Değerlendirme dialog açılırken hata: $e');
    }
  }

  IconData _getIconForNotification(model.NotificationModel notification) {
    // Admin bildirimi için entity_id'den ikon tipini kontrol et (format: "admin_icon:discount")
    if (notification.entityId != null && notification.entityId!.startsWith('admin_icon:')) {
      final iconType = notification.entityId!.replaceFirst('admin_icon:', '');
      return _getAdminNotificationIcon(iconType);
    }
    
    // Onaylanmış/reddedilmiş takip istekleri için farklı ikon
    if (notification.type == 'follow_request') {
      final reqStatus = _followRequestStatuses[notification.id];
      if (reqStatus == 'accepted') return Icons.how_to_reg;
      if (reqStatus == 'rejected') return Icons.person_off;
      return Icons.person_add_alt_1;
    }
    return _getIconForType(notification.type);
  }

  Color _getColorForNotification(model.NotificationModel notification) {
    // Admin bildirimi için entity_id'den renk tipini kontrol et
    if (notification.entityId != null && notification.entityId!.startsWith('admin_icon:')) {
      final iconType = notification.entityId!.replaceFirst('admin_icon:', '');
      return _getAdminNotificationColor(iconType);
    }
    
    // Onaylanmış/reddedilmiş takip istekleri için farklı renk
    if (notification.type == 'follow_request') {
      final reqStatus = _followRequestStatuses[notification.id];
      if (reqStatus == 'accepted') return Colors.green;
      if (reqStatus == 'rejected') return Colors.red.shade400;
      return Colors.orange;
    }
    return _getColorForType(notification.type);
  }

  /// Admin bildirim ikon tipinden IconData döndür
  IconData _getAdminNotificationIcon(String iconType) {
    switch (iconType) {
      case 'announcement':
        return Icons.campaign_rounded;
      case 'discount':
        return Icons.discount_rounded;
      case 'campaign':
        return Icons.local_offer_rounded;
      case 'news':
        return Icons.newspaper_rounded;
      case 'event':
        return Icons.event_rounded;
      case 'update':
        return Icons.system_update_rounded;
      case 'warning':
        return Icons.warning_amber_rounded;
      case 'gift':
        return Icons.card_giftcard_rounded;
      case 'info':
        return Icons.info_rounded;
      default:
        return Icons.campaign_rounded;
    }
  }

  /// Admin bildirim ikon tipinden renk döndür
  Color _getAdminNotificationColor(String iconType) {
    switch (iconType) {
      case 'announcement':
        return Colors.blue;
      case 'discount':
        return Colors.red;
      case 'campaign':
        return Colors.orange;
      case 'news':
        return Colors.teal;
      case 'event':
        return Colors.purple;
      case 'update':
        return Colors.green;
      case 'warning':
        return Colors.amber;
      case 'gift':
        return Colors.pink;
      case 'info':
        return Colors.indigo;
      default:
        return Colors.blue;
    }
  }

  IconData _getIconForType(String type) {
    switch (type) {
      case 'like':
      case 'post_like':
        return Icons.favorite;
      case 'comment':
      case 'post_comment':
        return Icons.chat_bubble;
      case 'follow':
      case 'new_follower':
        return Icons.person_add;
      case 'follow_request':
        return Icons.person_add_alt_1;
      case 'mention':
      case 'comment_mention':
        return Icons.alternate_email;
      case 'order':
        return Icons.shopping_cart;
      case 'order_update':
      case 'order_status':
        return Icons.local_shipping;
      case 'new_order':
        return Icons.shopping_bag;
      case 'shop':
        return Icons.store;
      case 'shop_review':
        return Icons.rate_review;
      case 'shop_review_reply':
        return Icons.reply;
      case 'review_request':
      case 'review_pending':
        return Icons.star_rate;
      case 'admin_notification':
        return Icons.campaign_rounded;
      default:
        return Icons.notifications;
    }
  }

  Color _getColorForType(String type) {
    switch (type) {
      case 'like':
      case 'post_like':
        return Colors.red;
      case 'comment':
      case 'post_comment':
        return Colors.blue;
      case 'follow':
      case 'new_follower':
        return Colors.purple;
      case 'follow_request':
        return Colors.orange;
      case 'order':
        return Colors.green;
      case 'order_update':
      case 'order_status':
        return Colors.teal;
      case 'new_order':
        return Colors.green.shade700;
      case 'shop_review':
        return Colors.orange;
      case 'shop_review_reply':
        return Colors.teal;
      case 'review_request':
      case 'review_pending':
        return Colors.amber;
      case 'admin_notification':
        return Colors.blue;
      default:
        return Colors.grey;
    }
  }

  Widget _buildFollowRequestsSection() {
    if (_followRequestNotifications.isEmpty) {
      return const SizedBox.shrink();
    }

    // Sadece en son istek göster
    final latestRequest = _followRequestNotifications.first;
    final hasMoreRequests = _followRequestNotifications.length > 1;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.blue.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Başlık
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.blue.shade50,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.person_add_rounded, color: Colors.blue.shade700, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Takip İstekleri (${_followRequestNotifications.length})',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.2,
                    ),
                  ),
                ),
                // Tümünü Gör butonu
                if (hasMoreRequests)
                  TextButton.icon(
                    onPressed: () {
                      // Tüm takip isteklerini göster - dialog veya yeni ekran
                      _showAllFollowRequestsDialog();
                    },
                    icon: Icon(Icons.visibility_outlined, size: 16),
                    label: Text('Tümünü Gör', style: TextStyle(fontSize: 12)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue.shade700,
                      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    ),
                  ),
              ],
            ),
          ),
          // Sadece en son istek kartı
          _buildNotificationCard(latestRequest),
        ],
      ),
    );
  }

  /// Admin duyuruları bölümü (herkese açık)
  Widget _buildAdminBroadcastsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(Icons.campaign_rounded, color: Colors.blue.shade700, size: 20),
              const SizedBox(width: 8),
              Text(
                'Duyurular',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.blue.shade800,
                ),
              ),
            ],
          ),
        ),
        ..._adminBroadcasts.map((broadcast) => _buildAdminBroadcastCard(broadcast)),
        const Divider(height: 1),
      ],
    );
  }

  /// Admin duyuru kartı
  Widget _buildAdminBroadcastCard(Map<String, dynamic> broadcast) {
    final iconType = broadcast['icon_type'] as String? ?? 'announcement';
    final icon = _getAdminNotificationIcon(iconType);
    final color = _getAdminNotificationColor(iconType);
    final title = broadcast['title'] as String? ?? 'Duyuru';
    final content = broadcast['content'] as String? ?? '';
    final createdAt = broadcast['created_at'] as String?;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        // ignore: deprecated_member_use
        color: color.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          // ignore: deprecated_member_use
          color: color.withOpacity(0.2),
          width: 1.5,
        ),
      ),
      child: ListTile(
        leading: Container(
          width: 50,
          height: 50,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            // ignore: deprecated_member_use
            color: color.withOpacity(0.15),
            border: Border.all(color: color, width: 2),
          ),
          child: Icon(
            icon,
            color: color,
            size: 28,
          ),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 2),
            Text(
              content,
              style: TextStyle(
                fontSize: 12,
                color: Colors.grey.shade700,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            if (createdAt != null) ...[
              const SizedBox(height: 4),
              Text(
                _formatBroadcastTime(createdAt),
                style: TextStyle(
                  fontSize: 10,
                  color: Colors.grey.shade500,
                ),
              ),
            ],
          ],
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
    );
  }

  /// Broadcast zamanını formatla
  String _formatBroadcastTime(String dateStr) {
    try {
      final dateTime = DateTime.parse(dateStr);
      final now = DateTime.now();
      final difference = now.difference(dateTime);

      if (difference.inMinutes < 1) {
        return 'Az önce';
      } else if (difference.inHours < 1) {
        return '${difference.inMinutes} dakika önce';
      } else if (difference.inDays < 1) {
        return '${difference.inHours} saat önce';
      } else if (difference.inDays < 7) {
        return '${difference.inDays} gün önce';
      } else {
        return DateFormat('dd MMM yyyy', 'tr').format(dateTime);
      }
    } catch (e) {
      return '';
    }
  }

  // Tüm takip isteklerini gösteren dialog
  void _showAllFollowRequestsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.person_add_rounded, color: Colors.blue.shade700),
            SizedBox(width: 10),
            Text('Takip İstekleri (${_followRequestNotifications.length})'),
          ],
        ),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: _followRequestNotifications.length,
            itemBuilder: (context, index) {
              return Padding(
                padding: EdgeInsets.only(bottom: index < _followRequestNotifications.length - 1 ? 12 : 0),
                child: _buildNotificationCard(_followRequestNotifications[index]),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Kapat'),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.notifications_none, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 16),
          Text(
            'Bildirim bulunmuyor',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Colors.grey.shade600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Yeni bildirimler burada görünecek',
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey.shade500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNotificationCard(model.NotificationModel notification) {
    final icon = _getIconForNotification(notification);
    final color = _getColorForNotification(notification);
    final actorName = notification.actorName ?? 'Bir kullanıcı';
    final actorAvatar = notification.actorAvatar;
    
    // Bildirim mesajını oluştur
    String notificationMessage = '';
    switch (notification.type) {
      case 'like':
        notificationMessage = '$actorName gönderini beğendi';
        break;
      case 'comment':
        notificationMessage = '$actorName yorum yaptı';
        break;
      case 'follow':
        notificationMessage = '$actorName seni takip etti';
        break;
      case 'follow_request':
        final reqStatus = _followRequestStatuses[notification.id];
        if (reqStatus == 'accepted') {
          notificationMessage = '$actorName kullanıcısının takip isteğini onayladın';
        } else if (reqStatus == 'rejected') {
          notificationMessage = '$actorName kullanıcısının takip isteğini reddettin';
        } else {
          notificationMessage = '$actorName sana takip isteği gönderdi';
        }
        break;
      case 'mention':
        notificationMessage = '$actorName seni bahsetti';
        break;
      case 'review_pending':
        notificationMessage = notification.title ?? 'Siparişiniz teslim edildi - değerlendirin';
        break;
      case 'shop_review':
        notificationMessage = notification.title ?? 'Mağazanıza yeni yorum yapıldı';
        break;
      case 'shop_review_reply':
        notificationMessage = notification.title ?? 'Yorumunuza cevap verildi';
        break;
      case 'order_update':
        notificationMessage = notification.title ?? 'Sipariş durumunuz güncellendi';
        break;
      case 'order_status':
        notificationMessage = notification.title ?? 'Sipariş durumunuz güncellendi';
        break;
      case 'new_order':
        notificationMessage = notification.title ?? 'Yeni sipariş aldınız!';
        break;
      default:
        // entity_id admin_icon: ile başlıyorsa admin bildirimidir
        if (notification.entityId != null && notification.entityId!.startsWith('admin_icon:')) {
          notificationMessage = notification.title ?? 'Yeni duyuru';
        } else {
          notificationMessage = notification.title ?? 'Yeni bildirim';
        }
    }

    return Dismissible(
      key: Key(notification.id),
      onDismissed: (direction) {
        _deleteNotification(notification);
      },
      background: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.delete, color: Colors.white),
      ),
      child: GestureDetector(
        onTap: () => _handleNotificationTap(notification),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: notification.isRead ? Colors.white : Colors.blue.shade50,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: notification.isRead ? Colors.grey.shade200 : Colors.blue.shade200,
              width: notification.isRead ? 1 : 2,
            ),
          ),
          child: ListTile(
            // Admin bildirimi ise sadece büyük ikon, değilse profil fotoğrafı + küçük ikon
            leading: (notification.entityId != null && notification.entityId!.startsWith('admin_icon:'))
                ? Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: color.withOpacity(0.15),
                      border: Border.all(color: color, width: 2),
                    ),
                    child: Icon(
                      icon,
                      color: color,
                      size: 32,
                    ),
                  )
                : SizedBox(
                    width: 56,
                    height: 56,
                    child: Stack(
                      children: [
                        // Profil resmi (CircleAvatar)
                        Container(
                          width: 56,
                          height: 56,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              // ignore: deprecated_member_use
                              color: color.withOpacity(0.3),
                              width: 2,
                            ),
                          ),
                          child: actorAvatar != null && actorAvatar.isNotEmpty
                              ? CircleAvatar(
                                  radius: 26,
                                  backgroundImage: NetworkImage(actorAvatar),
                                  onBackgroundImageError: (error, stackTrace) {
                                    debugPrint('❌ Profil resmi yüklenemedi: $error');
                                  },
                                  child: actorAvatar.isEmpty
                                      ? Icon(Icons.person, color: Colors.grey.shade400, size: 28)
                                      : null,
                                )
                              : CircleAvatar(
                                  radius: 26,
                                  // ignore: deprecated_member_use
                                  backgroundColor: color.withOpacity(0.1),
                                  child: Icon(Icons.person, color: color, size: 28),
                                ),
                        ),
                        // Bildirim tipi ikonu (sağ alt köşe)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: color,
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 2),
                            ),
                            child: Icon(
                              icon,
                              color: Colors.white,
                              size: 12,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
            title: Text(
              notificationMessage,
              style: TextStyle(
                fontWeight: notification.isRead ? FontWeight.normal : FontWeight.bold,
                fontSize: 14,
              ),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                if (notification.body != null && notification.body!.isNotEmpty)
                  Text(
                    notification.body!,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                const SizedBox(height: 4),
                Text(
                  _formatDate(notification.createdAt),
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.grey.shade500,
                  ),
                ),
                // Takip isteği butonları
                if (notification.type == 'follow_request') ...[
                  const SizedBox(height: 8),
                  _buildFollowRequestButtons(notification),
                ],
              ],
            ),
            trailing: notification.type != 'follow_request' && !notification.isRead
                ? Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  Widget _buildFollowRequestButtons(model.NotificationModel notification) {
    final status = _followRequestStatuses[notification.id];
    
    if (status == 'accepted') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, size: 14, color: Colors.green.shade700),
            const SizedBox(width: 4),
            Text(
              'Kabul edildi',
              style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }
    
    if (status == 'rejected') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cancel, size: 14, color: Colors.red.shade700),
            const SizedBox(width: 4),
            Text(
              'Reddedildi',
              style: TextStyle(fontSize: 11, color: Colors.red.shade700, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );
    }
    
    // Henüz işlem yapılmadı - butonları göster
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () => _handleFollowRequestAction(notification, false),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: Colors.grey.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: const Text(
                'Reddet',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.black87),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            onTap: () => _handleFollowRequestAction(notification, true),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    Theme.of(context).colorScheme.primary,
                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
                  ],
                ),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'Onayla',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
              ),
            ),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) {
      return 'Az önce';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes} dakika önce';
    } else if (difference.inHours < 24) {
      return '${difference.inHours} saat önce';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} gün önce';
    } else {
      return '${date.day}/${date.month}/${date.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Bildirimler',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: theme.colorScheme.primary,
        foregroundColor: Colors.white,
        actions: [
          if (_unreadCount > 0)
            TextButton.icon(
              onPressed: _markAllAsRead,
              icon: const Icon(Icons.done_all, color: Colors.white, size: 20),
              label: const Text(
                'Tümünü Oku',
                style: TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: CustomScrollView(
                slivers: [
                  // Admin Duyuruları (herkese açık)
                  if (_adminBroadcasts.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _buildAdminBroadcastsSection(),
                    ),

                  // Takip İstekleri Bölümü
                  if (_followRequestNotifications.isNotEmpty)
                    SliverToBoxAdapter(
                      child: _buildFollowRequestsSection(),
                    ),
                  
                  // Boş durum göster
                  if (_notifications.isEmpty && _adminBroadcasts.isEmpty)
                    SliverFillRemaining(
                      child: _buildEmptyState(),
                    ),

                  // Diğer bildirimler
                  if (_notifications.isNotEmpty)
                    SliverPadding(
                      padding: const EdgeInsets.all(16),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate(
                            (context, index) {
                              final notification = _otherNotifications[index];
                              return _buildNotificationCard(notification);
                            },
                            childCount: _otherNotifications.length,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }
}
