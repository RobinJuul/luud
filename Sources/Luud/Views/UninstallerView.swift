import SwiftUI

struct UninstallerView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case apps = "Applications"
        case unused = "Unused"
        case leftovers = "Leftovers"
        var id: String { rawValue }
    }

    enum SortOrder: String, CaseIterable, Identifiable {
        case name = "Name", size = "Size", lastUsed = "Last opened"
        var id: String { rawValue }
    }

    @EnvironmentObject private var model: UninstallerModel
    @State private var mode: Mode = .apps
    @State private var sort: SortOrder = .name
    @State private var search = ""
    @State private var confirmUninstall = false
    @State private var confirmOrphans = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(section: .uninstaller, subtitle: "Remove apps together with the files they leave behind", isActive: model.isLoading || model.isLoadingOrphans) {
                Picker("", selection: $mode) {
                    ForEach(Mode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .frame(width: 300)
            }

            if let message = model.message {
                StatusBanner(text: message) { model.message = nil }
            }

            switch mode {
            case .apps, .unused: appsBrowser
            case .leftovers: orphansView
            }
        }
        .task { if !model.hasLoaded { await model.load() } }
        .onChange(of: mode) { _, newMode in
            if newMode == .leftovers && model.orphans.isEmpty && !model.isLoadingOrphans {
                Task { await model.loadOrphans() }
            }
        }
    }

    // MARK: Apps

    private var visibleApps: [InstalledApp] {
        var apps = mode == .unused ? model.unusedApps : model.apps
        if !search.isEmpty { apps = apps.filter { $0.name.localizedCaseInsensitiveContains(search) } }
        switch sort {
        case .name: return apps
        case .size: return apps.sorted { ($0.size ?? 0) > ($1.size ?? 0) }
        case .lastUsed: return apps.sorted { ($0.lastUsed ?? .distantPast) < ($1.lastUsed ?? .distantPast) }
        }
    }

    private var appsBrowser: some View {
        HSplitView {
            VStack(spacing: 0) {
                HStack {
                    TextField("Search apps", text: $search).textFieldStyle(.roundedBorder)
                    Picker("", selection: $sort) {
                        ForEach(SortOrder.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .frame(width: 120)
                }
                .padding(10)
                List(visibleApps, selection: $model.selection) { app in
                    HStack(spacing: 10) {
                        Image(nsImage: IconCache.icon(for: app.url)).resizable().frame(width: 28, height: 28)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(app.name).lineLimit(1)
                            Text("Opened \(Fmt.relativeDate(app.lastUsed))").font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text(app.size.map(Fmt.bytes) ?? "…").monospacedDigit().foregroundStyle(.secondary)
                    }
                    .tag(app.id)
                }
                .overlay { if model.isLoading { ProgressView() } }
            }
            .frame(minWidth: 320, idealWidth: 360)

            appDetail
                .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
        }
        .onChange(of: model.selection) { _, _ in model.loadLeftovers() }
    }

    @ViewBuilder
    private var appDetail: some View {
        if let app = model.selectedApp {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    Image(nsImage: IconCache.icon(for: app.url)).resizable().frame(width: 64, height: 64)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(app.name).font(.title2.bold())
                        Text([app.version.map { "Version \($0)" }, app.bundleID, app.isAppStore ? "App Store" : nil]
                            .compactMap { $0 }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        Text("Last opened \(Fmt.relativeDate(app.lastUsed))").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                HStack {
                    Text("App bundle").font(.headline)
                    Spacer()
                    Text(app.size.map(Fmt.bytes) ?? "Measuring…").monospacedDigit()
                }

                HStack {
                    Text("Related files").font(.headline)
                    if model.isLoadingLeftovers { ProgressView().controlSize(.small) }
                    Spacer()
                    Text(Fmt.bytes(model.leftovers.filter(\.selected).reduce(0) { $0 + $1.size })).monospacedDigit()
                }

                List($model.leftovers) { $leftover in
                    HStack {
                        Toggle("", isOn: $leftover.selected).labelsHidden().toggleStyle(.checkbox)
                        Text(Fmt.abbreviatePath(leftover.url)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(Fmt.bytes(leftover.size)).monospacedDigit().foregroundStyle(.secondary)
                        ExplainButton(url: leftover.url, size: leftover.size, category: "Related files of \(app.name)")
                        Button { leftover.url.revealInFinder() } label: { Image(systemName: "magnifyingglass") }
                            .buttonStyle(.borderless)
                    }
                }
                .listStyle(.bordered)
                .overlay {
                    if model.leftovers.isEmpty && !model.isLoadingLeftovers {
                        Text("No related files found").foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Button("Show in Finder") { app.url.revealInFinder() }
                    Spacer()
                    Button("Uninstall \(app.name)", role: .destructive) { confirmUninstall = true }
                        .buttonStyle(.borderedProminent)
                        .tint(.red)
                }
                .controlSize(.large)
            }
            .padding(20)
            .confirmationDialog("Uninstall \(app.name)?", isPresented: $confirmUninstall) {
                Button("Move to Trash", role: .destructive) { Task { await model.uninstall(app) } }
            } message: {
                Text("The app and the selected related files are moved to the Trash. If the app is running it will be quit.")
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "xmark.app").font(.system(size: 44)).foregroundStyle(.tertiary)
                Text(mode == .unused ? "\(model.unusedApps.count) apps haven't been opened in 6 months" : "Select an app")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: Orphans

    private var orphansView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Support files whose app no longer seems to be installed. These are matched by bundle identifier, so check each one before removing it.")
                    .font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button("Rescan") { Task { await model.loadOrphans() } }.disabled(model.isLoadingOrphans)
                Button("Remove selected") { confirmOrphans = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.orphans.contains(where: \.selected))
            }
            .padding(.horizontal, 24)

            List($model.orphans) { $orphan in
                HStack {
                    Toggle("", isOn: $orphan.selected).labelsHidden().toggleStyle(.checkbox)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(orphan.url.lastPathComponent).lineLimit(1)
                        Text(Fmt.abbreviatePath(orphan.url.deletingLastPathComponent()))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(Fmt.bytes(orphan.size)).monospacedDigit().foregroundStyle(.secondary)
                    ExplainButton(url: orphan.url, size: orphan.size, category: "Possible leftover of a removed app")
                    Button { orphan.url.revealInFinder() } label: { Image(systemName: "magnifyingglass") }
                        .buttonStyle(.borderless)
                }
            }
            .overlay {
                if model.isLoadingOrphans { ProgressView("Looking for leftovers…") }
                else if model.orphans.isEmpty { Text("No leftovers found").foregroundStyle(.secondary) }
            }
        }
        .confirmationDialog("Move selected leftovers to the Trash?", isPresented: $confirmOrphans) {
            Button("Move to Trash", role: .destructive) { Task { await model.removeOrphans() } }
        }
    }
}
