import { AI_CONFIG, isFirebaseConfigured, prepareFirebaseAI } from './firebase-client.js';
import { prepareSnapshot, SYSTEM_PROMPT, validateAnalysis } from './analysis-data.js';

const element = (id) => document.getElementById(id);
const dateTime = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'short' });
const time = new Intl.DateTimeFormat(undefined, { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false });
const ai = { device: null, busy: false, generation: 0, controller: null, model: null, report: null, error: false };

function currentSnapshot() {
  return window.getFieldworkSnapshot?.() || { deviceId: 'esp32-01', latest: {}, readings: [] };
}

function updatePanel() {
  const snapshot = currentSnapshot();
  if (ai.device !== snapshot.deviceId) {
    ai.generation++;
    ai.controller?.abort();
    ai.device = snapshot.deviceId;
    ai.busy = false; ai.report = null; ai.error = false;
    element('ai-report').hidden = true;
    element('ai-error').hidden = true;
    element('ai-loading').hidden = true;
    element('ai-empty').hidden = false;
  }
  const rows = snapshot.readings;
  element('ai-scope').textContent = rows.length
    ? `${snapshot.deviceId} · ${rows.length.toLocaleString()} readings · ${time.format(new Date(rows[0].timestamp))}–${time.format(new Date(rows.at(-1).timestamp))}`
    : `${snapshot.deviceId} · waiting for saved readings`;
  element('analyze-readings').disabled = ai.busy || !isFirebaseConfigured() || rows.length < 3 || !navigator.onLine;
  element('analyze-readings').setAttribute('aria-busy', String(ai.busy));
  if (!ai.busy) {
    element('ai-status').textContent = !isFirebaseConfigured() ? 'Firebase API key removed. Add your app configuration in firebase-client.js to enable Gemini and Firebase Analytics.' : !navigator.onLine ? 'Reconnect to the internet to request Gemini analysis.' : rows.length < 3
      ? 'At least 3 saved readings are needed for trend analysis.'
      : 'Runs on demand. Sends the selected readings to Google Gemini. Relay control stays manual.';
  }
  if (ai.report) {
    const stats = ai.report.statistics;
    const newer = rows.at(-1)?.timestamp !== stats.end || rows.length !== stats.readingCount;
    element('ai-report-meta').textContent = `Analyzed ${dateTime.format(new Date(ai.report.analyzedAt))} · ${stats.readingCount} readings over ${stats.spanMinutes.toFixed(1)} minutes · ${ai.report.sampledReadingCount} time-series points reviewed${newer ? ' · New readings available; analyze again to update.' : ''}`;
  }
}

function reportError(error) {
  if (error.name === 'AbortError') return 'Analysis was cancelled or timed out. You can try again.';
  const message = String(error.message || '');
  const code = String(error.code || '');
  const status = error.customErrorData?.status;
  if (status === 429 || /quota|rate.limit|resource.exhausted/i.test(message)) return 'Gemini quota or rate limit reached. Check your Firebase AI Logic quota and try again later.';
  if (code.includes('api-not-enabled') || /SERVICE_DISABLED|API.*not.*enabled/i.test(message)) return 'Enable Firebase AI Logic in ai-projects-abf22, select Gemini Developer API, then try again.';
  if (/app.?check|attestation|recaptcha/i.test(message)) return 'Firebase requires App Check. Configure the public reCAPTCHA Enterprise site key in firebase-client.js and register this site in Firebase.';
  if (status === 401 || status === 403 || /permission.denied|API_KEY/i.test(message)) return 'Firebase AI access was denied. Check AI Logic setup, App Check, and API restrictions for this web app.';
  if (status === 404) return 'The Gemini model is unavailable for this project. Check the model setting in firebase-client.js.';
  if (error instanceof TypeError || /fetch|network/i.test(message)) return 'Could not reach Firebase AI. Check your connection and try again.';
  return message.startsWith('Gemini returned') || message.startsWith('At least') ? message : 'Gemini could not complete the analysis. Please try again.';
}

async function getModel() {
  if (ai.model) return ai.model;
  const { app, sdk } = await prepareFirebaseAI();
  const { getAI, GoogleAIBackend, getGenerativeModel, Schema } = sdk;
  const array = (description) => Schema.array({ description, items: Schema.string() });
  const schema = Schema.object({ properties: {
    summary: Schema.string({ description: 'A concise, evidence-based overview.' }),
    temperatureTrend: Schema.string({ description: 'Observed temperature trend, with Celsius values.' }),
    humidityTrend: Schema.string({ description: 'Observed relative humidity trend, with percentage-point changes.' }),
    anomalies: array('Up to three unusual changes or gaps. Empty if none are evident.'),
    recommendations: array('Up to three practical observational checks.'),
    limitations: array('Up to three limitations in the readings or interpretation.'),
  } });
  ai.model = getGenerativeModel(getAI(app, { backend: new GoogleAIBackend() }), {
    model: AI_CONFIG.model, systemInstruction: SYSTEM_PROMPT,
    generationConfig: { responseMimeType: 'application/json', responseSchema: schema, maxOutputTokens: 2048 },
  });
  return ai.model;
}

function showList(id, items, empty) {
  const list = element(id);
  list.replaceChildren();
  for (const item of items.length ? items : [empty]) {
    const row = document.createElement('li'); row.textContent = item; list.append(row);
  }
}

async function analyze() {
  if (ai.busy || !isFirebaseConfigured()) return;
  let snapshot;
  try { snapshot = prepareSnapshot(currentSnapshot()); }
  catch (error) { element('ai-error').textContent = reportError(error); element('ai-error').hidden = false; return; }
  const generation = ai.generation;
  const controller = new AbortController();
  ai.controller = controller;
  ai.busy = true;
  ai.error = false;
  element('ai-error').hidden = true;
  element('ai-report').hidden = true;
  element('ai-empty').hidden = true;
  element('ai-loading').hidden = false;
  element('ai-status').textContent = 'Gemini is analyzing this snapshot. New sensor readings continue to refresh.';
  updatePanel();
  try {
    const model = await getModel();
    if (generation !== ai.generation || controller.signal.aborted) return;
    const result = await model.generateContent(JSON.stringify(snapshot), { signal: controller.signal, timeout: 30000 });
    if (generation !== ai.generation) return;
    if (result.response.candidates?.[0]?.finishReason !== 'STOP') throw new Error('Gemini returned an incomplete analysis. Please try again.');
    let output;
    try { output = JSON.parse(result.response.text()); } catch { throw new Error('Gemini returned an unreadable analysis. Please try again.'); }
    const analysis = validateAnalysis(output);
    element('ai-summary').textContent = analysis.summary;
    element('ai-temperature-trend').textContent = analysis.temperatureTrend;
    element('ai-humidity-trend').textContent = analysis.humidityTrend;
    showList('ai-anomalies', analysis.anomalies, 'No unusual changes identified in this snapshot.');
    showList('ai-recommendations', analysis.recommendations, 'Continue collecting readings to observe longer-term patterns.');
    showList('ai-limitations', analysis.limitations, 'Interpretation applies only to the supplied readings.');
    ai.report = { statistics: snapshot.statistics, analyzedAt: Date.now(), sampledReadingCount: snapshot.sampledReadingCount };
    element('ai-report').hidden = false;
  } catch (error) {
    if (generation !== ai.generation) return;
    ai.error = true;
    ai.report = null;
    element('ai-error').textContent = reportError(error);
    element('ai-error').hidden = false;
    element('ai-empty').hidden = false;
  } finally {
    if (generation === ai.generation) { ai.busy = false; element('ai-loading').hidden = true; updatePanel(); }
  }
}

element('analyze-readings').addEventListener('click', analyze);
window.addEventListener('fieldwork:data', updatePanel);
window.addEventListener('online', updatePanel);
window.addEventListener('offline', updatePanel);
updatePanel();
