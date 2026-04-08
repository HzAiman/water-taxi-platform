import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:operator_app/features/profile/presentation/pages/operator_presence_debug_page.dart';
import 'package:water_taxi_shared/water_taxi_shared.dart';

void main() {
  testWidgets('renders presence summary and current operator status', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();

    await firestore
        .collection(FirestoreCollections.operators)
        .doc('operator-1')
        .set({
          OperatorFields.operatorId: 'OP-1',
          OperatorFields.name: 'Captain Aiman',
          OperatorFields.email: 'captain@example.com',
          OperatorFields.isOnline: true,
        });
    await firestore
        .collection(FirestoreCollections.operatorPresence)
        .doc('operator-1')
        .set({
          OperatorPresenceFields.isOnline: true,
          OperatorPresenceFields.updatedAt: Timestamp.fromDate(DateTime.now()),
        });
    await firestore
        .collection(FirestoreCollections.operatorPresence)
        .doc('operator-2')
        .set({
          OperatorPresenceFields.isOnline: false,
          OperatorPresenceFields.updatedAt: Timestamp.fromDate(
            DateTime(2020, 1, 1, 0, 0),
          ),
        });

    await tester.pumpWidget(
      MaterialApp(
        home: OperatorPresenceDebugPage(
          firestore: firestore,
          currentOperatorId: 'operator-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Presence Summary'), findsOneWidget);
    expect(find.text('Current Operator'), findsOneWidget);
    expect(
      find.text(
        'operator_presence is authoritative. The profile document no longer stores online state.',
      ),
      findsOneWidget,
    );
    expect(find.text('Presence stored in operator_presence'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('Presence Documents'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Presence Documents'), findsOneWidget);
    expect(find.text('operator-2'), findsWidgets);
    expect(find.text('ONLINE'), findsOneWidget);
    expect(find.text('OFFLINE'), findsOneWidget);
    expect(find.text('Mark Stale Offline (Server Admin)'), findsOneWidget);
    expect(
      find.text(
        'Disabled in client app. Use the server-admin operation path for cleanup.',
      ),
      findsOneWidget,
    );
    expect(find.text('operator-1 (current)'), findsOneWidget);
    expect(find.text('STALE (>10 min)'), findsOneWidget);
  });

  testWidgets('presence debug page keeps presence authoritative', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();

    await firestore
        .collection(FirestoreCollections.operators)
        .doc('operator-1')
        .set({
          OperatorFields.operatorId: 'OP-1',
          OperatorFields.name: 'Captain Aiman',
          OperatorFields.email: 'captain@example.com',
          OperatorFields.isOnline: true,
        });
    await firestore
        .collection(FirestoreCollections.operatorPresence)
        .doc('operator-1')
        .set({
          OperatorPresenceFields.isOnline: false,
          OperatorPresenceFields.updatedAt: Timestamp.fromDate(
            DateTime(2026, 3, 15, 9, 59),
          ),
        });

    await tester.pumpWidget(
      MaterialApp(
        home: OperatorPresenceDebugPage(
          firestore: firestore,
          currentOperatorId: 'operator-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        'operator_presence is authoritative. The profile document no longer stores online state.',
      ),
      findsOneWidget,
    );
    expect(find.text('Presence stored in operator_presence'), findsOneWidget);

    final presenceSnap = await firestore
        .collection(FirestoreCollections.operatorPresence)
        .doc('operator-1')
        .get();

    expect(presenceSnap.data()?[OperatorPresenceFields.isOnline], isFalse);
  });

  testWidgets('dry-run preview lists stale online operators for server cleanup', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();

    await firestore
        .collection(FirestoreCollections.operators)
        .doc('operator-1')
        .set({
          OperatorFields.operatorId: 'OP-1',
          OperatorFields.name: 'Captain Aiman',
          OperatorFields.email: 'captain@example.com',
          OperatorFields.isOnline: true,
        });
    await firestore
        .collection(FirestoreCollections.operatorPresence)
        .doc('operator-1')
        .set({
          OperatorPresenceFields.isOnline: true,
          OperatorPresenceFields.updatedAt: Timestamp.fromDate(DateTime.now()),
        });
    await firestore
        .collection(FirestoreCollections.operatorPresence)
        .doc('operator-2')
        .set({
          OperatorPresenceFields.isOnline: true,
          OperatorPresenceFields.updatedAt: Timestamp.fromDate(
            DateTime(2020, 1, 1, 0, 0),
          ),
        });

    await tester.pumpWidget(
      MaterialApp(
        home: OperatorPresenceDebugPage(
          firestore: firestore,
          currentOperatorId: 'operator-1',
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Mark Stale Offline (Server Admin)'),
      150,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Will mark offline (1):'), findsOneWidget);
    expect(find.text('operator-2'), findsWidgets);
    expect(find.text('Mark Stale Offline (Server Admin)'), findsOneWidget);
    expect(
      find.text(
        'Disabled in client app. Use the server-admin operation path for cleanup.',
      ),
      findsOneWidget,
    );
  });
}
