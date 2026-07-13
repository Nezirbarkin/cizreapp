class SmmProvider {
  final String id;
  final String ownerType; // 'admin' veya 'seller'
  final String ownerId; // admin: profiles.id, seller: shops.id
  final String name;
  final String apiUrl;
  final bool isActive;
  final DateTime createdAt;
  final DateTime updatedAt;

  // api_key bilerek modele dahil edilmedi: RLS/column-grant tarafında
  // client'a hiçbir zaman dönmüyor, sadece Edge Function service-role ile okuyabiliyor.

  SmmProvider({
    required this.id,
    required this.ownerType,
    required this.ownerId,
    required this.name,
    required this.apiUrl,
    required this.isActive,
    required this.createdAt,
    required this.updatedAt,
  });

  factory SmmProvider.fromJson(Map<String, dynamic> json) {
    return SmmProvider(
      id: json['id'] as String,
      ownerType: json['owner_type'] as String,
      ownerId: json['owner_id'] as String,
      name: json['name'] as String,
      apiUrl: json['api_url'] as String,
      isActive: json['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
  }
}
