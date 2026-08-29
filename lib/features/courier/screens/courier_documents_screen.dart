// ignore_for_file: use_build_context_synchronously, deprecated_member_use

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';

/// Kurye kimlik/ehliyet/araç evraklarını girdiği ve fotoğraflarını yüklediği
/// ekran. Kaydedilen veriler admin panelinde "Kurye Yönetimi" bölümünden
/// incelenip onaylanır/reddedilir (bkz. submit_courier_documents ve
/// admin_review_courier_document RPC'leri).
class CourierDocumentsScreen extends StatefulWidget {
  const CourierDocumentsScreen({super.key});

  @override
  State<CourierDocumentsScreen> createState() =>
      _CourierDocumentsScreenState();
}

enum _DocSlot { idFront, idBack, license, vehicle }

class _CourierDocumentsScreenState extends State<CourierDocumentsScreen> {
  final _fullNameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _plateController = TextEditingController();

  bool _isLoading = true;
  bool _isSaving = false;
  Map<String, dynamic>? _existing;

  // Yeni seçilen fotoğraflar (henüz yüklenmedi)
  final Map<_DocSlot, XFile> _pickedFiles = {};
  final Map<_DocSlot, Uint8List> _pickedBytes = {};

  // Daha önce yüklenmiş fotoğrafların önizleme URL'leri (signed url)
  final Map<_DocSlot, String> _existingPreviewUrls = {};

  // Selfie doğrulama videosu
  XFile? _pickedVideo;
  String? _existingVideoPath;
  String? _existingVideoUrl;

  String get _userId => Supabase.instance.client.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _phoneController.dispose();
    _plateController.dispose();
    super.dispose();
  }

  String _pathColumn(_DocSlot slot) {
    switch (slot) {
      case _DocSlot.idFront:
        return 'id_front_path';
      case _DocSlot.idBack:
        return 'id_back_path';
      case _DocSlot.license:
        return 'license_photo_path';
      case _DocSlot.vehicle:
        return 'vehicle_photo_path';
    }
  }

  String _slotLabel(_DocSlot slot) {
    switch (slot) {
      case _DocSlot.idFront:
        return 'Kimlik (Ön Yüz)';
      case _DocSlot.idBack:
        return 'Kimlik (Arka Yüz)';
      case _DocSlot.license:
        return 'Ehliyet Fotoğrafı';
      case _DocSlot.vehicle:
        return 'Motor / Plaka Fotoğrafı';
    }
  }

  Future<void> _loadExisting() async {
    setState(() => _isLoading = true);
    try {
      if (_userId.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }

      // Profil adı/telefonu varsayılan olarak formu doldurur.
      final profile = await Supabase.instance.client
          .from('profiles')
          .select('full_name, phone')
          .eq('id', _userId)
          .maybeSingle();

      final doc = await Supabase.instance.client
          .from('courier_documents')
          .select()
          .eq('courier_id', _userId)
          .maybeSingle();

      _existing = doc;
      _fullNameController.text =
          (doc?['full_name'] as String?) ?? (profile?['full_name'] as String?) ?? '';
      _phoneController.text =
          (doc?['phone'] as String?) ?? (profile?['phone'] as String?) ?? '';
      _plateController.text = (doc?['plate_number'] as String?) ?? '';

      if (doc != null) {
        for (final slot in _DocSlot.values) {
          final path = doc[_pathColumn(slot)] as String?;
          if (path != null && path.isNotEmpty) {
            try {
              final url = await Supabase.instance.client.storage
                  .from('courier-documents')
                  .createSignedUrl(path, 3600);
              _existingPreviewUrls[slot] = url;
            } catch (e) {
              debugPrint('Signed url alınamadı ($slot): $e');
            }
          }
        }

        _existingVideoPath = doc['selfie_video_path'] as String?;
        if (_existingVideoPath != null && _existingVideoPath!.isNotEmpty) {
          try {
            _existingVideoUrl = await Supabase.instance.client.storage
                .from('courier-documents')
                .createSignedUrl(_existingVideoPath!, 3600);
          } catch (e) {
            debugPrint('Selfie video signed url alınamadı: $e');
          }
        }
      }

      if (mounted) setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Kurye evrakları yüklenirken hata: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickImage(_DocSlot slot) async {
    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        maxHeight: 1600,
        imageQuality: 90,
      );
      if (image == null) return;

      final bytes = await image.readAsBytes();
      if (!mounted) return;
      setState(() {
        _pickedFiles[slot] = image;
        _pickedBytes[slot] = bytes;
      });
    } catch (e) {
      debugPrint('Fotoğraf seçme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Fotoğraf seçilemedi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _pickVideo(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final video = await picker.pickVideo(
        source: source,
        maxDuration: const Duration(seconds: 30),
      );
      if (video == null) return;

      if (!mounted) return;
      setState(() => _pickedVideo = video);
    } catch (e) {
      debugPrint('Video seçme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Video seçilemedi: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _showVideoSourceSheet() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.videocam_outlined),
              title: const Text('Kamera ile Video Çek'),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.video_library_outlined),
              title: const Text('Galeriden Seç'),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
    if (source != null) await _pickVideo(source);
  }

  void _playVideo(String url) {
    showDialog(
      context: context,
      builder: (context) => _VideoPreviewDialog(url: url),
    );
  }

  Future<String?> _uploadVideoIfPicked() async {
    final file = _pickedVideo;
    if (file == null) {
      // Yeni seçim yoksa mevcut kaydı koru.
      return _existingVideoPath;
    }
    final extension = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : 'mp4';
    final fileName = 'selfie_video_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final path = '$_userId/$fileName';
    final bytes = await file.readAsBytes();
    await Supabase.instance.client.storage
        .from('courier-documents')
        .uploadBinary(path, bytes, fileOptions: const FileOptions(upsert: true));
    return path;
  }

  Future<String?> _uploadIfPicked(_DocSlot slot) async {
    final file = _pickedFiles[slot];
    if (file == null) {
      // Yeni seçim yoksa mevcut kaydı koru.
      return _existing?[_pathColumn(slot)] as String?;
    }
    final extension = file.name.contains('.') ? file.name.split('.').last.toLowerCase() : 'jpg';
    final fileName = '${slot.name}_${DateTime.now().millisecondsSinceEpoch}.$extension';
    final path = '$_userId/$fileName';
    final bytes = await file.readAsBytes();
    await Supabase.instance.client.storage
        .from('courier-documents')
        .uploadBinary(path, bytes, fileOptions: const FileOptions(upsert: true));
    return path;
  }

  Future<void> _submit() async {
    if (_userId.isEmpty) return;

    final fullName = _fullNameController.text.trim();
    final phone = _phoneController.text.trim();
    final plate = _plateController.text.trim();

    if (fullName.isEmpty || phone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Ad soyad ve telefon zorunludur'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final hasAnyPhoto = _DocSlot.values.any(
      (slot) => _pickedFiles.containsKey(slot) || (_existing?[_pathColumn(slot)] != null),
    );
    if (!hasAnyPhoto) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('En az bir belge fotoğrafı ekleyin'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final hasVideo = _pickedVideo != null ||
        (_existingVideoPath != null && _existingVideoPath!.isNotEmpty);
    if (!hasVideo) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Yüzünüzü, motorunuzu ve plakanızı gösteren selfie videosu zorunludur',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final idFrontPath = await _uploadIfPicked(_DocSlot.idFront);
      final idBackPath = await _uploadIfPicked(_DocSlot.idBack);
      final licensePath = await _uploadIfPicked(_DocSlot.license);
      final vehiclePath = await _uploadIfPicked(_DocSlot.vehicle);
      final selfieVideoPath = await _uploadVideoIfPicked();

      await Supabase.instance.client.rpc('submit_courier_documents', params: {
        'p_full_name': fullName,
        'p_phone': phone,
        'p_id_front_path': idFrontPath,
        'p_id_back_path': idBackPath,
        'p_license_photo_path': licensePath,
        'p_vehicle_photo_path': vehiclePath,
        'p_plate_number': plate.isEmpty ? null : plate,
        'p_selfie_video_path': selfieVideoPath,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Evraklarınız gönderildi, admin onayı bekleniyor'),
            backgroundColor: Colors.green,
          ),
        );
        _pickedFiles.clear();
        _pickedBytes.clear();
        _pickedVideo = null;
        await _loadExisting();
      }
    } catch (e) {
      debugPrint('Evrak gönderme hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Hata: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Widget _statusBanner() {
    final status = _existing?['status'] as String?;
    if (status == null) return const SizedBox.shrink();

    late final Color bg;
    late final Color fg;
    late final IconData icon;
    late final String text;

    switch (status) {
      case 'approved':
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
        icon = Icons.verified;
        text = 'Evraklarınız onaylandı';
        break;
      case 'rejected':
        bg = Colors.red.shade50;
        fg = Colors.red.shade800;
        icon = Icons.error_outline;
        text = 'Evraklarınız reddedildi';
        break;
      default:
        bg = Colors.orange.shade50;
        fg = Colors.orange.shade800;
        icon = Icons.hourglass_top;
        text = 'Evraklarınız inceleniyor';
    }

    final note = _existing?['admin_note'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.bold)),
                if (status == 'rejected' && note != null && note.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text('Gerekçe: $note', style: TextStyle(color: fg, fontSize: 12)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _photoSlot(_DocSlot slot) {
    final bytes = _pickedBytes[slot];
    final previewUrl = _existingPreviewUrls[slot];

    Widget preview;
    if (bytes != null) {
      preview = Image.memory(bytes, fit: BoxFit.cover);
    } else if (previewUrl != null) {
      preview = Image.network(
        previewUrl,
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) =>
            const Center(child: Icon(Icons.broken_image, color: Colors.grey)),
      );
    } else {
      preview = Center(
        child: Icon(Icons.add_a_photo_outlined, color: Colors.grey.shade400, size: 32),
      );
    }

    return GestureDetector(
      onTap: () => _pickImage(slot),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _slotLabel(slot),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Container(
            height: 140,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade300),
            ),
            clipBehavior: Clip.antiAlias,
            child: preview,
          ),
        ],
      ),
    );
  }

  Widget _videoInstructionNote() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.blue.shade50,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.shade200),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Colors.blue.shade700, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Kimlik doğrulama için kısa bir video çekin: önce kendi '
              'yüzünüzü net şekilde gösterin, ardından motorunuzu ve '
              'plakanızı gösterin. Video admin onayına gönderilecek ve '
              'onaylanmadan teslimat alamazsınız.',
              style: TextStyle(fontSize: 12, color: Colors.blue.shade900),
            ),
          ),
        ],
      ),
    );
  }

  Widget _videoSlot() {
    final hasNewVideo = _pickedVideo != null;
    final hasExistingVideo = _existingVideoUrl != null;

    return GestureDetector(
      onTap: _showVideoSourceSheet,
      child: Container(
        height: 120,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: hasNewVideo || hasExistingVideo
            ? Row(
                children: [
                  const SizedBox(width: 16),
                  Icon(Icons.check_circle, color: Colors.green.shade600, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      hasNewVideo
                          ? 'Yeni video seçildi: ${_pickedVideo!.name}'
                          : 'Video yüklendi',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                  if (!hasNewVideo && hasExistingVideo)
                    TextButton.icon(
                      onPressed: () => _playVideo(_existingVideoUrl!),
                      icon: const Icon(Icons.play_circle_outline, size: 18),
                      label: const Text('Oynat'),
                    ),
                  TextButton(
                    onPressed: _showVideoSourceSheet,
                    child: const Text('Değiştir'),
                  ),
                  const SizedBox(width: 8),
                ],
              )
            : Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.videocam_outlined, color: Colors.grey.shade400, size: 32),
                    const SizedBox(height: 4),
                    Text(
                      'Selfie video ekle',
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kurye Evraklarım'),
        backgroundColor: Colors.teal,
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _statusBanner(),
                  const Text(
                    'Kimlik Bilgileri',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _fullNameController,
                    decoration: InputDecoration(
                      labelText: 'Ad Soyad',
                      prefixIcon: const Icon(Icons.person),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _phoneController,
                    keyboardType: TextInputType.phone,
                    decoration: InputDecoration(
                      labelText: 'Telefon Numarası',
                      prefixIcon: const Icon(Icons.phone),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _plateController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      labelText: 'Motor Plakası',
                      hintText: '34 ABC 123',
                      prefixIcon: const Icon(Icons.two_wheeler),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Belge Fotoğrafları',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Kimlik ön/arka, ehliyet ve motor fotoğrafını net şekilde yükleyin',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _photoSlot(_DocSlot.idFront)),
                      const SizedBox(width: 12),
                      Expanded(child: _photoSlot(_DocSlot.idBack)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(child: _photoSlot(_DocSlot.license)),
                      const SizedBox(width: 12),
                      Expanded(child: _photoSlot(_DocSlot.vehicle)),
                    ],
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Selfie Doğrulama Videosu',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  _videoInstructionNote(),
                  const SizedBox(height: 12),
                  _videoSlot(),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: primary,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSaving
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2,
                              ),
                            )
                          : const Text('Evrakları Gönder'),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}

class _VideoPreviewDialog extends StatefulWidget {
  const _VideoPreviewDialog({required this.url});

  final String url;

  @override
  State<_VideoPreviewDialog> createState() => _VideoPreviewDialogState();
}

class _VideoPreviewDialogState extends State<_VideoPreviewDialog> {
  VideoPlayerController? _controller;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final controller = VideoPlayerController.networkUrl(Uri.parse(widget.url));
    try {
      await controller.initialize();
      await controller.play();
      if (mounted) {
        setState(() => _controller = controller);
      }
    } catch (e) {
      debugPrint('Video oynatma hatası: $e');
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.black,
      insetPadding: const EdgeInsets.all(12),
      child: _hasError
          ? const Padding(
              padding: EdgeInsets.all(32),
              child: Text(
                'Video oynatılamadı',
                style: TextStyle(color: Colors.white),
              ),
            )
          : _controller == null
              ? const Padding(
                  padding: EdgeInsets.all(32),
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : AspectRatio(
                  aspectRatio: _controller!.value.aspectRatio,
                  child: GestureDetector(
                    onTap: () {
                      setState(() {
                        _controller!.value.isPlaying
                            ? _controller!.pause()
                            : _controller!.play();
                      });
                    },
                    child: VideoPlayer(_controller!),
                  ),
                ),
    );
  }
}
