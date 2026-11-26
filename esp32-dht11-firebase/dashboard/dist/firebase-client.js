// Firebase web app configuration. Add your Firebase web API key to enable it.
// This identifies the AI/Analytics app. Sensor data stays in the IoT database.
export const firebaseConfig = Object.freeze({
  apiKey: '',
  authDomain: 'ai-projects-abf22.firebaseapp.com',
  projectId: 'ai-projects-abf22',
  storageBucket: 'ai-projects-abf22.firebasestorage.app',
  messagingSenderId: '125313470603',
  appId: '1:125313470603:web:d2500a48add5b32ec9048e',
  measurementId: 'G-87WJLED12G',
});

export const AI_CONFIG = Object.freeze({
  model: 'gemini-3.5-flash-lite',
  // If App Check is enforced, register your web app and paste its public
  // reCAPTCHA Enterprise site key here. This is NOT a Gemini API key.
  appCheckSiteKey: '',
  analyticsEnabled: true,
});

const SDK = 'https://www.gstatic.com/firebasejs/13.4.0';
let appPromise;
let appCheckPromise;

export function isFirebaseConfigured() {
  return typeof firebaseConfig.apiKey === 'string' && firebaseConfig.apiKey.trim().length > 0;
}

export function getFirebaseApp() {
  if (!isFirebaseConfigured()) return Promise.reject(new Error('Firebase API key is not configured.'));
  if (!appPromise) {
    appPromise = import(`${SDK}/firebase-app.js`)
      .then(({ initializeApp, getApps }) => getApps().find((app) => app.name === 'fieldwork-ai') || initializeApp(firebaseConfig, 'fieldwork-ai'))
      .catch((error) => { appPromise = null; throw error; });
  }
  return appPromise;
}

export async function prepareFirebaseAI() {
  const app = await getFirebaseApp();
  if (AI_CONFIG.appCheckSiteKey && !appCheckPromise) {
    appCheckPromise = import(`${SDK}/firebase-app-check.js`).then(({ initializeAppCheck, ReCaptchaEnterpriseProvider }) => initializeAppCheck(app, {
      provider: new ReCaptchaEnterpriseProvider(AI_CONFIG.appCheckSiteKey), isTokenAutoRefreshEnabled: true,
    })).catch((error) => { appCheckPromise = null; throw error; });
  }
  if (appCheckPromise) await appCheckPromise;
  return { app, sdk: await import(`${SDK}/firebase-ai.js`) };
}

// Analytics is optional: unsupported browsers or blocked trackers must never
// interrupt live readings, relay control, or Gemini analysis.
async function initializeAnalytics() {
  if (!AI_CONFIG.analyticsEnabled || !isFirebaseConfigured()) return;
  const { getAnalytics, isSupported } = await import(`${SDK}/firebase-analytics.js`);
  if (await isSupported()) getAnalytics(await getFirebaseApp());
}

initializeAnalytics().catch(() => { console.info('Firebase Analytics could not initialize; dashboard features remain available.'); });
