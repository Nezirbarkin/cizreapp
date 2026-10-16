import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cizreapp/core/models/product_model.dart';
import 'package:cizreapp/features/seller/models/bulk_product_draft.dart';
import 'package:cizreapp/features/seller/services/bulk_product_service.dart';
import 'package:cizreapp/features/seller/utils/spreadsheet_io.dart';
import 'package:flutter_test/flutter_test.dart';

Product _product({
  required String id,
  required String name,
  double price = 10,
  double? oldPrice,
  int stock = 5,
  String? category,
  String? imageUrl,
  String type = 'normal',
}) {
  final now = DateTime(2026, 10, 15);
  return Product(
    id: id,
    shopId: 'shop',
    name: name,
    price: price,
    oldPrice: oldPrice,
    stockQuantity: stock,
    category: category,
    imageUrl: imageUrl,
    isAvailable: true,
    createdAt: now,
    updatedAt: now,
    productType: type,
  );
}

BulkImportPlan _plan(
  String text, {
  List<Product> existing = const [],
  List<String> categories = const [],
  void Function(BulkImportPlan p)? setup,
}) {
  final table = SpreadsheetIO.parseText(text);
  final mapping = BulkSheetMapping.detect(table.rows)!;
  final plan = BulkImportPlan.fromTable(
    rows: table.rows,
    mapping: mapping,
    numbersCanonical: table.numbersCanonical,
    existingProducts: existing,
    shopCategories: categories,
  );
  if (setup != null) {
    setup(plan);
    plan.resolve();
  }
  return plan;
}

void main() {
  group('SpreadsheetIO metin', () {
    test('Türkçe Excel CSV: noktalı virgül, tırnak, satır içi satır sonu', () {
      final t = SpreadsheetIO.parseText(
        'Ürün Adı;Fiyat;Açıklama\r\n'
        'Domates;"12,50";"Taze; günlük"\r\n'
        '"Uzun ""özel"" ad";3;"iki\nsatır"\r\n'
        '\r\n',
      );
      expect(t.rows, [
        ['Ürün Adı', 'Fiyat', 'Açıklama'],
        ['Domates', '12,50', 'Taze; günlük'],
        ['Uzun "özel" ad', '3', 'iki\nsatır'],
      ]);
      expect(t.numbersCanonical, isFalse);
    });

    test('ayırıcı: virgüllü ad ve ondalık virgül noktalı virgülü bozmaz', () {
      final t = SpreadsheetIO.parseText('Liste\nAd;Fiyat\nElma, kırmızı;12,50\nArmut;3\n');
      expect(t.rows, [
        ['Liste'],
        ['Ad', 'Fiyat'],
        ['Elma, kırmızı', '12,50'],
        ['Armut', '3'],
      ]);
      expect(SpreadsheetIO.parseText('Ad,Fiyat\nElma,3\n').rows.last, ['Elma', '3']);
    });

    test('Excel\'den yapıştırma (sekmeli) virgülü ayırıcı saymaz', () {
      final t = SpreadsheetIO.parseText('Ad\tFiyat\nElma, kırmızı\t1,5\n');
      expect(t.rows[1], ['Elma, kırmızı', '1,5']);
    });

    test('Windows-1254 (ANSI) Türkçe harfler', () {
      // "Şeker;Iğdır;ı" — 1254 baytları
      final bytes = Uint8List.fromList([0xDE, 0x65, 0x6B, 0x65, 0x72, 0x3B, 0x49, 0xF0, 0x64, 0xFD, 0x72, 0x3B, 0xFD]);
      expect(SpreadsheetIO.readBytes(bytes).rows.single, ['Şeker', 'Iğdır', 'ı']);
    });

    test('UTF-8 BOM ve UTF-16 LE (Excel "Unicode metin")', () {
      final bom = Uint8List.fromList([0xEF, 0xBB, 0xBF, ...utf8.encode('Ad;Stok\nÇay;4')]);
      expect(SpreadsheetIO.readBytes(bom).rows, [
        ['Ad', 'Stok'],
        ['Çay', '4'],
      ]);

      final units = 'Ad\tStok\r\nŞal\t2'.codeUnits;
      final le = Uint8List.fromList([0xFF, 0xFE, for (final u in units) ...[u & 0xFF, u >> 8]]);
      expect(SpreadsheetIO.readBytes(le).rows.last, ['Şal', '2']);
    });

    test('eski .xls açık bir hata verir', () {
      final ole = Uint8List.fromList([0xD0, 0xCF, 0x11, 0xE0, 0xA1, 0xB1, 0x1A, 0xE1, 0, 0]);
      expect(
        () => SpreadsheetIO.readBytes(ole, fileName: 'urunler.xls'),
        throwsA(isA<SpreadsheetReadException>()),
      );
    });
  });

  group('SpreadsheetIO xlsx', () {
    test('yazılan xlsx geri okunur; sayılar kanonik', () {
      final bytes = SpreadsheetIO.buildXlsx([
        const SpreadsheetSheet(
          name: 'Ürünler',
          rows: [
            ['Ürün Adı *', 'Fiyat *', 'Stok *', 'Not'],
            ['Süt <1 L> & "tam"', 34.9, 12, null],
            ['Yumurta', 1.125, 0, 'x'],
          ],
        ),
        const SpreadsheetSheet(name: 'Açıklama', rows: [
          ['b'],
        ]),
      ]);
      final t = SpreadsheetIO.readBytes(bytes);
      expect(t.numbersCanonical, isTrue);
      expect(t.rows, [
        ['Ürün Adı *', 'Fiyat *', 'Stok *', 'Not'],
        ['Süt <1 L> & "tam"', '34.9', '12'],
        ['Yumurta', '1.125', '0', 'x'],
      ]);
      // Kanonik sayı binlik ayırıcı sayılmaz: 1.125 TL, 1125 TL değil.
      expect(BulkValues.parseNumber('1.125', canonical: true), 1.125);
    });

    test('Excel\'in yazdığı paylaşılan metin + boş hücre + kayan nokta gürültüsü', () {
      String x(String s) => s;
      final archive = Archive()
        ..addFile(ArchiveFile.string('xl/workbook.xml', x(
          '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
          'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
          '<sheets><sheet name="Liste" sheetId="1" r:id="rId7"/></sheets></workbook>',
        )))
        ..addFile(ArchiveFile.string('xl/_rels/workbook.xml.rels', x(
          '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId7" Type="x" Target="worksheets/sheet3.xml"/></Relationships>',
        )))
        ..addFile(ArchiveFile.string('xl/sharedStrings.xml', x(
          '<sst xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
          '<si><t>Ad</t></si><si><t>Fiyat</t></si>'
          '<si><r><t>Kır</t></r><r><t xml:space="preserve">mızı Elma</t></r><rPh><t>x</t></rPh></si>'
          '</sst>',
        )))
        ..addFile(ArchiveFile.string('xl/worksheets/sheet3.xml', x(
          '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>'
          '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="C1" t="s"><v>1</v></c></row>'
          '<row r="3"><c r="A3" t="s"><v>2</v></c><c r="C3"><v>12.499999999999998</v></c>'
          '<c r="D3" t="b"><v>1</v></c></row>'
          '</sheetData></worksheet>',
        )));
      final bytes = ZipEncoder().encodeBytes(archive);
      expect(SpreadsheetIO.readBytes(bytes).rows, [
        ['Ad', '', 'Fiyat'],
        <String>[],
        ['Kırmızı Elma', '', '12.5', 'evet'],
      ]);
    });

    test('şablon ve dışa aktarma kendi başlıklarını tanır', () {
      final service = BulkProductService();
      final template = SpreadsheetIO.readBytes(service.buildTemplate());
      final mapping = BulkSheetMapping.detect(template.rows)!;
      expect(mapping.columns.keys.toSet(), BulkProductService.templateFields.toSet());
      expect(mapping.unknownHeaders, isEmpty);

      final export = SpreadsheetIO.readBytes(service.buildExport([
        _product(id: 'p1', name: 'Çay 1 kg', price: 89.9, oldPrice: 99.9, stock: 7, category: 'Market'),
        _product(id: 'd1', name: 'Takipçi', type: 'digital'),
      ]));
      expect(export.rows.length, 2, reason: 'dijital ürün dışa aktarılmaz');
      final plan = BulkImportPlan.fromTable(
        rows: export.rows,
        mapping: BulkSheetMapping.detect(export.rows)!,
        numbersCanonical: export.numbersCanonical,
        existingProducts: [
          _product(id: 'p1', name: 'Çay 1 kg', price: 89.9, oldPrice: 99.9, stock: 7, category: 'Market'),
        ],
        shopCategories: const ['Market'],
      );
      expect(plan.drafts.single.action, BulkRowAction.unchanged,
          reason: 'değiştirilmeden geri yüklenen dosya hiçbir şeyi güncellememeli');
    });
  });

  group('BulkValues', () {
    test('sayılar', () {
      expect(BulkValues.parseNumber('12,50'), 12.5);
      expect(BulkValues.parseNumber('1.234,50'), 1234.5);
      expect(BulkValues.parseNumber('1,234.50'), 1234.5);
      expect(BulkValues.parseNumber('1.250'), 1250);
      expect(BulkValues.parseNumber('12.5'), 12.5);
      expect(BulkValues.parseNumber('₺ 99'), 99);
      expect(BulkValues.parseNumber('99 TL'), 99);
      expect(BulkValues.parseNumber('abc'), isNull);
      expect(BulkValues.parseInt('10,0'), 10);
      expect(BulkValues.parseInt('10,5'), isNull);
    });

    test('evet/hayır, rozetler, görseller, başlıklar', () {
      expect(BulkValues.parseBool('Evet'), isTrue);
      expect(BulkValues.parseBool('HAYIR'), isFalse);
      expect(BulkValues.parseBool('belki'), isNull);

      final unknown = <String>[];
      expect(BulkValues.parseBadges('Yeni, çok satan; yerli_uretim', unknown: unknown),
          ['yeni', 'cok_satan', 'yerli_uretim']);
      expect(unknown, isEmpty);
      BulkValues.parseBadges('Süper', unknown: unknown);
      expect(unknown, ['Süper']);
      expect(BulkValues.parseBadges('-'), isEmpty);

      expect(BulkValues.splitImageRefs('https://a.com/1.jpg, https://b.com/2.jpg | c.png'),
          ['https://a.com/1.jpg', 'https://b.com/2.jpg', 'c.png']);
      expect(BulkValues.fileKey(r'C:\foto\Salkım Domates.JPG'), 'salkimdomates');

      expect(BulkField.fromHeader('Fiyat (TL) *'), BulkField.price);
      expect(BulkField.fromHeader('STOK ADEDİ'), BulkField.stock);
      expect(BulkField.fromHeader('Ürün Görseli Linki'), isNull);
      expect(BulkField.fromHeader('Görsel Linki'), BulkField.images);
    });
  });

  group('BulkImportPlan', () {
    test('başlık üstte başlık satırı olsa da bulunur; hatalı satırlar işaretlenir', () {
      final plan = _plan(
        'Mağazam ürün listesi\n'
        'Ad;Fiyat;Stok;Eski Fiyat;Rozetler;Bilinmeyen\n'
        'Elma;10;3;;;x\n'
        'Armut;0;1;;;\n'
        'Kiraz;abc;1;;;\n'
        ';5;5;;;\n'
        'Muz;20;2;15;;\n'
        'Erik;5;1,5;;;\n'
        'Nar;5;1;;Uçan;\n',
      );
      expect(plan.mapping.headerRow, 1);
      expect(plan.mapping.unknownHeaders, ['Bilinmeyen']);
      final byName = {for (final d in plan.drafts) d.rowNumber: d};
      expect(byName[3]!.isValid, isTrue);
      expect(byName[4]!.errors.single, contains('0\'dan büyük'));
      expect(byName[5]!.errors.single, contains('sayı değil'));
      expect(byName[6]!.errors.single, 'Ürün adı eksik');
      expect(byName[7]!.errors.single, contains('Eski fiyat'));
      expect(byName[8]!.errors.single, contains('tam sayı'));
      expect(byName[9]!.errors.single, contains('Bilinmeyen rozet'));
      expect(plan.toCreate.length, 1);
      expect(plan.invalidRows.length, 6);
    });

    test('aynı adlı ürün: atla / güncelle / yine de ekle; ürün kodu her zaman günceller', () {
      final existing = [_product(id: 'p1', name: 'Salkım Domates', price: 30, stock: 4)];
      const text = 'Ürün Kodu;Ad;Fiyat;Stok\n;salkim  DOMATES;32;4\np1;;;9\nyok-boyle;;;1\n';

      var plan = _plan(text, existing: existing);
      expect(plan.drafts[0].action, BulkRowAction.skipExisting);
      expect(plan.drafts[1].action, BulkRowAction.update);
      expect(plan.drafts[1].updateDiff(), {'stock': 9});
      expect(plan.drafts[2].errors.first, 'Ürün kodu mağazanda yok');

      plan = _plan(text, existing: existing, setup: (p) => p.duplicatePolicy = BulkDuplicatePolicy.update);
      expect(plan.drafts[0].action, BulkRowAction.update);
      expect(plan.drafts[0].updateDiff(), {'price': 32.0});
      expect(plan.drafts[0].warnings, contains('Aynı adlı ürün güncellenecek'));

      plan = _plan(text, existing: existing, setup: (p) => p.duplicatePolicy = BulkDuplicatePolicy.create);
      expect(plan.drafts[0].action, BulkRowAction.create);
    });

    test('güncellemede boş hücre dokunmaz, eski fiyat 0 temizler, değişmeyen gönderilmez', () {
      final existing = [_product(id: 'p1', name: 'Çay', price: 50, oldPrice: 60, stock: 3)];
      final plan = _plan('Ürün Kodu;Fiyat;Eski Fiyat;Stok\np1;;0;\np1;50;;3\n', existing: existing);
      final first = plan.drafts[0];
      expect(first.action, BulkRowAction.update);
      expect(first.toRpcItem(imageUrls: const [], hideWithoutImage: true), {'id': 'p1', 'old_price': null});
      expect(plan.drafts[1].action, BulkRowAction.unchanged);
      expect(plan.duplicateRows, {3});
    });

    test('görseller: kendi depomuz, dış bağlantı, seçilen dosya (hücrede ya da ürün adında)', () {
      const own = 'https://proje.supabase.co/storage/v1/object/public/';
      final plan = _plan(
        'Ad;Fiyat;Stok;Görsel\n'
        'A ürünü;1;1;${own}shop-images/a.jpg | https://site.com/b.png\n'
        'B ürünü;1;1;b.JPG | eksik.png\n'
        'Salkım Domates;1;1;\n'
        'Görselsiz;1;1;\n',
        setup: (p) {
          p.ownStoragePrefix = own;
          p.pickedFiles['b'] = BulkImage.file('b.jpg', () async => Uint8List(1));
          p.pickedFiles['salkimdomates'] = BulkImage.file('Salkım Domates.png', () async => Uint8List(1));
        },
      );
      final a = plan.drafts[0];
      expect(a.images.map((i) => i.kind), [BulkImageKind.ready, BulkImageKind.remote]);
      final b = plan.drafts[1];
      expect(b.images.single.fileName, 'b.jpg');
      expect(b.warnings, contains('Görsel dosyası seçilmedi: eksik.png'));
      expect(plan.drafts[2].images.single.fileName, 'Salkım Domates.png');

      final none = plan.drafts[3];
      expect(none.images, isEmpty);
      expect(none.warnings, contains('Görsel yok — satışa kapalı eklenecek'));
      expect(none.toRpcItem(imageUrls: const [], hideWithoutImage: true)['is_available'], isFalse);
      expect(none.toRpcItem(imageUrls: const [], hideWithoutImage: false)['is_available'], isTrue);
      expect(plan.needsLibrarySearch.map((d) => d.name), ['Görselsiz']);

      none
        ..libraryImage = const BulkImage.library('https://lib/x.webp', 'Görselsiz')
        ..librarySearched = true;
      plan.resolve();
      expect(none.images.single.kind, BulkImageKind.library);
      expect(none.warnings.where((w) => w.startsWith('Görsel yok')), isEmpty);

      none.manualImages = const [];
      plan.resolve();
      expect(none.images, isEmpty, reason: 'satıcı görseli kaldırdıysa kütüphane geri gelmez');
    });

    test('yeni ürün satırı RPC alanları', () {
      final plan = _plan(
        'Ad;Fiyat;Stok;Kategori;Ücretsiz Kargo;Kargo Ücreti;Min. Sipariş Adedi;Rozetler;Satışta\n'
        'Peynir;120,5;8;Şarküteri;evet;25;0;Yeni;hayır\n',
        categories: const ['Market'],
      );
      final d = plan.drafts.single;
      expect(d.warnings, contains('"Şarküteri" kategorisi mağazana eklenecek'));
      expect(d.toRpcItem(imageUrls: const ['https://x/1.jpg', 'https://x/2.jpg'], hideWithoutImage: true), {
        'product_type': 'normal',
        'name': 'Peynir',
        'description': null,
        'price': 120.5,
        'old_price': null,
        'stock': 8,
        'category': 'Şarküteri',
        'image_url': 'https://x/1.jpg',
        'additional_images': ['https://x/2.jpg'],
        'is_available': false,
        'shipping_fee': null,
        'free_shipping': true,
        'min_order_quantity': null,
        'max_order_quantity': null,
        'badges': ['yeni'],
      });
    });
  });
}
