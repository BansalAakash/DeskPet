// DeskPet content script. Runs independently in every tab — there is no
// cross-tab coordination and no background-owned timer. That's deliberate:
// MV3 service workers get killed after ~30s idle, so they can't reliably
// hold a 5s-5min countdown, while a tab's own JS timers run at full speed
// exactly when that tab is the one you're looking at, and get throttled by
// the browser itself when it isn't — which is also exactly the battery
// behavior we want. Each tab schedules its own peeks against the settings
// in chrome.storage.local, so switching tabs always lands you on a live,
// independently-running pet, no matter which tab that is.
(() => {
  "use strict";

  if (window.__deskpetInjected) return;
  window.__deskpetInjected = true;

  const FREQUENCY_BANDS = {
    ultraOften: [5000, 5000],
    often: [15000, 45000],
    normal: [45000, 120000],
    rare: [120000, 300000]
  };

  const SPECIES_IDS = ["cat", "dog"];
  const FACES = ["plain", "smiling"];
  const GESTURE_FAMILIES = [["earL", "earR"], ["paw"]];
  const IDLE_FRAME_COUNT = 10;
  const GESTURE_FRAME_COUNT = 20;
  const FRAME_INTERVAL_MS = 90;

  // Same source art as the macOS app: natural size is ~274x240,
  // effectively identical aspect ratio for both species.
  const ASPECT = 274 / 240;
  const TARGET_HEIGHT = 110;

  const REST_REVEAL = 0.667;
  const MAX_REVEAL = 0.8;
  const EDGE_MARGIN = 40;

  const SLIDE_DURATION_MS = 450;
  const SLIDE_OUT_DURATION_MS = 400;
  const HOLD_RANGE_MS = [3600, 5400];
  const POST_CLICK_LINGER_MS = 2600;

  const EDGES = ["top", "bottom", "left", "right"];
  const REDUCE_MOTION = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  let settings = { enabled: true, frequency: "normal", disabledSpecies: [] };
  let lastEdge = null;
  let pendingTimer = null;
  let activePeek = null;
  let shadowRoot = null;

  function randomInRange([lo, hi]) {
    return lo + Math.random() * (hi - lo);
  }

  function ensureShadowRoot() {
    if (shadowRoot) return shadowRoot;
    const host = document.createElement("div");
    host.id = "deskpet-host";
    // Attached to <html>, not <body>: a transformed body (page
    // transitions, parallax, etc.) would otherwise become the containing
    // block for our position:fixed elements and break edge-anchoring.
    document.documentElement.appendChild(host);
    shadowRoot = host.attachShadow({ mode: "open" });
    const style = document.createElement("style");
    style.textContent = STYLES;
    shadowRoot.appendChild(style);
    return shadowRoot;
  }

  const STYLES = `
    .dp-clip {
      position: fixed;
      overflow: hidden;
      z-index: 2147483647;
      pointer-events: none;
    }
    .dp-slide {
      position: absolute;
      pointer-events: none;
    }
    .dp-orient {
      width: 100%;
      height: 100%;
      display: flex;
      align-items: center;
      justify-content: center;
      pointer-events: none;
    }
    .dp-sprite {
      display: block;
      cursor: pointer;
      pointer-events: auto;
      user-select: none;
      -webkit-user-drag: none;
    }
    @media (prefers-reduced-motion: reduce) {
      .dp-slide { transition: none !important; }
    }
  `;

  function loadSettings(callback) {
    chrome.storage.local.get(["enabled", "frequency", "disabledSpecies"], (data) => {
      settings = {
        enabled: data.enabled !== undefined ? data.enabled : true,
        frequency: data.frequency || "normal",
        disabledSpecies: data.disabledSpecies || []
      };
      if (callback) callback();
    });
  }

  chrome.storage.onChanged.addListener((changes, area) => {
    if (area !== "local") return;
    if (changes.enabled) settings.enabled = changes.enabled.newValue;
    if (changes.disabledSpecies) settings.disabledSpecies = changes.disabledSpecies.newValue;
    if (changes.frequency) {
      settings.frequency = changes.frequency.newValue;
      // Take effect now instead of after whatever's already armed.
      if (!activePeek) scheduleNext();
    }
  });

  chrome.runtime.onMessage.addListener((message) => {
    if (message && message.type === "peekNow") {
      if (activePeek) {
        activePeek.dismissNow();
      } else {
        spawnPeek();
      }
    }
  });

  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible" && !activePeek) {
      scheduleNext();
    }
  });

  function canPeek() {
    return settings.enabled && document.visibilityState === "visible";
  }

  function scheduleNext() {
    if (pendingTimer) {
      clearTimeout(pendingTimer);
      pendingTimer = null;
    }
    const range = FREQUENCY_BANDS[settings.frequency] || FREQUENCY_BANDS.normal;
    const delay = randomInRange(range);
    pendingTimer = setTimeout(() => {
      pendingTimer = null;
      attemptPeek();
    }, delay);
  }

  function attemptPeek() {
    if (activePeek) return; // already showing (e.g. a manual Peek Now) — its own finish reschedules
    if (!canPeek()) {
      scheduleNext();
      return;
    }
    spawnPeek();
  }

  function pickSpecies() {
    const enabled = SPECIES_IDS.filter((id) => !settings.disabledSpecies.includes(id));
    const pool = enabled.length > 0 ? enabled : SPECIES_IDS;
    return pool[Math.floor(Math.random() * pool.length)];
  }

  function pickEdge() {
    const choices = EDGES.filter((e) => e !== lastEdge);
    return choices[Math.floor(Math.random() * choices.length)];
  }

  function pickGesture() {
    const family = GESTURE_FAMILIES[Math.floor(Math.random() * GESTURE_FAMILIES.length)];
    return family[Math.floor(Math.random() * family.length)];
  }

  function requiredReveal(gesture) {
    return gesture === "paw" ? MAX_REVEAL : REST_REVEAL;
  }

  function spriteUrl(speciesId, face, frameName) {
    return chrome.runtime.getURL(`sprites/${speciesId}/${face}/${frameName}.png`);
  }

  function frameName(prefix, index) {
    return `${prefix}_${String(index).padStart(2, "0")}`;
  }

  function naturalSize() {
    return { width: TARGET_HEIGHT * ASPECT, height: TARGET_HEIGHT };
  }

  function fullSize(edge) {
    const n = naturalSize();
    return edge === "left" || edge === "right"
      ? { width: n.height, height: n.width }
      : { width: n.width, height: n.height };
  }

  function spawnPeek() {
    const speciesId = pickSpecies();
    const face = FACES[Math.floor(Math.random() * FACES.length)];
    const edge = pickEdge();
    lastEdge = edge;

    const root = ensureShadowRoot();
    const full = fullSize(edge);
    const natural = naturalSize();

    const clip = document.createElement("div");
    clip.className = "dp-clip";
    const slide = document.createElement("div");
    slide.className = "dp-slide";
    const orient = document.createElement("div");
    orient.className = "dp-orient";
    const img = document.createElement("img");
    img.className = "dp-sprite";
    img.draggable = false;
    img.alt = "";

    orient.appendChild(img);
    slide.appendChild(orient);
    clip.appendChild(slide);
    root.appendChild(clip);

    // clip: sized/positioned per edge, pinned flush to that viewport edge.
    let clipWidth, clipHeight;
    if (edge === "top" || edge === "bottom") {
      clipWidth = full.width;
      clipHeight = full.height * MAX_REVEAL;
    } else {
      clipWidth = full.width * MAX_REVEAL;
      clipHeight = full.height;
    }
    clip.style.width = `${clipWidth}px`;
    clip.style.height = `${clipHeight}px`;

    const vw = window.innerWidth;
    const vh = window.innerHeight;
    if (edge === "top" || edge === "bottom") {
      const low = EDGE_MARGIN;
      const high = vw - clipWidth - EDGE_MARGIN;
      const x = high > low ? low + Math.random() * (high - low) : Math.max(0, (vw - clipWidth) / 2);
      clip.style.left = `${x}px`;
      clip.style[edge === "bottom" ? "bottom" : "top"] = "0px";
    } else {
      const low = EDGE_MARGIN;
      const high = vh - clipHeight - EDGE_MARGIN;
      const y = high > low ? low + Math.random() * (high - low) : Math.max(0, (vh - clipHeight) / 2);
      clip.style.top = `${y}px`;
      clip.style[edge === "left" ? "left" : "right"] = "0px";
    }

    // slide: full (post-rotation) box, base-aligned to the side the
    // sprite's "head" anchors to, then translated for reveal.
    slide.style.width = `${full.width}px`;
    slide.style.height = `${full.height}px`;
    const baseSide = { bottom: "top", top: "bottom", left: "right", right: "left" }[edge];
    slide.style[baseSide] = "0px";
    if (!REDUCE_MOTION) slide.style.transition = `transform ${SLIDE_DURATION_MS}ms ease-out`;

    // sprite img: natural (pre-rotation) size, rotated/flipped to orient
    // its head into the screen from this edge.
    img.style.width = `${natural.width}px`;
    img.style.height = `${natural.height}px`;
    const orientTransform = { top: "scaleY(-1)", left: "rotate(90deg)", right: "rotate(-90deg)", bottom: "" }[edge];
    img.style.transform = orientTransform;

    let reveal = 0;
    let finished = false;
    let interactive = false;
    let playingGesture = null;
    let frameIndex = 0;
    let gestureIndex = 0;
    let leaveDeadline = 0;
    let leaveTimer = null;
    let leanTimer = null;

    function setReveal(v) {
      reveal = v;
      const revealAxis = edge === "top" || edge === "bottom" ? full.height : full.width;
      const back = (MAX_REVEAL - v) * revealAxis;
      const axisTransform = {
        bottom: `translateY(${back}px)`,
        top: `translateY(${-back}px)`,
        left: `translateX(${-back}px)`,
        right: `translateX(${back}px)`
      }[edge];
      slide.style.transform = axisTransform;
    }

    function render() {
      const name = playingGesture ? frameName(`gesture_${playingGesture}`, gestureIndex) : frameName("idle", frameIndex);
      img.src = spriteUrl(speciesId, face, name);
    }
    render();

    const tickTimer = setInterval(() => {
      if (playingGesture) {
        gestureIndex++;
        if (gestureIndex >= GESTURE_FRAME_COUNT) {
          // The gesture's last frame is the idle pose, so dropping back
          // to idle frame 0 continues without a visible jump.
          playingGesture = null;
          gestureIndex = 0;
          frameIndex = 0;
        }
        render();
        return;
      }
      frameIndex = (frameIndex + 1) % IDLE_FRAME_COUNT;
      render();
    }, FRAME_INTERVAL_MS);

    function scheduleLeave(delayMs) {
      if (leaveTimer) clearTimeout(leaveTimer);
      leaveDeadline = Date.now() + delayMs;
      leaveTimer = setTimeout(beginLeaving, delayMs);
    }

    function extendStay(byMs) {
      const target = Date.now() + byMs;
      if (target > leaveDeadline) scheduleLeave(byMs);
    }

    function beginLeaving() {
      if (finished) return;
      interactive = false;
      setReveal(0);
      setTimeout(finish, REDUCE_MOTION ? 0 : SLIDE_OUT_DURATION_MS);
    }

    function finish() {
      if (finished) return;
      finished = true;
      clearInterval(tickTimer);
      if (leaveTimer) clearTimeout(leaveTimer);
      if (leanTimer) clearTimeout(leanTimer);
      clip.remove();
      activePeek = null;
      scheduleNext();
    }

    function handleClick() {
      if (!interactive) return;
      const gesture = pickGesture();
      const needed = requiredReveal(gesture);

      if (needed <= REST_REVEAL + 0.001) {
        playingGesture = gesture;
        gestureIndex = 0;
        render();
        extendStay(POST_CLICK_LINGER_MS);
        return;
      }

      // Deeper gestures (paw) need the character leaned further out first,
      // so the lean finishes before the gesture starts playing.
      setReveal(needed);
      if (leanTimer) clearTimeout(leanTimer);
      leanTimer = setTimeout(() => {
        if (finished) return;
        playingGesture = gesture;
        gestureIndex = 0;
        render();
      }, SLIDE_DURATION_MS);

      const settleBack = SLIDE_DURATION_MS + GESTURE_FRAME_COUNT * FRAME_INTERVAL_MS + 200;
      setTimeout(() => {
        if (finished) return;
        setReveal(REST_REVEAL);
      }, settleBack);
      extendStay(settleBack + 400);
    }

    img.addEventListener("click", handleClick);

    // Let the hidden state paint before animating in.
    requestAnimationFrame(() => setReveal(REST_REVEAL));
    setTimeout(() => {
      interactive = true;
    }, SLIDE_DURATION_MS);

    scheduleLeave(SLIDE_DURATION_MS + randomInRange(HOLD_RANGE_MS));

    activePeek = {
      dismissNow() {
        if (finished) return;
        if (leaveTimer) clearTimeout(leaveTimer);
        if (leanTimer) clearTimeout(leanTimer);
        beginLeaving();
      }
    };
  }

  loadSettings(scheduleNext);
})();
