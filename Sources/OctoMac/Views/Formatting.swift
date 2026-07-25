import Foundation

enum Fmt {
    static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "–" }
        if seconds < 60 { return "\(Int(seconds))s" }
        return Duration.seconds(seconds).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated, maximumUnitCount: 2))
    }

    static func eta(_ secondsLeft: Double?) -> String {
        guard let secondsLeft, secondsLeft.isFinite, secondsLeft >= 0 else { return "–" }
        let date = Date.now.addingTimeInterval(secondsLeft)
        let sameDay = Calendar.current.isDate(date, inSameDayAs: .now)
        return date.formatted(sameDay ? .dateTime.hour().minute() : .dateTime.weekday(.abbreviated).hour().minute())
    }

    static func percent(_ value: Double?) -> String {
        guard let value else { return "–" }
        return String(format: "%.1f%%", value)
    }

    static func temp(_ value: Double?) -> String {
        guard let value else { return "–" }
        return String(format: "%.1f°", value)
    }

    static func bytes(_ value: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    /// Filament length in mm → "12.34 m".
    static func filament(_ mm: Double?) -> String {
        guard let mm, mm > 0 else { return "–" }
        return String(format: "%.2f m", mm / 1000)
    }

    static func number(_ value: Double?) -> String {
        guard let value else { return "?" }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }
}
