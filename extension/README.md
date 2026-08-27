# DeskPet for Chrome

The same idea as the macOS app, ported to the browser: a cat or a dog peeks
in from the edge of your browser window every so often, has a look around,
and ducks back out. Click it for an ear flick or a paw wave. Works no
matter which tab you're on — each tab runs its own independent schedule,
so switching tabs always lands you on a live pet, not a frozen one.

Not published to the Chrome Web Store — install it as an unpacked
extension:

1. Open `chrome://extensions` in Chrome.
2. Turn on **Developer mode** (top right).
3. Click **Load unpacked** and select this `extension/` folder.

That's it — no build step, no dependencies.

## How it differs from the macOS app

- **No cross-tab or cross-app coordination.** The native app enforces one
  character on screen at a time across every display; this extension has
  no equivalent for tabs. Each tab's content script runs its own
  independent scheduler reading the same shared settings, so if you have
  two browser windows open side by side, both could peek at once. In the
  common case of one window with many tabs, only the tab you're actually
  looking at is ever visibly peeking — a hidden tab still schedules
  peeks, but they render into a document nobody's looking at, and Chrome
  throttles a hidden tab's timers on its own regardless.
- **No per-pixel click hit-testing.** The native app only registers a
  click on the character's actually-opaque pixels, via an alpha mask, so
  clicks on the transparent margin around it fall through to whatever's
  underneath. This extension's click target is the sprite's full
  rectangular bounding box instead — clicking the (mostly small,
  transparent) padding around the character will still catch the click
  rather than passing it through to the page.
- **No background-owned scheduling.** MV3 service workers get killed
  after ~30s idle, so they can't reliably hold a countdown anywhere from
  5 seconds to 5 minutes. Each content script owns its own timer instead
  — see the comment at the top of `content.js`.
- **Settings are separate.** This extension has its own toolbar popup and
  its own `chrome.storage.local`, entirely independent of the macOS app's
  `UserDefaults`. Turning one off doesn't affect the other.

## Files

| File | Role |
| --- | --- |
| `manifest.json` | Extension manifest (MV3) |
| `content.js` | Everything: scheduling, DOM/CSS overlay, sprite animation, click gestures |
| `background.js` | Seeds default settings on install only — no scheduling happens here |
| `popup.html` / `popup.js` | Toolbar popup: Enabled, Frequency, Animals, Peek Now |
| `sprites/` | Same art as the macOS app's `Sources/DeskPet/Resources/species/` |
| `icons/` | Toolbar icon, generated from a cat sprite frame |
