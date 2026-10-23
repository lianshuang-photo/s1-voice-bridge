#!/usr/bin/env python3
"""Build the native app and a separate, user-invoked HAL audio installer."""
import hashlib
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"
BUILD = ROOT / "build"
VERSION = "0.2.2"


def run(args):
    subprocess.run([str(x) for x in args], check=True, cwd=ROOT)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, default=DIST)
    parser.add_argument("--portable", action="store_true", help="Bundle the local standalone CPython 3.12 runtime")
    args = parser.parse_args()
    output = args.output.resolve()
    app = output / "S1 Voice Bridge.app"
    output.mkdir(parents=True, exist_ok=True); BUILD.mkdir(exist_ok=True)
    python = os.environ.get("S1_PYTHON") or shutil.which("python3.12")
    if not python:
        candidate = Path.home() / ".local/bin/python3.12"
        python = str(candidate) if candidate.exists() else None
    if not python:
        raise SystemExit("请先安装 Python 3.12，或设置 S1_PYTHON 后重新构建。")
    result = subprocess.run([python, "-c", "import sys; print('%d.%d' % sys.version_info[:2])"], capture_output=True, text=True, check=True)
    if result.stdout.strip() != "3.12": raise SystemExit("S1_PYTHON 必须指向 Python 3.12。")
    run([python, ROOT / "backend/bridge_backend.py", "--probe"])

    # Upstream source is pinned and verified, never fetched at runtime.
    vendor = ROOT / "third_party/BlackHole"
    provenance = json.loads((vendor / "PROVENANCE.json").read_text())
    for name, expected in provenance["sha256"].items():
        if hashlib.sha256((vendor / name).read_bytes()).hexdigest() != expected:
            raise SystemExit(f"BlackHole 源码校验失败：{name}")
    stage = BUILD / "audio-package-root"
    driver = stage / "Library/Audio/Plug-Ins/HAL/S1BridgeAudio.driver"
    macos = driver / "Contents/MacOS"
    macos.mkdir(parents=True, exist_ok=True)
    driver_info = plistlib.loads((vendor / "BlackHole.plist").read_bytes())
    driver_info.update({
        "CFBundleExecutable": "S1BridgeAudio", "CFBundleIdentifier": "local.cherry.s1bridge.audio",
        "CFBundleName": "S1BridgeAudio", "CFBundleVersion": "0.1.0", "CFBundleShortVersionString": "0.1.0",
    })
    # A unique factory UUID avoids collisions with an existing stock BlackHole.
    factory = "c8265d50-94e5-477d-89fa-6fd8465456ca"
    driver_info["CFPlugInFactories"] = {factory: "BlackHole_Create"}
    driver_info["CFPlugInTypes"] = {"443ABAB8-E7B3-491A-B985-BEB9187030DB": [factory]}
    # Resolve Xcode placeholders in the upstream property list.
    driver_info = {k: (v.replace("$(PRODUCT_BUNDLE_IDENTIFIER)", "local.cherry.s1bridge.audio").replace("${PRODUCT_NAME}", "S1BridgeAudio").replace("$(PRODUCT_NAME)", "S1BridgeAudio") if isinstance(v, str) else v) for k, v in driver_info.items()}
    (driver / "Contents/Info.plist").write_bytes(plistlib.dumps(driver_info))
    run(["clang", "-O2", "-Wno-format-extra-args", "-arch", "arm64", "-mmacosx-version-min=13.0", "-bundle", "-fblocks",
         '-DkDriver_Name="S1BridgeAudio"', '-DkDevice_Name="S1 Bridge Audio"',
         '-DkPlugIn_BundleID="local.cherry.s1bridge.audio"', "-DkHas_Driver_Name_Format=false", "-DkNumber_Of_Channels=2",
         vendor / "BlackHole.c", "-framework", "CoreAudio", "-framework", "CoreFoundation", "-framework", "Accelerate",
         "-o", macos / "S1BridgeAudio"])
    run(["codesign", "--force", "--sign", "-", driver])
    package = output / "S1-Bridge-Audio.pkg"
    run(["pkgbuild", "--root", stage, "--identifier", "local.cherry.s1bridge.audio.installer", "--version", "0.1.0", "--ownership", "recommended", "--filter", r"/\._", package])

    binary = app / "Contents/MacOS/S1VoiceBridge"
    resources = app / "Contents/Resources"
    binary.parent.mkdir(parents=True, exist_ok=True); resources.mkdir(parents=True, exist_ok=True)
    sources = sorted((ROOT / "Sources").glob("*.swift"))
    run(["swiftc", "-swift-version", "5", "-O", "-debug-prefix-map", str(ROOT)+"=.", "-target", "arm64-apple-macosx13.0", *sources,
         "-framework", "SwiftUI", "-framework", "AppKit", "-framework", "CoreBluetooth",
         "-framework", "AVFoundation", "-framework", "CoreAudio", "-framework", "AudioToolbox", "-framework", "ApplicationServices",
         "-o", binary])
    info = {
        "CFBundleExecutable": "S1VoiceBridge", "CFBundleIdentifier": "local.cherry.s1voicebridge.demo",
        "CFBundleName": "S1 Voice Bridge", "CFBundleDisplayName": "S1 Voice Bridge",
        "CFBundlePackageType": "APPL", "CFBundleVersion": "4", "CFBundleShortVersionString": VERSION,
        "CFBundleIconFile": "AppIcon.icns",
        "LSMinimumSystemVersion": "13.0", "NSHighResolutionCapable": True,
        "NSBluetoothAlwaysUsageDescription": "连接你选择的讯飞 S1，接收按钮事件和语音音频。",
        "NSMicrophoneUsageDescription": "通过虚拟音频设备将 S1 收音交给目标输入工具。",
        "NSPrincipalClass": "NSApplication",
    }
    shutil.copytree(ROOT / "backend", resources / "backend", dirs_exist_ok=True, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    shutil.copy2(package, resources / package.name)
    shutil.copy2(ROOT / "README.md", resources / "README.md")
    shutil.copy2(vendor / "LICENSE", resources / "BlackHole-LICENSE")
    icon = ROOT / "Assets/AppIcon.png"
    if icon.exists():
        # Tahoe otherwise wraps a legacy-only ICNS in a grey compatibility tile.
        # Compile a native icon stack plus Apple's fallback for earlier macOS.
        icon_info = BUILD / "app-icon-info.plist"
        run(["xcrun", "actool", ROOT / "Assets/AppIcon.icon", "--compile", resources,
             "--platform", "macosx", "--minimum-deployment-target", "13.0",
             "--app-icon", "AppIcon", "--output-partial-info-plist", icon_info,
             "--output-format", "human-readable-text"])
        info.update(plistlib.loads(icon_info.read_bytes()))
        shutil.copy2(icon, resources / "Brandmark.png")
    (app / "Contents/Info.plist").write_bytes(plistlib.dumps(info))
    path_file = resources / "python-path.txt"
    if args.portable:
        prefix = Path(subprocess.check_output([python, "-c", "import sys; print(sys.base_prefix)"], text=True).strip())
        if not (prefix / "BUILD").exists():
            raise SystemExit("便携包需要 python-build-standalone / uv 提供的 CPython 3.12。")
        runtime = resources / "python"
        # copytree(dirs_exist_ok=True) still fails on already-present symlinks.
        # This directory is generated output; recreate it for reproducible rebuilds.
        if runtime.exists():
            shutil.rmtree(runtime)
        runtime.mkdir(exist_ok=True); (runtime / "bin").mkdir(exist_ok=True)
        shutil.copy2(prefix / "bin/python3.12", runtime / "bin/python3.12")
        shutil.copytree(prefix / "lib", runtime / "lib", dirs_exist_ok=True, symlinks=True,
                        ignore=shutil.ignore_patterns("__pycache__", "*.pyc", "pkgconfig"))
        # uv patches sysconfig to its installation prefix. Resolve those values
        # from the bundled interpreter at runtime instead of shipping a user path.
        for config in (runtime / "lib/python3.12").glob("_sysconfigdata_*.py"):
            content = config.read_text()
            for original in {str(prefix), str(prefix.resolve())}:
                content = content.replace(original, "__S1_EMBEDDED_PREFIX__")
            content += "\nimport sys as _s1_runtime_sys\nbuild_time_vars = {k: (v.replace('__S1_EMBEDDED_PREFIX__', _s1_runtime_sys.base_prefix) if isinstance(v, str) else v) for k, v in build_time_vars.items()}\ndel _s1_runtime_sys\n"
            config.write_text(content)
        shutil.copytree(prefix / "share", runtime / "share", dirs_exist_ok=True, symlinks=True)
        shutil.copy2(prefix / "BUILD", runtime / "BUILD")
        library = runtime / "lib/libpython3.12.dylib"
        run(["install_name_tool", "-id", "@rpath/libpython3.12.dylib", library])
        run(["codesign", "--force", "--sign", "-", library])
        path_file.unlink(missing_ok=True)
        run([runtime / "bin/python3.12", "-s", "-B", resources / "backend/bridge_backend.py", "--probe"])
    else:
        path_file.write_text(python + "\n")
    run(["codesign", "--force", "--sign", "-", app])
    run(["codesign", "--verify", "--deep", "--strict", app])
    run([binary, "--self-test"])
    run(["codesign", "--verify", "--deep", "--strict", app])
    print("\n已生成：", app)
    print("本次构建仅生成音频安装包；没有执行系统安装或切换默认设备。")


if __name__ == "__main__": main()
