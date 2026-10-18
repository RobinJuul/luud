import AppKit
import Foundation

struct SizedNode: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let size: Int64
    let isFolder: Bool

    var name: String { url.lastPathComponent }
}

/// Drill-down disk usage map, like CleanMyMac's Space Lens.
@MainActor
final class SpaceLensModel: ObservableObject {
    @Published private(set) var path: [URL] = [FileManager.default.homeDirectoryForCurrentUser]
    @Published private(set) var nodes: [SizedNode] = []
    @Published private(set) var isLoading = false
    @Published private(set) var pending = 0

    private var sizeCache: [URL: Int64] = [:]
    private var loadTask: Task<Void, Never>?

    var current: URL { path.last! }
    var total: Int64 { nodes.reduce(0) { $0 + $1.size } }

    func start(at root: URL) {
        path = [root]
        reload()
    }

    func open(_ node: SizedNode) {
        guard node.isFolder else { return }
        path.append(node.url)
        reload()
    }

    func goTo(index: Int) {
        guard path.indices.contains(index), index != path.count - 1 else { return }
        path = Array(path.prefix(index + 1))
        reload()
    }

    func reload() {
        loadTask?.cancel()
        let folder = current
        nodes = []
        isLoading = true
        loadTask = Task { await load(folder) }
    }

    func trash(_ node: SizedNode) async -> Bool {
        do {
            _ = try await NSWorkspace.shared.moveToTrash([node.url])
            nodes.removeAll { $0.id == node.id }
            sizeCache[node.url] = nil
            for ancestor in path { sizeCache[ancestor] = nil }
            return true
        } catch {
            return false
        }
    }

    private func load(_ folder: URL) async {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey, .isPackageKey]
        let children = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys)) ?? []
        pending = children.count
        let cache = sizeCache

        await withTaskGroup(of: SizedNode.self) { group in
            for child in children {
                group.addTask {
                    let values = try? child.resourceValues(forKeys: Set(keys))
                    let isFolder = values?.isDirectory == true && values?.isPackage != true && values?.isSymbolicLink != true
                    let size = cache[child] ?? FileSizer.size(of: child)
                    return SizedNode(url: child, size: size, isFolder: isFolder)
                }
            }
            for await node in group {
                guard !Task.isCancelled else { break }
                sizeCache[node.url] = node.size
                pending -= 1
                if node.size > 0 {
                    let index = nodes.firstIndex { $0.size < node.size } ?? nodes.count
                    nodes.insert(node, at: index)
                }
            }
        }
        if !Task.isCancelled {
            isLoading = false
            pending = 0
        }
    }
}

struct LargeFile: Identifiable, Hashable {
    var id: URL { url }
    let url: URL
    let size: Int64
    let lastOpened: Date?
    var selected = false

    var name: String { url.lastPathComponent }
}

@MainActor
final class LargeFilesModel: ObservableObject {
    @Published var files: [LargeFile] = []
    @Published var thresholdMB = 500
    @Published private(set) var isScanning = false
    @Published private(set) var scannedCount = 0
    @Published private(set) var hasScanned = false
    @Published var message: String?

    private var scanTask: Task<Void, Never>?

    var selectedSize: Int64 { files.filter(\.selected).reduce(0) { $0 + $1.size } }

    func scan() {
        scanTask?.cancel()
        files = []
        scannedCount = 0
        isScanning = true
        message = nil
        let threshold = Int64(thresholdMB) * 1_000_000
        scanTask = Task {
            let worker = Task.detached { [weak self] in
                LargeFilesModel.findLargeFiles(threshold: threshold) { count in
                    Task { @MainActor in self?.scannedCount = count }
                }
            }
            let found = await withTaskCancellationHandler {
                await worker.value
            } onCancel: {
                worker.cancel()
            }
            guard !Task.isCancelled else { return }
            files = found
            isScanning = false
            hasScanned = true
        }
    }

    func cancel() {
        scanTask?.cancel()
        isScanning = false
    }

    func trashSelected() async {
        let urls = files.filter(\.selected).map(\.url)
        guard !urls.isEmpty else { return }
        let moved = Set(((try? await NSWorkspace.shared.moveToTrash(urls)) ?? [:]).keys)
        let freed = files.filter { moved.contains($0.url) }.reduce(0) { $0 + $1.size }
        files.removeAll { moved.contains($0.url) }
        message = "Moved \(moved.count) files to the Trash (\(Fmt.bytes(freed)))."
    }

    nonisolated static func findLargeFiles(threshold: Int64, progress: @escaping (Int) -> Void) -> [LargeFile] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let keys: [URLResourceKey] = [.isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentAccessDateKey]
        guard let enumerator = FileManager.default.enumerator(
            at: home,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants],
            errorHandler: { _, _ in true }
        ) else { return [] }

        let skipped: Set<String> = [home.appendingPathComponent("Library/Caches").path, home.appendingPathComponent(".Trash").path]
        var results: [LargeFile] = []
        var count = 0
        while let url = enumerator.nextObject() as? URL {
            count += 1
            if count % 2_000 == 0 {
                if Task.isCancelled { break }
                progress(count)
            }
            if skipped.contains(url.path) {
                enumerator.skipDescendants()
                continue
            }
            guard let values = try? url.resourceValues(forKeys: Set(keys)), values.isRegularFile == true else { continue }
            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            if size >= threshold {
                results.append(LargeFile(url: url, size: size, lastOpened: values.contentAccessDate))
            }
        }
        progress(count)
        return results.sorted { $0.size > $1.size }
    }
}
