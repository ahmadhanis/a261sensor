const MAX_ROWS = 1000;
const MAX_MODEL_ROWS = 200;
const MAX_DATE = 8640000000000000;

function finite(value) { return typeof value === 'number' && Number.isFinite(value); }
function timestamp(value) { return finite(value) && value > 0 && value <= MAX_DATE; }
function round(value) { return Number(value.toFixed(3)); }
function metricStats(rows, field) {
  const values = rows.map((row) => row[field]);
  const mean = values.reduce((sum, value) => sum + value, 0) / values.length;
  const times = rows.map((row) => (row.timestamp - rows[0].timestamp) / 3600000);
  const meanTime = times.reduce((sum, value) => sum + value, 0) / times.length;
  let numerator = 0, denominator = 0, largestStep = 0;
  values.forEach((value, i) => {
    numerator += (times[i] - meanTime) * (value - mean);
    denominator += (times[i] - meanTime) ** 2;
    if (i) largestStep = Math.max(largestStep, Math.abs(value - values[i - 1]));
  });
  return {
    min: round(Math.min(...values)), max: round(Math.max(...values)), mean: round(mean),
    first: values[0], last: values.at(-1), change: round(values.at(-1) - values[0]),
    observedSlopePerHour: denominator ? round(numerator / denominator) : null,
    largestConsecutiveStep: round(largestStep),
  };
}

export function prepareSnapshot(input, now = Date.now()) {
  if (!input || typeof input !== 'object' || !/^[A-Za-z0-9_-]{1,64}$/.test(input.deviceId || '')) {
    throw new Error('A valid device ID is required.');
  }
  if (!Array.isArray(input.readings) || input.readings.length > MAX_ROWS) {
    throw new Error(`Send at most ${MAX_ROWS} historical readings.`);
  }
  const rows = input.readings.map((row) => {
    if (!row || !timestamp(row.timestamp) || !finite(row.temperature) || !finite(row.humidity) ||
        Math.abs(row.temperature) > 1000 || Math.abs(row.humidity) > 1000) {
      throw new Error('Every reading needs a valid timestamp, temperature, and humidity.');
    }
    return { timestamp: row.timestamp, temperature: row.temperature, humidity: row.humidity };
  }).sort((a, b) => a.timestamp - b.timestamp);
  if (rows.length < 3) throw new Error('At least 3 saved readings are needed for analysis.');
  const intervals = rows.slice(1).map((row, i) => row.timestamp - rows[i].timestamp).filter((value) => value > 0).sort((a, b) => a - b);
  const middle = Math.floor(intervals.length / 2);
  const medianInterval = intervals.length ? (intervals.length % 2 ? intervals[middle] : (intervals[middle - 1] + intervals[middle]) / 2) : null;
  const latest = input.latest || {};
  const latestTimestamp = timestamp(latest.timestamp) ? latest.timestamp : null;
  const statistics = {
    readingCount: rows.length, start: rows[0].timestamp, end: rows.at(-1).timestamp,
    spanMinutes: round((rows.at(-1).timestamp - rows[0].timestamp) / 60000),
    temperature: metricStats(rows, 'temperature'), humidity: metricStats(rows, 'humidity'),
    medianIntervalSeconds: medianInterval === null ? null : round(medianInterval / 1000),
    gapCount: medianInterval === null ? 0 : intervals.filter((value) => value > medianInterval * 3).length,
    duplicateTimestampCount: rows.length - 1 - intervals.length,
  };
  const sampled = rows.length <= MAX_MODEL_ROWS ? rows : Array.from({ length: MAX_MODEL_ROWS }, (_, i) => rows[Math.round(i * (rows.length - 1) / (MAX_MODEL_ROWS - 1))]);
  return {
    deviceId: input.deviceId, capturedAt: now,
    latest: {
      temperature: finite(latest.temperature) ? latest.temperature : null,
      humidity: finite(latest.humidity) ? latest.humidity : null,
      timestamp: latestTimestamp,
      ageSeconds: latestTimestamp === null ? null : round((now - latestTimestamp) / 1000),
      relayCommand: typeof latest.relay === 'boolean' ? latest.relay : null,
    },
    statistics, sampledReadingCount: sampled.length, readings: sampled,
  };
}

export const SYSTEM_PROMPT = `You analyze DHT11 temperature and humidity measurements for an ESP32 dashboard.
Use only the supplied numerical readings and precomputed statistics. Write concise plain English, at most 250 words total.
Report observed patterns, largest changes, and sampling gaps. Quote units and distinguish a relative humidity percentage-point change from a percent change.
Statistics cover every submitted reading, while the included time series may be evenly sampled. A fitted slope is descriptive, never a forecast.
Treat gaps as gaps in the fetched data, not proven device failures. Do not invent causes, precise predictions, health claims, safety thresholds, room purpose, occupancy, or equipment attached to the relay.
The relay value is only a stored command, not physical feedback. Never instruct switching the relay ON or OFF and never claim to control it.
Flag stale or future timestamps when applicable. Mention limited duration or insufficient variation when relevant. Recommendations should be observational checks such as inspecting placement, wiring, or collecting more readings.
If no anomalies are evident, return an empty anomalies array. Return only the JSON object matching the schema.`;

export function validateAnalysis(value) {
  if (!value || typeof value !== 'object') throw new Error('Gemini returned an invalid analysis. Please try again.');
  const result = {};
  for (const field of ['summary', 'temperatureTrend', 'humidityTrend']) {
    if (typeof value[field] !== 'string' || !value[field].trim() || value[field].length > 2000) throw new Error('Gemini returned an incomplete analysis. Please try again.');
    result[field] = value[field].trim();
  }
  for (const field of ['anomalies', 'recommendations', 'limitations']) {
    if (!Array.isArray(value[field]) || value[field].length > 3 || value[field].some((item) => typeof item !== 'string' || !item.trim() || item.length > 1000)) throw new Error('Gemini returned an invalid analysis. Please try again.');
    result[field] = value[field].map((item) => item.trim());
  }
  return result;
}

