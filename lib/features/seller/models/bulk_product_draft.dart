import 'dart:typed_data';

import '../../../core/models/product_model.dart';

/// Toplu ürün dosyasındaki tanınan sütunlar.
///
/// Başlık eşleştirmesi büyük/küçük harf, Türkçe karakter, boşluk, `*` ve
/// parantez içinden bağımsızdır ("Fiyat (TL) *" → fiyat). Şablon başlıkları
/// [templateHeader]; satıcının kendi dosyasındaki yaygın adlar [aliases].
enum BulkField {
  code('Ürün Kodu', ['urunkodu', 'urunid', 'id', 'kod', 'productid']),
  name('Ürün Adı', ['urunadi', 'ad', 'adi', 'isim', 'urun', 'name', 'productname', 'baslik', 'urunismi']),
  description('Açıklama', ['aciklama', 'urunaciklamasi', 'description', 'detay', 'detaylar']),
  price('Fiyat', ['fiyat', 'satisfiyati', 'fiyattl', 'price', 'tutar', 'birimfiyat', 'indirimlifiyat']),
  oldPrice('Eski Fiyat', ['eskifiyat', 'indirimoncesifiyat', 'listefiyati', 'oldprice', 'ustucizilifiyat', 'piyasafiyati']),
  stock('Stok', ['stok', 'stokadedi', 'stokmiktari', 'adet', 'miktar', 'stock', 'quantity']),
  category('Kategori', ['kategori', 'category', 'kategoriadi', 'reyon']),
  images('Görsel', [
    'gorsel', 'gorseller', 'gorselurl', 'gorsellinki', 'gorseldosyasi', 'resim', 'resimler',
    'resimurl', 'foto', 'fotograf', 'fotolar', 'image', 'images', 'imageurl', 'gorseladi',
  ]),
  available('Satışta', ['satista', 'durum', 'aktif', 'yayinda', 'status', 'satisdurumu', 'gorunur']),
  shippingFee('Kargo Ücreti', ['kargoucreti', 'kargo', 'shippingfee', 'kargobedeli']),
  freeShipping('Ücretsiz Kargo', ['ucretsizkargo', 'freeshipping', 'kargobedava']),
  minOrder('Min. Sipariş Adedi', ['minsiparisadedi', 'minadet', 'minsiparis', 'enazadet', 'enazsiparis']),
  maxOrder('Maks. Sipariş Adedi', [
    'makssiparisadedi', 'maxsiparisadedi', 'maxadet', 'maksadet', 'maxsiparis', 'makssiparis', 'encokadet',
  ]),
  badges('Rozetler', ['rozetler', 'rozet', 'badges', 'etiketler']);

  const BulkField(this.label, this.aliases);

  final String label;
  final List<String> aliases;

  /// Şablondaki başlık: zorunlu alanlar yıldızlı.
  String get templateHeader => switch (this) {
    BulkField.name || BulkField.price || BulkField.stock => '$label *',
    _ => label,
  };

  static BulkField? fromHeader(String header) {
    final key = BulkValues.headerKey(header);
    if (key.isEmpty) return null;
    for (final f in BulkField.values) {
      if (f.aliases.contains(key)) return f;
    }
    return null;
  }
}

/// Başlık satırının yeri ve sütun → alan eşlemesi.
class BulkSheetMapping {
  const BulkSheetMapping({
    required this.headerRow,
    required this.columns,
    required this.unknownHeaders,
  });

  /// Tablo içindeki 0 tabanlı başlık satırı.
  final int headerRow;
  final Map<BulkField, int> columns;
  final List<String> unknownHeaders;

  /// İlk 10 satırda ürün adı ya da ürün kodu içeren, en çok sütunu tanınan
  /// satırı başlık sayar. Bulunamazsa null.
  static BulkSheetMapping? detect(List<List<String>> rows) {
    BulkSheetMapping? best;
    for (var r = 0; r < rows.length && r < 10; r++) {
      final columns = <BulkField, int>{};
      final unknown = <String>[];
      for (var c = 0; c < rows[r].length; c++) {
        final header = rows[r][c];
        if (header.trim().isEmpty) continue;
        final field = BulkField.fromHeader(header);
        if (field == null) {
          unknown.add(header.trim());
        } else {
          columns.putIfAbsent(field, () => c);
        }
      }
      final usable = columns.containsKey(BulkField.name) || columns.containsKey(BulkField.code);
      if (!usable || columns.length < 2) continue;
      if (best == null || columns.length > best.columns.length) {
        best = BulkSheetMapping(headerRow: r, columns: columns, unknownHeaders: unknown);
      }
    }
    return best;
  }
}

/// Hücre metni → değer dönüştürücüleri.
class BulkValues {
  BulkValues._();

  /// Türkçe harfleri ASCII'ye indirip yalnız harf/rakam bırakır.
  static String fold(String s) {
    const from = 'çÇğĞıİIöÖşŞüÜâÂîÎûÛ';
    const to = 'ccggiiioossuuaaiiuu';
    final sb = StringBuffer();
    for (final ch in s.split('')) {
      final i = from.indexOf(ch);
      sb.write(i >= 0 ? to[i] : ch.toLowerCase());
    }
    return sb.toString();
  }

  static String headerKey(String header) {
    final withoutParens = header.replaceAll(RegExp(r'\([^)]*\)'), '');
    return fold(withoutParens).replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  /// Ad karşılaştırma anahtarı (büyük/küçük harf, Türkçe harf ve fazla
  /// boşluktan bağımsız).
  static String nameKey(String name) =>
      fold(name.trim()).replaceAll(RegExp(r'\s+'), ' ');

  /// "12,50", "1.234,50", "1,234.50", "₺ 99", "99 TL" → sayı.
  /// [canonical]: xlsx sayı hücresi ("1234.5") — önce olduğu gibi okunur.
  static double? parseNumber(String input, {bool canonical = false}) {
    var s = input.trim();
    if (s.isEmpty) return null;
    if (canonical) {
      final direct = double.tryParse(s);
      if (direct != null) return direct;
    }
    s = s
        .replaceAll(RegExp(r'^(₺|tl|try)\s*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*(₺|tl|try)$', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\s ]'), '');
    if (s.isEmpty) return null;
    final lastComma = s.lastIndexOf(',');
    final lastDot = s.lastIndexOf('.');
    if (lastComma >= 0 && lastDot >= 0) {
      s = lastComma > lastDot
          ? s.replaceAll('.', '').replaceAll(',', '.')
          : s.replaceAll(',', '');
    } else if (lastComma >= 0) {
      s = ','.allMatches(s).length > 1 ? s.replaceAll(',', '') : s.replaceAll(',', '.');
    } else if (lastDot >= 0) {
      // "1.250" Türkçede bin iki yüz elli; tek noktalı ve 3 haneli kesir
      // dışındakiler ondalık sayılır.
      if ('.'.allMatches(s).length > 1 || RegExp(r'^-?\d{1,3}\.\d{3}$').hasMatch(s)) {
        s = s.replaceAll('.', '');
      }
    }
    final v = double.tryParse(s);
    return (v == null || !v.isFinite) ? null : v;
  }

  /// Tam sayı; "10", "10,0", "10.0" kabul, "10,5" reddedilir.
  static int? parseInt(String input, {bool canonical = false}) {
    final v = parseNumber(input, canonical: canonical);
    if (v == null || v != v.roundToDouble() || v.abs() > 1e9) return null;
    return v.toInt();
  }

  static const _yes = {'evet', 'e', 'yes', 'y', 'true', 'dogru', '1', 'var', 'aktif', 'acik', 'satista', 'x', 'olur'};
  static const _no = {'hayir', 'h', 'no', 'n', 'false', 'yanlis', '0', 'yok', 'pasif', 'kapali', 'gizli', 'degil'};

  static bool? parseBool(String input) {
    final k = fold(input.trim()).replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (k.isEmpty) return null;
    if (_yes.contains(k) || input.trim() == '✓' || input.trim() == '✔') return true;
    if (_no.contains(k)) return false;
    return null;
  }

  /// Rozet hücresi: anahtar ya da etiket, virgül/noktalı virgül/| ile ayrılmış.
  /// "-", "yok" boş liste. Tanınmayan varsa ilk tanınmayan [unknown]'a yazılır.
  static List<String>? parseBadges(String input, {List<String>? unknown}) {
    final t = input.trim();
    if (t.isEmpty) return null;
    if (t == '-' || fold(t) == 'yok') return const [];
    final out = <String>[];
    for (final part in t.split(RegExp(r'[,;|/]'))) {
      final k = fold(part).replaceAll(RegExp(r'[^a-z0-9]'), '');
      if (k.isEmpty) continue;
      ProductBadge? match;
      for (final b in ProductBadge.all) {
        if (b.key.replaceAll('_', '') == k || fold(b.label).replaceAll(RegExp(r'[^a-z0-9]'), '') == k) {
          match = b;
          break;
        }
      }
      if (match == null) {
        unknown?.add(part.trim());
        continue;
      }
      if (!out.contains(match.key)) out.add(match.key);
    }
    return out;
  }

  /// Görsel hücresi: URL'ler ya da dosya adları; `|`, satır sonu, `;` ya da
  /// (birden çok URL varsa) virgül/boşlukla ayrılmış.
  static List<String> splitImageRefs(String input) {
    final out = <String>[];
    for (final piece in input.split(RegExp(r'[|\n;]'))) {
      final p = piece.trim();
      if (p.isEmpty) continue;
      if (RegExp('https?://', caseSensitive: false).allMatches(p).length > 1) {
        out.addAll(
          p.split(RegExp(r'[,\s]+(?=https?://)', caseSensitive: false)).map((e) => e.trim()).where((e) => e.isNotEmpty),
        );
      } else {
        out.add(p);
      }
    }
    return out;
  }

  static bool isUrl(String ref) => RegExp(r'^https?://', caseSensitive: false).hasMatch(ref.trim());

  /// Dosya adı karşılaştırma anahtarı: klasör ve uzantı atılır.
  static String fileKey(String nameOrPath) {
    var base = nameOrPath.trim().split(RegExp(r'[\\/]')).last;
    final dot = base.lastIndexOf('.');
    if (dot > 0) base = base.substring(0, dot);
    return fold(base).replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}

/// Bir ürün satırının görseli ve nereden geldiği.
enum BulkImageKind {
  /// Zaten bizim depomuzda (dışa aktarılmış ürün ya da kütüphane) — yüklenmez.
  ready,

  /// Dış bağlantı: yüklemede indirilip mağaza klasörüne kopyalanır.
  remote,

  /// Satıcının seçtiği dosyalardan adıyla eşleşen.
  file,

  /// Ürün adıyla kütüphaneden otomatik bulunan.
  library,
}

class BulkImage {
  const BulkImage._(this.kind, {this.url, this.read, this.fileName, this.label});

  const BulkImage.ready(String url) : this._(BulkImageKind.ready, url: url);
  const BulkImage.remote(String url) : this._(BulkImageKind.remote, url: url);

  /// Cihazdaki dosya. Baytlar yüklemede okunur: yüzlerce fotoğraf seçildiğinde
  /// hepsi birden belleğe alınmasın.
  const BulkImage.file(String fileName, Future<Uint8List> Function() read)
    : this._(BulkImageKind.file, fileName: fileName, read: read);
  const BulkImage.library(String url, String name)
    : this._(BulkImageKind.library, url: url, label: name);

  final BulkImageKind kind;
  final String? url;
  final Future<Uint8List> Function()? read;
  final String? fileName;

  /// Kütüphane görselinin adı.
  final String? label;

  /// Depoya yüklenmesi gerekiyor mu?
  bool get needsUpload => kind == BulkImageKind.remote || kind == BulkImageKind.file;

  /// Önizlemede küçük resim gösterilebilir mi? (Yalnız kendi depomuzdakiler;
  /// dış sitelerin görselleri web'de CORS'a takılır.)
  bool get hasNetworkPreview => kind == BulkImageKind.ready || kind == BulkImageKind.library;
}

/// Mağazada aynı adla zaten olan ürünler için ne yapılacağı (ürün kodu
/// verilmiş satırlar her zaman o ürünü günceller).
enum BulkDuplicatePolicy {
  skip('Atla'),
  update('Güncelle'),
  create('Yine de ekle');

  const BulkDuplicatePolicy(this.label);
  final String label;
}

enum BulkRowAction {
  create,
  update,

  /// Aynı adlı ürün var, politika "atla".
  skipExisting,

  /// Güncellenecek ürün zaten aynı — gönderilmez.
  unchanged,
}

/// Dosyadaki bir ürün satırı: ayrıştırılmış değerler + doğrulama durumu.
class BulkProductDraft {
  BulkProductDraft({required this.rowNumber});

  /// Sayfadaki satır numarası (1 tabanlı; satıcıya böyle gösterilir).
  final int rowNumber;

  /// Dosyada DOLU gelen (ya da önizlemede düzenlenen) alanlar. Güncellemede
  /// yalnız bunlar değişir — boş hücre "dokunma" demektir.
  final Set<BulkField> present = {};

  /// Ayrıştırılamayan hücreler: alan → hata metni.
  final Map<BulkField, String> invalid = {};

  String? code;
  String? name;
  String? description;
  double? price;
  double? oldPrice;
  int? stock;
  String? category;
  List<String> imageRefs = [];
  bool? isAvailable;
  double? shippingFee;
  bool? freeShipping;
  int? minOrder;
  int? maxOrder;
  List<String>? badges;

  // ── Çözümleme sonucu ────────────────────────────────────────────────────────
  Product? existing;
  bool matchedByName = false;
  BulkRowAction action = BulkRowAction.create;

  /// Kullanılacak görseller (en fazla 5). [BulkImportPlan.resolve] üretir.
  List<BulkImage> images = [];

  /// Görsel hücresindeki, seçilen dosyalar arasında bulunamayan dosya adları.
  final List<String> unresolvedRefs = [];

  /// Kütüphaneden ürün adıyla bulunan görsel (yalnız başka görsel yoksa).
  BulkImage? libraryImage;
  bool librarySearched = false;

  /// Satıcının önizlemede elle seçtiği görseller; null = otomatik, boş liste =
  /// "görsel olmasın".
  List<BulkImage>? manualImages;

  /// Satıcı bu satırı listeden çıkardı mı?
  bool include = true;

  final List<String> errors = [];
  final List<String> warnings = [];

  bool get isValid => errors.isEmpty;
  bool get willSend =>
      include && isValid && (action == BulkRowAction.create || action == BulkRowAction.update);

  String get displayName => (name?.trim().isNotEmpty ?? false)
      ? name!.trim()
      : (existing?.name ?? 'Satır $rowNumber');

  /// Tablo satırını ayrıştırır.
  factory BulkProductDraft.fromCells({
    required int rowNumber,
    required List<String> cells,
    required BulkSheetMapping mapping,
    bool numbersCanonical = false,
  }) {
    final d = BulkProductDraft(rowNumber: rowNumber);
    mapping.columns.forEach((field, index) {
      final raw = index < cells.length ? cells[index].trim() : '';
      if (raw.isEmpty) return;
      d.setRaw(field, raw, numbersCanonical: numbersCanonical);
    });
    return d;
  }

  /// Bir alanı hücre metninden ayarlar (önizlemede düzenlemede de kullanılır).
  /// Boş metin alanı "dosyada yok" yapar.
  void setRaw(BulkField field, String raw, {bool numbersCanonical = false}) {
    final t = raw.trim();
    invalid.remove(field);
    if (t.isEmpty) {
      present.remove(field);
      _clear(field);
      return;
    }
    present.add(field);
    final c = numbersCanonical;
    switch (field) {
      case BulkField.code:
        code = t;
      case BulkField.name:
        name = t.replaceAll(RegExp(r'\s+'), ' ');
      case BulkField.description:
        description = t;
      case BulkField.price:
        price = BulkValues.parseNumber(t, canonical: c);
        if (price == null) invalid[field] = 'Fiyat sayı değil: "$t"';
      case BulkField.oldPrice:
        oldPrice = BulkValues.parseNumber(t, canonical: c);
        if (oldPrice == null) invalid[field] = 'Eski fiyat sayı değil: "$t"';
      case BulkField.stock:
        stock = BulkValues.parseInt(t, canonical: c);
        if (stock == null) invalid[field] = 'Stok tam sayı değil: "$t"';
      case BulkField.category:
        category = t.replaceAll(RegExp(r'\s+'), ' ');
      case BulkField.images:
        imageRefs = BulkValues.splitImageRefs(t);
      case BulkField.available:
        isAvailable = BulkValues.parseBool(t);
        if (isAvailable == null) invalid[field] = 'Satışta: "$t" (evet/hayır yazın)';
      case BulkField.shippingFee:
        shippingFee = BulkValues.parseNumber(t, canonical: c);
        if (shippingFee == null) invalid[field] = 'Kargo ücreti sayı değil: "$t"';
      case BulkField.freeShipping:
        freeShipping = BulkValues.parseBool(t);
        if (freeShipping == null) invalid[field] = 'Ücretsiz kargo: "$t" (evet/hayır yazın)';
      case BulkField.minOrder:
        minOrder = BulkValues.parseInt(t, canonical: c);
        if (minOrder == null) invalid[field] = 'Min. sipariş adedi tam sayı değil: "$t"';
      case BulkField.maxOrder:
        maxOrder = BulkValues.parseInt(t, canonical: c);
        if (maxOrder == null) invalid[field] = 'Maks. sipariş adedi tam sayı değil: "$t"';
      case BulkField.badges:
        final unknown = <String>[];
        badges = BulkValues.parseBadges(t, unknown: unknown);
        if (unknown.isNotEmpty) invalid[field] = 'Bilinmeyen rozet: "${unknown.first}"';
    }
  }

  void _clear(BulkField field) {
    switch (field) {
      case BulkField.code:
        code = null;
      case BulkField.name:
        name = null;
      case BulkField.description:
        description = null;
      case BulkField.price:
        price = null;
      case BulkField.oldPrice:
        oldPrice = null;
      case BulkField.stock:
        stock = null;
      case BulkField.category:
        category = null;
      case BulkField.images:
        imageRefs = [];
      case BulkField.available:
        isAvailable = null;
      case BulkField.shippingFee:
        shippingFee = null;
      case BulkField.freeShipping:
        freeShipping = null;
      case BulkField.minOrder:
        minOrder = null;
      case BulkField.maxOrder:
        maxOrder = null;
      case BulkField.badges:
        badges = null;
    }
  }

  /// Önizlemedeki düzenleme alanı için hücre metni.
  String rawText(BulkField field) {
    String num(double? v) {
      if (v == null) return '';
      return v == v.roundToDouble() ? v.toInt().toString() : v.toString().replaceAll('.', ',');
    }

    return switch (field) {
      BulkField.code => code ?? '',
      BulkField.name => name ?? '',
      BulkField.description => description ?? '',
      BulkField.price => num(price),
      BulkField.oldPrice => num(oldPrice),
      BulkField.stock => stock?.toString() ?? '',
      BulkField.category => category ?? '',
      BulkField.images => imageRefs.join(' | '),
      BulkField.available => isAvailable == null ? '' : (isAvailable! ? 'evet' : 'hayır'),
      BulkField.shippingFee => num(shippingFee),
      BulkField.freeShipping => freeShipping == null ? '' : (freeShipping! ? 'evet' : 'hayır'),
      BulkField.minOrder => minOrder?.toString() ?? '',
      BulkField.maxOrder => maxOrder?.toString() ?? '',
      BulkField.badges => (badges ?? const [])
          .map((k) => ProductBadge.fromKey(k)?.label ?? k)
          .join(', '),
    };
  }

  // ── Doğrulama ───────────────────────────────────────────────────────────────

  /// Hataları ve uyarıları yeniden hesaplar. [action] önceden belirlenmiş
  /// olmalı (bkz. BulkImportPlan.resolve).
  void validate({required bool hideWithoutImage, required Set<String> shopCategoryKeys}) {
    errors
      ..clear()
      ..addAll(invalid.values);
    warnings.clear();

    final isUpdate = action == BulkRowAction.update;
    final n = name?.trim() ?? '';

    if (!isUpdate || present.contains(BulkField.name)) {
      if (n.length < 2) {
        errors.add('Ürün adı eksik');
      } else if (n.length > 200) {
        errors.add('Ürün adı en fazla 200 karakter olabilir');
      }
    }
    if ((description?.length ?? 0) > 5000) {
      errors.add('Açıklama en fazla 5000 karakter olabilir');
    }
    if ((category?.length ?? 0) > 60) {
      errors.add('Kategori adı en fazla 60 karakter olabilir');
    }

    final effPrice = present.contains(BulkField.price) ? price : existing?.price;
    if (!invalid.containsKey(BulkField.price)) {
      if (!isUpdate && price == null) {
        errors.add('Fiyat eksik');
      } else if (present.contains(BulkField.price) && price != null && price! <= 0) {
        errors.add('Fiyat 0\'dan büyük olmalı');
      } else if ((price ?? 0) > 10000000) {
        errors.add('Fiyat çok yüksek');
      }
    }
    if (oldPrice != null && oldPrice! > 0 && effPrice != null && oldPrice! <= effPrice) {
      errors.add('Eski fiyat, satış fiyatından büyük olmalı');
    }
    if (oldPrice != null && oldPrice! < 0) errors.add('Eski fiyat negatif olamaz');

    if (!invalid.containsKey(BulkField.stock)) {
      if (!isUpdate && stock == null) {
        errors.add('Stok eksik');
      } else if (stock != null && stock! < 0) {
        errors.add('Stok negatif olamaz');
      }
    }
    if (isUpdate &&
        present.contains(BulkField.stock) &&
        (existing?.hasVariants ?? false) &&
        stock != existing?.stockQuantity) {
      errors.add('Bedenli/numaralı ürünün stoğu renk varyantlarından yönetilir');
    }
    if (shippingFee != null && shippingFee! < 0) errors.add('Kargo ücreti negatif olamaz');
    if (minOrder != null && minOrder! < 0) errors.add('Min. sipariş adedi negatif olamaz');
    if (maxOrder != null && maxOrder! < 0) errors.add('Maks. sipariş adedi negatif olamaz');
    final effMin = present.contains(BulkField.minOrder) ? _positiveOrNull(minOrder) : existing?.minOrderQuantity;
    final effMax = present.contains(BulkField.maxOrder) ? _positiveOrNull(maxOrder) : existing?.maxOrderQuantity;
    if (effMin != null && effMax != null && effMax < effMin) {
      errors.add('Maks. sipariş adedi, minimumdan küçük olamaz');
    }
    if ((badges?.length ?? 0) > ProductBadge.maxPerProduct) {
      errors.add('En fazla ${ProductBadge.maxPerProduct} rozet seçilebilir');
    }
    if (existing?.isDigital ?? false) errors.add('Dijital ürünler dosyayla güncellenemez');

    // Uyarılar
    if (imageRefs.length > 5 && manualImages == null) {
      warnings.add('Yalnız ilk 5 görsel kullanılacak');
    }
    if (unresolvedRefs.isNotEmpty && manualImages == null) {
      warnings.add('Görsel dosyası seçilmedi: ${unresolvedRefs.join(', ')}');
    }
    if (action == BulkRowAction.create) {
      if (images.isEmpty) {
        warnings.add(hideWithoutImage ? 'Görsel yok — satışa kapalı eklenecek' : 'Görsel yok');
      }
      final cat = category?.trim();
      if (cat != null && cat.isNotEmpty && !shopCategoryKeys.contains(cat.toLowerCase())) {
        warnings.add('"$cat" kategorisi mağazana eklenecek');
      }
    }
    if (matchedByName && action == BulkRowAction.update) {
      warnings.add('Aynı adlı ürün güncellenecek');
    }
  }

  static int? _positiveOrNull(int? v) => (v == null || v <= 0) ? null : v;

  // ── Sunucuya gidecek satır ──────────────────────────────────────────────────

  /// Güncellemede mevcut üründen farklı olan alanlar (görseller hariç; onlar
  /// yüklemeden sonra eklenir). Boşsa ürün değişmemiştir.
  Map<String, dynamic> updateDiff() {
    final p = existing!;
    final diff = <String, dynamic>{};
    bool differs(double? a, double? b) => (a == null) != (b == null) || (a != null && (a - b!).abs() > 0.0001);

    // Adla eşleşen üründe ad eşleşme anahtarıdır; "salkim domates" yazımı
    // "Salkım Domates"i ezmesin.
    if (present.contains(BulkField.name) && !matchedByName && name != null && name != p.name) {
      diff['name'] = name;
    }
    if (present.contains(BulkField.description) && description != (p.description ?? '')) {
      diff['description'] = description;
    }
    if (present.contains(BulkField.price) && price != null && differs(price, p.price)) diff['price'] = price;
    if (present.contains(BulkField.oldPrice)) {
      final v = (oldPrice == null || oldPrice! <= 0) ? null : oldPrice;
      if (differs(v, p.oldPrice)) diff['old_price'] = v;
    }
    if (present.contains(BulkField.stock) && stock != null && stock != p.stockQuantity) diff['stock'] = stock;
    if (present.contains(BulkField.category) && category != p.category) diff['category'] = category;
    if (present.contains(BulkField.available) && isAvailable != null && isAvailable != p.isAvailable) {
      diff['is_available'] = isAvailable;
    }
    if (present.contains(BulkField.shippingFee) && differs(shippingFee, p.shippingFee)) {
      diff['shipping_fee'] = shippingFee;
    }
    if (present.contains(BulkField.freeShipping) && freeShipping != null && freeShipping != p.freeShipping) {
      diff['free_shipping'] = freeShipping;
    }
    if (present.contains(BulkField.minOrder) && _positiveOrNull(minOrder) != p.minOrderQuantity) {
      diff['min_order_quantity'] = _positiveOrNull(minOrder);
    }
    if (present.contains(BulkField.maxOrder) && _positiveOrNull(maxOrder) != p.maxOrderQuantity) {
      diff['max_order_quantity'] = _positiveOrNull(maxOrder);
    }
    if (present.contains(BulkField.badges) && badges != null) {
      final a = [...badges!]..sort();
      final b = [...p.badges]..sort();
      if (a.join(',') != b.join(',')) diff['badges'] = badges;
    }
    return diff;
  }

  /// Görseller güncellemede değişiyor mu? (Yüklenecek her görsel değişikliktir.)
  bool get imagesChanged {
    if (action != BulkRowAction.update || images.isEmpty) return false;
    if (images.any((i) => i.needsUpload)) return true;
    final urls = images.map((i) => i.url).toList();
    return urls.join('|') != existing!.images.join('|');
  }

  /// RPC satırı. [imageUrls] yüklenmiş/hazır görsel adresleri (sırayla).
  Map<String, dynamic> toRpcItem({required List<String> imageUrls, required bool hideWithoutImage}) {
    if (action == BulkRowAction.update) {
      return {
        'id': existing!.id,
        ...updateDiff(),
        if (imageUrls.isNotEmpty) ...{
          'image_url': imageUrls.first,
          'additional_images': imageUrls.skip(1).toList(),
        },
      };
    }
    final available = (isAvailable ?? true) && !(hideWithoutImage && imageUrls.isEmpty);
    return {
      'product_type': 'normal',
      'name': name,
      'description': description,
      'price': price,
      'old_price': (oldPrice == null || oldPrice! <= 0) ? null : oldPrice,
      'stock': stock,
      'category': category,
      'image_url': imageUrls.isEmpty ? null : imageUrls.first,
      'additional_images': imageUrls.skip(1).toList(),
      'is_available': available,
      'shipping_fee': (freeShipping ?? false) ? null : shippingFee,
      'free_shipping': freeShipping ?? false,
      'min_order_quantity': _positiveOrNull(minOrder),
      'max_order_quantity': _positiveOrNull(maxOrder),
      'badges': badges ?? const <String>[],
    };
  }
}

/// Dosyadan çıkan tüm satırlar + mağaza bağlamı; eşleştirme ve sayımlar.
class BulkImportPlan {
  BulkImportPlan({
    required this.drafts,
    required this.mapping,
    required List<Product> existingProducts,
    required List<String> shopCategories,
  }) : _byId = {for (final p in existingProducts) p.id: p},
       _shopCategoryKeys = {for (final c in shopCategories) c.trim().toLowerCase()} {
    for (final p in existingProducts) {
      if (p.isDigital) continue;
      _byName.putIfAbsent(BulkValues.nameKey(p.name), () => []).add(p);
    }
  }

  final List<BulkProductDraft> drafts;
  final BulkSheetMapping mapping;
  final Map<String, Product> _byId;
  final Map<String, List<Product>> _byName = {};
  final Set<String> _shopCategoryKeys;

  BulkDuplicatePolicy duplicatePolicy = BulkDuplicatePolicy.skip;
  bool hideWithoutImage = true;

  /// Görselsiz satırlarda kütüphane eşleşmesi kullanılsın mı?
  bool useLibraryImages = true;

  /// Kendi depomuzun herkese açık adres öneki (`…/storage/v1/object/public/`).
  /// Bununla başlayan görseller yeniden yüklenmez (dışa aktarılan dosya).
  String ownStoragePrefix = '';

  /// Satıcının seçtiği görsel dosyaları: [BulkValues.fileKey] → görsel.
  final Map<String, BulkImage> pickedFiles = {};

  /// Dosyada ürün kodu ya da adı tekrar eden satırlar (ilki hariç).
  final Set<int> duplicateRows = {};

  /// Ürün kodu olmadan, mağazadaki bir ürünle aynı adı taşıyan satır sayısı
  /// (politikadan bağımsız; seçeneği göstermek için).
  int nameMatchCount = 0;

  /// Tablodan plan kurar: başlık altındaki boş satırlar atlanır.
  static BulkImportPlan fromTable({
    required List<List<String>> rows,
    required BulkSheetMapping mapping,
    required bool numbersCanonical,
    required List<Product> existingProducts,
    required List<String> shopCategories,
  }) {
    final drafts = <BulkProductDraft>[];
    for (var r = mapping.headerRow + 1; r < rows.length; r++) {
      final cells = rows[r];
      if (cells.every((c) => c.trim().isEmpty)) continue;
      drafts.add(
        BulkProductDraft.fromCells(
          rowNumber: r + 1,
          cells: cells,
          mapping: mapping,
          numbersCanonical: numbersCanonical,
        ),
      );
    }
    return BulkImportPlan(
      drafts: drafts,
      mapping: mapping,
      existingProducts: existingProducts,
      shopCategories: shopCategories,
    )..resolve();
  }

  /// Mevcut ürünle eşleştirir, eylemi belirler ve doğrular.
  void resolve() {
    duplicateRows.clear();
    nameMatchCount = 0;
    final seen = <String>{};
    for (final d in drafts) {
      d.existing = null;
      d.matchedByName = false;
      d.action = BulkRowAction.create;
      String? codeError;

      final code = d.code?.trim();
      if (code != null && code.isNotEmpty) {
        final p = _byId[code];
        if (p == null) {
          codeError = 'Ürün kodu mağazanda yok';
        } else {
          d.existing = p;
          d.action = BulkRowAction.update;
        }
      } else if (d.name != null) {
        final matches = _byName[BulkValues.nameKey(d.name!)];
        if (matches != null && matches.isNotEmpty) {
          nameMatchCount++;
          switch (duplicatePolicy) {
            case BulkDuplicatePolicy.skip:
              d.existing = matches.first;
              d.matchedByName = true;
              d.action = BulkRowAction.skipExisting;
            case BulkDuplicatePolicy.update:
              d.existing = matches.first;
              d.matchedByName = true;
              d.action = BulkRowAction.update;
            case BulkDuplicatePolicy.create:
              break;
          }
        }
      }

      _resolveImages(d);
      d.validate(hideWithoutImage: hideWithoutImage, shopCategoryKeys: _shopCategoryKeys);
      if (codeError != null) d.errors.insert(0, codeError);

      if (d.action == BulkRowAction.update && d.isValid && d.updateDiff().isEmpty && !d.imagesChanged) {
        d.action = BulkRowAction.unchanged;
      }

      final key = (code != null && code.isNotEmpty)
          ? 'id:$code'
          : (d.name == null ? null : 'ad:${BulkValues.nameKey(d.name!)}');
      if (key != null && !seen.add(key)) {
        duplicateRows.add(d.rowNumber);
        d.warnings.add('Dosyada bu ürün birden fazla kez var');
      }
    }
  }

  /// Görsel önceliği: elle seçilen → hücredeki URL/dosya adları → ürün adıyla
  /// (ya da koduyla) adlandırılmış seçili dosya → kütüphane eşleşmesi.
  void _resolveImages(BulkProductDraft d) {
    d.unresolvedRefs.clear();
    if (d.manualImages != null) {
      d.images = d.manualImages!.take(5).toList();
      return;
    }
    final resolved = <BulkImage>[];
    for (final ref in d.imageRefs.take(5)) {
      if (BulkValues.isUrl(ref)) {
        final own = ownStoragePrefix.isNotEmpty && ref.startsWith(ownStoragePrefix);
        resolved.add(own ? BulkImage.ready(ref) : BulkImage.remote(ref));
      } else {
        final f = pickedFiles[BulkValues.fileKey(ref)];
        if (f != null) {
          resolved.add(f);
        } else {
          d.unresolvedRefs.add(ref);
        }
      }
    }
    if (resolved.isEmpty && d.imageRefs.isEmpty && pickedFiles.isNotEmpty) {
      for (final key in [d.name, d.code]) {
        final f = key == null ? null : pickedFiles[BulkValues.fileKey(key)];
        if (f != null) {
          resolved.add(f);
          break;
        }
      }
    }
    if (resolved.isEmpty && useLibraryImages && d.libraryImage != null && wantsLibraryImage(d)) {
      resolved.add(d.libraryImage!);
    }
    d.images = resolved;
  }

  /// Kütüphaneden görsel aranacak satır mı? Yeni ürünler ve görseli hiç
  /// olmayan güncellenen ürünler; dosyada görsel belirtilmişse aranmaz.
  bool wantsLibraryImage(BulkProductDraft d) =>
      d.include &&
      d.manualImages == null &&
      d.imageRefs.isEmpty &&
      (d.action == BulkRowAction.create ||
          ((d.action == BulkRowAction.update || d.action == BulkRowAction.unchanged) &&
              (d.existing?.images.isEmpty ?? false)));

  Iterable<BulkProductDraft> get toCreate =>
      drafts.where((d) => d.willSend && d.action == BulkRowAction.create);
  Iterable<BulkProductDraft> get toUpdate =>
      drafts.where((d) => d.willSend && d.action == BulkRowAction.update);
  Iterable<BulkProductDraft> get invalidRows => drafts.where((d) => d.include && !d.isValid);
  Iterable<BulkProductDraft> get skippedExisting =>
      drafts.where((d) => d.include && d.isValid && d.action == BulkRowAction.skipExisting);
  Iterable<BulkProductDraft> get unchanged =>
      drafts.where((d) => d.include && d.isValid && d.action == BulkRowAction.unchanged);
  Iterable<BulkProductDraft> get excluded => drafts.where((d) => !d.include);
  Iterable<BulkProductDraft> get sendable => drafts.where((d) => d.willSend);

  /// Kütüphanede henüz aranmamış, görselsiz satırlar.
  Iterable<BulkProductDraft> get needsLibrarySearch => drafts.where(
    (d) =>
        useLibraryImages &&
        !d.librarySearched &&
        d.images.isEmpty &&
        d.name != null &&
        d.isValid &&
        wantsLibraryImage(d),
  );

  /// Kütüphaneden görsel alan satırlar.
  Iterable<BulkProductDraft> get withLibraryImage =>
      drafts.where((d) => d.images.any((i) => i.kind == BulkImageKind.library));
}
