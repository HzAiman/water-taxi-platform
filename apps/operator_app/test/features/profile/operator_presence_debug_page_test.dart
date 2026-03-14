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

    await firestore.collection(FirestoreCollections.operators).doc('operator-1').set({
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
      OperatorPresenceFields.updatedAt: Timestamp.fromDate(DateTime(2026, 3, 15, 10, 0)),
    });
    await firestore
        .collection(FirestoreCollections.operatorPresence)
        .doc('operator-2')
        .set({
      OperatorPresenceFields.isOnline: false,
      OperatorPresenceFields.updatedAt: Timestamp.fromDate(DateTime(2020, 1, 1, 0, 0)),
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
    expect(find.text('Presence Documents'), findsOneWidget);
    expect(find.text('operator-2'), findsOneWidget);
    expect(find.text('ONLINE'), findsOneWidget);
    expect(find.text('OFFLINE'), findsOneWidget);
    expect(find.text('operator-1 (current)'), findsOneWidget);
    expect(find.text('Presence sync looks consistent for this operator.'), findsOneWidget);
    expect(find.text('Sync My Presence Now'), findsOneWidget);
    expect(find.text('STALE (>10 min)'), findsOneWidget);
  });

  testWidgets('sync action updates operator_presence from profile isOnline', (
    tester,
  ) async {
    final firestore = FakeFirebaseFirestore();

    await firestore.collection(FirestoreCollections.operators).doc('operator-1').set({
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
      OperatorPresenceFields.updatedAt: Timestamp.fromDate(DateTime(2026, 3, 15, 9, 59)),
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

    expect(find.textContaining('mismatch detected'), findsOneWidget);

    await tester.tap(find.text('Sync My Presence Now'));
    await tester.pumpAndSettle();

    final presenceSnap = await firestore
        .collection(FirestoreCollections.operatorPresence)
        .doc('operator-1')
        .get();

    expect(presenceSnap.data()?[OperatorPresenceFields.isOnline], isTrue);
    expect(find.textContaining('Presence synced to online'), findsOneWidget);
  });
}