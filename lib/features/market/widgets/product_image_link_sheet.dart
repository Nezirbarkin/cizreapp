import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/product_image_scrape_service.dart';

/// "Linkten görsel ekle" alt sayfasını açar.
///
/// Kullanıcı bir ürün sayfası (ya da doğrudan görsel) linki yapıştırır; sayfa
/// sunucuda kazınıp ana görsel getirilir, önizlenir ve onaylanırsa döner.
/// İptal edilirse `null` döner. [accent] verilmezse temanın ana rengi kullanılır
/// (admin ekranları kendi marka rengini geçirir).
Future<ScrapedProductImage?> showProductImageLinkSheet(
  BuildContext context, {
  Color? accent,
  ProductImageScrapeService? service,
}) {
  return showModalBottomSheet<ScrapedProductImage>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    constraints: const BoxConstraints(maxWidth: 560),
    builder: (_) => ProductImageLinkSheet(
      accent: accent ?? Theme.of(context).colorScheme.primary,
      service: service ?? ProductImageScrapeService(),
    ),
  );
}

class ProductImageLinkSheet extends StatefulWidget {
  const ProductImageLinkSheet({
    super.key,
    required this.accent,
    required this.service,
  });

  final Color accent;
  final ProductImageScrapeService service;

  @override
  State<ProductImageLinkSheet> createState() => _ProductImageLinkSheetState();
}

class _ProductImageLinkSheetState extends State<ProductImageLinkSheet> {
  final TextEditingController _link = TextEditingController();

  bool _loading = false;
  String? _error;
  ScrapedProductImage? _result;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      final text = data?.text?.trim();
      if (text == null || text.isEmpty || !mounted) return;
      setState(() {
        _link.text = text;
        _link.selection = TextSelection.collapsed(offset: text.length);
        _error = null;
      });
    } catch (_) {
      // Pano erişimi reddedildiyse kullanıcı elle yapıştırabilir.
    }
  }

  Future<void> _fetch() async {
    if (_loading) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _loading = true;
      _error = null;
      _result = null;
    });
    try {
      final result = await widget.service.fetchFromLink(_link.text);
      if (!mounted) return;
      setState(() {
        _result = result;
        _loading = false;
      });
    } on ProductImageScrapeException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = 'Görsel alınamadı; biraz sonra tekrar deneyin';
        _loading = false;
      });
    }
  }

  void _reset() {
    setState(() {
      _result = null;
      _error = null;
      _link.clear();
    });
  }

  String _sizeLabel(int bytes) => bytes >= 1024 * 1024
      ? '${(bytes / (1024 * 1024)).toStringAsFixed(1).replaceAll('.', ',')} MB'
      : '${(bytes / 1024).round()} KB';

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;
    return AnimatedPadding(
      duration: const Duration(milliseconds: 100),
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Material(
        color: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(
            20,
            10,
            20,
            16 + MediaQuery.paddingOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(Icons.link_rounded, color: accent),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Linkten Görsel Ekle',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        Text(
                          'Ürün sayfasının linkini yapıştır, ana görseli otomatik alınır',
                          style: TextStyle(fontSize: 12.5, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Kapat',
                    icon: const Icon(Icons.close_rounded),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _link,
                enabled: !_loading && _result == null,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.go,
                autocorrect: false,
                enableSuggestions: false,
                onSubmitted: (_) => _fetch(),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                decoration: InputDecoration(
                  labelText: 'Ürün linki',
                  hintText: 'https://ornek.com/urun/kirmizi-domates',
                  prefixIcon: const Icon(Icons.link_rounded),
                  suffixIcon: _result == null
                      ? TextButton(
                          onPressed: _loading ? null : _paste,
                          child: const Text('Yapıştır'),
                        )
                      : null,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: accent, width: 1.5),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.error_outline_rounded,
                        size: 18,
                        color: Colors.red.shade700,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.red.shade800,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              if (_result != null) ...[
                const SizedBox(height: 14),
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    height: 220,
                    color: const Color(0xFFEDEEF3),
                    alignment: Alignment.center,
                    child: Image.memory(
                      _result!.bytes,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image_outlined,
                        color: Colors.grey,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                if (_result!.title != null)
                  Text(
                    _result!.title!,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                Text(
                  '${_result!.extension.toUpperCase()} · ${_sizeLabel(_result!.bytes.length)}',
                  style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                ),
              ],
              const SizedBox(height: 14),
              if (_result == null)
                FilledButton(
                  onPressed: _loading ? null : _fetch,
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    minimumSize: const Size.fromHeight(50),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Görseli Getir',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                )
              else
                Row(
                  children: [
                    OutlinedButton(
                      onPressed: _reset,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: const Text('Başka link'),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.pop(context, _result),
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          minimumSize: const Size.fromHeight(50),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        child: const Text(
                          'Bu görseli kullan',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              const SizedBox(height: 10),
              const Text(
                'Yalnızca kullanım hakkına sahip olduğunuz görselleri ekleyin. '
                'Bazı siteler otomatik erişimi engeller; o durumda görseli '
                'galeriden yükleyebilirsiniz.',
                style: TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
