# Changelog

## 0.3.0 preview — 2026-10-27

- Add a separate wired-headset mode with explicit, device-scoped takeover of the built-in analogue headset remote.
- Default to click-to-start/click-to-stop so the microphone can capture speech after the physical button is released; keep hold-to-talk available for other microphone arrangements.
- Reuse shortcut settings on first setup, and store headset settings independently from S1 settings.
- Release input on stop, mode switch, unplug detection, sleep, timeout and normal app exit; pause S1 while headset mode is active.
- Show Input Monitoring and Accessibility status, a menu bar activity indicator, and a one-click return to system headset controls.
- Add core-only self-tests for gesture handling, cancellation, permission defaults and device matching.
- Keep headset events and safety timers running while menus track input; preserve modifiers in custom Fn shortcuts.
- Cancel an unfinished S1 shortcut recording when switching input modes.

## 0.2.2 — 2026-10-23

- Publish v0.2.2 as a regular GitHub release using the existing verified binary; add bilingual READMEs, language buttons, download badges, and native UI previews.
- Compile a native macOS icon stack so Tahoe no longer shrinks the mascot inside a grey compatibility tile; include the system-generated fallback for older macOS.
- Show the granted Accessibility state, refresh it when the app becomes active, and avoid requesting an already-granted permission.
- Keep ad-hoc signing for GitHub releases; describe removing an old permission entry only as troubleshooting when authorization is not recognized.

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
