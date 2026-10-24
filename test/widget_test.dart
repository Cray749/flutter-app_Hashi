import 'package:flutter_test/flutter_test.dart';
import 'package:hashi_mobile/airport.dart';
import 'package:hashi_mobile/languages.dart';

void main() {
  test('17 passenger languages, every phrase has English and Japanese', () {
    expect(languages.length, 17);
    for (final p in phrases) {
      expect(p.length, 2);
      expect(p[0].isNotEmpty && p[1].isNotEmpty, true);
    }
  });
}
