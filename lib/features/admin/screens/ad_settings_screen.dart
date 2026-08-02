import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/models/admin_reward_overview_model.dart';
import '../../../core/models/ad_settings_model.dart';
import '../../../core/services/ad_settings_service.dart';

class AdminAdSettingsScreen extends StatefulWidget {
  const AdminAdSettingsScreen({super.key});

  @override
  State<AdminAdSettingsScreen> createState() => _AdminAdSettingsScreenState();
}

class _AdminAdSettingsScreenState extends State<AdminAdSettingsScreen> {
  final _service = AdSettingsService();
  final _rewardController = TextEditingController();
  final _budgetController = TextEditingController();
  final _rateController = TextEditingController();
  final _maxViewsDayController = TextEditingController();
  final _maxViewsHourController = TextEditingController();
  final _cooldownController = TextEditingController();
  final _reasonController = TextEditingController();
  final _appIdAndroidController = TextEditingController();
  final _appIdIosController = TextEditingController();
  final _rewardedUnitAndroidController = TextEditingController();
  final _rewardedUnitIosController = TextEditingController();

  AdSettings? _settings;
  AdminRewardOverview? _overview;
  RewardFeatureMode _mode = RewardFeatureMode.disabled;
  bool _testMode = false;
  bool _earnEnabled = false;
  bool _ssvEnabled = false;
  bool _spendEnabled = false;
  bool _eligibleProductsEnabled = false;
  bool _adminReportingEnabled = false;
  bool _loading = true;
  bool _saving = false;
  bool _loadingOverview = true;

  @override
  void initState() {
    super.initState();
    _load();
    _loadOverview();
  }

  @override
  void dispose() {
    _rewardController.dispose();
    _budgetController.dispose();
    _rateController.dispose();
    _maxViewsDayController.dispose();
    _maxViewsHourController.dispose();
    _cooldownController.dispose();
    _reasonController.dispose();
    _appIdAndroidController.dispose();
    _appIdIosController.dispose();
    _rewardedUnitAndroidController.dispose();
    _rewardedUnitIosController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final settings = await _service.getSettings();
      if (!mounted) return;
      if (settings == null) {
        _snack(
          'Reklam ayarları yüklenemedi. Migration ve RPC kurulumunu kontrol edin.',
          error: true,
        );
        setState(() => _loading = false);
        return;
      }
      setState(() {
        _settings = settings;
        _mode = settings.rewardFeatureMode;
        _testMode = settings.testMode;
        _earnEnabled = settings.rewardPointsEarnEnabled;
        _ssvEnabled = settings.rewardPointsSsvEnabled;
        _spendEnabled = settings.rewardPointsSpendEnabled;
        _eligibleProductsEnabled = settings.rewardPointsEligibleProductsEnabled;
        _adminReportingEnabled = settings.rewardPointsAdminReportingEnabled;
        _rewardController.text = settings.rewardMinPoints.toString();
        _budgetController.text = (settings.maxDailyRewardPoints ?? 0)
            .toString();
        _rateController.text = settings.pointsPerTry.toString();
        _maxViewsDayController.text =
            (settings.maxViewsPerDay == 0 ? 10 : settings.maxViewsPerDay)
                .toString();
        _maxViewsHourController.text =
            (settings.maxViewsPerHour == 0 ? 3 : settings.maxViewsPerHour)
                .toString();
        _cooldownController.text = settings.cooldownSeconds.toString();
        _rewardedUnitAndroidController.text =
            settings.admobRewardedUnitIdAndroid ?? '';
        _rewardedUnitIosController.text = settings.admobRewardedUnitIdIos ?? '';
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      _snack('Reklam ayarları yüklenemedi: $error', error: true);
    }
  }

  Future<void> _loadOverview() async {
    try {
      final overview = await _service.getAdminOverview();
      if (!mounted) return;
      setState(() {
        _overview = overview;
        final config = overview.config;
        _appIdAndroidController.text = config.admobAppIdAndroid ?? '';
        _appIdIosController.text = config.admobAppIdIos ?? '';
        _rewardedUnitAndroidController.text =
            config.admobRewardedUnitIdAndroid ??
            _rewardedUnitAndroidController.text;
        _rewardedUnitIosController.text =
            config.admobRewardedUnitIdIos ?? _rewardedUnitIosController.text;
        _loadingOverview = false;
      });
    } catch (_) {
      // Rapor yüklenemezse form yine de kullanılabilir.
      if (mounted) setState(() => _loadingOverview = false);
    }
  }

  bool get _productionReady =>
      !_testMode &&
      _settings?.rewardPointsSchemaReady == true &&
      _settings?.rewardPointsSsvRequired == true &&
      _settings?.legacyAdTlGrantDisabled == true &&
      _rewardedUnitAndroidController.text.trim().isNotEmpty &&
      _rewardedUnitIosController.text.trim().isNotEmpty &&
      _ssvEnabled &&
      _mode == RewardFeatureMode.enabled;

  Future<void> _save() async {
    final rewardPoints = int.tryParse(_rewardController.text.trim()) ?? -1;
    final update = RewardPointsConfigUpdate(
      rewardMinPoints: rewardPoints,
      rewardMaxPoints: rewardPoints,
      maxDailyRewardPoints: int.tryParse(_budgetController.text.trim()) ?? -1,
      pointsPerTry: int.tryParse(_rateController.text.trim()) ?? -1,
      testMode: _testMode,
      admobAppIdAndroid: _appIdAndroidController.text,
      admobAppIdIos: _appIdIosController.text,
      admobRewardedUnitIdAndroid: _rewardedUnitAndroidController.text,
      admobRewardedUnitIdIos: _rewardedUnitIosController.text,
      featureMode: _mode,
      earnEnabled: _earnEnabled,
      ssvEnabled: _ssvEnabled,
      spendEnabled: _spendEnabled,
      eligibleProductsEnabled: _eligibleProductsEnabled,
      adminReportingEnabled: _adminReportingEnabled,
      maxViewsPerDay: int.tryParse(_maxViewsDayController.text.trim()) ?? 0,
      maxViewsPerHour: int.tryParse(_maxViewsHourController.text.trim()) ?? 0,
      cooldownSeconds: int.tryParse(_cooldownController.text.trim()) ?? 0,
      reason: _reasonController.text,
    );
    final error = update.validate();
    if (error != null) {
      _snack(error, error: true);
      return;
    }
    setState(() => _saving = true);
    try {
      await _service.updateRewardPointsConfig(update);
      if (!mounted) return;
      _reasonController.clear();
      _snack('Reklam ve puan ayarları güvenli biçimde kaydedildi.');
      await _load();
      await _loadOverview();
    } catch (error) {
      if (mounted) _snack('Ayarlar kaydedilemedi: $error', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _snack(String text, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(text),
        backgroundColor: error ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reklam ve Puan Yönetimi'),
        actions: [
          IconButton(
            tooltip: 'Yenile',
            onPressed: _saving
                ? null
                : () async {
                    setState(() {
                      _loading = true;
                      _loadingOverview = true;
                    });
                    await Future.wait([_load(), _loadOverview()]);
                  },
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1120),
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _heroCard(),
                    const SizedBox(height: 16),
                    _environmentCard(),
                    const SizedBox(height: 16),
                    _adMobConfigurationCard(),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 760;
                        return wide
                            ? Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(child: _pointsCard()),
                                  const SizedBox(width: 16),
                                  Expanded(child: _limitsCard()),
                                ],
                              )
                            : Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _pointsCard(),
                                  const SizedBox(height: 16),
                                  _limitsCard(),
                                ],
                              );
                      },
                    ),
                    const SizedBox(height: 16),
                    _featureControlsCard(),
                    const SizedBox(height: 16),
                    _readinessCard(),
                    const SizedBox(height: 16),
                    _todayCard(),
                    const SizedBox(height: 16),
                    _saveCard(),
                    const SizedBox(height: 16),
                    _recentEventsCard(),
                    const SizedBox(height: 16),
                    _topEarnersCard(),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _heroCard() {
    final points = int.tryParse(_rewardController.text) ?? 0;
    final rate = int.tryParse(_rateController.text) ?? 100;
    final rewardTry = rate <= 0 ? 0.0 : points / rate;
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF172554), Color(0xFF1D4ED8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Wrap(
        spacing: 24,
        runSpacing: 18,
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          const SizedBox(
            width: 560,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ödüllü Reklam Merkezi',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  'AdMob kimlikleri, test/gerçek ortam, puan ekonomisi, izleme sınırları ve SSV güvenliğini tek yerden yönetin.',
                  style: TextStyle(color: Colors.white70, height: 1.4),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white24),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$points puan = ${rewardTry.toStringAsFixed(2)} TL',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  '$rate puan = 1 TL dijital indirim',
                  style: const TextStyle(color: Colors.white70),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _environmentCard() {
    return _section('1. Reklam Ortamı', [
      const Text(
        'Önce hangi reklam ortamını kullanacağınızı seçin. Test reklamları Google’ın resmi test birimleriyle gösterilir ve gerçek puan üretmez.',
      ),
      const SizedBox(height: 14),
      SegmentedButton<bool>(
        segments: const [
          ButtonSegment(
            value: true,
            icon: Icon(Icons.science_rounded),
            label: Text('Test reklamı'),
          ),
          ButtonSegment(
            value: false,
            icon: Icon(Icons.campaign_rounded),
            label: Text('Gerçek reklam'),
          ),
        ],
        selected: {_testMode},
        onSelectionChanged: (selection) => setState(() {
          _testMode = selection.first;
          if (_testMode) _earnEnabled = false;
        }),
      ),
      const SizedBox(height: 12),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: (_testMode ? Colors.blue : Colors.green).withValues(
            alpha: 0.08,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Icon(
              _testMode ? Icons.info_outline : Icons.verified_user_outlined,
              color: _testMode ? Colors.blue : Colors.green,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _testMode
                    ? 'Test modu aktifken gerçek AdMob kimlikleri kullanılmaz ve ekonomik puan yazılmaz.'
                    : 'Gerçek modda aşağıdaki Rewarded Unit ID’leri ve Edge Function SSV allowlist’i eşleşmelidir.',
              ),
            ),
          ],
        ),
      ),
    ]);
  }

  Widget _adMobConfigurationCard() {
    final callbackUrl =
        '${AppConstants.supabaseUrl}/functions/v1/admob-ssv-callback';
    return _section('2. AdMob ve SSV Yapılandırması', [
      LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= 720;
          final android = _platformConfiguration(
            title: 'Android',
            icon: Icons.android_rounded,
            appController: _appIdAndroidController,
            unitController: _rewardedUnitAndroidController,
          );
          final ios = _platformConfiguration(
            title: 'iOS',
            icon: Icons.apple_rounded,
            appController: _appIdIosController,
            unitController: _rewardedUnitIosController,
          );
          return wide
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: android),
                    const SizedBox(width: 16),
                    Expanded(child: ios),
                  ],
                )
              : Column(children: [android, const SizedBox(height: 16), ios]);
        },
      ),
      const SizedBox(height: 16),
      InputDecorator(
        decoration: InputDecoration(
          labelText: 'AdMob SSV callback URL',
          prefixIcon: const Icon(Icons.link_rounded),
          suffixIcon: IconButton(
            tooltip: 'Kopyala',
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: callbackUrl));
              if (mounted) _snack('SSV callback URL kopyalandı.');
            },
            icon: const Icon(Icons.copy_rounded),
          ),
          border: const OutlineInputBorder(),
        ),
        child: SelectableText(callbackUrl),
      ),
      const SizedBox(height: 12),
      const Text(
        'Gizli API anahtarı bu ekrana girilmez. Supabase Edge Function Secrets içinde ADMOB_SSV_HASH_SECRET ve diğer SSV değişkenleri tutulmalıdır. App ID değişikliği native Android/iOS yapılandırmasında da aynı değerle yeni uygulama sürümü gerektirir.',
        style: TextStyle(fontSize: 12, height: 1.45),
      ),
    ]);
  }

  Widget _platformConfiguration({
    required String title,
    required IconData icon,
    required TextEditingController appController,
    required TextEditingController unitController,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _idField(
            appController,
            'AdMob App ID',
            'ca-app-pub-0000000000000000~0000000000',
          ),
          const SizedBox(height: 12),
          _idField(
            unitController,
            'Rewarded Unit ID',
            'ca-app-pub-0000000000000000/0000000000',
            enabled: !_testMode,
          ),
        ],
      ),
    );
  }

  Widget _pointsCard() {
    final points = int.tryParse(_rewardController.text) ?? 0;
    final rate = int.tryParse(_rateController.text) ?? 100;
    final value = rate > 0 ? points / rate : 0;
    return _section('3. Puan Ekonomisi', [
      _integerField(
        _rewardController,
        'Reklam başına puan',
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      _integerField(
        _rateController,
        '1 TL karşılığı puan',
        onChanged: (_) => setState(() {}),
      ),
      const SizedBox(height: 12),
      _integerField(_budgetController, 'Günlük toplam puan bütçesi'),
      const SizedBox(height: 14),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          'Örnek: $rate puan = 1 TL • Bir reklam $points puan = ${value.toStringAsFixed(2)} TL dijital indirim değeri',
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
      ),
      const SizedBox(height: 10),
      const Text(
        'Puan nakit değildir; yalnız uygun dijital ürünlerde indirim sağlar. Transfer edilemez veya çekilemez.',
        style: TextStyle(fontSize: 12),
      ),
    ]);
  }

  Widget _limitsCard() {
    return _section('4. Kullanım Limitleri', [
      _integerField(_maxViewsDayController, 'Kullanıcı / günlük reklam'),
      const SizedBox(height: 12),
      _integerField(_maxViewsHourController, 'Kullanıcı / saatlik reklam'),
      const SizedBox(height: 12),
      _integerField(_cooldownController, 'Reklamlar arası bekleme (saniye)'),
      const SizedBox(height: 12),
      const Text(
        'Limitler istemcide değil, doğrulanmış SSV işlemi sırasında sunucuda uygulanır.',
        style: TextStyle(fontSize: 12),
      ),
    ]);
  }

  Widget _featureControlsCard() {
    return _section('5. Yayın ve Güvenlik Kontrolleri', [
      DropdownButtonFormField<RewardFeatureMode>(
        initialValue: _mode,
        decoration: const InputDecoration(
          labelText: 'Yayın modu',
          border: OutlineInputBorder(),
        ),
        items: RewardFeatureMode.values.map((mode) {
          final label = switch (mode) {
            RewardFeatureMode.disabled => 'Kapalı',
            RewardFeatureMode.observe => 'Yalnız gözlem',
            RewardFeatureMode.cohort => 'Sınırlı kullanıcı grubu',
            RewardFeatureMode.enabled => 'Tüm kullanıcılara açık',
          };
          return DropdownMenuItem(value: mode, child: Text(label));
        }).toList(),
        onChanged: (value) => setState(() {
          _mode = value ?? _mode;
          if (_mode != RewardFeatureMode.enabled) _earnEnabled = false;
        }),
      ),
      const SizedBox(height: 8),
      _settingSwitch(
        title: 'SSV kurulumu ve allowlist hazır',
        subtitle:
            'Supabase Secrets, callback URL ve AdMob rewarded birimleri deploy edildi.',
        value: _ssvEnabled,
        onChanged: _testMode
            ? null
            : (value) => setState(() {
                _ssvEnabled = value;
                if (!value) _earnEnabled = false;
              }),
      ),
      _settingSwitch(
        title: 'Doğrulanmış reklamdan puan kazanımı',
        subtitle: _testMode
            ? 'Test modunda güvenlik gereği kapalıdır.'
            : 'Yalnız Google SSV doğrulamasından sonra puan yazar.',
        value: _earnEnabled,
        onChanged: _testMode
            ? null
            : (value) {
                if (value && !_productionReady) {
                  _snack(
                    'Önce gerçek ortam, enabled yayın modu ve SSV hazırlığını tamamlayın.',
                    error: true,
                  );
                  return;
                }
                setState(() => _earnEnabled = value);
              },
      ),
      _settingSwitch(
        title: 'Uygun dijital ürünlerde puan harcama',
        subtitle:
            '100 puan = 1 TL gibi belirlediğiniz oran checkout’ta uygulanır.',
        value: _spendEnabled,
        onChanged: (value) => setState(() => _spendEnabled = value),
      ),
      _settingSwitch(
        title: 'Ürün puan uygunluğu kontrolü',
        subtitle:
            'Yalnız adminin uygun işaretlediği dijital ürünlerde puan kullanılır.',
        value: _eligibleProductsEnabled,
        onChanged: (value) => setState(() => _eligibleProductsEnabled = value),
      ),
      _settingSwitch(
        title: 'Admin raporlaması',
        subtitle:
            'Kazanım, son olay ve en çok kazananlar metriklerini gösterir.',
        value: _adminReportingEnabled,
        onChanged: (value) => setState(() => _adminReportingEnabled = value),
      ),
    ]);
  }

  Widget _saveCard() {
    return Card(
      color: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: 0.35),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Değişiklikleri Kaydet',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            const Text(
              'Güvenlik denetimi için bu işlem audit kaydına gerekçesiyle yazılır.',
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _reasonController,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Değişiklik gerekçesi (en az 8 karakter)',
                hintText:
                    'Örn. AdMob üretim birimleri ve puan oranı güncellendi',
                border: OutlineInputBorder(),
                filled: true,
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.save_rounded),
                label: Text(
                  _saving ? 'Kaydediliyor...' : 'Tüm Ayarları Kaydet',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _settingSwitch({
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool>? onChanged,
  }) {
    return SwitchListTile.adaptive(
      contentPadding: EdgeInsets.zero,
      title: Text(title),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _idField(
    TextEditingController controller,
    String label,
    String hint, {
    bool enabled = true,
  }) {
    return TextField(
      controller: controller,
      enabled: enabled,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
        helperText: enabled
            ? null
            : 'Test modunda Google test birimi kullanılır',
      ),
    );
  }

  Widget _readinessCard() {
    final lastCallback = _overview == null || _overview!.recent.isEmpty
        ? 'Henüz görünür doğrulanmış callback yok'
        : DateFormat(
            'dd.MM.yyyy HH:mm',
          ).format(_overview!.recent.first.creditedAt ?? DateTime.now());
    return Card(
      color: (_productionReady ? Colors.green : Colors.orange).shade50,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _productionReady
                  ? 'SSV production-readiness: hazır'
                  : 'SSV production-readiness: kapalı / eksik',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              'Şema: ${_settings?.rewardPointsSchemaReady == true ? 'hazır' : 'hazır değil'}',
            ),
            Text(
              'SSV zorunlu: ${_settings?.rewardPointsSsvRequired == true ? 'evet' : 'hayır'}',
            ),
            Text('Test modu: ${_testMode ? 'açık' : 'kapalı'}'),
            Text(
              'Eski TL kredi yolu: ${_settings?.legacyAdTlGrantDisabled == true ? 'kapalı' : 'AÇIK'}',
            ),
            Text('Son doğrulanmış olay: $lastCallback'),
            const Text(
              'Allowlist/anahtar erişimi istemciye açılmaz; gerçek readiness backend deploy doğrulaması gerektirir.',
              style: TextStyle(fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }

  Widget _connectionStatusCard() {
    final config = _overview?.config;
    final productionUnitAndroid =
        AdSettings.productionRewardedUnitIdAndroid.isNotEmpty
        ? AdSettings.productionRewardedUnitIdAndroid
        : null;
    final productionUnitIos = AdSettings.productionRewardedUnitIdIos.isNotEmpty
        ? AdSettings.productionRewardedUnitIdIos
        : null;
    return _section('AdMob / SSV Bağlantı Durumu', [
      _infoRow('Test modu', _testMode ? 'açık' : 'kapalı'),
      _infoRow(
        'App ID (Android)',
        config?.admobAppIdAndroid ?? 'yok (native manifest)',
      ),
      _infoRow('App ID (iOS)', config?.admobAppIdIos ?? 'yok (native plist)'),
      _infoRow(
        'Rewarded Unit (Android)',
        config?.admobRewardedUnitIdAndroid ??
            productionUnitAndroid ??
            'yok (dart-define)',
      ),
      _infoRow(
        'Rewarded Unit (iOS)',
        config?.admobRewardedUnitIdIos ??
            productionUnitIos ??
            'yok (dart-define)',
      ),
      _infoRow(
        'Politika versiyonu',
        '${config?.rewardPolicyVersion ?? _settings?.rewardPolicyVersion ?? 0}',
      ),
      _infoRow(
        'Fraud hash retansiyonu (gün)',
        '${config?.fraudHashRetentionDays ?? 0}',
      ),
      const SizedBox(height: 8),
      const Text(
        'AdMob App ID ve rewarded unit ID\'leri native build config / dart-define '
        've Edge Function Secrets üzerinden yönetilir. Burada yalnızız okunabilir '
        'durum gösterilir; anahtarlar uygulamaya açılmaz.',
        style: TextStyle(fontSize: 11),
      ),
    ]);
  }

  Widget _todayCard() {
    final today = _overview?.today;
    if (today == null) {
      return _section('Bugünkü Kazanımlar', const [Text('Rapor yüklenemedi.')]);
    }
    final budgetPct = (today.budgetUsedFraction * 100).toStringAsFixed(1);
    return _section('Bugünkü Kazanımlar', [
      Row(
        children: [
          Expanded(
            child: _metricTile(
              'Verilen puan',
              '${today.grantedPoints}',
              Icons.stars_rounded,
              Colors.amber,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _metricTile(
              'İzleme',
              '${today.grantCount}',
              Icons.play_circle_rounded,
              Colors.blue,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _metricTile(
              'Kullanıcı',
              '${today.distinctUsers}',
              Icons.people_rounded,
              Colors.green,
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
      _infoRow(
        'Günlük bütçe kullanımı',
        '${today.grantedPoints} / ${today.maxDailyRewardPoints} puan (%$budgetPct)',
      ),
      _infoRow('Kalan günlük bütçe', '${today.remainingPoints} puan'),
    ]);
  }

  Widget _recentEventsCard() {
    if (_loadingOverview) {
      return _section('Son Doğrulanmış Puan Olayları', const [
        Center(child: CircularProgressIndicator()),
      ]);
    }
    final events = _overview?.recent ?? const <AdminRewardRecentSession>[];
    return _section('Son Doğrulanmış Puan Olayları', [
      if (events.isEmpty)
        const Text('Henüz doğrulanmış puan olayı yok.')
      else
        ...events.map(
          (event) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.verified, color: Colors.green),
            title: Text(
              event.creditedPoints == null
                  ? event.fullName ?? 'Kullanıcı'
                  : '+${event.creditedPoints} puan — ${event.fullName ?? 'Kullanıcı'}',
            ),
            subtitle: Text(
              '${event.email ?? '-'} · '
              '${event.creditedAt == null ? '-' : DateFormat('dd.MM.yyyy HH:mm').format(event.creditedAt!)}',
            ),
            trailing: Text(event.status),
          ),
        ),
    ]);
  }

  Widget _topEarnersCard() {
    if (_loadingOverview) {
      return _section('En Çok Puan Kazananlar', const [
        Center(child: CircularProgressIndicator()),
      ]);
    }
    final earners = _overview?.topEarners ?? const <AdminRewardTopEarner>[];
    return _section('En Çok Puan Kazananlar', [
      if (earners.isEmpty)
        const Text('Henüz puan kazanan yok.')
      else
        ...earners.asMap().entries.map((entry) {
          final index = entry.key;
          final earner = entry.value;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundColor: Colors.amber.shade100,
              child: Text('${index + 1}'),
            ),
            title: Text(earner.fullName ?? 'Kullanıcı'),
            subtitle: Text(
              '${earner.email ?? '-'} · ${earner.sessionCount} izleme',
            ),
            trailing: Text(
              '${earner.totalPoints} puan',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          );
        }),
    ]);
  }

  Widget _metricTile(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          Text(
            label,
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
        ],
      ),
    );
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: TextStyle(color: Colors.grey.shade700)),
          ),
          Expanded(
            flex: 3,
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  Widget _integerField(
    TextEditingController controller,
    String label, {
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: controller,
      onChanged: onChanged,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
    );
  }
}
