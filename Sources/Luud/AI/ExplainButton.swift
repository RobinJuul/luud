import SwiftUI

/// A sparkles button that asks Apple Intelligence what an item is and whether it's safe to delete.
/// Hidden entirely when this build has no Foundation Models support.
struct ExplainButton: View {
    let url: URL
    let size: Int64
    var category: String?

    @State private var isPresented = false
    @State private var state: ExplainerState = .idle

    var body: some View {
        if ItemExplainer.isCompiledIn {
            Button {
                isPresented = true
                if case .done = state { return }
                run()
            } label: {
                Label("Explain", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .foregroundStyle(Palette.brandPink)
                    .background(Palette.brandPink.opacity(0.14), in: Capsule())
                    .contentShape(Capsule())
            }
            .buttonStyle(.plain)
            .fixedSize()
            .help("Ask Apple Intelligence what this is and whether it's safe to delete")
            .popover(isPresented: $isPresented, arrowEdge: .trailing) {
                ExplanationCard(name: url.lastPathComponent, state: state, retry: run)
            }
        }
    }

    private func run() {
        if let reason = ItemExplainer.unavailableReason {
            state = .failed(reason)
            return
        }
        state = .thinking
        let url = url, size = size, category = category
        Task {
            let facts = await Task.detached { ItemFacts.gather(url: url, size: size, category: category) }.value
            do {
                state = .done(try await ItemExplainer.explain(facts))
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }
}

private struct ExplanationCard: View {
    let name: String
    let state: ExplainerState
    let retry: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(Palette.brandGradient)
                    .symbolEffect(.pulse, isActive: state == .thinking)
                Text(name).font(.headline).lineLimit(1).truncationMode(.middle)
            }

            switch state {
            case .idle, .thinking:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Thinking on-device…").foregroundStyle(.secondary)
                }
            case .done(let explanation):
                Text(explanation.text)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                if let verdict = explanation.verdict {
                    Label(verdict.rawValue, systemImage: verdict.symbol)
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(verdict.color)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(verdict.color.opacity(0.14), in: Capsule())
                }
                Text("Generated on this Mac by Apple Intelligence. It can be wrong; Luud's own rules decide what's ticked.")
                    .font(.caption).foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            case .failed(let message):
                Text(message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                HStack {
                    if ItemExplainer.canBeTurnedOn {
                        Button("Open Apple Intelligence Settings") { SystemSettings.openAppleIntelligence() }
                            .buttonStyle(.borderedProminent)
                    }
                    Button("Try Again", action: retry)
                }
            }
        }
        .padding(Corner.panelPadding)
        .frame(width: 320, alignment: .leading)
        .animation(.easeOut(duration: 0.2), value: state)
    }
}

private extension Explanation.Verdict {
    var color: Color {
        switch self {
        case .safe: Palette.network
        case .caution: Palette.disk
        case .keep: Palette.danger
        }
    }

    var symbol: String {
        switch self {
        case .safe: "checkmark.circle.fill"
        case .caution: "exclamationmark.triangle.fill"
        case .keep: "hand.raised.fill"
        }
    }
}
