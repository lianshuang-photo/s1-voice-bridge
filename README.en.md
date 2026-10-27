<p align="center"><img src="docs/images/app-icon.png" width="116" alt="S1 Voice Bridge icon"></p>

<h1 align="center">S1 Voice Bridge</h1>

<p align="center"><b>Turn your iFLYTEK S1 voice clip into a wireless push-to-talk button for your Mac.</b></p>
<p align="center">Hold to speak · Release to finish · Reconnect on wake</p>

<p align="center">
  <a href="README.md"><img src="docs/badges/zh.svg" alt="简体中文 README"></a>
  <a href="README.en.md"><img src="docs/badges/en-active.svg" alt="English"></a>
</p>

<p align="center">
  <a href="https://github.com/lianshuang-photo/s1-voice-bridge/releases/latest"><img src="docs/badges/release.svg" alt="Release v0.2.2"></a>
  <img src="docs/badges/macos.svg" alt="macOS 13 or later">
  <img src="docs/badges/arch.svg" alt="Apple Silicon arm64">
  <a href="LICENSE"><img src="docs/badges/license.svg" alt="GPL-3.0 License"></a>
</p>

<p align="center">
  <a href="https://github.com/lianshuang-photo/s1-voice-bridge/releases/download/v0.2.2/S1-Voice-Bridge-v0.2.2-macOS-arm64.zip"><img src="docs/badges/download.svg" alt="Download for Mac"></a>
</p>

<p align="center">
  <a href="#quick-start">Quick start</a> ·
  <a href="https://github.com/lianshuang-photo/s1-voice-bridge/releases/tag/v0.2.2">Release notes</a> ·
  <a href="https://github.com/lianshuang-photo/s1-voice-bridge/issues">Report an issue</a>
</p>

---

S1 Voice Bridge receives Bluetooth audio and button events from the **S1 voice clip bundled with the iFLYTEK T8 keyboard**. It routes audio into the **S1 Bridge Audio virtual microphone** and triggers your input tool's keyboard shortcut, making the clip useful for dictating code, messages, and notes.

**Current release: v0.2.2.** This is an independent open-source project, unaffiliated with iFLYTEK, Doubao, WeChat, or OpenAI.

**v0.3.0 preview adds a wired-headset mode** for single-button remotes on the built-in 3.5mm jack. [Download the preview](https://github.com/lianshuang-photo/s1-voice-bridge/releases/tag/v0.3.0) · [Headset guide / 耳机说明](docs/HEADSET.md). It uses the microphone selected in your input tool directly, without the iFLYTEK assistant or a virtual audio driver.

## Product preview

<p align="center"><img src="docs/images/app-overview.png" width="820" alt="Native S1 Voice Bridge interface showing automatic connection, virtual microphone routing, and Fn shortcut settings"></p>
<p align="center"><sub>Rendered from the v0.2.2 native UI with illustrative device and diagnostic data. These images show the interface, not additional hardware test results. The app UI is currently in Simplified Chinese; this page provides English documentation.</sub></p>

<details>
<summary><b>See the automatic reconnect state</b></summary>

<p align="center"><img src="docs/images/auto-reconnect.png" width="820" alt="Example interface waiting for the remembered S1 voice clip to wake and reconnect"></p>

After the first successful manual connection, the app remembers your S1. Keep it running in the menu bar so it can reconnect when the clip wakes.

</details>

## Features

| Feature | What it does |
| --- | --- |
| 🎙️ Push to talk | Hold the S1 button to capture audio; release to finish after the audio tail. Messages are never submitted automatically. |
| 🔁 Automatic connection | Remembers the last successfully connected S1, with startup reconnect, retries, and sleep recovery. |
| ⌨️ Shortcut control | Supports Fn and custom shortcuts, with hold-to-talk or toggle-to-talk behavior. |
| 🎚️ Virtual microphone | Sends S1 audio to third-party input tools that let you select a microphone. |
| 🧷 Menu bar operation | Keeps running when the window closes and remembers shortcut, routing, and output settings. |
| 🔍 Audio diagnostics | Includes a level meter, local WAV capture, playback, diagnostic export, and a recording time limit. |

The portable release includes Python 3.12, so users do not need to install Python separately.

## Requirements

These requirements apply to **S1 mode**. Wired-headset mode has separate device and permission requirements in the [headset guide](docs/HEADSET.md).

1. An **Apple Silicon Mac running macOS 13+**. Hardware testing so far used macOS 26.2.
2. **The S1 voice clip bundled with the iFLYTEK T8.** The S1 and the keyboard are separate devices; connecting only the keyboard is not enough.
3. The official [iFLYTEK voice assistant](https://mouse.iflytek.com/#/download), normally installed at `/Applications/iFLYAssistant.app`. Verified version: **4.4.36.4**.
4. Quit the official assistant while using S1 Voice Bridge to avoid device contention, but keep it installed.

This project does not redistribute iFLYTEK code, libraries, credentials, or account data. At runtime it reads the protocol and codec components from the user's existing installation.

## Quick start

Download [S1-Voice-Bridge-v0.2.2-macOS-arm64.zip](https://github.com/lianshuang-photo/s1-voice-bridge/releases/download/v0.2.2/S1-Voice-Bridge-v0.2.2-macOS-arm64.zip).

1. Extract the ZIP and move **S1 Voice Bridge.app** to `/Applications`. Use that fixed location afterward.
2. Remove and wake the S1 clip, pair it in macOS Bluetooth settings, open the app, and grant Bluetooth access. Choose “扫描 S1” (Scan S1), then “连接” (Connect).
3. Initially leave “虚拟麦克风与快捷键联动” (virtual microphone and shortcut routing) off. Hold the clip's button, speak, release, then use “播放上次录音” (Play last recording) to check the audio.
4. Run the included `S1-Bridge-Audio.pkg`, or choose “安装音频组件” in the app. Skip this if **S1 Bridge Audio** is already installed.
5. If the device does not appear after refreshing, restart the system audio service or your Mac. Restarting only the app does not reload the system audio driver.
6. Grant S1 Voice Bridge access under System Settings → Privacy & Security → Accessibility, and enable routing. Select **S1 Bridge Audio** as both the app's output and your input tool's microphone.
7. Set matching voice-input shortcuts in both apps. Focus a text field and hold the S1 button to speak.

After the first successful connection, the app remembers the device. It can wait for a sleeping S1 to wake, without another scan. If you forget the device in system settings or replace it, pair and connect it successfully again.

### Doubao input method example

| Setting | Doubao input method | S1 Voice Bridge |
| --- | --- | --- |
| Microphone / output | S1 Bridge Audio | S1 Bridge Audio |
| Shortcut | Fn | Fn |
| Trigger | Hold-to-talk | 按住型 (hold mode) |

For tools that start and stop recording with separate presses, choose “开关型” (toggle mode). The default `Control + Shift + D` is only an example; match the target tool's actual settings.

## Accessibility permission after an update

No action is needed when the app shows “辅助功能已授权” (Accessibility granted); it refreshes the state when you return from System Settings.

Current releases use ad-hoc signing and are not Apple-notarized. After an update, macOS may retain a permission entry for the previous signature. **Only if the system toggle is on but the app still reports no access**, remove the old entry, add the new `/Applications/S1 Voice Bridge.app`, enable it, and relaunch the app. Make sure you select the installed version, not another build copy.

## Automatic reconnect behavior

- Keep the app running. Closing its window leaves it in the menu bar; Quit stops it completely.
- It does not change system pairing, turn on Bluetooth, add login items, or connect to unfamiliar devices.
- Select and successfully connect a device manually once. Only a device with a successful handshake is remembered.
- A manual Disconnect pauses reconnection. Choose “立即重连” (Reconnect now) or reopen the app to resume.
- The app waits while Bluetooth is off and resumes when it returns. Failed attempts use backoff up to 30 seconds.
- Rejected handshakes, incompatible protocols, or decoding failures pause reconnection instead of retrying indefinitely.
- Wait for “已就绪” (Ready) after waking the clip. The initial wake press is not guaranteed to capture a complete utterance.

## Verification status

Hardware checks have covered the S1 connection, handshake, physical button events, 16 kHz decoding, and clear playback. macOS and Doubao recognized the virtual microphone, and the input-method workflow was confirmed working.

Offline checks cover reconnect policy, pause behavior, backoff, sleep recovery, settings migration, and execution after moving the portable app to another directory. One successful reconnect and handshake was observed after the v0.2.2 update.

Repeated clip power cycles, sleep, and extended standby still need further validation. WeChat, Codex, and other input tools depend on their microphone selection and shortcut support and have not been individually validated. See the [verification record](docs/VERIFICATION.md) for the full scope.

## Data and privacy

- Settings and the remembered device identifier stay in `~/Library/Application Support/S1VoiceBridgeDemo/`.
- Local recordings are stored in its `Recordings/` directory. You can turn off “保存本地测试录音” (Save local test recordings).
- `live-status.json` contains status, counters, and recent diagnostics. Exports do not include audio or recognized text; review device information and file paths before sharing them publicly.
- The app itself does not call an online speech-recognition service. When routing is enabled, your chosen input tool handles audio according to its own settings.
- It does not modify the official assistant, write firmware, or read iFLYTEK accounts or history.
- It does not automatically change system-default audio devices. If an input tool only uses the system default microphone, select it yourself.

## Build from source

Requires Xcode 26+ with `actool`, Python 3.12, and the installed iFLYTEK assistant.

```sh
python3 scripts/build.py
python3.12 -m unittest discover -s tests -v
dist/'S1 Voice Bridge.app'/Contents/MacOS/S1VoiceBridge --self-test
```

For a portable release, use a CPython 3.12 runtime from uv / python-build-standalone:

```sh
python3 scripts/build.py --output releases/v0.3.0 --portable
python3 scripts/package_release.py --version 0.3.0
python3 scripts/verify_release.py releases/v0.3.0/S1-Voice-Bridge-v0.3.0-macOS-arm64.zip
```

Building only creates the audio installer; it does not install it or restart the audio service. Set `S1_PYTHON` to select a Python 3.12 interpreter. To regenerate the native UI documentation images, run `python3 scripts/render_readme_screenshots.py`; it uses isolated sample data without connecting to hardware or sending shortcuts.

Use `S1VoiceBridge --self-test-core` for checks that do not require the iFLYTEK installation. `--self-test` additionally verifies the local vendor protocol worker.

## License and acknowledgments

- Project code is licensed under **[GPL-3.0](LICENSE)**. See [NOTICE.md](NOTICE.md) for third-party notices.
- Virtual audio is based on [BlackHole](https://github.com/ExistentialAudio/BlackHole) v0.7.1; upstream source, licensing, and pinned-source checksums are retained.
- Portable releases preserve CPython and bundled-component license files.
- The mascot icon was generated with ImageGen. Artwork and prompts are documented in [Assets](Assets/IMAGEGEN.md).
- Inspired by [MiVibe Remote](https://github.com/wyuzhi/MiVibe-Remote) and [Open Voice Bridge](https://github.com/nijez/open-voice-bridge). No Xiaomi device protocol is used to control the S1.

## Uninstall

Quit from the menu bar, then remove the app. Settings and recordings remain separate. The optional audio driver is located at `/Library/Audio/Plug-Ins/HAL/S1BridgeAudio.driver`; removing it requires administrator access, followed by restarting the audio service or the Mac.
