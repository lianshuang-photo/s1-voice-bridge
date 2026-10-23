"""Read the installed iFLYAssistant SDK in place; never copy or modify it.

The adapter supports the CPython 3.12 PyInstaller build inspected on this machine.
Only the device protocol, codec, and their dependencies may be imported. It does
not import the iFLY application, account, UI, transcription, or network modules.
"""
from __future__ import annotations

import importlib.abc
import importlib.machinery
import importlib.util
import marshal
import pathlib
import plistlib
import struct
import sys
import zlib


class SDKError(RuntimeError):
    pass


class InstalledSDK(importlib.abc.MetaPathFinder, importlib.abc.Loader):
    ALLOWED = ("mspeech", "loguru", "Crypto")
    DEVICE_MODULES = {
        "mspeech", "mspeech.protocol", "mspeech.mspeech_framework",
        "mspeech.mspeech_framework_enum", "mspeech.mspeech_utils",
        "mspeech.mspeech_pcm", "mspeech.protocol.protocol_constants",
        "mspeech.protocol.protocol_data", "mspeech.protocol.protocol_utils",
        "mspeech.protocol.protocol_manager_classical",
        "mspeech.protocol.protocol_manager_default",
    }

    def __init__(self, app="/Applications/iFLYAssistant.app"):
        if sys.version_info[:2] != (3, 12):
            raise SDKError("本机讯飞协议模块需要 Python 3.12，请重新运行构建脚本。")
        self.app = pathlib.Path(app).resolve()
        self.resources = self.app / "Contents/Resources"
        try:
            info = plistlib.loads((self.app / "Contents/Info.plist").read_bytes())
            if info.get("CFBundleIdentifier") != "com.iflytek.aidevice":
                raise SDKError("指定位置不是讯飞语音助手。")
            self.version = info.get("CFBundleShortVersionString", "unknown")
            blob = (self.app / "Contents/MacOS" / info["CFBundleExecutable"]).read_bytes()
        except (OSError, KeyError, plistlib.InvalidFileException) as exc:
            raise SDKError("找不到完整的讯飞语音助手安装，请保留 /Applications/iFLYAssistant.app。") from exc
        marker = bytes([77, 69, 73, 12, 11, 10, 11, 14])
        end = blob.rfind(marker)
        if end < 0 or end + 88 > len(blob):
            raise SDKError("此版本讯飞助手的打包格式尚未适配。")
        _, length, toc_offset, toc_length, python_version, _ = struct.unpack("!8sIIII64s", blob[end:end + 88])
        if python_version != 312:
            raise SDKError(f"讯飞助手内置 Python {python_version}，当前适配器只支持 312。")
        base = end + 88 - length
        pos, stop = base + toc_offset, base + toc_offset + toc_length
        if not 0 <= base <= pos <= stop <= len(blob):
            raise SDKError("讯飞助手归档边界无效。")
        self.pyz = None
        while pos < stop:
            entry_length, offset, size, _, compressed, _ = struct.unpack("!IIIIBc", blob[pos:pos + 18])
            if entry_length < 18 or pos + entry_length > stop:
                raise SDKError("讯飞助手归档索引无效。")
            name = blob[pos + 18:pos + entry_length].rstrip(b"\0")
            pos += entry_length
            if name == b"PYZ.pyz":
                self.pyz = blob[base + offset:base + offset + size]
                if compressed:
                    self.pyz = zlib.decompress(self.pyz)
                break
        if not self.pyz or self.pyz[:4] != b"PYZ\0":
            raise SDKError("找不到讯飞设备协议归档。")
        if self.pyz[4:8] != importlib.util.MAGIC_NUMBER:
            raise SDKError("Python 字节码版本不匹配。")
        self.entries = dict(marshal.loads(self.pyz[struct.unpack("!i", self.pyz[8:12])[0]:]))

    def permitted(self, name):
        if name == "mspeech" or name.startswith("mspeech."):
            return name in self.DEVICE_MODULES
        return any(name == p or name.startswith(p + ".") for p in ("loguru", "Crypto"))

    def find_spec(self, fullname, path=None, target=None):
        if not self.permitted(fullname):
            return None
        if fullname not in self.entries:
            return None
        kind, _, size = self.entries[fullname]
        return importlib.util.spec_from_loader(fullname, self, is_package=kind in (1, 3))

    def create_module(self, spec):
        return None

    def exec_module(self, module):
        name = module.__name__
        kind, offset, size = self.entries[name]
        location = self.resources.joinpath(*name.split("."))
        module.__file__ = str(location / "__init__.py" if kind in (1, 3) else location.with_suffix(".py"))
        if kind in (1, 3):
            module.__path__ = [str(location)]
        if size:
            code = marshal.loads(zlib.decompress(self.pyz[offset:offset + size]))
            exec(code, module.__dict__)

    def install(self):
        sys.dont_write_bytecode = True
        sys.meta_path.insert(0, self)
        # Native Crypto dependencies are loaded by their original package paths.
        import loguru
        loguru.logger.remove()
        loguru.logger.disable("")
        from mspeech.mspeech_framework import Framework
        from mspeech.mspeech_pcm import MSpeechPcm, MSpeechPcmLib
        from mspeech import mspeech_framework_enum as enums
        return Framework, MSpeechPcm, MSpeechPcmLib, enums
