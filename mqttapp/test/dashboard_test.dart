import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mqttapp/dashboard.dart';
import 'package:mqttapp/main.dart';
import 'package:mqttapp/mqtt/mqtt_controller.dart';

void main() {
  testWidgets('validates settings even after the settings panel is collapsed', (
    tester,
  ) async {
    await tester.pumpWidget(const MainApp());
    await tester.tap(find.text('Broker settings'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('brokerPort')), '0');
    await tester.tap(find.text('Broker settings'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('connectionButton')));
    await tester.pumpAndSettle();
    expect(find.text('1–65535'), findsOneWidget);
    expect(find.text('Disconnected'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets(
    'starts disconnected with empty readings and publishing disabled',
    (tester) async {
      await tester.pumpWidget(const MainApp());
      expect(find.text('MQTT Sensor'), findsOneWidget);
      expect(find.text('Disconnected'), findsOneWidget);
      expect(find.text('Sensor overview'), findsOneWidget);
      final publish = tester.widget<FilledButton>(
        find.byKey(const Key('publishButton')),
      );
      expect(publish.onPressed, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('fits a narrow screen and validates publish topics', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final controller = MqttController()..state = BrokerState.connected;
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(home: Dashboard(controller: controller)),
    );
    await tester.ensureVisible(find.byKey(const Key('publishTopic')));
    await tester.enterText(
      find.byKey(const Key('publishTopic')),
      'other/sensor',
    );
    await tester.ensureVisible(find.byKey(const Key('publishButton')));
    await tester.tap(find.byKey(const Key('publishButton')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Use a topic inside'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
