S1 Voice Bridge v0.3.0 预览版新增“有线耳机”模式，适用于当前测试的 Mac 内置 3.5mm 接口单键线控耳机。

- 单独接管耳机线控，避免该按钮同时唤起 Siri；保留系统其他 Siri 入口和音频路由。
- 默认点一下开始说话、再点一下结束，复用 Fn 或自定义快捷键。
- 切换回 S1 模式时释放耳机接管，并恢复 S1 的自动连接。
- 关闭接管、正常退出、拔出检测、电脑休眠或达到时长上限时结束输入。
- 耳机模式直接使用目标输入工具选择的麦克风，不需要讯飞助手或 S1 Bridge Audio，也不保存耳机录音。
- 修复菜单展开时计时暂停、Fn 组合键修饰键丢失，以及切换模式时快捷键录入状态残留。

**实测注意：** 当前耳机按住按钮时麦克风输出静音，松开后恢复，因此默认推荐点按开关。USB / 蓝牙线控及三键耳机音量转发尚未支持。

下载 `S1-Voice-Bridge-v0.3.0-macOS-arm64.zip`。首次使用耳机模式需要输入监控及辅助功能权限；当前仍为 ad-hoc 签名，更新后可能需要重新授权。

测试版构建 6 已由使用者实际完成有线耳机输入，并确认点按开始和结束正常。发布包构建 7 另包含切换模式取消未完成快捷键录入的清理，已通过离线自检和发布包检查；完整验证边界见下方记录。

[有线耳机说明 / Headset guide](https://github.com/lianshuang-photo/s1-voice-bridge/blob/main/docs/HEADSET.md) · [验证范围](https://github.com/lianshuang-photo/s1-voice-bridge/blob/main/docs/VERIFICATION.md)

This preview adds device-scoped control of a single-button wired headset remote. Click to start and click again to finish. The tested analogue headset mutes its microphone while the button is held, so click mode is the default. Choose the external microphone in your input tool; iFLYTEK software and the virtual driver are not needed for this mode. Input Monitoring and Accessibility permissions are required. See the headset guide for the tested scope and limitations.
