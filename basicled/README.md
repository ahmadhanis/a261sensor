# ESP32 Arduino Setup in VS Code

This project is an Arduino sketch for an ESP32 board. The steps below configure VS Code to verify and upload the sketch.

## 1. Install the required software

Install:

- [Arduino IDE 2.x](https://www.arduino.cc/en/software)
- [Visual Studio Code](https://code.visualstudio.com/)

In VS Code, install one Arduino extension. This workspace uses **Arduino Community Edition**:

- `vscode-arduino.vscode-arduino-community`

Disable other Arduino extensions while configuring the project, especially duplicate Arduino extensions and PlatformIO. They can provide competing board and upload commands.

## 2. Enable Arduino CLI mode

This workspace already contains `.vscode/settings.json` with:

```json
{
    "arduino.useArduinoCli": true
}
```

After changing this setting, run **Developer: Reload Window** from the VS Code Command Palette.

## 3. Install the ESP32 board package

1. Open the Arduino IDE.
2. Open **File > Preferences**.
3. Add this URL to **Additional boards manager URLs**:

   ```text
   https://raw.githubusercontent.com/espressif/arduino-esp32/gh-pages/package_esp32_index.json
   ```

4. Open **Tools > Board > Boards Manager**.
5. Search for `esp32`.
6. Install **esp32 by Espressif Systems**.

The package can also be installed with Arduino CLI:

```powershell
arduino-cli core update-index
arduino-cli core install esp32:esp32
```

If `arduino-cli` is not on `PATH`, use the CLI bundled with Arduino IDE. Its location is commonly:

```text
%LOCALAPPDATA%\Programs\Arduino IDE\resources\app\node_modules\arduino-ide-extension\build\arduino-cli.exe
```

## 4. Connect the ESP32

Use a USB cable that supports data, not charging only.

In Windows Device Manager, check **Ports (COM & LPT)** for a port such as `COM5`.

If no port appears:

- Try another USB cable and USB port.
- Install the USB-UART driver used by the board, commonly CP210x or CH340.
- Disconnect and reconnect the board.
- Close Arduino IDE Serial Monitor and other programs using the port.

## 5. Select the board and port in VS Code

1. Open `basicled.ino` in VS Code.
2. Press `Ctrl+Shift+P`.
3. Run **Arduino: Change Board Type**.
4. Select the exact ESP32 board. For a generic ESP32 DevKit, choose **ESP32 Dev Module**.
5. Run **Arduino: Select Serial Port**.
6. Select the COM port shown by Windows.
7. Run **Arduino: Rebuild IntelliSense Configuration**.

The board selection is saved in the workspace configuration. A typical configuration for an ESP32 Dev Module looks like this:

```json
{
    "board": "esp32:esp32:esp32",
    "port": "COM5",
    "sketch": "basicled.ino"
}
```

Replace `COM5` with the actual port. Do not use this FQBN if the board is a different ESP32 model; select the exact model from the board list instead.

## 6. Verify and upload

Use the Arduino toolbar buttons or the Command Palette:

- **Arduino: Verify** compiles the sketch.
- **Arduino: Upload** compiles and uploads the sketch.

You can also test with Arduino CLI:

```powershell
arduino-cli compile --fqbn esp32:esp32:esp32 .
arduino-cli upload -p COM5 --fqbn esp32:esp32:esp32 .
```

Replace `COM5` with the detected port.

For some ESP32 boards, hold the **BOOT** button while the upload starts, then release it when the upload begins. This is only needed when the board does not enter download mode automatically.

## 7. Programmer selection

A programmer is not required for normal USB upload. Leave it unset unless you are using **Upload Using Programmer** or **Burn Bootloader** with an external programmer.

If the programmer list is empty, first select the board type. Programmer options depend on the selected board and are not needed for the normal upload workflow.

## Troubleshooting

### Board list is empty

- Confirm `"arduino.useArduinoCli": true` is in `.vscode/settings.json`.
- Run **Developer: Reload Window**.
- Confirm the ESP32 package is installed in Boards Manager.
- Disable duplicate Arduino and PlatformIO extensions.

### Verify reports missing `Arduino.h`, `delay`, or `Serial`

- Run **Arduino: Rebuild IntelliSense Configuration**.
- Confirm the ESP32 board is selected, not an AVR/Uno board.
- Close and reopen the sketch after changing the board.

### Upload fails with a port or timeout error

- Select the current COM port again.
- Close Serial Monitor.
- Press and hold **BOOT** while starting the upload.
- Check that the selected board matches the physical ESP32 board.

### GPIO warning

This sketch uses GPIO 0 for the button and GPIO 2 for the LED. On many ESP32 boards these pins affect boot mode or are connected to onboard hardware. Do not hold the GPIO 0 button while resetting or powering on the board unless you intend to enter download mode.
