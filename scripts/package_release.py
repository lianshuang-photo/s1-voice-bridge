#!/usr/bin/env python3
"""Create a clean end-user ZIP; never include local settings or voice recordings."""
import argparse
import hashlib
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", default="0.3.0")
    args = parser.parse_args()
    version = args.version
    output = ROOT / "releases" / f"v{version}"
    app = output / "S1 Voice Bridge.app"
    if not (app / "Contents/Resources/python/bin/python3.12").exists():
        raise SystemExit("请先用 --portable 构建发布 App。")
    subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    staging = output / f"S1 Voice Bridge {version}"
    if staging.exists():
        shutil.rmtree(staging)
    staging.mkdir(exist_ok=True)
    subprocess.run(["ditto", str(app), str(staging / app.name)], check=True)
    shutil.copy2(output / "S1-Bridge-Audio.pkg", staging / "S1-Bridge-Audio.pkg")
    shutil.copy2(ROOT / "LICENSE", staging / "LICENSE.txt")
    shutil.copy2(ROOT / "third_party/BlackHole/LICENSE", staging / "BlackHole-LICENSE.txt")
    (staging / "先读我.txt").write_text(f"""S1 Voice Bridge {version}

1. 把 S1 Voice Bridge.app 放到 /Applications，并从固定位置打开。
有线耳机模式：
- 选择顶部“有线耳机”，授予输入监控和辅助功能权限，再开启“接管有线耳机按键”。
- 默认点一下开始、再点一下结束。当前实测耳机长按按钮时麦克风静音，点按可在松开后正常收音。
- 目标输入工具选择“外置麦克风”，不要选择 S1 Bridge Audio；Fn/快捷键设置与目标工具保持一致。
- 此模式不需要讯飞助手，也不需要虚拟音频驱动；不保存耳机录音。
- 仅验证内置 3.5mm 接口的单键线控；USB/蓝牙耳机及三键线控的音量转发尚未支持。

讯飞 S1 模式：
2. 保留官方讯飞助手 /Applications/iFLYAssistant.app（已验证 4.4.36.4），使用时退出它。
3. 首次配对并连接 S1，授予蓝牙权限。首次连接成功后会记住设备，之后唤醒自动连接。
4. 首次使用安装 S1-Bridge-Audio.pkg；安装后若设备未显示，重启音频服务或 Mac。
5. App 和输入法都选 S1 Bridge Audio，设置相同快捷键，授予本 App 辅助功能权限。
6. 豆包长按模式若为 Fn，App 也选 Fn + 按住型。不会自动提交消息。
7. 关闭窗口后在菜单栏继续运行，点“退出”才完全停止。

辅助功能显示“已授权”时无需再次操作。当前签名方式下，更新后可能需要重新授权；
仅当系统开关已开启、App 仍提示未授权时，移除旧条目，再添加 /Applications 中的新版本。
当前发布包为本地 ad-hoc 签名，未做 Apple 公证。
已含 Python 3.12，无需另外安装 Python；讯飞组件不随包分发。
原始收音/输入链路已真机跑通，新增自动重连通过离线测试，需进一步开关/休眠验收。
完整源码、测试与说明见同一 GitHub 仓库。
""", encoding="utf-8")
    archive = output / f"S1-Voice-Bridge-v{version}-macOS-arm64.zip"
    subprocess.run(["ditto", "-c", "-k", "--sequesterRsrc", "--keepParent", str(staging), str(archive)], check=True)
    checksum = hashlib.sha256(archive.read_bytes()).hexdigest()
    (output / "SHA256SUMS.txt").write_text(f"{checksum}  {archive.name}\n", encoding="ascii")
    print(archive)
    print(f"{archive.stat().st_size / 1024 / 1024:.1f} MiB; SHA-256 {checksum}")


if __name__ == "__main__": main()
