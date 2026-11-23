# Sotto

**Free, open-source voice dictation for the Mac. Hold a key, talk, let go, and your words are typed wherever your cursor is.**

Sotto is a free alternative to paid dictation apps like Wispr Flow. It lives in
the menu bar and works in any app: Mail, Safari, Notes, Slack, your code editor.

- **Free and open source.** MIT licensed. No account, no subscription, no trial.
- **Private.** Speech is transcribed on your Mac. Your audio is never sent anywhere.
- **Fast.** A 60-second dictation transcribes in about half a second on Apple Silicon.
- **Works offline.** After a one-time model download, no internet is needed.

Sotto is an independent project. It is not affiliated with Wispr Flow or OpenAI.

## Requirements

- A Mac with Apple Silicon (M1 or newer)
- macOS 14 (Sonoma) or newer
- English dictation only, for now

## Install

1. Download **[Sotto.zip](https://github.com/nomanclazure/sotto/releases/latest/download/Sotto.zip)**
   from the latest release.
2. Double-click the zip to unpack it, then drag **Sotto** into your **Applications** folder.
3. Open Sotto. The first time, macOS will refuse because the app is not signed
   with a paid Apple developer certificate. To allow it:
   - Open **System Settings → Privacy & Security**.
   - Scroll down to the message about Sotto and click **Open Anyway**.

   If you are comfortable in Terminal, this one command does the same thing:

   ```bash
   xattr -dr com.apple.quarantine /Applications/Sotto.app
   ```

4. A small microphone icon appears in the menu bar at the top right of your
   screen. Sotto has no window and no Dock icon.

On first launch Sotto downloads its speech model (about 142 MB, one time).

Prefer to build it yourself? See [Build from source](#build-from-source).

## First-time setup: three permissions

macOS asks for your OK before any app can hear you or type for you. Sotto walks
you through this the first time it opens. If you missed it, click the menu bar
icon → **Check Permissions…**. Every line must show ✅.

1. **Microphone.** A system pop-up appears. Click **Allow**.
2. **Input Monitoring.** This lets Sotto notice the hotkey in any app. System
   Settings opens on **Privacy & Security → Input Monitoring**. Turn on the
   switch next to **Sotto**. If Sotto is not in the list, click **+** and pick
   Sotto from the Applications folder.
3. **Accessibility.** This lets Sotto type the text for you. System Settings
   opens on **Privacy & Security → Accessibility**. Turn on the switch next to
   **Sotto**.

After granting Input Monitoring or Accessibility, quit Sotto (menu bar icon →
Quit Sotto) and open it again. macOS often applies these only on the next launch.

## Using it

1. Click into any text field.
2. **Hold** Right Option (⌥). You hear a soft tick and the menu bar mic turns red.
3. Speak normally. Long dictation is fine, up to 5 minutes per hold.
4. **Release** the key. A moment later your words appear.

A tap shorter than half a second is ignored, so brushing the key by accident
does nothing.

## The menu

Click the menu bar icon for these options:

- **Enable Dictation.** Master on/off switch.
- **Hotkey.** Swap Right Option for Right Command, Right Control, Fn/Globe, or F13.
- **Microphone.** Pick a specific mic, or leave it on System Default.
- **Model.** *Base* (recommended, 142 MB) is fast and accurate. *Tiny* (75 MB)
  is faster but sloppier. *Small* (466 MB) is more accurate but slower to load.
  Picking a model you don't have yet downloads it once.
- **Play Sounds.** Turn the start/stop ticks on or off.
- **Launch at Login.** Start Sotto automatically when you log in.
- **Check Permissions…** Shows what is granted and opens the right settings page.
- **Quit Sotto.**

Settings are remembered between launches.

## How it works

1. **Hotkey.** Sotto watches for your hotkey system-wide. This is why it needs
   Input Monitoring.
2. **Recording.** While the key is held, Sotto records from your microphone
   into memory. Nothing is written to disk.
3. **Transcription.** When you release, the audio goes to
   [whisper.cpp](https://github.com/ggml-org/whisper.cpp), which runs OpenAI's
   Whisper speech model on your Mac's GPU through Metal.
4. **Typing.** Sotto puts the text on the clipboard, simulates Cmd+V in the app
   you were using, then restores your previous clipboard about a second later.
   This is why it needs Accessibility.

The only time Sotto uses the network is to download a speech model from
Hugging Face. Your audio and your text stay on your Mac.

The app is native Swift with no dependencies beyond macOS and whisper.cpp.

## Troubleshooting

**I hold the key and speak, but no text appears.**
This is almost always a permission. Menu bar icon → **Check Permissions…**. All
three lines must show ✅. Grant whatever is missing, then quit Sotto and open it
again. A yellow ⚠ menu bar icon means Input Monitoring is missing.

**Text appears but it is wrong, garbled, or empty.**
Check the right microphone is selected (menu → Microphone). If headphones with
a mic are plugged in, macOS may be listening to those. Speak a little louder or
closer. For better accuracy, try menu → Model → **Small**.

**The menu bar icon shows a down-arrow.**
The speech model is still downloading. Give it a couple of minutes on Wi-Fi. If
it failed, pick the model again under menu → Model to retry.

**I opened Sotto and nothing happened.**
Sotto has no window. Look for the microphone icon in the menu bar. On a MacBook
with a notch, a crowded menu bar can hide it behind the notch.

**Dictation stopped working after I updated or rebuilt Sotto.**
macOS treats a replaced app as a new app and drops Input Monitoring and
Accessibility. Grant them again through **Check Permissions…**, then quit and
reopen.

## Build from source

You need Xcode Command Line Tools (`xcode-select --install`) and CMake
(`brew install cmake`).

```bash
git clone https://github.com/nomanclazure/sotto.git
cd sotto
bash scripts/build_app.sh
```

The script downloads whisper.cpp at a pinned commit, builds it, compiles
Sotto, and installs it to `/Applications/Sotto.app`. The first build takes a
few minutes. Add `--no-install` to only produce `build/Sotto.app`.

To check a build without using the microphone:

```bash
Sotto/.build/release/Sotto --selftest
```

Project layout:

- `Sotto/Sources/Sotto` is the app (Swift).
- `Sotto/Sources/CWhisper` holds the whisper.cpp headers the app links against.
- `scripts/` has the build scripts, `Info.plist`, and the app icon.

## Uninstalling

1. Quit Sotto (menu bar icon → Quit Sotto).
2. Drag `/Applications/Sotto.app` to the Trash.
3. Optional: delete the downloaded models in `~/Library/Application Support/Sotto`.

## License

Sotto is released under the [MIT License](LICENSE). It builds on whisper.cpp
and OpenAI's Whisper models. See [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
