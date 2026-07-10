// Test helpers - Mock data and utilities for testing

// ignore_for_file: avoid_relative_lib_imports

import 'package:flutter_test/flutter_test.dart';
import '../../lib/core/models/user_model.dart';
import '../../lib/core/models/balance_model.dart';
import '../../lib/core/models/order_model.dart';

/// Test için kullanılan mock data yardımcıları
class TestHelpers {
  // ===== USER MOCK DATA =====
  
  static Map<String, dynamic> createMockUserJson({
    String? id,
    String? email,
    String? fullName,
    String? username,
    String? role,
    String? status,
  }) {
    return {
      'id': id ?? 'user-123',
      'email': email ?? 'test@example.com',
      'full_name': fullName ?? 'Test User',
      'username': username,
      'phone': '+905551234567',
      'avatar_url': 'https://example.com/avatar.jpg',
      'banner_url': 'https://example.com/banner.jpg',
      'bio': 'Test bio',
      'role': role ?? 'customer',
      'status': status ?? 'active',
      'is_online': true,
      'is_ghost_mode': false,
      'created_at': '2024-01-01T00:00:00.000Z',
      'updated_at': '2024-01-01T00:00:00.000Z',
    };
  }

  static User createMockUser({
    String? id,
    String? email,
    String? fullName,
    String? username,
    UserRole? role,
    UserStatus? status,
  }) {
    return User.fromJson(createMockUserJson(
      id: id,
      email: email,
      fullName: fullName,
      username: username,
      role: role?.name,
      status: status?.name,
    ));
  }

  // ===== BALANCE MOCK DATA =====
  
  static Map<String, dynamic> createMockBalanceJson({
    String? id,
    String? userId,
    double? balance,
    double? lockedBalance,
    double? totalEarned,
    double? totalSpent,
    double? totalRefunds,
    double? totalWithdrawn,
  }) {
    return {
      'id': id ?? 'balance-123',
      'user_id': userId ?? 'user-123',
      'balance': balance ?? 100.0,
      'locked_balance': lockedBalance ?? 10.0,
      'total_earned': totalEarned ?? 200.0,
      'total_spent': totalSpent ?? 80.0,
      'total_refunds': totalRefunds ?? 10.0,
      'total_withdrawn': totalWithdrawn ?? 20.0,
      'created_at': '2024-01-01T00:00:00.000Z',
      'updated_at': '2024-01-01T00:00:00.000Z',
    };
  }

  static UserBalance createMockBalance({
    String? id,
    String? userId,
    double? balance,
    double? lockedBalance,
    double? totalEarned,
    double? totalSpent,
    double? totalRefunds,
    double? totalWithdrawn,
  }) {
    return UserBalance.fromJson(createMockBalanceJson(
      id: id,
      userId: userId,
      balance: balance,
      lockedBalance: lockedBalance,
      totalEarned: totalEarned,
      totalSpent: totalSpent,
      totalRefunds: totalRefunds,
      totalWithdrawn: totalWithdrawn,
    ));
  }

  // ===== ORDER MOCK DATA =====
  
  static Map<String, dynamic> createMockOrderItemJson({
    String? id,
    String? orderId,
    String? productId,
    String? productName,
    double? price,
    int? quantity,
  }) {
    return {
      'id': id ?? 'item-123',
      'order_id': orderId ?? 'order-123',
      'product_id': productId ?? 'product-123',
      'product_name': productName ?? 'Test Product',
      'price': price ?? 25.0,
      'quantity': quantity ?? 2,
      'product_image_url': 'https://example.com/product.jpg',
      'shop_id': 'shop-123',
      'shop_name': 'Test Shop',
      'created_at': '2024-01-01T00:00:00.000Z',
    };
  }

  static Map<String, dynamic> createMockOrderJson({
    String? id,
    String? userId,
    String? shopId,
    String? status,
    String? paymentMethod,
    double? subtotal,
    double? deliveryFee,
    double? totalAmount,
    List<Map<String, dynamic>>? items,
  }) {
    return {
      'id': id ?? 'order-123',
      'user_id': userId ?? 'user-123',
      'shop_id': shopId ?? 'shop-123',
      'address_id': 'address-123',
      'order_number_int': 1,
      'subtotal': subtotal ?? 50.0,
      'discount_amount': 0.0,
      'delivery_fee': deliveryFee ?? 10.0,
      'total_amount': totalAmount ?? 60.0,
      'status': status ?? 'pending',
      'payment_method': paymentMethod ?? 'cash',
      'payment_status': 'pending',
      'order_items': items ?? [createMockOrderItemJson()],
      'delivery_notes': 'Test notes',
      'created_at': '2024-01-01T00:00:00.000Z',
      'updated_at': '2024-01-01T00:00:00.000Z',
      'address_display': 'Test Address',
      'shop_name': 'Test Shop',
    };
  }

  static Order createMockOrder({
    String? id,
    String? userId,
    String? shopId,
    OrderStatus? status,
    PaymentMethod? paymentMethod,
    double? subtotal,
    double? deliveryFee,
    double? totalAmount,
  }) {
    return Order.fromJson(createMockOrderJson(
      id: id,
      userId: userId,
      shopId: shopId,
      status: status?.name,
      paymentMethod: paymentMethod?.name,
      subtotal: subtotal,
      deliveryFee: deliveryFee,
      totalAmount: totalAmount,
    ));
  }
}