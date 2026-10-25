import Foundation
import Darwin

struct SelectedItem: Equatable {
    let url: URL
    let isDirectory: Bool?
    var isPackage = false
}

enum MenuLocation { case items, container, toolbar, sidebar }

struct ActionContext: Equatable {
    let selected: [SelectedItem]
    let currentFolder: URL?

    init(location: MenuLocation, target: SelectedItem?, selected: [SelectedItem]) {
        switch location {
        case .container:
            self.selected = []
            currentFolder = target.flatMap { $0.isDirectory == true ? $0.url : nil }
        case .items:
            self.selected = selected
            currentFolder = nil
        case .toolbar:
            self.selected = selected
            currentFolder = target.flatMap { $0.isDirectory == true ? $0.url : nil }
        case .sidebar:
            self.selected = []
            currentFolder = nil
        }
    }
    var pathsToCopy: [String] {
        if !selected.isEmpty { return selected.map { $0.url.path } }
        return currentFolder.map { [$0.path] } ?? []
    }
    var creationFolder: URL? {
        guard selected.count <= 1 else { return nil }
        if let item = selected.first {
            guard let directory = item.isDirectory else { return nil }
            return directory ? item.url : item.url.deletingLastPathComponent()
        }
        return currentFolder
    }
    var terminalFolder: URL? { creationFolder }
    var editorTargets: [URL] {
        if !selected.isEmpty { return selected.map(\.url) }
        return currentFolder.map { [$0] } ?? []
    }
    func applicationTargets(for target: ApplicationTarget) -> [URL] {
        let items = selected.isEmpty ? currentFolder.map { [SelectedItem(url: $0, isDirectory: true)] } ?? [] : selected
        guard !items.isEmpty, items.allSatisfy({ item in
            item.isDirectory.map { target.accepts(isDirectory: $0 && !item.isPackage) } == true
        }) else { return [] }
        return items.map(\.url)
    }
}

enum FileCreation {
    static func validateDestination(at url: URL, format: FileFormat) throws {
        let name = url.lastPathComponent
        guard url.isFileURL, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              name != ".", name != "..", !name.contains("/"), !name.contains("\0") else {
            throw RightNookError.invalidName
        }
        guard url.pathExtension.lowercased() == format.rawValue else { throw RightNookError.invalidExtension }
        var entry = stat()
        if lstat(url.path, &entry) == 0 { throw RightNookError.fileExists }
        let failure = errno
        guard failure == ENOENT else { throw NSError(domain: NSPOSIXErrorDomain, code: Int(failure)) }
        let parent = try url.deletingLastPathComponent().resourceValues(forKeys: [.isDirectoryKey])
        guard parent.isDirectory == true else {
            throw RightNookError.missingFolder
        }
    }
    static func create(at url: URL, format: FileFormat) throws {
        try validateDestination(at: url, format: format)
        // O_EXCL semantics: the final file operation, not a preceding existence
        // check, prevents clobbering a file created by another process.
        try FileTemplates.data(for: format).write(to: url, options: .withoutOverwriting)
        guard FileManager.default.fileExists(atPath: url.path) else { throw RightNookError.noTarget }
    }
}

enum FileCreationProblem: Equatable {
    case nameConflict, permissionDenied, readOnlyLocation, missingLocation, notEnoughSpace
    case invalidName, invalidFormat, disabled, invalidRequest, templateUnavailable, other

    static func classify(_ error: Error) -> FileCreationProblem {
        if let error = error as? RightNookError {
            switch error {
            case .fileExists: return .nameConflict
            case .missingFolder, .noTarget: return .missingLocation
            case .invalidName: return .invalidName
            case .invalidExtension: return .invalidFormat
            case .disabled, .invalidSettings: return .disabled
            case .invalidRequest: return .invalidRequest
            case .templateUnavailable: return .templateUnavailable
            default: break
            }
        }
        var current = error as NSError
        for _ in 0..<8 {
            if current.domain == NSCocoaErrorDomain {
                switch current.code {
                case NSFileWriteFileExistsError: return .nameConflict
                case NSFileWriteNoPermissionError, NSFileReadNoPermissionError: return .permissionDenied
                case NSFileWriteVolumeReadOnlyError: return .readOnlyLocation
                case NSFileNoSuchFileError, NSFileReadNoSuchFileError: return .missingLocation
                case NSFileWriteOutOfSpaceError: return .notEnoughSpace
                case NSFileWriteInvalidFileNameError: return .invalidName
                default: break
                }
            } else if current.domain == NSPOSIXErrorDomain {
                switch Int32(current.code) {
                case EEXIST: return .nameConflict
                case EACCES, EPERM: return .permissionDenied
                case EROFS: return .readOnlyLocation
                case ENOENT, ENOTDIR: return .missingLocation
                case ENOSPC, EDQUOT: return .notEnoughSpace
                case ENAMETOOLONG: return .invalidName
                default: break
                }
            }
            guard let underlying = current.userInfo[NSUnderlyingErrorKey] as? NSError else { break }
            current = underlying
        }
        return .other
    }
    var canChooseAgain: Bool { self != .disabled && self != .invalidRequest && self != .templateUnavailable }
    var message: String {
        switch self {
        case .nameConflict: return "같은 이름의 파일이나 폴더가 있습니다. 기존 항목은 보존됩니다. 다른 이름을 입력해 주세요."
        case .permissionDenied: return "선택한 위치에 쓸 권한이 없습니다. 폴더 권한을 확인하거나 저장창에서 다른 위치를 직접 선택해 주세요."
        case .readOnlyLocation: return "선택한 위치는 읽기 전용입니다. 쓸 수 있는 위치를 저장창에서 직접 선택해 주세요."
        case .missingLocation: return "선택한 폴더가 삭제되었거나 연결이 끊겼습니다. 저장 위치를 다시 선택해 주세요."
        case .notEnoughSpace: return "저장 공간이 부족합니다. 공간을 확보하거나 다른 위치를 선택해 주세요."
        case .invalidName: return "사용할 수 없는 파일 이름입니다. 이름을 바꾸거나 길이를 줄여 주세요."
        case .invalidFormat: return "선택한 파일 형식에 맞는 확장자를 사용해 주세요."
        case .disabled: return "새 파일 기능이나 해당 형식이 꺼졌거나 설정을 읽을 수 없습니다. RightNook 설정에서 확인하고 적용한 뒤 다시 시도해 주세요."
        case .invalidRequest: return "파일 생성 요청이 올바르지 않습니다. Finder 메뉴를 닫았다가 다시 선택해 주세요."
        case .templateUnavailable: return RightNookError.templateUnavailable.localizedDescription
        case .other: return "파일을 만들지 못했습니다. 이름과 위치를 확인하고 다시 선택해 주세요."
        }
    }
}

enum SharedFiles {
    // The local build has no provisioned App Group. Use a dedicated menu-only
    // directory; the Finder and file creator sandboxes can only read this path.
    // Keep the existing store when updating from the former QuickRight name.
    static let menuRelativeDirectory = "Library/Application Support/QuickRight/Menu"
    static func directory() throws -> URL {
        // Foundation's home URL is redirected into the extension's sandbox.
        // Resolve the real account home consistently in the host and extension.
        guard let account = getpwuid(getuid()), let path = account.pointee.pw_dir else {
            throw RightNookError.sharedContainer
        }
        return directory(in: URL(fileURLWithPath: String(cString: path), isDirectory: true))
    }
    static func directory(in home: URL) -> URL {
        home.appendingPathComponent(menuRelativeDirectory, isDirectory: true)
    }
    static func snapshotURL() throws -> URL { try directory().appendingPathComponent("menu-v1.json") }
    static func write(_ snapshot: MenuSnapshot, to url: URL) throws {
        let manager = FileManager.default
        try manager.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(snapshot).write(to: url, options: .atomic)
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func loadSnapshot() -> MenuSnapshot? {
        guard let url = try? snapshotURL() else { return nil }
        return loadSnapshot(from: url)
    }
    static func loadSnapshot(from url: URL) -> MenuSnapshot? {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber, size.intValue <= 262_144,
              let data = try? Data(contentsOf: url), data.count <= 262_144 else { return nil }
        return try? JSONDecoder().decode(MenuSnapshot.self, from: data)
    }
}
