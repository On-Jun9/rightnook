#!/usr/bin/env python3
"""Package the verified release bundle and write its SHA-256 checksum."""
import hashlib
from pathlib import Path
import plistlib
import subprocess
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parent.parent


def package():
    app = ROOT / "_build/Release/RightNook.app"
    version = (ROOT / "VERSION").read_text().strip()
    build_number = (ROOT / "BUILD_NUMBER").read_text().strip()
    for bundle in [app, app / "Contents/PlugIns/RightNookFinder.appex", app / "Contents/Helpers/RightNookFileCreator.app"]:
        info = plistlib.loads((bundle / "Contents/Info.plist").read_bytes())
        if info["CFBundleShortVersionString"] != version or info["CFBundleVersion"] != build_number:
            raise RuntimeError("빌드 버전이 소스와 다릅니다. 다시 빌드해 주세요.")
    subprocess.run(["/usr/bin/codesign", "--verify", "--deep", "--strict", str(app)], check=True)
    destination = ROOT / "dist"
    destination.mkdir(exist_ok=True)
    archive = destination / ("RightNook-" + version + ".zip")
    temporary = archive.with_suffix(".zip.tmp")
    try:
        subprocess.run(["/usr/bin/ditto", "-c", "-k", "--keepParent", "--norsrc", str(app), str(temporary)], check=True)
        with ZipFile(temporary) as package_file:
            if package_file.testzip() is not None or any(not name.startswith("RightNook.app/") for name in package_file.namelist()):
                raise RuntimeError("배포 ZIP 구조를 확인할 수 없습니다.")
        temporary.replace(archive)
    finally:
        temporary.unlink(missing_ok=True)
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    (destination / "SHA256SUMS.txt").write_text(digest + "  " + archive.name + "\n")
    print(archive)


if __name__ == "__main__":
    package()
