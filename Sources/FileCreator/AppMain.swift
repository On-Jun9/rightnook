import AppKit
import UniformTypeIdentifiers

@main
enum FileCreatorMain {
    static func main() {
        if CommandLine.arguments.contains("--diagnostics") {
            let snapshot = SharedFiles.loadSnapshot()
            let result: [String: Any] = ["version": RightNook.version, "bundleID": RightNook.fileCreatorID,
                "menuReadable": snapshot != nil,
                "newFileEnabled": snapshot?.visibleEntries.contains(where: { $0.id == .newFile }) ?? false,
                "formats": snapshot?.formats.map(\.rawValue) ?? []]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
                print(String(decoding: data, as: UTF8.self))
            }
            return
        }
        let app = NSApplication.shared
        let delegate = FileCreatorDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class FileCreatorDelegate: NSObject, NSApplicationDelegate, NSOpenSavePanelDelegate {
    private var launched = false
    private var pending: [URL] = []
    private var panel: NSSavePanel?
    private var activeRequest: ActionRequest?
    private var previousApplication: NSRunningApplication?
    private var busy = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenu()
        launched = true
        let waiting = pending
        pending.removeAll()
        waiting.forEach(receive)
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        if !launched { pending.append(contentsOf: urls); return }
        urls.forEach(receive)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { false }

    private func configureMenu() {
        let bar = NSMenu()
        let appRoot = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "파일 생성 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appRoot.submenu = appMenu
        bar.addItem(appRoot)
        let editRoot = NSMenuItem()
        let edit = NSMenu(title: "편집")
        edit.addItem(withTitle: "실행 취소", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "잘라내기", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "복사", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "붙여넣기", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "모두 선택", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editRoot.submenu = edit
        bar.addItem(editRoot)
        NSApp.mainMenu = bar
    }
    private func receive(_ url: URL) {
        guard !busy else {
            panel?.makeKeyAndOrderFront(nil)
            NSSound.beep()
            return
        }
        busy = true
        previousApplication = NSWorkspace.shared.frontmostApplication
        do {
            let request = try ActionRequest.decode(url)
            let format = try request.validatedCreationFormat(in: SharedFiles.loadSnapshot())
            activeRequest = request
            present(request, format: format, directory: request.targets[0], name: "제목 없음.\(format.rawValue)")
        } catch {
            _ = showError(error, allowRetry: false)
            finish(restoreFocus: true)
        }
    }
    private func present(_ request: ActionRequest, format: FileFormat, directory: URL, name: String) {
        let save = NSSavePanel()
        panel = save
        save.delegate = self
        save.title = "새 \(format.documentName)"
        save.message = "파일을 만들 위치와 이름을 확인해 주세요. 기존 파일은 덮어쓰지 않습니다."
        // A Finder path is a location hint, not persistent permission.
        // The Save panel grants access to the user's chosen output file.
        save.directoryURL = directory
        save.nameFieldStringValue = name
        save.allowedContentTypes = [UTType(filenameExtension: format.rawValue) ?? .data]
        save.allowsOtherFileTypes = false
        save.canCreateDirectories = false
        save.prompt = "만들기"
        NSApp.activate(ignoringOtherApps: true)
        save.begin { [weak self] response in
            guard let self else { return }
            guard response == .OK, let output = save.url else {
                self.finish(restoreFocus: true)
                return
            }
            do {
                _ = try request.validatedCreationFormat(in: SharedFiles.loadSnapshot())
                let scoped = output.startAccessingSecurityScopedResource()
                defer { if scoped { output.stopAccessingSecurityScopedResource() } }
                try FileCreation.create(at: output, format: format)
                NSWorkspace.shared.activateFileViewerSelecting([output])
            } catch {
                if self.showError(error, allowRetry: true) {
                    self.present(request, format: format, directory: output.deletingLastPathComponent(), name: output.lastPathComponent)
                    return
                }
            }
            self.finish(restoreFocus: false)
        }
    }
    func panel(_ sender: Any, validate url: URL) throws {
        guard let request = activeRequest else { throw RightNookError.invalidRequest }
        let format = try request.validatedCreationFormat(in: SharedFiles.loadSnapshot())
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do { try FileCreation.validateDestination(at: url, format: format) }
        catch {
            // Validation keeps the Save panel open. The final O_EXCL write
            // still protects against a collision after this check.
            throw NSError(domain: "local.hj.quickright.filecreation", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: FileCreationProblem.classify(error).message])
        }
    }
    private func showError(_ error: Error, allowRetry: Bool) -> Bool {
        let problem = FileCreationProblem.classify(error)
        let canRetry = allowRetry && problem.canChooseAgain
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "파일을 만들지 못했습니다."
        alert.informativeText = problem == .other ? "\(problem.message)\n\(error.localizedDescription)" : problem.message
        alert.addButton(withTitle: canRetry ? "이름·위치 다시 선택" : "확인")
        if canRetry { alert.addButton(withTitle: "취소") }
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertFirstButtonReturn && canRetry
    }
    private func finish(restoreFocus: Bool) {
        panel = nil
        activeRequest = nil
        busy = false
        if restoreFocus, previousApplication?.bundleIdentifier != RightNook.fileCreatorID {
            previousApplication?.activate(options: [])
        }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.busy else { return }
            NSApp.terminate(nil)
        }
    }
}
