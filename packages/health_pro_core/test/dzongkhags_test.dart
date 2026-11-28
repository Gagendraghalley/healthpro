import 'package:flutter_test/flutter_test.dart';
import 'package:health_pro_core/health_pro_core.dart';

void main() {
  test('every main town is in one of the 20 dzongkhags, and each dzongkhag has one', () {
    expect({for (final (name, _, _) in dzongkhagTowns) name}, dzongkhags.toSet());
  });

  test('the dzongkhag a phone is in, from where it stands', () {
    expect(dzongkhagAt(27.4400, 89.6560), 'Thimphu'); // Olakha
    expect(dzongkhagAt(27.4290, 89.6500), 'Thimphu'); // Babesa
    expect(dzongkhagAt(27.4305, 89.4133), 'Paro');
    expect(dzongkhagAt(26.8520, 89.3900), 'Chhukha'); // Phuentsholing
    expect(dzongkhagAt(26.8700, 90.4850), 'Sarpang'); // Gelephu
    expect(dzongkhagAt(27.5490, 90.7520), 'Bumthang');
    expect(dzongkhagAt(27.3330, 91.5530), 'Trashigang');
  });

  test('outside Bhutan, none', () {
    expect(dzongkhagAt(22.5726, 88.3639), isNull); // Kolkata
    expect(dzongkhagAt(26.7271, 88.3953), isNull); // Siliguri
  });
}
