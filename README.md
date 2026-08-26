# DeskPet

A cat or a dog wanders up to the edge of your screen every so often, has a
look around, and ducks back out. Click one and it flicks an ear or waves a
paw. That's the whole app.

It lives in the menu bar (🐾) — no Dock icon, no window, no account, no
settings to configure. macOS 13 or later.

---

## Get the app

### Recommended: build it on your own Mac

Paste this into **Terminal** and press return:

```sh
curl -fsSL https://raw.githubusercontent.com/BansalAakash/DeskPet/main/install.sh | bash
```

It downloads the source, builds it, installs it, and starts it — about a
minute. A paw appears in your menu bar and you're done.

**No security warnings, no approval step.** macOS only quarantines apps that
arrive *from* the internet; one you compiled yourself is trusted from the
start. It also installs to `~/Applications` automatically if your Mac doesn't
let you write to `/Applications`, which is common on work machines.

The one requirement is Apple's developer tools. If they're missing the script
starts the installer and asks you to run it again — that's a one-time,
Apple-provided download.

Prefer to read it before running it? That's the same file:
[`install.sh`](install.sh).

### Alternative: download a prebuilt app

**[Download the latest release →](../../releases/latest)** and take the file
ending in **`-macOS-app.zip`**. (GitHub also lists *Source code (zip)* and
*(tar.gz)* on every release — those are the code, not something you can open.)

Unzip it, drag `DeskPet.app` to **Applications**, and double-click.
**macOS will refuse to open it the first time** — open  → **System Settings
→ Privacy & Security**, scroll to the bottom, and click **Open Anyway**.

That extra step exists because Apple only waives it for developers who pay
$99/year to have each build notarised. It isn't a warning about anything the
app does. Building locally avoids it entirely, which is why that's the
recommended route.

> On macOS 15 and later the old right-click → **Open** shortcut no longer
> works. If you prefer the Terminal:
> `xattr -d com.apple.quarantine /Applications/DeskPet.app`

### If something goes wrong

```sh
curl -fsSL https://raw.githubusercontent.com/BansalAakash/DeskPet/main/Scripts/diagnose.sh | bash
```

Prints a short summary of what happened — whether the app crashed, or was
shut down by something else on the machine (which is what usually happens on
a managed work laptop).

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
| `Scripts/release.sh` | Package and publish a GitHub release (`v1.0`) |
| `Scripts/gen_gestures.py` | Regenerate every sprite from the source art |
| `Scripts/diagnose.sh` | Summarise a crash or a policy kill |
| `install.sh` | One-command build-and-install, for users |

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
