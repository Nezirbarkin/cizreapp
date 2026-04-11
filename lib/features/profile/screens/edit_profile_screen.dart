import 'dart:typed_data';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:image_cropper/image_cropper.dart';
import '../services/profile_service.dart';
import '../../../core/utils/image_compression_helper.dart';

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

  Future<void> _pickAndCropAvatar() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1200,
        maxHeight: 1200,
        imageQuality: 100,
      );

      if (pickedFile == null) return;
      if (!mounted) return;

      // Kırpma ekranını aç
      final primaryColor = Theme.of(context).colorScheme.primary;
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
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

      // Kırpılan dosyadan bytes oku (hem web hem mobile)
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
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 100,
      );

      if (pickedFile == null) return;
      if (!mounted) return;

      // Kırpma ekranını aç
      final primaryColor = Theme.of(context).colorScheme.primary;
      final croppedFile = await ImageCropper().cropImage(
        sourcePath: pickedFile.path,
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
          WebUiSettings(
            context: context,
            presentStyle: WebPresentStyle.dialog,
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
                  child: Text('Hata: ${e.toString()}'),
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
                    ? Image.network(
                        _coverXFile!.path,
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
                        ? Image.network(
                            _currentCoverUrl!,
                            width: double.infinity,
                            height: 180,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) {
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
                      ? Image.network(
                          _avatarXFile!.path,
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
                          ? Image.network(
                              _currentAvatarUrl!,
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
