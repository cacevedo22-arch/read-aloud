import { registerPlugin } from '@capacitor/core';

// Web fallback: no native engine in a browser, so report not-ready and let the
// page fall back to the PC server or the browser's own voices.
export const SherpaTts = registerPlugin('SherpaTts', {
  web: () => ({
    info: async () => ({ ready: false, error: 'native only', speakers: 0, sampleRate: 0 }),
    synthesize: async () => { throw new Error('SherpaTts is only available in the app'); },
  }),
});
