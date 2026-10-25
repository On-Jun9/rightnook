#!/usr/bin/env python3
"""Install only this project's app; never touches another Finder extension."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import shutil
import signal
import subprocess
import time
import uuid

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "_build/Release/RightNook.app"
TARGET = Path.home() / "Applications/RightNook.app"
LEGACY_TARGET = TARGET.with_name("QuickRight.app")
BUNDLE_ID = "local.hj.quickright"
EXTENSION_ID = BUNDLE_ID + ".finder"


def run(command, **kwargs):
    return subprocess.run([str(x) for x in command], check=True, **kwargs)


def bundle_id(path):
    return plistlib.loads((path / "Contents/Info.plist").read_bytes()).get("CFBundleIdentifier")


def stop_previous_build(previous_bundles):
    allowed = set()
    for bundle in previous_bundles:
        for prefix in ["RightNook", "QuickRight"]:
            allowed.update({str(bundle / ("Contents/MacOS/" + prefix)),
                            str(bundle / ("Contents/Helpers/" + prefix + "FileCreator.app/Contents/MacOS/" + prefix + "FileCreator")),
                            str(bundle / ("Contents/PlugIns/" + prefix + "Finder.appex/Contents/MacOS/" + prefix + "Finder"))})
    output = run(["/bin/ps", "-axo", "pid=,comm="], capture_output=True, text=True).stdout
    stopped = []
    for line in output.splitlines():
        parts = line.strip().split(None, 1)
        if len(parts) != 2 or parts[1] not in allowed:
            continue
        pid = int(parts[0])
        current = subprocess.run(["/bin/ps", "-p", str(pid), "-o", "comm="], capture_output=True, text=True)
        if current.returncode == 0 and current.stdout.strip() == parts[1]:
            os.kill(pid, signal.SIGTERM)
            stopped.append(pid)
    for _ in range(50):
        if not any(subprocess.run(["/bin/ps", "-p", str(pid), "-o", "comm="], capture_output=True).returncode == 0 for pid in stopped):
            return stopped
        time.sleep(0.1)
    raise RuntimeError("이전 RightNook이 종료되지 않았습니다. 앱을 닫고 다시 설치해 주세요.")


def install(source=SOURCE):
    if bundle_id(source) != BUNDLE_ID:
        raise RuntimeError("빌드된 앱 식별자가 다릅니다.")
    if TARGET.is_symlink() or (TARGET.exists() and bundle_id(TARGET) != BUNDLE_ID):
        raise RuntimeError("기존 경로가 다른 앱이므로 덮어쓰지 않습니다.")
    previous_bundles = [TARGET] if TARGET.exists() else []
    # Only replace this project's former app, never another app named QuickRight.
    if not LEGACY_TARGET.is_symlink() and LEGACY_TARGET.exists() and bundle_id(LEGACY_TARGET) == BUNDLE_ID:
        previous_bundles.append(LEGACY_TARGET)
    TARGET.parent.mkdir(parents=True, exist_ok=True)
    stage = TARGET.parent / (".RightNook-install-" + uuid.uuid4().hex + ".app")
    backups = []
    run(["/usr/bin/ditto", source, stage])
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", stage])
    stopped = stop_previous_build(previous_bundles)
    register = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
    try:
        for previous in previous_bundles:
            backup = TARGET.parent / (".RightNook-previous-" + uuid.uuid4().hex)
            previous.rename(backup)
            backups.append((previous, backup))
        stage.rename(TARGET)
        run([register, "-f", TARGET])
        run([register, "-f", TARGET / "Contents/Helpers/RightNookFileCreator.app"])
        run(["/usr/bin/pluginkit", "-a", TARGET / "Contents/PlugIns/RightNookFinder.appex"])
        run(["/usr/bin/pluginkit", "-e", "use", "-i", EXTENSION_ID])
        match = run(["/usr/bin/pluginkit", "-m", "-v", "-i", EXTENSION_ID], capture_output=True, text=True).stdout
        if EXTENSION_ID not in match or str(TARGET / "Contents/PlugIns/RightNookFinder.appex") not in match:
            raise RuntimeError("Finder 확장 등록을 확인할 수 없습니다.")
    except Exception:
        if not stage.exists() and TARGET.exists():
            shutil.rmtree(TARGET)
        for previous, backup in reversed(backups):
            backup.rename(previous)
            run([register, "-f", previous])
            for prefix in ["RightNook", "QuickRight"]:
                extension = previous / ("Contents/PlugIns/" + prefix + "Finder.appex")
                if extension.exists():
                    run(["/usr/bin/pluginkit", "-a", extension])
        raise
    for _, backup in backups:
        shutil.rmtree(backup)
    # Drop the former path from Launch Services after a successful replacement.
    if LEGACY_TARGET in previous_bundles:
        subprocess.run([register, "-u", LEGACY_TARGET], check=False, capture_output=True)
    result = {"installed_path": str(TARGET), "stopped_previous_processes": stopped,
              "extension_registration": match, "other_extensions_modified": False,
              "replaced_legacy_app": LEGACY_TARGET in previous_bundles}
    (ROOT / "_build/install-info.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n")
    print(match)
    print("설치 완료:", TARGET)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=SOURCE, help="설치할 앱 번들 경로")
    install(parser.parse_args().source)
