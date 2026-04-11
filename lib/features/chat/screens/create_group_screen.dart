// ignore_for_file: deprecated_member_use

import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/group_chat_service.dart';
import '../../../core/utils/app_logger.dart';

class CreateGroupScreen extends StatefulWidget {
  const CreateGroupScreen({super.key});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final GroupChatService _groupChatService = GroupChatService();
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  bool _isPrivate = false;
  bool _isDiscoverable = true;
  bool _isCreating = false;
  Uint8List? _groupImageBytes;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    final name = _nameController.text.trim();
    if (name.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Grup adı en az 3 karakter olmalı'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      // Önce grubu oluştur
      String? avatarUrl;
      
      final group = await _groupChatService.createGroup(
        name: name,
        description: _descriptionController.text.trim().isEmpty
            ? null
            : _descriptionController.text.trim(),
        isPrivate: _isPrivate,
        isDiscoverable: _isDiscoverable,
        avatarUrl: avatarUrl,
      );

      // Grup oluşturulduysa ve resim seçilmişse yükle
      if (group != null && _groupImageBytes != null) {
        try {
          final imageUrl = await _groupChatService.uploadGroupImage(
            group.id,
            _groupImageBytes!,
          );
          if (imageUrl != null) {
            await _groupChatService.updateGroupAvatar(group.id, imageUrl);
          }
        } catch (e) {
          AppLogger.error('Error uploading group image: $e');
        }
      }

      if (mounted) {
        if (group != null) {
          Navigator.pop(context, group);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('"${group.name}" grubu oluşturuldu'),
              backgroundColor: Colors.green,
            ),
          );
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Grup oluşturulamadı. Lütfen tekrar deneyin.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    } catch (e) {
      AppLogger.error('Create group error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Hata: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  Future<void> _pickGroupImage() async {
    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );

      if (pickedFile == null) return;

      final imageBytes = await pickedFile.readAsBytes();
      setState(() {
        _groupImageBytes = imageBytes;
      });
    } catch (e) {
      AppLogger.error('Error picking group image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fotoğraf seçilemedi'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grup Oluştur'),
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 2,
        actions: [
          TextButton(
            onPressed: _isCreating ? null : _createGroup,
            child: _isCreating
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text(
                    'Oluştur',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Grup ikonu placeholder
            Center(
              child: GestureDetector(
                onTap: _pickGroupImage,
                child: Stack(
                  children: [
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        color: isDarkMode ? Colors.grey[800] : Colors.grey[200],
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: theme.primaryColor.withOpacity(0.3),
                          width: 2,
                        ),
                        image: _groupImageBytes != null
                            ? DecorationImage(
                                image: MemoryImage(_groupImageBytes!),
                                fit: BoxFit.cover,
                              )
                            : null,
                      ),
                      child: _groupImageBytes == null
                          ? Icon(
                              Icons.camera_alt,
                              size: 40,
                              color: theme.primaryColor,
                            )
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 30,
                        height: 30,
                        decoration: BoxDecoration(
                          color: theme.primaryColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: Icon(
                          _groupImageBytes != null ? Icons.edit : Icons.add_a_photo,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                _groupImageBytes != null ? 'Resmi Değiştir' : 'Grup Resmi Ekle',
                style: TextStyle(
                  color: theme.primaryColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Grup adı
            Text(
              'Grup Adı *',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _nameController,
              maxLength: 100,
              decoration: InputDecoration(
                hintText: 'Grup adını girin...',
                prefixIcon: const Icon(Icons.group),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: theme.primaryColor, width: 2),
                ),
                counterText: '${_nameController.text.length}/100',
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 20),

            // Grup açıklaması
            Text(
              'Açıklama',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              maxLength: 500,
              decoration: InputDecoration(
                hintText: 'Grup hakkında kısa bir açıklama yazın...',
                prefixIcon: const Padding(
                  padding: EdgeInsets.only(bottom: 48),
                  child: Icon(Icons.description),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey[300]!),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: theme.primaryColor, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Gizlilik ayarı
            Container(
              decoration: BoxDecoration(
                color: isDarkMode ? Colors.grey[850] : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey[300]!),
                boxShadow: [
                  BoxShadow(
                    offset: const Offset(0, 2),
                    blurRadius: 4,
                    color: Colors.black.withOpacity(0.05),
                  ),
                ],
              ),
              child: Column(
                children: [
                  SwitchListTile(
                    secondary: Icon(
                      _isPrivate ? Icons.lock : Icons.public,
                      color: _isPrivate ? Colors.orange : Colors.green,
                    ),
                    title: const Text(
                      'Gizli Grup',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _isPrivate
                          ? 'Sadece davet veya onay ile katılınabilir'
                          : 'Herkes arayıp katılabilir',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    value: _isPrivate,
                    activeColor: Colors.orange,
                    onChanged: (value) {
                      setState(() => _isPrivate = value);
                    },
                  ),
                  const Divider(height: 1),
                  SwitchListTile(
                    secondary: Icon(
                      _isDiscoverable ? Icons.visibility : Icons.visibility_off,
                      color: _isDiscoverable ? Colors.green : Colors.grey,
                    ),
                    title: const Text(
                      'Herkese Görünür',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      _isDiscoverable
                          ? 'Tüm kullanıcılar bu grubu görebilir'
                          : 'Sadece üyeler bu grubu görebilir',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey[600],
                      ),
                    ),
                    value: _isDiscoverable,
                    activeColor: Colors.green,
                    onChanged: (value) {
                      setState(() => _isDiscoverable = value);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Bilgi kartı
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.primaryColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: theme.primaryColor, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Bilgi',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: theme.primaryColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _isPrivate
                        ? 'Gizli gruplar arama sonuçlarında görünmez. Kullanıcılar katılmak için istek gönderir ve grup admini onaylamalıdır.'
                        : 'Açık gruplar herkes tarafından bulunup katılabilir. Gruba katılan herkes mesaj yazabilir.',
                    style: TextStyle(
                      fontSize: 13,
                      color: isDarkMode ? Colors.grey[300] : Colors.grey[700],
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
}
