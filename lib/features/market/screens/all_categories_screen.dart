// ignore_for_file: deprecated_member_use

import 'package:flutter/material.dart';
import '../../../core/models/category_model.dart';
import 'category_shops_screen.dart';

class AllCategoriesScreen extends StatelessWidget {
  final List<Category> categories;

  const AllCategoriesScreen({super.key, required this.categories});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Tüm Kategoriler',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Theme.of(context).colorScheme.primary,
        foregroundColor: Colors.white,
      ),
      body: categories.isEmpty
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.category_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text(
                    'Henüz kategori bulunmuyor',
                    style: TextStyle(fontSize: 16, color: Colors.grey),
                  ),
                ],
              ),
            )
          : GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.8,
              ),
              itemCount: categories.length,
              itemBuilder: (context, index) {
                final category = categories[index];
                return _buildCategoryCard(context, category);
              },
            ),
    );
  }

  Widget _buildCategoryCard(BuildContext context, Category category) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => CategoryShopsScreen(category: category),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          // Kategorinin kendi görselini kullan, yoksa varsayılan
          image: category.imageUrl != null
              ? DecorationImage(
                  image: NetworkImage(category.imageUrl!),
                  fit: BoxFit.cover,
                  colorFilter: ColorFilter.mode(
                    Colors.black.withOpacity(0.3),
                    BlendMode.darken,
                  ),
                )
              : null,
          color: category.imageUrl == null ? Colors.grey.shade300 : null,
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.black.withOpacity(category.imageUrl != null ? 0.1 : 0.2),
                Colors.black.withOpacity(category.imageUrl != null ? 0.5 : 0.4),
              ],
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              // Kategori ikonu varsa göster
              if (category.icon != null && category.imageUrl == null) ...[
                Icon(
                  _getIconFromString(category.icon!),
                  size: 32,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 4),
              ],
              Text(
                category.name,
                style: TextStyle(
                  color: category.imageUrl != null ? Colors.white : Colors.black87,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  height: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getIconFromString(String iconString) {
    switch (iconString.toLowerCase()) {
      case 'restaurant':
      case 'food':
        return Icons.restaurant;
      case 'shopping':
      case 'cart':
        return Icons.shopping_cart;
      case 'electronics':
        return Icons.devices;
      case 'fashion':
      case 'clothing':
        return Icons.checkroom;
      case 'grocery':
        return Icons.local_grocery_store;
      case 'pharmacy':
        return Icons.local_pharmacy;
      case 'home':
        return Icons.home;
      case 'car':
        return Icons.directions_car;
      case 'sports':
        return Icons.sports_soccer;
      case 'books':
        return Icons.book;
      case 'beauty':
        return Icons.face;
      case 'pet':
        return Icons.pets;
      case 'baby':
        return Icons.baby_changing_station;
      case 'gift':
        return Icons.card_giftcard;
      default:
        return Icons.category;
    }
  }
}
