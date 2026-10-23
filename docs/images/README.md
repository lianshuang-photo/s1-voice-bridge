# Product images

- `app-icon.png`: macOS 26.2's system-rendered icon from the installed v0.2.2 app.
- `app-overview.png` and `auto-reconnect.png`: native `ContentView` captures from v0.2.2, using illustrative state in an isolated documentation process. Device labels and diagnostics are sample data. These are interface illustrations, not additional hardware-test evidence.

Regenerate the interface images on macOS with `python3 scripts/render_readme_screenshots.py`. This tool compiles the production view unchanged into a documentation renderer. It does not start BLE, audio capture, or shortcut output, and does not read personal settings or recordings.
