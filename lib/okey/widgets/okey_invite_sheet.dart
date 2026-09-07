import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/okey_invite_service.dart';
import '../theme/okey_theme.dart';
import '../theme/okey_ui.dart';

/// Bekleme odasından açılan "arkadaşını davet et" sayfası (bottom sheet).
///
/// Liste, oyuncunun TAKİP ETTİĞİ kişilerdir; karşılıklı takip edenler
/// (arkadaşlar) başta gelir ve bir rozetle ayrılır. Kural sunucuda da aynıdır
/// — burada uygulanan tek şey, davet edilemeyecek satırın düğmesini kapatmak.
///
/// Davet, karşı tarafa BİLDİRİM (ve push) gönderir; arkadaş masaya oturunca
/// davet EDENE de bildirim döner (bkz. 20260905000002 göçü).
Future<void> showOkeyInviteSheet(
  BuildContext context, {
  required String roomId,
  String? joinCode,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _OkeyInviteSheet(roomId: roomId, joinCode: joinCode),
  );
}

class _OkeyInviteSheet extends StatefulWidget {
  final String roomId;
  final String? joinCode;

  const _OkeyInviteSheet({required this.roomId, this.joinCode});

  @override
  State<_OkeyInviteSheet> createState() => _OkeyInviteSheetState();
}

class _OkeyInviteSheetState extends State<_OkeyInviteSheet> {
  final OkeyInviteService _service = OkeyInviteService();
  final TextEditingController _searchController = TextEditingController();

  List<OkeyInviteCandidate> _people = const [];
  bool _loading = true;
  String? _error;

  /// Davet isteği SÜREN kişi — aynı satıra iki kez basılmasın.
  final Set<String> _sending = <String>{};

  /// Arama kutusuna her harfte sunucuya gitmemek için.
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final rows = await _service.invitableFriends(
        widget.roomId,
        search: _searchController.text.trim().isEmpty
            ? null
            : _searchController.text.trim(),
      );
      if (!mounted) return;
      setState(() {
        _people = rows;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = OkeyInviteService.friendlyError(e);
        _loading = false;
      });
    }
  }

  void _onSearchChanged(String _) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 350), _load);
  }

  Future<void> _invite(OkeyInviteCandidate person) async {
    setState(() => _sending.add(person.userId));
    try {
      await _service.invite(roomId: widget.roomId, inviteeId: person.userId);
      if (!mounted) return;
      setState(() {
        _sending.remove(person.userId);
        // Satırı yeniden yüklemeden "davet edildi"ye çevir: sunucudan
        // gelecek yanıt zaten aynı şeyi söyleyecek, ama kullanıcı düğmeye
        // bastığı anda karşılık görmeli.
        _people = _people
            .map(
              (p) => p.userId == person.userId ? p.copyWith(invited: true) : p,
            )
            .toList();
      });
      _toast('${person.displayName} masaya davet edildi.');
    } catch (e) {
      if (!mounted) return;
      setState(() => _sending.remove(person.userId));
      _toast(OkeyInviteService.friendlyError(e));
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final viewInsets = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      // Klavye açıldığında liste ve arama kutusu klavyenin ARKASINDA kalmaz.
      padding: EdgeInsets.only(bottom: viewInsets),
      child: DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) => Container(
          decoration: const BoxDecoration(
            gradient: OkeyUI.screenGradient,
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(OkeyUI.radiusLg),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: OkeyUI.gapSm),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: OkeyUI.textFaint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  14,
                  OkeyUI.gap,
                  14,
                  OkeyUI.gapSm,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.person_add_alt_1,
                      size: 20,
                      color: OkeyColors.accentGold,
                    ),
                    const SizedBox(width: OkeyUI.gapSm),
                    const Expanded(
                      child: Text('Arkadaşını davet et', style: OkeyUI.title),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: OkeyUI.textDim),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: TextField(
                  controller: _searchController,
                  onChanged: _onSearchChanged,
                  style: const TextStyle(color: OkeyUI.text),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: 'İsim ara',
                    hintStyle: const TextStyle(color: OkeyUI.textFaint),
                    prefixIcon: const Icon(
                      Icons.search,
                      color: OkeyUI.textDim,
                      size: 20,
                    ),
                    filled: true,
                    fillColor: OkeyUI.cardFill,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(OkeyUI.radiusSm),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              if (widget.joinCode != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, OkeyUI.gapSm, 14, 0),
                  child: _JoinCodeRow(code: widget.joinCode!),
                ),
              const SizedBox(height: OkeyUI.gapSm),
              Expanded(child: _buildBody(scrollController)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(ScrollController controller) {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: OkeyColors.accentGold),
      );
    }
    if (_error != null) {
      return ListView(
        controller: controller,
        children: [
          OkeyEmptyState(
            icon: Icons.error_outline,
            title: 'Liste alınamadı',
            message: _error!,
            action: OkeyButton(
              label: 'Tekrar dene',
              icon: Icons.refresh,
              expand: false,
              onPressed: _load,
            ),
          ),
        ],
      );
    }
    if (_people.isEmpty) {
      final searching = _searchController.text.trim().isNotEmpty;
      return ListView(
        controller: controller,
        children: [
          OkeyEmptyState(
            icon: searching ? Icons.search_off : Icons.group_off,
            title: searching ? 'Kimse bulunamadı' : 'Davet edecek kimse yok',
            message: searching
                ? 'Bu isimde takip ettiğin biri yok.'
                : 'Yalnızca takip ettiğin kişileri davet edebilirsin. '
                      'Arkadaşlarını takip et, sonra buradan masaya çağır. '
                      'Dilersen davet kodunu da paylaşabilirsin.',
          ),
        ],
      );
    }

    return ListView.separated(
      controller: controller,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, OkeyUI.gapXl),
      itemCount: _people.length,
      separatorBuilder: (_, _) => const SizedBox(height: OkeyUI.gapSm),
      itemBuilder: (_, i) {
        final person = _people[i];
        return _CandidateRow(
          person: person,
          busy: _sending.contains(person.userId),
          onInvite: () => _invite(person),
        );
      },
    );
  }
}

class _CandidateRow extends StatelessWidget {
  final OkeyInviteCandidate person;
  final bool busy;
  final VoidCallback onInvite;

  const _CandidateRow({
    required this.person,
    required this.busy,
    required this.onInvite,
  });

  @override
  Widget build(BuildContext context) {
    return OkeyCard(
      child: Row(
        children: [
          OkeyAvatar(url: person.avatarUrl, size: 40),
          const SizedBox(width: OkeyUI.gap),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  person.displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: OkeyUI.body.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text('${person.points} puan', style: OkeyUI.caption),
                    if (person.isFriend) ...[
                      const SizedBox(width: OkeyUI.gapSm),
                      const OkeyPill(text: 'Arkadaş', icon: Icons.favorite),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: OkeyUI.gapSm),
          SizedBox(
            width: 116,
            child: person.inRoom
                ? const OkeyPill(text: 'Masada', icon: Icons.chair_alt)
                : person.invited
                ? const OkeyPill(text: 'Davet edildi', icon: Icons.check)
                : OkeyButton(
                    label: 'Davet et',
                    icon: Icons.send,
                    busy: busy,
                    onPressed: busy ? null : onInvite,
                  ),
          ),
        ],
      ),
    );
  }
}

/// Uygulamayı kullanmayan/takip etmediğin arkadaşlar için kaçış yolu.
class _JoinCodeRow extends StatelessWidget {
  final String code;

  const _JoinCodeRow({required this.code});

  @override
  Widget build(BuildContext context) {
    return OkeyCard(
      padding: const EdgeInsets.symmetric(
        horizontal: OkeyUI.gap,
        vertical: OkeyUI.gapSm,
      ),
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: code));
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Davet kodu kopyalandı')));
      },
      child: Row(
        children: [
          const Icon(Icons.vpn_key, size: 16, color: OkeyColors.accentGold),
          const SizedBox(width: OkeyUI.gapSm),
          const Expanded(
            child: Text('Davet kodunu kopyala', style: OkeyUI.caption),
          ),
          Text(
            code,
            maxLines: 1,
            style: const TextStyle(
              color: OkeyColors.accentGold,
              fontWeight: FontWeight.w900,
              letterSpacing: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
