/// `invoices` tablosunu yansıtan model — admin panelde fatura durumu
/// listelemek için kullanılır. Alıcı/fatura bilgisi (ad, VKN vb.) burada
/// tekrarlanmaz; ilgili sipariş (`orders`) üzerinden okunur.
class InvoiceModel {
  final String id;
  final String orderId;
  final String userId;
  final String? provider;
  final String? environment;
  final String status;
  final String? invoiceType;
  final String? externalId;
  final String? invoiceNumber;
  final double? kdvRate;
  final double? kdvAmount;
  final double? netAmount;
  final double? grossAmount;
  final String? pdfUrl;
  final String? ublXmlUrl;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime? queuedAt;
  final DateTime? sentAt;
  final DateTime? approvedAt;

  InvoiceModel({
    required this.id,
    required this.orderId,
    required this.userId,
    this.provider,
    this.environment,
    required this.status,
    this.invoiceType,
    this.externalId,
    this.invoiceNumber,
    this.kdvRate,
    this.kdvAmount,
    this.netAmount,
    this.grossAmount,
    this.pdfUrl,
    this.ublXmlUrl,
    this.errorMessage,
    required this.createdAt,
    this.queuedAt,
    this.sentAt,
    this.approvedAt,
  });

  factory InvoiceModel.fromJson(Map<String, dynamic> json) {
    return InvoiceModel(
      id: json['id'] as String,
      orderId: json['order_id'] as String,
      userId: json['user_id'] as String,
      provider: json['provider'] as String?,
      environment: json['environment'] as String?,
      status: json['status'] as String? ?? 'draft',
      invoiceType: json['invoice_type'] as String?,
      externalId: json['external_id'] as String?,
      invoiceNumber: json['invoice_number'] as String?,
      kdvRate: (json['kdv_rate'] as num?)?.toDouble(),
      kdvAmount: (json['kdv_amount'] as num?)?.toDouble(),
      netAmount: (json['net_amount'] as num?)?.toDouble(),
      grossAmount: (json['gross_amount'] as num?)?.toDouble(),
      pdfUrl: json['pdf_url'] as String?,
      ublXmlUrl: json['ubl_xml_url'] as String?,
      errorMessage: json['error_message'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      queuedAt: json['queued_at'] != null
          ? DateTime.parse(json['queued_at'] as String)
          : null,
      sentAt: json['sent_at'] != null
          ? DateTime.parse(json['sent_at'] as String)
          : null,
      approvedAt: json['approved_at'] != null
          ? DateTime.parse(json['approved_at'] as String)
          : null,
    );
  }
}
