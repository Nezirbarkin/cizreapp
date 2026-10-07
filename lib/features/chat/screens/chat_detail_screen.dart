// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/message_model.dart';
import '../../../core/models/post_model.dart';
import '../services/chat_location_service.dart';
import '../services/chat_media_service.dart';
import '../services/chat_service.dart';
import '../services/typing_channel.dart';
import '../widgets/chat_bubble.dart';
import '../widgets/chat_media_bubbles.dart';
import '../widgets/chat_message_actions.dart';
import '../widgets/presence_status_line.dart';
import 'chat_image_send_screen.dart';
import 'chat_image_viewer_screen.dart';
import 'chat_location_picker_screen.dart';
import 'chat_location_viewer_screen.dart';
import '../../profile/screens/user_profile_screen.dart';
import '../../social/screens/post_detail_screen.dart';
import '../../../ilanlar/screens/ilan_detail_screen.dart';
import '../../../core/utils/image_url.dart';

class ChatDetailScreen extends StatefulWidget {
  final String conversationId;
  final String otherUserId;
  final String otherUserName;
  final String? otherUserAvatar;

  /// Testlerde gerçek ağ/realtime yerine sahte servis vermek için.
  @visibleForTesting
  final ChatService? chatService;

  const ChatDetailScreen({
    super.key,
    required this.conversationId,
    required this.otherUserId,
    required this.otherUserName,
    this.otherUserAvatar,
    this.chatService,
  });

  @override
  State<ChatDetailScreen> createState() => _ChatDetailScreenState();
}

class _ChatDetailScreenState extends State<ChatDetailScreen>
    with WidgetsBindingObserver {
  late final ChatService _chatService = widget.chatService ?? ChatService();
  final TextEditingController _messageController = TextEditingController();
  // Listenin altındaki boşluk (eski ListView'in alt dolgusu). Kaydırma buradan
  // başlar ki açılışta en altta olsun (bkz. _buildOptimizedMessageList).
  static const double _listBottomGap = 16;
  static const ValueKey<String> _historySliverKey =
      ValueKey<String>('chat-history');
  final ScrollController _scrollController = ScrollController(
    initialScrollOffset: -_listBottomGap,
  );

  // Id-bazlı Map — duplicate önler, optimistic+DB merge'i yönetir
  final Map<String, Message> _messagesById = {};
  // İKİ PARÇALI LİSTE, ikisi de eskiden yeniye:
  //  * _historyIds: sunucudan gelen sayfalar (ilk sayfa + yukarı kaydırınca
  //    eskiler); ekranın ÜSTÜNE doğru büyür.
  //  * _newIds: bu ekran açıkken canlı gelen / gönderilen mesajlar; ekranın
  //    ALTINA doğru büyür.
  // Ayrı büyüdükleri için eski sayfa yüklemek de, kullanıcı yukarıdayken yeni
  // mesaj gelmesi de görünen içeriği kaydırmaz. (Flutter liste konumlarını
  // indeks bazlı tutar; tek listede bu iki eklemeden biri mutlaka kaydırırdı.)
  final List<String> _historyIds = [];
  final List<String> _newIds = [];
  // Kompozit-anahtar (sender|content|createdAt) -> gösterilen mesajın id'si.
  // Mailbox modelinde aynı mesaj iki conv'da farklı id ile durur; bu index
  // canlı akışta ikinci kopyanın tekrar eklenmesini önler.
  final Map<String, String> _keyToId = {};

  bool _isLoading = true;
  bool _isSending = false;
  // Sayfalama: ilk sayfa gelmeden eski sayfa istenmez (önbellekten çizilen
  // liste ilk sayfa gelince değiştirildiği için).
  bool _initialFetchDone = false;
  bool _loadingOlder = false;
  bool _hasMore = true;
  RealtimeChannel? _messagesChannel;
  String? _currentUserId;
  bool _isAtBottom = true;
  DateTime? _lastReadTime; // Son okundu işaretleme zamanı (debounce)

  // Yanıt özelliği için
  Message? _replyToMessage;
  final FocusNode _messageFocusNode = FocusNode();

  // "Yazıyor…": karşı taraf yazıyorsa başlıkta gösterilir; kendi yazdığımız da
  // (tercihimiz ve yönetici izin veriyorsa) karşıya bildirilir.
  TypingChannel? _typingChannel;
  final ValueNotifier<bool> _peerTyping = ValueNotifier<bool>(false);

  // Fotoğraf / konum (Görev 3.1). Gönderilen medya önce GEÇİCİ bir balonla
  // (yerel baytlar, "gönderiliyor") hemen görünür; gerçek mesaj gelince —
  // RPC dönüşü ya da realtime, hangisi önce gelirse — yerini alır. Başarısız
  // olursa balon "tekrar dene" olarak kalır; yeniden denemek için veri burada.
  final ImagePicker _imagePicker = ImagePicker();
  final Map<String, _PendingMedia> _pendingMedia = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentUserId = Supabase.instance.client.auth.currentUser?.id;
    // Bu konuşma daha önce açıldıysa son sayfası beklemeden çizilir; sunucudan
    // gelen ilk sayfa (tek istek) onu sessizce günceller.
    final cached = _chatService.cachedFirstPage(widget.conversationId);
    if (cached != null && cached.isNotEmpty) {
      _mergeMessages(cached);
      _isLoading = false;
    }
    _loadMessages();
    _subscribeToMessages();
    _startTyping();
    // Mesajları okundu olarak işaretle (bana gelen mesajlar)
    _chatService.markMessagesAsRead(widget.conversationId);

    // Scroll pozisyonunu takip et
    _scrollController.addListener(_onScroll);

    // Klavye açıldığında (input focus alınca) en alttaysak en alta kaydır
    _messageFocusNode.addListener(() {
      if (_messageFocusNode.hasFocus) {
        _scrollToBottom(force: true);
      }
    });
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    // En alt = minScrollExtent (yeni mesajlar aşağı doğru büyür); son 50px
    // içindeyse "en altta" say.
    _isAtBottom = position.pixels <= position.minScrollExtent + 50;
    // En üste yaklaşınca bir önceki sayfayı getir.
    if (position.pixels >= position.maxScrollExtent - 400) {
      _loadOlder();
    }
  }

  void _startTyping() {
    final uid = _currentUserId;
    if (uid == null) return;
    final channel = TypingChannel(
      transport: SupabaseTypingTransport.direct(widget.otherUserId),
      selfId: uid,
    );
    _typingChannel = channel;
    channel.typing.addListener(_syncPeerTyping);
    _messageController.addListener(_onComposerChanged);
    channel.start();
  }

  void _syncPeerTyping() {
    _peerTyping.value =
        _typingChannel?.typing.value.contains(widget.otherUserId) ?? false;
  }

  // Metin kutusu boşaldığında (mesaj gönderilince `clear()` dahil) kanal
  // kendiliğinden "yazmıyor" der.
  void _onComposerChanged() {
    _typingChannel?.onTextChanged(_messageController.text);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Uygulama ön plana geldiğinde mesajları okundu işaretle
    if (state == AppLifecycleState.resumed && mounted) {
      _chatService.markMessagesAsRead(widget.conversationId);
    }
    // Arka plana giderken "yazıyor" takılı kalmasın.
    if (state != AppLifecycleState.resumed) {
      _typingChannel?.stopTyping();
    }
  }

  @override
  void didChangeMetrics() {
    // Klavye açılıp kapanırken viewInsets değişir; liste viewport'u küçülüp
    // büyüdüğünde en alttaki kullanıcı için son mesajın görünür kalmasını sağla.
    if (!mounted) return;
    if (_isAtBottom) {
      _scrollToBottom(force: true);
    }
  }

  /// Bu metod artık gerekli değil (kaldırıldı)
  /// Okundu bilgisi sadece mesajı ALAN kişi tarafından işaretlenir
  Future<void> _markSenderMessagesAsRead() async {
    // Boş - artık çağrılmıyor
    debugPrint('_markSenderMessagesAsRead: DEPRECATED');
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.removeListener(_onScroll);
    _messageController.removeListener(_onComposerChanged);
    _typingChannel?.typing.removeListener(_syncPeerTyping);
    // "Yazmıyor"u gönderip kanalı kapatır; beklenmez.
    unawaited(_typingChannel?.dispose());
    _peerTyping.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _messageFocusNode.dispose();
    final channel = _messagesChannel;
    if (channel != null) {
      unawaited(Supabase.instance.client.removeChannel(channel));
    }
    // Aynı konuşma tekrar açılınca beklemeden çizilsin: en yeni mesajlar.
    final shown = [..._historyIds, ..._newIds];
    if (_initialFetchDone && shown.isNotEmpty) {
      _chatService.rememberConversationPage(
        widget.conversationId,
        shown.reversed
            .map((id) => _messagesById[id])
            .whereType<Message>()
            // Gönderimi süren/başarısız geçici balonlar önbelleğe girmez.
            .where((m) => !m.id.startsWith('temp_'))
            .toList(),
      );
    }
    super.dispose();
  }

  /// Yanıtlanacak mesajı ayarla
  void _setReply(Message message) {
    setState(() {
      _replyToMessage = message;
    });
    _messageFocusNode.requestFocus();
  }

  /// Yanıtı iptal et
  void _cancelReply() {
    setState(() {
      _replyToMessage = null;
    });
  }

  /// İlk sayfa (en yeni [ChatService.messagePageSize] mesaj) — tek istek.
  Future<void> _loadMessages() async {
    try {
      final page = await _chatService.getMessagesPage(widget.conversationId);
      if (!mounted) return;
      setState(() {
        _replaceWithFirstPage(page);
        _hasMore = page.length >= ChatService.messagePageSize;
      });
    } catch (e) {
      debugPrint('loadMessages error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _initialFetchDone = true;
        });
      }
    }
  }

  /// Yukarı kaydırınca bir önceki sayfa. Hata olursa sonraki kaydırmada
  /// yeniden denenir.
  Future<void> _loadOlder() async {
    if (!_initialFetchDone || _loadingOlder || !_hasMore) return;
    final oldestId = _historyIds.isNotEmpty
        ? _historyIds.first
        : (_newIds.isNotEmpty ? _newIds.first : null);
    final oldest = oldestId == null ? null : _messagesById[oldestId];
    if (oldest == null) return;

    setState(() => _loadingOlder = true);
    try {
      final page = await _chatService.getMessagesPage(
        widget.conversationId,
        before: oldest.createdAt,
      );
      if (!mounted) return;
      setState(() {
        _mergeMessages(page);
        _hasMore = page.length >= ChatService.messagePageSize;
      });
    } catch (e) {
      debugPrint('loadOlder error: $e');
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  /// Ekrandakini (önbellekten çizilmiş olabilir) sunucunun ilk sayfasıyla
  /// değiştirir; yalnız bu arada canlı gelmiş ve sayfada olmayan mesajlar
  /// korunur. Böylece önbellekte kalmış, sonradan silinmiş mesaj kalmaz,
  /// açılışta gelen yeni mesaj da kaybolmaz.
  void _replaceWithFirstPage(List<Message> page) {
    final pageIds = {for (final m in page) m.id};
    final pageKeys = {for (final m in page) _dupKey(m)};
    final live = _newIds
        .map((id) => _messagesById[id])
        .whereType<Message>()
        .where((m) => !pageIds.contains(m.id) && !pageKeys.contains(_dupKey(m)))
        .toList();
    _messagesById.clear();
    _historyIds.clear();
    _newIds.clear();
    _keyToId.clear();
    _mergeMessages(page);
    for (final m in live) {
      _messagesById[m.id] = m;
      _keyToId[_dupKey(m)] = m.id;
      _newIds.add(m.id);
    }
  }

  /// Sunucu sayfasını GEÇMİŞE katar: aynı kimlik yerinde güncellenir, aynı
  /// mantıksal mesajın ikinci kopyası eklenmez (yalnız okundu bilgisi alınır),
  /// geçmiş eskiden yeniye sıralı kalır. Listeyi SIFIRLAMAZ.
  void _mergeMessages(Iterable<Message> messages) {
    var added = false;
    for (final m in messages) {
      final key = _dupKey(m);
      final twinId = _keyToId[key];
      if (twinId != null && twinId != m.id) {
        final twin = _messagesById[twinId];
        if (twin != null) {
          _messagesById[twinId] = twin.copyWith(isRead: m.isRead);
          continue;
        }
      }
      if (_messagesById.containsKey(m.id)) {
        _messagesById[m.id] = m;
        continue;
      }
      _messagesById[m.id] = m;
      _keyToId[key] = m.id;
      _historyIds.add(m.id);
      added = true;
    }
    if (added) {
      // Eşit zamanda kimliğe göre (kararlı). Eski sayfa her zaman mevcut
      // geçmişten eskidir → listenin başına, yani ekranın üstüne gider.
      _historyIds.sort((a, b) {
        final ma = _messagesById[a]!, mb = _messagesById[b]!;
        final byTime = ma.createdAt.compareTo(mb.createdAt);
        return byTime != 0 ? byTime : a.compareTo(b);
      });
    }
  }

  void _removeMessage(String id) {
    final removed = _messagesById.remove(id);
    if (removed == null) return;
    _historyIds.remove(id);
    _newIds.remove(id);
    _keyToId.remove(_dupKey(removed));
    setState(() {});
  }

  /// Tek realtime kanalı (INSERT/UPDATE/DELETE, sunucuda bu konuşmaya
  /// süzülür). DB'yi yeniden çekmez, yalnız değişen mesajı listeye işler.
  void _subscribeToMessages() {
    final userId = _currentUserId;
    if (userId == null) return;
    _messagesChannel = _chatService.subscribeToMessagesChannel(
      conversationId: widget.conversationId,
      currentUserId: userId,
      onEvent: (event) {
        if (!mounted) return;
        if (event is InsertMessageEvent) {
          _addOrMerge(event.message);
        } else if (event is UpdateMessageEvent) {
          _addOrMerge(event.message, allowInsert: false);
        } else if (event is DeleteMessageEvent) {
          _removeMessage(event.messageId);
        } else if (event is PartnerReadEvent) {
          _markReadByPartner(event.partnerCopy);
        }
      },
    );
  }

  /// Karşı taraf mesajımı okudu: ONUN kopyası is_read=true oldu. Ekrandaki
  /// aynı mantıksal mesajım (bkz. [_dupKey]) "okundu" yapılır — mavi çift tik
  /// artık ekran yeniden açılmadan gelir (Görev 2.3).
  void _markReadByPartner(Message partnerCopy) {
    final id = _keyToId[_dupKey(partnerCopy)];
    if (id == null) return;
    final mine = _messagesById[id];
    if (mine == null || mine.isRead || mine.senderId != _currentUserId) return;
    setState(() => _messagesById[id] = mine.copyWith(isRead: true));
  }

  /// Mailbox modelinde aynı mantıksal mesaj iki conversation'da farklı id ile
  /// durur (sender|content|createdAt aynıdır). Bu anahtar iki kopyayı eşler.
  String _dupKey(Message m) =>
      '${m.senderId}|${m.content}|${m.createdAt.toIso8601String()}';

  /// Kompozit-anahtar bazlı merge — INSERT ve UPDATE için kullanılır.
  /// Mevcut mesaj varsa günceller, yoksa ([allowInsert] ise) ekler. İki-kopya
  /// durumunda ikinci kopyanın tekrar eklenmesini engeller.
  void _addOrMerge(Message m, {bool allowInsert = true}) {
    // Realtime INSERT'ten gelen DB mesajı: temp ID'leri atla
    if (m.id.startsWith('temp_')) return;

    final bool isMine = m.senderId == _currentUserId;

    // ÖNEMLI: Gönderenin KENDI conv kopyasında is_read=true anlamsızdır
    // (mesajı gönderen zaten "okumuştur"), karşı tarafın okuyup okumadığını
    // göstermez. Bu yüzden kendi mesajımın is_read=true'sunu YOK SAY → 'sent'.
    // Gerçek "okundu" bilgisi partner kopyasından / reopen'da getMessages'ten gelir.
    Message incoming = (isMine && m.isRead) ? m.copyWith(isRead: false) : m;
    final key = _dupKey(incoming);

    // Aynı id zaten var mı? (RPC dönüşü + realtime INSERT aynı satır)
    final existing = _messagesById[incoming.id];
    if (existing != null) {
      final mergedRead = isMine
          ? (existing.isRead || incoming.isRead)
          : incoming.isRead;
      _messagesById[incoming.id] = incoming.copyWith(isRead: mergedRead);
      if (mounted) setState(() {});
      return;
    }

    // Aynı mantıksal mesaj FARKLI id ile zaten gösteriliyor mu? (iki-kopya)
    final twinId = _keyToId[key];
    if (twinId != null && _messagesById.containsKey(twinId)) {
      final twin = _messagesById[twinId]!;
      if (isMine && incoming.isRead && !twin.isRead) {
        _messagesById[twinId] = twin.copyWith(isRead: true);
        if (mounted) setState(() {});
      }
      return; // İkinci kopyayı listeye EKLEME
    }

    // Güncelleme olayı ekranda olmayan (henüz yüklenmemiş, eski) bir mesaja
    // ait: eklenmez, sayfalama onu doğru yerde getirir. (Ör. konuşma açılınca
    // okundu işaretlenen eski mesajların UPDATE olayları listenin dibine
    // eklenirdi.)
    if (!allowInsert) return;

    // Bu cihazdan gönderilmekte olan fotoğraf/konumun gerçek kopyası RPC
    // dönmeden realtime'dan geldi: geçici balonun YERİNE geçer (aynı mesaj bir
    // an iki kez görünmesin).
    if (isMine && incoming.messageType != MessageType.text) {
      final tempId = _pendingTempFor(incoming);
      if (tempId != null) {
        _pendingMedia.remove(tempId);
        _replaceTemp(tempId, incoming);
        return;
      }
    }

    _messagesById[incoming.id] = incoming;
    _keyToId[key] = incoming.id;
    _newIds.add(incoming.id);

    if (mounted) setState(() {});

    // Sadece kullanıcı en alttaysa scroll
    if (_isAtBottom) _scrollToBottom();

    // Debounced okundu işaretleme
    final now = DateTime.now();
    if (_lastReadTime == null ||
        now.difference(_lastReadTime!).inSeconds >= 2) {
      _lastReadTime = now;
      _chatService.markMessagesAsRead(widget.conversationId);
    }
  }

  /// [force] true ise kullanıcının scroll pozisyonuna bakılmaksızın en alta
  /// kaydırır (kendi gönderdiğimiz mesaj veya klavye açılışı gibi durumlar için).
  void _scrollToBottom({bool force = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      // Liste açılışta zaten en alttadır (eski jumpTo(maxScrollExtent)
      // hilesine gerek yok). En alt = minScrollExtent: yeni mesajlar aşağı
      // doğru büyür.
      if (!(_isAtBottom || force)) return;
      final position = _scrollController.position;
      if (position.pixels <= position.minScrollExtent) return;
      _scrollController.animateTo(
        position.minScrollExtent,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    });
  }

  // ------------------------------------------------------------------
  // Fotoğraf / konum gönderimi (Görev 3.1)
  // ------------------------------------------------------------------

  Future<void> _openAttachments() async {
    FocusScope.of(context).unfocus();
    final action = await showChatAttachmentSheet(context, cameraAvailable: !kIsWeb);
    if (!mounted || action == null) return;
    switch (action) {
      case ChatAttachmentAction.gallery:
        await _pickImage(ImageSource.gallery);
      case ChatAttachmentAction.camera:
        await _pickImage(ImageSource.camera);
      case ChatAttachmentAction.location:
        await _pickLocation();
    }
  }

  Future<void> _pickImage(ImageSource source) async {
    XFile? file;
    try {
      file = await _imagePicker.pickImage(
        source: source,
        maxWidth: 2048,
        maxHeight: 2048,
        imageQuality: 90,
      );
    } catch (e) {
      debugPrint('Fotoğraf seçilemedi: $e');
      _showSnack('Fotoğraf açılamadı. Uygulama izinlerini kontrol edin.');
      return;
    }
    if (file == null || !mounted) return;
    final bytes = await file.readAsBytes();
    if (!mounted) return;

    final result = await showChatImageSendScreen(
      context,
      bytes: bytes,
      recipientName: widget.otherUserName,
    );
    if (result == null || !mounted) return;

    final reply = _takeReply();
    final prepared = await ChatMediaService.prepareImage(bytes, fileName: file.name);
    if (!mounted) return;
    await _sendPreparedImage(prepared, result.caption, reply);
  }

  /// Hazır fotoğrafı gönderir. Her denemede YENİ yol: önceki deneme yüklemeyi
  /// bitirip mesajda kalmış olabilir, aynı yola ikinci yükleme reddedilir.
  Future<void> _sendPreparedImage(
    PreparedChatImage prepared,
    String caption,
    _ReplyInfo reply,
  ) async {
    final me = _currentUserId ?? Supabase.instance.client.auth.currentUser?.id;
    if (me == null) return;
    final path = ChatMediaService.newImagePath(
      senderId: me,
      recipientId: widget.otherUserId,
      extension: prepared.extension,
    );
    ChatMediaService.rememberLocalBytes(path, prepared.bytes);

    final temp = Message.createTemp(
      conversationId: widget.conversationId,
      senderId: me,
      content: ChatService.imagePreviewText(caption),
      messageType: MessageType.image,
      attachment: ChatService.imageAttachment(
        path: path,
        image: prepared,
        caption: caption,
      ),
      replyToId: reply.id,
      replyToContent: reply.content,
      replyToSenderName: reply.senderName,
    );
    _pendingMedia[temp.id] = _PendingMedia.image(prepared, caption, reply);
    _showTemp(temp);

    final sent = await _chatService.sendImageMessage(
      conversationId: widget.conversationId,
      path: path,
      image: prepared,
      caption: caption,
      replyToId: reply.id,
      replyToContent: reply.content,
      replyToSenderName: reply.senderName,
    );
    _settleTemp(temp.id, sent);
  }

  Future<void> _pickLocation() async {
    final pick = await Navigator.push<ChatLocationPick>(
      context,
      MaterialPageRoute(builder: (_) => const ChatLocationPickerScreen()),
    );
    if (pick == null || !mounted) return;
    await _sendLocation(pick, _takeReply());
  }

  Future<void> _sendLocation(ChatLocationPick pick, _ReplyInfo reply) async {
    final me = _currentUserId ?? Supabase.instance.client.auth.currentUser?.id;
    if (me == null) return;
    final temp = Message.createTemp(
      conversationId: widget.conversationId,
      senderId: me,
      content: ChatLocationService.previewText(pick.label),
      messageType: MessageType.location,
      attachment: pick.toAttachment(),
      replyToId: reply.id,
      replyToContent: reply.content,
      replyToSenderName: reply.senderName,
    );
    _pendingMedia[temp.id] = _PendingMedia.location(pick, reply);
    _showTemp(temp);

    final sent = await _chatService.sendLocationMessage(
      conversationId: widget.conversationId,
      location: pick,
      replyToId: reply.id,
      replyToContent: reply.content,
      replyToSenderName: reply.senderName,
    );
    _settleTemp(temp.id, sent);
  }

  /// Yanıtlanan mesaj (varsa) alınır ve kutudan kaldırılır.
  _ReplyInfo _takeReply() {
    final reply = _replyToMessage;
    if (reply == null) return (id: null, content: null, senderName: null);
    setState(() => _replyToMessage = null);
    return (
      id: reply.id,
      content: reply.content,
      senderName: reply.senderId == _currentUserId ? 'Sen' : widget.otherUserName,
    );
  }

  void _showTemp(Message temp) {
    setState(() {
      _messagesById[temp.id] = temp;
      _newIds.add(temp.id);
    });
    _scrollToBottom(force: true);
  }

  /// Gönderim bitti: başarılıysa gerçek mesaj geçici balonun yerine geçer,
  /// değilse balon "tekrar dene" olur.
  void _settleTemp(String tempId, Message? sent) {
    if (!mounted) return;
    final temp = _messagesById[tempId];
    if (sent == null) {
      // Realtime gerçek kopyayı zaten getirdiyse geçici balon yoktur; hata
      // yalnız dönüş yanıtındadır (mesaj gönderilmiş).
      if (temp == null) return;
      setState(() {
        _messagesById[tempId] = temp.copyWith(isSending: false, isFailed: true);
      });
      _showSnack('Gönderilemedi. İnternet bağlantınızı kontrol edip tekrar deneyin.');
      return;
    }
    _pendingMedia.remove(tempId);
    _replaceTemp(tempId, sent);
  }

  /// Geçici balonu, listedeki YERİNİ koruyarak gerçek mesajla değiştirir.
  void _replaceTemp(String tempId, Message real) {
    final index = _newIds.indexOf(tempId);
    _messagesById.remove(tempId);
    if (index >= 0) _newIds.removeAt(index);
    final alreadyShown = _messagesById.containsKey(real.id) ||
        _messagesById.containsKey(_keyToId[_dupKey(real)]);
    if (!alreadyShown) {
      _messagesById[real.id] = real;
      _keyToId[_dupKey(real)] = real.id;
      _newIds.insert(index >= 0 ? index : _newIds.length, real.id);
    }
    if (mounted) setState(() {});
  }

  void _removeTemp(String tempId) {
    _pendingMedia.remove(tempId);
    if (_messagesById.remove(tempId) == null) return;
    _newIds.remove(tempId);
    if (mounted) setState(() {});
  }

  /// Gönderilmekte olan medya mesajlarından [real] ile aynı olanın geçici id'si.
  String? _pendingTempFor(Message real) {
    for (final tempId in _pendingMedia.keys) {
      final temp = _messagesById[tempId];
      if (temp == null || temp.isFailed || temp.messageType != real.messageType) continue;
      final same = switch (real.messageType) {
        MessageType.image => temp.imagePath != null && temp.imagePath == real.imagePath,
        MessageType.location =>
          temp.latitude == real.latitude && temp.longitude == real.longitude,
        MessageType.text => false,
      };
      if (same) return tempId;
    }
    return null;
  }

  /// Gönderilemeyen medya balonuna dokunuldu: tekrar dene ya da sil.
  Future<void> _showFailedMediaActions(Message temp) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.refresh_rounded, color: ChatPalette.accent),
              title: const Text('Tekrar gönder'),
              onTap: () => Navigator.pop(sheetContext, 'retry'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline, color: ChatPalette.failed),
              title: const Text('Sil'),
              onTap: () => Navigator.pop(sheetContext, 'delete'),
            ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'delete') {
      _removeTemp(temp.id);
      return;
    }
    final pending = _pendingMedia[temp.id];
    if (pending == null) return;
    _removeTemp(temp.id);
    final image = pending.image;
    final location = pending.location;
    if (image != null) {
      await _sendPreparedImage(image, pending.caption, pending.reply);
    } else if (location != null) {
      await _sendLocation(location, pending.reply);
    }
  }

  void _openImage(Message message) {
    final path = message.imagePath;
    if (path == null) return;
    final isMine = message.senderId == _currentUserId;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatImageViewerScreen(
          path: path,
          title: isMine ? 'Sen' : widget.otherUserName,
          subtitle:
              '${ChatDayLabel.format(message.createdAt)} ${ChatDayLabel.time(message.createdAt)}',
          caption: message.imageCaption,
        ),
      ),
    );
  }

  void _openLocation(Message message) {
    final lat = message.latitude, lng = message.longitude;
    if (lat == null || lng == null) return;
    final isMine = message.senderId == _currentUserId;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChatLocationViewerScreen(
          latitude: lat,
          longitude: lng,
          label: message.locationLabel,
          title: isMine ? 'Paylaştığın konum' : '${widget.otherUserName} konumu',
        ),
      ),
    );
  }

  void _showSnack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 3)),
    );
  }

  Future<void> _sendMessage() async {
    final content = _messageController.text.trim();
    if (content.isEmpty || _isSending) return;

    if (_currentUserId == null) {
      _currentUserId = Supabase.instance.client.auth.currentUser?.id;
      if (_currentUserId == null) return;
    }

    setState(() => _isSending = true);
    _messageController.clear();

    // Yanıt bilgilerini al
    final replyToId = _replyToMessage?.id;
    final replyToContent = _replyToMessage?.content;
    final replyToSenderName = _replyToMessage?.senderId == _currentUserId
        ? 'Sen'
        : widget.otherUserName;

    // Mesajı gönder (RPC içinde hem gönderen hem alıcı conversation'ına ekleniyor)
    final message = await _chatService.sendMessage(
      conversationId: widget.conversationId,
      content: content,
      replyToId: replyToId,
      replyToContent: replyToContent,
      replyToSenderName: replyToSenderName,
    );

    _replyToMessage = null; // Yanıtı temizle

    if (!mounted) return;
    setState(() => _isSending = false);

    if (message != null) {
      // RPC'den dönen mesajı merge et
      // Realtime subscription zaten aynı mesajı getirecek,
      // ama _addOrMerge ID bazlı kontrol yapıyor (duplicate önleniyor)
      _addOrMerge(message);
    } else {
      // Hata durumunda kullanıcıya bilgi ver
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Mesaj gönderilemedi. İnternet bağlantınızı kontrol edin.',
          ),
          duration: Duration(seconds: 3),
        ),
      );
    }

    // Kendi gönderdiğimiz mesaj her zaman görünür olmalı (scroll pozisyonundan bağımsız)
    _scrollToBottom(force: true);
  }

  @override
  Widget build(BuildContext context) {
    // Cache current user ID if not set
    _currentUserId ??= Supabase.instance.client.auth.currentUser?.id;
    final theme = Theme.of(context);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: ChatPalette.wallpaper,
      appBar: AppBar(
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 2,
        title: InkWell(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) =>
                    UserProfileScreen(userId: widget.otherUserId),
              ),
            );
          },
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.white.withOpacity(0.2),
                backgroundImage:
                    widget.otherUserAvatar != null &&
                        widget.otherUserAvatar!.isNotEmpty
                    ? avatarImage(widget.otherUserAvatar!)
                    : null,
                child:
                    widget.otherUserAvatar == null ||
                        widget.otherUserAvatar!.isEmpty
                    ? Text(
                        widget.otherUserName.isNotEmpty
                            ? widget.otherUserName[0].toUpperCase()
                            : '?',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.otherUserName,
                      style: const TextStyle(fontSize: 18, height: 1.15),
                      overflow: TextOverflow.ellipsis,
                    ),
                    // çevrimiçi / son görülme / yazıyor… — gösterilecek bir şey
                    // yoksa hiç yer kaplamaz.
                    PresenceStatusLine(
                      userId: widget.otherUserId,
                      typing: _peerTyping,
                      fontSize: 12,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          // Mesajlar listesi (desenli sohbet zemini üstünde)
          Expanded(
            child: ChatWallpaper(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : (_historyIds.isEmpty && _newIds.isEmpty)
                  ? _buildEmptyState()
                  : _buildOptimizedMessageList(),
            ),
          ),

          // Mesaj gönderme alanı - SafeArea ile cihazın alt navigasyon barı için padding ekle
          SafeArea(
            top: false,
            child: Container(
              color: ChatPalette.wallpaper,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Yanıt gösterimi
                  if (_replyToMessage != null) _buildReplyPreview(),

                  // Mesaj gönderme alanı
                  Padding(
                    padding: const EdgeInsets.fromLTRB(6, 8, 16, 8),
                    child: Row(
                      children: [
                        // Fotoğraf / kamera / konum (Görev 3.1)
                        IconButton(
                          tooltip: 'Fotoğraf veya konum gönder',
                          onPressed: _openAttachments,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints.tightFor(
                            width: 42,
                            height: 44,
                          ),
                          icon: const Icon(
                            Icons.add_circle_rounded,
                            color: ChatPalette.accent,
                            size: 30,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(24),
                              boxShadow: ChatPalette.bubbleShadow,
                            ),
                            child: TextField(
                              controller: _messageController,
                              focusNode: _messageFocusNode,
                              decoration: const InputDecoration(
                                hintText: 'Mesaj yazın...',
                                border: InputBorder.none,
                              ),
                              maxLines: null,
                              textCapitalization: TextCapitalization.sentences,
                              onSubmitted: (_) => _sendMessage(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          decoration: const BoxDecoration(
                            color: Colors.deepPurple,
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: _isSending
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.send, color: Colors.white),
                            onPressed: _isSending ? null : _sendMessage,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Mesaj listesi — İKİ PARÇALI, TERS eksenli (alttan yukarı) kaydırma:
  ///
  ///   üst  ▲  geçmiş (merkez parça): 0. öğe en yeni geçmiş mesajı, eski
  ///        │  sayfalar yukarı eklenir
  ///   ─────┼─ merkez (kaydırma 0)
  ///        │  yeni mesajlar: bu ekranda gelenler, aşağı eklenir
  ///   alt  ▼  sabit alt boşluk
  ///
  /// Merkezin iki yanındaki parçalar ayrı büyüdüğü için eski sayfa yüklemek
  /// de, kullanıcı yukarıdayken yeni mesaj gelmesi de görünen içeriği
  /// kaydırmaz. Açılışta kaydırma alt boşluktadır, yani liste zaten en alttadır.
  Widget _buildOptimizedMessageList() {
    final history = _historyIds
        .map((id) => _messagesById[id])
        .whereType<Message>()
        .toList();
    final fresh = _newIds
        .map((id) => _messagesById[id])
        .whereType<Message>()
        .toList();
    // Tarih ayraçları iki parçayı birlikte, eskiden yeniye okur.
    final all = [...history, ...fresh];
    final historyCount = history.length;

    return CustomScrollView(
      controller: _scrollController,
      reverse: true,
      center: _historySliverKey,
      cacheExtent: 300.0,
      slivers: [
        const SliverToBoxAdapter(child: SizedBox(height: _listBottomGap)),
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => _messageTile(all, historyCount + index),
              childCount: fresh.length,
              addAutomaticKeepAlives: false,
            ),
          ),
        ),
        SliverPadding(
          key: _historySliverKey,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (index >= historyCount) {
                  // En üstte: önceki sayfa yükleniyor.
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  );
                }
                return _messageTile(all, historyCount - 1 - index);
              },
              childCount: historyCount + (_loadingOlder ? 1 : 0),
              addAutomaticKeepAlives: false,
            ),
          ),
        ),
      ],
    );
  }

  Widget _messageTile(List<Message> all, int ascIndex) {
    return Material(
      key: ValueKey<String>(all[ascIndex].id),
      type: MaterialType.transparency,
      child: _buildMessageItem(all, ascIndex),
    );
  }

  /// Mesaj öğesi: gerekiyorsa gün hapı + balon. Aynı kişinin art arda
  /// mesajları tek öbek gibi durur (bkz. [ChatGrouping]); gün kararı Türkiye
  /// saatiyle verilir (eskiden UTC günüyle verilip Türkiye saatiyle
  /// etiketleniyordu).
  Widget _buildMessageItem(List<Message> messages, int index) {
    final message = messages[index];
    final isMe = message.senderId == _currentUserId;
    final prev = index > 0 ? messages[index - 1] : null;
    final next = index < messages.length - 1 ? messages[index + 1] : null;
    final showDate =
        prev == null || !ChatDayLabel.sameDay(prev.createdAt, message.createdAt);
    // showDate yanlışsa prev kesin var (Dart bunu bilir).
    final joinsAbove = !showDate && ChatGrouping.joins(prev, message);
    final joinsBelow = next != null && ChatGrouping.joins(message, next);

    return Column(
      children: [
        if (showDate) ChatDayPill(label: ChatDayLabel.format(message.createdAt)),
        _buildMessageBubble(
          message,
          isMe,
          joinsAbove: joinsAbove,
          joinsBelow: joinsBelow,
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Text(
            'Henüz mesaj yok',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w500,
              color: Colors.grey[700],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'İlk mesajı göndererek sohbete başlayın',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 14, color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(
    Message message,
    bool isMe, {
    bool joinsAbove = false,
    bool joinsBelow = false,
  }) {
    final timeString = ChatDayLabel.time(message.createdAt);

    // Paylaşılan gönderi / ilan kartları kendi düzenlerini korur.
    if (message.isSharedPost) {
      return _buildSharedPostBubble(message, isMe, timeString);
    }
    if (message.isSharedIlan) {
      return _buildSharedIlanBubble(message, isMe, timeString);
    }

    // Yanıt gösterimi için.
    // NOT: Hikaye yanıtlarında alıntılanacak bir mesaj yoktur (reply_to_id
    // null'dır), yalnızca reply_to_content doldurulur. Sadece id'ye bakmak
    // bu balonlardaki "Hikayene yanıt verdi" başlığını gizliyordu.
    final hasReply = message.replyToId != null ||
        (message.replyToContent?.isNotEmpty ?? false);
    final replySenderName =
        hasReply ? (message.replyToSenderName ?? 'Yanıt') : null;
    final replyContent = hasReply ? message.replyToContent : null;
    final status = isMe ? message.messageStatus : null;

    // Fotoğraf / konum (Görev 3.1)
    if (message.isImage) {
      return _swipeToReply(
        message,
        ChatImageBubble(
          path: message.imagePath!,
          aspectRatio: message.imageAspectRatio,
          caption: message.imageCaption,
          time: timeString,
          isMine: isMe,
          status: status,
          joinsAbove: joinsAbove,
          joinsBelow: joinsBelow,
          replySenderName: replySenderName,
          replyContent: replyContent,
          onTap: () => _openImage(message),
          onRetry: () => _showFailedMediaActions(message),
        ),
        copyText: message.imageCaption,
      );
    }
    if (message.isLocation) {
      return _swipeToReply(
        message,
        ChatLocationBubble(
          latitude: message.latitude!,
          longitude: message.longitude!,
          label: message.locationLabel,
          time: timeString,
          isMine: isMe,
          status: status,
          joinsAbove: joinsAbove,
          joinsBelow: joinsBelow,
          replySenderName: replySenderName,
          replyContent: replyContent,
          onTap: () => _openLocation(message),
          onRetry: () => _showFailedMediaActions(message),
        ),
      );
    }

    return _swipeToReply(
      message,
      ChatBubble(
        text: message.content,
        time: timeString,
        isMine: isMe,
        status: status,
        joinsAbove: joinsAbove,
        joinsBelow: joinsBelow,
        replySenderName: replySenderName,
        replyContent: replyContent,
      ),
      copyText: message.content,
    );
  }

  /// Sağa kaydırarak yanıtla; [copyText] varsa uzun basınca Kopyala / Metni
  /// seç / Yanıtla menüsü. Gönderimi süren geçici balon yanıtlanamaz (henüz
  /// sunucuda kimliği yok) ama yazısı kopyalanabilir.
  Widget _swipeToReply(Message message, Widget bubble, {String? copyText}) {
    final canReply = !message.id.startsWith('temp_');
    final canCopy = copyText != null && copyText.trim().isNotEmpty;
    if (!canReply && !canCopy) return bubble;
    return GestureDetector(
      onHorizontalDragEnd: canReply
          ? (details) {
              if (details.primaryVelocity != null &&
                  details.primaryVelocity! > 300) {
                _setReply(message);
              }
            }
          : null,
      onLongPress: canCopy
          ? () => ChatMessageActions.show(
                context,
                text: copyText,
                onReply: canReply ? () => _setReply(message) : null,
              )
          : null,
      child: bubble,
    );
  }

  Widget _buildSharedIlanBubble(Message message, bool isMe, String timeString) {
    final imageUrl = message.sharedIlanImageUrl;
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        width: MediaQuery.sizeOf(context).width * .72,
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.deepPurple.withOpacity(.2)),
          boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 4)],
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => IlanDetailScreen(ilanId: message.sharedIlanId!),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (imageUrl != null && imageUrl.isNotEmpty)
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(15),
                  ),
                  child: CachedNetworkImage(
                    memCacheWidth: 700,
                    imageUrl: imageUrl,
                    height: 125,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorWidget: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.campaign_outlined,
                          size: 16,
                          color: Colors.deepPurple,
                        ),
                        SizedBox(width: 5),
                        Text(
                          'İlan paylaşımı',
                          style: TextStyle(
                            color: Colors.deepPurple,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 7),
                    Text(
                      message.sharedIlanTitle ?? 'İlan',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message.sharedIlanPriceText ?? '',
                      style: const TextStyle(
                        color: Colors.deepPurple,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (message.sharedIlanLocationText?.isNotEmpty == true)
                      Text(
                        message.sharedIlanLocationText!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                      ),
                    const SizedBox(height: 7),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          timeString,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey[600],
                          ),
                        ),
                        if (isMe) ...[
                          const SizedBox(width: 4),
                          ChatStatusTicks(
                            status: message.messageStatus,
                            color: ChatPalette.theirsMeta,
                            size: 14,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Yanıt önizlemesi göster
  Widget _buildReplyPreview() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          left: BorderSide(color: Colors.deepPurple.shade300, width: 3),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _replyToMessage?.senderId == _currentUserId
                      ? 'Kendinize yanıt'
                      : 'Yanıt',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.deepPurple.shade300,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _replyToMessage?.content ?? '',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: Colors.grey[600], size: 20),
            onPressed: _cancelReply,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  /// Paylaşılan gönderi için özel bubble
  Widget _buildSharedPostBubble(Message message, bool isMe, String timeString) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.85,
        ),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              offset: const Offset(0, 1),
              blurRadius: 4,
              color: Colors.black.withOpacity(0.1),
            ),
          ],
        ),
        child: InkWell(
          onTap: () async {
            // Gönderi detayına git
            if (message.sharedPostId != null) {
              // Gönderiyi veritabanından al
              try {
                final postData = await Supabase.instance.client
                    .from('posts')
                    .select('*')
                    .eq('id', message.sharedPostId!)
                    .maybeSingle();

                if (postData != null && mounted) {
                  final post = Post.fromJson(postData);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PostDetailScreen(post: post),
                    ),
                  );
                }
              } catch (e) {
                debugPrint('Gönderi yüklenirken hata: $e');
              }
            }
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Gönderi başlığı
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(16),
                    topRight: Radius.circular(16),
                  ),
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.article,
                      size: 16,
                      color: Colors.deepPurple,
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      'Paylaşılan Gönderi',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.deepPurple,
                      ),
                    ),
                  ],
                ),
              ),
              // Gönderi içeriği
              Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (message.sharedPostAuthorName != null) ...[
                      Text(
                        message.sharedPostAuthorName!,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.black87,
                        ),
                      ),
                      const SizedBox(height: 4),
                    ],
                    if (message.sharedPostContent != null &&
                        message.sharedPostContent!.isNotEmpty)
                      Text(
                        message.sharedPostContent!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, color: Colors.grey[800]),
                      ),
                    if (message.sharedPostImageUrl != null &&
                        message.sharedPostImageUrl!.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: CachedNetworkImage(
                          memCacheWidth: 700,
                          imageUrl: message.sharedPostImageUrl!,
                          height: 150,
                          width: double.infinity,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) {
                            return const SizedBox.shrink(); // Resim yüklenemezse gizle
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Alt bilgi (zaman + tik)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      timeString,
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                    if (isMe) ...[
                      const SizedBox(width: 4),
                      ChatStatusTicks(
                            status: message.messageStatus,
                            color: ChatPalette.theirsMeta,
                            size: 14,
                          ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Yanıtlanan mesajın bilgisi (medya gönderiminde yeniden denemek için saklanır).
typedef _ReplyInfo = ({String? id, String? content, String? senderName});

/// Gönderimi süren ya da başarısız olan medya mesajının yeniden gönderim verisi.
class _PendingMedia {
  _PendingMedia.image(PreparedChatImage this.image, this.caption, this.reply)
    : location = null;

  _PendingMedia.location(ChatLocationPick this.location, this.reply)
    : image = null,
      caption = '';

  final PreparedChatImage? image;
  final String caption;
  final ChatLocationPick? location;
  final _ReplyInfo reply;
}
