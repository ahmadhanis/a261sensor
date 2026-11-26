import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqttapp/mqtt/mqtt_controller.dart';
import 'package:mqttapp/mqtt/settings.dart';

void main() {
  test(
    'live ${kIsWeb ? 'WebSocket' : 'TCP'} login and subscription (read only)',
    () async {
      final controller = MqttController();
      addTearDown(controller.dispose);
      final subscription = Completer<void>();
      controller.addListener(() {
        if (controller.subscribed && !subscription.isCompleted) {
          subscription.complete();
        }
      });
      await controller.connect(const BrokerSettings());
      expect(controller.state, BrokerState.connected, reason: controller.error);
      await subscription.future.timeout(const Duration(seconds: 10));
      expect(controller.error, isNull);
      controller.disconnect();
      expect(controller.state, BrokerState.disconnected);
    },
    skip: !const bool.fromEnvironment('MQTT_LIVE_TEST'),
  );
}
