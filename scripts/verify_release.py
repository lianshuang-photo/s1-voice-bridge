#!/usr/bin/env python3
"""Verify the actual release ZIP after extraction and runtime relocation."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile
import zipfile


def main():
    p = argparse.ArgumentParser()
    p.add_argument("archive", type=Path)
    args = p.parse_args()
    forbidden = ("live-status.json", "Recordings/", "settings.json", "iFLYAssistant.app", "python-path.txt")
    with zipfile.ZipFile(args.archive) as z:
        assert z.testzip() is None, "ZIP integrity failure"
        for item in z.infolist():
            path = Path(item.filename)
            assert not path.is_absolute() and ".." not in path.parts, "Invalid ZIP path"
            assert not any(name in item.filename for name in forbidden), item.filename
            if not item.is_dir():
                assert str(Path.home()).encode() not in z.read(item), "Local home path in " + item.filename
    with tempfile.TemporaryDirectory(prefix="s1-release-verification-") as directory:
        subprocess.run(["ditto", "-x", "-k", str(args.archive.resolve()), directory], check=True)
        apps = list(Path(directory).glob("*/S1 Voice Bridge.app"))
        assert len(apps) == 1, "Expected one app"
        app = apps[0]
        subprocess.run(["codesign", "--verify", "--deep", "--strict", str(app)], check=True)
        env = dict(os.environ)
        env.pop("PYTHONHOME", None); env.pop("PYTHONPATH", None)
        env["PYTHONNOUSERSITE"] = "1"; env["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        subprocess.run([str(app / "Contents/MacOS/S1VoiceBridge"), "--self-test"], env=env, check=True, timeout=20)
        runtime = app / "Contents/Resources/python"
        code = 'import sys,sysconfig,json; print(json.dumps({"prefix":sys.prefix,"configured":sysconfig.get_config_var("prefix")}))'
        result = subprocess.check_output([str(runtime / "bin/python3.12"), "-B", "-s", "-c", code], env=env, text=True)
        values = json.loads(result)
        assert Path(values["prefix"]).resolve() == runtime.resolve()
        assert Path(values["configured"]).resolve() == runtime.resolve()
    print("PASS: public package audit, extracted signature, native self-test, bundled Python and sysconfig relocation")


if __name__ == "__main__": main()
