// ignore_for_file: curly_braces_in_flow_control_structures

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../features/wallet/screens/topup_screen.dart';
import '../models/ilan_models.dart';
import '../services/ilan_service.dart';
import '../utils/ilan_category_selection.dart';
import '../utils/ilan_ui.dart';

class IlanFormScreen extends StatefulWidget {
  const IlanFormScreen({super.key, this.initialCategory});
  final IlanCategory? initialCategory;

  @override
  State<IlanFormScreen> createState() => _IlanFormScreenState();
}

class _IlanFormScreenState extends State<IlanFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _service = IlanService();
  final _title = TextEditingController();
  final _description = TextEditingController();
  final _price = TextEditingController();
  final _neighborhood = TextEditingController();
  final _phone = TextEditingController();
  List<IlanCategory> _categories = const [];
  List<Uint8List> _images = const [];
  int _maxImages = 8;
  IlanSettings? _settings;
  IlanCategory? _category;
  String? _condition;
  String _contactPreference = 'app';
  bool _negotiable = false;
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _category = widget.initialCategory;
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    _price.dispose();
    _neighborhood.dispose();
    _phone.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (Supabase.instance.client.auth.currentUser == null) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('İlan vermek için giriş yapmalısınız.')),
        );
      }
      return;
    }
    try {
      final values = await Future.wait([
        _service.getSettings(),
        _service.getCategories(),
      ]);
      final settings = values[0] as IlanSettings;
      final categories = values[1] as List<IlanCategory>;
      if (!settings.isEnabled || !settings.allowUserCreate)
        throw StateError('Kullanıcı ilan paylaşımı şu anda kapalı');
      if (!mounted) return;
      // initialCategory başka bir sorgudan üretildiği için listedeki nesneyle
      // aynı kimliğe (id) sahip olsa da Dart nesne eşitliği sağlanmayabilir.
      // Dropdown değerini her zaman kendi items listesindeki örnekle eşleştir.
      final uniqueCategories = uniqueIlanCategoriesById(categories);
      final selectedCategory = resolveIlanCategorySelection(
        uniqueCategories,
        _category?.id,
      );
      setState(() {
        _categories = uniqueCategories;
        _maxImages = settings.maxImagesPerIlan;
        _settings = settings;
        _category = selectedCategory;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(IlanUi.friendlyError(error))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Yeni İlan Ver')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  _sectionTitle('Kategori', Icons.category_outlined),
                  // Dropdown degeri model nesnesi degil kalici kategori ID'si
                  // olmalidir. API'den ayni kategori yeni bir IlanCategory
                  // ornegi olarak geldiginde nesne kimligi degisir ve Flutter
                  // items icinde tam bir eslesme bulamayarak assertion verir.
                  DropdownButtonFormField<String>(
                    initialValue: validIlanCategoryDropdownValue(
                      _categories,
                      _category?.id,
                    ),
                    decoration: _decoration('İlan kategorisi'),
                    items: _categories
                        .map(
                          (item) => DropdownMenuItem(
                            value: item.id,
                            child: Text(
                              item.isPaidToPublish
                                  ? '${item.name} (${IlanUi.formatFee(item.publishFee)})'
                                  : item.name,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (categoryId) => setState(() {
                      _category = _categories
                          .where((category) => category.id == categoryId)
                          .firstOrNull;
                      _condition = null;
                      if (_category?.allowsPrice == false) {
                        _price.clear();
                        _negotiable = false;
                      }
                    }),
                    validator: (value) =>
                        value == null ? 'Kategori seçiniz' : null,
                  ),
                  if (_category?.pricingMode == IlanPricingMode.forbidden)
                    _notice(
                      'Bu kategoride fiyat bilgisi kullanılmaz. Kayıp ilanları tamamen ücretsizdir.',
                      Colors.red,
                    ),
                  if (_category?.isPaidToPublish == true)
                    _notice(
                      'Bu kategoride ilan yayınlamak ${IlanUi.formatFee(_category!.publishFee)}. '
                      'Gönderdiğinizde bakiyenizden düşülecektir.',
                      Colors.orange,
                    ),
                  const SizedBox(height: 20),
                  _sectionTitle('İlan Bilgileri', Icons.description_outlined),
                  TextFormField(
                    controller: _title,
                    maxLength: 120,
                    decoration: _decoration(
                      'Başlık',
                      hint: 'Kısa ve açıklayıcı bir başlık',
                    ),
                    validator: (value) => (value?.trim().length ?? 0) < 5
                        ? 'Başlık en az 5 karakter olmalıdır'
                        : null,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _description,
                    minLines: 5,
                    maxLines: 10,
                    maxLength: 5000,
                    decoration: _decoration(
                      'Açıklama',
                      hint: 'İlanınızın tüm önemli ayrıntılarını yazın',
                    ),
                    validator: (value) => (value?.trim().length ?? 0) < 20
                        ? 'Açıklama en az 20 karakter olmalıdır'
                        : null,
                  ),
                  if (_category?.allowedConditions.isNotEmpty == true) ...[
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _condition,
                      decoration: _decoration('Ürün durumu'),
                      items: _category!.allowedConditions
                          .map(
                            (item) => DropdownMenuItem(
                              value: item,
                              child: Text(item),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _condition = value),
                      validator: (value) =>
                          value == null ? 'Ürün durumunu seçiniz' : null,
                    ),
                  ],
                  if (_category?.allowsPrice == true) ...[
                    const SizedBox(height: 20),
                    _sectionTitle('Fiyat', Icons.payments_outlined),
                    TextFormField(
                      controller: _price,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: _decoration(
                        _category!.requiresPrice
                            ? 'Fiyat (zorunlu)'
                            : 'Fiyat (isteğe bağlı)',
                        suffix: '₺',
                      ),
                      validator: (value) {
                        if (!_category!.requiresPrice &&
                            (value == null || value.trim().isEmpty))
                          return null;
                        final parsed = double.tryParse(
                          (value ?? '').replaceAll(',', '.'),
                        );
                        return parsed == null || parsed <= 0
                            ? 'Geçerli bir fiyat giriniz'
                            : null;
                      },
                    ),
                    CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _negotiable,
                      title: const Text('Pazarlık payı var'),
                      onChanged: (value) =>
                          setState(() => _negotiable = value ?? false),
                    ),
                  ],
                  const SizedBox(height: 20),
                  _sectionTitle('Fotoğraflar', Icons.photo_library_outlined),
                  _imagePicker(context),
                  const SizedBox(height: 20),
                  _sectionTitle(
                    'Konum ve İletişim',
                    Icons.location_on_outlined,
                  ),
                  TextFormField(
                    controller: _neighborhood,
                    maxLength: 120,
                    decoration: _decoration('Mahalle (isteğe bağlı)'),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: _contactPreference,
                    decoration: _decoration('İletişim tercihi'),
                    items: const [
                      DropdownMenuItem(
                        value: 'app',
                        child: Text('Uygulama içi mesaj'),
                      ),
                      DropdownMenuItem(value: 'phone', child: Text('WhatsApp')),
                      DropdownMenuItem(
                        value: 'both',
                        child: Text('Mesaj veya WhatsApp'),
                      ),
                    ],
                    onChanged: (value) =>
                        setState(() => _contactPreference = value ?? 'app'),
                  ),
                  if (_contactPreference != 'app') ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _phone,
                      keyboardType: TextInputType.phone,
                      decoration: _decoration('WhatsApp numarası'),
                      validator: (value) =>
                          (value?.replaceAll(RegExp(r'\D'), '').length ?? 0) <
                              10
                          ? 'Geçerli bir telefon numarası giriniz'
                          : null,
                    ),
                  ],
                  _notice(
                    'Güvenliğiniz için kapora göndermeyin, hassas kişisel bilgilerinizi paylaşmayın.',
                    Colors.orange,
                  ),
                  const SizedBox(height: 18),
                  FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(_submitLabel()),
                    style: FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  Widget _imagePicker(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    return SizedBox(
      height: 112,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: [
          InkWell(
            onTap: _pickImages,
            borderRadius: BorderRadius.circular(14),
            child: Container(
              width: 104,
              decoration: BoxDecoration(
                border: Border.all(
                  color: primary.withValues(alpha: .35),
                  width: 1.5,
                ),
                borderRadius: BorderRadius.circular(14),
                color: primary.withValues(alpha: .06),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_a_photo_outlined, color: primary),
                  const SizedBox(height: 6),
                  const Text(
                    'Fotoğraf Ekle',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
          ),
          ..._images.indexed.map(
            (entry) => Stack(
              children: [
                Container(
                  width: 104,
                  margin: const EdgeInsets.only(left: 10),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Image.memory(entry.$2, fit: BoxFit.cover),
                ),
                Positioned(
                  right: 3,
                  top: 3,
                  child: IconButton.filledTonal(
                    onPressed: () => setState(
                      () => _images = [..._images]..removeAt(entry.$1),
                    ),
                    icon: const Icon(Icons.close, size: 16),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImages() async {
    final picked = await ImagePicker().pickMultiImage(
      imageQuality: 82,
      maxWidth: 1800,
    );
    if (picked.isEmpty) return;
    final remaining = _maxImages - _images.length;
    if (remaining <= 0) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('En fazla $_maxImages fotoğraf ekleyebilirsiniz.'),
          ),
        );
      }
      return;
    }
    final bytes = await Future.wait(
      picked.take(remaining).map((image) => image.readAsBytes()),
    );
    if (mounted) setState(() => _images = [..._images, ...bytes]);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate() || _category == null) return;
    setState(() => _saving = true);
    try {
      final priceText = _price.text.trim().replaceAll(',', '.');
      await _service.createIlan({
        'category_id': _category!.id,
        'title': _title.text.trim(),
        'description': _description.text.trim(),
        'price': _category!.allowsPrice && priceText.isNotEmpty
            ? double.parse(priceText)
            : null,
        'currency': _category!.allowsPrice && priceText.isNotEmpty
            ? 'TRY'
            : null,
        'is_negotiable': _category!.allowsPrice && _negotiable,
        'item_condition': _condition,
        'city': 'Şırnak',
        'district': 'Cizre',
        'neighborhood': _neighborhood.text.trim().isEmpty
            ? null
            : _neighborhood.text.trim(),
        'contact_preference': _contactPreference,
        'contact_phone': _contactPreference == 'app'
            ? null
            : _phone.text.trim(),
      }, _images);
      if (!mounted) return;
      final fee = _category?.publishFee ?? 0;
      final baseMessage = (_settings?.requireApproval ?? true)
          ? 'İlanınız onaya gönderildi.'
          : 'İlanınız yayınlandı!';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            fee > 0
                ? '$baseMessage ${IlanUi.formatFee(fee)} bakiyenizden düşüldü.'
                : baseMessage,
          ),
        ),
      );
      Navigator.pop(context, true);
    } catch (error) {
      if (mounted) {
        final insufficientBalance = error.toString().contains(
          'Yetersiz bakiye',
        );
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(IlanUi.friendlyError(error)),
            action: insufficientBalance
                ? SnackBarAction(
                    label: 'Bakiye Yükle',
                    onPressed: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const TopupScreen()),
                    ),
                  )
                : null,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  String _submitLabel() {
    if (_saving) return 'Gönderiliyor...';
    final fee = _category?.publishFee ?? 0;
    final requiresApproval = _settings?.requireApproval ?? true;
    if (fee > 0) {
      return '${IlanUi.formatFee(fee)} Öde ve ${requiresApproval ? 'Onaya Gönder' : 'Yayınla'}';
    }
    return requiresApproval ? 'İlanı Onaya Gönder' : 'İlanı Yayınla';
  }

  Widget _sectionTitle(String text, IconData icon) => Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: Row(
      children: [
        Icon(icon, size: 20, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 7),
        Text(
          text,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
        ),
      ],
    ),
  );

  InputDecoration _decoration(String label, {String? hint, String? suffix}) =>
      InputDecoration(
        labelText: label,
        hintText: hint,
        suffixText: suffix,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
      );

  Widget _notice(String text, Color color) => Container(
    margin: const EdgeInsets.only(top: 12),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: color.withValues(alpha: .08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: color.withValues(alpha: .25)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.info_outline, size: 19, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 12, color: color.withValues(alpha: .9)),
          ),
        ),
      ],
    ),
  );
}
