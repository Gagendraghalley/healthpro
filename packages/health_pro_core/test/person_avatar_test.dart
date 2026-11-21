import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro_core/health_pro_core.dart';

void main() {
  test('initials: first and last name, one word, nothing', () {
    expect(PersonAvatar.initialsOf('Pema K Dorji'), 'PD');
    expect(PersonAvatar.initialsOf('  pema  '), 'P');
    expect(PersonAvatar.initialsOf(''), '?');
  });

  testWidgets('no photo shows their initials; a photo that won\'t load falls back to them', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Column(children: [
        PersonAvatar(name: 'Kuzu Bhutan'),
        PersonAvatar(name: 'Test Member', photoUrl: 'https://x.invalid/p.jpg'),
      ]),
    ));
    expect(find.text('KB'), findsOneWidget);
    expect(find.text('TM'), findsOneWidget);
    expect(find.byType(Image), findsOneWidget);
  });
}
