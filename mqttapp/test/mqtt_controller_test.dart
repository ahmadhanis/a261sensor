import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:mqttapp/mqtt/mqtt_controller.dart';
import 'package:mqttapp/mqtt/settings.dart';

import 'support/test_broker.dart';

Future<void> waitFor(bool Function() condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (!condition()) {
    if (DateTime.now().isAfter(deadline)) {
      fail('Timed out waiting for MQTT event');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late TestBroker broker;
  late MqttController controller;

  setUp(() async {
    broker = await TestBroker.start();
    controller = MqttController();
  });
  tearDown(() async {
    controller.dispose();
    await broker.close();
  });

  Future<void> connect() async {
    await controller.connect(
      BrokerSettings(host: '127.0.0.1', port: broker.port),
    );
  }

  test(
    'authenticates, subscribes, publishes UTF-8 and receives its echo',
    () async {
      await connect();
      await waitFor(() => controller.subscribed);
      expect(controller.state, BrokerState.connected);
      expect(broker.subscription, BrokerSettings.subscription);
      final connectText = utf8.decode(
        broker.connectBody!,
        allowMalformed: true,
      );
      expect(connectText, contains('ahmadhanis'));
      expect(connectText, contains(const BrokerSettings().password));
      controller.publish(
        BrokerSettings.sensorTopic,
        '{"temp":25,"device":"温度"}',
        retain: true,
      );
      await waitFor(() => controller.receivedCount == 1);
      expect(controller.reading!.temperature, 25);
      expect(controller.reading!.device, '温度');
      expect(controller.messages.first.outgoing, isFalse);
      expect(controller.sentCount, 1);
      expect(broker.lastPublishedHeader! & 1, 1);
    },
  );

  test('receives retained sensor data, preserves raw payloads, ignores other topics', () async {
    await connect();
    await waitFor(() => controller.subscribed);
    broker.publish(
      BrokerSettings.sensorTopic,
      BrokerSettings.samplePayload,
      retained: true,
    );
    await waitFor(() => controller.receivedCount == 1);
    expect(controller.reading!.humidity, 61.6);
    expect(controller.reading!.retained, isTrue);
    broker.publish(BrokerSettings.sensorTopic, '{temp:25}');
    broker.publish('${BrokerSettings.topicPrefix}status', '{"temp":99}');
    await waitFor(() => controller.receivedCount == 3);
    expect(controller.reading!.temperature, 25.8);
    expect(controller.messages[1].payload, '{temp:25}');
    controller.clearMessages();
    expect(controller.messages, isEmpty);
    expect(controller.receivedCount, 3);
  });

  test(
    'keeps the log bounded and rejects unsafe or disconnected publishes',
    () async {
      expect(
        () => controller.publish(BrokerSettings.sensorTopic, '{}'),
        throwsStateError,
      );
      await connect();
      await waitFor(() => controller.subscribed);
      expect(
        () => controller.publish('other/topic', '{}'),
        throwsFormatException,
      );
      expect(
        () => controller.publish(BrokerSettings.sensorTopic, ' '),
        throwsFormatException,
      );
      for (var i = 0; i < 105; i++) {
        broker.publish(BrokerSettings.sensorTopic, '{"temp":$i}');
      }
      await waitFor(() => controller.receivedCount == 105);
      expect(controller.messages.length, 100);
      expect(controller.reading!.temperature, 104);
      controller.disconnect();
      expect(controller.state, BrokerState.disconnected);
      expect(controller.subscribed, isFalse);
    },
  );

  test(
    'reports lost connections and can reconnect and subscribe again',
    () async {
      await connect();
      await waitFor(() => controller.subscribed);
      broker.dropConnections();
      await waitFor(() => !controller.isConnected);
      expect(controller.error, contains('Connection lost'));
      await connect();
      await waitFor(() => controller.subscribed);
      expect(controller.error, isNull);
    },
  );

  test('reports rejected credentials', () async {
    await broker.close();
    broker = await TestBroker.start(rejectLogin: true);
    await connect();
    expect(controller.state, BrokerState.failed);
    expect(controller.error, contains('Login rejected'));
  });

  test('does not claim a rejected subscription is active', () async {
    await broker.close();
    broker = await TestBroker.start(rejectSubscription: true);
    await connect();
    await waitFor(() => controller.error != null);
    expect(controller.isConnected, isTrue);
    expect(controller.subscribed, isFalse);
    expect(controller.error, contains('rejected the subscription'));
  });
}
