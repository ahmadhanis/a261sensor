'use strict';

// Change these defaults if you use a different Firebase database or device.
const CONFIG = Object.freeze({
  databaseUrl: 'https://iotprojects-62001-default-rtdb.asia-southeast1.firebasedatabase.app',
  defaultDevice: 'esp32-01',
  refreshMs: 5000,
  staleMs: 30000,
});

const $ = (id) => document.getElementById(id);
const validDevice = (value) => /^[A-Za-z0-9_-]{1,64}$/.test(value);
const isNumber = (value) => typeof value === 'number' && Number.isFinite(value);
let savedDevice;
try { savedDevice = localStorage.getItem('fieldwork.device'); } catch { /* Storage can be disabled. */ }
const state = {
  device: validDevice(savedDevice || '') ? savedDevice : CONFIG.defaultDevice,
  temperature: null, humidity: null, timestamp: null, relay: null,
  history: [], metric: 'temperature', limit: 100, visibleRows: 10,
  auto: true, busy: false, writing: false, readable: false, relayReadable: false,
  historyFailed: false, generation: 0, relayRevision: 0, controller: null, timer: null, feedbackTimer: null,
};

const fullDate = new Intl.DateTimeFormat(undefined, { dateStyle: 'medium', timeStyle: 'medium' });
const dateOnly = new Intl.DateTimeFormat(undefined, { month: 'short', day: '2-digit' });
const timeOnly = new Intl.DateTimeFormat(undefined, { hour: '2-digit', minute: '2-digit', second: '2-digit', hour12: false });
const shortTime = new Intl.DateTimeFormat(undefined, { hour: '2-digit', minute: '2-digit', hour12: false });
const decimal = new Intl.NumberFormat(undefined, { minimumFractionDigits: 1, maximumFractionDigits: 1 });
const readableTime = (timestamp, formatter = fullDate) => isNumber(timestamp) && timestamp > 0 ? formatter.format(new Date(timestamp)) : 'No timestamp yet';
const escapeHtml = (value) => String(value).replace(/[&<>"']/g, (char) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[char]));

function databaseUrl(path, query = {}) {
  const url = new URL(`${CONFIG.databaseUrl}/devices/${encodeURIComponent(state.device)}/${path}.json`);
  Object.entries(query).forEach(([key, value]) => url.searchParams.set(key, value));
  return url;
}

async function request(url, options = {}) {
  const response = await fetch(url, { cache: 'no-store', ...options });
  if (!response.ok) {
    if (response.status === 401 || response.status === 403) throw new Error('Access denied. Publish the updated Firebase rules.');
    throw new Error(`Firebase returned HTTP ${response.status}.`);
  }
  return response.json();
}

function feedback(message, error = false) {
  clearTimeout(state.feedbackTimer);
  $('feedback').textContent = message;
  $('feedback').classList.toggle('error', error);
  state.feedbackTimer = setTimeout(() => { $('feedback').textContent = ''; }, 6500);
}

function updateStatus() {
  const age = isNumber(state.timestamp) && state.timestamp > 0 ? Date.now() - state.timestamp : null;
  const fresh = state.readable && age !== null && age >= -60000 && age < CONFIG.staleMs;
  let label = 'Waiting for device';
  if (!navigator.onLine) label = 'Browser offline';
  else if (!state.readable && !state.busy) label = 'Connection issue';
  else if (fresh) label = 'Device online';
  else if (age !== null) label = age < -60000 ? 'Check device clock' : 'Reading is stale';
  else if (state.busy) label = 'Connecting';
  $('connection-text').textContent = label;
  $('connection').className = `connection${fresh && navigator.onLine ? ' live' : (label === 'Connection issue' || label === 'Browser offline' || label === 'Reading is stale') ? ' error' : ''}`;
  $('reading-age').textContent = age === null ? 'Waiting' : age < -60000 ? 'Clock mismatch' : age < 1000 ? 'Just now' : age < 60000 ? `${Math.floor(age / 1000)} seconds ago` : age < 3600000 ? `${Math.floor(age / 60000)} minutes ago` : `${Math.floor(age / 3600000)} hours ago`;
  if (!state.writing) $('relay-help').textContent = state.relayReadable
    ? (fresh ? 'Stored command · physical relay state is not reported.' : 'Stored command · applies when the device reconnects.')
    : 'Waiting for access to the relay command.';
}

function renderLive() {
  $('temperature').textContent = isNumber(state.temperature) ? decimal.format(state.temperature) : '—';
  $('humidity').textContent = isNumber(state.humidity) ? decimal.format(state.humidity) : '—';
  $('last-update').textContent = readableTime(state.timestamp);
  $('relay-value').textContent = state.writing ? 'Sending…' : state.relay === true ? 'ON' : state.relay === false ? 'OFF' : 'Not set';
  $('relay-indicator').classList.toggle('on', state.relay === true);
  for (const [id, value] of [['relay-on', true], ['relay-off', false]]) {
    $(id).disabled = state.writing || !state.relayReadable || !navigator.onLine;
    $(id).setAttribute('aria-pressed', String(state.relay === value));
  }
  updateStatus();
}

function normalizeHistory(value) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return [];
  return Object.entries(value).flatMap(([key, item]) => {
    if (!item || typeof item !== 'object') return [];
    const timestamp = isNumber(item.timestamp) && item.timestamp > 0 ? item.timestamp : Number(key);
    if (!isNumber(timestamp) || timestamp <= 0 || timestamp > 8640000000000000 || !isNumber(item.temperature) || !isNumber(item.humidity)) return [];
    return [{ key, timestamp, temperature: item.temperature, humidity: item.humidity }];
  }).sort((a, b) => a.timestamp - b.timestamp || a.key.localeCompare(b.key));
}

function renderChart() {
  const rows = state.history;
  const svg = $('history-chart');
  const metric = state.metric;
  const humidity = metric === 'humidity';
  const color = humidity ? '#538fc1' : '#dc8850';
  const label = humidity ? 'Humidity' : 'Temperature';
  const unit = humidity ? '%' : '°C';
  $('chart-unit').textContent = `${label.toUpperCase()} · ${unit}`;
  $('chart-caption').textContent = label;
  $('legend-dot').style.background = color;
  $('chart-empty').hidden = rows.length > 0;
  $('chart-empty').querySelector('strong').textContent = state.historyFailed ? 'History is unavailable' : 'Waiting for your first reading';
  $('chart-empty').querySelector('p').textContent = state.historyFailed ? 'Check your connection and Firebase history rules.' : 'Saved readings will appear here automatically.';
  svg.setAttribute('aria-label', `${label} history chart with ${rows.length} readings`);
  if (!rows.length) { svg.innerHTML = ''; $('chart-summary').textContent = 'No historical readings yet'; return; }

  const values = rows.map((row) => row[metric]);
  const min = Math.min(...values), max = Math.max(...values);
  const average = values.reduce((sum, value) => sum + value, 0) / values.length;
  const padding = Math.max((max - min) * .25, 1);
  const low = humidity ? Math.min(0, min) : Math.floor(min - padding);
  const high = humidity ? Math.max(100, max) : Math.ceil(max + padding);
  const width = Math.max(320, svg.clientWidth || 800);
  svg.setAttribute('viewBox', `0 0 ${width} 270`);
  const left = 57, right = width - 25, top = 25, bottom = 224;
  const first = rows[0].timestamp, last = rows[rows.length - 1].timestamp;
  const x = (row) => rows.length === 1 || last === first ? (left + right) / 2 : left + (row.timestamp - first) / (last - first) * (right - left);
  const y = (value) => bottom - (value - low) / (high - low) * (bottom - top);
  const points = rows.map((row) => [x(row), y(row[metric])]);
  const path = points.map(([px, py], index) => `${index ? 'L' : 'M'}${px.toFixed(2)},${py.toFixed(2)}`).join(' ');
  const area = `${path} L${points[points.length - 1][0]},${bottom} L${points[0][0]},${bottom} Z`;
  let markup = `<defs><linearGradient id="chart-fill" x1="0" y1="0" x2="0" y2="1"><stop offset="0%" stop-color="${color}" stop-opacity=".15"/><stop offset="100%" stop-color="${color}" stop-opacity=".01"/></linearGradient></defs>`;
  for (let i = 0; i < 5; i++) {
    const value = low + (high - low) * i / 4, py = y(value);
    markup += `<line x1="${left}" x2="${right}" y1="${py}" y2="${py}" stroke="#edf1eb" stroke-dasharray="3 5"/><text x="43" y="${py + 4}" text-anchor="end" fill="#9ba99d" font-size="13">${value.toFixed(1)}</text>`;
  }
  for (let i = 0; i < (rows.length === 1 ? 1 : 5); i++) {
    const ratio = rows.length === 1 ? .5 : i / 4;
    const px = left + ratio * (right - left), time = first + ratio * (last - first);
    markup += `<text x="${px}" y="253" text-anchor="${i === 0 && rows.length > 1 ? 'start' : i === 4 ? 'end' : 'middle'}" fill="#a0aca0" font-size="13">${escapeHtml(readableTime(time, shortTime))}</text>`;
  }
  markup += `<path d="${area}" fill="url(#chart-fill)"/><path d="${path}" fill="none" stroke="${color}" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round"/>`;
  // Native SVG tooltips reveal the exact reading without a chart dependency.
  rows.forEach((row, i) => { markup += `<circle cx="${points[i][0]}" cy="${points[i][1]}" r="${rows.length === 1 || i === rows.length - 1 ? 4 : 3}" fill="${color}" fill-opacity="${i === rows.length - 1 ? 1 : .15}"><title>${escapeHtml(`${readableTime(row.timestamp)} · ${decimal.format(row[metric])} ${unit}`)}</title></circle>`; });
  svg.innerHTML = markup;
  $('chart-summary').textContent = `Min ${decimal.format(min)} · Avg ${decimal.format(average)} · Max ${decimal.format(max)} ${unit}`;
}

function renderHistory() {
  const newest = [...state.history].reverse();
  const visible = newest.slice(0, state.visibleRows);
  const body = $('history-body');
  body.replaceChildren();
  if (!visible.length) {
    const cell = document.createElement('td');
    cell.colSpan = 4;
    cell.className = 'table-empty';
    cell.textContent = state.historyFailed ? 'Could not load history. Check the connection and Firebase rules.' : 'No saved readings for this device yet.';
    const row = document.createElement('tr'); row.append(cell); body.append(row);
  }
  for (const item of visible) {
    const row = document.createElement('tr');
    const date = document.createElement('td');
    date.textContent = readableTime(item.timestamp, dateOnly);
    date.title = readableTime(item.timestamp);
    const time = document.createElement('span'); time.className = 'time'; time.textContent = readableTime(item.timestamp, timeOnly); date.append(time);
    const temperature = document.createElement('td'); temperature.textContent = `${decimal.format(item.temperature)} °C`;
    const humidity = document.createElement('td'); humidity.textContent = `${decimal.format(item.humidity)} %`;
    const device = document.createElement('td');
    const tag = document.createElement('span'); tag.className = 'device-tag'; tag.textContent = state.device; device.append(tag);
    row.append(date, temperature, humidity, device); body.append(row);
  }
  $('table-count').textContent = `Showing ${visible.length} of ${newest.length} readings`;
  $('history-caption').textContent = newest.length ? `Latest ${newest.length} saved readings · times shown in your local timezone.` : 'A closer look at the readings your device has saved.';
  $('show-more').hidden = newest.length <= state.visibleRows;
  $('export-csv').disabled = !newest.length;
  renderChart();
  window.dispatchEvent(new CustomEvent('fieldwork:data'));
}

function scheduleRefresh() {
  clearTimeout(state.timer);
  if (state.auto) state.timer = setTimeout(loadDashboard, CONFIG.refreshMs);
}

async function loadDashboard() {
  if (state.busy) return;
  clearTimeout(state.timer);
  const generation = state.generation;
  const relayRevision = state.relayRevision;
  const controller = new AbortController();
  state.controller = controller;
  const timeout = setTimeout(() => controller.abort(), 10000);
  state.busy = true;
  $('refresh').disabled = true;
  $('refresh').setAttribute('aria-busy', 'true');
  const fields = ['temperature', 'humidity', 'timestamp', 'relay'];
  const results = await Promise.allSettled([
    ...fields.map((field) => request(databaseUrl(field), { signal: controller.signal })),
    request(databaseUrl('history', { orderBy: JSON.stringify('$key'), limitToLast: String(state.limit) }), { signal: controller.signal }),
  ]);
  clearTimeout(timeout);
  if (generation !== state.generation) return;
  state.busy = false;
  $('refresh').disabled = false;
  $('refresh').setAttribute('aria-busy', 'false');
  const errors = [];
  results.forEach((result, index) => {
    if (result.status === 'rejected') { errors.push(`${index === 4 ? 'History' : fields[index]}: ${result.reason.message || 'Connection timed out.'}`); return; }
    if (index === 4) { state.history = normalizeHistory(result.value); return; }
    const field = fields[index];
    // A poll started before a relay write must not replace the new command.
    if (field === 'relay' && (state.writing || relayRevision !== state.relayRevision)) return;
    state[field] = field === 'relay' ? (typeof result.value === 'boolean' ? result.value : null) : isNumber(result.value) && (field !== 'timestamp' || result.value <= 8640000000000000) ? result.value : null;
  });
  state.readable = results.slice(0, 4).every((result) => result.status === 'fulfilled');
  state.relayReadable = results[3].status === 'fulfilled';
  state.historyFailed = results[4].status === 'rejected';
  $('notice').hidden = errors.length === 0;
  $('notice').textContent = errors.length ? `Some data could not be refreshed. ${errors.join(' ')}` : '';
  $('refresh-time').textContent = state.readable ? `Refreshed ${shortTime.format(new Date())}` : 'Refresh failed';
  renderLive();
  renderHistory();
  scheduleRefresh();
}

async function writeRelay(on) {
  if (state.writing || !state.relayReadable) return;
  const device = state.device;
  const generation = state.generation;
  const controller = new AbortController();
  const timeout = setTimeout(() => controller.abort(), 10000);
  state.writing = true;
  state.relayRevision++;
  renderLive();
  $('relay-help').textContent = 'Saving relay command to Firebase…';
  try {
    const saved = await request(databaseUrl('relay'), { method: 'PUT', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(on), signal: controller.signal });
    if (saved !== on) throw new Error('Firebase did not confirm the requested command.');
    if (generation !== state.generation) return;
    state.relay = saved;
    feedback(`${device}: ${on ? 'ON' : 'OFF'} command saved. The device checks for commands every 2 seconds.`);
  } catch (error) {
    if (generation === state.generation) feedback(`Command not confirmed. ${error.name === 'AbortError' ? 'Request timed out; refresh to check its stored value.' : error.message}`, true);
  } finally {
    clearTimeout(timeout);
    if (generation === state.generation) { state.writing = false; renderLive(); }
  }
}

function reload(clear = false) {
  state.generation++;
  state.controller?.abort();
  clearTimeout(state.timer);
  state.busy = false;
  state.writing = false;
  if (clear) {
    Object.assign(state, { temperature: null, humidity: null, timestamp: null, relay: null, history: [], readable: false, relayReadable: false, historyFailed: false, visibleRows: 10 });
    $('snapshot-id').textContent = state.device;
    renderLive(); renderHistory();
  }
  loadDashboard();
}

$('device-id').value = state.device;
$('snapshot-id').textContent = state.device;
$('timezone').textContent = `(${Intl.DateTimeFormat().resolvedOptions().timeZone})`;
$('device-form').addEventListener('submit', (event) => {
  event.preventDefault();
  const device = $('device-id').value.trim();
  if (!validDevice(device)) { feedback('Use letters, digits, hyphens, or underscores for the device ID.', true); return; }
  state.device = device;
  try { localStorage.setItem('fieldwork.device', device); } catch { /* Storage is optional. */ }
  reload(true);
});
$('refresh').addEventListener('click', loadDashboard);
$('auto-refresh').addEventListener('click', () => {
  state.auto = !state.auto;
  $('auto-refresh').setAttribute('aria-pressed', String(state.auto));
  $('auto-label').textContent = `Auto-refresh ${state.auto ? 'on' : 'paused'}`;
  if (state.auto) loadDashboard(); else clearTimeout(state.timer);
});
$('history-limit').addEventListener('change', () => { state.limit = Number($('history-limit').value); state.visibleRows = 10; reload(); });
for (const metric of ['temperature', 'humidity']) $('chart-' + metric).addEventListener('click', () => {
  state.metric = metric;
  for (const option of ['temperature', 'humidity']) {
    $('chart-' + option).classList.toggle('selected', metric === option);
    $('chart-' + option).setAttribute('aria-pressed', String(metric === option));
  }
  renderChart();
});
$('relay-on').addEventListener('click', () => writeRelay(true));
$('relay-off').addEventListener('click', () => writeRelay(false));
$('show-more').addEventListener('click', () => { state.visibleRows += 20; renderHistory(); });
$('export-csv').addEventListener('click', () => {
  const lines = ['device_id,timestamp_ms,time_utc,temperature_c,humidity_pct', ...state.history.map((item) => [state.device, item.timestamp, new Date(item.timestamp).toISOString(), item.temperature, item.humidity].join(','))];
  const url = URL.createObjectURL(new Blob([lines.join('\r\n')], { type: 'text/csv;charset=utf-8' }));
  const link = document.createElement('a'); link.href = url; link.download = `${state.device}-history.csv`; link.click();
  setTimeout(() => URL.revokeObjectURL(url), 1000);
});
document.querySelectorAll('.nav-item').forEach((link) => link.addEventListener('click', () => {
  document.querySelectorAll('.nav-item').forEach((item) => item.classList.toggle('active', item === link));
}));
window.addEventListener('online', () => { renderLive(); if (state.auto) loadDashboard(); });
window.addEventListener('offline', renderLive);
window.getFieldworkSnapshot = () => ({
  deviceId: state.device,
  latest: { temperature: state.temperature, humidity: state.humidity, timestamp: state.timestamp, relay: state.relay },
  readings: state.history.map(({ timestamp, temperature, humidity }) => ({ timestamp, temperature, humidity })),
});
let resizeFrame;
window.addEventListener('resize', () => { cancelAnimationFrame(resizeFrame); resizeFrame = requestAnimationFrame(renderChart); });
setInterval(updateStatus, 1000);
loadDashboard();
