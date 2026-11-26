# ESP32 + DHT11 + relay + Firebase

Simple Arduino demo, already configured for:

- Wi-Fi: `myUUM_Guest` (no password)
- Firebase: `https://iotprojects-62001-default-rtdb.asia-southeast1.firebasedatabase.app/`
- DHT11 DATA: D4 / GPIO 4
- Relay IN: D18 / GPIO 18
- Device ID: `esp32-01`

## Wiring

| Component | ESP32 connection |
| --- | --- |
| DHT11 VCC | 3V3 |
| DHT11 DATA | D4 / GPIO 4 |
| DHT11 GND | GND |
| Relay IN | D18 / GPIO 18 |
| Relay GND | GND (common with ESP32) |
| Relay VCC | Supply required by the module, commonly 5 V |

Use a relay module with a 3.3 V compatible input. A bare DHT11 needs a 4.7-10 kOhm pull-up from DATA to 3V3; many modules already have it.

## Upload

1. Install **esp32 by Espressif Systems** in Arduino IDE Boards Manager.
2. Install **DHT sensor library by Adafruit** and **Adafruit Unified Sensor** in Library Manager.
3. Open `arduino/esp32_dht11_relay_firebase/esp32_dht11_relay_firebase.ino`. Keep `firebase_ca.h` alongside the sketch; it provides HTTPS certificates.
4. Select **ESP32 Dev Module** and your serial port, then upload.
5. Open Serial Monitor at **115200 baud**.

All settings are at the top of the sketch. No API key, account, or separate config file is needed for this public-access demo. `RELAY_ACTIVE_LOW` defaults to `false`, matching the existing combined sensor/relay sketch in this repository. Set it to `true` if your relay module switches ON with LOW.

## Firebase

Set `DEVICE_ID` at the top of the sketch to a unique name for each ESP32, such as `esp32-01` or `esp32-02`. Use letters, digits, hyphens, or underscores.

The sketch updates temperature, humidity, and timestamp every 5 seconds under `/devices/esp32-01`:

```json
{
  "devices": {
    "esp32-01": {
      "temperature": 27.5,
      "humidity": 65,
      "timestamp": 1795651200000,
      "relay": false,
      "history": {
        "1795651199800": {
          "temperature": 27.5,
          "humidity": 65,
          "timestamp": 1795651200000
        }
      }
    }
  }
}
```

Temperature is Celsius and humidity is percent. In the Firebase Realtime Database console, add `/devices/esp32-01/relay` as a **boolean** (replace `esp32-01` if you changed `DEVICE_ID`). Set it to `true` to turn ON or `false` to turn OFF. The sketch checks it every 2 seconds. Sensor uploads preserve the relay command. You can import `firebase/database.example.json` into an empty database to create the initial fields.

`timestamp` is the time Firebase accepts the sensor upload, in milliseconds since the Unix epoch (UTC), using a [Firebase server timestamp](https://firebase.google.com/docs/database/rest/save-data#section-server-values). It updates with each successful sensor upload; a failed sensor read or upload leaves the previous timestamp unchanged. The example import starts it at `0` until the first upload.

Historical readings are stored at `/devices/esp32-01/history/<timestamp>`. Each key is the ESP32's NTP-synchronized sample time in Unix milliseconds. The `timestamp` inside the record is Firebase's server upload time, so it may differ slightly from the key. A single [multi-path PATCH](https://firebase.google.com/docs/database/rest/save-data#section-patch) updates the latest fields and adds the history record together, preserving earlier records and the relay command. No history is saved for failed sensor reads or failed uploads, and missed readings are not queued offline. History remains until you delete it. The example import leaves history empty; Firebase creates the path on the first successful upload.

If you published the earlier example rules, publish the revised `firebase/database.rules.json` to allow `history` writes; without permission, the entire sensor update will fail. The device fields replace the earlier root-level `/temperature`, `/humidity`, and `/relay` paths.

The relay starts OFF. Missing/invalid commands, failed command reads, or disconnected Wi-Fi switch it OFF when checked. If the stored command is still `true` when the connection returns, it switches ON again. HTTPS calls can delay checks by several seconds. Failed DHT reads leave the last uploaded sensor values unchanged.

The supplied database allowed an unauthenticated read when checked; write access has not been tested. If Serial Monitor reports HTTP **401/403**, review your database rules. `firebase/database.rules.json` allows public reads/writes on the four latest-value/control fields and history records under each device ID. Publish it in the Rules tab if you want this demo access, reviewing any existing rules first. Anyone who knows the URL can read those fields and control the relay under these public rules; add authentication before using it beyond a demo.

If the sketch waits at clock synchronization, check internet/NTP access. A guest Wi-Fi captive portal may need separate authorization.

Optional PlatformIO commands: `pio run` to compile, `pio run --target upload` to flash, and `pio device monitor` to view serial output.

## HTML dashboard

The `dashboard/dist` folder contains an HTML, CSS, and JavaScript dashboard with live readings, a history chart/table, CSV export, device selection, relay ON/OFF control, and on-demand Gemini analytics through Firebase AI Logic. Your supplied Firebase app configuration and Firebase Analytics are integrated. See `dashboard/README.md` for AI Logic/App Check setup; the sensor database remains unchanged.

Start it from this folder with `python -m http.server 8080 --directory dashboard/dist --bind 127.0.0.1`, then open `http://localhost:8080`. Publish the supplied Firebase rules to allow the individual data fields and history queries. The relay control shows the stored command, not physical contact feedback.

References: [Firebase REST API](https://firebase.google.com/docs/reference/rest/database), [Google HTTPS root certificates](https://pki.goog/roots.pem).
