import AppKit
import Combine
import FinderSync
import UniformTypeIdentifiers

final class SettingsStore: ObservableObject {
    @Published var draft = Settings()
    @Published private(set) var active = Settings()
    @Published var status = "사용할 기능을 선택하고 적용해 주세요."
    @Published var errorMessage: String?
    @Published var extensionEnabled = false
    private let fileURL: URL

    init() {
        fileURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("QuickRight", isDirectory: true).appendingPathComponent("settings-v1.json")
        draft = active
        do {
            if FileManager.default.fileExists(atPath: fileURL.path) {
                let stored = try JSONDecoder().decode(Settings.self, from: Data(contentsOf: fileURL)).validated()
                active = stored
                draft = stored
                try publish(stored)
                status = "저장한 설정을 불러왔습니다."
            } else {
                try publish(active)
            }
        } catch {
            // Do not leave an older shared menu enabled when the private
            // settings can no longer be read. Preserve the private file.
            active = Settings()
            draft = active
            try? publish(active)
            errorMessage = "설정을 불러오지 못했습니다. 원본은 유지됩니다.\n\(error.localizedDescription)"
        }
        refreshExtension()
    }
    var hasChanges: Bool { draft != active }
    func discardDraft() {
        draft = active
        errorMessage = nil
        status = "저장한 설정으로 되돌렸습니다."
    }

    func refreshExtension() { extensionEnabled = FIFinderSyncController.isExtensionEnabled }
    func apply() {
        do {
            var next = try draft.validated()
            next.revision = UUID()
            try savePrivate(next)
            active = next
            draft = next
            do { try publish(next) }
            catch {
                errorMessage = "본체 설정은 저장했지만 Finder에 반영하지 못했습니다. 다시 적용해 주세요.\n\(error.localizedDescription)"
                return
            }
            status = next.snapshot.visibleEntries.isEmpty ? "모든 메뉴가 꺼져 있습니다. Finder에 항목을 표시하지 않습니다." : "적용했습니다. Finder 우클릭 메뉴를 다시 열어 주세요."
            errorMessage = nil
            refreshExtension()
        } catch { errorMessage = error.localizedDescription }
    }
    private func savePrivate(_ settings: Settings) throws {
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(settings).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
    private func publish(_ settings: Settings) throws {
        try SharedFiles.write(settings.snapshot, to: SharedFiles.snapshotURL())
    }
    func recommendedSelection() {
        for index in draft.entries.indices { draft.entries[index].enabled = draft.entries[index].id != .favorites }
        draft.formats = [.txt, .md]
    }
    func moveFeature(_ id: MenuFeature, by delta: Int) {
        guard let index = draft.entries.firstIndex(where: { $0.id == id }), draft.entries.indices.contains(index + delta) else { return }
        draft.entries.swapAt(index, index + delta)
    }
    func setFormat(_ format: FileFormat, enabled: Bool) {
        draft.setFormat(format, enabled: enabled)
    }
    func addApplications(replacing id: UUID? = nil) {
        let panel = NSOpenPanel()
        panel.title = id == nil ? "앱 추가" : "앱 다시 선택"
        panel.prompt = id == nil ? "추가" : "선택"
        panel.allowedContentTypes = [.applicationBundle]
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.treatsFilePackagesAsDirectories = false
        panel.allowsMultipleSelection = id == nil
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        guard panel.runModal() == .OK else { return }
        do {
            let picked = try panel.urls.map { try ApplicationRegistry.application(at: $0) }
            var next = draft.applications
            if let id, let index = next.firstIndex(where: { $0.id == id }), let app = picked.first {
                guard !next.contains(where: { $0.id != id && $0.bundleID == app.bundleID }) else { throw ApplicationRegistrationError.duplicate }
                next[index].bundleID = app.bundleID
                next[index].path = app.path
            } else {
                for app in picked where !next.contains(where: { $0.bundleID == app.bundleID }) { next.append(app) }
                guard next != draft.applications else { throw ApplicationRegistrationError.duplicate }
            }
            guard next.count <= 100 else { throw ApplicationRegistrationError.limit }
            draft.applications = next
            errorMessage = nil
        } catch { errorMessage = error.localizedDescription }
    }
    func moveApplication(_ id: UUID, by delta: Int) {
        guard let index = draft.applications.firstIndex(where: { $0.id == id }), draft.applications.indices.contains(index + delta) else { return }
        draft.applications.swapAt(index, index + delta)
    }
    func addFolder(reconnecting id: UUID? = nil) {
        let panel = NSOpenPanel()
        panel.title = id == nil ? "자주 쓰는 폴더 등록" : "폴더 다시 연결"
        panel.prompt = "이 폴더 등록"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            if let id, let index = draft.favorites.firstIndex(where: { $0.id == id }) {
                draft.favorites[index].displayPath = url.path
                draft.favorites[index].bookmark = data
            } else {
                guard draft.favorites.count < 100 else { throw RightNookError.invalidSettings }
                draft.favorites.append(.init(id: UUID(), name: url.lastPathComponent.isEmpty ? url.path : url.lastPathComponent,
                                             displayPath: url.path, bookmark: data))
            }
            status = "폴더를 추가했습니다. 적용을 누르면 Finder에 반영됩니다."
        } catch { errorMessage = "폴더를 등록하지 못했습니다.\n\(error.localizedDescription)" }
    }
    func moveFolder(_ id: UUID, by delta: Int) {
        guard let index = draft.favorites.firstIndex(where: { $0.id == id }), draft.favorites.indices.contains(index + delta) else { return }
        draft.favorites.swapAt(index, index + delta)
    }
    func resolveFavorite(_ id: UUID) throws -> URL {
        guard let index = active.favorites.firstIndex(where: { $0.id == id }) else { throw RightNookError.disabled }
        var stale = false
        let url = try URL(resolvingBookmarkData: active.favorites[index].bookmark, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale)
        if stale {
            let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
            active.favorites[index].bookmark = data
            if let draftIndex = draft.favorites.firstIndex(where: { $0.id == id }) { draft.favorites[draftIndex].bookmark = data }
            try savePrivate(active)
        }
        return url
    }
}
