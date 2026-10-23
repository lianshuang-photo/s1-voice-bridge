"""Isolated protocol/codec worker. JSON-lines stdin/stdout; no Bluetooth or network.

Bluetooth belongs to the macOS app, which owns its permission and device choice.
The worker uses the unmodified, locally installed vendor handshake/codec.
"""
from __future__ import annotations

import argparse
import base64
import ctypes as c
import json
import os
import sys
import threading
import time
from vendor_sdk import InstalledSDK

_wire = os.fdopen(os.dup(sys.stdout.fileno()), "w", buffering=1)
_lock = threading.Lock()
# Vendor diagnostic prints must never corrupt the JSON stream or reveal device data.
sys.stdout = open(os.devnull, "w")


def emit(event, **values):
    with _lock:
        _wire.write(json.dumps(dict(event=event, **values), ensure_ascii=False) + "\n")


class DeviceSession:
    def __init__(self, sdk, generation):
        self.Framework, self.Pcm, self.PcmLib, self.enums = sdk
        self.generation = generation
        self.active = True
        self.authorized = False
        self.handshake_ok = False
        self.native = self.PcmLib()
        self.decoders = []
        self.decode_lock = threading.Lock()
        self.noted_formats = set()
        for _ in range(2):
            decoder = self.Pcm()
            self.native.mspeech_pcm_construct(c.pointer(decoder))
            result = decoder.init(c.pointer(decoder), self.enums.MSPEECH_ENCODE_ICO, 1)
            if not result:
                raise RuntimeError("讯飞 ICO 音频解码器初始化失败。")
            self.decoders.append(decoder)
        self.framework = self.Framework(self.write, self.key, self.action, self.audio, self.info)

    def event(self, event, **kwargs):
        if self.active:
            emit(event, generation=self.generation, **kwargs)

    def write(self, _address, data, size):
        self.event("write", data=base64.b64encode(bytes(data[:size])).decode())

    def key(self, state, _address, value):
        if state in (self.enums.MSPEECH_FRAMEWORK_EVENT_KEY_DOWN, self.enums.MSPEECH_FRAMEWORK_EVENT_KEY_UP):
            self.event("key", down=state == self.enums.MSPEECH_FRAMEWORK_EVENT_KEY_DOWN, key=int(value))
        elif state == self.enums.MSPEECH_FRAMEWORK_EVENT_BLE_DISCONNECTED:
            self.event("device_disconnected")

    def action(self, _address, action, value):
        e = self.enums
        if action == e.MSPEECH_FRAMEWORK_ACTION_HANDSHAKE:
            self.handshake_ok = value == 1
            self.event("handshake", ok=self.handshake_ok)
        elif action == e.MSPEECH_FRAMEWORK_ACTION_AUTHENTICATION:
            self.authorized = value == 1
            self.event("authentication", ok=self.authorized)
        elif action in (e.MSPEECH_FRAMEWORK_ACTION_START_RECORD, e.MSPEECH_FRAMEWORK_ACTION_STOP_RECORD):
            self.event("record_ack", started=action == e.MSPEECH_FRAMEWORK_ACTION_START_RECORD, status=int(value))
        elif action == e.MSPEECH_FRAMEWORK_ACTION_BATTERY:
            self.event("battery", value=int(value))

    def info(self, kind, _address, data, size):
        e = self.enums
        if kind == e.MSPEECH_FRAMEWORK_INFO_DEVICE_PRODUCTNO:
            raw = bytes(data[:size]) if not isinstance(data, int) else data.to_bytes(4, "little")
            printable = raw.rstrip(b"\0").decode("ascii", "replace")
            self.event("product", name=printable if printable.isprintable() else "unknown")
        elif kind == e.MSPEECH_FRAMEWORK_INFO_PROTOCOL_VERSION:
            self.event("protocol", version=int(data) if isinstance(data, int) else None)

    def audio(self, audio_type, channel, _address, buffer, length):
        if not self.active:
            return
        fmt = (audio_type, channel)
        if fmt not in self.noted_formats:
            self.noted_formats.add(fmt)
            self.event("audio_format", codec=int(audio_type), channel=int(channel))
        # The inspected macOS BLE adapter decodes type 2 with the ICO decoder.
        # Unknown types are reported instead of guessing and emitting noise.
        if audio_type != 2 or channel not in (0, 1) or not 0 < length <= 2048:
            self.event("unsupported_audio", codec=int(audio_type), channel=int(channel), length=int(length))
            return
        with self.decode_lock:
            # Native ABI has no input-length argument. Allocate a padded input and
            # oversized output; validate its returned sample count before reading.
            raw = bytes(buffer[:length])
            incoming = (c.c_ubyte * 4096)()
            c.memmove(incoming, raw, len(raw))
            output = (c.c_ushort * 8192)()
            sample_count = c.c_ushort(0)
            decoder = self.decoders[channel]
            result = decoder.convert2pcm(c.byref(decoder), c.cast(incoming, c.POINTER(c.c_ushort)), output, c.byref(sample_count))
            if not result or not 0 < sample_count.value <= 8192:
                self.event("decode_error")
                return
            pcm = c.string_at(output, sample_count.value * 2)
        self.event("pcm", channel=int(channel), samples=sample_count.value, data=base64.b64encode(pcm).decode())

    def handshake(self):
        try:
            self.framework.handshake()
        except Exception as exc:
            self.event("error", message=f"设备握手失败：{type(exc).__name__}")

    def feed(self, data):
        if not 1 <= len(data) <= 8192:
            raise ValueError("蓝牙数据长度超出范围")
        self.framework.append_data(list(data), len(data))

    def start(self):
        if not self.handshake_ok:
            raise RuntimeError("握手尚未成功，不能开始录音。")
        self.framework.start_record()

    def stop(self):
        if self.handshake_ok:
            self.framework.stop_record()

    def close(self):
        self.active = False
        # Framework owns background threads. The app terminates this isolated
        # process on disconnect; no vendor globals survive into another session.


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--app", default="/Applications/iFLYAssistant.app")
    parser.add_argument("--probe", action="store_true")
    args = parser.parse_args()
    installed = InstalledSDK(args.app)
    sdk = installed.install()
    native = sdk[2]()  # Validate architecture and dynamic-library loading now.
    if args.probe:
        decoder = sdk[1]()
        native.mspeech_pcm_construct(c.pointer(decoder))
        ok = decoder.init(c.pointer(decoder), sdk[3].MSPEECH_ENCODE_ICO, 1)
        if not ok:
            raise RuntimeError("音频解码器未通过初始化检查。")
        decoder.uninit(c.pointer(decoder))
        emit("probe", ok=True, version=installed.version, hardware_tested=False)
        return
    emit("ready", version=installed.version, hardware_tested=False)
    session = None
    for line in sys.stdin:
        try:
            if len(line) > 131072:
                raise ValueError("命令长度超限")
            msg = json.loads(line)
            command = msg.get("command")
            if command == "quit":
                if session:
                    session.close()
                emit("bye")
                return
            if command == "attach":
                if session:
                    raise RuntimeError("每个进程仅允许一个设备会话，请重新连接。")
                session = DeviceSession(sdk, int(msg["generation"]))
                threading.Thread(target=session.handshake, daemon=True).start()
            elif command in ("data", "start", "stop", "battery"):
                if session is None:
                    raise RuntimeError("尚未建立协议会话。")
                if command == "data":
                    session.feed(base64.b64decode(msg["data"], validate=True))
                elif command == "start":
                    session.start()
                elif command == "stop":
                    session.stop()
                else:
                    session.framework.get_battery()
            else:
                raise ValueError("未知命令")
        except Exception as exc:
            emit("error", message=f"{type(exc).__name__}: {str(exc)[:180]}")


if __name__ == "__main__":
    code = 0
    try:
        main()
    except Exception as exc:
        emit("fatal", message=f"{type(exc).__name__}: {str(exc)[:240]}")
        code = 1
    finally:
        _wire.flush()
        os._exit(code)
