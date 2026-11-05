import 'package:flutter_test/flutter_test.dart';
import 'package:home_control/core/update_service.dart';

void main() {
  AvailableUpdate u(String v, [int? code]) => AvailableUpdate(version: v, versionCode: code, url: '');

  test('Versionen numerisch vergleichen', () {
    expect(compareVersions('1.10.0', '1.9.2'), greaterThan(0));
    expect(compareVersions('1.0.0', '1.0.0+5'), 0);
    expect(compareVersions('1.0.1', '1.1'), lessThan(0));
  });

  test('versionCode entscheidet, Versionsnummer darf nicht sinken', () {
    expect(isNewer(u('1.0.1', 105), '1.0.0', 2), isTrue);
    expect(isNewer(u('1.0.1', 105), '1.0.1', 104), isTrue); // gleiche Version neu gebaut
    expect(isNewer(u('1.0.1', 105), '1.0.1', 105), isFalse);
    expect(isNewer(u('1.0.0', 200), '1.0.1', 105), isFalse);
  });

  test('ohne versionCode zaehlt die Versionsnummer', () {
    expect(isNewer(u('1.0.1'), '1.0.0', 2), isTrue);
    expect(isNewer(u('1.0.0'), '1.0.0', 2), isFalse);
  });
}
