import SwiftUI

struct CleanupView: View {
    @EnvironmentObject private var model: CleanupModel
    @State private var confirmClean = false
    @State private var dismissedResult = false

    var body: some View {
        VStack(spacing: 0) {
            PageHeader(section: .cleanup, subtitle: subtitle, isActive: model.isBusy) {
                HStack {
                    if model.isScanning || model.isCleaning { ProgressView().controlSize(.small) }
                    Button(model.hasScanned ? "Rescan" : "Scan") { Task { await model.scan() } }
                        .disabled(model.isBusy)
                    Button("Clean \(Fmt.bytes(model.selectedSize))") { confirmClean = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(model.isBusy || model.selectedSize == 0)
                }
                .controlSize(.large)
            }

            if let result = model.lastResult, !dismissedResult {
                StatusBanner(text: resultText(result), isError: !result.failures.isEmpty) { dismissedResult = true }
            }
            if model.needsFullDiskAccess { FullDiskAccessHint() }

            if !model.hasScanned && !model.isScanning {
                EmptyStateView(
                    icon: "trash",
                    title: "Find system junk",
                    message: "Scans caches, logs, Xcode and developer leftovers, old installers, Mail attachments and the Trash. Nothing is removed until you review it.",
                    actionTitle: "Scan",
                    tint: Palette.network
                ) { Task { await model.scan() } }
            } else {
                List {
                    ForEach($model.categories) { $category in
                        CategoryRow(category: $category)
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .task {
            if LaunchOptions.autoScan && LaunchOptions.section == .cleanup && !model.hasScanned { await model.scan() }
        }
        .confirmationDialog("Clean \(Fmt.bytes(model.selectedSize))?", isPresented: $confirmClean) {
            Button("Clean", role: .destructive) {
                dismissedResult = false
                Task { await model.clean() }
            }
        } message: {
            Text("Caches, logs and developer caches are deleted (apps rebuild them). Installers and Mail attachments are moved to the Trash. Emptying the Trash is permanent.")
        }
    }

    private var subtitle: String {
        if model.isScanning { return "Scanning…" }
        if model.hasScanned { return "\(Fmt.bytes(model.totalSize)) found, \(Fmt.bytes(model.selectedSize)) selected" }
        return "Caches, logs and leftovers you don't need"
    }

    private func resultText(_ result: CleanupResult) -> String {
        var text = "Removed \(Fmt.bytes(result.deleted))"
        if result.trashed > 0 { text += ", moved \(Fmt.bytes(result.trashed)) to the Trash" }
        if !result.failures.isEmpty {
            text += ". \(result.failures.count) items couldn't be removed (in use or protected): "
                + result.failures.prefix(3).joined(separator: "; ")
        }
        return text
    }
}

private struct CategoryRow: View {
    @Binding var category: JunkCategory
    @State private var isExpanded = true

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            if let error = category.errorMessage {
                Text(error).font(.callout).foregroundStyle(.orange)
            }
            ForEach($category.items) { $item in
                HStack(spacing: 10) {
                    Toggle("", isOn: $item.selected).labelsHidden().toggleStyle(.checkbox)
                    Image(nsImage: IconCache.icon(for: item.url)).resizable().frame(width: 18, height: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(item.name).lineLimit(1).truncationMode(.middle)
                        if let note = item.note {
                            Text(note).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    Text(Fmt.bytes(item.size)).monospacedDigit().foregroundStyle(.secondary)
                    ExplainButton(url: item.url, size: item.size, category: category.title)
                    Button { item.url.revealInFinder() } label: { Image(systemName: "magnifyingglass") }
                        .buttonStyle(.borderless)
                        .help("Show in Finder")
                }
                .padding(.vertical, 2)
            }
        } label: {
            HStack(spacing: 12) {
                Toggle("", isOn: allSelected).labelsHidden().toggleStyle(.checkbox)
                    .disabled(category.items.isEmpty)
                Image(systemName: category.icon)
                    .font(.title3)
                    .foregroundStyle(Palette.network)
                    .symbolEffect(.pulse, isActive: category.isScanning)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.title).font(.headline)
                    Text(category.subtitle).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if category.isScanning {
                    ProgressView().controlSize(.small)
                } else if category.needsFullDiskAccess {
                    Label("Needs access", systemImage: "lock").font(.caption).foregroundStyle(.orange)
                } else {
                    VStack(alignment: .trailing, spacing: 2) {
                        LiveValue(text: Fmt.bytes(category.selectedSize), value: Double(category.selectedSize), size: 15, weight: .bold)
                        Text("\(category.items.count) items · \(Fmt.bytes(category.totalSize)) total")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.vertical, 6)
        }
    }

    private var allSelected: Binding<Bool> {
        Binding(
            get: { !category.items.isEmpty && category.items.allSatisfy(\.selected) },
            set: { value in
                for index in category.items.indices { category.items[index].selected = value }
            }
        )
    }
}
