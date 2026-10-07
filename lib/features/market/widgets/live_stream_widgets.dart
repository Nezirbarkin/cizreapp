import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../core/models/live_shopping_model.dart';
import '../services/live_shopping_service.dart';
import 'shop_card.dart' show formatShopMoney;

/// Canlı yayın ekranlarının ortak parçaları (Görev 3.4): dikey tam ekran
/// görüntünün üstünde yarı saydam katmanlar.

const Color kLiveRed = Color(0xFFE53935);

/// "12:05" / "1:02:05".
String formatLiveDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return h > 0 ? '$h:$m:$s' : '${d.inMinutes}:$s';
}

/// Yayının neden bittiğinin kullanıcıya açıklaması.
/// [userStream]: kullanıcı yayınında "Satıcı" yerine "Yayıncı" denir.
String liveEndedReasonText(String? reason, {required bool forHost, bool userStream = false}) {
  final who = userStream ? 'Yayıncı' : 'Satıcı';
  switch (reason) {
    case 'timeout':
      return forHost
          ? 'Bağlantı 2 dakikadan uzun süre koptuğu için yayın sona erdi.'
          : '${who}nın bağlantısı koptuğu için yayın sona erdi.';
    case 'admin':
      return 'Yayın yönetici tarafından kapatıldı.';
    default:
      return forHost ? 'Yayını bitirdin.' : '$who yayını bitirdi.';
  }
}

/// Kırmızı "CANLI" rozeti; isteğe bağlı süre ve izleyici sayısı.
class LiveBadge extends StatelessWidget {
  const LiveBadge({super.key, this.elapsed, this.viewers});

  final Duration? elapsed;
  final int? viewers;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(color: kLiveRed, borderRadius: BorderRadius.circular(6)),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.circle, size: 8, color: Colors.white),
              const SizedBox(width: 5),
              Text(
                elapsed == null ? 'CANLI' : 'CANLI · ${formatLiveDuration(elapsed!)}',
                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        if (viewers != null) ...[
          const SizedBox(width: 6),
          Semantics(
            label: '${viewers!} izleyici',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.visibility_outlined, size: 14, color: Colors.white),
                  const SizedBox(width: 4),
                  Text(
                    '${viewers!}',
                    style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Mağaza logosu (yoksa baş harf) — yuvarlak.
class LiveShopAvatar extends StatelessWidget {
  const LiveShopAvatar({super.key, this.logoUrl, required this.name, this.size = 36});

  final String? logoUrl;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? '?' : name.trim().characters.first.toUpperCase();
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(color: kLiveRed, shape: BoxShape.circle),
      child: Text(
        initial,
        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.42),
      ),
    );
    final url = logoUrl;
    if (url == null) return fallback;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: url,
        width: size,
        height: size,
        fit: BoxFit.cover,
        memCacheWidth: (size * 3).round(),
        errorWidget: (_, _, _) => fallback,
        placeholder: (_, _) => fallback,
      ),
    );
  }
}

/// Görüntünün üstündeki sohbet: en yeni en altta, eskiler yukarı kayar.
class LiveChatList extends StatelessWidget {
  const LiveChatList({
    super.key,
    required this.messages,
    this.onMessageLongPress,
    this.maxHeight = 220,
    this.hostIcon = Icons.storefront,
  });

  final List<LiveMessage> messages;

  /// Yayıncı mesajının simgesi (mağaza yayını: vitrin, kullanıcı: kamera).
  final IconData hostIcon;

  /// Satıcı moderasyonu: uzun basınca (yalnız satıcı ekranında verilir).
  final void Function(LiveMessage message)? onMessageLongPress;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    if (messages.isEmpty) return const SizedBox.shrink();
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: ShaderMask(
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.white, Colors.white],
          stops: [0, 0.18, 1],
        ).createShader(rect),
        blendMode: BlendMode.dstIn,
        child: ListView.builder(
          reverse: true,
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          itemCount: messages.length,
          itemBuilder: (context, i) {
            final m = messages[messages.length - 1 - i];
            return _LiveChatBubble(
              key: ValueKey('live-msg-${m.id}'),
              message: m,
              hostIcon: hostIcon,
              onLongPress: onMessageLongPress == null ? null : () => onMessageLongPress!(m),
            );
          },
        ),
      ),
    );
  }
}

class _LiveChatBubble extends StatelessWidget {
  const _LiveChatBubble({super.key, required this.message, this.onLongPress, this.hostIcon = Icons.storefront});

  final LiveMessage message;
  final IconData hostIcon;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: message.isHost ? kLiveRed.withValues(alpha: 0.85) : Colors.black.withValues(alpha: 0.45),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Text.rich(
            TextSpan(
              children: [
                if (message.isHost)
                  WidgetSpan(
                    alignment: PlaceholderAlignment.middle,
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Icon(hostIcon, size: 13, color: Colors.white),
                    ),
                  ),
                TextSpan(
                  text: '${message.authorName}  ',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: message.isHost ? Colors.white : const Color(0xFFFFD54F),
                  ),
                ),
                TextSpan(text: message.message),
              ],
            ),
            style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.25),
          ),
        ),
      ),
    );
  }
}

/// Yayında sabitlenen ürün kartı. İzleyici dokunur → ürün; satıcı kaldırır.
class LivePinnedProductCard extends StatelessWidget {
  const LivePinnedProductCard({super.key, required this.product, this.onTap, this.onRemove});

  final LivePinnedProduct product;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final image = product.imageUrl;
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: image == null
                      ? const ColoredBox(
                          color: Color(0xFFF1F1F1),
                          child: Icon(Icons.shopping_bag_outlined, color: Colors.black38),
                        )
                      : CachedNetworkImage(
                          imageUrl: image,
                          fit: BoxFit.cover,
                          memCacheWidth: 156,
                          errorWidget: (_, _, _) => const ColoredBox(
                            color: Color(0xFFF1F1F1),
                            child: Icon(Icons.shopping_bag_outlined, color: Colors.black38),
                          ),
                        ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.push_pin, size: 13, color: kLiveRed),
                        const SizedBox(width: 3),
                        Text(
                          onRemove == null ? 'Yayında gösterilen ürün' : 'Yayında gösteriyorsun',
                          style: const TextStyle(fontSize: 11, color: kLiveRed, fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      product.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14, color: Colors.black87),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Text(
                          formatShopMoney(product.effectivePrice),
                          style: const TextStyle(fontWeight: FontWeight.w800, color: Colors.black87),
                        ),
                        if (product.hasDiscount) ...[
                          const SizedBox(width: 6),
                          Text(
                            formatShopMoney(product.price),
                            style: const TextStyle(
                              color: Colors.black38,
                              fontSize: 12,
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (onRemove != null)
                IconButton(
                  tooltip: 'Ürünü kaldır',
                  icon: const Icon(Icons.close, color: Colors.black54),
                  onPressed: onRemove,
                )
              else if (onTap != null)
                FilledButton(
                  onPressed: onTap,
                  style: FilledButton.styleFrom(
                    backgroundColor: kLiveRed,
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: const Text('İncele'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Görüntünün üstündeki yuvarlak mesaj kutusu.
class LiveChatInput extends StatelessWidget {
  const LiveChatInput({
    super.key,
    required this.controller,
    required this.onSend,
    this.sending = false,
    this.hint = 'Bir şey yaz…',
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final bool sending;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: TextField(
            controller: controller,
            maxLength: 300,
            minLines: 1,
            maxLines: 3,
            textInputAction: TextInputAction.send,
            onSubmitted: (_) => onSend(),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              counterText: '',
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white60),
              filled: true,
              fillColor: Colors.black.withValues(alpha: 0.45),
              isDense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 44,
          height: 44,
          child: sending
              ? const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : IconButton.filled(
                  tooltip: 'Gönder',
                  onPressed: onSend,
                  style: IconButton.styleFrom(backgroundColor: kLiveRed),
                  icon: const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                ),
        ),
      ],
    );
  }
}

/// Görüntü yokken ortada gösterilen durum (bağlanıyor, kamera kapalı, …).
class LiveStageMessage extends StatelessWidget {
  const LiveStageMessage({super.key, required this.icon, required this.text, this.busy = false});

  final IconData icon;
  final String text;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (busy)
              const SizedBox(
                width: 36,
                height: 36,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
              )
            else
              Icon(icon, color: Colors.white70, size: 48),
            const SizedBox(height: 14),
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 15, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }
}

/// Yuvarlak yarı saydam kontrol düğmesi (kamera, mikrofon, ürünler…).
class LiveRoundButton extends StatelessWidget {
  const LiveRoundButton({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onPressed;

  /// Kırmızı vurgulu (ör. mikrofon kapalı).
  final bool active;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: IconButton(
        tooltip: tooltip,
        onPressed: onPressed,
        style: IconButton.styleFrom(
          backgroundColor: active ? kLiveRed : Colors.black.withValues(alpha: 0.45),
          fixedSize: const Size(46, 46),
        ),
        icon: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }
}

/// "Yayınlarından haberdar ol": mağaza canlı yayına başlayınca bildirim.
///
/// Durumu kendisi okur ve yazar (`live_shop_subscription` /
/// `live_set_subscription`). Misafir dokunursa girişe yönlendirilir.
/// [dark]: görüntü üstünde yarı saydam hap; false = açık zeminde çerçeveli.
class LiveSubscribeButton extends StatefulWidget {
  const LiveSubscribeButton({
    super.key,
    required this.shopId,
    required this.service,
    this.shopName,
    this.dark = true,
    this.expanded = false,
  });

  final String shopId;
  final LiveShoppingService service;
  final String? shopName;
  final bool dark;

  /// Tam genişlik (bitti ekranı).
  final bool expanded;

  @override
  State<LiveSubscribeButton> createState() => _LiveSubscribeButtonState();
}

class _LiveSubscribeButtonState extends State<LiveSubscribeButton> {
  LiveSubscription? _subscription;
  bool _busy = false;

  bool get _isGuest => widget.service.currentUserId == null;
  bool get _subscribed => _subscription?.subscribed ?? false;

  @override
  void initState() {
    super.initState();
    if (!_isGuest && widget.shopId.isNotEmpty) _load();
  }

  Future<void> _load() async {
    try {
      final subscription = await widget.service.fetchSubscription(widget.shopId);
      if (mounted && !_busy) setState(() => _subscription = subscription);
    } catch (_) {
      // Durum okunamazsa "Haberdar ol" görünür; dokununca yazma dener.
    }
  }

  void _snack(String text, {SnackBarAction? action}) {
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text), action: action));
  }

  Future<void> _toggle() async {
    if (_isGuest) {
      // Navigator şimdi yakalanır: snackbar eylemi bu widget kapandıktan
      // sonra da basılabilir ve o anda context ölüdür.
      final navigator = Navigator.of(context);
      _snack(
        'Yayın bildirimi almak için giriş yapmalısın',
        action: SnackBarAction(
          label: 'Giriş Yap',
          onPressed: () {
            if (navigator.mounted) navigator.pushNamed('/login');
          },
        ),
      );
      return;
    }
    if (_busy) return;
    final target = !_subscribed;
    setState(() => _busy = true);
    try {
      final result = await widget.service.setSubscription(widget.shopId, target);
      if (!mounted) return;
      setState(() => _subscription = result);
      final shop = widget.shopName ?? 'Mağaza';
      _snack(
        result.subscribed
            ? '🔔 $shop canlı yayına başlayınca haber vereceğiz'
            : '$shop için yayın bildirimleri kapatıldı',
      );
    } catch (e) {
      if (!mounted) return;
      _snack(LiveShoppingService.toLiveException(e).message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final subscribed = _subscribed;
    final icon = Icon(
      subscribed ? Icons.notifications_active : Icons.notifications_none,
      size: 18,
      color: widget.dark ? Colors.white : (subscribed ? kLiveRed : Colors.black87),
    );
    final label = Text(
      subscribed ? 'Haberdarsın' : 'Haberdar ol',
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontWeight: FontWeight.w700,
        fontSize: 13,
        color: widget.dark ? Colors.white : (subscribed ? kLiveRed : Colors.black87),
      ),
    );
    final child = Row(
      mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (_busy)
          SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: widget.dark ? Colors.white : kLiveRed,
            ),
          )
        else
          icon,
        const SizedBox(width: 6),
        Flexible(child: label),
      ],
    );
    return Semantics(
      button: true,
      toggled: subscribed,
      label: 'Canlı yayın bildirimi',
      child: Material(
        key: const ValueKey('live-subscribe'),
        color: widget.dark
            ? (subscribed ? Colors.white.withValues(alpha: 0.18) : Colors.black.withValues(alpha: 0.45))
            : (subscribed ? kLiveRed.withValues(alpha: 0.08) : Colors.white),
        shape: StadiumBorder(
          side: BorderSide(
            color: widget.dark ? Colors.white38 : (subscribed ? kLiveRed : Colors.black26),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _toggle,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 12, vertical: widget.expanded ? 12 : 6),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Yayında öne çıkan (sabitlenmiş) ürünler — yatay şerit, koyu zeminde.
class LiveFeaturedProducts extends StatelessWidget {
  const LiveFeaturedProducts({super.key, required this.products, required this.onTap, this.title});

  final List<LivePinnedProduct> products;
  final ValueChanged<String> onTap;
  final String? title;

  @override
  Widget build(BuildContext context) {
    if (products.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title ?? 'Bu yayında öne çıkanlar',
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 150,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: products.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final product = products[i];
              final image = product.imageUrl;
              return Material(
                key: ValueKey('live-featured-${product.id}'),
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                child: InkWell(
                  onTap: () => onTap(product.id),
                  child: SizedBox(
                    width: 112,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        SizedBox(
                          height: 84,
                          width: double.infinity,
                          child: image == null
                              ? const ColoredBox(
                                  color: Color(0xFFF1F1F1),
                                  child: Icon(Icons.shopping_bag_outlined, color: Colors.black38),
                                )
                              : CachedNetworkImage(
                                  imageUrl: image,
                                  fit: BoxFit.cover,
                                  memCacheWidth: 336,
                                  errorWidget: (_, _, _) => const ColoredBox(
                                    color: Color(0xFFF1F1F1),
                                    child: Icon(Icons.shopping_bag_outlined, color: Colors.black38),
                                  ),
                                ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
                          child: Text(
                            product.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.black87),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(8, 2, 8, 0),
                          child: Text(
                            product.isAvailable ? formatShopMoney(product.effectivePrice) : 'Tükendi',
                            maxLines: 1,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: product.isAvailable ? kLiveRed : Colors.black38,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Bitti ekranı / geçmiş için küçük istatistik (ikon + değer + etiket).
class LiveStatChip extends StatelessWidget {
  const LiveStatChip({super.key, required this.icon, required this.value, required this.label});

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(12)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white70, size: 18),
          const SizedBox(height: 4),
          Text(value, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ],
      ),
    );
  }
}
