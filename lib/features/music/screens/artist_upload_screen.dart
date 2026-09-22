import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../models/music_track.dart';
import '../services/mp3_clipper.dart';
import '../services/music_attach_service.dart';
import '../services/music_catalog_service.dart';
import '../services/music_library_service.dart';
import '../services/music_settings_service.dart';
import '../widgets/music_ui.dart';

/// Yerel sanatçıların kendi şarkılarını Cizre Radyo'ya göndermesi.
///
/// ## Neden onaydan geçiyor
///
/// Yüklenen her dosya katalogda herkese açılacak. Onay adımı olmadan bu, bir
/// dosya yükleme kutusuna dönüşür ve uygulamanın sunucusunda kimin neyi
/// barındırdığını kimse bilmez. Admin dinleyip onayladığında ise katalogdaki
/// her parçanın arkasında bir insan kararı olur.
///
/// ## Hak beyanı neden zorunlu
///
/// Onay kutusu bir formalite değil: beyan başvuruyla birlikte veritabanında
/// KALICI olarak saklanıyor (`music_track_submissions.rights_confirmed`).
/// Telif şikâyeti geldiğinde kimin neyi beyan ettiği gösterilebilir olmalı.
class ArtistUploadScreen extends StatefulWidget {
  const ArtistUploadScreen({super.key});

  @override
  State<ArtistUploadScreen> createState() => _ArtistUploadScreenState();
}

class _ArtistUploadScreenState extends State<ArtistUploadScreen> {
  static const _uuid = Uuid();
  static const List<String> _genreOptions = [
    'Kürtçe',
    'Türkü',
    'Arabesk',
    'Pop',
    'Rap',
    'Enstrümantal',
    'Dini',
    'Diğer',
  ];

  final _titleController = TextEditingController();
  final _artistController = TextEditingController();

  PlatformFile? _file;
  Uint8List? _fileBytes;
  String? _genre;
  bool _rightsConfirmed = false;
  bool _submitting = false;
  String? _error;

  List<MusicSubmission> _submissions = const [];
  bool _loadingSubmissions = true;

  MusicSettings get _settings => MusicSettingsService.cached;

  @override
  void initState() {
    super.initState();
    _loadSubmissions();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _artistController.dispose();
    super.dispose();
  }

  Future<void> _loadSubmissions() async {
    final rows = await MusicCatalogService.instance.mySubmissions();
    if (!mounted) return;
    setState(() {
      _submissions = rows;
      _loadingSubmissions = false;
    });
  }

  Future<void> _pickFile() async {
    try {
      // Tür süzgeci yok — Android'de `.m4a` dosyalarını soluklaştırdığı
      // biliniyor (bkz. MusicLibraryService.addFromDevice).
      final result = await FilePicker.pickFiles(
        type: FileType.any,
        allowMultiple: false,
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) return;

      final picked = result.files.first;
      if (!isAudioFileName(picked.name) &&
          !isAudioFileName(picked.path ?? '')) {
        setState(() => _error = 'Bu bir ses dosyası değil.');
        return;
      }

      // Mobilde dosyayı yoldan okuyoruz; web'de yalnızca baytlar var.
      final bytes = picked.bytes ?? await _readFromPath(picked.path);
      if (bytes == null) {
        setState(() => _error = 'Dosya okunamadı.');
        return;
      }

      final maxBytes = _settings.maxUploadMb * 1024 * 1024;
      if (bytes.lengthInBytes > maxBytes) {
        final mb = (bytes.lengthInBytes / (1024 * 1024)).toStringAsFixed(1);
        setState(() {
          _error =
              'Dosya $mb MB — en fazla ${_settings.maxUploadMb} MB olabilir.';
        });
        return;
      }

      setState(() {
        _file = picked;
        _fileBytes = bytes;
        _error = null;
        if (_titleController.text.trim().isEmpty) {
          _titleController.text = p.basenameWithoutExtension(picked.name);
        }
      });
    } catch (e) {
      debugPrint('⚠️ Dosya seçilemedi: $e');
      if (mounted) setState(() => _error = 'Dosya seçilemedi.');
    }
  }

  Future<Uint8List?> _readFromPath(String? path) async {
    if (kIsWeb || path == null || path.isEmpty) return null;
    try {
      return await File(path).readAsBytes();
    } catch (_) {
      return null;
    }
  }

  Future<void> _submit() async {
    if (_submitting) return;

    final bytes = _fileBytes;
    final file = _file;
    if (bytes == null || file == null) {
      setState(() => _error = 'Önce bir ses dosyası seç.');
      return;
    }
    if (_titleController.text.trim().isEmpty) {
      setState(() => _error = 'Şarkı adı gerekli.');
      return;
    }
    if (_artistController.text.trim().isEmpty) {
      setState(() => _error = 'Sanatçı adı gerekli.');
      return;
    }
    if (!_rightsConfirmed) {
      setState(() => _error = 'Hak beyanını onaylaman gerekiyor.');
      return;
    }

    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      setState(() => _error = 'Bu işlem için giriş yapmalısın.');
      return;
    }

    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      var ext = p.extension(file.name).toLowerCase();
      if (ext.isEmpty) ext = p.extension(file.path ?? '').toLowerCase();
      if (ext.isEmpty) ext = '.mp3';

      final path = '$userId/${_uuid.v4()}$ext';

      await Supabase.instance.client.storage
          .from('artist-music')
          .uploadBinary(
            path,
            bytes,
            fileOptions: FileOptions(
              upsert: false,
              contentType: MusicAttachService.contentTypeFor(ext),
            ),
          );

      final url = Supabase.instance.client.storage
          .from('artist-music')
          .getPublicUrl(path);

      await MusicCatalogService.instance.submitTrack(
        title: _titleController.text,
        artist: _artistController.text,
        genre: _genre,
        storagePath: path,
        publicUrl: url,
        durationMs: Mp3Clipper.looksLikeMp3(file.name)
            ? Mp3Clipper.durationMs(bytes)
            : null,
        sizeBytes: bytes.lengthInBytes,
        rightsConfirmed: true,
      );

      if (!mounted) return;
      setState(() {
        _file = null;
        _fileBytes = null;
        _rightsConfirmed = false;
        _submitting = false;
        _titleController.clear();
        _artistController.clear();
        _genre = null;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Başvurun alındı. Onaylanınca katalogda görünecek.'),
        ),
      );
      await _loadSubmissions();
    } on MusicCatalogException catch (e) {
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = e.message;
      });
    } catch (e) {
      debugPrint('⚠️ Şarkı yüklenemedi: $e');
      if (!mounted) return;
      setState(() {
        _submitting = false;
        _error = 'Şarkı yüklenemedi. Bağlantını kontrol et.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!_settings.artistUpload) {
      return Scaffold(
        appBar: AppBar(title: const Text('Şarkını yükle')),
        body: const MusicEmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Başvurular kapalı',
          message:
              'Şarkı yükleme şu anda kapalı. Daha sonra tekrar deneyebilirsin.',
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Şarkını yükle')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
        children: [
          _filePicker(theme),
          const SizedBox(height: 16),
          TextField(
            controller: _titleController,
            decoration: InputDecoration(
              labelText: 'Şarkı adı',
              border: OutlineInputBorder(borderRadius: MusicUI.radius),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _artistController,
            decoration: InputDecoration(
              labelText: 'Sanatçı',
              border: OutlineInputBorder(borderRadius: MusicUI.radius),
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _genre,
            decoration: InputDecoration(
              labelText: 'Tür',
              border: OutlineInputBorder(borderRadius: MusicUI.radius),
            ),
            items: [
              for (final g in _genreOptions)
                DropdownMenuItem(value: g, child: Text(g)),
            ],
            onChanged: (v) => setState(() => _genre = v),
          ),
          const SizedBox(height: 16),
          _rightsBox(theme),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton(
            onPressed: _submitting ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: MusicUI.accentDeep,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            child: _submitting
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('Onaya gönder'),
          ),
          const SizedBox(height: 28),
          Text(
            'Başvurularım',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          if (_loadingSubmissions)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_submissions.isEmpty)
            Text(
              'Henüz başvurun yok.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
              ),
            )
          else
            for (final s in _submissions) _submissionRow(theme, s),
        ],
      ),
    );
  }

  Widget _filePicker(ThemeData theme) {
    final file = _file;
    final bytes = _fileBytes;

    return InkWell(
      onTap: _submitting ? null : _pickFile,
      borderRadius: MusicUI.radius,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          borderRadius: MusicUI.radius,
          border: Border.all(color: theme.dividerColor),
        ),
        child: Row(
          children: [
            const Icon(Icons.audio_file_outlined, color: MusicUI.accentDeep),
            const SizedBox(width: 12),
            Expanded(
              child: file == null
                  ? Text(
                      'Ses dosyası seç (en fazla ${_settings.maxUploadMb} MB)',
                      style: theme.textTheme.bodyMedium,
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          file.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          _fileMeta(bytes, file.name),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.textTheme.bodySmall?.color?.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                      ],
                    ),
            ),
            if (file != null)
              IconButton(
                onPressed: _submitting
                    ? null
                    : () => setState(() {
                        _file = null;
                        _fileBytes = null;
                      }),
                icon: const Icon(Icons.close_rounded, size: 18),
                tooltip: 'Dosyayı kaldır',
              ),
          ],
        ),
      ),
    );
  }

  String _fileMeta(Uint8List? bytes, String name) {
    if (bytes == null) return '';
    final mb = (bytes.lengthInBytes / (1024 * 1024)).toStringAsFixed(1);
    final duration = Mp3Clipper.looksLikeMp3(name)
        ? Mp3Clipper.durationMs(bytes)
        : null;
    if (duration == null) return '$mb MB';
    return '$mb MB · ${formatDuration(duration)}';
  }

  Widget _rightsBox(ThemeData theme) {
    return InkWell(
      onTap: () => setState(() => _rightsConfirmed = !_rightsConfirmed),
      borderRadius: MusicUI.radius,
      child: Container(
        padding: const EdgeInsets.fromLTRB(4, 6, 12, 6),
        decoration: BoxDecoration(
          color: MusicUI.tint,
          borderRadius: MusicUI.radius,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(
              value: _rightsConfirmed,
              activeColor: MusicUI.accentDeep,
              onChanged: (v) => setState(() => _rightsConfirmed = v ?? false),
            ),
            const Expanded(
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 10),
                child: Text(
                  'Bu eser bana ait ya da yayınlama hakkına sahibim. '
                  'Aksi durumda şarkı kaldırılabilir ve hesabım kapatılabilir.',
                  style: TextStyle(
                    fontSize: 12,
                    height: 1.45,
                    color: MusicUI.onTint,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _submissionRow(ThemeData theme, MusicSubmission s) {
    final (bg, fg) = switch (s.status) {
      SubmissionStatus.approved => (
        const Color(0xFFEAF3DE),
        const Color(0xFF173404),
      ),
      SubmissionStatus.rejected => (
        const Color(0xFFFCEBEB),
        const Color(0xFF501313),
      ),
      SubmissionStatus.pending => (
        const Color(0xFFFAEEDA),
        const Color(0xFF412402),
      ),
    };

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  s.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 2,
                ),
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  s.statusLabel,
                  style: TextStyle(fontSize: 11, color: fg),
                ),
              ),
            ],
          ),
          if (s.status == SubmissionStatus.rejected &&
              (s.rejectReason ?? '').isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                'Sebep: ${s.rejectReason}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.textTheme.bodySmall?.color?.withValues(
                    alpha: 0.7,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
