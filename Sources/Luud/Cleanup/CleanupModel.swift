import AppKit
import Foundation

struct JunkItem: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let size: Int64
    var selected: Bool
    var note: String?

    var name: String { url.lastPathComponent }
}

struct JunkCategory: Identifiable {
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let disposal: Disposal
    var items: [JunkItem] = []
    var isScanning = false
    var needsFullDiskAccess = false
    var errorMessage: String?

    var totalSize: Int64 { items.reduce(0) { $0 + $1.size } }
    var selectedSize: Int64 { items.reduce(0) { $0 + ($1.selected ? $1.size : 0) } }

    init(definition: JunkDefinition) {
        id = definition.id
        title = definition.title
        subtitle = definition.subtitle
        icon = definition.icon
        disposal = definition.disposal
    }
}

struct CleanupResult {
    var deleted: Int64 = 0
    var trashed: Int64 = 0
    var failures: [String] = []
}

@MainActor
final class CleanupModel: ObservableObject {
    @Published var categories: [JunkCategory] = JunkRules.all.map(JunkCategory.init)
    @Published private(set) var isScanning = false
    @Published private(set) var isCleaning = false
    @Published private(set) var hasScanned = false
    @Published private(set) var lastResult: CleanupResult?

    var totalSize: Int64 { categories.reduce(0) { $0 + $1.totalSize } }
    var selectedSize: Int64 { categories.reduce(0) { $0 + $1.selectedSize } }
    var needsFullDiskAccess: Bool { categories.contains { $0.needsFullDiskAccess } }
    var isBusy: Bool { isScanning || isCleaning }

    func scan() async {
        guard !isBusy else { return }
        isScanning = true
        lastResult = nil
        let context = JunkContext(
            runningBundleIDs: Set(NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier))
        )
        let definitions = JunkRules.all
        categories = definitions.map {
            var category = JunkCategory(definition: $0)
            category.isScanning = true
            return category
        }

        await withTaskGroup(of: (Int, JunkCategory).self) { group in
            for (index, definition) in definitions.enumerated() {
                group.addTask { (index, Self.scanCategory(definition, context: context)) }
            }
            for await (index, category) in group {
                categories[index] = category
            }
        }
        isScanning = false
        hasScanned = true
    }

    nonisolated private static func scanCategory(_ definition: JunkDefinition, context: JunkContext) -> JunkCategory {
        var category = JunkCategory(definition: definition)
        do {
            category.items = try definition.candidates(context)
                .map { JunkItem(url: $0.url, size: FileSizer.size(of: $0.url), selected: $0.selected, note: $0.note) }
                .filter { $0.size > 0 }
                .sorted { $0.size > $1.size }
        } catch {
            if FileSizer.isPermissionError(error) {
                category.needsFullDiskAccess = true
                category.errorMessage = "Luud needs Full Disk Access to look here."
            } else {
                category.errorMessage = error.localizedDescription
            }
        }
        return category
    }

    func clean() async {
        guard !isBusy else { return }
        isCleaning = true
        let work = categories.flatMap { category in
            category.items.filter(\.selected).map { (url: $0.url, size: $0.size, disposal: category.disposal) }
        }

        let result = await Task.detached { () -> CleanupResult in
            var result = CleanupResult()
            let fileManager = FileManager.default
            for item in work {
                do {
                    switch item.disposal {
                    case .delete:
                        try fileManager.removeItem(at: item.url)
                        result.deleted += item.size
                    case .moveToTrash:
                        try fileManager.trashItem(at: item.url, resultingItemURL: nil)
                        result.trashed += item.size
                    }
                } catch {
                    result.failures.append("\(item.url.lastPathComponent): \(error.localizedDescription)")
                }
            }
            return result
        }.value

        let removed = Set(work.map(\.url))
        for index in categories.indices {
            categories[index].items.removeAll { removed.contains($0.url) && !FileManager.default.fileExists(atPath: $0.url.path) }
        }
        lastResult = result
        isCleaning = false
    }

    func setAll(_ selected: Bool) {
        for c in categories.indices {
            for i in categories[c].items.indices { categories[c].items[i].selected = selected }
        }
    }
}
