import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mqtt/mqtt_controller.dart';
import 'mqtt/settings.dart';

class Dashboard extends StatefulWidget {
  const Dashboard({super.key, this.controller});
  final MqttController? controller;

  @override
  State<Dashboard> createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  late final MqttController _mqtt = widget.controller ?? MqttController();
  final _settingsForm = GlobalKey<FormState>();
  final _publishForm = GlobalKey<FormState>();
  final _settingsExpansion = ExpansibleController();
  final _host = TextEditingController(text: const BrokerSettings().host);
  final _port = TextEditingController(text: '1884');
  final _webSocket = TextEditingController(
    text: const BrokerSettings().webSocketUrl,
  );
  final _username = TextEditingController(
    text: const BrokerSettings().username,
  );
  final _password = TextEditingController(
    text: const BrokerSettings().password,
  );
  final _topic = TextEditingController(text: BrokerSettings.sensorTopic);
  final _payload = TextEditingController(
    text: const JsonEncoder.withIndent('  ')
        .convert(jsonDecode(BrokerSettings.samplePayload)),
  );
  bool _showPassword = false;
  bool _retain = false;

  @override
  void dispose() {
    _settingsExpansion.dispose();
    if (widget.controller == null) _mqtt.dispose();
    for (final controller in [
      _host,
      _port,
      _webSocket,
      _username,
      _password,
      _topic,
      _payload,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _connect() {
    if (!_settingsForm.currentState!.validate()) {
      _settingsExpansion.expand();
      return;
    }
    _mqtt.connect(
      BrokerSettings(
        host: _host.text.trim(),
        port: int.tryParse(_port.text) ?? 1884,
        webSocketUrl: _webSocket.text.trim(),
        username: _username.text.trim(),
        password: _password.text,
      ),
    );
  }

  void _publish() {
    if (!_publishForm.currentState!.validate()) return;
    try {
      _mqtt.publish(_topic.text.trim(), _payload.text, retain: _retain);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Message sent (QoS 0). Watch for the broker echo below.',
          ),
        ),
      );
    } catch (error) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(error.toString())));
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _mqtt,
    builder: (context, _) {
      final theme = Theme.of(context);
      return Scaffold(
        body: SafeArea(
          child: SingleChildScrollView(
            padding: EdgeInsets.all(
              MediaQuery.sizeOf(context).width < 600 ? 16 : 32,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1160),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.sensors,
                            color: Colors.white,
                            size: 28,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'MQTT Sensor',
                                style: theme.textTheme.headlineSmall?.copyWith(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const Text(
                                'ahmadhanis / ESP32 monitor',
                                style: TextStyle(color: Color(0xFF596776)),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    _connectionCard(),
                    const SizedBox(height: 28),
                    Text(
                      'Sensor overview',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _mqtt.reading == null
                          ? 'Connect and publish sensor data to see your readings here.'
                          : '${_mqtt.reading!.device ?? 'Sensor'} · ${_mqtt.isConnected ? 'Last received' : 'Offline · last received'} '
                                '${_time(_mqtt.reading!.receivedAt)}${_mqtt.reading!.retained ? ' · retained message' : ''}',
                      style: const TextStyle(color: Color(0xFF596776)),
                    ),
                    const SizedBox(height: 16),
                    _sensorCards(),
                    const SizedBox(height: 24),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        if (constraints.maxWidth < 850) {
                          return Column(
                            children: [
                              _publisher(),
                              const SizedBox(height: 24),
                              _messageLog(),
                            ],
                          );
                        }
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(flex: 5, child: _publisher()),
                            const SizedBox(width: 24),
                            Expanded(flex: 6, child: _messageLog()),
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                    Text(
                      'MQTT 3.1.1 · ${kIsWeb ? 'WebSocket' : 'TCP'} · ${_mqtt.receivedCount} received · ${_mqtt.sentCount} sent',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );

  Widget _connectionCard() {
    final connecting = _mqtt.state == BrokerState.connecting;
    final locked = connecting || _mqtt.isConnected;
    final status = switch (_mqtt.state) {
      BrokerState.disconnected => 'Disconnected',
      BrokerState.connecting => 'Connecting…',
      BrokerState.connected => 'Connected',
      BrokerState.failed => 'Connection failed',
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _settingsForm,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 16,
                runSpacing: 14,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.circle,
                        size: 10,
                        color: _mqtt.isConnected
                            ? const Color(0xFF008577)
                            : const Color(0xFF768390),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        status,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  FilledButton.icon(
                    key: const Key('connectionButton'),
                    onPressed: connecting
                        ? null
                        : (_mqtt.isConnected ? _mqtt.disconnect : _connect),
                    icon: connecting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(_mqtt.isConnected ? Icons.link_off : Icons.link),
                    label: Text(
                      connecting
                          ? 'Connecting…'
                          : (_mqtt.isConnected ? 'Disconnect' : 'Connect'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const SelectableText(
                'Subscription: ${BrokerSettings.subscription}',
                style: TextStyle(fontFamily: 'monospace', fontSize: 14),
              ),
              if (_mqtt.isConnected) ...[
                const SizedBox(height: 6),
                Text(
                  _mqtt.subscribed
                      ? 'Subscription confirmed · listening for messages'
                      : 'Waiting for subscription confirmation…',
                ),
              ],
              if (_mqtt.error != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _mqtt.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              ExpansionTile(
                controller: _settingsExpansion,
                maintainState: true,
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(top: 8, bottom: 8),
                shape: const Border(),
                collapsedShape: const Border(),
                title: const Text(
                  'Broker settings',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                subtitle: Text(
                  kIsWeb ? _webSocket.text : '${_host.text}:${_port.text}',
                  style: const TextStyle(fontSize: 14),
                ),
                children: [
                  if (kIsWeb)
                    TextFormField(
                      controller: _webSocket,
                      enabled: !locked,
                      decoration: const InputDecoration(
                        labelText: 'WebSocket URL',
                      ),
                      validator: (value) {
                        final uri = Uri.tryParse(value?.trim() ?? '');
                        return uri != null &&
                                ['ws', 'wss'].contains(uri.scheme) &&
                                uri.host.isNotEmpty &&
                                (!uri.hasPort ||
                                    uri.port > 0 && uri.port <= 65535)
                            ? null
                            : 'Enter a valid ws:// or wss:// URL.';
                      },
                    )
                  else
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 3,
                          child: TextFormField(
                            controller: _host,
                            enabled: !locked,
                            decoration: const InputDecoration(
                              labelText: 'Broker host',
                            ),
                            validator: (value) =>
                                (value == null ||
                                    value.trim().isEmpty ||
                                    value.contains(RegExp(r'[\s/:]')))
                                ? 'Enter a hostname or IPv4 address.'
                                : null,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextFormField(
                            controller: _port,
                            key: const Key('brokerPort'),
                            enabled: !locked,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Port',
                            ),
                            validator: (value) {
                              final port = int.tryParse(value ?? '');
                              return port != null && port > 0 && port <= 65535
                                  ? null
                                  : '1–65535';
                            },
                          ),
                        ),
                      ],
                    ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _username,
                    enabled: !locked,
                    decoration: const InputDecoration(labelText: 'Username'),
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter your username.'
                        : null,
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _password,
                    enabled: !locked,
                    obscureText: !_showPassword,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        tooltip: _showPassword
                            ? 'Hide password'
                            : 'Show password',
                        onPressed: () =>
                            setState(() => _showPassword = !_showPassword),
                        icon: Icon(
                          _showPassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Use the same local network or VPN as the broker. Disconnect to edit settings.',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _sensorCards() {
    final reading = _mqtt.reading;
    final cards = [
      _metric(
        'Temperature',
        reading?.temperature?.toStringAsFixed(1) ?? '—',
        '°C',
        Icons.thermostat_outlined,
        const Color(0xFFB45309),
      ),
      _metric(
        'Humidity',
        reading?.humidity?.toStringAsFixed(1) ?? '—',
        '%',
        Icons.water_drop_outlined,
        const Color(0xFF2563EB),
      ),
      _metric(
        'Relay',
        reading?.relay ?? '—',
        '',
        Icons.power_settings_new,
        const Color(0xFF007F73),
      ),
    ];
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 550) {
          return Column(
            children: [
              for (final card in cards)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: card,
                ),
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 16),
              Expanded(child: cards[i]),
            ],
          ],
        );
      },
    );
  }

  Widget _metric(
    String label,
    String value,
    String unit,
    IconData icon,
    Color color,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: color, size: 28),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: Color(0xFF596776),
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 5),
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: value,
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      TextSpan(
                        text: ' $unit',
                        style: const TextStyle(fontSize: 18),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _publisher() => Card(
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Form(
        key: _publishForm,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Publish a message',
              style: Theme.of(context).textTheme.titleLarge
                  ?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            const Text(
              'Send a sensor sample or your own payload.',
              style: TextStyle(color: Color(0xFF596776)),
            ),
            const SizedBox(height: 22),
            TextFormField(
              key: const Key('publishTopic'),
              controller: _topic,
              decoration: const InputDecoration(labelText: 'Topic'),
              style: const TextStyle(fontFamily: 'monospace', fontSize: 14),
              validator: (value) =>
                  BrokerSettings.validatePublishTopic(value?.trim() ?? ''),
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('publishPayload'),
              controller: _payload,
              minLines: 6,
              maxLines: 12,
              autocorrect: false,
              enableSuggestions: false,
              style: const TextStyle(
                fontFamily: 'monospace',
                fontSize: 14,
                height: 1.6,
              ),
              decoration: const InputDecoration(
                labelText: 'Payload',
                alignLabelWithHint: true,
              ),
              validator: (value) => value == null || value.trim().isEmpty
                  ? 'Enter a message.'
                  : null,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () =>
                      _payload.text = const JsonEncoder.withIndent('  ')
                          .convert(jsonDecode(BrokerSettings.samplePayload)),
                  child: const Text('Sensor sample'),
                ),
                TextButton(
                  onPressed: () => _payload.text = '{"temp":25}',
                  child: const Text('Temperature only'),
                ),
              ],
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(
                'Retain message',
                style: TextStyle(fontSize: 15),
              ),
              subtitle: const Text(
                'Store the latest payload on the broker.',
                style: TextStyle(fontSize: 13),
              ),
              value: _retain,
              onChanged: (value) => setState(() => _retain = value),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                key: const Key('publishButton'),
                onPressed: _mqtt.isConnected ? _publish : null,
                icon: const Icon(Icons.send_outlined, size: 18),
                label: const Text('Publish message'),
              ),
            ),
            if (!_mqtt.isConnected)
              const Padding(
                padding: EdgeInsets.only(top: 10),
                child: Text(
                  'Connect to enable publishing.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF596776)),
                ),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _messageLog() {
    final messages = _mqtt.messages;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Message log',
                    style: Theme.of(context).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                TextButton(
                  onPressed: messages.isEmpty ? null : _mqtt.clearMessages,
                  child: const Text('Clear'),
                ),
              ],
            ),
            const Text(
              'Latest 100 messages · newest first',
              style: TextStyle(color: Color(0xFF596776), fontSize: 14),
            ),
            const SizedBox(height: 20),
            if (messages.isEmpty)
              const SizedBox(
                height: 310,
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.forum_outlined,
                        size: 42,
                        color: Color(0xFF83939F),
                      ),
                      SizedBox(height: 16),
                      Text(
                        'No messages yet',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Incoming and outgoing payloads appear here.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Color(0xFF596776)),
                      ),
                    ],
                  ),
                ),
              )
            else
              SizedBox(
                height: 440,
                child: ListView.separated(
                  itemCount: messages.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 28),
                  itemBuilder: (context, index) => _message(messages[index]),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _message(MessageEntry entry) {
    String formatted = entry.payload;
    try {
      formatted = const JsonEncoder.withIndent('  ')
          .convert(jsonDecode(entry.payload));
    } on FormatException {
      /* Display non-JSON unchanged. */
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              entry.outgoing ? Icons.upload_outlined : Icons.download_outlined,
              size: 17,
              color: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                '${entry.outgoing ? 'SENT · QoS 0' : 'RECEIVED'}${entry.retained ? ' · retained' : ''}',
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              _time(entry.time),
              style: const TextStyle(fontSize: 12, color: Color(0xFF596776)),
            ),
            IconButton(
              tooltip: 'Copy payload',
              visualDensity: VisualDensity.compact,
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: entry.payload));
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Payload copied.')),
                  );
                }
              },
              icon: const Icon(Icons.copy_outlined, size: 16),
            ),
          ],
        ),
        SelectableText(
          entry.topic,
          style: const TextStyle(
            fontSize: 13,
            fontFamily: 'monospace',
            color: Color(0xFF596776),
          ),
        ),
        const SizedBox(height: 10),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF5F7F9),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SelectableText(
            formatted,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 13,
              height: 1.5,
            ),
          ),
        ),
      ],
    );
  }

  String _time(DateTime time) =>
      '${time.hour.toString().padLeft(2, '0')}:'
      '${time.minute.toString().padLeft(2, '0')}:${time.second.toString().padLeft(2, '0')}';
}
