import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:mqtt_client/mqtt_client.dart';

import 'client_factory.dart';
import 'sensor_reading.dart';
import 'settings.dart';

enum BrokerState { disconnected, connecting, connected, failed }

class MessageEntry {
  MessageEntry({
    required this.topic,
    required this.payload,
    this.outgoing = false,
    this.retained = false,
  }) : time = DateTime.now();

  final String topic;
  final String payload;
  final bool outgoing;
  final bool retained;
  final DateTime time;
}

class MqttController extends ChangeNotifier {
  MqttClient? _client;
  StreamSubscription<List<MqttReceivedMessage<MqttMessage>>>? _updates;
  Timer? _subscriptionTimeout;
  bool _disposed = false;
  int _generation = 0;
  final List<MessageEntry> _messages = [];

  BrokerState state = BrokerState.disconnected;
  bool subscribed = false;
  String? error;
  SensorReading? reading;
  int receivedCount = 0;
  int sentCount = 0;

  bool get isConnected => state == BrokerState.connected;
  List<MessageEntry> get messages => List.unmodifiable(_messages);

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> connect(BrokerSettings settings) async {
    if (_disposed || isConnected || state == BrokerState.connecting) return;
    final generation = ++_generation;
    state = BrokerState.connecting;
    subscribed = false;
    error = null;
    reading = null;
    _notify();
    final id = 'ahan_${Random.secure().nextInt(0x7fffffff).toRadixString(16)}';
    final client = createMqttClient(settings, id);
    _client = client;
    bool current() => !_disposed && generation == _generation;
    client
      ..logging(on: false)
      ..setProtocolV311()
      ..keepAlivePeriod = 20
      ..connectTimeoutPeriod = 8000
      ..connectionMessage = MqttConnectMessage()
          .withClientIdentifier(id)
          .startClean()
      ..onDisconnected = () {
        if (!current() || state == BrokerState.connecting) return;
        _subscriptionTimeout?.cancel();
        subscribed = false;
        state = BrokerState.disconnected;
        error = 'Connection lost. Check your network, then connect again.';
        _notify();
      }
      ..onSubscribed = (topic) {
        if (!current()) return;
        _subscriptionTimeout?.cancel();
        subscribed = true;
        error = null;
        _notify();
      }
      ..onSubscribeFail = (topic) {
        if (!current()) return;
        _subscriptionTimeout?.cancel();
        subscribed = false;
        error = 'The broker rejected the subscription to $topic.';
        _notify();
      };

    try {
      await client
          .connect(settings.username, settings.password)
          .timeout(const Duration(seconds: 12));
      if (!current()) {
        client.disconnect();
        return;
      }
      if (client.connectionStatus?.state != MqttConnectionState.connected) {
        throw StateError(
          'Broker response: ${client.connectionStatus?.returnCode}',
        );
      }
      state = BrokerState.connected;
      await _updates?.cancel();
      _updates = client.updates!.listen((updates) {
        if (!current()) return;
        for (final update in updates) {
          final message = update.payload;
          if (message is! MqttPublishMessage) continue;
          final payload = utf8.decode(
            message.payload.message,
            allowMalformed: true,
          );
          final retained = message.header?.retain ?? false;
          _addMessage(
            MessageEntry(
              topic: update.topic,
              payload: payload,
              retained: retained,
            ),
          );
          receivedCount++;
          if (update.topic == BrokerSettings.sensorTopic) {
            // Each card represents this packet; missing values never masquerade
            // as measurements from the latest device message.
            final parsed = SensorReading.parse(payload, retained: retained);
            if (parsed != null) reading = parsed;
          }
        }
        _notify();
      });
      _subscriptionTimeout = Timer(const Duration(seconds: 8), () {
        if (!current() || subscribed) return;
        error = 'Subscription was not confirmed. Reconnect to try again.';
        _notify();
      });
      client.subscribe(BrokerSettings.subscription, MqttQos.atLeastOnce);
      _notify();
    } catch (_) {
      final code = client.connectionStatus?.returnCode;
      _subscriptionTimeout?.cancel();
      client.onDisconnected = null;
      client.disconnect();
      if (!current()) return;
      state = BrokerState.failed;
      subscribed = false;
      error =
          code == MqttConnectReturnCode.badUsernameOrPassword ||
              code == MqttConnectReturnCode.notAuthorized
          ? 'Login rejected. Check the username and password in broker settings.'
          : 'Could not connect. Check the broker address, credentials, and local '
                'network access. Web browsers require ws:// or wss://.';
      _notify();
    }
  }

  void publish(String topic, String payload, {bool retain = false}) {
    final topicError = BrokerSettings.validatePublishTopic(topic);
    if (topicError != null) throw FormatException(topicError);
    if (!isConnected || _client == null) {
      throw StateError('Connect to the broker first.');
    }
    if (payload.trim().isEmpty) throw const FormatException('Enter a message.');
    final builder = MqttClientPayloadBuilder()..addUTF8String(payload);
    // QoS 0 is a send attempt, not an acknowledgement from the device.
    _client!.publishMessage(
      topic,
      MqttQos.atMostOnce,
      builder.payload!,
      retain: retain,
    );
    _addMessage(
      MessageEntry(
        topic: topic,
        payload: payload,
        outgoing: true,
        retained: retain,
      ),
    );
    sentCount++;
    _notify();
  }

  void _addMessage(MessageEntry entry) {
    _messages.insert(0, entry);
    if (_messages.length > 100) _messages.removeLast();
  }

  void clearMessages() {
    _messages.clear();
    _notify();
  }

  void disconnect() {
    ++_generation;
    _subscriptionTimeout?.cancel();
    _updates?.cancel();
    _updates = null;
    _client?.onDisconnected = null;
    _client?.disconnect();
    _client = null;
    subscribed = false;
    state = BrokerState.disconnected;
    error = null;
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    disconnect();
    super.dispose();
  }
}
