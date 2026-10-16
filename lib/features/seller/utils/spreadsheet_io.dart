import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

/// Toplu ürün yüklemede satıcının dosyasını hücre tablosuna çevirir ve
/// şablon / dışa aktarma için .xlsx üretir.
///
/// Desteklenen girdiler:
/// - `.xlsx` (ilk sayfa; paylaşılan metin, satır içi metin, sayı, mantıksal)
/// - CSV / TSV: ayırıcı ilk dolu satırdan seçilir (sekme, `;`, `,`).
///   Türkçe Excel "CSV (virgülle ayrılmış)" kaydını `;` ile ve Windows-1254
///   kodlamasıyla yazar; UTF-8 olarak çözülemeyen dosya 1254 sayılır.
///   Excel'in "Unicode metin" kaydı UTF-16 LE'dir (BOM'dan tanınır).
/// - Excel / Google E-Tablolar'dan kopyalanıp yapıştırılan metin (sekmeli).
///
/// Eski `.xls` (ikili biçim) okunamaz; [SpreadsheetReadException] açıklar.
class SpreadsheetIO {
  SpreadsheetIO._();

  /// Dosya baytlarını satırlara çevirir. Sondaki boş satırlar atılır, her
  /// hücre kırpılır.
  static SpreadsheetTable readBytes(Uint8List bytes, {String? fileName}) {
    final lower = (fileName ?? '').toLowerCase();
    if (_isZip(bytes)) {
      return SpreadsheetTable(_trim(_readXlsx(bytes)), numbersCanonical: true);
    }
    if (lower.endsWith('.xls') || _isOle(bytes)) {
      throw const SpreadsheetReadException(
        'Eski Excel (.xls) biçimi okunamıyor. Dosyayı Excel\'de '
        '"Farklı Kaydet → Excel Çalışma Kitabı (.xlsx)" ile kaydedip tekrar seçin.',
      );
    }
    return parseText(decodeText(bytes));
  }

  /// Yapıştırılan ya da çözülmüş metni satırlara çevirir.
  static SpreadsheetTable parseText(String text) {
    final normalized = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final delimiter = _detectDelimiter(normalized);
    return SpreadsheetTable(_trim(_parseDelimited(normalized, delimiter)));
  }

  // ── Metin çözme ─────────────────────────────────────────────────────────────

  static String decodeText(Uint8List bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _decodeUtf16(bytes.sublist(2), littleEndian: true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _decodeUtf16(bytes.sublist(2), littleEndian: false);
    }
    var data = bytes;
    if (data.length >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF) {
      data = data.sublist(3);
    }
    try {
      return utf8.decode(data);
    } on FormatException {
      return decodeWindows1254(data);
    }
  }

  static String _decodeUtf16(Uint8List bytes, {required bool littleEndian}) {
    final units = <int>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      units.add(
        littleEndian ? bytes[i] | (bytes[i + 1] << 8) : (bytes[i] << 8) | bytes[i + 1],
      );
    }
    return String.fromCharCodes(units);
  }

  /// Windows-1254 (Türkçe ANSI). 0x80–0x9F aralığı ve altı Türkçe harf
  /// dışında Latin-1 ile aynıdır.
  static String decodeWindows1254(List<int> bytes) {
    final out = StringBuffer();
    for (final b in bytes) {
      if (b < 0x80) {
        out.writeCharCode(b);
      } else if (b < 0xA0) {
        out.writeCharCode(_cp1254High[b - 0x80]);
      } else {
        out.writeCharCode(switch (b) {
          0xD0 => 0x011E, // Ğ
          0xDD => 0x0130, // İ
          0xDE => 0x015E, // Ş
          0xF0 => 0x011F, // ğ
          0xFD => 0x0131, // ı
          0xFE => 0x015F, // ş
          _ => b,
        });
      }
    }
    return out.toString();
  }

  static const List<int> _cp1254High = [
    0x20AC, 0xFFFD, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, //
    0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0xFFFD, 0xFFFD, 0xFFFD,
    0xFFFD, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014,
    0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0xFFFD, 0xFFFD, 0x0178,
  ];

  // ── Ayırıcılı metin ─────────────────────────────────────────────────────────

  static const List<String> _delimiters = ['\t', ';', ','];

  /// İlk 20 dolu satırda (tırnak dışında) her ayırıcıyı sayar. Satırların
  /// çoğunda AYNI sayıda geçen ilk ayırıcı seçilir: Türkçe CSV'de hem `;`
  /// (sütun) hem `,` (ondalık, "Elma, kırmızı") bulunur ama yalnız `;` her
  /// satırda sabittir. Üstteki tek hücrelik başlık satırı oranı bozmaz.
  static String _detectDelimiter(String text) {
    final lines = <Map<String, int>>[];
    var current = {for (final d in _delimiters) d: 0};
    var inQuotes = false;
    var hasContent = false;
    for (var i = 0; i < text.length && lines.length < 20; i++) {
      final ch = text[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
        hasContent = true;
      } else if (!inQuotes && ch == '\n') {
        if (hasContent) lines.add(current);
        current = {for (final d in _delimiters) d: 0};
        hasContent = false;
      } else if (!inQuotes && current.containsKey(ch)) {
        current[ch] = current[ch]! + 1;
      } else if (ch.trim().isNotEmpty) {
        hasContent = true;
      }
    }
    if (hasContent && lines.length < 20) lines.add(current);
    if (lines.isEmpty) return '\t';

    final needed = (lines.length * 0.6).ceil();
    for (final d in _delimiters) {
      final freq = <int, int>{};
      for (final l in lines) {
        final c = l[d]!;
        if (c > 0) freq[c] = (freq[c] ?? 0) + 1;
      }
      if (freq.isEmpty) continue;
      final best = freq.values.reduce((a, b) => a > b ? a : b);
      if (best >= needed) return d;
    }
    // Tutarlı ayırıcı yok: en çok geçen.
    var bestDelimiter = '\t';
    var bestTotal = 0;
    for (final d in _delimiters) {
      final total = lines.fold<int>(0, (s, l) => s + l[d]!);
      if (total > bestTotal) {
        bestTotal = total;
        bestDelimiter = d;
      }
    }
    return bestDelimiter;
  }

  static List<List<String>> _parseDelimited(String text, String delimiter) {
    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var inQuotes = false;
    var i = 0;
    while (i < text.length) {
      final ch = text[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i += 2;
            continue;
          }
          inQuotes = false;
        } else {
          cell.write(ch);
        }
      } else if (ch == '"' && cell.toString().trim().isEmpty) {
        cell.clear();
        inQuotes = true;
      } else if (ch == delimiter) {
        row.add(cell.toString());
        cell.clear();
      } else if (ch == '\n') {
        row.add(cell.toString());
        cell.clear();
        rows.add(row);
        row = <String>[];
      } else {
        cell.write(ch);
      }
      i++;
    }
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString());
      rows.add(row);
    }
    return rows;
  }

  static List<List<String>> _trim(List<List<String>> rows) {
    final out = [
      for (final r in rows) [for (final c in r) c.trim()],
    ];
    while (out.isNotEmpty && out.last.every((c) => c.isEmpty)) {
      out.removeLast();
    }
    return out;
  }

  // ── XLSX okuma ──────────────────────────────────────────────────────────────

  static bool _isZip(Uint8List b) =>
      b.length > 4 && b[0] == 0x50 && b[1] == 0x4B && b[2] == 0x03 && b[3] == 0x04;

  static bool _isOle(Uint8List b) =>
      b.length > 8 && b[0] == 0xD0 && b[1] == 0xCF && b[2] == 0x11 && b[3] == 0xE0;

  static List<List<String>> _readXlsx(Uint8List bytes) {
    final Archive archive;
    try {
      archive = ZipDecoder().decodeBytes(bytes);
    } catch (_) {
      throw const SpreadsheetReadException('Dosya açılamadı (bozuk ya da desteklenmeyen biçim).');
    }

    XmlDocument? docOf(String path) {
      final file = archive.findFile(path);
      if (file == null) return null;
      return XmlDocument.parse(utf8.decode(file.content, allowMalformed: true));
    }

    final sheetPath = _firstSheetPath(docOf('xl/workbook.xml'), docOf('xl/_rels/workbook.xml.rels'));
    final sheet = docOf(sheetPath) ?? docOf('xl/worksheets/sheet1.xml');
    if (sheet == null) {
      throw const SpreadsheetReadException('Dosyada çalışma sayfası bulunamadı (.xlsx değil mi?).');
    }

    final shared = <String>[];
    final sst = docOf('xl/sharedStrings.xml');
    if (sst != null) {
      for (final si in sst.findAllElements('si')) {
        shared.add(_textOf(si));
      }
    }

    final rows = <List<String>>[];
    for (final rowEl in sheet.findAllElements('row')) {
      final rowIndex = (int.tryParse(rowEl.getAttribute('r') ?? '') ?? rows.length + 1) - 1;
      while (rows.length < rowIndex) {
        rows.add(<String>[]);
      }
      final cells = <String>[];
      for (final c in rowEl.findElements('c')) {
        final ref = c.getAttribute('r');
        final col = ref == null ? cells.length : _columnIndex(ref);
        while (cells.length < col) {
          cells.add('');
        }
        cells.add(_cellValue(c, shared));
      }
      if (rowIndex < rows.length) {
        rows[rowIndex] = cells;
      } else {
        rows.add(cells);
      }
    }
    return rows;
  }

  static String _firstSheetPath(XmlDocument? workbook, XmlDocument? rels) {
    const fallback = 'xl/worksheets/sheet1.xml';
    if (workbook == null || rels == null) return fallback;
    final sheet = workbook.findAllElements('sheet').firstOrNull;
    if (sheet == null) return fallback;
    final relId = sheet.attributes
        .where((a) => a.name.local == 'id')
        .map((a) => a.value)
        .firstOrNull;
    if (relId == null) return fallback;
    for (final rel in rels.findAllElements('Relationship')) {
      if (rel.getAttribute('Id') == relId) {
        final target = rel.getAttribute('Target') ?? '';
        if (target.isEmpty) return fallback;
        return target.startsWith('/') ? target.substring(1) : 'xl/$target';
      }
    }
    return fallback;
  }

  static String _textOf(XmlElement el) =>
      // Zengin metinde birden fazla <r><t> parçası olur; fonetik (<rPh>) atlanır.
      el.descendants
          .whereType<XmlElement>()
          .where((e) => e.name.local == 't' && e.parentElement?.name.local != 'rPh')
          .map((e) => e.innerText)
          .join();

  static String _cellValue(XmlElement c, List<String> shared) {
    final type = c.getAttribute('t');
    final v = c.findElements('v').firstOrNull?.innerText ?? '';
    switch (type) {
      case 's':
        final i = int.tryParse(v);
        return (i != null && i >= 0 && i < shared.length) ? shared[i] : '';
      case 'inlineStr':
        final isEl = c.findElements('is').firstOrNull;
        return isEl == null ? '' : _textOf(isEl);
      case 'b':
        return v == '1' ? 'evet' : 'hayır';
      case 'str':
      case 'e':
        return v;
      default:
        return _formatNumber(v);
    }
  }

  /// Excel sayıları kayan noktalı saklar (12.5 → "12.499999999999998" olabilir).
  static String _formatNumber(String raw) {
    final d = double.tryParse(raw);
    if (d == null || !d.isFinite) return raw;
    if (d == d.roundToDouble() && d.abs() < 1e15) return d.toInt().toString();
    var s = d.toStringAsFixed(6);
    s = s.replaceFirst(RegExp(r'0+$'), '');
    return s.endsWith('.') ? s.substring(0, s.length - 1) : s;
  }

  static int _columnIndex(String ref) {
    var col = 0;
    for (final unit in ref.toUpperCase().codeUnits) {
      if (unit < 65 || unit > 90) break;
      col = col * 26 + (unit - 64);
    }
    return col == 0 ? 0 : col - 1;
  }

  static String columnName(int index) {
    var n = index + 1;
    final sb = StringBuffer();
    while (n > 0) {
      final rem = (n - 1) % 26;
      sb.write(String.fromCharCode(65 + rem));
      n = (n - 1) ~/ 26;
    }
    return sb.toString().split('').reversed.join();
  }

  // ── XLSX yazma ──────────────────────────────────────────────────────────────

  static const String xlsxMimeType =
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

  /// Basit bir .xlsx üretir: her sayfanın ilk satırı kalın ve dondurulmuş
  /// başlıktır. `num` hücreler sayı, diğerleri metin olarak yazılır.
  static Uint8List buildXlsx(List<SpreadsheetSheet> sheets) {
    assert(sheets.isNotEmpty);
    final archive = Archive();
    void add(String path, String content) =>
        archive.addFile(ArchiveFile.bytes(path, utf8.encode(content)));

    const ns = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
    const relNs = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
    const head = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n';

    final overrides = StringBuffer();
    for (var i = 0; i < sheets.length; i++) {
      overrides.write(
        '<Override PartName="/xl/worksheets/sheet${i + 1}.xml" '
        'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>',
      );
    }
    add(
      '[Content_Types].xml',
      '$head<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
          '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
          '<Default Extension="xml" ContentType="application/xml"/>'
          '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
          '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
          '$overrides</Types>',
    );
    add(
      '_rels/.rels',
      '$head<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '<Relationship Id="rId1" Type="$relNs/officeDocument" Target="xl/workbook.xml"/>'
          '</Relationships>',
    );

    final sheetEls = StringBuffer();
    final sheetRels = StringBuffer();
    for (var i = 0; i < sheets.length; i++) {
      sheetEls.write(
        '<sheet name="${_esc(_sheetName(sheets[i].name))}" sheetId="${i + 1}" r:id="rId${i + 1}"/>',
      );
      sheetRels.write(
        '<Relationship Id="rId${i + 1}" Type="$relNs/worksheet" Target="worksheets/sheet${i + 1}.xml"/>',
      );
    }
    sheetRels.write(
      '<Relationship Id="rId${sheets.length + 1}" Type="$relNs/styles" Target="styles.xml"/>',
    );
    add(
      'xl/workbook.xml',
      '$head<workbook xmlns="$ns" xmlns:r="$relNs"><sheets>$sheetEls</sheets></workbook>',
    );
    add(
      'xl/_rels/workbook.xml.rels',
      '$head<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
          '$sheetRels</Relationships>',
    );
    add(
      'xl/styles.xml',
      '$head<styleSheet xmlns="$ns">'
          '<fonts count="2"><font><sz val="11"/><name val="Calibri"/></font>'
          '<font><b/><sz val="11"/><name val="Calibri"/></font></fonts>'
          '<fills count="2"><fill><patternFill patternType="none"/></fill>'
          '<fill><patternFill patternType="gray125"/></fill></fills>'
          '<borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders>'
          '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
          '<cellXfs count="3"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
          '<xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1"/>'
          '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1">'
          '<alignment wrapText="1" vertical="top"/></xf></cellXfs>'
          '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
          '</styleSheet>',
    );

    for (var i = 0; i < sheets.length; i++) {
      add('xl/worksheets/sheet${i + 1}.xml', _sheetXml(sheets[i], ns, head));
    }
    return ZipEncoder().encodeBytes(archive);
  }

  static String _sheetXml(SpreadsheetSheet sheet, String ns, String head) {
    final sb = StringBuffer('$head<worksheet xmlns="$ns">');
    if (sheet.freezeHeader && sheet.rows.length > 1) {
      sb.write(
        '<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" '
        'activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>',
      );
    }
    if (sheet.columnWidths.isNotEmpty) {
      sb.write('<cols>');
      for (var c = 0; c < sheet.columnWidths.length; c++) {
        sb.write(
          '<col min="${c + 1}" max="${c + 1}" width="${sheet.columnWidths[c]}" customWidth="1"/>',
        );
      }
      sb.write('</cols>');
    }
    sb.write('<sheetData>');
    for (var r = 0; r < sheet.rows.length; r++) {
      sb.write('<row r="${r + 1}">');
      final row = sheet.rows[r];
      for (var c = 0; c < row.length; c++) {
        final value = row[c];
        if (value == null || (value is String && value.isEmpty)) continue;
        final ref = '${columnName(c)}${r + 1}';
        final style = (r == 0 && sheet.freezeHeader)
            ? ' s="1"'
            : (sheet.wrapText ? ' s="2"' : '');
        if (value is num && value.isFinite) {
          sb.write('<c r="$ref"$style><v>$value</v></c>');
        } else {
          sb.write(
            '<c r="$ref" t="inlineStr"$style><is><t xml:space="preserve">'
            '${_esc(value.toString())}</t></is></c>',
          );
        }
      }
      sb.write('</row>');
    }
    sb.write('</sheetData></worksheet>');
    return sb.toString();
  }

  /// Sayfa adı en fazla 31 karakter, `[]:*?/\` içeremez.
  static String _sheetName(String name) {
    final cleaned = name.replaceAll(RegExp(r'[\[\]:*?/\\]'), ' ').trim();
    final safe = cleaned.isEmpty ? 'Sayfa' : cleaned;
    return safe.length > 31 ? safe.substring(0, 31) : safe;
  }

  static String _esc(String s) {
    final sb = StringBuffer();
    for (final rune in s.runes) {
      switch (rune) {
        case 0x26:
          sb.write('&amp;');
        case 0x3C:
          sb.write('&lt;');
        case 0x3E:
          sb.write('&gt;');
        case 0x22:
          sb.write('&quot;');
        default:
          // XML 1.0'da geçersiz kontrol karakterleri atlanır.
          if (rune == 0x09 || rune == 0x0A || rune == 0x0D || rune >= 0x20) {
            sb.writeCharCode(rune);
          }
      }
    }
    return sb.toString();
  }
}

/// Okunan tablo.
class SpreadsheetTable {
  const SpreadsheetTable(this.rows, {this.numbersCanonical = false});

  final List<List<String>> rows;

  /// Sayı hücreleri "1234.5" biçiminde mi (xlsx)? Metin dosyalarında sayı
  /// yerel yazılır ("1.234,50"); ayrıştırıcı binlik ayırıcıyı ancak o zaman
  /// tahmin eder — aksi halde xlsx'teki 1.125 TL, 1125 TL okunurdu.
  final bool numbersCanonical;
}

/// [SpreadsheetIO.buildXlsx] için bir sayfa.
class SpreadsheetSheet {
  const SpreadsheetSheet({
    required this.name,
    required this.rows,
    this.columnWidths = const [],
    this.freezeHeader = true,
    this.wrapText = false,
  });

  final String name;

  /// Hücreler: `num` sayı olarak, diğerleri metin olarak yazılır.
  final List<List<Object?>> rows;
  final List<double> columnWidths;
  final bool freezeHeader;
  final bool wrapText;
}

/// Kullanıcıya olduğu gibi gösterilebilecek Türkçe okuma hatası.
class SpreadsheetReadException implements Exception {
  const SpreadsheetReadException(this.message);

  final String message;

  @override
  String toString() => message;
}
