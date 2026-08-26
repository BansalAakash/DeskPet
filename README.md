# DeskPet

A cat or a dog wanders up to the edge of your screen every so often, has a
look around, and ducks back out. Click one and it flicks an ear or waves a
paw. That's the whole app.

It lives in the menu bar (🐾) — no Dock icon, no window, no account, no
settings to configure. macOS 13 or later.

---

## Get the app

DeskPet is **not notarised by Apple** — that costs $99/year — so macOS can't
vouch for it. Both routes below deal with that honestly rather than asking
you to run something unseen.

### Option 1 — Homebrew (checksum-verified)

```sh
brew tap BansalAakash/deskpet https://github.com/BansalAakash/DeskPet
brew install --cask --no-quarantine deskpet
```

Homebrew downloads the release, checks it against a SHA-256 pinned in
[`Casks/deskpet.rb`](Casks/deskpet.rb), and refuses to install if a single
byte differs. The cask is a short, readable file in this repo — worth
[reading first](Casks/deskpet.rb).

`--no-quarantine` skips the Gatekeeper prompt. Leave it off if you'd rather
approve the app yourself in System Settings → Privacy & Security.

Update with `brew upgrade --cask deskpet`, remove with
`brew uninstall --cask deskpet`.

### Option 2 — build it yourself (nothing to trust)

The most cautious route: read the code, then compile it. Nothing downloaded
runs until you've looked at it, and an app you build locally is never
quarantined, so macOS raises no warning at all.

```sh
git clone https://github.com/BansalAakash/DeskPet.git
cd DeskPet
less Scripts/build_app.sh     # ~60 lines; see what it will do
./Scripts/build_app.sh
cp -R DeskPet.app /Applications/
open /Applications/DeskPet.app
```

Needs Apple's developer tools (`xcode-select --install`). Takes about a
minute.

### Verifying a manual download

If you'd rather grab the zip straight from the
[releases page](../../releases/latest), check it before opening it:

```sh
shasum -a 256 DeskPet-v1.1-macOS-app.zip
```

Compare the output against the checksum printed in that release's notes. Take
the file ending in **`-macOS-app.zip`** — GitHub also attaches *Source code
(zip)* and *(tar.gz)*, which are the code, not something you can open.

### If something goes wrong

From a checkout: `./Scripts/diagnose.sh`. It prints a short summary — whether
the app crashed, or was shut down by something else on the machine, which is
what usually happens on a managed work laptop.

## The menu

| Item | What it does |
| --- | --- |
| **Enabled** | Pause or resume without quitting |
| **Frequency** | Often (15–45s), Normal (45–120s), Rare (2–5 min) |
| **Animals** | Turn individual characters on or off |
| **Peek Now** | Show one right away — replaces any that's already out |
| **Open at Login** | Start automatically with your Mac |
| **Quit** | |

To uninstall: quit from the menu, then drag `DeskPet.app` out of
`/Applications` (or `~/Applications`) to the Trash. Nothing else is left
behind but a small preferences file.

## What it can and can't do
<a id="what-it-can-and-cant-do"></a>

It draws in a transparent, click-through overlay and does nothing else.

- **No network code.** Not "it doesn't phone home" — there is no networking
  in the app at all.
- **No permissions.** No Accessibility, no Screen Recording, no file access.
  macOS never prompts for anything.
- **It can't steal your clicks.** Clicks register only on the character's own
  pixels; everywhere else they pass straight through to the app underneath.
- **One at a time.** Never more than a single character on screen.

---

## For developers
<a id="for-developers"></a>

Plain SwiftUI + AppKit, no third-party dependencies.

```sh
git clone https://github.com/BansalAakash/DeskPet.git
cd DeskPet
./Scripts/build_app.sh && open DeskPet.app
```

Needs the Swift toolchain — Xcode, or `xcode-select --install`.

### Scripts

| Script | Purpose |
| --- | --- |
| `Scripts/build_app.sh` | Build `DeskPet.app` (`--dev` adds the checks below) |
| `Scripts/run_tests.sh` | Build with checks, run them all, rebuild clean |
| `Scripts/package.sh` | Build + zip for a release |
| `Scripts/release.sh` | Publish a release and pin its checksum into the cask |
| `Scripts/gen_gestures.py` | Regenerate every sprite from the source art |
| `Scripts/diagnose.sh` | Summarise a crash or a policy kill |

### How it's put together

| File | Role |
| --- | --- |
| `PeekScheduler` | Decides when/where/who peeks next; caps it at one at a time |
| `PeekWindowController` | Owns one peek: its panel, timings, clicks, gestures |
| `PeekGeometry` | Pure layout maths — edges, reveal depths, hit testing |
| `PeekContentView` | Draws the character; plays the idle loop and gestures |
| `SpriteLibrary` | Loads and caches art; builds click masks |
| `Settings` | UserDefaults wrapper |
| `SelfTest` | Development checks (not shipped) |

A few decisions worth knowing before you change things:

- **The window never moves.** Each peek is a fixed panel flush against a
  screen edge, and the character slides *inside* it. An earlier version moved
  a larger window partly off-screen, which broke the moment a second display
  sat on that edge — the "hidden" half rendered on the neighbouring monitor.
- **Rotation is applied in the view, not baked into the art.** Pre-rotating
  would rasterise at one fixed scale and look wrong on mixed-DPI setups.
- **Gestures are synthesised.** The source pack ships only an idle bob, so
  ear flicks and paw waves are generated by isolating a body part from the
  alpha channel and rotating it about its joint. Every sequence starts and
  ends on the exact idle pose so playback can cut in and out seamlessly.
- **Reveal depth is per-gesture.** Ears show at rest; the arms sit below the
  resting cut, so a paw wave leans the character further out first — without
  that, the wave plays entirely off-screen.

### Development checks

```sh
./Scripts/run_tests.sh
```

Covers layout across simulated multi-display arrangements (including a
display placed *above* the primary, which broke an earlier version), click
routing, whether each gesture's motion actually lands on screen, and the
face mix. They're compiled out of release builds behind `#if PEEK_DEV`, so
none of it ships.

### Artwork

```sh
python3 Scripts/gen_gestures.py           # preview; contact sheets to /tmp
python3 Scripts/gen_gestures.py --write   # update the app's resources
```

Downloads and caches the original pack, then derives everything — the two
face variants and all gesture frames. Needs `pillow` and `numpy`. See
[`LICENSE-ASSETS.md`](LICENSE-ASSETS.md) for the art's provenance and licence.

## Licence

Code is MIT — see [`LICENSE`](LICENSE). The artwork is CC0 and separately
credited in [`LICENSE-ASSETS.md`](LICENSE-ASSETS.md).
