import Foundation

/// Whisper model sizes. Larger = more accurate, slower, more memory.
enum WhisperModelType: String, CaseIterable, Identifiable, Codable {
    case tiny
    case base
    case small
    case medium
    case large
    case turbo

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny: return "Tiny"
        case .base: return "Base"
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        case .turbo: return "Turbo"
        }
    }

    /// Approximate download size for UI display.
    var approxSize: String {
        switch self {
        case .tiny: return "~75 MB"
        case .base: return "~145 MB"
        case .small: return "~465 MB"
        case .medium: return "~1.5 GB"
        case .large: return "~2.9 GB"
        case .turbo: return "~1.6 GB"
        }
    }

    var speedNote: String {
        switch self {
        case .tiny: return "Fastest · lowest accuracy"
        case .base: return "Fast · good for drafts"
        case .small: return "Balanced (recommended)"
        case .medium: return "Slow · high accuracy"
        case .large: return "Slowest · best accuracy"
        case .turbo: return "Fast · near-large accuracy"
        }
    }

    /// Rough peak memory so UI can warn on large models.
    var peakMemoryMB: Int {
        switch self {
        case .tiny: return 300
        case .base: return 500
        case .small: return 1_000
        case .medium: return 2_500
        case .large: return 4_000
        case .turbo: return 2_000
        }
    }

    var isRecommendedForIPhone: Bool {
        self == .tiny || self == .base || self == .small || self == .turbo
    }

    /// WhisperKit model identifier slug.
    /// Verified against the argmaxinc/whisperkit-coreml repo: each slug below
    /// resolves to exactly one model folder via WhisperKit's lookup.
    var whisperKitModelSlug: String {
        switch self {
        case .tiny: return "openai_whisper-tiny"
        case .base: return "openai_whisper-base"
        case .small: return "openai_whisper-small"
        case .medium: return "openai_whisper-medium"
        case .large: return "openai_whisper-large-v3"
        case .turbo: return "openai_whisper-large-v3_turbo"
        }
    }
}
