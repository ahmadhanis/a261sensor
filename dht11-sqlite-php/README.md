# ESP32 DHT11 storage API

POST `https://slum78.myddns.me/iot/dht11/insertdht.php`

No API key, login, or token is required. This project only inserts readings.
Send `device_id`, `temperature` in Celsius and `humidity` in percent, using JSON or form data.
`device_id` is required and must contain 1–64 letters, numbers, underscores or hyphens.

```sh
curl -X POST 'https://slum78.myddns.me/iot/dht11/insertdht.php' \
  -H 'Content-Type: application/json' \
  -d '{"device_id":"esp32-01","temperature":28.5,"humidity":65}'
```

Success returns HTTP 201 with `success`, inserted `id`, `device_id`, `temperature`, `humidity`,
and server-generated `created_at` (UTC). Invalid readings/JSON return 400,
unsupported content types 415, non-POST requests 405, and database failures 500.
Numeric form values are accepted; humidity must be between 0 and 100.

SQLite database: `data/dht11.sqlite`, table `tbl_dht11`. PHP creates the database
and table on the first valid request. PHP needs PDO SQLite, and the web-server
user needs write access to `data/` and the database file.
The existing database has been migrated to include `device_id`; any readings from
before this change retain NULL for their unknown device ID. New requests require an ID.

## ESP32

Open `esp32_dht11/esp32_dht11.ino` in Arduino IDE. Install the ESP32 board package
by Espressif Systems, **DHT sensor library** by Adafruit, and **Adafruit Unified
Sensor** using the board/library managers. Select your ESP32 board and serial port.

Wire DHT11 VCC to 3.3V, GND to GND, and DATA to GPIO 4. For a bare sensor, add a
10 kΩ pull-up resistor between DATA and 3.3V; modules usually include one.
Change `DHT_PIN` if using another pin.
Set `DEVICE_ID` to a unique name for each board, such as `esp32-01` or `esp32-02`.
Upload the updated sketch so requests include the now-required device ID.

Upload the sketch and open Serial Monitor at 115200 baud. It joins
`myUUM_Guest` without a password, reads the sensor, and posts roughly every
10 seconds (plus request time). Failed sensor reads are skipped; Wi-Fi is retried
when disconnected. Readings are not queued while offline.

The sketch uses HTTPS with certificate verification disabled and no authentication.
If the guest network requires a browser captive-portal login, Wi-Fi association
alone will not provide API access; the device needs network access enabled first.

API references: [Espressif Wi-Fi](https://docs.espressif.com/projects/arduino-esp32/en/latest/api/wifi.html),
[Adafruit DHT example](https://github.com/adafruit/DHT-sensor-library/blob/master/examples/DHTtester/DHTtester.ino).
