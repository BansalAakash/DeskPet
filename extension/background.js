// Nothing runs the actual peek schedule here. Each tab's content script
// owns its own timer — see content.js for why: MV3 service workers get
// killed after ~30s idle, so they can't reliably hold a 5s-5min timer,
// while a visible tab's own JS timers run at full speed for as long as
// it's the one you're looking at. This worker only seeds default settings.
const DEFAULTS = {
  enabled: true,
  frequency: "normal",
  disabledSpecies: []
};

chrome.runtime.onInstalled.addListener(async () => {
  const existing = await chrome.storage.local.get(Object.keys(DEFAULTS));
  const missing = {};
  for (const key of Object.keys(DEFAULTS)) {
    if (!(key in existing)) missing[key] = DEFAULTS[key];
  }
  if (Object.keys(missing).length > 0) {
    await chrome.storage.local.set(missing);
  }
});
