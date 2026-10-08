
#include <Arduino.h>
#include <DHT.h>

// Sensor configuration
#define DHTPIN 4
#define DHTTYPE DHT11  // Change to DHT22 if using DHT22

// Create DHT object
DHT dht(DHTPIN, DHTTYPE);

void setup() {
  Serial.begin(115200);

  // Initialize sensor
  dht.begin();

  Serial.println("ESP32 Temperature & Humidity Monitor");
  Serial.println("------------------------------------");
}

void loop() {
  // Wait 2 seconds between readings
  delay(2000);

  // Read humidity and temperature
  float humidity = dht.readHumidity();
  float temperature = dht.readTemperature();

  // Check if reading failed
  if (isnan(humidity) || isnan(temperature)) {
    Serial.println("Failed to read from DHT sensor!");
    return;
  }

  // Display results
  Serial.print("Temperature: ");
  Serial.print(temperature, 1);
  Serial.println(" °C");

  Serial.print("Humidity: ");
  Serial.print(humidity, 1);
  Serial.println(" %");

  Serial.println("------------------------------------");
}
