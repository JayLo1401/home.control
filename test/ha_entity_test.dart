import 'package:flutter_test/flutter_test.dart';
import 'package:home_control/ha/ha_client.dart';
import 'package:home_control/ha/ha_entity.dart';

void main() {
  HaEntity e(String id, String state, [Map<String, dynamic> attrs = const {}]) => HaEntity(id, state, attrs);

  test('Lichter und Schalter werden getoggelt', () {
    final a = primaryAction(e('light.wohnzimmer', 'off'))!;
    expect((a.domain, a.service), ('light', 'toggle'));
    expect(primaryAction(e('switch.tv', 'on'))!.service, 'toggle');
  });

  test('Szenen ausfuehren, Schloss je nach Zustand', () {
    expect(primaryAction(e('scene.kino', 'unknown'))!.service, 'turn_on');
    expect(primaryAction(e('lock.tuer', 'locked'))!.service, 'unlock');
    expect(primaryAction(e('lock.tuer', 'unlocked'))!.service, 'lock');
  });

  test('Sensoren sind reine Statusanzeige', () {
    expect(primaryAction(e('sensor.temp', '21.5', {'unit_of_measurement': '°C'})), isNull);
    expect(stateLabel(e('sensor.temp', '21.5', {'unit_of_measurement': '°C'})), '21.5 °C');
  });

  test('Nicht verfuegbare Geraete nicht schalten', () {
    expect(primaryAction(e('light.flur', 'unavailable')), isNull);
  });

  test('Statustexte', () {
    expect(stateLabel(e('light.a', 'on', {'brightness': 128})), 'An · 50 %');
    expect(stateLabel(e('binary_sensor.fenster', 'on', {'device_class': 'window'})), 'Offen');
    expect(isActive(e('cover.rollo', 'open')), isTrue);
    expect(isActive(e('sensor.x', 'on')), isFalse);
  });

  test('URL wird normalisiert', () {
    expect(HaClient.normalizeUrl(' 192.168.1.10:8123/ '), 'http://192.168.1.10:8123');
    expect(HaClient.normalizeUrl('https://ha.local'), 'https://ha.local');
  });
}
