import XCTest
import Darwin
@testable import RightNookCore

final class CoreTests: XCTestCase {
    func testLegacyVSCodeSettingMigratesWithoutChangingSelectionOrOrder() throws {
        var settings = Settings()
        settings.entries.reverse()
        settings.entries[1].enabled = true // The old VS Code position stays in place.
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        legacy.removeValue(forKey: "applications")
        let decoded = try JSONDecoder().decode(Settings.self, from: JSONSerialization.data(withJSONObject: legacy)).validated()
        XCTAssertEqual(decoded, settings)
        XCTAssertEqual(decoded.applications, [.visualStudioCode])
        var legacyMenu = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings.snapshot)) as? [String: Any])
        legacyMenu.removeValue(forKey: "applications")
        XCTAssertEqual(try JSONDecoder().decode(MenuSnapshot.self, from: JSONSerialization.data(withJSONObject: legacyMenu)), settings.snapshot)
        legacy["applications"] = []
        let cleared = try JSONDecoder().decode(Settings.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertTrue(cleared.applications.isEmpty)
        XCTAssertFalse(cleared.snapshot.visibleEntries.contains { $0.id == .vscode })
    }
    func testOpenApplicationRequestsUseRegisteredIdentityAndCurrentAuthorization() throws {
        var settings = Settings()
        settings.entries[3].enabled = true
        let app = OpenWithApplication(id: UUID(), name: "문서 앱", bundleID: "test.reader", path: "/Applications/문서 앱.app")
        settings.applications.append(app)
        let file = URL(fileURLWithPath: "/tmp/한글 ' $() ; & #.md")
        let request = ActionRequest(action: .openApplication, targets: [file], applicationID: app.id)
        XCTAssertEqual(try ActionRequest.decode(request.encodedURL()), request)
        XCTAssertEqual(try request.validatedApplication(in: settings), app)
        XCTAssertThrowsError(try ActionRequest(action: .openApplication, targets: [file]).validated())
        XCTAssertThrowsError(try ActionRequest(action: .openApplication, applicationID: app.id).validated())
        XCTAssertThrowsError(try ActionRequest(action: .openApplication, targets: [file], favoriteID: UUID(), applicationID: app.id).validated())
        XCTAssertThrowsError(try ActionRequest(action: .terminal, targets: [file], applicationID: app.id).validated())
        XCTAssertThrowsError(try ActionRequest(action: .openApplication, targets: [file], terminalApp: .iterm2, applicationID: app.id).validated())
        XCTAssertThrowsError(try ActionRequest(action: .openApplication, targets: [file], applicationID: UUID()).validatedApplication(in: settings))
        settings.applications[1].enabled = false
        XCTAssertThrowsError(try request.validatedApplication(in: settings))
        settings.applications[1].enabled = true
        settings.entries[3].enabled = false
        XCTAssertThrowsError(try request.validatedApplication(in: settings))
        settings.entries[3].enabled = true
        settings.applications.removeLast()
        XCTAssertThrowsError(try request.validatedApplication(in: settings))
        let oldRequest = ActionRequest(action: .vscode, targets: [file])
        XCTAssertEqual(try oldRequest.validatedApplication(in: settings), .visualStudioCode)
        settings.applications = [app]
        XCTAssertThrowsError(try oldRequest.validatedApplication(in: settings))
    }
    func testApplicationTargetFilteringKeepsWholeSelectionAndHandlesBackground() {
        let file = SelectedItem(url: URL(fileURLWithPath: "/tmp/a.md"), isDirectory: false)
        let folder = SelectedItem(url: URL(fileURLWithPath: "/tmp/folder", isDirectory: true), isDirectory: true)
        let mixed = ActionContext(location: .items, target: file, selected: [file, folder])
        XCTAssertTrue(mixed.applicationTargets(for: .files).isEmpty)
        XCTAssertTrue(mixed.applicationTargets(for: .folders).isEmpty)
        XCTAssertEqual(mixed.applicationTargets(for: .filesAndFolders), [file.url, folder.url])
        let background = ActionContext(location: .container, target: folder, selected: [file])
        XCTAssertTrue(background.applicationTargets(for: .files).isEmpty)
        XCTAssertEqual(background.applicationTargets(for: .folders), [folder.url])
        XCTAssertEqual(background.applicationTargets(for: .filesAndFolders), [folder.url])
        let unknown = SelectedItem(url: file.url, isDirectory: nil)
        XCTAssertTrue(ActionContext(location: .items, target: file, selected: [file, unknown]).applicationTargets(for: .filesAndFolders).isEmpty)
        XCTAssertTrue(ActionContext(location: .sidebar, target: folder, selected: [file]).applicationTargets(for: .filesAndFolders).isEmpty)
    }
    func testApplicationOrderMembershipAndSnapshotRoundTrip() throws {
        var settings = Settings()
        settings.entries[3].enabled = true
        let first = OpenWithApplication(id: UUID(), name: "A", bundleID: "test.a", path: "/Applications/A.app", target: .folders)
        let second = OpenWithApplication(id: UUID(), name: "B", bundleID: "test.b", path: "/Applications/B.app")
        settings.applications = [first, second, .visualStudioCode]
        settings.applications[0].enabled = false
        XCTAssertEqual(settings.applications.map(\.id), [first.id, second.id, OpenWithApplication.visualStudioCode.id])
        XCTAssertEqual(settings.snapshot.enabledApplications.map(\.id), [second.id, OpenWithApplication.visualStudioCode.id])
        let stored = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings)).validated()
        XCTAssertEqual(stored, settings)
        XCTAssertEqual(try JSONDecoder().decode(MenuSnapshot.self, from: JSONEncoder().encode(settings.snapshot)), settings.snapshot)
        settings.applications[1].enabled = false
        settings.applications[2].enabled = false
        XCTAssertFalse(settings.snapshot.visibleEntries.contains { $0.id == .vscode })
    }
    func testApplicationDocumentPackagesAreFilesNotFolders() {
        let project = SelectedItem(url: URL(fileURLWithPath: "/tmp/Project.xcodeproj", isDirectory: true), isDirectory: true, isPackage: true)
        let context = ActionContext(location: .items, target: project, selected: [project])
        XCTAssertEqual(context.applicationTargets(for: .files), [project.url])
        XCTAssertTrue(context.applicationTargets(for: .folders).isEmpty)
        XCTAssertEqual(context.applicationTargets(for: .filesAndFolders), [project.url])
    }
    func testInvalidApplicationRegistrationsAreRejected() throws {
        var settings = Settings()
        let app = OpenWithApplication.visualStudioCode
        settings.applications = [app, app]
        XCTAssertThrowsError(try settings.validated())
        XCTAssertTrue(settings.snapshot.enabledApplications.isEmpty)
        let duplicateBundle = OpenWithApplication(id: UUID(), name: "Duplicate", bundleID: app.bundleID, path: app.path)
        settings.applications = [app, duplicateBundle]
        XCTAssertThrowsError(try settings.validated())
        settings.applications = [app]
        settings.applications[0].name = "  "
        XCTAssertThrowsError(try settings.validated())
        settings.applications = [app]
        settings.applications[0].path = "/tmp/script.sh"
        XCTAssertThrowsError(try settings.validated())
        settings.applications[0].path = "relative.app"
        XCTAssertThrowsError(try settings.validated())
    }
    func testFileAndFolderContextsAndBackgroundSelection() {
        let folder = URL(fileURLWithPath: "/tmp/한글 폴더", isDirectory: true)
        let file = folder.appendingPathComponent("a '$;().txt")
        let item = SelectedItem(url: file, isDirectory: false)
        let single = ActionContext(location: .items, target: item, selected: [item])
        XCTAssertEqual(single.creationFolder, folder)
        XCTAssertEqual(single.terminalFolder, folder)
        XCTAssertEqual(single.editorTargets, [file])
        let background = ActionContext(location: .container, target: .init(url: folder, isDirectory: true), selected: [item])
        XCTAssertEqual(background.pathsToCopy, [folder.path])
        XCTAssertEqual(background.editorTargets, [folder])
        let many = ActionContext(location: .items, target: item, selected: [item, item])
        XCTAssertNil(many.creationFolder)
        XCTAssertNil(many.terminalFolder)
        XCTAssertEqual(many.pathsToCopy, [file.path, file.path])
        let unknown = SelectedItem(url: folder, isDirectory: nil)
        XCTAssertNil(ActionContext(location: .items, target: unknown, selected: [unknown]).creationFolder)
        XCTAssertNil(ActionContext(location: .items, target: unknown, selected: [item, unknown]).creationFolder)
        XCTAssertTrue(ActionContext(location: .items, target: nil, selected: []).pathsToCopy.isEmpty)
    }
    func testRequestPreservesPathsAndRejectsExtraInstructions() throws {
        let url = URL(fileURLWithPath: "/tmp/한글 ' $() ; & #.txt")
        let request = ActionRequest(action: .vscode, targets: [url])
        XCTAssertEqual(try ActionRequest.decode(request.encodedURL()), request)
        XCTAssertThrowsError(try ActionRequest.decode(URL(string: "quickright://action?request=x&shell=rm")!))
        XCTAssertThrowsError(try ActionRequest(action: .terminal, targets: []).validated())
        XCTAssertThrowsError(try ActionRequest(action: .newText, targets: [URL(string: "https://example.com")!]).validated())
        XCTAssertThrowsError(try ActionRequest(action: .settings, targets: [url]).validated())
        XCTAssertThrowsError(try ActionRequest(version: 99, action: .settings).validated())
    }
    func testDefaultMenusAreNotPublishedAndEmptySubmenusHide() throws {
        var settings = Settings()
        XCTAssertTrue(settings.snapshot.visibleEntries.isEmpty)
        settings.entries = [.init(id: .vscode, enabled: true), .init(id: .newFile, enabled: true),
                            .init(id: .favorites, enabled: true), .init(id: .copyPath, enabled: false),
                            .init(id: .terminal, enabled: false)]
        settings.formats = []
        XCTAssertEqual(try settings.validated().snapshot.visibleEntries.map(\.id), [.vscode])
        settings.entries.append(.init(id: .vscode, enabled: false))
        XCTAssertThrowsError(try settings.validated())
        XCTAssertTrue(settings.snapshot.visibleEntries.isEmpty)
    }
    func testCreatesEmptyFilesWithoutTemplatesAndNeverOverwrites() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let txt = directory.appendingPathComponent("한글 ' $().txt")
        try FileCreation.create(at: txt, format: .txt)
        XCTAssertEqual(try Data(contentsOf: txt).count, 0)
        let original = Data("keep existing data".utf8)
        try original.write(to: txt)
        XCTAssertThrowsError(try FileCreation.create(at: txt, format: .txt))
        XCTAssertEqual(try Data(contentsOf: txt), original)
        let markdown = directory.appendingPathComponent("메모.md")
        try FileCreation.create(at: markdown, format: .md)
        XCTAssertTrue(FileManager.default.fileExists(atPath: markdown.path))
        XCTAssertThrowsError(try FileCreation.create(at: directory.appendingPathComponent("wrong.rtf"), format: .txt))
        XCTAssertThrowsError(try FileCreation.create(at: directory.appendingPathComponent("missing/file.txt"), format: .txt))
    }
    func testMenuSnapshotUsesOwnDirectoryAndPreservesOnlyDisplayData() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let directory = SharedFiles.directory(in: home)
        XCTAssertEqual(directory.path, home.appendingPathComponent("Library/Application Support/QuickRight/Menu").path)
        XCTAssertFalse(directory.path.contains("Group Containers"))
        let file = directory.appendingPathComponent("menu-v1.json")
        var settings = Settings()
        settings.entries[0].enabled = true
        settings.favorites = [.init(id: UUID(), name: "폴더", displayPath: "/private/favorite", bookmark: Data("private bookmark".utf8))]
        try SharedFiles.write(settings.snapshot, to: file)
        XCTAssertEqual(SharedFiles.loadSnapshot(from: file), settings.snapshot)
        let text = try String(contentsOf: file, encoding: .utf8)
        XCTAssertFalse(text.contains("bookmark"))
        XCTAssertFalse(text.contains("displayPath"))
        XCTAssertFalse(text.contains("/private/favorite"))
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        settings.entries[0].enabled = false
        try SharedFiles.write(settings.snapshot, to: file)
        XCTAssertTrue(try XCTUnwrap(SharedFiles.loadSnapshot(from: file)).visibleEntries.isEmpty)
        try Data("invalid".utf8).write(to: file)
        XCTAssertNil(SharedFiles.loadSnapshot(from: file))
        try Data(repeating: 0, count: 262_145).write(to: file)
        XCTAssertNil(SharedFiles.loadSnapshot(from: file))
    }
    func testTerminalChoiceMigratesAndOnlyAllowsSupportedApps() throws {
        var settings = Settings()
        settings.entries[2].enabled = true
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings)) as? [String: Any])
        legacy.removeValue(forKey: "terminalApp")
        let migrated = try JSONDecoder().decode(Settings.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertEqual(migrated, settings)
        var legacyMenu = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(settings.snapshot)) as? [String: Any])
        legacyMenu.removeValue(forKey: "terminalApp")
        XCTAssertEqual(try JSONDecoder().decode(MenuSnapshot.self, from: JSONSerialization.data(withJSONObject: legacyMenu)), settings.snapshot)
        settings.terminalApp = .iterm2
        XCTAssertEqual(try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings)), settings)
        XCTAssertEqual(settings.snapshot.terminalApp.bundleID, "com.googlecode.iterm2")
        XCTAssertEqual(settings.snapshot.terminalApp.menuTitle, "iTerm2에서 열기")
        let request = ActionRequest(action: .terminal, targets: [URL(fileURLWithPath: "/tmp/한글 ' $()", isDirectory: true)], terminalApp: .iterm2)
        XCTAssertEqual(try ActionRequest.decode(request.encodedURL()), request)
        XCTAssertThrowsError(try ActionRequest(action: .settings, terminalApp: .iterm2).validated())
        legacy["terminalApp"] = "unsupported-bundle-id"
        XCTAssertThrowsError(try JSONDecoder().decode(Settings.self, from: JSONSerialization.data(withJSONObject: legacy)))
    }
    func testFileCreatorRouteAndCurrentFeatureAuthorization() throws {
        var settings = Settings()
        let folder = URL(fileURLWithPath: "/tmp/한글 공백 $()", isDirectory: true)
        let txt = ActionRequest(action: .newText, targets: [folder])
        let md = ActionRequest(action: .newMarkdown, targets: [folder])
        XCTAssertEqual(try txt.encodedURL().scheme, RightNook.fileCreatorScheme)
        XCTAssertEqual(try ActionRequest.decode(txt.encodedURL()), txt)
        var legacy = URLComponents(url: try txt.encodedURL(), resolvingAgainstBaseURL: false)!
        legacy.scheme = RightNook.scheme
        XCTAssertEqual(try ActionRequest.decode(XCTUnwrap(legacy.url)), txt)
        var wrongRoute = URLComponents(url: try ActionRequest(action: .settings).encodedURL(), resolvingAgainstBaseURL: false)!
        wrongRoute.scheme = RightNook.fileCreatorScheme
        XCTAssertThrowsError(try ActionRequest.decode(XCTUnwrap(wrongRoute.url)))
        XCTAssertThrowsError(try txt.validatedCreationFormat(in: nil))
        XCTAssertThrowsError(try txt.validatedCreationFormat(in: settings.snapshot))
        settings.entries[0].enabled = true
        XCTAssertEqual(try txt.validatedCreationFormat(in: settings.snapshot), .txt)
        XCTAssertEqual(try md.validatedCreationFormat(in: settings.snapshot), .md)
        settings.formats = [.txt]
        XCTAssertThrowsError(try md.validatedCreationFormat(in: settings.snapshot))
        settings.entries[0].enabled = false
        XCTAssertThrowsError(try txt.validatedCreationFormat(in: settings.snapshot))
        XCTAssertThrowsError(try ActionRequest(action: .settings).validatedCreationFormat(in: settings.snapshot))
        XCTAssertThrowsError(try ActionRequest(action: .newText, targets: [folder, folder]).validatedCreationFormat(in: settings.snapshot))
        let app = URL(fileURLWithPath: "/Applications/RightNook.app", isDirectory: true)
        XCTAssertEqual(RightNook.fileCreatorURL(in: app).path, "/Applications/RightNook.app/Contents/Helpers/RightNookFileCreator.app")
    }
    func testDestinationValidationProtectsFilesFoldersAndBrokenSymlinks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let existing = directory.appendingPathComponent("existing.txt")
        try Data("keep original".utf8).write(to: existing)
        let folder = directory.appendingPathComponent("folder.txt", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        let brokenLink = directory.appendingPathComponent("broken.txt")
        try FileManager.default.createSymbolicLink(at: brokenLink, withDestinationURL: directory.appendingPathComponent("absent"))
        for url in [existing, folder, brokenLink] {
            XCTAssertThrowsError(try FileCreation.validateDestination(at: url, format: .txt)) {
                XCTAssertEqual(FileCreationProblem.classify($0), .nameConflict)
            }
            XCTAssertThrowsError(try FileCreation.create(at: url, format: .txt))
        }
        XCTAssertEqual(try String(contentsOf: existing, encoding: .utf8), "keep original")
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: brokenLink.path), directory.appendingPathComponent("absent").path)
        XCTAssertThrowsError(try FileCreation.create(at: directory.appendingPathComponent("gone/new.txt"), format: .txt)) {
            XCTAssertEqual(FileCreationProblem.classify($0), .missingLocation)
        }
        let planned = directory.appendingPathComponent("race.txt")
        try FileCreation.validateDestination(at: planned, format: .txt)
        try Data("created after validation".utf8).write(to: planned)
        XCTAssertThrowsError(try FileCreation.create(at: planned, format: .txt))
        XCTAssertEqual(try String(contentsOf: planned, encoding: .utf8), "created after validation")
    }
    func testWritePermissionAndDeletedDestinationFailuresRemainSpecific() throws {
        guard geteuid() != 0 else { throw XCTSkip("Permission test requires a non-root user") }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
            try? FileManager.default.removeItem(at: directory)
        }
        let output = directory.appendingPathComponent("denied.txt")
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: directory.path)
        XCTAssertThrowsError(try FileCreation.create(at: output, format: .txt)) {
            XCTAssertEqual(FileCreationProblem.classify($0), .permissionDenied)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
        try FileCreation.validateDestination(at: output, format: .txt)
        try FileManager.default.removeItem(at: directory)
        XCTAssertThrowsError(try FileCreation.create(at: output, format: .txt)) {
            XCTAssertEqual(FileCreationProblem.classify($0), .missingLocation)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
    }
    func testFailureClassificationAndRetryPolicy() {
        let examples: [(Int32, FileCreationProblem)] = [(EEXIST, .nameConflict), (EACCES, .permissionDenied),
            (EPERM, .permissionDenied), (EROFS, .readOnlyLocation), (ENOENT, .missingLocation),
            (ENOTDIR, .missingLocation), (ENOSPC, .notEnoughSpace), (EDQUOT, .notEnoughSpace), (ENAMETOOLONG, .invalidName)]
        for (code, expected) in examples {
            let underlying = NSError(domain: NSPOSIXErrorDomain, code: Int(code))
            let wrapped = NSError(domain: NSCocoaErrorDomain, code: NSFileWriteUnknownError,
                                  userInfo: [NSUnderlyingErrorKey: underlying])
            XCTAssertEqual(FileCreationProblem.classify(wrapped), expected)
            XCTAssertTrue(expected.canChooseAgain)
        }
        XCTAssertEqual(FileCreationProblem.classify(NSError(domain: NSCocoaErrorDomain, code: NSFileWriteFileExistsError)), .nameConflict)
        XCTAssertEqual(FileCreationProblem.classify(RightNookError.disabled), .disabled)
        XCTAssertFalse(FileCreationProblem.disabled.canChooseAgain)
        XCTAssertFalse(FileCreationProblem.invalidRequest.canChooseAgain)
        XCTAssertEqual(FileCreationProblem.classify(NSError(domain: "unknown", code: 1)), .other)
    }
    func testLegacyFormatsRemainSelectedAndNewFormatsAreExplicitAndOrdered() throws {
        var old = Settings()
        old.formats = [.md, .txt]
        old.formatOrder = [.md, .txt, .rtf, .docx, .xlsx, .pptx]
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(old)) as? [String: Any])
        legacy.removeValue(forKey: "formatOrder")
        var settings = try JSONDecoder().decode(Settings.self, from: JSONSerialization.data(withJSONObject: legacy)).validated()
        XCTAssertEqual(settings, old)
        XCTAssertEqual(settings.formats, [.md, .txt])
        XCTAssertEqual(settings.formatOrder, old.formatOrder)
        settings.setFormat(.docx, enabled: true)
        settings.setFormat(.docx, enabled: true)
        settings.moveFormat(.docx, by: -1)
        XCTAssertEqual(settings.snapshot.formats, [.md, .txt, .docx])
        settings.moveFormat(.docx, by: -1)
        XCTAssertEqual(settings.snapshot.formats, [.md, .docx, .txt])
        settings.moveFormat(.md, by: -1)
        settings.moveFormat(.xlsx, by: -1)
        XCTAssertEqual(settings.snapshot.formats, [.md, .docx, .txt])
        settings.setFormat(.docx, enabled: false)
        XCTAssertEqual(settings.formats, [.md, .txt])
        XCTAssertEqual(settings.snapshot.formats, [.md, .txt])
        settings.formats = [.txt, .txt]
        XCTAssertThrowsError(try settings.validated())
    }
    func testCheckingAndUncheckingNeverMoveFormatRows() {
        var settings = Settings()
        settings.formats = FileFormat.allCases
        settings.moveFormat(.xlsx, by: -1)
        let order = settings.formatOrder
        settings.setFormat(.xlsx, enabled: false)
        XCTAssertEqual(settings.formatOrder, order)
        settings.setFormat(.xlsx, enabled: true)
        XCTAssertEqual(settings.formatOrder, order)
        settings.setFormat(.md, enabled: false)
        XCTAssertEqual(settings.formatOrder, order)
        settings.setFormat(.md, enabled: true)
        XCTAssertEqual(settings.formatOrder, order)
    }
    func testDisabledFormatCanMoveAndOrderSurvivesSavingAndReopening() throws {
        var settings = Settings()
        settings.entries[0].enabled = true
        settings.formatOrder = [.xlsx, .rtf, .docx, .md, .pptx, .txt]
        settings.formats = [.txt, .md, .xlsx]
        settings.setFormat(.md, enabled: false)
        settings.moveFormat(.md, by: -1)
        let order: [FileFormat] = [.xlsx, .rtf, .md, .docx, .pptx, .txt]
        XCTAssertEqual(settings.formatOrder, order)
        XCTAssertEqual(settings.snapshot.formats, [.xlsx, .txt])
        let reloaded = try JSONDecoder().decode(Settings.self, from: JSONEncoder().encode(settings)).validated()
        XCTAssertEqual(reloaded, settings)
        var enabledAgain = reloaded
        enabledAgain.setFormat(.md, enabled: true)
        XCTAssertEqual(enabledAgain.formatOrder, order)
        XCTAssertEqual(enabledAgain.snapshot.formats, [.xlsx, .md, .txt])
        enabledAgain.formatOrder[0] = enabledAgain.formatOrder[1]
        XCTAssertThrowsError(try enabledAgain.validated())
    }
    func testEveryFileFormatRoutesToHelperAndChecksCurrentSelection() throws {
        var settings = Settings()
        settings.entries[0].enabled = true
        settings.formats = []
        let folder = URL(fileURLWithPath: "/tmp/한글 공백 '$()", isDirectory: true)
        for format in FileFormat.allCases {
            let request = ActionRequest(action: format.action, targets: [folder])
            XCTAssertEqual(request.action.creationFormat, format)
            XCTAssertEqual(request.action.feature, .newFile)
            XCTAssertEqual(try request.encodedURL().scheme, RightNook.fileCreatorScheme)
            XCTAssertEqual(try ActionRequest.decode(request.encodedURL()), request)
            XCTAssertThrowsError(try request.validatedCreationFormat(in: settings.snapshot))
            settings.setFormat(format, enabled: true)
            XCTAssertEqual(try request.validatedCreationFormat(in: settings.snapshot), format)
            settings.setFormat(format, enabled: false)
            XCTAssertThrowsError(try request.validatedCreationFormat(in: settings.snapshot))
            XCTAssertThrowsError(try ActionRequest(action: format.action, targets: []).validated())
        }
    }
    func testAllFormatsCreateBundledContentsAndPreserveExistingFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for format in FileFormat.allCases {
            let output = directory.appendingPathComponent("한글 공백 '$().\(format.rawValue)")
            try FileCreation.create(at: output, format: format)
            let data = try Data(contentsOf: output)
            XCTAssertEqual(data, try FileTemplates.data(for: format))
            XCTAssertEqual(data.isEmpty, format == .txt || format == .md)
            try Data("preserve original".utf8).write(to: output)
            XCTAssertThrowsError(try FileCreation.create(at: output, format: format))
            XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "preserve original")
        }
    }
    func testMissingEmptyAndWrongTemplateFailsWithoutBlankFallback() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for format in [FileFormat.rtf, .docx, .xlsx, .pptx] {
            let file = directory.appendingPathComponent("blank.\(format.rawValue)")
            XCTAssertThrowsError(try FileTemplates.data(for: format, in: directory))
            for data in [Data(), Data("not a document".utf8)] {
                try data.write(to: file)
                XCTAssertThrowsError(try FileTemplates.data(for: format, in: directory)) {
                    XCTAssertEqual(FileCreationProblem.classify($0), .templateUnavailable)
                    XCTAssertFalse(FileCreationProblem.classify($0).canChooseAgain)
                }
            }
        }
    }
}
