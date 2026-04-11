// ignore_for_file: deprecated_member_use

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/group_model.dart';
import '../../../core/models/group_message_model.dart';
import '../../../core/services/privacy_service.dart';
import '../../../core/utils/app_logger.dart';
import '../../../core/widgets/group_avatar_viewer.dart';
import '../services/group_chat_service.dart';
import '../../profile/screens/user_profile_screen.dart';

class GroupSettingsScreen extends StatefulWidget {
  final ChatGroup group;

  const GroupSettingsScreen({super.key, required this.group});

  @override
  State<GroupSettingsScreen> createState() => _GroupSettingsScreenState();
}

class _GroupSettingsScreenState extends State<GroupSettingsScreen> {
  final GroupChatService _groupChatService = GroupChatService();
  late ChatGroup _group;
  List<GroupMember> _members = [];
  List<GroupJoinRequest> _joinRequests = [];
  bool _isLoading = true;
  bool _isLoadingRequests = false;
  bool _isUploadingImage = false;
  bool _isMuted = false;
  RealtimeChannel? _membersChannel;

  String? get _currentUserId => Supabase.instance.client.auth.currentUser?.id;

  @override
  void initState() {
    super.initState();
    _group = widget.group;
    _isMuted = _group.isMuted;
    _loadMembers();
    if (_group.isAdmin || _group.isModerator) {
      _loadJoinRequests();
    }
    _subscribeToMembers();
  }

  @override
  void dispose() {
    _membersChannel?.unsubscribe();
    super.dispose();
  }

  Future<void> _loadMembers() async {
    setState(() => _isLoading = true);
    final members = await _groupChatService.getGroupMembers(_group.id);
    if (mounted) {
      setState(() {
        _members = members;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadJoinRequests() async {
    if (!_group.isAdmin && !_group.isModerator) return;

    setState(() => _isLoadingRequests = true);
    final requests = await _groupChatService.getJoinRequests(_group.id);
    if (mounted) {
      setState(() {
        _joinRequests = requests;
        _isLoadingRequests = false;
      });
    }
  }

  void _subscribeToMembers() {
    _membersChannel = _groupChatService.subscribeToGroupMembers(
      _group.id,
      (members) {
        if (mounted) {
          setState(() => _members = members);
        }
      },
    );
  }

  Future<void> _approveRequest(GroupJoinRequest request) async {
    final success = await _groupChatService.approveJoinRequest(request.id);
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${request.userName ?? 'Kullanıcı'} gruba eklendi'),
            backgroundColor: Colors.green,
          ),
        );
        _loadJoinRequests();
        _loadMembers();
        // Grup bilgisini güncelle
        final updatedGroup = await _groupChatService.getGroupDetail(_group.id);
        if (updatedGroup != null && mounted) {
          setState(() => _group = updatedGroup);
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('İstek onaylanamadı'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _rejectRequest(GroupJoinRequest request) async {
    final success = await _groupChatService.rejectJoinRequest(request.id);
    if (mounted) {
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${request.userName ?? 'Kullanıcı'} isteği reddedildi'),
            backgroundColor: Colors.orange,
          ),
        );
        _loadJoinRequests();
      }
    }
  }

  Future<void> _removeMember(GroupMember member) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Üyeyi Çıkar'),
        content: Text(
          '${member.fullName ?? 'Bu kullanıcıyı'} gruptan çıkarmak istediğinize emin misiniz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Çıkar'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _groupChatService.removeMember(_group.id, member.userId);
      if (mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('${member.fullName ?? 'Kullanıcı'} gruptan çıkarıldı'),
              backgroundColor: Colors.green,
            ),
          );
          _loadMembers();
          // Grup bilgisini güncelle
          final updatedGroup = await _groupChatService.getGroupDetail(_group.id);
          if (updatedGroup != null && mounted) {
            setState(() => _group = updatedGroup);
          }
        }
      }
    }
  }

  Future<void> _changeMemberRole(GroupMember member) async {
    final newRole = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rol Değiştir'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.admin_panel_settings, color: Colors.blue),
              title: const Text('Admin'),
              subtitle: const Text('Tüm yetkilere sahip'),
              selected: member.role == 'admin',
              onTap: () => Navigator.pop(context, 'admin'),
            ),
            ListTile(
              leading: const Icon(Icons.shield, color: Colors.orange),
              title: const Text('Moderatör'),
              subtitle: const Text('Üyeleri yönetebilir'),
              selected: member.role == 'moderator',
              onTap: () => Navigator.pop(context, 'moderator'),
            ),
            ListTile(
              leading: const Icon(Icons.person, color: Colors.grey),
              title: const Text('Üye'),
              subtitle: const Text('Mesaj gönderebilir'),
              selected: member.role == 'member',
              onTap: () => Navigator.pop(context, 'member'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
        ],
      ),
    );

    if (newRole != null && newRole != member.role) {
      final success = await _groupChatService.updateMemberRole(
        _group.id,
        member.userId,
        newRole,
      );
      if (mounted && success) {
        _loadMembers();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${member.fullName ?? 'Kullanıcı'} rolü güncellendi'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _leaveGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Gruptan Ayrıl'),
        content: const Text('Bu gruptan ayrılmak istediğinize emin misiniz?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Ayrıl'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _groupChatService.leaveGroup(_group.id);
      if (mounted) {
        if (success) {
          Navigator.pop(context, false); // Geri dön ve sohbet ekranını kapat
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Gruptan ayrılma başarısız'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }

  Future<void> _deleteGroup() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Grubu Sil'),
        content: const Text(
          'Bu grup kalıcı olarak silinecek. Tüm mesajlar ve üyelikler kaybolacak. Devam etmek istiyor musunuz?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Sil'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final success = await _groupChatService.deleteGroup(_group.id);
      if (mounted) {
        if (success) {
          Navigator.pop(context, false); // Geri dön ve sohbet ekranını kapat
        }
      }
    }
  }

  Future<void> _editGroup() async {
    final nameController = TextEditingController(text: _group.name);
    final descController = TextEditingController(text: _group.description ?? '');
    bool isPrivate = _group.isPrivate;
    bool isDiscoverable = _group.isDiscoverable;
    bool hideCreator = _group.hideCreator;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, dialogSetState) {
            return AlertDialog(
              title: const Text('Grubu Düzenle'),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: InputDecoration(
                        labelText: 'Grup Adı',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: descController,
                      maxLines: 3,
                      decoration: InputDecoration(
                        labelText: 'Açıklama',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      secondary: Icon(
                        isPrivate ? Icons.lock : Icons.public,
                        color: isPrivate ? Colors.orange : Colors.green,
                      ),
                      title: const Text('Gizli Grup'),
                      subtitle: const Text('Katılmak için istek gerekir'),
                      value: isPrivate,
                      onChanged: (v) => dialogSetState(() => isPrivate = v),
                    ),
                    SwitchListTile(
                      secondary: Icon(
                        isDiscoverable ? Icons.visibility : Icons.visibility_off,
                        color: isDiscoverable ? Colors.green : Colors.grey,
                      ),
                      title: const Text('Herkese Görünür'),
                      subtitle: const Text('Kapatırsanız sadece üyeler görebilir'),
                      value: isDiscoverable,
                      onChanged: (v) => dialogSetState(() => isDiscoverable = v),
                    ),
                    SwitchListTile(
                      secondary: Icon(
                        hideCreator ? Icons.person_off : Icons.person,
                        color: hideCreator ? Colors.grey : Colors.blue,
                      ),
                      title: const Text('Kurucuyu Gizle'),
                      subtitle: const Text('Kurucu sadece adminlere görünür olur'),
                      value: hideCreator,
                      onChanged: (v) => dialogSetState(() => hideCreator = v),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('İptal'),
                ),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context, {
                      'name': nameController.text.trim(),
                      'description': descController.text.trim(),
                      'is_private': isPrivate,
                      'is_discoverable': isDiscoverable,
                      'hide_creator': hideCreator,
                    });
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.deepPurple,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Kaydet'),
                ),
              ],
            );
          },
        );
      },
    );

    nameController.dispose();
    descController.dispose();

    if (result != null && mounted) {
      final name = result['name'] as String;
      if (name.length < 3) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Grup adı en az 3 karakter olmalı'),
            backgroundColor: Colors.orange,
          ),
        );
        return;
      }

      final success = await _groupChatService.updateGroup(
        groupId: _group.id,
        name: name,
        description: result['description'] as String,
        isPrivate: result['is_private'] as bool,
        isDiscoverable: result['is_discoverable'] as bool,
        hideCreator: result['hide_creator'] as bool,
      );

      if (success && mounted) {
        final updatedGroup = await _groupChatService.getGroupDetail(_group.id);
        if (updatedGroup != null && mounted) {
          setState(() => _group = updatedGroup);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Grup güncellendi'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grup Bilgileri'),
        backgroundColor: theme.primaryColor,
        foregroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Colors.white),
        elevation: 2,
        actions: [
          if (_group.isAdmin)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: _editGroup,
              tooltip: 'Grubu Düzenle',
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              children: [
                // Grup bilgi kartı (profil fotoğrafı ile)
                _buildGroupInfoCard(isDarkMode),

                // Bildirim & Sessize alma ayarları
                _buildNotificationSettings(isDarkMode),

                // Katılma İstekleri (admin/moderator için)
                if ((_group.isAdmin || _group.isModerator) && _group.isPrivate)
                  _buildJoinRequestsSection(isDarkMode),

                // Üyeler bölümü
                _buildMembersSection(isDarkMode),

                // Medya & Paylaşım
                _buildMediaSection(isDarkMode),

                const SizedBox(height: 16),

                // İşlem butonları
                _buildActionButtons(isDarkMode),

                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _buildGroupInfoCard(bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            offset: const Offset(0, 2),
            blurRadius: 8,
            color: Colors.black.withOpacity(0.05),
          ),
        ],
      ),
      child: Column(
        children: [
          // Avatar (tıklanabilir - admin için değiştirme/büyütme, üye için büyütme)
          GestureDetector(
            onTap: _group.isAdmin ? _pickGroupImage : _showAvatarFullscreen,
            onLongPress: _group.isAdmin && _group.avatarUrl != null ? _showAvatarFullscreen : null,
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 45,
                  backgroundColor: _group.isPrivate ? Colors.orange[100] : Colors.green[100],
                  backgroundImage: _group.avatarUrl != null ? NetworkImage(_group.avatarUrl!) : null,
                  child: _group.avatarUrl == null
                      ? Icon(
                          _group.isPrivate ? Icons.lock : Icons.groups,
                          size: 40,
                          color: _group.isPrivate ? Colors.orange[700] : Colors.green[700],
                        )
                      : null,
                ),
                // Admin ise fotoğraf değiştirme ikonu
                if (_group.isAdmin)
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: _isUploadingImage
                          ? const Padding(
                              padding: EdgeInsets.all(4),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.camera_alt,
                              size: 16,
                              color: Colors.white,
                            ),
                    ),
                  ),
              ],
            ),
          ),
          // Admin ise fotoğraf değiştirme ipucu
          if (_group.isAdmin) ...[
            const SizedBox(height: 4),
            GestureDetector(
              onTap: _isUploadingImage ? null : _pickGroupImage,
              child: Text(
                'Fotoğraf değiştir',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),

          // Grup adı
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Flexible(
                child: Text(
                  _group.name,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              if (_group.isPrivate) ...[
                const SizedBox(width: 6),
                Icon(Icons.lock, size: 18, color: Colors.orange[700]),
              ],
            ],
          ),
          const SizedBox(height: 6),

          // Açıklama
          if (_group.description != null && _group.description!.isNotEmpty) ...[
            Text(
              _group.description!,
              style: TextStyle(
                fontSize: 14,
                color: isDarkMode ? Colors.grey[400] : Colors.grey[600],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
          ],

          // Bilgi etiketleri
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              _buildInfoChip(
                Icons.people,
                '${_group.memberCount} üye',
                Colors.blue,
              ),
              _buildInfoChip(
                _group.isPrivate ? Icons.lock : Icons.public,
                _group.isPrivate ? 'Gizli' : 'Açık',
                _group.isPrivate ? Colors.orange : Colors.green,
              ),
              if (_group.userRole != null)
                _buildInfoChip(
                  _group.isAdmin ? Icons.admin_panel_settings : Icons.person,
                  _group.isAdmin
                      ? 'Admin'
                      : _group.isModerator
                          ? 'Moderatör'
                          : 'Üye',
                  _group.isAdmin
                      ? Colors.blue
                      : _group.isModerator
                          ? Colors.orange
                          : Colors.grey,
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ============================================
  // BİLDİRİM & SESSİZE ALMA
  // ============================================

  Widget _buildNotificationSettings(bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            offset: const Offset(0, 2),
            blurRadius: 4,
            color: Colors.black.withOpacity(0.05),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.notifications, color: isDarkMode ? Colors.grey[400] : Colors.grey[700]),
                const SizedBox(width: 8),
                Text(
                  'Bildirimler',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.grey[300] : Colors.grey[800],
                  ),
                ),
              ],
            ),
          ),
          SwitchListTile(
            secondary: Icon(
              _isMuted ? Icons.notifications_off : Icons.notifications_active,
              color: _isMuted ? Colors.red : Colors.green,
            ),
            title: const Text(
              'Bildirimleri Sessize Al',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              _isMuted
                  ? 'Bu gruptan bildirim gelmeyecek'
                  : 'Yeni mesajlarda bildirim al',
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            ),
            value: _isMuted,
            activeColor: Colors.red,
            onChanged: _toggleMute,
          ),
          if (_isMuted)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.orange.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.orange.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.orange[700]),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Bu grup sessize alındı. Yeni mesajlar için bildirim almayacaksınız.',
                        style: TextStyle(fontSize: 12, color: Colors.orange[700]),
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

  Future<void> _toggleMute(bool value) async {
    final success = await _groupChatService.toggleMuteGroup(_group.id, value);
    if (mounted && success) {
      setState(() {
        _isMuted = value;
        _group = _group.copyWith(isMuted: value);
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(value ? 'Grup bildirimleri sessize alındı' : 'Grup bildirimleri açıldı'),
          backgroundColor: value ? Colors.orange : Colors.green,
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  // ============================================
  // PROFİL FOTOĞRAFI
  // ============================================

  Future<void> _pickGroupImage() async {
    if (!_group.isAdmin) return;

    try {
      final picker = ImagePicker();
      final pickedFile = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 80,
      );

      if (pickedFile == null) return;

      setState(() => _isUploadingImage = true);

      final imageBytes = await pickedFile.readAsBytes();
      final imageUrl = await _groupChatService.uploadGroupImage(
        _group.id,
        imageBytes,
      );

      if (imageUrl != null && mounted) {
        // Context'i önce al
        final scaffoldMessenger = ScaffoldMessenger.of(context);
        
        // Grup avatar'ını güncelle
        final success = await _groupChatService.updateGroupAvatar(_group.id, imageUrl);
        if (success) {
          final updatedGroup = await _groupChatService.getGroupDetail(_group.id);
          if (updatedGroup != null && mounted) {
            setState(() => _group = updatedGroup);
          }
          scaffoldMessenger.showSnackBar(
            const SnackBar(
              content: Text('Grup fotoğrafı güncellendi'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      AppLogger.error('Error picking group image: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Fotoğraf yüklenemedi'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploadingImage = false);
      }
    }
  }

  void _showAvatarFullscreen() {
    if (_group.avatarUrl == null) return;
    showGroupAvatarFullscreen(
      context: context,
      imageUrl: _group.avatarUrl!,
      title: _group.name,
    );
  }

  // ============================================
  // MEDYA & PAYLAŞIM
  // ============================================

  Widget _buildMediaSection(bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            offset: const Offset(0, 2),
            blurRadius: 4,
            color: Colors.black.withOpacity(0.05),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Icon(Icons.perm_media, color: isDarkMode ? Colors.grey[400] : Colors.grey[700]),
                const SizedBox(width: 8),
                Text(
                  'Medya & Veriler',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: isDarkMode ? Colors.grey[300] : Colors.grey[800],
                  ),
                ),
              ],
            ),
          ),
          // Grup bilgisi
          ListTile(
            leading: const Icon(Icons.info_outline, color: Colors.blue),
            title: const Text('Grup Oluşturulma'),
            subtitle: Text(_formatDate(_group.createdAt)),
          ),
          // Grup ID (admin için)
          if (_group.isAdmin)
            ListTile(
              leading: const Icon(Icons.tag, color: Colors.grey),
              title: const Text('Grup ID'),
              subtitle: Text(
                '${_group.id.substring(0, 8)}...',
                style: TextStyle(fontSize: 12, fontFamily: 'monospace'),
              ),
              trailing: IconButton(
                icon: const Icon(Icons.copy, size: 18),
                onPressed: () {
                  // Clipboard'a kopyala
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Grup ID kopyalandı')),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    const turkeyOffset = Duration(hours: 3);
    final turkeyDate = date.toUtc().add(turkeyOffset);
    return '${turkeyDate.day.toString().padLeft(2, '0')}.${turkeyDate.month.toString().padLeft(2, '0')}.${turkeyDate.year} ${turkeyDate.hour.toString().padLeft(2, '0')}:${turkeyDate.minute.toString().padLeft(2, '0')}';
  }

  Widget _buildInfoChip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildJoinRequestsSection(bool isDarkMode) {
    if (_joinRequests.isEmpty && !_isLoadingRequests) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            offset: const Offset(0, 2),
            blurRadius: 4,
            color: Colors.black.withOpacity(0.05),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.person_add, color: Colors.orange),
                const SizedBox(width: 8),
                Text(
                  'Katılma İstekleri (${_joinRequests.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          if (_isLoadingRequests)
            const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            )
          else
            ..._joinRequests.map((request) => _buildJoinRequestTile(request)),
        ],
      ),
    );
  }

  Widget _buildJoinRequestTile(GroupJoinRequest request) {
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Colors.grey[200],
        backgroundImage: request.userAvatarUrl != null
            ? NetworkImage(request.userAvatarUrl!)
            : null,
        child: request.userAvatarUrl == null
            ? Text(
                (request.userName ?? '?')[0].toUpperCase(),
                style: const TextStyle(fontWeight: FontWeight.bold),
              )
            : null,
      ),
      title: Text(
        request.userName ?? 'Bilinmeyen Kullanıcı',
        style: const TextStyle(fontWeight: FontWeight.w600),
      ),
      subtitle: request.message != null
          ? Text(
              request.message!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
            )
          : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.check_circle, color: Colors.green),
            onPressed: () => _approveRequest(request),
            tooltip: 'Onayla',
          ),
          IconButton(
            icon: const Icon(Icons.cancel, color: Colors.red),
            onPressed: () => _rejectRequest(request),
            tooltip: 'Reddet',
          ),
        ],
      ),
    );
  }

  Widget _buildMembersSection(bool isDarkMode) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: isDarkMode ? Colors.grey[850] : Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            offset: const Offset(0, 2),
            blurRadius: 4,
            color: Colors.black.withOpacity(0.05),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Icon(Icons.people, color: Colors.deepPurple),
                const SizedBox(width: 8),
                Text(
                  'Üyeler (${_members.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          ..._members.map((member) => _buildMemberTile(member)),
        ],
      ),
    );
  }

  Widget _buildMemberTile(GroupMember member) {
    final isCurrentUser = member.userId == _currentUserId;
    final canManage = _group.isAdmin && !isCurrentUser;

    return ListTile(
      leading: Stack(
        children: [
          CircleAvatar(
            backgroundColor: Colors.deepPurple[100],
            backgroundImage: member.avatarUrl != null
                ? NetworkImage(member.avatarUrl!)
                : null,
            child: member.avatarUrl == null
                ? Text(
                    (member.fullName ?? '?')[0].toUpperCase(),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.deepPurple[700],
                    ),
                  )
                : null,
          ),
          if (PrivacyService.isUserTrulyActive(member.isOnline ?? false, member.lastSeen))
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              member.fullName ?? 'Bilinmeyen',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: isCurrentUser ? Colors.deepPurple : null,
              ),
            ),
          ),
          if (isCurrentUser) ...[
            const SizedBox(width: 4),
            const Text(
              '(Sen)',
              style: TextStyle(fontSize: 12, color: Colors.deepPurple),
            ),
          ],
        ],
      ),
      subtitle: Row(
        children: [
          Icon(
            member.isAdmin
                ? Icons.admin_panel_settings
                : member.isModerator
                    ? Icons.shield
                    : Icons.person,
            size: 14,
            color: member.isAdmin
                ? Colors.blue
                : member.isModerator
                    ? Colors.orange
                    : Colors.grey,
          ),
          const SizedBox(width: 4),
          Text(
            member.isAdmin
                ? 'Admin'
                : member.isModerator
                    ? 'Moderatör'
                    : 'Üye',
            style: TextStyle(
              fontSize: 12,
              color: member.isAdmin
                  ? Colors.blue
                  : member.isModerator
                      ? Colors.orange
                      : Colors.grey[600],
            ),
          ),
          if (member.username != null) ...[
            const SizedBox(width: 8),
            Text(
              '@${member.username}',
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ],
      ),
      trailing: canManage
          ? PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert),
              onSelected: (value) {
                switch (value) {
                  case 'role':
                    _changeMemberRole(member);
                    break;
                  case 'remove':
                    _removeMember(member);
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'role',
                  child: Row(
                    children: [
                      Icon(Icons.swap_horiz, size: 18),
                      SizedBox(width: 8),
                      Text('Rol Değiştir'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'remove',
                  child: Row(
                    children: [
                      Icon(Icons.remove_circle, size: 18, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Çıkar', style: TextStyle(color: Colors.red)),
                    ],
                  ),
                ),
              ],
            )
          : null,
      onTap: () {
        if (!isCurrentUser) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => UserProfileScreen(userId: member.userId),
            ),
          );
        }
      },
    );
  }

  Widget _buildActionButtons(bool isDarkMode) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          // Gruptan Ayrıl
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _leaveGroup,
              icon: const Icon(Icons.exit_to_app, color: Colors.red),
              label: const Text('Gruptan Ayrıl'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                side: const BorderSide(color: Colors.red),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),

          // Grubu Sil (sadece admin)
          if (_group.isAdmin) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _deleteGroup,
                icon: const Icon(Icons.delete_forever),
                label: const Text('Grubu Sil'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
