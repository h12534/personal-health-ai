import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:personal_health_os/core/database/local_database.dart';

void main() {
  test('pending outbox count excludes synced records', () async {
    final database = LocalDatabase.forTesting(NativeDatabase.memory());
    final now = DateTime.utc(2026, 10, 2);
    try {
      await database.enqueue(
        OutboxRecord(
          id: 'pending-1',
          aggregateType: 'meal',
          aggregateLocalId: 'meal-1',
          operation: 'create',
          payload: const {'meal_type': 'lunch'},
          idempotencyKey: 'pending-key-1',
          createdAt: now,
        ),
      );
      await database.enqueue(
        OutboxRecord(
          id: 'synced-1',
          aggregateType: 'meal',
          aggregateLocalId: 'meal-2',
          operation: 'create',
          payload: const {'meal_type': 'dinner'},
          idempotencyKey: 'synced-key-1',
          createdAt: now,
        ),
      );
      await database.markOutboxSynced('synced-1');
      expect(await database.pendingOutboxCount(), 1);
      await database.clearPrivateData();
      expect(await database.pendingOutboxCount(), 0);
    } finally {
      await database.close();
    }
  });
}
