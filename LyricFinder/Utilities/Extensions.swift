import Foundation

extension Double {
    /// m:ss for compact display.
    var compactTimeString: String {
        guard isFinite else { return "0:00" }
        let total = max(0, Int(self))
        return "\(total / 60):\(String(format: "%02d", total % 60))"
    }

    /// m:ss.t for editor precision.
    var preciseTimeString: String {
        guard isFinite else { return "0:00.0" }
        let m = Int(self / 60)
        let s = self.truncatingRemainder(dividingBy: 60)
        return String(format: "%d:%04.1f", m, s)
    }
}

extension Int64 {
    var fileSizeString: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
