# Sotto — hold a key, talk, and your words get typed

Sotto is a free voice-dictation app that lives in your Mac's menu bar.
Hold the **Right Option (⌥)** key, speak, let go — a second later your words
are typed into whatever app you were using: Mail, Safari, Notes, Slack, anywhere.

Everything happens **on your Mac**. No cloud, no account, no subscription.
Your voice never leaves your computer.

---

## Installing (build from source)

You need a Mac with Apple Silicon, macOS 13 or later, Xcode Command Line Tools
(`xcode-select --install`) and CMake (`brew install cmake`). Then:

```bash
git clone https://github.com/nomanclazure/sotto.git
cd sotto
bash scripts/build_app.sh
```

The script downloads and builds whisper.cpp, compiles Sotto, and installs it
to **/Applications/Sotto.app**. The first build takes a few minutes.

## Starting Sotto

Once installed, Sotto lives at **/Applications/Sotto.app** — open it like any app
(Spotlight → type "Sotto" → Enter). A small microphone icon appears in the
menu bar at the top-right of your screen. That's it — there is no window.

To have it start automatically every time you turn on your Mac:
click the menu bar icon → **Launch at Login**.

## First-time setup: three permissions

macOS requires your explicit OK before any app can hear you or type for you.
The first time Sotto opens, it walks you through this. If you missed it, click
the menu bar icon → **Check Permissions…** — every line must show ✅.

1. **Microphone** — a system pop-up appears; click **Allow**.
2. **Input Monitoring** (lets Sotto notice the hotkey in any app) —
   System Settings opens on **Privacy & Security → Input Monitoring**.
   Turn **ON** the switch next to **Sotto**. If Sotto isn't in the list,
   click **+**, then pick Sotto from the Applications folder.
3. **Accessibility** (lets Sotto type the text for you) —
   System Settings opens on **Privacy & Security → Accessibility**.
   Turn **ON** the switch next to **Sotto**.

**Important:** after granting Input Monitoring or Accessibility, quit Sotto
(menu bar icon → Quit Sotto) and open it again. macOS often applies these
permissions only on the next launch.

## Using it

1. Click into any text field.
2. **Hold** Right Option (⌥) — you'll hear a soft tick and the menu bar mic turns red.
3. Speak normally. Long dictation is fine (up to 5 minutes per hold).
4. **Release** the key. After a beat, your words appear.

A tap shorter than half a second is ignored on purpose, so accidentally
brushing the key does nothing.

## The menu (click the menu bar icon)

- **Enable Dictation** — master on/off switch.
- **Hotkey** — swap Right Option for Right Command, Right Control, Fn/Globe, or F13.
- **Microphone** — pick a specific mic, or leave on System Default.
- **Model** — the "brain" size. **Base (recommended)** is fast and accurate.
  *Tiny* is faster but sloppier; *Small* is a bit more accurate but slower to
  load. Picking a model you don't have yet downloads it once (progress shows
  in the menu); everything runs offline afterwards.
- **Play Sounds** — turn the start/stop ticks on or off.
- **Launch at Login** — start Sotto automatically.
- **Check Permissions…** — shows what's granted and takes you to the right settings page.
- **Quit Sotto** — fully stops the app.

All settings are remembered between launches.

## Troubleshooting

**1. I hold the key and speak, but no text appears.**
Almost always a permission. Menu bar icon → **Check Permissions…** — all three
lines must show ✅. Grant whatever is missing (steps above), then **quit Sotto
and open it again**. A yellow ⚠ menu bar icon specifically means Input
Monitoring is missing.

**2. Text appears but it's wrong, garbled, or empty.**
Check the right microphone is selected (menu → Microphone) — if you have
headphones with a mic plugged in, macOS may be listening to those. Speak a
little louder or closer to the mic. For better accuracy, try menu → Model →
**Small**.

**3. The menu bar icon shows a down-arrow, or dictation says the model is downloading.**
The speech model (a one-time ~142 MB download) isn't finished yet. Leave it a
couple of minutes on Wi-Fi. If it failed (no internet at the time), just pick
the model again under menu → Model to retry.

**Also worth knowing:** if you (or a future rebuild) replace Sotto.app,
macOS treats it as a brand-new app and silently drops Input Monitoring and
Accessibility — re-grant them via **Check Permissions…**, then quit and reopen.

## Uninstalling

1. Quit Sotto (menu bar icon → Quit Sotto).
2. Drag **/Applications/Sotto.app** to the Trash.
3. Optional: delete the downloaded models folder at
   `~/Library/Application Support/Sotto`.

## For the curious (technical)

- Speech recognition: [whisper.cpp](https://github.com/ggml-org/whisper.cpp)
  running OpenAI's Whisper models locally, GPU-accelerated via Metal.
  A 60-second dictation transcribes in about half a second on Apple Silicon.
- App: native Swift, no frameworks beyond macOS itself.
- To rebuild after changing code: `bash scripts/build_app.sh`
  (then re-grant permissions — see above).
- `Sotto/Sources/CWhisper/include` contains headers copied from whisper.cpp
  and ggml, which are MIT licensed (copyright the ggml authors).
- Text is inserted via the clipboard (Cmd+V is simulated); your previous
  clipboard contents are restored automatically about a second later.
