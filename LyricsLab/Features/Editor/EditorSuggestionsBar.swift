import SwiftUI

struct EditorSuggestionsBar: View {
    var suggestions: [String]
    var onInsert: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    if suggestions.isEmpty {
                        Text("No suggestions")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                    } else {
                        ForEach(suggestions, id: \ .self) { word in
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

struct EditorSuggestionsBar_Previews: PreviewProvider {
    static var previews: some View {
        EditorSuggestionsBar(suggestions: ["time", "rhyme", "shine", "line"]) { _ in }
            .previewLayout(.sizeThatFits)
    }
}
