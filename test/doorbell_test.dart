import 'package:flutter_test/flutter_test.dart';
import 'package:home_control/core/config.dart';
import 'package:home_control/ha/mobile_app.dart';

void main() {
  test('Klingel-Nachricht aus dem Push-Event', () {
    final m = DoorbellMessage.fromPush({
      'message': 'Es hat an der Haustür geläutet',
      'title': 'Türglocke',
      'data': {'duration': 45, 'camera': 'camera.haustuer', 'chime': 'none'},
    });
    expect(m.title, 'Türglocke');
    expect(m.message, 'Es hat an der Haustür geläutet');
    expect(m.duration, 45);
    expect(m.camera, 'camera.haustuer');
    expect(m.chime, isFalse);
    expect(m.clear, isFalse);
  });

  test('Minimal-Nachricht und clear_notification', () {
    final m = DoorbellMessage.fromPush({'message': 'Ding'});
    expect(m.title, 'Türglocke');
    expect((m.duration, m.chime, m.camera), (null, null, null));
    expect(DoorbellMessage.fromPush({'message': 'clear_notification'}).clear, isTrue);
  });

  test('Dienstname wie Home Assistant', () {
    expect(haSlug('Home Control MiTV-AFMU0'), 'home_control_mitv_afmu0');
    expect(haSlug('Hütte Küche'), 'hutte_kuche');
  });

  test('Tuerglocken-Konfiguration JSON', () {
    final d = DoorbellConfig(webhookId: 'abc', deviceName: 'TV', notifyService: 'mobile_app_tv', chimeRepeat: 2);
    final back = DoorbellConfig.fromJson(d.toJson());
    expect((back.webhookId, back.notifyService, back.chimeRepeat, back.durationSeconds), ('abc', 'mobile_app_tv', 2, 30));
    expect(DoorbellConfig.fromJson({}).isRegistered, isFalse);
  });
}
