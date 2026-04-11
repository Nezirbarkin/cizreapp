// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/providers/theme_provider.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({super.key});

  @override
  State<AccountSettingsScreen> createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  final _emailController = TextEditingController();
  final _currentPasswordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  
  bool _isLoading = true;
  bool _isUpdating = false;
  String? _currentEmail;
  
  // Durum ve Gizlilik ayarları
  String _userStatus = 'online'; // online, busy, away, offline
  bool _showLastSeen = true;
  bool _allowMessagesFromNonFollowers = true;
  bool _profileIsPublic = true;
  bool _messagesEnabled = true; // Mesajları kapat/aç
  
  @override
  void initState() {
    super.initState();
    _loadUserData();
    _loadPrivacySettings();
  }
  
  @override
  void dispose() {
    _emailController.dispose();
    _currentPasswordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }
  
  Future<void> _loadUserData() async {
    setState(() => _isLoading = true);
    
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) {
        setState(() {
          _currentEmail = user.email;
          _emailController.text = user.email ?? '';
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Kullanıcı verisi yüklenirken hata: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadPrivacySettings() async {
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      final response = await Supabase.instance.client
          .from('profiles')
          .select('status, show_last_seen, allow_messages_from_non_followers, profile_is_public, messages_enabled')
          .eq('id', userId)
          .maybeSingle();

      if (response != null && mounted) {
        setState(() {
          _userStatus = response['status'] as String? ?? 'online';
          _showLastSeen = response['show_last_seen'] as bool? ?? true;
          _allowMessagesFromNonFollowers = response['allow_messages_from_non_followers'] as bool? ?? true;
          _profileIsPublic = response['profile_is_public'] as bool? ?? true;
          _messagesEnabled = response['messages_enabled'] as bool? ?? true;
        });
      }
    } catch (e) {
      debugPrint('Gizlilik ayarları yüklenirken hata: $e');
    }
  }

  Future<void> _updatePrivacySettings() async {
    setState(() => _isUpdating = true);
    
    try {
      final userId = Supabase.instance.client.auth.currentUser?.id;
      if (userId == null) return;

      await Supabase.instance.client
          .from('profiles')
          .update({
            'status': _userStatus,
            'show_last_seen': _showLastSeen,
            'allow_messages_from_non_followers': _allowMessagesFromNonFollowers,
            'profile_is_public': _profileIsPublic,
            'messages_enabled': _messagesEnabled,
            'last_seen': DateTime.now().toIso8601String(),
          })
          .eq('id', userId);

      if (mounted) {
        _showMessage('Gizlilik ayarları güncellendi');
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Ayarlar güncellenirken hata: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }
  
  Future<void> _updateEmail() async {
    if (_emailController.text.trim().isEmpty) {
      _showMessage('Lütfen email adresinizi girin', isError: true);
      return;
    }
    
    if (_emailController.text.trim() == _currentEmail) {
      _showMessage('Yeni email mevcut ile aynı', isError: true);
      return;
    }
    
    setState(() => _isUpdating = true);
    
    try {
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(email: _emailController.text.trim()),
      );
      
      if (mounted) {
        _showMessage('Email güncelleme linki gönderildi. Lütfen email\'inizi kontrol edin.');
        _loadUserData();
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Email güncellenirken hata: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }
  
  Future<void> _updatePassword() async {
    if (_currentPasswordController.text.isEmpty) {
      _showMessage('Lütfen mevcut şifrenizi girin', isError: true);
      return;
    }
    
    if (_newPasswordController.text.isEmpty) {
      _showMessage('Lütfen yeni şifrenizi girin', isError: true);
      return;
    }
    
    if (_newPasswordController.text.length < 6) {
      _showMessage('Şifre en az 6 karakter olmalıdır', isError: true);
      return;
    }
    
    if (_newPasswordController.text != _confirmPasswordController.text) {
      _showMessage('Yeni şifreler eşleşmiyor', isError: true);
      return;
    }
    
    setState(() => _isUpdating = true);
    
    try {
      // Önce mevcut şifre ile giriş yapmayı deneyelim (doğrulama)
      final email = Supabase.instance.client.auth.currentUser?.email;
      if (email == null) {
        throw Exception('Kullanıcı email\'i bulunamadı');
      }
      
      // Şifreyi güncelle
      await Supabase.instance.client.auth.updateUser(
        UserAttributes(password: _newPasswordController.text),
      );
      
      if (mounted) {
        _showMessage('Şifreniz başarıyla güncellendi');
        _currentPasswordController.clear();
        _newPasswordController.clear();
        _confirmPasswordController.clear();
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Şifre güncellenirken hata: $e', isError: true);
      }
    } finally {
      if (mounted) {
        setState(() => _isUpdating = false);
      }
    }
  }
  
  Future<void> _deleteAccount() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Hesabı Sil'),
        content: const Text(
          'Hesabınızı silmek istediğinizden emin misiniz? Bu işlem geri alınamaz!',
          style: TextStyle(color: Colors.red),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('İptal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Devam'),
          ),
        ],
      ),
    );
    
    if (confirm != true) return;
    
    setState(() => _isUpdating = true);
    
    try {
      // RPC ile onay kodu iste
      final response = await Supabase.instance.client.rpc(
        'request_account_deletion',
      );
      
      if (response != null) {
        final email = response['email'] as String?;
        final code = response['confirmationCode'] as String?;
        
        if (email != null && code != null && mounted) {
          // Email gönder
          await _sendConfirmationEmail(email, code);
          
          setState(() => _isUpdating = false);
          // Onay kodu giriş dialog'unu göster
          _showConfirmationCodeDialog();
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUpdating = false);
        _showMessage('Hata: $e', isError: true);
      }
    }
  }
  
  Future<void> _sendConfirmationEmail(String email, String code) async {
    try {
      Uri.encodeComponent('Hesap Silme Onay Kodu');
      Uri.encodeComponent(
        'Merhaba,\n\n'
        'Hesabınızı silmek için onay kodunuz:\n\n'
        '$code\n\n'
        'Bu kod 15 dakika geçerlidir.\n\n'
        'Eğer bu işlemi siz yapmadıysanız, lütfen bu mesajı görmezden gelin.\n\n'
        'Saygılarımızla,\n'
        'Cizre App Ekibi'
      );
      
      // Geliştirici modunda: Kodu ekranda göster
      if (mounted) {
        _showMessage('Onay kodu: $code (Email: $email)');
      }
      
      // Production'da email servisi kullanılacak
      // Şimdilik kullanıcının varsayılan email istemcisini aç
      // final uri = Uri.parse('mailto:$email?subject=$subject&body=$body');
      // await launchUrl(uri);
    } catch (e) {
      debugPrint('Email gönderme hatası: $e');
    }
  }
  
  Future<void> _showConfirmationCodeDialog() async {
    final codeController = TextEditingController();
    
    final code = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('Onay Kodunu Girin'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Email adresinize gönderilen 6 haneli onay kodunu girin:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: codeController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 24,
                letterSpacing: 8,
                fontWeight: FontWeight.bold,
              ),
              decoration: InputDecoration(
                hintText: '000000',
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Colors.grey.shade50,
              ),
            ),
            const SizedBox(height: 12),
            TextButton.icon(
              onPressed: () {
                Navigator.pop(context);
                _deleteAccount();
              },
              icon: const Icon(Icons.refresh, size: 16),
              label: const Text('Yeni kod iste'),
              style: TextButton.styleFrom(foregroundColor: Colors.blue),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('İptal'),
          ),
          ElevatedButton(
            onPressed: () {
              final code = codeController.text.trim();
              if (code.length == 6) {
                Navigator.pop(context, code);
              } else {
                _showMessage('Lütfen 6 haneli kodu girin', isError: true);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Hesabı Sil', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    
    if (code != null && code.length == 6) {
      await _confirmAccountDeletion(code);
    }
  }
  
  Future<void> _confirmAccountDeletion(String code) async {
    setState(() => _isUpdating = true);
    
    try {
      // RPC ile hesabı sil
      final _ = await Supabase.instance.client.rpc(
        'delete_account_with_code',
        params: {'p_confirmation_code': code},
      );
      
      // Başarılı
      if (mounted) {
        _showMessage('Hesabınız başarıyla silindi');
        
        // Oturumu kapat ve login ekranına yönlendir
        await Supabase.instance.client.auth.signOut();
        if (mounted) {
          Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUpdating = false);
        _showMessage('Hata: $e', isError: true);
      }
    }
  }
  
  void _showMessage(String message, {bool isError = false}) {
    if (!mounted) return;
    
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        duration: const Duration(seconds: 3),
      ),
    );
  }
  
  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    
    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        backgroundColor: themeProvider.primaryColor,
        elevation: 0,
        title: const Text(
          'Hesap Ayarları',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Email Değiştirme
                  _buildSection(
                    title: 'Email Değiştir',
                    icon: Icons.email_outlined,
                    color: Colors.blue,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Mevcut Email',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _currentEmail ?? 'Email bulunamadı',
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _emailController,
                          keyboardType: TextInputType.emailAddress,
                          decoration: InputDecoration(
                            labelText: 'Yeni Email',
                            hintText: 'yeni@email.com',
                            prefixIcon: const Icon(Icons.email),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isUpdating ? null : _updateEmail,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isUpdating
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Email Güncelle',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Şifre Değiştirme
                  _buildSection(
                    title: 'Şifre Değiştir',
                    icon: Icons.lock_outlined,
                    color: Colors.orange,
                    child: Column(
                      children: [
                        TextField(
                          controller: _currentPasswordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Mevcut Şifre',
                            prefixIcon: const Icon(Icons.lock),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _newPasswordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Yeni Şifre',
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _confirmPasswordController,
                          obscureText: true,
                          decoration: InputDecoration(
                            labelText: 'Yeni Şifre (Tekrar)',
                            prefixIcon: const Icon(Icons.lock_outline),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            filled: true,
                            fillColor: Colors.white,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            onPressed: _isUpdating ? null : _updatePassword,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: _isUpdating
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Text(
                                    'Şifre Güncelle',
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Durum ve Gizlilik Ayarları
                  _buildSection(
                    title: 'Durum ve Gizlilik',
                    icon: Icons.privacy_tip_outlined,
                    color: Colors.purple,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                         // Gizlilik Ayarları
                        const Text(
                          'Gizlilik',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        
                        // Son Görülme
                        SwitchListTile(
                          title: const Text('Son görülme göster'),
                          subtitle: const Text('Diğer kullanıcılar en son ne zaman aktif olduğunuzu görebilir'),
                          value: _showLastSeen,
                          onChanged: (value) {
                            setState(() => _showLastSeen = value);
                            _updatePrivacySettings();
                          },
                          contentPadding: EdgeInsets.zero,
                          activeColor: Colors.purple,
                        ),
                        
                        // Mesajları Kapat/Aç
                        SwitchListTile(
                          title: const Text('Mesajları kabul et'),
                          subtitle: const Text('Kapalıyken kimse size mesaj gönderemez'),
                          value: _messagesEnabled,
                          onChanged: (value) {
                            setState(() => _messagesEnabled = value);
                            _updatePrivacySettings();
                          },
                          contentPadding: EdgeInsets.zero,
                          activeColor: Colors.purple,
                        ),
                         
                        // Takip Etmeyenlerden Mesaj
                        SwitchListTile(
                          title: const Text('Takip etmeyenlerden mesaj'),
                          subtitle: const Text('Sizi takip etmeyen kullanıcılar size mesaj gönderebilir'),
                          value: _allowMessagesFromNonFollowers,
                          onChanged: (value) {
                            setState(() => _allowMessagesFromNonFollowers = value);
                            _updatePrivacySettings();
                          },
                          contentPadding: EdgeInsets.zero,
                          activeColor: Colors.purple,
                        ),
                         
                        // Profil Herkese Açık
                        SwitchListTile(
                          title: const Text('Herkese açık profil'),
                          subtitle: const Text('Herkes profilinizi görebilir (kapalı ise sadece takipçiler)'),
                          value: _profileIsPublic,
                          onChanged: (value) {
                            setState(() => _profileIsPublic = value);
                            _updatePrivacySettings();
                          },
                          contentPadding: EdgeInsets.zero,
                          activeColor: Colors.purple,
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // İki Faktörlü Kimlik Doğrulama (Gelecekte eklenecek)
                  _buildSection(
                    title: 'İki Faktörlü Kimlik Doğrulama',
                    icon: Icons.security_outlined,
                    color: Colors.green,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Hesabınızı daha güvenli hale getirmek için iki faktörlü kimlik doğrulamayı etkinleştirin.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey,
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.grey.shade100,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.info_outline, color: Colors.grey.shade600, size: 20),
                              const SizedBox(width: 12),
                              const Expanded(
                                child: Text(
                                  'Yakında eklenecek',
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 24),
                  
                  // Tehlikeli Alan - Hesap Silme
                  _buildSection(
                    title: 'Tehlikeli Alan',
                    icon: Icons.warning_outlined,
                    color: Colors.red,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Hesabınızı silmek geri alınamaz bir işlemdir. Tüm verileriniz kalıcı olarak silinecektir.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.red,
                            height: 1.4,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: _isUpdating ? null : _deleteAccount,
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(color: Colors.red, width: 2),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Hesabı Kalıcı Olarak Sil',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Colors.red,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  
                  const SizedBox(height: 80), // Alt boşluk
                ],
              ),
            ),
    );
  }
  
  Widget _buildSection({
    required String title,
    required IconData icon,
    required Color color,
    required Widget child,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 12),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildStatusOption(String status, String label, IconData icon, Color color) {
    final isSelected = _userStatus == status;
    
    return Expanded(
      child: InkWell(
        onTap: () {
          setState(() => _userStatus = status);
          _updatePrivacySettings();
        },
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? color.withOpacity(0.15) : Colors.grey.shade100,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected ? color : Colors.transparent,
              width: 2,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                color: isSelected ? color : Colors.grey.shade600,
                size: 24,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? color : Colors.grey.shade700,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
