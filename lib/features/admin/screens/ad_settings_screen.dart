import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/models/ad_settings_model.dart';
import '../../../core/services/ad_settings_service.dart';

class AdminAdSettingsScreen extends StatefulWidget {
  const AdminAdSettingsScreen({super.key});

  @override
  State<AdminAdSettingsScreen> createState() => _AdminAdSettingsScreenState();
}

class _AdminAdSettingsScreenState extends State<AdminAdSettingsScreen> {
  final AdSettingsService _service = AdSettingsService();

  AdSettings? _settings;
  bool _isLoading = true;
  bool _isSaving = false;

  bool _isEnabled = false;
  bool _testMode = true;

  late TextEditingController _appIdAndroidController;
  late TextEditingController _appIdIosController;
  late TextEditingController _rewardedUnitAndroidController;
  late TextEditingController _rewardedUnitIosController;
  late TextEditingController _rewardMinController;
  late TextEditingController _rewardMaxController;
  late TextEditingController _maxPerDayController;
  late TextEditingController _maxPerHourController;
  late TextEditingController _minWatchSecondsController;
  late TextEditingController _cooldownSecondsController;
  late TextEditingController _maxDailyPayoutController;
  late TextEditingController _cardDescriptionController;

  List<Map<String, dynamic>> _winners = [];
  bool _isLoadingWinners = true;

  @override
  void initState() {
    super.initState();
    _appIdAndroidController = TextEditingController();
    _appIdIosController = TextEditingController();
    _rewardedUnitAndroidController = TextEditingController();
    _rewardedUnitIosController = TextEditingController();
    _rewardMinController = TextEditingController();
    _rewardMaxController = TextEditingController();
    _maxPerDayController = TextEditingController();
    _maxPerHourController = TextEditingController();
    _minWatchSecondsController = TextEditingController();
    _cooldownSecondsController = TextEditingController();
    _maxDailyPayoutController = TextEditingController();
    _cardDescriptionController = TextEditingController();
    _loadSettings();
    _loadWinners();
  }

  @override
  void dispose() {
    _appIdAndroidController.dispose();
    _appIdIosController.dispose();
    _rewardedUnitAndroidController.dispose();
    _rewardedUnitIosController.dispose();
    _rewardMinController.dispose();
    _rewardMaxController.dispose();
    _maxPerDayController.dispose();
    _maxPerHourController.dispose();
    _minWatchSecondsController.dispose();
    _cooldownSecondsController.dispose();
    _maxDailyPayoutController.dispose();
    _cardDescriptionController.dispose();
    super.dispose();
  }

  Future<void> _loadWinners() async {
    setState(() => _isLoadingWinners = true);
    try {
      final views = await Supabase.instance.client
          .from('ad_reward_views')
          .select('user_id, reward_amount, created_at')
          .eq('status', 'success')
          .order('created_at', ascending: false)
          .limit(50);

      final userIds = views.map((v) => v['user_id'] as String).toSet().toList();
      final profiles = userIds.isEmpty
          ? <Map<String, dynamic>>[]
          : await Supabase.instance.client
              .from('profiles')
              .select('id, username, full_name')
              .inFilter('id', userIds);

      final profileMap = {for (final p in profiles) p['id'] as String: p};

      if (mounted) {
        setState(() {
          _winners = views.map<Map<String, dynamic>>((v) {
            final profile = profileMap[v['user_id']];
            return {
              'name': profile?['full_name'] ?? profile?['username'] ?? 'Bilinmeyen kullanıcı',
              'amount': v['reward_amount'],
              'created_at': v['created_at'],
            };
          }).toList();
          _isLoadingWinners = false;
        });
      }
    } catch (e) {
      debugPrint('⚠️ Kazananlar yüklenemedi: $e');
      if (mounted) setState(() => _isLoadingWinners = false);
    }
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);
    final settings = await _service.getSettings();
    if (settings != null && mounted) {
      _settings = settings;
      _isEnabled = settings.isEnabled;
      _testMode = settings.testMode;
      _appIdAndroidController.text = settings.admobAppIdAndroid ?? '';
      _appIdIosController.text = settings.admobAppIdIos ?? '';
      _rewardedUnitAndroidController.text = settings.admobRewardedUnitIdAndroid ?? '';
      _rewardedUnitIosController.text = settings.admobRewardedUnitIdIos ?? '';
      _rewardMinController.text = settings.rewardMinTry.toStringAsFixed(2);
      _rewardMaxController.text = settings.rewardMaxTry.toStringAsFixed(2);
      _maxPerDayController.text = settings.maxViewsPerDay.toString();
      _maxPerHourController.text = settings.maxViewsPerHour.toString();
      _minWatchSecondsController.text = settings.minWatchSeconds.toString();
      _cooldownSecondsController.text = settings.cooldownSeconds.toString();
      _maxDailyPayoutController.text = settings.maxDailyPayoutTry.toStringAsFixed(2);
      _cardDescriptionController.text = settings.cardDescription ?? '';
    }
    if (mounted) setState(() => _isLoading = false);
  }

  Future<void> _saveSettings() async {
    final rewardMin = double.tryParse(_rewardMinController.text.trim().replaceAll(',', '.'));
    final rewardMax = double.tryParse(_rewardMaxController.text.trim().replaceAll(',', '.'));
    final maxDay = int.tryParse(_maxPerDayController.text.trim());
    final maxHour = int.tryParse(_maxPerHourController.text.trim());
    final minWatch = int.tryParse(_minWatchSecondsController.text.trim());
    final cooldown = int.tryParse(_cooldownSecondsController.text.trim());
    final maxDailyPayout = double.tryParse(_maxDailyPayoutController.text.trim().replaceAll(',', '.'));

    if (rewardMin == null || rewardMax == null || maxDay == null || maxHour == null ||
        minWatch == null || cooldown == null || maxDailyPayout == null) {
      _showSnackBar('Lütfen tüm sayısal alanları geçerli değerlerle doldurun', isError: true);
      return;
    }
    if (rewardMax < rewardMin) {
      _showSnackBar('Maksimum ödül, minimumdan küçük olamaz', isError: true);
      return;
    }

    setState(() => _isSaving = true);
    try {
      final updated = (_settings ?? AdSettings(
        isEnabled: false,
        testMode: true,
        rewardMinTry: 0,
        rewardMaxTry: 0,
        maxViewsPerDay: 0,
        maxViewsPerHour: 0,
        minWatchSeconds: 0,
        cooldownSeconds: 0,
        maxDailyPayoutTry: 0,
      )).copyWith(
        isEnabled: _isEnabled,
        testMode: _testMode,
        admobAppIdAndroid: _appIdAndroidController.text.trim(),
        admobAppIdIos: _appIdIosController.text.trim(),
        admobRewardedUnitIdAndroid: _rewardedUnitAndroidController.text.trim(),
        admobRewardedUnitIdIos: _rewardedUnitIosController.text.trim(),
        rewardMinTry: rewardMin,
        rewardMaxTry: rewardMax,
        maxViewsPerDay: maxDay,
        maxViewsPerHour: maxHour,
        minWatchSeconds: minWatch,
        cooldownSeconds: cooldown,
        maxDailyPayoutTry: maxDailyPayout,
        cardDescription: _cardDescriptionController.text.trim(),
      );

      final success = await _service.updateSettings(updated);
      if (success && mounted) {
        _showSnackBar('Reklam ayarları kaydedildi', isError: false);
        await _loadSettings();
      } else if (mounted) {
        _showSnackBar('Ayarlar kaydedilirken hata oluştu', isError: true);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  void _showSnackBar(String message, {required bool isError}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.deepOrange,
        title: const Text('Reklam Ayarları', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (!_isLoading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: _isSaving
                    ? const SizedBox(
                        width: 20, height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : TextButton.icon(
                        onPressed: _saveSettings,
                        icon: const Icon(Icons.save, color: Colors.white),
                        label: const Text('Kaydet', style: TextStyle(color: Colors.white)),
                      ),
              ),
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                _buildSectionHeader('Genel', Icons.settings),
                const SizedBox(height: 12),
                _buildCard([
                  SwitchListTile(
                    title: const Text('İzleyerek Kazan Aktif', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      _isEnabled ? 'Kullanıcılar cüzdan ekranından reklam izleyip bakiye kazanabilir' : 'Özellik kapalı, kart kullanıcıya gösterilmez',
                      style: TextStyle(color: _isEnabled ? Colors.deepOrange : Colors.grey),
                    ),
                    value: _isEnabled,
                    onChanged: (v) => setState(() => _isEnabled = v),
                    activeThumbColor: Colors.deepOrange,
                    contentPadding: EdgeInsets.zero,
                  ),
                  SwitchListTile(
                    title: const Text('Test Modu', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: Text(
                      _testMode
                          ? 'Google\'ın test reklam birimleri kullanılıyor (AdMob hesabın askıya alınmaz)'
                          : 'GERÇEK reklamlar gösteriliyor - dikkatli olun',
                      style: TextStyle(color: _testMode ? Colors.blue : Colors.red, fontSize: 12),
                    ),
                    value: _testMode,
                    onChanged: (v) => setState(() => _testMode = v),
                    activeThumbColor: Colors.deepOrange,
                    contentPadding: EdgeInsets.zero,
                  ),
                  if (_testMode)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Kullanılan Google test reklam birimleri:\n'
                        'Android: ${AdSettings.testRewardedUnitIdAndroid}\n'
                        'iOS: ${AdSettings.testRewardedUnitIdIos}',
                        style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                      ),
                    ),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.warning_amber, color: Colors.red.shade700, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Uygulamayı yayınlamadan/güncellemeden önce Test Modu\'nu kapatıp gerçek AdMob birim ID\'lerini gir. Test modunda gerçek para kazanılmaz.',
                            style: TextStyle(fontSize: 11),
                          ),
                        ),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 24),

                _buildSectionHeader('AdMob Anahtarları', Icons.vpn_key),
                const SizedBox(height: 12),
                _buildCard([
                  _buildTextField(
                    controller: _appIdAndroidController,
                    label: 'AdMob App ID (Android)',
                    icon: Icons.android,
                    hint: 'ca-app-pub-XXXXXXXXXXXXXXXX~YYYYYYYYYY',
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _appIdIosController,
                    label: 'AdMob App ID (iOS)',
                    icon: Icons.phone_iphone,
                    hint: 'ca-app-pub-XXXXXXXXXXXXXXXX~ZZZZZZZZZZ',
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _rewardedUnitAndroidController,
                    label: 'Ödüllü Reklam Birim ID (Android)',
                    icon: Icons.android,
                    hint: 'ca-app-pub-XXXXXXXXXXXXXXXX/YYYYYYYYYY',
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _rewardedUnitIosController,
                    label: 'Ödüllü Reklam Birim ID (iOS)',
                    icon: Icons.phone_iphone,
                    hint: 'ca-app-pub-XXXXXXXXXXXXXXXX/ZZZZZZZZZZ',
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.orange.shade200),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Nereden alınır?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                        SizedBox(height: 4),
                        Text(
                          '1. admob.google.com adresine gir, hesap oluştur.\n'
                          '2. "Uygulamalar" > "Uygulama Ekle" ile Android ve iOS için ayrı uygulama tanımla; buradan App ID\'leri alırsın.\n'
                          '3. Her uygulama için "Reklam Birimleri" > "Ödüllü" seçip birim oluştur; buradan Birim ID alırsın.\n'
                          '4. App ID\'leri BURAYA girmek yeterli değildir; AndroidManifest.xml ve Info.plist dosyalarına da elle eklenmelidir (kod tarafında zaten test ID ile hazır, gerçek ID ile değiştir).',
                          style: TextStyle(fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 24),

                _buildSectionHeader('Ödül & Limitler', Icons.tune),
                const SizedBox(height: 12),
                _buildCard([
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: _rewardMinController,
                          label: 'Min. Ödül (₺)',
                          icon: Icons.trending_down,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          controller: _rewardMaxController,
                          label: 'Max. Ödül (₺)',
                          icon: Icons.trending_up,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.purple.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Her izlemede kullanıcı bu aralıkta RASTGELE bir ödül kazanır (küçük tutarlara ağırlıklı, büyük tutar seyrek çıkar) — "şans" hissi çok izlenmeyi teşvik eder.',
                      style: TextStyle(fontSize: 11, color: Colors.deepPurple),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: _maxPerDayController,
                          label: 'Günlük Max İzlenme',
                          icon: Icons.today,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          controller: _maxPerHourController,
                          label: 'Saatlik Max İzlenme',
                          icon: Icons.schedule,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: _buildTextField(
                          controller: _minWatchSecondsController,
                          label: 'Min. İzlenme Süresi (sn)',
                          icon: Icons.timer,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildTextField(
                          controller: _cooldownSecondsController,
                          label: 'İki İzlenme Arası Bekleme (sn)',
                          icon: Icons.hourglass_bottom,
                          keyboardType: TextInputType.number,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildTextField(
                    controller: _maxDailyPayoutController,
                    label: 'Platform Günlük Toplam Ödül Tavanı (₺)',
                    icon: Icons.account_balance,
                    keyboardType: TextInputType.number,
                  ),
                ]),
                const SizedBox(height: 24),

                _buildSectionHeader('Kart Açıklaması', Icons.edit_note),
                const SizedBox(height: 12),
                _buildCard([
                  TextFormField(
                    controller: _cardDescriptionController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: InputDecoration(
                      labelText: 'Cüzdandaki kart açıklama metni',
                      hintText: 'Boş bırakılırsa "₺X - ₺Y arası şansla bakiye kazan" otomatik gösterilir',
                      hintStyle: const TextStyle(fontSize: 11),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                      filled: true,
                      fillColor: Colors.grey.shade50,
                    ),
                  ),
                ]),
                const SizedBox(height: 24),

                _buildSectionHeader('Kazananlar', Icons.emoji_events),
                const SizedBox(height: 12),
                _buildCard([
                  if (_isLoadingWinners)
                    const Center(child: Padding(padding: EdgeInsets.all(12), child: CircularProgressIndicator()))
                  else if (_winners.isEmpty)
                    const Text('Henüz reklam izleyerek bakiye kazanan kullanıcı yok', style: TextStyle(fontSize: 12, color: Colors.grey))
                  else
                    ..._winners.map((w) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(
                            children: [
                              const Icon(Icons.person, size: 18, color: Colors.deepOrange),
                              const SizedBox(width: 8),
                              Expanded(child: Text(w['name'] as String, style: const TextStyle(fontSize: 13))),
                              Text(
                                '+₺${(w['amount'] as num).toStringAsFixed(2)}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.green),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                DateFormat('dd.MM HH:mm').format(DateTime.parse(w['created_at'] as String).toLocal()),
                                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                              ),
                            ],
                          ),
                        )),
                ]),
                const SizedBox(height: 24),

                _buildSectionHeader('Kötüye Kullanım Koruması', Icons.shield),
                const SizedBox(height: 12),
                _buildCard([
                  const Text(
                    'Aşağıdaki korumalar otomatik olarak, sunucu tarafında (Edge Function) uygulanır; '
                    'istemci (mobil uygulama) tarafında herhangi bir sahtecilik bakiyeyi etkileyemez:',
                    style: TextStyle(fontSize: 12, color: Colors.black87),
                  ),
                  const SizedBox(height: 8),
                  _buildProtectionRow('Bakiye SADECE sunucu tarafında (service_role) güncellenir; uygulama doğrudan veritabanına yazamaz.'),
                  _buildProtectionRow('Kullanıcı başına günlük/saatlik izlenme limiti ve iki izlenme arası bekleme süresi zorunludur.'),
                  _buildProtectionRow('Aynı cihazdan farklı hesaplarla çok sayıda izlenme (cihaz kimliği) tespit edilip sınırlanır.'),
                  _buildProtectionRow('Platform genelinde günlük toplam ödül bütçesi aşılamaz.'),
                  _buildProtectionRow('AdMob\'un kendi "onUserEarnedReward" callback\'i tetiklenmeden ödül talebi oluşturulamaz; reklamı atlayan/tıklama botları ödül alamaz.'),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Daha güçlü koruma için AdMob "Server-Side Verification (SSV)" kurulabilir; '
                      'bu, ödülün sadece Google\'ın imzaladığı sunucu callback\'i ile verilmesini sağlar. '
                      'İsterseniz sonraki adımda ekleyebilirim.',
                      style: TextStyle(fontSize: 11, color: Colors.blueGrey),
                    ),
                  ),
                ]),
                const SizedBox(height: 32),
              ],
            ),
    );
  }

  Widget _buildProtectionRow(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 16),
          const SizedBox(width: 6),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12))),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.deepOrange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.deepOrange, size: 20),
        ),
        const SizedBox(width: 12),
        Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
      ],
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 12, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? hint,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 11),
        prefixIcon: Icon(icon, size: 20),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Colors.deepOrange, width: 2),
        ),
        filled: true,
        fillColor: Colors.grey.shade50,
      ),
    );
  }
}
