import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro_core/health_pro_core.dart';

void main() {
  test('every 3D icon the menu names is in assets/icons3d, with its licence', () {
    expect(Art3D.all.map((a) => a.name).toSet(), hasLength(Art3D.all.length), reason: 'no name twice');
    for (final art in Art3D.all) {
      expect(File(art.asset).existsSync(), isTrue, reason: art.asset);
    }
    expect(File('assets/icons3d/LICENSE.txt').existsSync(), isTrue);
    final files = Directory('assets/icons3d').listSync().where((f) => f.path.endsWith('.png')).length;
    expect(files, Art3D.all.length, reason: 'none left over');
  });
}
