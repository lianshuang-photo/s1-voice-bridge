# Changelog

## 0.2.1 — 2026-10-23

- Replace the app, Dock, and README icon with the white-haired, winking headset mascot.
- Include the selected artwork and its ImageGen prompt in the source repository.
- Update the portable release and launcher to 0.2.1; Bluetooth and audio behavior are unchanged.

## 0.2.0 — 2026-10-22

- Remember the last successfully connected S1 and reconnect on launch or peripheral wake.
- Preserve manual disconnect intent; support retry backoff and Bluetooth/system sleep recovery.
- Keep running from the menu bar when the window closes.
- Preserve shortcut, routing, and input settings across app restarts; migrate 0.1 settings.
- Bundle a relocatable CPython 3.12 runtime in the macOS release.
- Add the orange microphone app icon and branded app header.
- Report battery voltage instead of presenting an unconverted reading as battery level.
- Prevent older scan/connection timeout callbacks from cancelling newer requests.

## 0.1.0

- BLE S1 protocol/codec adapter, push-to-talk controls, virtual microphone routing, and WAV diagnostics.
- Local S1 capture and input-method integration validated with the user's device.
