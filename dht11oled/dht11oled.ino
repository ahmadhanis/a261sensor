#include <Arduino.h>
#include <DHT.h>
#include <Wire.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>

// DHT sensor
#define DHTPIN 4
#define DHTTYPE DHT11  // Change to DHT22 if needed

// 0.91-inch OLED: 128 x 32 pixels
#define SCREEN_WIDTH 128
#define SCREEN_HEIGHT 32
#define OLED_ADDRESS 0x3C
#define OLED_SDA 21
#define OLED_SCL 22

DHT dht(DHTPIN, DHTTYPE);

Adafruit_SSD1306 display(
  SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1
);

void setup() {
  Serial.begin(115200);
  dht.begin();

  Wire.begin(OLED_SDA, OLED_SCL);

  if (!display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDRESS)) {
    Serial.println("OLED initialization failed!");
    while (true) {
      delay(1000);
    }
  }

  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setTextWrap(false);
  display.setCursor(0, 0);
  display.println("ESP32 DHT Monitor");
  display.setCursor(0, 16);
  display.println("Reading sensor...");
  display.display();

  Serial.println("ESP32 Temperature & Humidity Monitor");
}

void loop() {
  delay(2000);

  float humidity = dht.readHumidity();
  float temperature = dht.readTemperature();

  display.clearDisplay();
  display.setTextSize(1);

  if (isnan(humidity) || isnan(temperature)) {
    Serial.println("Failed to read from DHT sensor!");

    display.setCursor(0, 0);
    display.println("Sensor read failed!");
    display.setCursor(0, 16);
    display.println("Check DHT wiring.");
    display.display();
    return;
  }

  // Serial output
  Serial.print("Temperature: ");
  Serial.print(temperature, 1);
  Serial.println(" C");

  Serial.print("Humidity: ");
  Serial.print(humidity, 1);
  Serial.println(" %");

  // OLED title
  display.setCursor(0, 0);
  display.print("ESP32 DHT Monitor");
  display.drawLine(0, 9, 127, 9, SSD1306_WHITE);

  // Temperature
  display.setCursor(0, 13);
  display.print("Temp: ");
  display.print(temperature, 1);
  display.print(" C");

  // Humidity
  display.setCursor(0, 24);
  display.print("Humidity: ");
  display.print(humidity, 1);
  display.print(" %");

  display.display();
}