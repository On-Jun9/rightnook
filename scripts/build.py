#!/usr/bin/env python3
"""Build the native app, Finder extension, and isolated file creator."""
import argparse
import json
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def run(command):
    subprocess.run([str(part) for part in command], check=True)


def build(identity="-"):
    out = ROOT / "_build/Release"
    app = out / "RightNook.app"
    extension = app / "Contents/PlugIns/RightNookFinder.appex"
    creator = app / "Contents/Helpers/RightNookFileCreator.app"
    report_path = out / "build-info.json"
    version = (ROOT / "VERSION").read_text().strip()
    build_number = int((ROOT / "BUILD_NUMBER").read_text().strip())
    if not re.fullmatch(r"\d+\.\d+\.\d+", version) or build_number < 1:
        raise RuntimeError("VERSION 또는 BUILD_NUMBER를 확인해 주세요.")
    # Rebuild the output bundle so old resources and signatures cannot remain.
    if app.exists():
        shutil.rmtree(app)
    for directory in [app / "Contents/MacOS", extension / "Contents/MacOS", creator / "Contents/MacOS"]:
        directory.mkdir(parents=True, exist_ok=True)
    for bundle in [app, creator]:
        resources = bundle / "Contents/Resources"
        resources.mkdir(parents=True, exist_ok=True)
        for name in ["LICENSE", "THIRD_PARTY_NOTICES.txt"]:
            shutil.copy2(ROOT / name, resources / name)
        shutil.copy2(ROOT / "Resources/RightNook.icns", resources / "RightNook.icns")
    templates = ROOT / "Sources/Core/Resources/FileTemplates"
    bundled_templates = creator / "Contents/Resources/FileTemplates"
    bundled_templates.mkdir(parents=True, exist_ok=True)
    for suffix in ["rtf", "docx", "xlsx", "pptx"]:
        source = templates / ("blank." + suffix)
        if not source.is_file() or source.stat().st_size == 0:
            raise RuntimeError("기본 문서 파일이 없거나 비어 있습니다: " + str(source))
        shutil.copy2(source, bundled_templates / source.name)
    shutil.copy2(ROOT / "THIRD_PARTY_NOTICES.txt", creator / "Contents/Resources/THIRD_PARTY_NOTICES.txt")
    common = dict(CFBundleInfoDictionaryVersion="6.0", CFBundleVersion=str(build_number), CFBundleShortVersionString=version,
                  CFBundleDevelopmentRegion="ko", CFBundleSupportedPlatforms=["MacOSX"], LSMinimumSystemVersion="14.0")
    host_info = dict(common, CFBundleIdentifier="local.hj.quickright", CFBundleName="RightNook",
                     CFBundleDisplayName="RightNook", CFBundleExecutable="RightNook", CFBundlePackageType="APPL", CFBundleIconFile="RightNook.icns",
                     NSPrincipalClass="NSApplication", NSHighResolutionCapable=True,
                     LSMultipleInstancesProhibited=True, LSUIElement=True,
                     NSDesktopFolderUsageDescription="선택한 폴더를 터미널에서 열거나 선택한 파일을 처리하기 위해 접근합니다.",
                     NSDocumentsFolderUsageDescription="선택한 폴더를 터미널에서 열거나 선택한 파일을 처리하기 위해 접근합니다.",
                     NSDownloadsFolderUsageDescription="선택한 폴더를 터미널에서 열거나 선택한 파일을 처리하기 위해 접근합니다.",
                     CFBundleURLTypes=[dict(CFBundleURLName="local.hj.quickright.actions", CFBundleURLSchemes=["quickright"])])
    extension_info = dict(common, CFBundleIdentifier="local.hj.quickright.finder", CFBundleName="RightNook",
                          CFBundleDisplayName="RightNook", CFBundleExecutable="RightNookFinder", CFBundlePackageType="XPC!",
                          LSUIElement=True,
                          NSExtension=dict(NSExtensionPointIdentifier="com.apple.FinderSync",
                                           NSExtensionPrincipalClass="RightNookFinder", NSExtensionAttributes={}))
    creator_info = dict(common, CFBundleIdentifier="local.hj.quickright.filecreator", CFBundleName="RightNook 파일 만들기",
                        CFBundleDisplayName="RightNook 파일 만들기", CFBundleExecutable="RightNookFileCreator", CFBundlePackageType="APPL", CFBundleIconFile="RightNook.icns",
                        NSPrincipalClass="NSApplication", NSHighResolutionCapable=True, LSUIElement=True,
                        LSMultipleInstancesProhibited=True,
                        CFBundleURLTypes=[dict(CFBundleURLName="local.hj.quickright.filecreator.actions", CFBundleURLSchemes=["quickright-file"])])
    config = ROOT / "Config"
    config.mkdir(exist_ok=True)
    for name, value, installed in [("Host-Info.plist", host_info, app / "Contents/Info.plist"),
                                    ("Finder-Info.plist", extension_info, extension / "Contents/Info.plist"),
                                    ("FileCreator-Info.plist", creator_info, creator / "Contents/Info.plist")]:
        data = plistlib.dumps(value)
        (config / name).write_bytes(data)
        installed.write_bytes(data)
    host_entitlements = {}
    finder_entitlements = {"com.apple.security.app-sandbox": True,
                           "com.apple.security.files.user-selected.read-only": True,
                           "com.apple.security.temporary-exception.files.home-relative-path.read-only":
                           ["/Library/Application Support/QuickRight/Menu/"]}
    creator_entitlements = {"com.apple.security.app-sandbox": True,
                            "com.apple.security.files.user-selected.read-write": True,
                            "com.apple.security.temporary-exception.files.home-relative-path.read-only":
                            ["/Library/Application Support/QuickRight/Menu/"]}
    for name, value in [("Host.entitlements", host_entitlements), ("Finder.entitlements", finder_entitlements),
                        ("FileCreator.entitlements", creator_entitlements)]:
        (config / name).write_bytes(plistlib.dumps(value))
    flags = ["xcrun", "swiftc", "-swift-version", "5", "-target", "arm64-apple-macosx14.0", "-O",
             "-parse-as-library", "-module-cache-path", ROOT / "_build/ModuleCache-RightNook"]
    core = sorted((ROOT / "Sources/Core").glob("*.swift"))
    run(flags + ["-module-name", "RightNook"] + core + sorted((ROOT / "Sources/Host").glob("*.swift")) +
        ["-framework", "AppKit", "-framework", "SwiftUI", "-framework", "FinderSync", "-o", app / "Contents/MacOS/RightNook"])
    run(flags + ["-module-name", "RightNookFinder", "-application-extension", "-emit-executable"] + core +
        sorted((ROOT / "Sources/Finder").glob("*.swift")) + ["-framework", "FinderSync", "-framework", "AppKit",
         "-Xlinker", "-e", "-Xlinker", "_NSExtensionMain", "-o", extension / "Contents/MacOS/RightNookFinder"])
    run(flags + ["-module-name", "RightNookFileCreator"] + core + sorted((ROOT / "Sources/FileCreator").glob("*.swift")) +
        ["-framework", "AppKit", "-o", creator / "Contents/MacOS/RightNookFileCreator"])
    for bundle, entitlement in [(creator, "FileCreator.entitlements"), (extension, "Finder.entitlements"), (app, "Host.entitlements")]:
        run(["/usr/bin/codesign", "--force", "--sign", identity, "--entitlements", config / entitlement, bundle])
    run(["/usr/bin/codesign", "--verify", "--deep", "--strict", app])
    report = {"product": str(app), "architectures": "arm64", "version": version, "build_number": build_number, "signing_identity": identity,
              "host_sandboxed": False, "finder_sandboxed": True, "notarized": False,
              "file_creator_sandboxed": True, "file_creator": str(creator),
              "app_groups": False, "menu_snapshot": "~/Library/Application Support/QuickRight/Menu/menu-v1.json",
              "finder_menu_access": "read-only, dedicated menu directory"}
    report_path.write_text(json.dumps(report, indent=2) + "\n")
    print(app)


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--identity", default=os.environ.get("RIGHTNOOK_SIGN_IDENTITY", "-"))
    build(parser.parse_args().identity)
