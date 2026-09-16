import SwiftUI
import AVFoundation

/// Downsamples audio peaks off the main thread for the timeline view.
enum WaveformGenerator {
    static func peaks(for url: URL, targetCount: Int = 120) async -> [Float] {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .utility).async {
                cont.resume(returning: syncPeaks(for: url, targetCount: targetCount))
            }
        }
    }

    private static func syncPeaks(for url: URL, targetCount: Int) -> [Float] {
        do {
            let file = try AVAudioFile(forReading: url)
            let format = file.processingFormat
            let totalFrames = AVAudioFrameCount(file.length)
            guard totalFrames > 0 else { return [] }
            let chunk = max(1, totalFrames / AVAudioFrameCount(targetCount))
            let framesPerChunk = min(chunk, 8192)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: framesPerChunk) else { return [] }
            var peaks: [Float] = []
            peaks.reserveCapacity(targetCount)
            var framesRead: AVAudioFrameCount = 0
            var accumulator: Float = 0
            var accCount = 0
            let chunksPerBar = max(1, Int(chunk / framesPerChunk))
            var chunkIndex = 0
            while file.framePosition < totalFrames {
                try? file.read(into: buffer)
                guard buffer.frameLength > 0 else { break }
                var peak: Float = 0
                if let ch = buffer.floatChannelData {
                    let n = Int(buffer.frameLength)
                    let channels = Int(buffer.stride == 0 ? format.channelCount : min(format.channelCount, 2))
                    for c in 0..<max(1, channels) {
                        let ptr = ch[c]
                        for i in 0..<n {
                            let v = abs(ptr[i])
                            if v > peak { peak = v }
                        }
                    }
                }
                accumulator = max(accumulator, peak)
                accCount += 1
                if accCount >= chunksPerBar {
                    peaks.append(accumulator)
                    accumulator = 0
                    accCount = 0
                    chunkIndex += 1
                    if peaks.count >= targetCount { break }
                }
                framesRead += buffer.frameLength
                if framesRead > totalFrames { break }
            }
            if accCount > 0 && peaks.count < targetCount { peaks.append(accumulator) }
            return peaks
        } catch {
            return []
        }
    }
}

/// Playback timeline with waveform bars + scrubbing.
struct WaveformView: View {
    var peaks: [Float]
    var progress: Double  // 0...1
    var onScrub: (Double) -> Void

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                ForEach(peaks.indices, id: \.self) { i in
                    let h = max(3, CGFloat(peaks[i]) * geo.size.height)
                    let barCenter = Double(i) / Double(max(1, peaks.count))
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(barCenter <= progress ? Color.accentColor : Color.secondary.opacity(0.35))
                        .frame(height: h)
                        .frame(maxHeight: .infinity)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        let p = min(max(0, v.location.x / max(1, geo.size.width)), 1)
                        onScrub(p)
                    }
            )
            .animation(.easeOut(duration: 0.15), value: progress)
        }
    }
}
