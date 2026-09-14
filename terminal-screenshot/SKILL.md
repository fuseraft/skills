---
name: terminal-screenshot
description: "Capture a real screenshot of an actual terminal application running real commands — not an HTML/CSS mockup — on an isolated virtual display that never touches the user's real desktop or real settings. Trigger when the user wants an authentic CLI screenshot for a README, docs hero image, or blog post, or asks to replace a hand-drawn terminal mockup with the real thing."
compatibility: "Linux only, with an X11-capable desktop. Requires Xvfb, a GTK/X11 terminal emulator (tilix verified; others documented but untested), ImageMagick, and tmux. Not applicable on Windows or macOS."
---

# Terminal Screenshot

Get a pixel-real screenshot of a real terminal application doing real work, safely isolated from the user's actual desktop session and application settings. Built from a session where the naive version of this went wrong twice — read "Critical Safety Rules" before running anything.

## When to Use

Use this skill when:
- The user wants an authentic terminal screenshot for docs, a README hero, or marketing — not a hand-drawn HTML/CSS terminal mockup
- A previous mockup needs to be replaced with the real thing for credibility
- The exact rendered output (colors, wrapping, real command output) needs to be shown, not approximated

Do **not** use this skill for:
- Windows or macOS — this is Linux/X11-specific top to bottom (Xvfb, GTK backend, `wmctrl`)
- Cases where a plain text/code block would do — an image loses selectability and accessibility that real text has; only reach for a screenshot when the *visual* is the point
- Screenshotting a rendered web page (e.g. verifying a docs site) — that's plain Playwright/headless-browser work with none of this skill's risk profile; see "Bonus" at the end

## Critical Safety Rules

Both of these went wrong for real during the session this skill was extracted from. Read both before touching a terminal emulator.

### 1. The terminal can render on the user's REAL desktop

Most Linux desktops run Wayland. GTK/Qt apps prefer `WAYLAND_DISPLAY` over `DISPLAY` when both are set, so launching a terminal emulator with only `DISPLAY=:99` set can silently render its window on the user's live screen instead of the isolated display — even though you never touched their desktop on purpose.

Always:
- `env -u WAYLAND_DISPLAY -u XDG_SESSION_TYPE ... GDK_BACKEND=x11 DISPLAY=:99 <terminal-emulator> ...`
- Screenshot the isolated display **immediately** after launch to confirm real content is rendering there
- Check the real display too (`DISPLAY=:0 wmctrl -l`) for anything unexpected
- If a window appears on the real display, kill it immediately, tell the user what happened, and don't retry until you understand why

### 2. `gsettings`/`dconf` writes can mutate the user's REAL settings

Setting `HOME` for the child process does **not** isolate `gsettings set` or `dconf write`. `dconf-service` is a single per-user daemon reached over the shared session D-Bus bus (`DBUS_SESSION_BUS_ADDRESS`), so a `gsettings set` call routes to — and mutates — the user's real profile regardless of what `HOME` the calling process had. This actually happened: a user's real Tilix profile (background/foreground/font/window size) was silently overwritten this way, with no prior backup to restore from.

**Never use `gsettings`/`dconf` to theme or configure the throwaway terminal.** Set appearance at runtime only, via OSC terminal escape sequences sent as literal keystrokes into the live session — these affect only that one session and are never persisted anywhere:

```bash
printf '\e]10;#f3ede6\a\e]11;#171310\a\e]12;#e0784f\a\e]4;2;#8fc99b\a\e]4;6;#6fb8c9\a'
# 10=foreground  11=background  12=cursor  4;N=ANSI palette index N
```

If a config-file-based approach is ever unavoidable, the theoretically correct fix is `dbus-run-session` to get a genuinely fresh, isolated D-Bus session — untested in the session this skill came from, so verify the isolation (per Rule 2's spirit) before trusting it.

## Workflow

### Step 1: Confirm the environment

```bash
for c in tilix xterm kitty alacritty gnome-terminal konsole foot wezterm; do command -v "$c" && break; done
command -v Xvfb && command -v tmux && command -v wmctrl && (command -v magick || command -v import)
```

Prefer `tilix` if present — every command below was verified against it. `xterm` (`-geometry COLSxROWS`, `-e command`) is the most universally-available fallback and should generalize, but wasn't verified in the originating session; treat its exact flags as a starting point; check other emulators' `--help` yourself and adjust rather than assuming these examples' flags carry over.

### Step 2: Start an isolated virtual display

```bash
Xvfb :99 -screen 0 1600x1000x24 -nolisten tcp   # run with run_in_background: true
```

Pick a display number that isn't already in `/tmp/.X11-unix/` (`:0`/`:1` are usually the real desktop). Size it generously — bigger than the terminal window you intend to create — so there's no need to guess crop bounds later.

Verify it came up:
```bash
DISPLAY=:99 magick import -window root /path/to/probe.png   # should not error
```

### Step 3: Create the content session before touching any GUI

```bash
tmux new-session -d -s shot -x <cols> -y <rows>
tmux set-option -t shot status off   # tmux's own status bar would otherwise show in the screenshot
tmux has-session -t shot && echo alive   # confirm — see Gotchas below
```

Size `-x`/`-y` to comfortably fit everything you intend to show in one screen — resizing later means recreating the session and terminal window together. When in doubt, oversize; a taller-than-needed window just leaves blank space, but a too-short one silently scrolls your content's top (including any banner) off-screen with no error.

### Step 4: Launch the terminal emulator, forced to the isolated display

```bash
env -u WAYLAND_DISPLAY -u XDG_SESSION_TYPE DISPLAY=:99 GDK_BACKEND=x11 HOME=/path/to/scratch-home \
  tilix --new-process --window-style=disable-csd-hide-toolbar --geometry=<cols>x<rows> \
  -e "tmux attach -t shot"
# run with run_in_background: true — a plain `&`/`disown` does not reliably survive
# to the next tool call in a sandboxed harness; use the real backgrounding mechanism.
```

`HOME` here is only to keep the emulator's own cache/state dirs (`~/.cache`, `~/.local/share`) out of the real user's — it is **not** what isolates `gsettings` (see Rule 2). `--window-style=disable-csd-hide-toolbar` (tilix-specific) gives the cleanest capture: no title bar, no tab toolbar, just terminal content.

### Step 5: Verify isolation immediately — do not skip

```bash
DISPLAY=:0 wmctrl -l                                              # real desktop: expect nothing new
DISPLAY=:99 magick import -window root /path/to/probe.png         # isolated display: expect real content
```

Read the probe image. If it's blank/black, the emulator likely rendered on the real display instead (Rule 1) — stop and re-check the `env -u` flags before trying again, don't just retry blindly.

### Step 6 (optional): Set colors at runtime only

Send the OSC sequence from Rule 2 via `tmux send-keys`, never via `gsettings`. This is the *only* safe way to theme the throwaway session.

### Step 7: Drive the real content

```bash
tmux send-keys -t shot "<command>" Enter
```

Because tmux's server is reachable by socket from any shell running as the same user — not just the terminal emulator attached to it — you can keep sending commands from plain (non-GUI) `Bash` calls after the emulator is already showing the session live.

**Don't race the app.** Sending input immediately after launch can interleave keystrokes with the app's own startup — worse, some libraries (Spectre.Console and similar) probe the terminal via an OSC query (e.g. "what's your background color?") on startup, and if the raw escape-code reply isn't consumed yet, it can land in the input stream and corrupt whatever you send next. Poll for a clean, idle prompt instead of trusting a fixed `sleep`:

```bash
for i in $(seq 1 15); do
  sleep 1
  tmux capture-pane -t shot -p > /path/to/check.txt
  grep -qE '<your prompt regex> *$' /path/to/check.txt && break
done
```

**Read captured panes from a file, not a pipe.** `tmux capture-pane -p` piped straight into `tail`/`grep` inline can render empty — box-drawing/Unicode content trips naive pipe handling in some shells. Redirect to a file and read the file.

**If the content comes from a live model or other non-deterministic source**, constrain the prompt for length up front (e.g. "in 2 short sentences, ...") rather than hoping the response fits the window — a response that's too long will scroll earlier content (including any banner) off-screen with no visual indication it happened.

### Step 8: Capture and crop

```bash
DISPLAY=:99 magick import -window root /path/to/final-raw.png
```

Inspect it, then crop out the emulator's own chrome and the empty display background around it:
```bash
magick /path/to/final-raw.png -crop <W>x<H>+<X>+<Y> +repage /path/to/final.png
```
Iterate once on the crop bounds by inspecting the result — don't try to compute exact pixel bounds analytically.

### Step 9: Clean up and re-verify

```bash
tmux send-keys -t shot "<exit the app cleanly, e.g. its own quit command>" Enter
tmux kill-session -t shot
pkill -f "<terminal-emulator> --new-process"
pkill -f "Xvfb :99"
rm -rf /path/to/scratch-home
```

Re-check with `pgrep`/`tmux list-sessions` afterward — don't assume a kill command's exit code alone means the target is gone, and don't assume a *previous* creation step is still standing either: some sandboxed environments silently reap detached background processes (tmux server included) between tool calls. If a session or process you created earlier has vanished with no error, recreate it and re-verify rather than treating it as a mystery bug in the app you're screenshotting.

## Bonus: verifying the result in a rendered web page

If the screenshot is going into a doc site (e.g. as a hero image), verify the final rendered page with a headless browser rather than trusting the file in isolation:

```bash
node -e "
const { chromium } = require('playwright');   // resolve via its actual install path if not on NODE_PATH
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage({ viewport: { width: 1280, height: 1000 } });
  await page.goto('http://127.0.0.1:<port>/', { waitUntil: 'networkidle' });
  await page.screenshot({ path: 'out.png' });
  await browser.close();
})();
"
```

If the site is served by a dev server with hot-reload (e.g. `mkdocs serve`), note that template/theme-override changes don't always hot-reload the way content-page changes do — restart the dev server after editing a template rather than trusting a stale live-reload.
