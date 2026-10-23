"""Meaningful offline compatibility checks, not a hardware acceptance test."""
import json
from pathlib import Path
import subprocess
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
BACKEND = ROOT / "backend"


class BackendTests(unittest.TestCase):
    def test_codec_probe_is_offline_and_loads_installed_sdk(self):
        p = subprocess.run([sys.executable, str(BACKEND / "bridge_backend.py"), "--probe"], capture_output=True, text=True, timeout=10)
        self.assertEqual(p.returncode, 0, p.stderr + p.stdout)
        result = json.loads(p.stdout)
        self.assertTrue(result["ok"])
        self.assertFalse(result["hardware_tested"])
        self.assertEqual(result["version"], "4.4.36.4")

    def test_missing_app_is_a_structured_failure(self):
        p = subprocess.run([sys.executable, str(BACKEND / "bridge_backend.py"), "--probe", "--app", "/nonexistent/S1-test.app"], capture_output=True, text=True, timeout=10)
        self.assertNotEqual(p.returncode, 0)
        self.assertEqual(json.loads(p.stdout)["event"], "fatal")

    def test_worker_rejects_commands_without_a_device_and_quits(self):
        commands = '\n'.join(json.dumps(x) for x in [{"command": "start"}, {"command": "not-supported"}, {"command": "quit"}]) + '\n'
        p = subprocess.run([sys.executable, str(BACKEND / "bridge_backend.py")], input=commands, capture_output=True, text=True, timeout=10)
        events = [json.loads(x)["event"] for x in p.stdout.splitlines()]
        self.assertEqual(events, ["ready", "error", "error", "bye"])
        self.assertEqual(p.returncode, 0)

    def test_vendor_real_frame_parser_fragmentation_and_button_events(self):
        # Exercise the installed parser through append_data, including split GATT
        # notifications. The synthetic packet is never sent to a physical device.
        program = r'''
import json, os, sys
sys.path.insert(0, sys.argv[1])
from vendor_sdk import InstalledSDK
sdk = InstalledSDK(); Framework, _, _, e = sdk.install()
from mspeech.protocol import protocol_constants as k
events = []
f = Framework(lambda *x: None, lambda state, address, value: events.append((state,value)), lambda *x: None, lambda *x: None, lambda *x: None)
def frame(state):
    payload = bytes([k.EVENT_TYPE_KEY]) + ((3 << 16) | state).to_bytes(4,'little')
    return bytes([0xfe, 1, 9]) + len(payload).to_bytes(4,'little') + payload + bytes(4)
down, up = frame(k.EVENT_KEY_DOWN), frame(k.EVENT_KEY_UP)
f.append_data(list(down[:6]),6)
assert not events
f.append_data(list(down[6:]),len(down)-6)
f.append_data(list(up),len(up))
assert events == [(e.MSPEECH_FRAMEWORK_EVENT_KEY_DOWN,3),(e.MSPEECH_FRAMEWORK_EVENT_KEY_UP,3)], events
assert sdk.permitted('mspeech.mspeech_framework')
assert not sdk.permitted('proc_device')
assert not sdk.permitted('mspeech.bundle_ble')
assert not sdk.permitted('util.constants')
print(json.dumps({'ok':True,'button_events':len(events),'split_notification':True}),flush=True)
os._exit(0)
'''
        p = subprocess.run([sys.executable, "-c", program, str(BACKEND)], capture_output=True, text=True, timeout=10)
        self.assertEqual(p.returncode, 0, p.stdout + p.stderr)
        self.assertEqual(json.loads(p.stdout)["button_events"], 2)


if __name__ == "__main__": unittest.main()
