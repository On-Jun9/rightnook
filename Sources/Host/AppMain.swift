import AppKit
import SwiftUI

@main
enum AppMain {
    static func main() {
        if CommandLine.arguments.contains("--diagnostics") {
            let snapshot = SharedFiles.loadSnapshot()
            let result: [String: Any] = ["version": RightNook.version, "architecture": "arm64",
                "menuDirectory": (try? SharedFiles.directory().path) ?? "unavailable",
                "terminalApp": snapshot?.terminalApp.rawValue ?? "terminal",
                "visibleFeatures": snapshot?.visibleEntries.map { $0.id.rawValue } ?? [],
                "configurationRevision": snapshot?.revision.uuidString ?? "none"]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) { print(String(decoding: data, as: UTF8.self)) }
            return
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    let store = SettingsStore()
    private var window: NSWindow?
    private var launched = false
    private var receivedURL = false
    private var pending: [URL] = []
    private var busy = false
    private let launchedForAction = CommandLine.arguments.contains("--finder-action")

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMenu()
        launched = true
        let waiting = pending
        pending.removeAll()
        for url in waiting { receive(url) }
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.launchedForAction, !self.receivedURL else { return }
            self.showSettings()
        }
    }
    func application(_ application: NSApplication, open urls: [URL]) {
        receivedURL = true
        if !launched { pending.append(contentsOf: urls); return }
        urls.forEach(receive)
    }
    func applicationDidBecomeActive(_ notification: Notification) { store.refreshExtension() }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !busy && !flag { showSettings() }
        return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { !busy }

    private func configureMenu() {
        let bar = NSMenu()
        let item = NSMenuItem()
        let app = NSMenu()
        app.addItem(withTitle: "RightNook 설정…", action: #selector(settingsMenu), keyEquivalent: ",").target = self
        app.addItem(.separator())
        app.addItem(withTitle: "RightNook 종료", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        item.submenu = app
        bar.addItem(item)
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
    @objc private func settingsMenu(_ sender: Any?) { showSettings() }
    func showSettings() {
        NSApp.setActivationPolicy(.regular)
        if window == nil {
            let controller = NSHostingController(rootView: SettingsView(store: store))
            let created = NSWindow(contentViewController: controller)
            created.title = "RightNook 설정"
            created.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            created.setContentSize(NSSize(width: 820, height: 720))
            created.contentMinSize = NSSize(width: 760, height: 650)
            created.isReleasedWhenClosed = false
            created.delegate = self
            if !created.setFrameUsingName("QuickRightSettings") { created.center() }
            created.setFrameAutosaveName("QuickRightSettings")
            window = created
        }
        store.refreshExtension()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard store.hasChanges else { return true }
        let alert = NSAlert()
        alert.messageText = "변경한 설정을 적용할까요?"
        alert.informativeText = "적용하지 않은 변경 사항은 Finder 메뉴에 반영되지 않습니다."
        alert.addButton(withTitle: "적용")
        alert.addButton(withTitle: "적용하지 않음")
        alert.addButton(withTitle: "취소")
        let response = alert.runModal()
        if response == .alertFirstButtonReturn { store.apply(); return store.errorMessage == nil }
        return response == .alertSecondButtonReturn
    }
    func windowWillClose(_ notification: Notification) { window = nil }

    private func receive(_ url: URL) {
        var ownsAction = false
        do {
            let request = try ActionRequest.decode(url)
            if request.action == .settings { showSettings(); return }
            guard !busy else {
                showError("진행 중인 작업을 먼저 마친 뒤 다시 선택해 주세요.", error: nil)
                return
            }
            if let feature = request.action.feature, !store.active.isEnabled(feature) { throw RightNookError.disabled }
            busy = true
            ownsAction = true
            switch request.action {
            case .newText, .newMarkdown, .newRTF, .newWord, .newExcel, .newPowerPoint:
                // Forward legacy quickright:// creation URLs without sharing
                // the settings application's window or activation lifecycle.
                _ = try request.validatedCreationFormat(in: store.active.snapshot)
                let config = NSWorkspace.OpenConfiguration()
                config.activates = false
                NSWorkspace.shared.open([try request.encodedURL()],
                    withApplicationAt: RightNook.fileCreatorURL(in: Bundle.main.bundleURL), configuration: config) { [weak self] _, error in
                    DispatchQueue.main.async {
                        if let error { self?.showError("파일 생성 창을 열지 못했습니다.", error: error) }
                        self?.finish()
                    }
                }
            case .terminal:
                try checkDirectory(request.targets[0])
                let terminal = request.terminalApp ?? store.active.terminalApp
                open(request.targets, bundleID: terminal.bundleID, name: terminal.name)
            case .vscode, .openApplication:
                let app = try request.validatedApplication(in: store.active)
                for target in request.targets {
                    let values = try target.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
                    guard let directory = values.isDirectory else { throw RightNookError.noTarget }
                    guard app.target.accepts(isDirectory: directory && values.isPackage != true) else { throw ApplicationRegistrationError.unsupportedTarget }
                }
                guard let appURL = ApplicationRegistry.url(for: app) else { throw ApplicationRegistrationError.missingApplication }
                open(request.targets, applicationURL: appURL, name: app.name)
            case .favorite:
                let folder = try store.resolveFavorite(request.favoriteID!)
                let scoped = folder.startAccessingSecurityScopedResource()
                defer { if scoped { folder.stopAccessingSecurityScopedResource() } }
                try checkDirectory(folder)
                guard NSWorkspace.shared.open(folder) else { throw RightNookError.missingFolder }
                finish()
            case .settings: break
            }
        } catch {
            showError("작업을 완료하지 못했습니다.", error: error)
            if ownsAction || !busy { finish() }
        }
    }
    private func checkDirectory(_ url: URL) throws {
        var directory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &directory), directory.boolValue else { throw RightNookError.missingFolder }
    }
    private func open(_ urls: [URL], bundleID: String, name: String) {
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            showError("\(name)이 설치되어 있지 않습니다.", error: nil)
            finish()
            return
        }
        open(urls, applicationURL: appURL, name: name)
    }
    private func open(_ urls: [URL], applicationURL appURL: URL, name: String) {
        let config = NSWorkspace.OpenConfiguration()
        config.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: appURL, configuration: config) { [weak self] _, error in
            DispatchQueue.main.async {
                if let error { self?.showError("\(name)에서 열지 못했습니다.", error: error) }
                self?.finish()
            }
        }
    }
    private func showError(_ message: String, error: Error?) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = message
        alert.informativeText = error?.localizedDescription ?? "RightNook 설정에서 해당 기능을 끄거나 앱을 설치한 뒤 다시 시도해 주세요."
        alert.addButton(withTitle: "확인")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }
    private func finish() {
        busy = false
        if window == nil {
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.busy, self.window == nil else { return }
                NSApp.terminate(nil)
            }
        }
    }
}
