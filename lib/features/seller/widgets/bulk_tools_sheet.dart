import 'package:flutter/material.dart';

import '../../../core/models/product_model.dart';
import '../screens/bulk_digital_import_screen.dart';
import '../screens/bulk_product_upload_screen.dart';
import '../services/bulk_product_service.dart';

/// Ürünlerim'deki "Toplu işlemler" sayfası: Excel'den yükleme, SMM
/// servislerinden dijital ürün, dışa aktarma ve boş şablon.
///
/// Ürün eklendi/güncellendiyse `true` döner (liste yenilensin).
Future<bool> showBulkToolsSheet(
  BuildContext context, {
  required List<Product> products,
  BulkProductService? service,
}) async {
  final choice = await showModalBottomSheet<_BulkTool>(
    context: context,
    useSafeArea: true,
    showDragHandle: true,
    constraints: const BoxConstraints(maxWidth: 640),
    builder: (context) => _BulkToolsSheet(exportable: products.where((p) => !p.isDigital).length),
  );
  if (choice == null || !context.mounted) return false;

  final bulk = service ?? BulkProductService();
  switch (choice) {
    case _BulkTool.upload:
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => BulkProductUploadScreen(service: bulk)),
      );
      return changed == true;
    case _BulkTool.digital:
      final changed = await Navigator.of(context).push<bool>(
        MaterialPageRoute(builder: (_) => BulkDigitalImportScreen(service: bulk)),
      );
      return changed == true;
    case _BulkTool.export:
      await _shareSafely(context, () => bulk.shareSpreadsheet(bulk.buildExport(products), _exportName()));
      return false;
    case _BulkTool.template:
      await _shareSafely(
        context,
        () => bulk.shareSpreadsheet(bulk.buildTemplate(), 'toplu_urun_sablonu.xlsx'),
      );
      return false;
  }
}

String _exportName() {
  final d = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return 'urunlerim_${d.year}${two(d.month)}${two(d.day)}.xlsx';
}

Future<void> _shareSafely(BuildContext context, Future<void> Function() share) async {
  try {
    await share();
  } catch (e) {
    debugPrint('Toplu işlem dosyası paylaşılamadı: $e');
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Dosya paylaşılamadı')));
    }
  }
}

enum _BulkTool { upload, digital, export, template }

class _BulkToolsSheet extends StatelessWidget {
  const _BulkToolsSheet({required this.exportable});

  final int exportable;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text('Toplu işlemler', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          ),
          _tile(
            context,
            tool: _BulkTool.upload,
            icon: Icons.table_view_rounded,
            color: const Color(0xFF16A34A),
            title: 'Excel ile toplu ürün yükle',
            subtitle: 'Excel/CSV dosyasından ürün ekle ya da fiyat-stok güncelle',
          ),
          _tile(
            context,
            tool: _BulkTool.digital,
            icon: Icons.bolt_rounded,
            color: const Color(0xFF7C3AED),
            title: 'Toplu dijital ürün (SMM)',
            subtitle: 'Sağlayıcı servislerini seçip tek seferde ürüne çevir',
          ),
          if (exportable > 0)
            _tile(
              context,
              tool: _BulkTool.export,
              icon: Icons.ios_share_rounded,
              color: const Color(0xFF2563EB),
              title: 'Ürünlerimi Excel\'e aktar',
              subtitle: '$exportable ürün · düzenleyip geri yükleyerek toplu güncelle',
            ),
          _tile(
            context,
            tool: _BulkTool.template,
            icon: Icons.description_outlined,
            color: const Color(0xFF64748B),
            title: 'Boş şablonu indir',
            subtitle: 'Sütunları hazır Excel dosyası',
          ),
        ],
      ),
    );
  }

  Widget _tile(
    BuildContext context, {
    required _BulkTool tool,
    required IconData icon,
    required Color color,
    required String title,
    required String subtitle,
  }) {
    return ListTile(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      leading: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: color),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(subtitle),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.of(context).pop(tool),
    );
  }
}
