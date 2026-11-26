# Fieldwork sensor dashboard

Plain HTML, CSS, and JavaScript. No npm build or framework is needed. The Firebase web SDK is loaded from Google's CDN for Firebase Analytics and Gemini through Firebase AI Logic.

## Open locally

From this project's root folder, run:

```powershell
python -m http.server 8080 --directory dashboard/dist --bind 127.0.0.1
```

Open `http://localhost:8080`. Use a local server for the ES modules required by the Gemini panel; opening the HTML directly from disk will not load those modules reliably.

## Files

- `dist/index.html`: dashboard layout.
- `dist/styles.css`: responsive styling.
- `dist/app.js`: Firebase reads, relay commands, history chart, and CSV download. Change `CONFIG.databaseUrl` or `CONFIG.defaultDevice` here if needed.
- `dist/firebase-client.js`: your supplied Firebase app configuration, optional Firebase Analytics initialization, Gemini model setting, and optional App Check site key.
- `dist/analytics.js`: on-demand Gemini analysis and its UI.
- `dist/analysis-data.js`: measured statistics, bounded sampling, analysis instructions, and output validation.

The device defaults to `esp32-01`. Enter another device ID and press **Connect** to switch; the choice is remembered in your browser. The dashboard refreshes every 5 seconds and lets you pause automatic refresh or refresh manually. History requests fetch only the selected latest 100, 300, or 1,000 records; the table shows newest first and CSV includes all fetched records. Chart statistics apply to the fetched records.

Latest values are read individually from `/devices/<device-id>/temperature`, `humidity`, `timestamp`, and `relay`. History comes from `/devices/<device-id>/history`, queried by its timestamp keys (`orderBy="$key"`) without requiring a custom Firebase index. Fetched rows are sorted by their stored server timestamp for display. The supplied `firebase/database.rules.json` supports the dashboard without granting reads to the whole device or database. Publish that rules file if you have not already done so. Times are shown in the browser's local timezone; CSV also includes UTC and Unix milliseconds.

The ON/OFF buttons write only the boolean `/devices/<device-id>/relay`. They show the command confirmed by Firebase. The firmware polls it every 2 seconds; physical relay feedback is not available. A stale or disconnected device may apply a saved ON command when it reconnects. Freshness is inferred from the sensor timestamp (30-second threshold), not a hardware heartbeat.

No sample readings are displayed as live data. Empty, stale, disconnected, and permission-denied states are shown explicitly. Google Fonts is optional and falls back to a local sans-serif font.

## Firebase app and Gemini analytics

Firebase app settings for **ai-projects-abf22** are in `dist/firebase-client.js`, using Firebase SDK **13.4.0**. The API key has been removed and is blank. Gemini analysis and Firebase Analytics stay disabled until a Firebase web API key is configured. When configured, Firebase Analytics initializes with the measurement ID when supported; blocked or unsupported Analytics does not stop the dashboard. Sensor readings and relay commands continue using **iotprojects-62001**, the existing Realtime Database in `app.js`. No sensor data is moved to the AI project.

The configuration's Firebase API key identifies the web app. It is not used as a direct Gemini API key. This integration uses [Firebase AI Logic](https://firebase.google.com/docs/ai-logic/get-started?platform=web), which supports Gemini calls from web apps without embedding a separate Gemini credential.

1. Add the Firebase web app's API key to `firebaseConfig.apiKey` in `firebase-client.js` if you want to enable the feature.
2. In the [ai-projects-abf22 AI Logic console](https://console.firebase.google.com/project/ai-projects-abf22/ailogic), complete **Get started**, choose **Gemini Developer API**, and enable the required services.
3. If App Check is enforced, register the web app with reCAPTCHA Enterprise and add the public site key to `AI_CONFIG.appCheckSiteKey` in `firebase-client.js`. Include the hosted dashboard domain in its allowed domains. Follow the [App Check debug provider guide](https://firebase.google.com/docs/app-check/web/debug-provider) for local development; do not disable enforcement or commit debug tokens.
4. Open the dashboard over HTTP/HTTPS, wait for at least 3 saved readings, then click **Analyze readings**.

The model defaults to [gemini-3.5-flash-lite](https://firebase.google.com/docs/ai-logic/models); change `AI_CONFIG.model` to another supported model if needed. It summarizes temperature/humidity trends, unusual changes, suggested checks, and limitations. It does not change the relay. Model output is displayed as text and validated before being shown.

Analysis runs only when clicked, never on the 5-second sensor refresh. All selected readings (up to 1,000) contribute to computed statistics; up to 200 evenly spaced time-series points, the device ID, latest values/relay command, and timestamps are sent to Google through Firebase AI Logic. The report records its analyzed snapshot and flags newer readings. It is not stored in Firebase or automatically applied to relay control. Turning off page Analytics via `AI_CONFIG.analyticsEnabled` does not turn off Gemini requests that you explicitly make.

If AI Logic is not enabled, App Check rejects the app, the model is unavailable, or quota is exhausted, the panel reports that error; it never substitutes a fabricated AI report. No `.env` file or separate Gemini key is required for this Firebase AI Logic integration.

Firebase access follows the existing public demo rules. Anyone with the database URL can access those allowed paths; the website's audience does not change Firebase's rules.

See [Firebase REST queries](https://firebase.google.com/docs/database/rest/retrieve-data#filtering-data) for the history query format. The `.openai/hosting.json` file describes optional Sites hosting; it is not needed to run locally.
