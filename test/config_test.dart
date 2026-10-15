import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:home_control/core/config.dart';
import 'package:home_control/core/theme.dart';
import 'package:home_control/ha/entity_look.dart';
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

  test('Eigene Namen/Symbole: Textformat und Aufloesung', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await Mdi.load();
    final c = AppConfig()
      ..panelsFromText('== Garten\n-- Whirlpool\nswitch.pumpe | Pumpe | mdi:hot-tub\nsensor.temp\n--');
    expect(c.overrides['switch.pumpe']?.name, 'Pumpe');
    expect(c.panelsToText(), contains('switch.pumpe | Pumpe | mdi:hot-tub'));

    const e = HaEntity('switch.pumpe', 'on', {'friendly_name': 'Whirlpool Pumpe', 'icon': 'mdi:pump'});
    expect(entityName(c, 'switch.pumpe', e), 'Pumpe');
    expect(entityIcon(c, 'switch.pumpe', e), mdiIcon('mdi:hot-tub'));
    expect(mdiIcon('mdi:hot-tub'), isNotNull);

    // ohne eigenes Symbol: das in HA gesetzte
    c.setOverride('switch.pumpe', name: 'Pumpe');
    expect(entityIcon(c, 'switch.pumpe', e), mdiIcon('mdi:pump'));
    // "| |" entfernt eigene Werte wieder
    c.panelsFromText('== Garten\nswitch.pumpe | |');
    expect(c.overrides.containsKey('switch.pumpe'), isFalse);
    expect(entityName(c, 'switch.pumpe', e), 'Whirlpool Pumpe');
  });

  test('Gruppen-Sensoren im Textformat und JSON', () {
    final c = AppConfig()
      ..panelsFromText('== Garten\n-- Whirlpool\ntemperatur: sensor.wp_temp\nleistung: sensor.wp_watt\n'
          'switch.pumpe\n--');
    final g = c.panels.first.items.single as GroupItem;
    expect((g.temperature, g.humidity, g.power), ('sensor.wp_temp', null, 'sensor.wp_watt'));
    expect(g.entities, ['switch.pumpe']);
    expect(c.panelsToText(), contains('temperatur: sensor.wp_temp'));
    final back = PanelItem.fromJson(g.toJson()) as GroupItem;
    expect(back.power, 'sensor.wp_watt');
  });

  test('Sensoren aus Gruppen in die Ueberschrift uebernehmen', () {
    final c = AppConfig()
      ..panelsFromText('== P\n-- Whirlpool\nswitch.pumpe\nsensor.t1\nsensor.t2\nsensor.uv\nsensor.w\n--');
    final kinds = {'sensor.t1': 'temperature', 'sensor.t2': 'temperature', 'sensor.w': 'power'};
    expect(c.assignGroupSensors((id) => kinds[id]), isTrue);
    final g = c.panels.first.items.single as GroupItem;
    expect((g.temperature, g.humidity, g.power), ('sensor.t1', null, 'sensor.w'));
    // zweiter Temperatursensor und UV bleiben Kacheln
    expect(g.entities, ['switch.pumpe', 'sensor.t2', 'sensor.uv']);
  });

  test('Zahlen mit deutschem Komma', () {
    expect(formatNumber('21.52'), '21,5');
    expect(formatNumber('21.0'), '21');
    expect(formatNumber('0.6624'), '0,7');
    expect(formatNumber('1234.5'), '1235');
    expect(formatNumber('21.52', decimals: 1), '21,5');
    expect(formatNumber('45.4', decimals: 0), '45');
    expect(formatNumber('an'), isNull);
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

  HaClient haWithStates() {
    final ha = HaClient();
    ha.states
      ..['sensor.temp'] = const HaEntity('sensor.temp', '35', {'unit_of_measurement': '°C'})
      ..['switch.pumpe'] = const HaEntity('switch.pumpe', 'on', {'friendly_name': 'Whirlpool Pumpe Massagedüsen'})
      ..['light.licht'] = const HaEntity('light.licht', 'off', {'friendly_name': 'Licht'})
      ..['light.lose'] = const HaEntity('light.lose', 'off', {'friendly_name': 'Wohnzimmer'});
    return ha;
  }

  Widget panelApp(HaClient ha, int columns, GlobalKey<QuickPanelState> key) {
    final config = AppConfig(haUrl: 'http://x', token: 't', columns: columns, autoCloseSeconds: 0)
      ..panels = [
        PanelConfig('Garten', items: [
          EntityItem('light.lose'),
          GroupItem('Whirlpool', ['switch.pumpe', 'light.licht'])..temperature = 'sensor.temp',
        ]),
      ];
    return MaterialApp(
      theme: buildTvTheme(),
      home: Material(child: QuickPanel(key: key, ha: ha, config: config, panel: config.panels.first, onClose: () {})),
    );
  }

  testWidgets('Gruppe als Ueberschrift mit Temperatur, Kacheln darunter', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final key = GlobalKey<QuickPanelState>();
    await tester.pumpWidget(panelApp(haWithStates(), 4, key));
    expect(find.text('Whirlpool'), findsOneWidget);
    expect(find.text('35,0 °C'), findsOneWidget);
    expect(find.byType(EntityTile), findsNWidgets(3)); // lose Lampe + Pumpe + Licht

    // Runter springt von der losen Kachel in die Gruppe.
    key.currentState!.handleKey(PanelKey.down);
    await tester.pump();
    final tiles = tester.widgetList<EntityTile>(find.byType(EntityTile)).toList();
    expect(tiles.where((t) => t.selected).single.name, 'Whirlpool Pumpe Massagedüsen');
  });

  for (final cols in [2, 4, 6, 8]) {
    testWidgets('Kein Ueberlauf bei $cols Spalten', (tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(panelApp(haWithStates(), cols, GlobalKey()));
      expect(tester.takeException(), isNull);
    });
  }
}
