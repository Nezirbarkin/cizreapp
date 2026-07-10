/// Fatura türü enum
enum InvoiceType {
  individual, // Bireysel (T.C. kimlik no ile)
  corporate;  // Kurumsal (Vergi no ile)

  String get label {
    switch (this) {
      case InvoiceType.individual:
        return 'Bireysel';
      case InvoiceType.corporate:
        return 'Kurumsal';
    }
  }

  String get dbValue => name;

  static InvoiceType fromString(String? value) {
    if (value == null) return InvoiceType.individual;
    return InvoiceType.values.firstWhere(
      (type) => type.name == value,
      orElse: () => InvoiceType.individual,
    );
  }
}

/// Fatura bilgileri modeli
/// 
/// Müşteri fatura bilgilerini temsil eder. İki kullanım alanı vardır:
/// 1. profiles tablosu: Kayıtlı fatura bilgileri (tekrar kullanılabilir)
/// 2. orders tablosu: Sipariş anındaki snapshot (değiştirilemez)
class InvoiceInfo {
  final InvoiceType type;
  final String? fullName;
  final String? taxNumber;    // Vergi no (kurumsal)
  final String? tcNo;         // T.C. kimlik no (bireysel)
  final String? taxOffice;    // Vergi dairesi (kurumsal)
  final String? address;     // Fatura adresi (kurumsal)
  final String? email;       // Fatura e-postası
  final DateTime? savedAt;    // Kayıt tarihi (profil için)

  const InvoiceInfo({
    this.type = InvoiceType.individual,
    this.fullName,
    this.taxNumber,
    this.tcNo,
    this.taxOffice,
    this.address,
    this.email,
    this.savedAt,
  });

  /// Boş fatura bilgisi mi?
  bool get isEmpty =>
      fullName == null &&
      taxNumber == null &&
      tcNo == null &&
      taxOffice == null &&
      address == null &&
      email == null;

  /// Fatura bilgileri geçerli mi?
  /// Sadece temel format kontrolü yapar (uzunluk).
  /// Tam doğrulama (VKN/TCKN algoritması) backend'de yapılmalıdır.
  String? validate() {
    if (type == InvoiceType.corporate) {
      // Kurumsal: unvan ve vergi no zorunlu
      if (fullName == null || fullName!.trim().isEmpty) {
        return 'Fatura ünvanı girilmelidir';
      }
      if (taxNumber == null || taxNumber!.trim().isEmpty) {
        return 'Vergi numarası girilmelidir';
      }
      // Vergi no: 10 hane rakam olmalı (tüzel kişiler için)
      if (!_isNumeric(taxNumber!) || taxNumber!.length != 10) {
        return 'Vergi numarası 10 haneli rakam olmalıdır';
      }
    } else {
      // Bireysel: ad soyad ve T.C. no zorunlu
      if (fullName == null || fullName!.trim().isEmpty) {
        return 'Ad soyad girilmelidir';
      }
      if (tcNo == null || tcNo!.trim().isEmpty) {
        return 'T.C. kimlik numarası girilmelidir';
      }
      // T.C. no: 11 hane rakam olmalı
      if (!_isNumeric(tcNo!) || tcNo!.length != 11) {
        return 'T.C. kimlik numarası 11 haneli rakam olmalıdır';
      }
    }
    return null; // Geçerli
  }

  /// Basit numerik kontrol
  static bool _isNumeric(String str) {
    return RegExp(r'^\d+$').hasMatch(str);
  }

  factory InvoiceInfo.fromJson(Map<String, dynamic> json) {
    return InvoiceInfo(
      type: InvoiceType.fromString(json['invoice_type'] as String?),
      fullName: json['invoice_full_name'] as String?,
      taxNumber: json['invoice_tax_number'] as String?,
      tcNo: json['invoice_tc_no'] as String?,
      taxOffice: json['invoice_tax_office'] as String?,
      address: json['invoice_address'] as String?,
      email: json['invoice_email'] as String?,
      savedAt: json['invoice_saved_at'] != null
          ? DateTime.parse(json['invoice_saved_at'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'invoice_type': type.dbValue,
      'invoice_full_name': fullName,
      'invoice_tax_number': taxNumber,
      'invoice_tc_no': tcNo,
      'invoice_tax_office': taxOffice,
      'invoice_address': address,
      'invoice_email': email,
      'invoice_saved_at': savedAt?.toIso8601String(),
    };
  }

  /// Sadece sipariş için gerekli alanları (snapshot) döndürür
  Map<String, dynamic> toOrderSnapshot() {
    return {
      'invoice_type': type.dbValue,
      'invoice_full_name': fullName,
      'invoice_tax_number': taxNumber,
      'invoice_tc_no': tcNo,
      'invoice_tax_office': taxOffice,
      'invoice_address': address,
      'invoice_email': email,
    };
  }

  InvoiceInfo copyWith({
    InvoiceType? type,
    String? fullName,
    String? taxNumber,
    String? tcNo,
    String? taxOffice,
    String? address,
    String? email,
    DateTime? savedAt,
  }) {
    return InvoiceInfo(
      type: type ?? this.type,
      fullName: fullName ?? this.fullName,
      taxNumber: taxNumber ?? this.taxNumber,
      tcNo: tcNo ?? this.tcNo,
      taxOffice: taxOffice ?? this.taxOffice,
      address: address ?? this.address,
      email: email ?? this.email,
      savedAt: savedAt ?? this.savedAt,
    );
  }

  /// Vergi kimlik bilgisi (görüntüleme için)
  String? get taxIdDisplay {
    if (type == InvoiceType.corporate) {
      return taxNumber != null ? 'VN: $taxNumber' : null;
    } else {
      return tcNo != null ? 'TC: ${_maskTcNo(tcNo!)}' : null;
    }
  }

  /// T.C. no'yu gizli göster (son 4 hane görünür)
  static String _maskTcNo(String tc) {
    if (tc.length != 11) return tc;
    return '******${tc.substring(7)}';
  }

  /// Kurumsal bilgileri tek satırda göster
  String get displaySummary {
    final parts = <String>[];
    parts.add(type.label);
    if (fullName != null) parts.add(fullName!);
    if (type == InvoiceType.corporate && taxNumber != null) {
      parts.add('VN: $taxNumber');
    }
    if (type == InvoiceType.individual && tcNo != null) {
      parts.add('TC: ${_maskTcNo(tcNo!)}');
    }
    return parts.join(' • ');
  }
}
