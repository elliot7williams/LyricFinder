import SwiftUI

/// One lyric line with karaoke highlighting. Tap seeks to the line.
struct LyricRowView: View {
    var line: LyricLine
    var isActive: Bool
    var currentTime: Double
    var onTap: () -> Void
    var large: Bool = false

    var body: some View {
        Button(action: onTap) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    if let words = line.words, !words.isEmpty, isActive {
                        karaokeText(words: words)
                    } else {
                        Text(line.text)
                            .font(large ? .title3.weight(isActive ? .bold : .regular) : .body.weight(isActive ? .semibold : .regular))
                            .foregroundStyle(isActive ? .primary : .secondary)
                    }
                    Text(line.startTime.preciseTimeString)
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                if isActive {
                    Image(systemName: "waveform")
                        .foregroundStyle(.tint)
                        .symbolEffect(.pulse)
                }
            }
            .padding(.vertical, large ? 10 : 6)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(isActive ? Color.accentColor.opacity(0.15) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func karaokeText(words: [WordTimestamp]) -> some View {
        // iOS 17+: Text concatenation preserves per-word styling.
        words.enumerated().reduce(Text("")) { acc, pair in
            let (i, w) = pair
            let sung = currentTime >= w.endTime
            let active = w.isActive(at: currentTime)
            let styled = Text(w.word + (i == words.count - 1 ? "" : " "))
                .foregroundStyle(active ? Color.accentColor : (sung ? .primary : .secondary))
                .fontWeight(active ? .bold : (sung ? .semibold : .regular))
            return acc + styled
        }
        .font(large ? .title3 : .body)
    }
}
