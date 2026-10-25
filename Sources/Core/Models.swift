import Foundation

enum RightNook {
    static var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development" }
    // Preserve the local installation's settings, extension identity, and routes.
    static let bundleID = "local.hj.quickright"
    static let extensionID = "local.hj.quickright.finder"
    static let scheme = "quickright"
    static let fileCreatorID = bundleID + ".filecreator"
    static let fileCreatorScheme = "quickright-file"
    static func fileCreatorURL(in app: URL) -> URL {
        app.appendingPathComponent("Contents/Helpers/RightNookFileCreator.app", isDirectory: true)
    }
}

enum MenuFeature: String, Codable, CaseIterable, Identifiable {
    case newFile, copyPath, terminal, vscode, favorites
    var id: String { rawValue }
    var title: String {
        switch self {
        case .newFile: return "새 파일 만들기"
        case .copyPath: return "경로 복사"
        case .terminal: return "터미널에서 열기"
        case .vscode: return "앱으로 열기"
        case .favorites: return "자주 쓰는 폴더"
        }
    }
    var symbol: String {
        switch self {
        case .newFile: return "doc.badge.plus"
        case .copyPath: return "link"
        case .terminal: return "terminal"
        case .vscode: return "arrow.up.forward.app"
        case .favorites: return "folder.badge.plus"
        }
    }
}

enum TerminalApp: String, Codable, CaseIterable, Identifiable {
    case terminal, iterm2
    var id: String { rawValue }
    var name: String { self == .terminal ? "Terminal" : "iTerm2" }
    var bundleID: String { self == .terminal ? "com.apple.Terminal" : "com.googlecode.iterm2" }
    var menuTitle: String { "\(name)에서 열기" }
}

enum FileFormat: String, Codable, CaseIterable, Identifiable {
    case txt, md, rtf, docx, xlsx, pptx
    var id: String { rawValue }
    var title: String {
        switch self {
        case .txt: return "텍스트 (.txt)"
        case .md: return "Markdown (.md)"
        case .rtf: return "서식 있는 텍스트 (.rtf)"
        case .docx: return "Word (.docx)"
        case .xlsx: return "Excel (.xlsx)"
        case .pptx: return "PowerPoint (.pptx)"
        }
    }
    var documentName: String {
        switch self {
        case .txt: return "텍스트 파일"
        case .md: return "Markdown 파일"
        case .rtf: return "서식 있는 텍스트 파일"
        case .docx: return "Word 문서"
        case .xlsx: return "Excel 통합 문서"
        case .pptx: return "PowerPoint 프레젠테이션"
        }
    }
    var action: ActionKind {
        switch self {
        case .txt: return .newText
        case .md: return .newMarkdown
        case .rtf: return .newRTF
        case .docx: return .newWord
        case .xlsx: return .newExcel
        case .pptx: return .newPowerPoint
        }
    }
}

struct MenuEntry: Codable, Equatable, Identifiable {
    let id: MenuFeature
    var enabled: Bool
}

struct FavoriteFolder: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var displayPath: String
    var bookmark: Data
}

enum ApplicationTarget: String, Codable, CaseIterable, Identifiable {
    case files, folders, filesAndFolders
    var id: Self { self }
    var title: String {
        switch self {
        case .files: return "파일"
        case .folders: return "폴더"
        case .filesAndFolders: return "파일·폴더"
        }
    }
    func accepts(isDirectory: Bool) -> Bool {
        self == .filesAndFolders || (isDirectory ? self == .folders : self == .files)
    }
}

struct OpenWithApplication: Codable, Equatable, Identifiable {
    let id: UUID
    var name: String
    var bundleID: String
    var path: String
    var enabled = true
    var target: ApplicationTarget = .files

    // Keep the pre-0.4 VS Code slot and old action requests identifiable.
    static let visualStudioCode = OpenWithApplication(
        id: UUID(uuidString: "C49B6276-1C8D-4F68-90FA-19EDDE83705B")!, name: "VS Code",
        bundleID: "com.microsoft.VSCode", path: "/Applications/Visual Studio Code.app", target: .filesAndFolders)
    var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 128 &&
        !name.contains("\0") && !bundleID.isEmpty && bundleID.count <= 255 && !bundleID.contains("\0") &&
        path.hasPrefix("/") && !path.contains("\0") && URL(fileURLWithPath: path).pathExtension.lowercased() == "app"
    }
}

struct Settings: Codable, Equatable {
    var schemaVersion = 1
    var revision: UUID = UUID()
    var entries = MenuFeature.allCases.map { MenuEntry(id: $0, enabled: false) }
    var formats: [FileFormat] = [.txt, .md]
    var formatOrder: [FileFormat] = FileFormat.allCases
    var favorites: [FavoriteFolder] = []
    var groupMenus = true
    var terminalApp: TerminalApp = .terminal
    var applications: [OpenWithApplication] = [.visualStudioCode]
    enum CodingKeys: String, CodingKey {
        case schemaVersion, revision, entries, formats, formatOrder, favorites, groupMenus, terminalApp, applications
    }

    func isEnabled(_ feature: MenuFeature) -> Bool {
        entries.contains { $0.id == feature && $0.enabled }
    }
    var enabledFormatsInOrder: [FileFormat] {
        formatOrder.filter { formats.contains($0) }
    }
    mutating func setFormat(_ format: FileFormat, enabled: Bool) {
        if enabled {
            if !formats.contains(format) { formats.append(format) }
        } else {
            formats.removeAll { $0 == format }
        }
    }
    mutating func moveFormat(_ format: FileFormat, by delta: Int) {
        guard let index = formatOrder.firstIndex(of: format), formatOrder.indices.contains(index + delta) else { return }
        formatOrder.swapAt(index, index + delta)
    }
    func validated() throws -> Settings {
        guard schemaVersion == 1,
              entries.count == MenuFeature.allCases.count,
              Set(entries.map(\.id)) == Set(MenuFeature.allCases),
              Set(formats).count == formats.count,
              formatOrder.count == FileFormat.allCases.count,
              Set(formatOrder) == Set(FileFormat.allCases),
              Set(favorites.map(\.id)).count == favorites.count,
              favorites.count <= 100,
              applications.count <= 100, applications.allSatisfy(\.isValid),
              Set(applications.map(\.id)).count == applications.count,
              Set(applications.map(\.bundleID)).count == applications.count,
              favorites.allSatisfy({ !$0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !$0.bookmark.isEmpty })
        else { throw RightNookError.invalidSettings }
        return self
    }
    var snapshot: MenuSnapshot {
        MenuSnapshot(schemaVersion: schemaVersion, revision: revision, entries: entries,
                     formats: enabledFormatsInOrder, favorites: favorites.map { .init(id: $0.id, name: $0.name) },
                     groupMenus: groupMenus, terminalApp: terminalApp, applications: applications)
    }
}

extension Settings {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        revision = try values.decode(UUID.self, forKey: .revision)
        entries = try values.decode([MenuEntry].self, forKey: .entries)
        formats = try values.decode([FileFormat].self, forKey: .formats)
        let order = try values.decodeIfPresent([FileFormat].self, forKey: .formatOrder) ?? formats
        formatOrder = order + FileFormat.allCases.filter { !order.contains($0) }
        favorites = try values.decode([FavoriteFolder].self, forKey: .favorites)
        groupMenus = try values.decode(Bool.self, forKey: .groupMenus)
        terminalApp = try values.decodeIfPresent(TerminalApp.self, forKey: .terminalApp) ?? .terminal
        applications = try values.decodeIfPresent([OpenWithApplication].self, forKey: .applications) ?? [.visualStudioCode]
    }
}

struct MenuSnapshot: Codable, Equatable {
    struct Folder: Codable, Equatable, Identifiable { let id: UUID; let name: String }
    let schemaVersion: Int
    let revision: UUID
    let entries: [MenuEntry]
    let formats: [FileFormat]
    let favorites: [Folder]
    let groupMenus: Bool
    var terminalApp: TerminalApp = .terminal
    var applications: [OpenWithApplication] = [.visualStudioCode]
    enum CodingKeys: String, CodingKey {
        case schemaVersion, revision, entries, formats, favorites, groupMenus, terminalApp, applications
    }

    var visibleEntries: [MenuEntry] {
        guard schemaVersion == 1, Set(entries.map(\.id)) == Set(MenuFeature.allCases),
              entries.count == MenuFeature.allCases.count else { return [] }
        return entries.filter { entry in
            entry.enabled && (entry.id != .newFile || !formats.isEmpty) &&
            (entry.id != .favorites || !favorites.isEmpty) &&
            (entry.id != .vscode || !enabledApplications.isEmpty)
        }
    }
    var enabledApplications: [OpenWithApplication] {
        guard applications.count <= 100, applications.allSatisfy(\.isValid),
              Set(applications.map(\.id)).count == applications.count,
              Set(applications.map(\.bundleID)).count == applications.count else { return [] }
        return applications.filter(\.enabled)
    }
}

extension MenuSnapshot {
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = try values.decode(Int.self, forKey: .schemaVersion)
        revision = try values.decode(UUID.self, forKey: .revision)
        entries = try values.decode([MenuEntry].self, forKey: .entries)
        formats = try values.decode([FileFormat].self, forKey: .formats)
        favorites = try values.decode([Folder].self, forKey: .favorites)
        groupMenus = try values.decode(Bool.self, forKey: .groupMenus)
        terminalApp = try values.decodeIfPresent(TerminalApp.self, forKey: .terminalApp) ?? .terminal
        applications = try values.decodeIfPresent([OpenWithApplication].self, forKey: .applications) ?? [.visualStudioCode]
    }
}

enum ActionKind: String, Codable {
    case newText, newMarkdown, newRTF, newWord, newExcel, newPowerPoint
    case terminal, vscode, openApplication, favorite, settings
    var creationFormat: FileFormat? {
        switch self {
        case .newText: return .txt
        case .newMarkdown: return .md
        case .newRTF: return .rtf
        case .newWord: return .docx
        case .newExcel: return .xlsx
        case .newPowerPoint: return .pptx
        default: return nil
        }
    }
    var feature: MenuFeature? {
        switch self {
        case .newText, .newMarkdown, .newRTF, .newWord, .newExcel, .newPowerPoint: return .newFile
        case .terminal: return .terminal
        case .vscode, .openApplication: return .vscode
        case .favorite: return .favorites
        case .settings: return nil
        }
    }
}

struct ActionRequest: Codable, Equatable {
    var version = 1
    let action: ActionKind
    var targets: [URL] = []
    var favoriteID: UUID? = nil
    var terminalApp: TerminalApp? = nil
    var applicationID: UUID? = nil

    func validated() throws -> ActionRequest {
        guard version == 1, targets.count <= 100, action == .terminal || terminalApp == nil,
              action == .openApplication || applicationID == nil,
              targets.allSatisfy({ $0.isFileURL && ($0.host == nil || $0.host == "" || $0.host == "localhost") && $0.path.hasPrefix("/") && !$0.path.contains("\0") })
        else { throw RightNookError.invalidRequest }
        switch action {
        case .newText, .newMarkdown, .newRTF, .newWord, .newExcel, .newPowerPoint, .terminal:
            guard targets.count == 1, favoriteID == nil else { throw RightNookError.invalidRequest }
        case .vscode:
            guard !targets.isEmpty, favoriteID == nil else { throw RightNookError.invalidRequest }
        case .openApplication:
            guard !targets.isEmpty, applicationID != nil, favoriteID == nil else { throw RightNookError.invalidRequest }
        case .favorite:
            guard targets.isEmpty, favoriteID != nil else { throw RightNookError.invalidRequest }
        case .settings:
            guard targets.isEmpty, favoriteID == nil else { throw RightNookError.invalidRequest }
        }
        return self
    }
    func encodedURL() throws -> URL {
        _ = try validated()
        let data = try JSONEncoder().encode(self)
        var components = URLComponents()
        components.scheme = action.creationFormat == nil ? RightNook.scheme : RightNook.fileCreatorScheme
        components.host = "action"
        components.queryItems = [URLQueryItem(name: "request", value: String(decoding: data, as: UTF8.self))]
        guard let url = components.url, url.absoluteString.utf8.count <= 65_536 else { throw RightNookError.invalidRequest }
        return url
    }
    static func decode(_ url: URL) throws -> ActionRequest {
        guard url.absoluteString.utf8.count <= 65_536,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              [RightNook.scheme, RightNook.fileCreatorScheme].contains(parts.scheme ?? ""), parts.host == "action",
              parts.user == nil, parts.password == nil, parts.port == nil,
              parts.path.isEmpty, parts.fragment == nil,
              let items = parts.queryItems, items.count == 1,
              items[0].name == "request", let string = items[0].value,
              let data = string.data(using: .utf8) else { throw RightNookError.invalidRequest }
        let request = try JSONDecoder().decode(ActionRequest.self, from: data).validated()
        guard parts.scheme != RightNook.fileCreatorScheme || request.action.creationFormat != nil else {
            throw RightNookError.invalidRequest
        }
        return request
    }
    func validatedCreationFormat(in snapshot: MenuSnapshot?) throws -> FileFormat {
        _ = try validated()
        guard let format = action.creationFormat else { throw RightNookError.invalidRequest }
        guard let snapshot, snapshot.visibleEntries.contains(where: { $0.id == .newFile }),
              snapshot.formats.contains(format) else { throw RightNookError.disabled }
        return format
    }
    func validatedApplication(in settings: Settings) throws -> OpenWithApplication {
        _ = try validated()
        _ = try settings.validated()
        guard settings.isEnabled(.vscode), action == .openApplication || action == .vscode,
              let app = settings.applications.first(where: {
                  action == .vscode ? $0.bundleID == OpenWithApplication.visualStudioCode.bundleID : $0.id == applicationID
              }), app.enabled else { throw RightNookError.disabled }
        return app
    }
}

enum RightNookError: LocalizedError {
    case invalidRequest, invalidSettings, noTarget, invalidName, invalidExtension
    case disabled, missingFolder, sharedContainer, bookmark, fileExists, templateUnavailable
    var errorDescription: String? {
        switch self {
        case .invalidRequest: return "요청 형식이나 파일 대상이 올바르지 않습니다."
        case .invalidSettings: return "설정을 읽을 수 없습니다. RightNook에서 다시 적용해 주세요."
        case .noTarget: return "작업할 파일이나 폴더를 확인할 수 없습니다."
        case .invalidName: return "파일 이름은 비어 있거나 /, NUL, . 또는 ..일 수 없습니다."
        case .invalidExtension: return "선택한 파일 형식에 맞는 확장자를 사용해 주세요."
        case .disabled: return "현재 설정에서 꺼져 있거나 삭제된 항목입니다."
        case .missingFolder: return "대상 폴더가 없거나 접근할 수 없습니다."
        case .sharedContainer: return "메뉴 설정을 저장할 사용자 폴더를 확인할 수 없습니다. 설치된 RightNook 앱을 다시 열어 주세요."
        case .bookmark: return "등록한 폴더에 다시 접근할 수 없습니다. 설정에서 폴더를 다시 연결해 주세요."
        case .fileExists: return "같은 이름의 파일이나 폴더가 있습니다. 기존 항목은 보존됩니다. 다른 이름을 입력해 주세요."
        case .templateUnavailable: return "기본 문서 파일을 읽을 수 없습니다. RightNook을 다시 빌드·설치한 뒤 시도해 주세요."
        }
    }
}
