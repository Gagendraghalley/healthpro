import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro_core/health_pro_core.dart';

/// A page that opens [id] from [items], counting what it opened.
Widget _page(String? id, List<String>? items, List<String> opened) => MaterialApp(
      home: OpenFromLink<String>(
        id: id,
        items: items,
        idOf: (s) => s,
        open: opened.add,
        child: const SizedBox(),
      ),
    );

void main() {
  test('a link names a record with ?open=', () {
    expect(withOpen('/gyms/g1/manage/offers', 'o 1'), '/gyms/g1/manage/offers?open=o+1');
    expect(withOpen('/gyms/g1/manage/plans?new=1', 'p1'), '/gyms/g1/manage/plans?new=1&open=p1');
    expect(withOpen('/gyms/g1/manage/offers', null), '/gyms/g1/manage/offers');
  });

  testWidgets('opens the record once its list loads, and only once', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(_page('b', null, opened));
    await tester.pump();
    expect(opened, isEmpty, reason: 'still loading');

    await tester.pumpWidget(_page('b', ['a', 'b'], opened));
    await tester.pump();
    expect(opened, ['b']);

    // Saved, so the list loads again: not again.
    await tester.pumpWidget(_page('b', ['a', 'b', 'c'], opened));
    await tester.pump();
    expect(opened, ['b']);

    // Another record asked for on the same page.
    await tester.pumpWidget(_page('c', ['a', 'b', 'c'], opened));
    await tester.pump();
    expect(opened, ['b', 'c']);
  });

  testWidgets("a record that isn't there opens nothing, nor later", (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(_page('gone', ['a'], opened));
    await tester.pump();
    await tester.pumpWidget(_page('gone', ['a', 'gone'], opened));
    await tester.pump();
    expect(opened, isEmpty);
  });

  testWidgets('no link, nothing opens', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(_page(null, ['a'], opened));
    await tester.pump();
    expect(opened, isEmpty);
  });
}
