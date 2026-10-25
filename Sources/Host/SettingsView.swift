import SwiftUI
import FinderSync

private enum SettingsPane: String, CaseIterable, Identifiable {
    case menu, files, applications, folders
    var id: Self { self }
    var title: String {
        switch self {
        case .menu: return "Finder 메뉴"
        case .files: return "새 파일"
        case .applications: return "앱"
        case .folders: return "폴더"
        }
    }
    var symbol: String {
        switch self {
        case .menu: return "cursorarrow.click"
        case .files: return "doc.badge.plus"
        case .applications: return "arrow.up.forward.app"
        case .folders: return "folder"
        }
    }
}

struct SettingsView: View {
    @ObservedObject var store: SettingsStore
    @State private var pane: SettingsPane = .menu

    var body: some View {
        VStack(spacing: 0) {
            header
            Picker("설정 탭", selection: $pane) {
                ForEach(SettingsPane.allCases) { Label($0.title, systemImage: $0.symbol).tag($0) }
            }.pickerStyle(.segmented).labelsHidden().controlSize(.large).frame(width: 500).padding(.bottom, 18)
            Divider()
            Group {
                switch pane {
                case .menu: menuPane
                case .files: filesPane
                case .applications: applicationsPane
                case .folders: foldersPane
                }
            }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            footer
        }.background(Color(nsColor: .windowBackgroundColor)).frame(minWidth: 760, minHeight: 650)
    }
    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "cursorarrow.click.2").font(.system(size: 25, weight: .medium)).foregroundStyle(.white)
                .frame(width: 46, height: 46).background(.blue.gradient, in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 3) {
                Text("RightNook").font(.system(size: 22, weight: .semibold))
                Text("설정").font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            Menu {
                Button("Finder 확장 설정 열기") { FIFinderSyncController.showExtensionManagementInterface() }
                Button("연결 상태 새로고침") { store.refreshExtension() }
            } label: {
                Label(store.extensionEnabled ? "Finder 연결됨" : "확장 연결 필요",
                      systemImage: store.extensionEnabled ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .font(.callout).foregroundStyle(store.extensionEnabled ? Color.green : Color.orange)
            }.menuStyle(.borderlessButton).fixedSize()
        }.padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 20)
    }
    private var menuPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                paneTitle("Finder 메뉴", subtitle: "드래그하여 순서 변경")
                Spacer()
                Menu {
                    Button("기본 항목 선택") { store.recommendedSelection() }
                    Button("모두 끄기") { for index in store.draft.entries.indices { store.draft.entries[index].enabled = false } }
                } label: { Image(systemName: "ellipsis.circle").font(.title3) }
                    .menuStyle(.borderlessButton).fixedSize().help("메뉴 선택 작업")
            }
            HStack(alignment: .top, spacing: 18) {
                List {
                    ForEach(store.draft.entries) { entry in
                        HStack(spacing: 12) {
                            grip(entry.id.title)
                            icon(entry.id.symbol, color: featureColor(entry.id))
                            VStack(alignment: .leading, spacing: 3) {
                                Text(entry.id.title).fontWeight(.medium)
                                Text(featureDetail(entry.id)).font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 4)
                            if entry.id == .terminal {
                                Picker("터미널 앱", selection: $store.draft.terminalApp) {
                                    ForEach(TerminalApp.allCases) { Text($0.name).tag($0) }
                                }.labelsHidden().controlSize(.small).frame(width: 110)
                            }
                            if [.newFile, .vscode, .favorites].contains(entry.id) {
                                Button { pane = entry.id == .newFile ? .files : (entry.id == .vscode ? .applications : .folders) } label: { Image(systemName: "slider.horizontal.3") }
                                    .buttonStyle(.borderless).help("\(entry.id.title) 설정")
                            }
                            Toggle(entry.id.title, isOn: featureBinding(entry.id)).labelsHidden().toggleStyle(.switch).controlSize(.small)
                        }.padding(.vertical, 7).contextMenu {
                            Button("위로 이동") { store.moveFeature(entry.id, by: -1) }.disabled(store.draft.entries.first?.id == entry.id)
                            Button("아래로 이동") { store.moveFeature(entry.id, by: 1) }.disabled(store.draft.entries.last?.id == entry.id)
                        }
                    }.onMove { store.draft.entries.move(fromOffsets: $0, toOffset: $1) }
                }.listStyle(.plain).scrollContentBackground(.hidden)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.07)))
                menuPreview.frame(width: 202)
            }
            HStack(spacing: 16) {
                Text("메뉴 표시 방식").font(.callout.weight(.medium))
                Picker("메뉴 표시 방식", selection: $store.draft.groupMenus) {
                    Text("개별 메뉴").tag(false)
                    Text("RightNook으로 묶기").tag(true)
                }.pickerStyle(.segmented).labelsHidden().frame(width: 250)
                Spacer()
            }.padding(14).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
        }
    }
    private var filesPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                paneTitle("새 파일 만들기", subtitle: "사용할 형식을 선택하고 드래그하여 순서 변경")
                Spacer()
                Toggle("새 파일 만들기 사용", isOn: featureBinding(.newFile)).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            HStack {
                Text("\(store.draft.formats.count) / \(FileFormat.allCases.count)개 형식 선택").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Menu("선택") {
                    Button("모두 선택") { store.draft.formats = FileFormat.allCases }
                    Button("모두 해제") { store.draft.formats = [] }
                }.menuStyle(.borderlessButton).fixedSize()
            }
            List {
                ForEach(store.draft.formatOrder) { format in
                    HStack(spacing: 12) {
                        grip(format.title)
                        icon(formatSymbol(format), color: formatColor(format))
                        VStack(alignment: .leading, spacing: 3) {
                            Text(format.title).fontWeight(.medium)
                            Text(formatDetail(format)).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Toggle(format.title, isOn: Binding(get: { store.draft.formats.contains(format) }, set: { store.setFormat(format, enabled: $0) }))
                            .labelsHidden().toggleStyle(.checkbox)
                    }.padding(.vertical, 6).contextMenu {
                        Button("위로 이동") { store.draft.moveFormat(format, by: -1) }.disabled(store.draft.formatOrder.first == format)
                        Button("아래로 이동") { store.draft.moveFormat(format, by: 1) }.disabled(store.draft.formatOrder.last == format)
                    }
                }.onMove { store.draft.formatOrder.move(fromOffsets: $0, toOffset: $1) }
            }.listStyle(.plain).scrollContentBackground(.hidden)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.07)))
            Label(store.draft.isEnabled(.newFile) ? "선택한 형식만 Finder 메뉴에 표시됩니다." : "현재 새 파일 메뉴는 꺼져 있습니다. 형식과 순서는 미리 설정할 수 있습니다.", systemImage: "info.circle")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
    private var foldersPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                paneTitle("자주 쓰는 폴더", subtitle: "폴더를 추가하고 드래그하여 순서 변경")
                Spacer()
                Toggle("자주 쓰는 폴더 사용", isOn: featureBinding(.favorites)).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            HStack {
                Text("\(store.draft.favorites.count)개 폴더 등록").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button { store.addFolder() } label: { Label("폴더 추가", systemImage: "plus") }
            }
            if store.draft.favorites.isEmpty {
                VStack(spacing: 13) {
                    Image(systemName: "folder.badge.plus").font(.system(size: 44, weight: .light)).foregroundStyle(.blue)
                    Text("등록된 폴더가 없습니다.").font(.title3.weight(.semibold))
                    Text("추가한 폴더는 Finder 메뉴에서 열 수 있습니다.").foregroundStyle(.secondary)
                    Button("폴더 추가") { store.addFolder() }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.background, in: RoundedRectangle(cornerRadius: 12))
            } else {
                List {
                    ForEach(store.draft.favorites) { folder in
                        HStack(spacing: 12) {
                            grip(folder.name)
                            icon("folder.fill", color: .blue)
                            VStack(alignment: .leading, spacing: 4) {
                                TextField("표시 이름", text: folderName(folder.id)).textFieldStyle(.plain).fontWeight(.medium)
                                Text(folder.displayPath).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(folder.displayPath)
                            }
                            Spacer()
                            Menu {
                                Button("다시 연결") { store.addFolder(reconnecting: folder.id) }
                                Button("위로 이동") { store.moveFolder(folder.id, by: -1) }.disabled(store.draft.favorites.first?.id == folder.id)
                                Button("아래로 이동") { store.moveFolder(folder.id, by: 1) }.disabled(store.draft.favorites.last?.id == folder.id)
                                Divider()
                                Button("등록 해제", role: .destructive) { store.draft.favorites.removeAll { $0.id == folder.id } }
                            } label: { Image(systemName: "ellipsis") }
                                .menuStyle(.borderlessButton).fixedSize().help("\(folder.name) 폴더 작업")
                        }.padding(.vertical, 8)
                    }.onMove { store.draft.favorites.move(fromOffsets: $0, toOffset: $1) }
                }.listStyle(.plain).scrollContentBackground(.hidden).background(.background, in: RoundedRectangle(cornerRadius: 12))
            }
            Label("등록 해제는 목록에서만 제거합니다. 실제 폴더는 그대로 남습니다.", systemImage: "info.circle").font(.callout).foregroundStyle(.secondary)
        }
    }
    private var applicationsPane: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top) {
                paneTitle("앱으로 열기", subtitle: "앱을 추가하고 드래그하여 순서 변경")
                Spacer()
                Toggle("앱으로 열기 사용", isOn: featureBinding(.vscode)).labelsHidden().toggleStyle(.switch).controlSize(.small)
            }
            HStack {
                Text("\(store.draft.applications.count)개 앱 등록").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button { store.addApplications() } label: { Label("앱 추가", systemImage: "plus") }
            }
            if store.draft.applications.isEmpty {
                VStack(spacing: 13) {
                    Image(systemName: "app.badge").font(.system(size: 44, weight: .light)).foregroundStyle(.indigo)
                    Text("등록된 앱이 없습니다.").font(.title3.weight(.semibold))
                    Button("앱 추가") { store.addApplications() }.buttonStyle(.borderedProminent)
                }.frame(maxWidth: .infinity, maxHeight: .infinity).background(.background, in: RoundedRectangle(cornerRadius: 12))
            } else {
                List {
                    ForEach(store.draft.applications) { app in applicationRow(app) }
                        .onMove { store.draft.applications.move(fromOffsets: $0, toOffset: $1) }
                }.listStyle(.plain).scrollContentBackground(.hidden)
                    .background(.background, in: RoundedRectangle(cornerRadius: 12))
            }
            Label(store.draft.isEnabled(.vscode) ? "열기 대상은 파일·폴더 중에서 선택합니다. 파일 형식 지원은 앱에 따라 다릅니다." : "현재 앱으로 열기 메뉴는 꺼져 있습니다. 앱 목록은 미리 설정할 수 있습니다.", systemImage: "info.circle")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
    private func applicationRow(_ app: OpenWithApplication) -> some View {
        HStack(spacing: 12) {
            grip(app.name)
            Image(nsImage: NSWorkspace.shared.icon(forFile: ApplicationRegistry.url(for: app)?.path ?? app.path))
                .resizable().frame(width: 32, height: 32)
            VStack(alignment: .leading, spacing: 4) {
                TextField("표시 이름", text: applicationBinding(app.id, \.name, fallback: ""))
                    .textFieldStyle(.plain).fontWeight(.medium).accessibilityLabel("\(app.name) 표시 이름")
                Text(ApplicationRegistry.url(for: app) == nil ? "앱을 찾을 수 없습니다. 다시 선택해 주세요." : app.path)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle).help(app.path)
            }
            Spacer(minLength: 4)
            Picker("\(app.name) 열기 대상", selection: applicationBinding(app.id, \.target, fallback: .files)) {
                ForEach(ApplicationTarget.allCases) { Text($0.title).tag($0) }
            }.labelsHidden().controlSize(.small).frame(width: 100)
            Toggle("\(app.name) 사용", isOn: applicationBinding(app.id, \.enabled, fallback: false))
                .labelsHidden().toggleStyle(.switch).controlSize(.small)
            Menu {
                Button("앱 다시 선택") { store.addApplications(replacing: app.id) }
                Button("위로 이동") { store.moveApplication(app.id, by: -1) }.disabled(store.draft.applications.first?.id == app.id)
                Button("아래로 이동") { store.moveApplication(app.id, by: 1) }.disabled(store.draft.applications.last?.id == app.id)
                Divider()
                Button("등록 해제", role: .destructive) { store.draft.applications.removeAll { $0.id == app.id } }
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).fixedSize().help("\(app.name) 앱 설정")
        }.padding(.vertical, 8).contentShape(Rectangle())
    }
    private var menuPreview: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("메뉴 미리보기").font(.callout.weight(.medium)).foregroundStyle(.secondary)
            if store.draft.snapshot.visibleEntries.isEmpty {
                Text("선택한 메뉴가 없습니다.").font(.callout).foregroundStyle(.secondary)
            } else {
                if store.draft.groupMenus { Label("RightNook", systemImage: "cursorarrow.click.2").fontWeight(.medium); Divider() }
                ForEach(store.draft.snapshot.visibleEntries) { entry in
                    HStack(spacing: 7) {
                        Image(systemName: entry.id.symbol).frame(width: 18).foregroundStyle(.secondary)
                        Text(entry.id == .terminal ? store.draft.terminalApp.menuTitle : entry.id.title).font(.system(size: 12)).lineLimit(1)
                        Spacer(minLength: 0)
                        if [.newFile, .vscode, .favorites].contains(entry.id) { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                    }
                }
                Divider()
                Label("RightNook 설정…", systemImage: "gearshape").font(.system(size: 12)).foregroundStyle(.secondary)
            }
        }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(.background, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.07)))
            .accessibilityElement(children: .contain).accessibilityLabel("Finder 메뉴 미리보기")
    }
    private var footer: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let error = store.errorMessage {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red).lineLimit(3)
                } else if store.hasChanges {
                    Label("적용 전", systemImage: "circle.fill").foregroundStyle(.orange).font(.callout.weight(.medium))
                    Text("모든 탭의 변경 사항을 함께 적용합니다.").font(.caption).foregroundStyle(.secondary)
                } else {
                    Label("저장됨", systemImage: "checkmark.circle").font(.callout).foregroundStyle(.secondary)
                    Text("RightNook \(RightNook.version) · Apple Silicon").font(.caption).foregroundStyle(.tertiary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button("되돌리기") { store.discardDraft() }.disabled(!store.hasChanges).help("적용하지 않은 변경 사항을 저장된 설정으로 되돌립니다.")
            Button("적용") { store.apply() }.buttonStyle(.borderedProminent).keyboardShortcut("s", modifiers: .command)
                .disabled(!store.hasChanges && store.errorMessage == nil)
        }.padding(.horizontal, 24).padding(.vertical, 16)
    }
    private func paneTitle(_ title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 20, weight: .semibold))
            Text(subtitle).font(.callout).foregroundStyle(.secondary)
        }
    }
    private func grip(_ title: String) -> some View {
        Image(systemName: "line.3.horizontal").font(.system(size: 12, weight: .medium)).foregroundStyle(.tertiary)
            .frame(width: 16, height: 32).help("드래그하여 \(title) 순서 변경").accessibilityLabel("\(title) 순서 이동")
    }
    private func icon(_ symbol: String, color: Color) -> some View {
        Image(systemName: symbol).font(.system(size: 16, weight: .medium)).foregroundStyle(color)
            .frame(width: 34, height: 34).background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
    }
    private func featureColor(_ feature: MenuFeature) -> Color {
        switch feature {
        case .newFile: return .blue
        case .copyPath: return .teal
        case .terminal: return .secondary
        case .vscode: return .indigo
        case .favorites: return .orange
        }
    }
    private func featureDetail(_ feature: MenuFeature) -> String {
        switch feature {
        case .newFile: return "\(store.draft.formats.count)개 파일 형식"
        case .copyPath: return "선택한 항목의 경로 복사"
        case .terminal: return "선택한 폴더에서 \(store.draft.terminalApp.name) 열기"
        case .vscode: return "\(store.draft.applications.filter(\.enabled).count)개 앱 사용"
        case .favorites: return "\(store.draft.favorites.count)개 폴더 등록"
        }
    }
    private func formatColor(_ format: FileFormat) -> Color {
        switch format {
        case .txt: return .secondary
        case .md: return .teal
        case .rtf: return .purple
        case .docx: return .blue
        case .xlsx: return .green
        case .pptx: return .orange
        }
    }
    private func formatSymbol(_ format: FileFormat) -> String {
        switch format {
        case .txt, .md: return "doc.text"
        case .rtf, .docx: return "doc.richtext"
        case .xlsx: return "tablecells"
        case .pptx: return "rectangle.on.rectangle"
        }
    }
    private func formatDetail(_ format: FileFormat) -> String {
        switch format {
        case .txt: return "빈 일반 텍스트"
        case .md: return "빈 Markdown 문서"
        case .rtf: return "서식 있는 빈 문서"
        case .docx: return "빈 Word 문서"
        case .xlsx: return "빈 워크시트 1개"
        case .pptx: return "빈 슬라이드 1장 · 16:9"
        }
    }
    private func featureBinding(_ id: MenuFeature) -> Binding<Bool> {
        Binding(get: { store.draft.isEnabled(id) }, set: { value in
            if let index = store.draft.entries.firstIndex(where: { $0.id == id }) { store.draft.entries[index].enabled = value }
        })
    }
    private func folderName(_ id: UUID) -> Binding<String> {
        Binding(get: { store.draft.favorites.first(where: { $0.id == id })?.name ?? "" }, set: { value in
            if let index = store.draft.favorites.firstIndex(where: { $0.id == id }) { store.draft.favorites[index].name = value }
        })
    }
    private func applicationBinding<Value>(_ id: UUID, _ keyPath: WritableKeyPath<OpenWithApplication, Value>, fallback: Value) -> Binding<Value> {
        Binding(get: { store.draft.applications.first(where: { $0.id == id })?[keyPath: keyPath] ?? fallback }, set: { value in
            if let index = store.draft.applications.firstIndex(where: { $0.id == id }) { store.draft.applications[index][keyPath: keyPath] = value }
        })
    }
}
