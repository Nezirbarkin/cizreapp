// ignore_for_file: avoid_relative_lib_imports

import 'package:flutter_test/flutter_test.dart';
import '../../lib/core/models/user_model.dart';
import '../helpers/test_helpers.dart';

void main() {
  group('User Model Tests', () {
    group('User.fromJson', () {
      test('should create User from valid JSON', () {
        final json = TestHelpers.createMockUserJson(
          id: 'user-123',
          email: 'test@example.com',
          fullName: 'Test User',
          username: 'testuser',
        );

        final user = User.fromJson(json);

        expect(user.id, equals('user-123'));
        expect(user.email, equals('test@example.com'));
        expect(user.fullName, equals('Test User'));
        expect(user.username, equals('testuser'));
        expect(user.role, equals(UserRole.customer));
        expect(user.status, equals(UserStatus.active));
        expect(user.isOnline, isTrue);
        expect(user.isGhostMode, isFalse);
      });

      test('should use default values for missing fields', () {
        final json = {
          'id': 'user-123',
          'email': 'test@example.com',
          'full_name': 'Test User',
          'created_at': '2024-01-01T00:00:00.000Z',
          'updated_at': '2024-01-01T00:00:00.000Z',
        };

        final user = User.fromJson(json);

        expect(user.role, equals(UserRole.customer));
        expect(user.status, equals(UserStatus.active));
        expect(user.isOnline, isFalse);
        expect(user.isGhostMode, isFalse);
        expect(user.username, isNull);
        expect(user.phone, isNull);
        expect(user.avatarUrl, isNull);
      });

      test('should parse all UserRole values correctly', () {
        for (final role in UserRole.values) {
          final json = TestHelpers.createMockUserJson(role: role.name);
          final user = User.fromJson(json);
          expect(user.role, equals(role), reason: 'Role: ${role.name}');
        }
      });

      test('should parse all UserStatus values correctly', () {
        for (final status in UserStatus.values) {
          final json = TestHelpers.createMockUserJson(status: status.name);
          final user = User.fromJson(json);
          expect(user.status, equals(status), reason: 'Status: ${status.name}');
        }
      });

      test('should default to customer role for invalid role', () {
        final json = TestHelpers.createMockUserJson(role: 'invalid_role');
        final user = User.fromJson(json);
        expect(user.role, equals(UserRole.customer));
      });

      test('should default to active status for invalid status', () {
        final json = TestHelpers.createMockUserJson(status: 'invalid_status');
        final user = User.fromJson(json);
        expect(user.status, equals(UserStatus.active));
      });
    });

    group('User.toJson', () {
      test('should convert User to JSON correctly', () {
        final user = TestHelpers.createMockUser(
          id: 'user-123',
          email: 'test@example.com',
          fullName: 'Test User',
          username: 'testuser',
          role: UserRole.seller,
        );

        final json = user.toJson();

        expect(json['id'], equals('user-123'));
        expect(json['email'], equals('test@example.com'));
        expect(json['full_name'], equals('Test User'));
        expect(json['username'], equals('testuser'));
        expect(json['role'], equals('seller'));
        expect(json['status'], equals('active'));
        expect(json['is_online'], isTrue);
      });
    });

    group('User.copyWith', () {
      test('should create copy with modified fields', () {
        final user = TestHelpers.createMockUser(
          id: 'user-123',
          email: 'test@example.com',
        );

        final modifiedUser = user.copyWith(
          fullName: 'Modified Name',
          role: UserRole.admin,
        );

        expect(modifiedUser.id, equals('user-123'));
        expect(modifiedUser.email, equals('test@example.com'));
        expect(modifiedUser.fullName, equals('Modified Name'));
        expect(modifiedUser.role, equals(UserRole.admin));
      });

      test('should keep original values when not specified', () {
        final user = TestHelpers.createMockUser();
        final copy = user.copyWith();

        expect(copy.id, equals(user.id));
        expect(copy.email, equals(user.email));
        expect(copy.fullName, equals(user.fullName));
        expect(copy.role, equals(user.role));
      });
    });

    group('User.toString', () {
      test('should return formatted string', () {
        final user = TestHelpers.createMockUser(
          id: 'user-123',
          email: 'test@example.com',
          fullName: 'Test User',
        );

        final str = user.toString();

        expect(str, contains('user-123'));
        expect(str, contains('test@example.com'));
        expect(str, contains('Test User'));
        expect(str, contains('customer'));
      });
    });
  });
}
