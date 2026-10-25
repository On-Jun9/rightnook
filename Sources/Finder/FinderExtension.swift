import AppKit
import FinderSync
import os
import Darwin

private enum MenuCommand {
    case copyPaths([String])
    case request(ActionRequest)
}
@objc(RightNookFinder)
final class RightNookFinder: FIFinderSync {
    private let logger = Logger(subsystem: RightNook.extensionID, category: "Finder")
    private var nextTag = 1
    private var commands: [Int: MenuCommand] = [:]
    private var generations: [[Int]] = []
    override init() {
        super.init()
        var roots: Set<URL> = [URL(fileURLWithPath: "/", isDirectory: true), URL(fileURLWithPath: "/Volumes", isDirectory: true)]
        if let account = getpwuid(getuid()), let directory = account.pointee.pw_dir {
            roots.insert(URL(fileURLWithPath: String(cString: directory), isDirectory: true))
        }
        FIFinderSyncController.default().directoryURLs = roots
        logger.notice("Finder extension loaded")
    }
    override func menu(for menuKind: FIMenuKind) -> NSMenu? {
        guard menuKind != .contextualMenuForSidebar else { return nil }
        guard let snapshot = SharedFiles.loadSnapshot() else {
            logger.error("Menu snapshot unavailable")
            return nil
        }
        logger.info("Menu requested: kind=\(menuKind.rawValue), features=\(snapshot.visibleEntries.count)")
        guard !snapshot.visibleEntries.isEmpty else { return nil }
        // Finder serializes the menu across processes. Custom representedObject
        // instances do not survive that boundary; public integer tags do.
        // Tags identify captured commands, never mutable settings-array indices.
        if generations.count >= 16 {
            for tag in generations.removeFirst() { commands.removeValue(forKey: tag) }
        }
        generations.append([])
        let controller = FIFinderSyncController.default()
        let location: MenuLocation
        switch menuKind {
        case .contextualMenuForItems: location = .items
        case .contextualMenuForContainer: location = .container
        case .toolbarItemMenu: location = .toolbar
        default: return nil
        }
        let selection = (controller.selectedItemURLs() ?? []).compactMap(classify)
        let context = ActionContext(location: location, target: controller.targetedURL().flatMap(classify), selected: selection)
        let content = NSMenu(title: "RightNook")
        content.autoenablesItems = false
        for entry in snapshot.visibleEntries {
            switch entry.id {
            case .newFile:
                let root = NSMenuItem(title: entry.id.title, action: nil, keyEquivalent: "")
                let submenu = NSMenu()
                submenu.autoenablesItems = false
                for format in snapshot.formats {
                    let request = context.creationFolder.map { ActionRequest(action: format.action, targets: [$0]) }
                    submenu.addItem(item(format.title, command: request.map { .request($0) }))
                }
                root.submenu = submenu
                root.image = NSImage(systemSymbolName: entry.id.symbol, accessibilityDescription: nil)
                content.addItem(root)
            case .copyPath:
                let paths = context.pathsToCopy
                content.addItem(item(entry.id.title, symbol: entry.id.symbol, command: paths.isEmpty ? nil : .copyPaths(paths)))
            case .terminal:
                let terminal = snapshot.terminalApp
                let request = context.terminalFolder.map { ActionRequest(action: .terminal, targets: [$0], terminalApp: terminal) }
                let installed = NSWorkspace.shared.urlForApplication(withBundleIdentifier: terminal.bundleID) != nil
                let entry = item(terminal.menuTitle, symbol: entry.id.symbol, command: installed ? request.map { .request($0) } : nil)
                if !installed { entry.toolTip = "\(terminal.name)을 설치하거나 설정에서 다른 터미널을 선택해 주세요." }
                content.addItem(entry)
            case .vscode:
                let root = NSMenuItem(title: entry.id.title, action: nil, keyEquivalent: "")
                root.image = NSImage(systemSymbolName: entry.id.symbol, accessibilityDescription: nil)
                let submenu = NSMenu()
                submenu.autoenablesItems = false
                for app in snapshot.enabledApplications {
                    let targets = context.applicationTargets(for: app.target)
                    let request = targets.isEmpty ? nil : ActionRequest(action: .openApplication, targets: targets, applicationID: app.id)
                    let child = item(app.name, command: request.map { .request($0) })
                    if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
                        let image = NSWorkspace.shared.icon(forFile: appURL.path)
                        image.size = NSSize(width: 16, height: 16)
                        child.image = image
                    }
                    if targets.isEmpty { child.toolTip = "열기 대상: \(app.target.title)" }
                    submenu.addItem(child)
                }
                root.submenu = submenu
                content.addItem(root)
            case .favorites:
                let root = NSMenuItem(title: entry.id.title, action: nil, keyEquivalent: "")
                root.image = NSImage(systemSymbolName: entry.id.symbol, accessibilityDescription: nil)
                let submenu = NSMenu()
                submenu.autoenablesItems = false
                for folder in snapshot.favorites {
                    submenu.addItem(item(folder.name, command: .request(.init(action: .favorite, favoriteID: folder.id))))
                }
                root.submenu = submenu
                content.addItem(root)
            }
        }
        content.addItem(.separator())
        content.addItem(item("RightNook 설정…", symbol: "gearshape", command: .request(.init(action: .settings))))
        if !snapshot.groupMenus { return content }
        let menu = NSMenu()
        let parent = NSMenuItem(title: "RightNook", action: nil, keyEquivalent: "")
        parent.image = NSImage(systemSymbolName: "cursorarrow.click.2", accessibilityDescription: nil)
        parent.submenu = content
        menu.addItem(parent)
        return menu
    }
    private func classify(_ url: URL) -> SelectedItem? {
        guard url.isFileURL else { return nil }
        // Keep unknown selected items in the count. Dropping one would turn a
        // mixed multi-selection into an apparently safe single-item creation.
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey])
        return .init(url: url, isDirectory: values?.isDirectory, isPackage: values?.isPackage == true)
    }
    private func item(_ title: String, symbol: String? = nil, command: MenuCommand?) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(performCommand(_:)), keyEquivalent: "")
        item.target = self
        if case .request(let request) = command, (try? request.encodedURL()) == nil {
            item.isEnabled = false
            item.toolTip = "대상은 최대 100개까지 지원합니다. 경로가 너무 길면 선택 개수를 줄여 주세요."
            return item
        }
        item.isEnabled = command != nil
        if let command {
            item.tag = nextTag
            commands[nextTag] = command
            generations[generations.count - 1].append(nextTag)
            nextTag += 1
        }
        if let symbol { item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil) }
        return item
    }
    @objc private func performCommand(_ sender: NSMenuItem) {
        guard let command = commands[sender.tag] else {
            logger.error("Expired Finder menu command")
            return
        }
        switch command {
        case .copyPaths(let paths):
            guard !paths.isEmpty, SharedFiles.loadSnapshot()?.visibleEntries.contains(where: { $0.id == .copyPath }) == true else { return }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.setString(paths.joined(separator: "\n"), forType: .string)
        case .request(let request):
            do {
                let url = try request.encodedURL()
                let containingApp = Bundle.main.bundleURL.deletingLastPathComponent()
                    .deletingLastPathComponent().deletingLastPathComponent()
                let application = request.action.creationFormat == nil ? containingApp : RightNook.fileCreatorURL(in: containingApp)
                guard FileManager.default.fileExists(atPath: application.appendingPathComponent("Contents/Info.plist").path) else {
                    showLaunchFailure(isFileCreation: request.action.creationFormat != nil, error: nil)
                    return
                }
                let config = NSWorkspace.OpenConfiguration()
                config.activates = request.action == .settings
                config.arguments = ["--finder-action"]
                NSWorkspace.shared.open([url], withApplicationAt: application, configuration: config) { [weak self] _, error in
                    if let error { self?.showLaunchFailure(isFileCreation: request.action.creationFormat != nil, error: error) }
                }
            } catch { logger.error("Invalid action request") }
        }
    }
    private func showLaunchFailure(isFileCreation: Bool, error: Error?) {
        logger.error("Could not open action application")
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = isFileCreation ? "파일 생성 도우미를 열지 못했습니다." : "RightNook을 열지 못했습니다."
            alert.informativeText = "RightNook 앱이 이동되었거나 설치가 불완전할 수 있습니다. 설치된 앱을 확인하고 다시 빌드·설치한 뒤 Finder 메뉴를 다시 열어 주세요."
            if let error { alert.informativeText += "\n\(error.localizedDescription)" }
            alert.addButton(withTitle: "확인")
            alert.runModal()
        }
    }
}
