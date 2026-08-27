const FREQUENCIES = ["ultraOften", "often", "normal", "rare"];
const SPECIES_IDS = ["cat", "dog"];
const GESTURE_BY_SPECIES = { cat: "gesture_earL_10", dog: "gesture_paw_10" };

const enabledEl = document.getElementById("enabled");
const frequencyEls = Object.fromEntries(
  FREQUENCIES.map((f) => [f, document.querySelector(`input[name="frequency"][value="${f}"]`)])
);
const speciesEls = {
  cat: document.getElementById("species-cat"),
  dog: document.getElementById("species-dog")
};
const peekNowEl = document.getElementById("peekNow");
const peekImgEl = document.getElementById("peekImg");

function load() {
  chrome.storage.local.get(["enabled", "frequency", "disabledSpecies"], (data) => {
    enabledEl.checked = data.enabled !== undefined ? data.enabled : true;
    const frequency = FREQUENCIES.includes(data.frequency) ? data.frequency : "normal";
    frequencyEls[frequency].checked = true;
    const disabled = data.disabledSpecies || [];
    for (const id of SPECIES_IDS) {
      speciesEls[id].checked = !disabled.includes(id);
    }
    setPeekPreview(disabled);
  });
}

/// Shows one of the enabled species peeking from the header, picked fresh
/// each time the popup opens — a small echo of the same randomness the
/// extension itself uses when picking who shows up.
function setPeekPreview(disabledSpecies) {
  const enabled = SPECIES_IDS.filter((id) => !disabledSpecies.includes(id));
  const pool = enabled.length > 0 ? enabled : SPECIES_IDS;
  const species = pool[Math.floor(Math.random() * pool.length)];
  const idleSrc = `sprites/${species}/smiling/idle_00.png`;
  const gestureSrc = `sprites/${species}/smiling/${GESTURE_BY_SPECIES[species]}.png`;
  peekImgEl.src = idleSrc;
  peekImgEl.onmouseenter = () => { peekImgEl.src = gestureSrc; };
  peekImgEl.onmouseleave = () => { peekImgEl.src = idleSrc; };
}

enabledEl.addEventListener("change", () => {
  chrome.storage.local.set({ enabled: enabledEl.checked });
});

for (const frequency of FREQUENCIES) {
  frequencyEls[frequency].addEventListener("change", () => {
    chrome.storage.local.set({ frequency });
  });
}

for (const id of SPECIES_IDS) {
  speciesEls[id].addEventListener("change", () => {
    chrome.storage.local.get(["disabledSpecies"], (data) => {
      const disabled = new Set(data.disabledSpecies || []);
      if (speciesEls[id].checked) {
        disabled.delete(id);
      } else {
        disabled.add(id);
      }
      chrome.storage.local.set({ disabledSpecies: Array.from(disabled) });
    });
  });
}

peekNowEl.addEventListener("click", () => {
  chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
    const tab = tabs[0];
    if (!tab || !tab.id) return;
    chrome.tabs.sendMessage(tab.id, { type: "peekNow" }, () => {
      // Ignore errors: a chrome:// page, the Chrome Web Store, or a tab
      // open since before the extension loaded has nothing listening.
      void chrome.runtime.lastError;
    });
  });
});

load();
