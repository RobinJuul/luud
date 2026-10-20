import AppKit
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

struct Explanation: Equatable {
    enum Verdict: String {
        case safe = "Safe to delete"
        case caution = "Check first"
        case keep = "Keep"
    }

    let text: String
    let verdict: Verdict?
}

enum ExplainerState: Equatable {
    case idle
    case thinking
    case done(Explanation)
    case failed(String)
}

/// Facts about a file or folder, gathered locally and handed to the on-device model.
/// The model only sees this summary; file contents never leave Luud.
struct ItemFacts: Sendable {
    let path: String
    let kind: String
    let size: Int64
    let modified: Date?
    let lastOpened: Date?
    let sampleContents: [String]
    let relatedApp: String?
    /// nil when no bundle identifier appears in the path.
    let appInstalled: Bool?
    let category: String?

    static func gather(url: URL, size: Int64, category: String?) -> ItemFacts {
        let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isPackageKey, .contentModificationDateKey,
                                                       .contentAccessDateKey, .localizedTypeDescriptionKey])
        let isFolder = values?.isDirectory == true && values?.isPackage != true
        let app = relatedApp(for: url)
        let contents = isFolder
            ? ((try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []).filter { !$0.hasPrefix(".") }.sorted().prefix(12).map { $0 }
            : []

        return ItemFacts(
            path: Fmt.abbreviatePath(url),
            kind: isFolder ? "folder" : (values?.localizedTypeDescription ?? "file"),
            size: size,
            modified: values?.contentModificationDate,
            lastOpened: values?.contentAccessDate,
            sampleContents: contents,
            relatedApp: app?.description,
            appInstalled: app?.installed,
            category: category
        )
    }

    /// Looks for a bundle identifier in the path and reports whether that app is installed or running.
    private static func relatedApp(for url: URL) -> (description: String, installed: Bool)? {
        let pattern = try! NSRegularExpression(pattern: "^[A-Za-z0-9-]+(\\.[A-Za-z0-9_-]+){2,}$")
        for component in url.pathComponents.reversed() {
            var id = component
            for suffix in [".plist", ".savedState", ".binarycookies"] where id.hasSuffix(suffix) {
                id = String(id.dropLast(suffix.count))
            }
            // Group Containers are prefixed with a team ID: S8EX82NJP6.com.vendor.app
            if let first = id.split(separator: ".").first, first.count == 10, first.uppercased() == first {
                id = String(id.dropFirst(first.count + 1))
            }
            let range = NSRange(id.startIndex..., in: id)
            guard pattern.firstMatch(in: id, range: range) != nil else { continue }
            if let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) {
                let name = appURL.deletingPathExtension().lastPathComponent
                let running = !NSRunningApplication.runningApplications(withBundleIdentifier: id).isEmpty
                return ("belongs to \(name), which IS installed\(running ? " and running right now" : "")", true)
            }
            return ("belongs to \(id), which is NOT installed on this Mac (a leftover)", false)
        }
        return nil
    }

    private enum Kind { case regenerable, slowToRegenerate, appData, personal, other }

    private static let locations: [(marker: String, meaning: String, kind: Kind)] = [
        ("/Library/Caches/", "a cache folder; it holds only temporary copies, not settings, and apps rebuild it automatically", .regenerable),
        ("/Library/Logs/", "log files; only used for troubleshooting", .regenerable),
        ("/Saved Application State/", "remembered window positions; harmless to delete", .regenerable),
        ("/Xcode/DerivedData/", "Xcode build output; rebuilt on the next build", .regenerable),
        ("/.npm/", "npm package cache; re-downloaded when needed", .regenerable),
        ("/.gradle/", "Gradle build cache; re-downloaded on the next build", .regenerable),
        ("/.m2/", "libraries Maven downloaded; if deleted, Maven downloads them again by itself on the next build, so nothing breaks, it just takes a while", .slowToRegenerate),
        ("/Group Containers/", "data an app shares with its extensions: settings, databases, sign-ins; not a cache", .appData),
        ("/Library/Containers/", "a sandboxed app's whole data folder: its settings, documents and caches", .appData),
        ("/Application Support/", "an app's own data and settings", .appData),
        ("/Library/Preferences/", "an app's settings file", .appData),
        ("/Documents/", "the person's own document", .personal),
        ("/Desktop/", "the person's own file", .personal),
        ("/Downloads/", "a file the person downloaded", .other),
    ]

    private var location: (marker: String, meaning: String, kind: Kind)? {
        let full = (path as NSString).expandingTildeInPath + "/"
        return Self.locations.first { full.contains($0.marker) }
    }

    /// What the location means on macOS. Decided here, not by the model, because it's a fixed convention.
    var locationMeaning: String? { location?.meaning }

    /// Luud's own verdict when location and app status settle it; nil leaves the call to the model.
    var ruleVerdict: (verdict: Explanation.Verdict, reason: String)? {
        switch location?.kind {
        case .regenerable?:
            return (.safe, "it is rebuilt or re-downloaded automatically")
        case .slowToRegenerate?:
            return (.caution, "it comes back on its own, but re-downloading takes a while")
        case .appData?:
            if appInstalled == false { return (.safe, "the app it belongs to is no longer installed") }
            if appInstalled == true { return (.caution, "an installed app keeps its settings or data here") }
            return nil
        case .personal?:
            return (.keep, "it is the person's own file")
        case .other?, nil:
            if appInstalled == false { return (.safe, "the app it belongs to is no longer installed") }
            return nil
        }
    }

    var prompt: String {
        var lines = ["Item: \(path) (\(kind), \(Fmt.bytes(size)))"]
        if let locationMeaning { lines.append("Location means: \(locationMeaning)") }
        if let relatedApp { lines.append("Owning app: \(relatedApp)") }
        if let category { lines.append("Listed by Luud under: \(category)") }
        if let rule = ruleVerdict {
            lines.append("Luud's verdict: \(rule.verdict.rawValue), because \(rule.reason). Your explanation must agree with this.")
        }
        if let modified { lines.append("Last modified: \(Fmt.relativeDate(modified))") }
        if let lastOpened { lines.append("Last opened: \(Fmt.relativeDate(lastOpened))") }
        if !sampleContents.isEmpty { lines.append("Contains: \(sampleContents.joined(separator: ", "))") }
        return lines.joined(separator: "\n")
    }
}

#if canImport(FoundationModels)
/// Structured answer schema, built at runtime (the @Generable macro needs full Xcode).
/// Reasoning fields come before the verdict so the verdict follows from them.
@available(macOS 26.0, *)
enum AssessmentSchema {
    private static let text = DynamicGenerationSchema(type: String.self)
    private static let explanation: [DynamicGenerationSchema.Property] = [
        .init(name: "whatItIs",
              description: "What the item is, in one plain sentence. Use the 'Location means' fact.",
              schema: text),
        .init(name: "ifDeleted",
              description: "What happens if it is deleted, in one or two plain sentences. Only state consequences that follow from the facts.",
              schema: text),
    ]

    /// Used when Luud's rules already decided the verdict.
    static let explainOnly = try! GenerationSchema(
        root: DynamicGenerationSchema(name: "ItemExplanation", properties: explanation), dependencies: [])

    /// Used for locations the rules don't cover; the model chooses the verdict after explaining.
    static let withVerdict = try! GenerationSchema(
        root: DynamicGenerationSchema(name: "ItemAssessment", properties: explanation + [
            .init(name: "verdict",
                  description: "safe: rebuilt or re-downloaded automatically, or belongs to an app that is NOT installed. caution: deleting resets settings, signs out, or is slow to recover. keep: the person's own files, or data an installed app needs.",
                  schema: DynamicGenerationSchema(name: "Verdict", anyOf: ["safe", "caution", "keep"])),
        ]),
        dependencies: [])
}
#endif

enum ItemExplainer {
    /// Whether this build includes Foundation Models (macOS 26 SDK or newer).
    static var isCompiledIn: Bool {
        #if canImport(FoundationModels)
        return true
        #else
        return false
        #endif
    }

    /// Nil when the model is ready; otherwise a sentence saying what to do.
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { return "Needs macOS 26 or later." }
        switch SystemLanguageModel.default.availability {
        case .available:
            return nil
        case .unavailable(.appleIntelligenceNotEnabled):
            return "Turn on Apple Intelligence in System Settings to get explanations."
        case .unavailable(.modelNotReady):
            return "Apple Intelligence is still downloading its model. Try again in a few minutes."
        case .unavailable(.deviceNotEligible):
            return "This Mac doesn't support Apple Intelligence."
        case .unavailable:
            return "Apple Intelligence isn't available right now."
        }
        #else
        return "This copy of Luud was built without Apple Intelligence support."
        #endif
    }

    /// True when Apple Intelligence just needs turning on or finishing its download,
    /// so pointing the person at System Settings will fix it.
    static var canBeTurnedOn: Bool {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *) else { return false }
        switch SystemLanguageModel.default.availability {
        case .unavailable(.appleIntelligenceNotEnabled), .unavailable(.modelNotReady): return true
        default: return false
        }
        #else
        return false
        #endif
    }

    static func explain(_ facts: ItemFacts) async throws -> Explanation {
        #if canImport(FoundationModels)
        guard #available(macOS 26.0, *), unavailableReason == nil else { throw ExplainerError.unavailable }
        let session = LanguageModelSession(instructions: """
            You help someone tidy up their Mac. You are given facts about one file or folder. \
            Explain it in plain language for a non-expert. Treat the facts as true, especially \
            'Location means' and 'Owning app'. Don't guess beyond them; if they don't tell you what \
            the item is, say so.
            """)
        let rule = facts.ruleVerdict
        let response = try await session.respond(
            to: facts.prompt,
            schema: rule == nil ? AssessmentSchema.withVerdict : AssessmentSchema.explainOnly,
            options: GenerationOptions(sampling: .greedy)
        )
        let content = response.content
        let whatItIs = try content.value(String.self, forProperty: "whatItIs")
        let ifDeleted = try content.value(String.self, forProperty: "ifDeleted")
        let verdict: Explanation.Verdict
        if let rule {
            verdict = rule.verdict
        } else {
            switch try content.value(String.self, forProperty: "verdict") {
            case "safe": verdict = .safe
            case "keep": verdict = .keep
            default: verdict = .caution
            }
        }
        return Explanation(text: "\(whatItIs) \(ifDeleted)", verdict: verdict)
        #else
        throw ExplainerError.unavailable
        #endif
    }
}

enum ExplainerError: LocalizedError {
    case unavailable
    var errorDescription: String? { ItemExplainer.unavailableReason ?? "Apple Intelligence isn't available." }
}
