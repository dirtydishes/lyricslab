import SwiftUI

struct EditorSuggestionsBar: View {
    var suggestions: [String]
    var isLoading: Bool = false
    var barPosition: BarPosition? = nil
    var onInsert: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()

            if let barPosition {
                BarRulerView(barPosition: barPosition)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    if suggestions.isEmpty {
                        HStack(spacing: 10) {
                            if isLoading {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(isLoading ? "Loading rhymes..." : "No suggestions")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                    } else {
                        ForEach(suggestions, id: \.self) { word in
                            Button {
                                onInsert(word)
                            } label: {
                                Text(word)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                                    .background(
                                        Capsule(style: .continuous)
                                            .fill(.ultraThinMaterial)
                                    )
                                    .overlay(
                                        Capsule(style: .continuous)
                                            .strokeBorder(.primary.opacity(0.12), lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
        }
        .background(.thinMaterial)
    }
}

private struct BarRulerView: View {
    var barPosition: BarPosition

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 4) {
                ForEach(0..<16, id: \.self) { idx in
                    Capsule(style: .continuous)
                        .fill(idx == barPosition.step ? Color.primary.opacity(0.70) : Color.primary.opacity(0.18))
                        .frame(width: 10, height: 4)
                }
            }

            Spacer(minLength: 6)

            Text("\(barPosition.syllablesBeforeCaret)/\(barPosition.totalSyllables)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)

            if barPosition.lowConfidenceTokenCount > 0 {
                Text("est")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Bar position")
        .accessibilityValue("Step \(barPosition.step + 1) of 16")
    }
}

struct EditorSuggestionsBar_Previews: PreviewProvider {
    static var previews: some View {
        EditorSuggestionsBar(
            suggestions: ["time", "rhyme", "shine", "line"],
            barPosition: BarPosition(step: 6, syllablesBeforeCaret: 7, totalSyllables: 15, lowConfidenceTokenCount: 1)
        ) { _ in }
            .previewLayout(.sizeThatFits)
    }
}
