// ignore_for_file: use_build_context_synchronously

import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import '../../../core/utils/app_error_handler.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/profile_service.dart';
import '../../../core/utils/image_compression_helper.dart';
import '../../../core/services/permission_service.dart';

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _profileService = ProfileService();
  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _bioController = TextEditingController();
  final _websiteController = TextEditingController();
  String? _selectedGender;

  XFile? _avatarXFile;  // XFile her platformda çalışır
  XFile? _coverXFile;   // XFile her platformda çalışır
  Uint8List? _avatarBytes;  // Web ve crop sonrası preview
  Uint8List? _coverBytes;   // Web ve crop sonrası preview
  String? _currentAvatarUrl;
  String? _currentCoverUrl;
  
  bool _isLoading = true;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() => _isLoading = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final response = await Supabase.instance.client
          .from('profiles')
          .select()
          .eq('id', userId)
          .single();

      setState(() {
        _fullNameController.text = response['full_name'] ?? '';
        _bioController.text = response['bio'] ?? '';
        _websiteController.text = response['website'] ?? '';
        _selectedGender = response['gender'];
        _currentAvatarUrl = response['avatar_url'];
        _currentCoverUrl = response['cover_url'];
        _isLoading = false;
      });
    } catch (e) {
      debugPrint('Profil yüklenirken hata: $e');
      setState(() => _isLoading = false);
    }
  }

  /// İzin reddedildiğinde gösterilecek dialog
  void _showPermissionDeniedDialog(PermissionResult result) {
    if (!mounted) return;
    
    // İzin açıklamasını al
    String title;
    String description;
    IconData icon;
    
    if (result.permission.toLowerCase().contains('kamera') || result.permission.toLowerCase().contains('camera')) {
      title = 'Kamera İzni Gerekli';
      description = 'CizreApp\'in kamera erişimine ihtiyacı var; böylece fotoğraf çekip profil fotoğrafınızı güncelleyebilir, gönderi ve hikaye paylaşabilir, satışa sunmak istediğiniz ürünlerin fotoğraflarını çekebilirsiniz.';
      icon = Icons.camera_alt;
    } else {
      title = 'Fotoğraf Galerisi İzni Gerekli';
      description = 'CizreApp\'in fotoğraf galerinize erişmesi gerekiyor; böylece galerinizden fotoğraf seçip gönderi veya hikaye paylaşabilir, ürün fotoğraflarını mağazanıza yükleyebilir ve profil fotoğrafınızı değiştirebilirsiniz.';
      icon = Icons.photo_library;
    }
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(title)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              description,
              style: const TextStyle(fontSize: 15, height: 1.4),
            ),
            const SizedBox(height: 16),
            if (result.isPermanentlyDenied) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, color: Colors.orange.shade700, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bu izin daha önce reddedildi. Lütfen uygulama ayarlarından izin verin.',
                        style: TextStyle(color: Colors.orange.shade900, fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
        actions: [
          if (!result.isPermanentlyDenied)
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('İptal'),
            ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              if (result.isPermanentlyDenied) {
                // Ayarları aç
                PermissionService().openPermissionSettings();
              }
            },
            child: Text(result.isPermanentlyDenied ? 'Ayarları Aç' : 'İzin Ver'),
          ),
        ],
      ),
    );
  }

  /// HEIC/HEIF dosyalarını JPEG formatına dönüştürür.
  /// Android'in BitmapFactory'si HEIC formatını desteklemediği için
  /// image_cropper bu dosyaları açarken hata veriyor.
  /// Bu metod HEIC dosyalarını önce JPEG'e çevirir, diğer formatları olduğu gibi döndürür.
  Future<String?> _convertHeicToJpegIfNeeded(String filePath) async {
    if (kIsWeb) return filePath; // Web'de dönüşüm gerekmez

    final extension = path.extension(filePath).toLowerCase();
    // HEIC/HEIF dosyaları mı kontrol et
    if (extension != '.heic' && extension != '.heif') {
      return filePath; // HEIC değilse, dönüşüm gerekmez
    }

    try {
      debugPrint('🔄 HEIC dosya tespit edildi, JPEG\'e dönüştürülüyor: $filePath');

      final tempDir = await getTemporaryDirectory();
      final targetPath = path.join(
        tempDir.path,
        'heic_converted_${DateTime.now().millisecondsSinceEpoch}.jpg',
      );

      final compressedFile = await FlutterImageCompress.compressAndGetFile(
        filePath,
        targetPath,
        quality: 95,
        format: CompressFormat.jpeg,
        keepExif: true,
      );

      if (compressedFile == null) {
        debugPrint('❌ HEIC → JPEG dönüşümü başarısız oldu');
        return null;
      }

      debugPrint('✅ HEIC → JPEG dönüşümü başarılı: ${compressedFile.path}');
      return compressedFile.path;
    } catch (e) {
      debugPrint('❌ HEIC dönüşüm hatası: $e');
      return null;
    }
  }

  Future<void> _pickAndCropAvatar() async {
    try {
      // Web'de kırpma yok, doğrudan kullan
      if (kIsWeb) {
        final picker = ImagePicker();
        final pickedFile = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1200,
          maxHeight: 1200,
          imageQuality: 100,
        );

        if (pickedFile == null) return;
        if (!mounted) return;

        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _avatarXFile = pickedFile;
          _avatarBytes = bytes;
        });
        return;
      }

      // Mobil için izin kontrolü
      final permissionService = PermissionService();
      final isGranted = await permissionService.isPhotosGranted();
      if (!isGranted) {
        if (!mounted) return;
        final result = await permissionService.checkAndRequestAllPermissions();
        final photosResult = result['photos'];
        if (photosResult != null && !photosResult.isGranted) {
          if (!mounted) return;
          _showPermissionDeniedDialog(photosResult);
          return;
        }
      }

      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 100,
      );

      if (pickedFile == null) return;
      if (!mounted) return;

      // HEIC/HEIF dosyalarını JPEG'e dönüştür (Android uyumluluğu için)
      String sourcePath = pickedFile.path;
      final convertedPath = await _convertHeicToJpegIfNeeded(pickedFile.path);
      if (convertedPath != null) {
        sourcePath = convertedPath;
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('HEIC formatındaki fotoğraf işlenemedi. Lütfen JPEG veya PNG formatında bir fotoğraf seçin.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // Kırpma ekranını aç
      final primaryColor = Theme.of(context).colorScheme.primary;
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: sourcePath,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Profil Fotoğrafı Kırp',
            toolbarColor: primaryColor,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.square,
            lockAspectRatio: true,
          ),
          IOSUiSettings(
            title: 'Profil Fotoğrafı Kırp',
            aspectRatioLockEnabled: true,
          ),
          WebUiSettings(
            context: context,
            presentStyle: WebPresentStyle.dialog,
          ),
        ],
      );

      if (croppedFile == null) return;
      if (!mounted) return;

      // Kırpılan dosyadan bytes oku
      final bytes = await croppedFile.readAsBytes();
      final xFile = XFile(croppedFile.path);

      if (mounted) {
        setState(() {
          _avatarXFile = xFile;
          _avatarBytes = bytes;
        });
      }
    } catch (e) {
      debugPrint('Avatar kırpma hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fotoğraf işlenirken hata oluştu: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _pickAndCropCover() async {
    try {
      // Web'de kırpma yok, doğrudan kullan
      if (kIsWeb) {
        final picker = ImagePicker();
        final pickedFile = await picker.pickImage(
          source: ImageSource.gallery,
          maxWidth: 1920,
          maxHeight: 1080,
          imageQuality: 100,
        );

        if (pickedFile == null) return;
        if (!mounted) return;

        final bytes = await pickedFile.readAsBytes();
        setState(() {
          _coverXFile = pickedFile;
          _coverBytes = bytes;
        });
        return;
      }

      // Mobil için izin kontrolü
      final permissionService = PermissionService();
      final isGranted = await permissionService.isPhotosGranted();
      if (!isGranted) {
        if (!mounted) return;
        final result = await permissionService.checkAndRequestAllPermissions();
        final photosResult = result['photos'];
        if (photosResult != null && !photosResult.isGranted) {
          if (!mounted) return;
          _showPermissionDeniedDialog(photosResult);
          return;
        }
      }

      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 100,
      );

      if (pickedFile == null) return;
      if (!mounted) return;

      // HEIC/HEIF dosyalarını JPEG'e dönüştür (Android uyumluluğu için)
      String sourcePath = pickedFile.path;
      final convertedPath = await _convertHeicToJpegIfNeeded(pickedFile.path);
      if (convertedPath != null) {
        sourcePath = convertedPath;
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('HEIC formatındaki fotoğraf işlenemedi. Lütfen JPEG veya PNG formatında bir fotoğraf seçin.'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 4),
            ),
          );
        }
        return;
      }

      // Kırpma ekranını aç
      final primaryColor = Theme.of(context).colorScheme.primary;
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: sourcePath,
        uiSettings: [
          AndroidUiSettings(
            toolbarTitle: 'Kapak Fotoğrafı Kırp',
            toolbarColor: primaryColor,
            toolbarWidgetColor: Colors.white,
            initAspectRatio: CropAspectRatioPreset.ratio16x9,
            lockAspectRatio: true,
          ),
          IOSUiSettings(
            title: 'Kapak Fotoğrafı Kırp',
            aspectRatioLockEnabled: true,
          ),
        ],
      );

      if (croppedFile == null) return;
      if (!mounted) return;

      // Kırpılan dosyadan bytes oku (hem web hem mobile)
      final bytes = await croppedFile.readAsBytes();
      final xFile = XFile(croppedFile.path);

      if (mounted) {
        setState(() {
          _coverXFile = xFile;
          _coverBytes = bytes;
        });
      }
    } catch (e) {
      debugPrint('Kapak kırpma hatası: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Fotoğraf işlenirken hata oluştu: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) {
        debugPrint('❌ User ID boş');
        return;
      }

      String? newAvatarUrl;
      String? newCoverUrl;

      // Avatar yükle (XFile ile - Web ve Mobile uyumlu)
      if (_avatarXFile != null) {
        debugPrint('📤 Avatar yükleniyor (XFile)...');
        newAvatarUrl = await _profileService.uploadProfilePhotoXFile(_avatarXFile!);
        debugPrint('📤 Upload result: $newAvatarUrl');
        if (newAvatarUrl != null) {
          debugPrint('✅ Avatar URL: $newAvatarUrl');
          setState(() => _currentAvatarUrl = newAvatarUrl);
        } else {
          debugPrint('❌ Avatar yüklenemedi');
        }
      }

      // Kapak fotoğrafı yükle (XFile ile - Web ve Mobile uyumlu)
      if (_coverXFile != null) {
        debugPrint('📤 Kapak yükleniyor (XFile)...');
        newCoverUrl = await _profileService.uploadCoverPhotoXFile(_coverXFile!);
        debugPrint('📤 Upload result: $newCoverUrl');
        if (newCoverUrl != null) {
          debugPrint('✅ Kapak URL: $newCoverUrl');
          setState(() => _currentCoverUrl = newCoverUrl);
        } else {
          debugPrint('❌ Kapak yüklenemedi');
        }
      }

      // Profil bilgilerini güncelle
      debugPrint('📝 Profil bilgileri güncelleniyor...');
      final success = await _profileService.updateProfile(
        fullName: _fullNameController.text.trim(),
        bio: _bioController.text.trim(),
        website: _websiteController.text.trim(),
        gender: _selectedGender,
      );

      if (!success) {
        throw Exception('Profil güncellenemedi');
      }

      debugPrint('✅ Profil başarıyla güncellendi');

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'Başarılı!',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'Profil güncellendi${newAvatarUrl != null ? ' (Avatar yüklendi)' : ''}${newCoverUrl != null ? ' (Kapak yüklendi)' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
        
        // Profil ekranına geri dön ve yenile
        Navigator.pop(context, true);
      }
    } catch (e) {
      debugPrint('❌ Profil güncellenirken hata: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(e.userMessage),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _bioController.dispose();
    _websiteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;

    if (_isLoading) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('Profili Düzenle'),
          backgroundColor: primaryColor,
        ),
        body: const Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Profili Düzenle'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            TextButton.icon(
              onPressed: _saveProfile,
              icon: const Icon(Icons.check, color: Colors.white),
              label: const Text(
                'Kaydet',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).padding.bottom + 80,
          ),
          children: [
            // Cover Photo Section
            _buildCoverSection(primaryColor),
            
            const SizedBox(height: 16),
            
            // Avatar Section
            _buildAvatarSection(primaryColor),
            
            const SizedBox(height: 24),
            
            // Full Name
            _buildTextField(
              controller: _fullNameController,
              label: 'Ad Soyad',
              icon: Icons.person,
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Ad soyad gerekli';
                }
                return null;
              },
            ),
            
            const SizedBox(height: 16),

            // Cinsiyet
            _buildGenderSelector(primaryColor),
            
            const SizedBox(height: 16),
            
            // Bio
            _buildTextField(
              controller: _bioController,
              label: 'Hakkında',
              icon: Icons.info_outline,
              maxLines: 3,
              maxLength: 150,
              hintText: 'Kendinden bahset...',
            ),
            
            const SizedBox(height: 16),
            
            // Website
            _buildTextField(
              controller: _websiteController,
              label: 'Web Sitesi',
              icon: Icons.language,
              keyboardType: TextInputType.url,
              hintText: 'https://example.com',
            ),
            
            const SizedBox(height: 32),
            
            // Save Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text(
                        'Değişiklikleri Kaydet',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCoverSection(Color primaryColor) {
    return Stack(
      children: [
        // Cover Image
        Container(
          height: 180,
          decoration: BoxDecoration(
            gradient: _coverBytes == null && 
                    (_coverXFile == null || kIsWeb) && 
                    (_currentCoverUrl == null || _currentCoverUrl!.isEmpty)
                ? LinearGradient(
                    colors: [
                      primaryColor.withValues(alpha: 0.3),
                      primaryColor.withValues(alpha: 0.1),
                    ],
                  )
                : null,
            color: _coverBytes != null || 
                    (!kIsWeb && _coverXFile != null) || 
                    (_currentCoverUrl != null && _currentCoverUrl!.isNotEmpty)
                ? null
                : null,
            borderRadius: BorderRadius.circular(16),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: _coverBytes != null
                ? Image.memory(
                    _coverBytes!,
                    width: double.infinity,
                    height: 180,
                    fit: BoxFit.cover,
                  )
                : _coverXFile != null && !kIsWeb
                    ? Image.file(
                        File(_coverXFile!.path),
                        width: double.infinity,
                        height: 180,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Container(
                            width: double.infinity,
                            height: 180,
                            color: Colors.grey.shade300,
                            child: const Icon(Icons.broken_image),
                          );
                        },
                      )
                    : _currentCoverUrl != null && _currentCoverUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: _currentCoverUrl!,
                            width: double.infinity,
                            height: 180,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) {
                              return Center(
                                child: Icon(
                                  Icons.image_not_supported,
                                  size: 48,
                                  color: primaryColor.withValues(alpha: 0.5),
                                ),
                              );
                            },
                          )
                        : Center(
                            child: Icon(
                              Icons.photo_size_select_actual,
                              size: 48,
                              color: primaryColor.withValues(alpha: 0.5),
                            ),
                          ),
          ),
        ),
        
        // Edit Button
        Positioned(
          right: 12,
          bottom: 12,
          child: Material(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            child: InkWell(
              onTap: _pickAndCropCover,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.camera_alt,
                      size: 18,
                      color: primaryColor,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      _coverBytes != null ? 'Kapak Değiştir' : 'Kapak Fotoğrafı',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),

        // Kırpma önizleme göstergesi
        if (_coverBytes != null)
          Positioned(
            left: 12,
            top: 12,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: primaryColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.crop, size: 14, color: Colors.white),
                  SizedBox(width: 4),
                  Text(
                    'Kırpıldı',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildAvatarSection(Color primaryColor) {
    return Center(
      child: Stack(
        children: [
          // Avatar
          Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: Colors.white,
                width: 4,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.2),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: ClipOval(
              child: _avatarBytes != null
                  ? Image.memory(
                      _avatarBytes!,
                      width: 120,
                      height: 120,
                      fit: BoxFit.cover,
                    )
                  : _avatarXFile != null && !kIsWeb
                      ? Image.file(
                          File(_avatarXFile!.path),
                          width: 120,
                          height: 120,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Container(
                              width: 120,
                              height: 120,
                              color: primaryColor,
                              child: const Icon(
                                Icons.person,
                                size: 48,
                                color: Colors.white,
                              ),
                            );
                          },
                        )
                      : _currentAvatarUrl != null && _currentAvatarUrl!.isNotEmpty
                          ? CachedNetworkImage(
                              imageUrl: _currentAvatarUrl!,
                              width: 120,
                              height: 120,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) {
                                return Container(
                                  width: 120,
                                  height: 120,
                                  color: primaryColor,
                                  child: const Icon(
                                    Icons.person,
                                    size: 48,
                                    color: Colors.white,
                                  ),
                                );
                              },
                            )
                          : Container(
                              width: 120,
                              height: 120,
                              color: primaryColor,
                              child: const Icon(
                                Icons.person,
                                size: 48,
                                color: Colors.white,
                              ),
                            ),
            ),
          ),
          
          // Edit Button
          Positioned(
            right: 0,
            bottom: 0,
            child: Material(
              color: primaryColor,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                onTap: _pickAndCropAvatar,
                borderRadius: BorderRadius.circular(20),
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(
                    Icons.camera_alt,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),

          // Kırpma göstergesi
          if (_avatarBytes != null)
            Positioned(
              left: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
                child: const Icon(
                  Icons.crop,
                  size: 12,
                  color: Colors.white,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildGenderSelector(Color primaryColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Cinsiyet',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _buildGenderOption(
                label: 'Erkek',
                icon: Icons.male,
                value: 'male',
                primaryColor: primaryColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildGenderOption(
                label: 'Kadın',
                icon: Icons.female,
                value: 'female',
                primaryColor: primaryColor,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildGenderOption(
                label: 'Diğer',
                icon: Icons.person_outline,
                value: 'other',
                primaryColor: primaryColor,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildGenderOption({
    required String label,
    required IconData icon,
    required String value,
    required Color primaryColor,
  }) {
    final isSelected = _selectedGender == value;
    // Web'de icon tree-shaking sorununu önlemek için emoji kullan
    final genderEmoji = value == 'male'
        ? '♂'
        : value == 'female'
            ? '♀'
            : '○';
    return InkWell(
      onTap: () => setState(() => _selectedGender = value),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? primaryColor.withValues(alpha: 0.1) : Colors.grey.shade50,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? primaryColor : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              genderEmoji,
              style: TextStyle(
                fontSize: 28,
                color: isSelected ? primaryColor : Colors.grey.shade600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? primaryColor : Colors.grey.shade600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
    int maxLines = 1,
    int? maxLength,
    TextInputType? keyboardType,
    String? hintText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: Colors.grey.shade700,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          controller: controller,
          validator: validator,
          maxLines: maxLines,
          maxLength: maxLength,
          keyboardType: keyboardType,
          decoration: InputDecoration(
            hintText: hintText,
            prefixIcon: Icon(icon, color: Theme.of(context).colorScheme.primary),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(
                color: Theme.of(context).colorScheme.primary,
                width: 2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Colors.red),
            ),
            filled: true,
            fillColor: Colors.grey.shade50,
          ),
        ),
      ],
    );
  }
}
