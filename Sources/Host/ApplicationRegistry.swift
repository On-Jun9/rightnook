import AppKit

enum ApplicationRegistry {
    static func application(at url: URL) throws -> OpenWithApplication {
        guard let info = info(at: url), let bundleID = info["CFBundleIdentifier"] as? String else {
            throw ApplicationRegistrationError.notApplication
        }
        guard ![RightNook.bundleID, RightNook.extensionID, RightNook.fileCreatorID].contains(bundleID) else {
            throw ApplicationRegistrationError.selfApplication
        }
        let name = (info["CFBundleDisplayName"] as? String) ?? (info["CFBundleName"] as? String) ?? url.deletingPathExtension().lastPathComponent
        let types = (info["CFBundleDocumentTypes"] as? [[String: Any]] ?? []).filter {
            ["Editor", "Viewer", "Shell"].contains($0["CFBundleTypeRole"] as? String ?? "")
        }
        let folderTypes: Set<String> = ["public.folder", "public.directory"]
        let hasFolders = types.contains { !Set($0["LSItemContentTypes"] as? [String] ?? []).isDisjoint(with: folderTypes) }
        let hasFiles = types.contains {
            let identifiers = Set($0["LSItemContentTypes"] as? [String] ?? [])
            return !identifiers.subtracting(folderTypes).isEmpty || !($0["CFBundleTypeExtensions"] as? [String] ?? []).isEmpty
        }
        let target: ApplicationTarget = hasFolders ? (hasFiles ? .filesAndFolders : .folders) : .files
        let app = OpenWithApplication(id: UUID(), name: name, bundleID: bundleID, path: url.path, target: target)
        guard app.isValid else { throw ApplicationRegistrationError.notApplication }
        return app
    }
    static func url(for app: OpenWithApplication) -> URL? {
        let configured = URL(fileURLWithPath: app.path)
        if info(at: configured)?["CFBundleIdentifier"] as? String == app.bundleID { return configured }
        guard let found = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID),
              info(at: found)?["CFBundleIdentifier"] as? String == app.bundleID else { return nil }
        return found
    }
    private static func info(at url: URL) -> [String: Any]? {
        guard url.isFileURL, url.pathExtension.lowercased() == "app",
              let data = try? Data(contentsOf: url.appendingPathComponent("Contents/Info.plist")),
              let info = (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any],
              info["CFBundlePackageType"] as? String == "APPL",
              let identifier = info["CFBundleIdentifier"] as? String, !identifier.isEmpty,
              let executable = info["CFBundleExecutable"] as? String, !executable.isEmpty else { return nil }
        return info
    }
}

enum ApplicationRegistrationError: LocalizedError {
    case notApplication, selfApplication, duplicate, limit, missingApplication, unsupportedTarget
    var errorDescription: String? {
        switch self {
        case .notApplication: return "macOS 앱(.app)을 선택해 주세요."
        case .selfApplication: return "RightNook은 열기 앱으로 등록할 수 없습니다."
        case .duplicate: return "이미 등록한 앱입니다."
        case .limit: return "앱은 최대 100개까지 등록할 수 있습니다."
        case .missingApplication: return "등록한 앱을 찾을 수 없습니다. 앱 설정에서 다시 선택해 주세요."
        case .unsupportedTarget: return "이 앱의 열기 대상 설정과 선택 항목이 맞지 않습니다. 앱 설정에서 파일·폴더 선택을 확인해 주세요."
        }
    }
}
