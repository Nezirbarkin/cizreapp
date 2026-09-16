import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/auth_shell.dart';

/// Google/Apple ile girişten hemen sonra çağrılır. `handle_new_user`
/// tetikleyicisi, OAuth sağlayıcısından username gelmediğinde geçici bir
/// `misafir_xxxxxxxx` adı üretir ve `profiles.needs_username`'i true yapar;
/// bu, kullanıcının henüz gerçek bir kullanıcı adı seçmediğini işaretler.
Future<bool> needsUsernameSetup() async {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId == null) return false;
  try {
    final response = await Supabase.instance.client
        .from('profiles')
        .select('needs_username')
        .eq('id', userId)
        .maybeSingle();
    return response?['needs_username'] == true;
  } catch (e) {
    debugPrint('⚠️ needsUsernameSetup kontrolü başarısız: $e');
    return false;
  }
}

/// Google/Apple ile kaydolan kullanıcıya, gerçek bir kullanıcı adı seçene
/// kadar uygulamanın geri kalanını açmayan zorunlu ara ekran.
class ChooseUsernameScreen extends StatefulWidget {
  const ChooseUsernameScreen({super.key});

  @override
  State<ChooseUsernameScreen> createState() => _ChooseUsernameScreenState();
}

class _ChooseUsernameScreenState extends State<ChooseUsernameScreen> {
  // register_screen_v2.dart'taki kullanıcı adı adımıyla aynı kurallar.
  static final RegExp _usernameAllowedChars = RegExp(r'^[a-zA-Z0-9._-]+$');

  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();

  bool _isLoading = false;
  bool _isCheckingUsername = false;
  bool _isUsernameAvailable = true;

  @override
  void dispose() {
    _usernameController.dispose();
    super.dispose();
  }

  String _sanitizeUsername(String value) {
    final buf = StringBuffer();
    for (final ch in value.characters) {
      if (RegExp(r'[a-zA-Z0-9._-]').hasMatch(ch)) buf.write(ch);
    }
    return buf.toString();
  }

  Future<void> _checkUsername(String username) async {
    if (!_usernameAllowedChars.hasMatch(username)) {
      if (mounted) setState(() => _isUsernameAvailable = false);
      return;
    }
    if (username.length < 3) return;
    setState(() => _isCheckingUsername = true);

    try {
      final response = await Supabase.instance.client
          .from('profiles')
          .select('username')
          .eq('username', username.toLowerCase())
          .maybeSingle();

      if (mounted) {
        setState(() {
          _isUsernameAvailable = response == null;
          _isCheckingUsername = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isCheckingUsername = false);
    }
  }

  String _translateClaimError(Object e) {
    final msg = e is PostgrestException ? e.message : e.toString();
    if (msg.contains('username taken')) return 'Bu kullanıcı adı alınmış.';
    if (msg.contains('invalid format')) {
      return 'Sadece harf, rakam, nokta, _ ve - kullan (3-20 karakter).';
    }
    if (msg.contains('reserved prefix')) {
      return 'Bu kullanıcı adını kullanamazsın, başka bir tane dene.';
    }
    if (msg.contains('already set')) {
      // needs_username zaten false: profil güncel, ana ekrana geçilebilir.
      return '';
    }
    return 'Kullanıcı adı kaydedilemedi, tekrar dene.';
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_isUsernameAvailable) return;

    setState(() => _isLoading = true);
    try {
      await Supabase.instance.client.rpc(
        'claim_username',
        params: {'p_username': _usernameController.text.trim().toLowerCase()},
      );
      if (mounted) _goToMain();
    } catch (e) {
      final message = _translateClaimError(e);
      if (message.isEmpty) {
        // Sunucuda username zaten tamamlanmış (ör. çift dokunma); akış
        // kullanıcı için tamamlanmış sayılır.
        if (mounted) _goToMain();
        return;
      }
      if (mounted) showAuthError(context, message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  /// `pushReplacementNamed` yerine tüm yığını temizler: bu ekran hem
  /// register/login'den `pushReplacement` ile (altında zaten hiçbir şey
  /// kalmaz) hem de main.dart'taki soğuk-başlangıç yakalamasından `push` ile
  /// (altında hazır bir MainScreen bulunur) açılabiliyor. İkinci durumda
  /// `pushReplacementNamed` altındaki MainScreen'i olduğu gibi bırakıp
  /// üstüne bir tane daha ekler; `pushNamedAndRemoveUntil` her iki giriş
  /// yolunda da yığında tek bir MainScreen kalmasını garanti eder.
  void _goToMain() {
    Navigator.of(context).pushNamedAndRemoveUntil('/main', (route) => false);
  }

  Future<void> _signOutAndExit() async {
    await Supabase.instance.client.auth.signOut();
    if (mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/login', (route) => false);
    }
  }

  Widget? _buildUsernameSuffix(AuthPalette p) {
    if (_isCheckingUsername) {
      return const Padding(
        padding: EdgeInsets.all(15),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_usernameController.text.length < 3) return null;
    return Icon(
      _isUsernameAvailable ? Icons.check_circle_rounded : Icons.cancel_rounded,
      color: _isUsernameAvailable ? p.success : p.danger,
      size: 20,
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = AuthPalette.of(context);

    // Kullanıcı adı seçilmeden ana uygulamaya dönemez; tek çıkış yolu
    // aşağıdaki "Çıkış yap" bağlantısıdır.
    return PopScope(
      canPop: false,
      child: AuthScaffold(
        title: 'Kullanıcı adı seç',
        subtitle: 'Hesabını kullanmaya başlamadan önce son bir adım kaldı.',
        footer: AuthFooterLink(
          question: 'Yanlış hesapla mı girdin?',
          action: 'Çıkış yap',
          onPressed: _isLoading ? () {} : _signOutAndExit,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AuthField(
                controller: _usernameController,
                hint: 'Kullanıcı adı',
                icon: Icons.alternate_email,
                autofocus: true,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.newUsername],
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[a-zA-Z0-9._-]')),
                ],
                onChanged: (v) {
                  final sanitized = _sanitizeUsername(v);
                  if (sanitized != v) {
                    _usernameController.value = TextEditingValue(
                      text: sanitized,
                      selection: TextSelection.collapsed(
                        offset: sanitized.length,
                      ),
                    );
                  }
                  setState(() {});
                  _checkUsername(sanitized);
                },
                onSubmitted: (_) => _submit(),
                suffix: _buildUsernameSuffix(p),
                helper:
                    'Sadece harf, rakam, nokta, _ ve - (3-20 karakter). '
                    'Kullanıcı adın sonradan değiştirilemez.',
                helperColor: p.warning,
                validator: (v) {
                  if (v?.isEmpty ?? true) return 'Kullanıcı adı gerekli';
                  if (!_usernameAllowedChars.hasMatch(v!)) {
                    return 'Sadece harf, rakam, nokta, _ ve - kullan';
                  }
                  if (v.length < 3) return 'En az 3 karakter';
                  if (v.length > 20) return 'En fazla 20 karakter';
                  if (!_isUsernameAvailable) return 'Bu ad kullanımda';
                  return null;
                },
              ),
              const SizedBox(height: 24),
              AuthPrimaryButton(
                label: 'Kaydı tamamla',
                isLoading: _isLoading,
                onPressed: _isLoading ? null : _submit,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
