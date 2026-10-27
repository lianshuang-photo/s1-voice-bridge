#!/usr/bin/env python3
"""Render the shipped native UI for docs without touching the running app."""
from pathlib import Path
import argparse
import plistlib
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build/readme-screenshots"
APP = BUILD / "ReadmeScreenshots.app"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=ROOT / "docs/images")
    args = parser.parse_args()
    resources = APP / "Contents/Resources"
    binary = APP / "Contents/MacOS/ReadmeScreenshots"
    resources.mkdir(parents=True, exist_ok=True)
    binary.parent.mkdir(parents=True, exist_ok=True)
    # Compile the actual view unchanged, excluding the production app delegate.
    views = BUILD / "ContentView.swift"
    views.write_text((ROOT / "Sources/App.swift").read_text().split("final class AppDelegate:", 1)[0])
    sources = [p for p in sorted((ROOT / "Sources").glob("*.swift")) if p.name not in {"App.swift", "SelfTests.swift"}]
    command = ["swiftc", "-swift-version", "5", "-O", *map(str, sources), str(views),
               str(ROOT / "scripts/render_readme_screenshots.swift")]
    for framework in ["SwiftUI", "AppKit", "CoreBluetooth", "AVFoundation", "CoreAudio", "AudioToolbox", "ApplicationServices", "IOKit"]:
        command.extend(["-framework", framework])
    subprocess.run([*command, "-o", str(binary)], check=True)
    shutil.copy2(ROOT / "Assets/AppIcon.png", resources / "Brandmark.png")
    (APP / "Contents/Info.plist").write_bytes(plistlib.dumps({
        "CFBundleExecutable": "ReadmeScreenshots",
        "CFBundleIdentifier": "local.s1voicebridge.docs-renderer",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "0.3.0",
        "LSUIElement": True,
    }))
    subprocess.run([str(binary), str(args.output.resolve())], check=True)


if __name__ == "__main__":
    main()
