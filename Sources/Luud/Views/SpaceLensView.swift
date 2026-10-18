import AppKit
import Charts
import SwiftUI

struct SpaceLensView: View {
    @EnvironmentObject private var model: SpaceLensModel
    @State private var hasStarted = false
    @State private var pendingTrash: SizedNode?

    private let palette: [Color] = [Palette.memory, Palette.brandPink, Palette.disk, Palette.cpu, Palette.network, Palette.upload, .yellow, .indigo]

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(section: .spaceLens, subtitle: "See what takes up space, folder by folder", isActive: model.isLoading) {
                Button("Choose Folder…", action: chooseFolder).controlSize(.large)
            }

            if !hasStarted {
                EmptyStateView(
                    icon: "circle.hexagongrid",
                    title: "Map your disk",
                    message: "Measures every folder in your home folder so you can drill into whatever is biggest.",
                    actionTitle: "Scan Home Folder",
                    tint: Palette.memory
                ) {
                    hasStarted = true
                    model.start(at: FileManager.default.homeDirectoryForCurrentUser)
                }
            } else {
                breadcrumbs
                HStack(alignment: .top, spacing: 20) {
                    chart.frame(width: 280, height: 280)
                    list
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 16)
            }
        }
        .confirmationDialog("Move \(pendingTrash?.name ?? "") to the Trash?",
                            isPresented: Binding(get: { pendingTrash != nil }, set: { if !$0 { pendingTrash = nil } })) {
            Button("Move to Trash", role: .destructive) {
                if let node = pendingTrash { Task { _ = await model.trash(node) } }
            }
        } message: {
            Text("\(Fmt.bytes(pendingTrash?.size ?? 0)) — you can restore it from the Trash.")
        }
    }

    private var breadcrumbs: some View {
        HStack(spacing: 4) {
            ForEach(Array(model.path.enumerated()), id: \.offset) { index, url in
                if index > 0 { Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary) }
                Button(index == 0 ? Fmt.abbreviatePath(url) : url.lastPathComponent) { model.goTo(index: index) }
                    .buttonStyle(.borderless)
                    .fontWeight(index == model.path.count - 1 ? .semibold : .regular)
            }
            Spacer()
            if model.isLoading {
                ProgressView().controlSize(.small)
                Text("\(model.pending) left").font(.caption).foregroundStyle(.secondary)
            }
            Text(Fmt.bytes(model.total)).font(.headline).monospacedDigit()
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    private var chartSlices: [(name: String, size: Int64, color: Color)] {
        let top = model.nodes.prefix(palette.count - 1)
        var slices = top.enumerated().map { (name: $1.name, size: $1.size, color: palette[$0]) }
        let rest = model.nodes.dropFirst(top.count).reduce(0) { $0 + $1.size }
        if rest > 0 { slices.append((name: "Other", size: rest, color: .gray)) }
        return slices
    }

    private var chart: some View {
        Chart(chartSlices, id: \.name) { slice in
            SectorMark(angle: .value("Size", slice.size), innerRadius: .ratio(0.58), angularInset: 1.5)
                .foregroundStyle(slice.color.gradient)
                .cornerRadius(4)
        }
        .chartBackground { _ in
            VStack {
                Text(Fmt.bytes(model.total)).font(.title2.bold()).monospacedDigit()
                Text(model.current.lastPathComponent).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .animation(.easeInOut, value: model.nodes.count)
    }

    private var list: some View {
        let largest = Double(model.nodes.first?.size ?? 1)
        return List(model.nodes) { node in
            HStack(spacing: 10) {
                Image(nsImage: IconCache.icon(for: node.url)).resizable().frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 4) {
                    Text(node.name).lineLimit(1).truncationMode(.middle)
                    UsageBar(fraction: Double(node.size) / max(largest, 1), tint: color(for: node), height: 5)
                }
                Text(Fmt.bytes(node.size)).monospacedDigit().foregroundStyle(.secondary).frame(width: 80, alignment: .trailing)
                ExplainButton(url: node.url, size: node.size, category: "Space Lens")
                if node.isFolder {
                    Image(systemName: "chevron.right").foregroundStyle(.tertiary)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { model.open(node) }
            .contextMenu {
                if node.isFolder { Button("Open") { model.open(node) } }
                Button("Show in Finder") { node.url.revealInFinder() }
                Divider()
                Button("Move to Trash…", role: .destructive) { pendingTrash = node }
            }
        }
        .listStyle(.bordered)
    }

    private func color(for node: SizedNode) -> Color {
        guard let index = model.nodes.firstIndex(of: node), index < palette.count - 1 else { return .gray }
        return palette[index]
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = model.current
        if panel.runModal() == .OK, let url = panel.url {
            hasStarted = true
            model.start(at: url)
        }
    }
}

struct LargeFilesView: View {
    @EnvironmentObject private var model: LargeFilesModel
    @State private var confirmTrash = false
    @State private var search = ""

    private var visibleFiles: Binding<[LargeFile]> {
        // Filtering a binding keeps checkbox state attached to the model.
        Binding(
            get: { search.isEmpty ? model.files : model.files.filter { $0.name.localizedCaseInsensitiveContains(search) } },
            set: { updated in
                for file in updated {
                    if let index = model.files.firstIndex(where: { $0.id == file.id }) { model.files[index] = file }
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(section: .largeFiles, subtitle: "Big files in your home folder, biggest first", isActive: model.isScanning) {
                HStack {
                    Picker("Larger than", selection: $model.thresholdMB) {
                        Text("100 MB").tag(100)
                        Text("500 MB").tag(500)
                        Text("1 GB").tag(1_000)
                        Text("5 GB").tag(5_000)
                    }
                    .frame(width: 190)
                    if model.isScanning {
                        Button("Stop") { model.cancel() }
                    } else {
                        Button(model.hasScanned ? "Rescan" : "Scan") { model.scan() }
                    }
                    Button("Move \(Fmt.bytes(model.selectedSize)) to Trash") { confirmTrash = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.selectedSize == 0)
                }
                .controlSize(.large)
            }

            if let message = model.message { StatusBanner(text: message) { model.message = nil } }

            if !model.hasScanned && !model.isScanning {
                EmptyStateView(
                    icon: "doc.badge.ellipsis",
                    title: "Find large files",
                    message: "Looks through your home folder for big files you may have forgotten — old videos, VM images, archives. macOS may ask to allow access to Desktop, Documents and Downloads.",
                    actionTitle: "Scan",
                    tint: .teal
                ) { model.scan() }
            } else {
                TextField("Filter", text: $search)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 8)
                Table(visibleFiles) {
                    TableColumn("") { $file in
                        Toggle("", isOn: $file.selected).labelsHidden().toggleStyle(.checkbox)
                    }
                    .width(24)
                    TableColumn("Name") { $file in
                        HStack {
                            Image(nsImage: IconCache.icon(for: file.url)).resizable().frame(width: 18, height: 18)
                            Text(file.name).lineLimit(1).truncationMode(.middle)
                            Spacer(minLength: 4)
                            ExplainButton(url: file.url, size: file.size, category: "Large files")
                        }
                        .contextMenu { Button("Show in Finder") { file.url.revealInFinder() } }
                    }
                    TableColumn("Location") { $file in
                        Text(Fmt.abbreviatePath(file.url.deletingLastPathComponent()))
                            .foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                    }
                    TableColumn("Last opened") { $file in
                        Text(Fmt.relativeDate(file.lastOpened)).foregroundStyle(.secondary)
                    }
                    .width(130)
                    TableColumn("Size") { $file in
                        Text(Fmt.bytes(file.size)).monospacedDigit()
                    }
                    .width(90)
                }
                .overlay {
                    if model.isScanning {
                        VStack {
                            ProgressView()
                            Text("Checked \(model.scannedCount.formatted()) files…").foregroundStyle(.secondary)
                        }
                        .padding(Corner.bannerPadding)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Corner.banner, style: .continuous))
                    } else if model.files.isEmpty {
                        Text("Nothing larger than \(model.thresholdMB) MB").foregroundStyle(.secondary)
                    }
                }
            }
        }
        .confirmationDialog("Move \(Fmt.bytes(model.selectedSize)) to the Trash?", isPresented: $confirmTrash) {
            Button("Move to Trash", role: .destructive) { Task { await model.trashSelected() } }
        }
    }
}
