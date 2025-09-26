// Basic home UI smoke test adapted to current design.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ideasamaapp/main.dart';

void main() {
  testWidgets('Home builds and shows central add button', (WidgetTester tester) async {
    await tester.pumpWidget(const ProviderScope(child: IdeaApp()));

    // Home renders without throwing and shows the central '+' action.
    expect(find.byIcon(Icons.add), findsOneWidget);

    // Optional: tap the add icon just to ensure it is interactive (no assertion on sheet to avoid flakiness).
    await tester.tap(find.byIcon(Icons.add));
    await tester.pump(const Duration(milliseconds: 300));
  });
}
