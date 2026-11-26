# MQTT Sensor

A simple Flutter dashboard for the `esp32_ahmadhanis` sensor. Connect/disconnect,
watch temperature, humidity and reported relay state, publish messages, and inspect
the latest 100 incoming/outgoing payloads. No readings are simulated.

## Run

With Flutter installed:

```powershell
flutter pub get
flutter run -d chrome
```

For Windows use `flutter run -d windows`, or connect an Android device and use
`flutter run`. The Windows build requires Visual Studio's desktop C++ workload.

1. Join the broker's local network or VPN.
2. Click **Connect**. The app subscribes to `students/ahmadhanis/#`.
3. Wait for **Subscription confirmed**.
4. Sensor messages on `students/ahmadhanis/sensor` update the cards.
5. Use **Publish message** to send the editable sample, or select **Temperature only**.

## Broker defaults

| Setting | Value |
| --- | --- |
| Native TCP host / port | `10.19.5.233:1884` |
| Browser WebSocket URL | `ws://10.19.5.233:9001` |
| Username | `ahmadhanis` |
| Subscription | `students/ahmadhanis/#` |
| Publish topic | `students/ahmadhanis/sensor` |

The supplied password is prefilled and masked. Expand **Broker settings** to edit
the address or credentials while disconnected. Settings stay in memory for the
current app session. You can override the default password at build/run time with
`--dart-define=MQTT_PASSWORD=...`. A bundled password (including a Dart define) is
extractable from distributed apps; these defaults are for the supplied classroom broker.

Native apps use TCP; the web build uses MQTT over WebSockets through `mqtt_client`.
The local Flutter development server runs over HTTP, which works with the supplied
`ws://` broker. An HTTPS deployment needs a broker with `wss://` support because
browsers block insecure WebSockets from secure pages. Allow local-network access
if the browser requests it.

## Sensor payload

```json
{"device":"esp32_ahmadhanis","temperature_c":25.8,"humidity_pct":61.6,"relay":"OFF"}
```

The app also accepts `{"temp":25}`. Partial packets show a dash for missing
measurements. Non-JSON messages such as `{temp:25}` remain visible in the log and
leave the last valid reading unchanged. Only messages on the exact sensor topic
update the cards. Relay is a reported state; no relay command topic is assumed.
Retained deliveries are labeled, and previous readings are marked offline after
disconnection. The displayed timestamp is local receipt time, not device time.

Publishing supports raw text and JSON within `students/ahmadhanis/`, with optional
retain (off by default). Publishing uses QoS 0: **sent** means handed to the MQTT
client, not acknowledged by the sensor. The broker echo appears as a separate
received message. The app requests QoS 1 for subscriptions.

## Send from PowerShell

The payload in the question (`{temp:25}`) is not valid JSON. This version quotes
the key. `Read-Host` keeps the password out of command history:

```powershell
$mqttPassword = Read-Host 'MQTT password'
# Use a file to preserve JSON quotes across PowerShell versions.
$sensorPayload = Join-Path $env:TEMP 'mqttapp-sensor.json'
[System.IO.File]::WriteAllText($sensorPayload, '{"temp":25}', [System.Text.UTF8Encoding]::new($false))
mosquitto_pub -h 10.19.5.233 -p 1884 -u ahmadhanis -P $mqttPassword -t students/ahmadhanis/sensor -f $sensorPayload
Remove-Item -LiteralPath $sensorPayload
```

## Verify / build

```powershell
flutter analyze
flutter test
flutter build web
flutter build apk
```

Tests cover payload parsing, narrow-screen layout, publish validation and real
MQTT packet exchanges against an in-process loopback test broker (login,
subscription, UTF-8 echo, retained data, disconnect/reconnect, broker rejection,
and bounded history). They do not write to your real broker. To additionally
verify login and subscription to the supplied broker without publishing:

```powershell
flutter test --dart-define=MQTT_LIVE_TEST=true test/live_broker_test.dart
flutter test --platform chrome --dart-define=MQTT_LIVE_TEST=true test/live_broker_test.dart
```

Generate desktop/mobile UI previews in `build/previews/` with
`flutter test --update-goldens tool/render_preview_test.dart`.

Implementation: `lib/dashboard.dart` contains the UI, `lib/mqtt/mqtt_controller.dart`
handles MQTT state and messages, and conditional client imports select TCP or
browser WebSocket transport.
