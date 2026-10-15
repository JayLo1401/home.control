import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_control/core/config.dart';
import 'package:home_control/core/theme.dart';
import 'package:home_control/ha/ha_client.dart';
import 'package:home_control/ha/ha_entity.dart';
import 'package:home_control/panel/quick_panel.dart';

void main() {
  const text = '''
== Wohnzimmer
light.wohnzimmer
-- Whirlpool
switch.whirlpool_pumpe
sensor.whirlpool_temperatur
--
scene.kino

== Garten
-- Hütte
light.huette
''';

  test('Textformat: Panels, Gruppen und Entitaeten', () {
    final c = AppConfig()..panelsFromText(text);
    expect(c.panels.map((p) => p.name), ['Wohnzimmer', 'Garten']);
    final wz = c.panels.first.items;
    expect(wz, hasLength(3));
    expect((wz[0] as EntityItem).entityId, 'light.wohnzimmer');
    final g = wz[1] as GroupItem;
    expect(g.name, 'Whirlpool');
    expect(g.entities, ['switch.whirlpool_pumpe', 'sensor.whirlpool_temperatur']);
    expect((wz[2] as EntityItem).entityId, 'scene.kino');
    expect(c.panels.first.allEntities, hasLength(4));
  });

  test('Textformat: Taste und Lang-Druecken bleiben ueber den Namen erhalten', () {
    final c = AppConfig()..panelsFromText(text);
    c.panels.first
      ..keyCode = 82
      ..keyName = 'MENU'
      ..longPress = LongPressAction('switch.whirlpool_pumpe', mode: 'off');
    c.panelsFromText(c.panelsToText());
    expect(c.panels.first.keyCode, 82);
    expect(c.panels.first.longPress?.mode, 'off');
    expect(c.panelForKey(82)?.name, 'Wohnzimmer');
    expect(c.panels[1].keyCode, 0);
  });

  test('JSON-Roundtrip', () {
    final c = AppConfig()..panelsFromText(text);
    c.panels.first.longPress = LongPressAction('light.wohnzimmer', holdMs: 3000);
    final back = [for (final p in c.panels) PanelConfig.fromJson(p.toJson())];
    expect(back.first.longPress?.holdMs, 3000);
    expect((back.first.items[1] as GroupItem).entities, hasLength(2));
  });

  test('Lang-Druecken: Verb und Service', () {
    const on = HaEntity('switch.pumpe', 'on', {});
    const off = HaEntity('switch.pumpe', 'off', {});
    expect(longPressVerb(on, 'toggle'), 'ausgeschaltet');
    expect(longPressVerb(off, 'toggle'), 'eingeschaltet');
    expect(longPressVerb(on, 'on'), 'eingeschaltet');
    expect(longPressServiceFor(on, 'off')!.service, 'turn_off');
    expect(longPressServiceFor(const HaEntity('cover.markise', 'open', {}), 'off')!.service, 'close_cover');
    expect(longPressVerb(const HaEntity('scene.kino', 'unknown', {}), 'toggle'), 'ausgeführt');
  });

  testWidgets('Gruppenkachel zeigt Sensorwert und was an ist', (tester) async {
    final ha = HaClient();
    ha.states
      ..['sensor.temp'] = const HaEntity('sensor.temp', '35', {'unit_of_measurement': '°C'})
      ..['switch.pumpe'] = const HaEntity('switch.pumpe', 'on', {'friendly_name': 'Pumpe'});
    await tester.pumpWidget(MaterialApp(
      theme: buildTvTheme(),
      home: SizedBox(
        width: 300,
        height: 190,
        child: GroupTile(
          group: GroupItem('Whirlpool', ['switch.pumpe', 'sensor.temp']),
          ha: ha,
          selected: false,
          scale: 1,
        ),
      ),
    ));
    expect(find.text('Whirlpool'), findsOneWidget);
    expect(find.text('35 °C'), findsOneWidget);
    expect(find.text('An: Pumpe'), findsOneWidget);
  });
}
