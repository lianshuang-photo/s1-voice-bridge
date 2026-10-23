**S1 Voice Bridge v0.2.2 正式发布。** 把讯飞 T8 的 S1 语音夹变成 Mac 上的无线按住说话按钮，支持虚拟麦克风、Fn / 自定义快捷键、记住设备自动连接和菜单栏后台运行。

[简体中文说明](https://github.com/lianshuang-photo/s1-voice-bridge#readme) · [English README](https://github.com/lianshuang-photo/s1-voice-bridge/blob/main/README.en.md)

修复 macOS Tahoe 的 Dock 图标灰框：使用原生图标资源，保留选定的眨眼耳麦角色，避免人物缩在灰色底板内。

调整图层位置，使蓝色衣服接到图标底边，消除下方黄色留白。已通过 macOS 26.2 系统图标渲染核对。

辅助功能已开启时显示“辅助功能已授权”，从系统设置返回 App 后自动刷新。已经授权时不会再次请求权限。

下载 `S1-Voice-Bridge-v0.2.2-macOS-arm64.zip`，内含 Apple Silicon / macOS 13+ App、虚拟音频安装包和中文说明。已有 S1 Bridge Audio 时无需重复安装驱动。

发布包使用 ad-hoc 签名，尚未做 Apple 公证；升级后仍可能需要重新授权。只有系统开关已开启、App 仍提示未授权时，才需要移除旧权限条目并添加 `/Applications` 中的新版本。

运行仍需本机安装讯飞语音助手，使用时退出助手但保留安装文件。蓝牙、收音和快捷键逻辑与 v0.2.1 相同，自动重连的多轮真实开关和休眠验收仍待完成。

本次正式发布沿用已验证的 v0.2.2 安装包，文件及校验值保持一致；已安装 v0.2.2 的用户无需重新安装。

---

**S1 Voice Bridge v0.2.2 is now a regular release.** Use the iFLYTEK S1 clip as a wireless push-to-talk button on an Apple Silicon Mac, with virtual microphone routing, configurable shortcuts, automatic reconnect, and menu bar operation.

This version fixes the grey Dock icon frame on macOS Tahoe, removes the yellow gap below the mascot's jacket, and displays the actual Accessibility permission state. Chinese and English documentation now include native interface previews.

Requires macOS 13+ and the separately installed iFLYTEK assistant (verified version 4.4.36.4). The archive includes Python 3.12 and the optional audio installer. It uses ad-hoc signing and is not Apple-notarized; updates may require Accessibility reauthorization. Repeated hardware power/sleep-cycle testing remains pending.

The existing v0.2.2 download and checksums are unchanged. If v0.2.2 is already installed, no reinstall is needed.
