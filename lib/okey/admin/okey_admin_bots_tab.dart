import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import 'okey_admin_service.dart';
import 'okey_admin_widgets.dart';

/// Bot kimliği: masada görünecek ad ve avatar.
class OkeyBotProfile {
  final String id;
  final String displayName;
  final String? avatarUrl;
  final bool isActive;

  const OkeyBotProfile({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.isActive = true,
  });

  factory OkeyBotProfile.fromMap(Map<String, dynamic> m) => OkeyBotProfile(
    id: m['id'] as String,
    displayName: m['display_name'] as String? ?? '',
    avatarUrl: m['avatar_url'] as String?,
    isActive: m['is_active'] as bool? ?? true,
  );
}

/// ADMIN — bot profilleri.
///
/// Botların daha önce kimliği yoktu; masada hepsi "Bot 1", "Bot 2" diye
/// görünüyordu. Burada tanımlanan profiller masaya oturan botlara rastgele
/// atanır ve botlar gerçek oyuncular gibi ad/avatarla görünür.
///
/// Havuz boşsa hiçbir şey bozulmaz: botlar eski davranışla "Bot N" olarak
/// görünmeye devam eder.
class OkeyAdminBotsTab extends StatefulWidget {
  const OkeyAdminBotsTab({super.key});

  @override
  State<OkeyAdminBotsTab> createState() => _OkeyAdminBotsTabState();
}

class _OkeyAdminBotsTabState extends State<OkeyAdminBotsTab> {
  final _service = OkeyAdminService();
  List<OkeyBotProfile> _profiles = [];
  bool _loading = true;
  String? _error;

  /// Henüz id'si olmayan (yeni eklenen) profil için meşgul anahtarı.
  static const _newProfileBusyKey = '__new__';

  /// Şu an fotoğrafı yüklenen/silinen profilin id'si.
  ///
  /// Tek bir `_busy` bayrağı yerine id tutulur: liste uzun olabilir ve
  /// yalnızca dokunulan kartın kilitlenmesi gerekir, hepsinin değil.
  String? _avatarBusyId;

  @override
  void initState() {
    super.initState();
    _load(initial: true);
  }

  /// [initial] yalnızca İLK yüklemede true. Sonraki tazelemelerde liste
  /// tam ekran çarkla değiştirilmez: her avatar yüklemesinden sonra kartlar
  /// kaybolup geri geliyor, liste zıplıyordu.
  Future<void> _load({bool initial = false}) async {
    // mounted kontrolü ŞART: bu metot her aksiyondan sonra await'lerin
    // ardından çağrılıyor. Admin işlem biterken sekmeyi değiştirdiğinde
    // aşağıdaki setState "setState() called after dispose()" fırlatıyordu.
    if (!mounted) return;
    if (initial) setState(() => _loading = true);
    setState(() => _error = null);
    try {
      final rows = await _service.listBotProfiles();
      if (!mounted) return;
      setState(() => _profiles = rows);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = OkeyAdminService.describeError(e));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _edit({OkeyBotProfile? existing}) async {
    final result = await showDialog<_BotDraft>(
      context: context,
      builder: (dialogContext) => _BotProfileDialog(existing: existing),
    );
    if (result == null || !mounted) return;

    final hadPhoto = (existing?.avatarUrl ?? '').isNotEmpty;
    final wantsPhotoGone =
        result.pickedBytes == null && (result.avatarUrl ?? '').isEmpty;

    setState(() => _avatarBusyId = existing?.id ?? _newProfileBusyKey);
    try {
      // "Fotoğrafı kaldır" seçildiyse ÖNCE bu çağrılır: upsert yalnızca
      // sütunları boşaltır, depodaki dosyayı bırakırdı. Sıra tersse yol
      // bilgisi silinmiş olacağı için dosya artık bulunamaz ve depoda
      // sonsuza kadar kalırdı.
      if (existing != null && hadPhoto && wantsPhotoGone) {
        await _service.clearBotAvatar(existing.id);
      }

      // ÖNCE profil kaydedilir, SONRA fotoğraf yüklenir. Sıra zorunlu:
      // dosya yolu profil id'sini içeriyor (`<id>/<zaman>.jpg`), dolayısıyla
      // yeni bir profilin fotoğrafı ancak kayıt oluştuktan sonra yüklenebilir.
      // "Bot eklerken fotoğraf yükleme" tam da bu yüzden yoktu.
      //
      // YENİ FOTOĞRAF SEÇİLDİYSE mevcut URL korunarak kaydedilir: kutu
      // dosya seçilince URL alanını temizliyor, bu da upsert'e null
      // gidip avatar_url'i BOŞALTIYORDU. Yükleme herhangi bir sebeple
      // başarısız olursa (ağ, boyut, izin) profil fotoğrafsız kalıyordu.
      final id = await _service.upsertBotProfile(
        id: existing?.id,
        displayName: result.name,
        avatarUrl: result.pickedBytes != null
            ? existing?.avatarUrl
            : result.avatarUrl,
        isActive: result.isActive,
      );

      if (result.pickedBytes != null) {
        await _service.uploadBotAvatar(
          botProfileId: id,
          fileName: result.pickedFileName ?? 'avatar.jpg',
          bytes: result.pickedBytes!,
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(OkeyAdminService.describeError(e))),
      );
    } finally {
      if (mounted) setState(() => _avatarBusyId = null);
      // HATA OLSA DA tazele: profil kaydedilip fotoğraf yüklenemediğinde
      // kayıt sunucuda VAR ama listede görünmüyordu; admin "kaydedilmedi"
      // sanıp ikinci kez ekliyor ve bu kez ad çakışması hatası alıyordu.
      await _load();
    }
  }

  /// Bot profiline fotoğraf yükler.
  ///
  /// TÜM dosyalar gösterilir, doğrulamayı BİZ yaparız — masa arka planı ve
  /// ses yüklemede olduğu gibi: uzantı filtresi bazı cihazlarda geçerli
  /// dosyaları da soluk/seçilemez bırakıyor.
  Future<void> _uploadAvatar(OkeyBotProfile p) async {
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    final bytes = file.bytes;
    if (bytes == null) {
      messenger.showSnackBar(const SnackBar(content: Text('Dosya okunamadı')));
      return;
    }
    // Ad yerine İÇERİĞE de bakılır: Android galerisinden seçilen dosya
    // çoğu zaman uzantısız bir adla geliyor ve geçerli bir JPEG
    // "Desteklenmeyen dosya" diye reddediliyordu.
    final ext = OkeyAdminService.resolveImageExtension(file.name, bytes);
    if (ext == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Bu dosya bir görsel değil: ${file.name}\n'
            'Desteklenen formatlar: ${OkeyAdminService.supportedImageLabel}',
          ),
        ),
      );
      return;
    }
    if (bytes.length > OkeyAdminService.botAvatarMaxBytes) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Fotoğraf 2 MB\'dan küçük olmalı')),
      );
      return;
    }

    setState(() => _avatarBusyId = p.id);
    try {
      await _service.uploadBotAvatar(
        botProfileId: p.id,
        fileName: 'avatar.$ext',
        bytes: bytes,
      );
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('${p.displayName} fotoğrafı güncellendi')),
      );
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text(OkeyAdminService.describeError(e))),
      );
    } finally {
      if (mounted) setState(() => _avatarBusyId = null);
      await _load();
    }
  }

  Future<void> _clearAvatar(OkeyBotProfile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Fotoğraf kaldırılsın mı?'),
        content: Text(
          '${p.displayName} masada fotoğrafsız görünecek. '
          'Dosya depodan da silinir ve bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Kaldır'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _avatarBusyId = p.id);
    try {
      await _service.clearBotAvatar(p.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(OkeyAdminService.describeError(e))),
      );
    } finally {
      if (mounted) setState(() => _avatarBusyId = null);
      await _load();
    }
  }

  Future<void> _delete(OkeyBotProfile p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('${p.displayName} silinsin mi?'),
        content: const Text(
          'Bu profil bir masada kullanılıyorsa o bot yeniden '
          '"Bot N" olarak görünür.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sil'),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _avatarBusyId = p.id);
    try {
      await _service.deleteBotProfile(p.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(OkeyAdminService.describeError(e))),
      );
    } finally {
      if (mounted) setState(() => _avatarBusyId = null);
      await _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    final activeCount = _profiles.where((p) => p.isActive).length;

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Bot Profilleri',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              FilledButton.icon(
                onPressed: () => _edit(),
                icon: const Icon(Icons.add),
                label: const Text('Bot Ekle'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Ayarlar sekmesiyle aynı desen: kartlar sarmalı değil, yatay
          // kaydırmalı — yükseklik her ekranda sabit kalır.
          OkeyStatStrip(
            cards: [
              OkeyStatCard(
                icon: Icons.smart_toy,
                label: 'Toplam Profil',
                value: '${_profiles.length}',
                gradient: [Colors.indigo.shade400, Colors.indigo.shade600],
              ),
              OkeyStatCard(
                icon: Icons.check_circle,
                label: 'Aktif Profil',
                value: '$activeCount',
                gradient: [Colors.green.shade400, Colors.green.shade600],
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            color: Colors.blue.shade50,
            child: const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'Masaya oturan botlar bu havuzdan rastgele seçilir ve '
                'burada tanımladığın ad/fotoğrafla görünür — masada bot '
                'olduklarını belli eden hiçbir işaret yoktur.\n'
                'Fotoğraf yüklemek için avatara ya da fotoğraf makinesi '
                'düğmesine dokun (JPG/PNG/WEBP, en fazla 2 MB).\n'
                'Aynı masada aynı profil iki kez kullanılmaz — 3 bot için '
                'en az 3 aktif profil önerilir.\n'
                'Havuz boşsa botlar yedek adlarla (Yusuf K., Elif A. …) '
                'görünür.',
                style: TextStyle(fontSize: 12),
              ),
            ),
          ),
          if (_error != null)
            Card(
              color: Colors.red.shade50,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Bot profilleri alınamadı: $_error',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            ),
          const SizedBox(height: 8),
          if (_profiles.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 32),
              child: Center(
                child: Text(
                  'Henüz bot profili yok',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            )
          else
            ..._profiles.map((p) {
              final hasPhoto = p.avatarUrl != null && p.avatarUrl!.isNotEmpty;
              final busy = _avatarBusyId == p.id;

              return Card(
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  // AVATARIN KENDİSİ yükleme düğmesidir. Fotoğrafı
                  // değiştirmek isteyen adminin ilk dokunacağı yer zaten
                  // fotoğrafın olduğu yer; ayrı bir düğme aramak zorunda
                  // kalmasın diye köşesine küçük bir kamera rozeti konur.
                  leading: InkWell(
                    onTap: busy ? null : () => _uploadAvatar(p),
                    borderRadius: BorderRadius.circular(24),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        CircleAvatar(
                          backgroundColor: Colors.deepPurple.shade50,
                          backgroundImage: hasPhoto
                              ? NetworkImage(p.avatarUrl!)
                              : null,
                          // onBackgroundImageError ŞART: bu olmadan bozuk
                          // ya da erişilemez bir avatar bağlantısı,
                          // yakalanmamış bir görüntü hatası olarak Flutter'a
                          // düşüyor ve hata ayıklama derlemesinde kırmızı
                          // hata olarak görünüyordu.
                          //
                          // İçi bilerek BOŞ: burada setState çağırmak
                          // görüntüyü yeniden yükletip aynı hatayı sonsuz
                          // döngüye sokardı. Yüklenemeyen avatar sessizce
                          // düz renk kalır.
                          onBackgroundImageError: hasPhoto ? (_, _) {} : null,
                          child: busy
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : (hasPhoto
                                    ? null
                                    : const Icon(
                                        Icons.person,
                                        color: Colors.deepPurple,
                                      )),
                        ),
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              color: Colors.deepPurple,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white,
                                width: 1.5,
                              ),
                            ),
                            child: const Icon(
                              Icons.photo_camera,
                              size: 10,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  title: Text(
                    p.displayName,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: p.isActive ? null : Colors.grey,
                    ),
                  ),
                  subtitle: Text(
                    '${p.isActive ? 'Aktif' : 'Pasif — masalarda kullanılmıyor'}'
                    '${hasPhoto ? '' : ' · fotoğraf yok'}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: hasPhoto
                            ? 'Fotoğrafı değiştir'
                            : 'Fotoğraf yükle',
                        icon: const Icon(Icons.add_a_photo_outlined),
                        onPressed: busy ? null : () => _uploadAvatar(p),
                      ),
                      if (hasPhoto)
                        IconButton(
                          tooltip: 'Fotoğrafı kaldır',
                          icon: const Icon(Icons.hide_image_outlined),
                          onPressed: busy ? null : () => _clearAvatar(p),
                        ),
                      IconButton(
                        tooltip: 'Düzenle',
                        icon: const Icon(Icons.edit),
                        onPressed: () => _edit(existing: p),
                      ),
                      IconButton(
                        tooltip: 'Sil',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => _delete(p),
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }
}

/// Bot profili düzenleme kutusunun sonucu.
class _BotDraft {
  final String name;
  final bool isActive;

  /// Elle yapıştırılan bağlantı (dosya seçildiyse null).
  final String? avatarUrl;

  /// Seçilen dosyanın içeriği — kutu kapandıktan SONRA yüklenir.
  final Uint8List? pickedBytes;
  final String? pickedFileName;

  const _BotDraft({
    required this.name,
    required this.isActive,
    this.avatarUrl,
    this.pickedBytes,
    this.pickedFileName,
  });
}

/// Bot profili ekleme/düzenleme kutusu.
///
/// ## Neden ayrı bir StatefulWidget
///
/// Eskiden bu bir `StatefulBuilder` idi ve denetleyiciler kutunun DIŞINDA
/// yaratılıp `showDialog` döner dönmez `dispose()` ediliyor, hemen ARDINDAN
/// `nameCtrl.text` okunuyordu — yani atılmış bir nesneden değer okunuyordu.
/// Çalışıyor olması tesadüf; denetleyicilerin ömrü artık kutunun kendi
/// State'ine ait.
///
/// Asıl kazanç fotoğraf: dosya kutunun İÇİNDE seçilir ve içeriği bellekte
/// tutulur. Böylece YENİ bir bot eklerken de fotoğraf seçilebilir — önce
/// profil kaydedilir, dönen id ile dosya yüklenir.
class _BotProfileDialog extends StatefulWidget {
  final OkeyBotProfile? existing;

  const _BotProfileDialog({this.existing});

  @override
  State<_BotProfileDialog> createState() => _BotProfileDialogState();
}

class _BotProfileDialogState extends State<_BotProfileDialog> {
  late final TextEditingController _nameCtrl = TextEditingController(
    text: widget.existing?.displayName ?? '',
  );
  late final TextEditingController _urlCtrl = TextEditingController(
    text: widget.existing?.avatarUrl ?? '',
  );

  late bool _active = widget.existing?.isActive ?? true;

  Uint8List? _pickedBytes;
  String? _pickedName;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pick() async {
    // TÜM dosyalar gösterilir, doğrulamayı BİZ yaparız — uzantı filtresi
    // bazı cihazlarda geçerli dosyaları da seçilemez hale getiriyor.
    final result = await FilePicker.pickFiles(
      type: FileType.any,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;

    String? problem;
    String? ext;
    final bytes = file.bytes;
    if (bytes == null) {
      problem = 'Dosya okunamadı';
    } else {
      // Doğrulama ADA DEĞİL İÇERİĞE bakar: galeriden seçilen dosya sık sık
      // uzantısız bir adla geliyor ve geçerli bir JPEG reddediliyordu.
      ext = OkeyAdminService.resolveImageExtension(file.name, bytes);
      if (ext == null) {
        problem =
            'Bu dosya bir görsel değil. Kabul edilenler: '
            '${OkeyAdminService.supportedImageLabel}';
      } else if (bytes.length > OkeyAdminService.botAvatarMaxBytes) {
        problem = 'Fotoğraf 2 MB\'dan küçük olmalı';
      }
    }

    if (!mounted) return;
    setState(() {
      _error = problem;
      if (problem == null) {
        _pickedBytes = bytes;
        // Ada uzantı EKLENİR: depodaki yol ve MIME türü buradan türetiliyor.
        _pickedName = OkeyAdminService.extensionOf(file.name) == ext
            ? file.name
            : 'avatar.$ext';
        // Dosya seçildiyse elle yazılmış bağlantı artık geçersiz: yükleme
        // kendi URL'ini üretip yazacak.
        _urlCtrl.clear();
      }
    });
  }

  Widget _preview() {
    const size = 64.0;
    final url = _urlCtrl.text.trim();

    Widget inner;
    if (_pickedBytes != null) {
      inner = Image.memory(_pickedBytes!, fit: BoxFit.cover);
    } else if (url.isNotEmpty) {
      inner = Image.network(
        url,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.broken_image, color: Colors.grey),
      );
    } else {
      inner = const Icon(Icons.person, size: 30, color: Colors.deepPurple);
    }

    return ClipOval(
      child: Container(
        width: size,
        height: size,
        color: Colors.deepPurple.shade50,
        child: inner,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasPhoto = _pickedBytes != null || _urlCtrl.text.trim().isNotEmpty;

    return AlertDialog(
      title: Text(widget.existing == null ? 'Yeni Bot Profili' : 'Bot Profili'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _preview(),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      OutlinedButton.icon(
                        onPressed: _pick,
                        icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                        label: Text(
                          hasPhoto ? 'Fotoğrafı değiştir' : 'Fotoğraf seç',
                        ),
                      ),
                      if (_pickedName != null)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            _pickedName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.grey,
                            ),
                          ),
                        ),
                      if (hasPhoto)
                        TextButton.icon(
                          onPressed: () => setState(() {
                            _pickedBytes = null;
                            _pickedName = null;
                            _urlCtrl.clear();
                          }),
                          icon: const Icon(Icons.close, size: 16),
                          label: const Text('Fotoğrafı kaldır'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                ),
              ),
            TextField(
              controller: _nameCtrl,
              maxLength: 24,
              decoration: const InputDecoration(
                labelText: 'Görünen ad',
                helperText: 'Masada bu ad görünür (2-24 karakter)',
              ),
            ),
            TextField(
              controller: _urlCtrl,
              enabled: _pickedBytes == null,
              onChanged: (_) => setState(() {}),
              decoration: const InputDecoration(
                labelText: 'veya fotoğraf bağlantısı',
                helperText: 'Dosya seçtiysen buna gerek yok',
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _active,
              onChanged: (v) => setState(() => _active = v),
              title: const Text('Aktif'),
              subtitle: const Text(
                'Kapalıysa yeni masalarda kullanılmaz',
                style: TextStyle(fontSize: 11),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            if (name.length < 2) {
              setState(() => _error = 'Ad en az 2 karakter olmalı');
              return;
            }
            final url = _urlCtrl.text.trim();
            Navigator.of(context).pop(
              _BotDraft(
                name: name,
                isActive: _active,
                avatarUrl: url.isEmpty ? null : url,
                pickedBytes: _pickedBytes,
                pickedFileName: _pickedName,
              ),
            );
          },
          child: const Text('Kaydet'),
        ),
      ],
    );
  }
}
