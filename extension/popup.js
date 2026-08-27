const FREQUENCIES = ["ultraOften", "often", "normal", "rare"];
const SPECIES_IDS = ["cat", "dog"];

const enabledEl = document.getElementById("enabled");
const frequencyEl = document.getElementById("frequency");
const speciesEls = {
  cat: document.getElementById("species-cat"),
  dog: document.getElementById("species-dog")
};
const peekNowEl = document.getElementById("peekNow");

function load() {
  chrome.storage.local.get(["enabled", "frequency", "disabledSpecies"], (data) => {
    enabledEl.checked = data.enabled !== undefined ? data.enabled : true;
    frequencyEl.value = FREQUENCIES.includes(data.frequency) ? data.frequency : "normal";
    const disabled = data.disabledSpecies || [];
    for (const id of SPECIES_IDS) {
      speciesEls[id].checked = !disabled.includes(id);
    }
  });
}

enabledEl.addEventListener("change", () => {
  chrome.storage.local.set({ enabled: enabledEl.checked });
});

frequencyEl.addEventListener("change", () => {
  chrome.storage.local.set({ frequency: frequencyEl.value });
});

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
