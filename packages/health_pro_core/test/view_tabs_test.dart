import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro_core/health_pro_core.dart';

enum _V { a, b, c }

Future<void> _pumpTabs(WidgetTester tester, double width, ValueChanged<_V> onChanged) async {
  tester.view.physicalSize = Size(width, 400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: AppTheme.light,
    home: Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ViewTabs<_V>(
          selected: _V.a,
          onChanged: onChanged,
          tabs: const [
            ViewTab(value: _V.a, label: 'Bookings', icon: Icons.event_available_rounded, count: 4),
            ViewTab(value: _V.b, label: 'Registered', icon: Icons.groups_rounded, count: 12),
            ViewTab(value: _V.c, label: 'Timetable', icon: Icons.calendar_view_week_rounded),
          ],
        ),
      ),
    ),
  ));
}

void main() {
  testWidgets('a page\'s views: labels, icons and counts; another one opens it', (tester) async {
    _V? opened;
    await _pumpTabs(tester, 1200, (v) => opened = v);
    expect(find.text('Registered'), findsOneWidget);
    expect(find.text('12'), findsOneWidget);
    expect(find.byIcon(Icons.groups_rounded), findsOneWidget);
    await tester.tap(find.text('Registered'));
    expect(opened, _V.b);
    expect(tester.getSemantics(find.text('Bookings')),
        matchesSemantics(label: 'Bookings, 4', isButton: true, hasSelectedState: true, isSelected: true));
  });

  testWidgets('on a phone: the width shared, no icons, nothing overflows', (tester) async {
    await _pumpTabs(tester, 340, (_) {});
    expect(find.byIcon(Icons.groups_rounded), findsNothing);
    expect(find.text('Timetable'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
