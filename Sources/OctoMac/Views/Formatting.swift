import OctoPrintKit
import Foundation
import SwiftUI

enum Fmt {
    static func duration(_ seconds: Double?) -> String {
        guard let seconds, seconds.isFinite, seconds >= 0 else { return "–" }
        // Numbers, units and separators all follow the app's language.
        if seconds < 60 { return Duration.seconds(seconds.rounded(.down)).formatted(.units(allowed: [.seconds], width: .narrow)) }
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
        return (value / 100).formatted(.percent.precision(.fractionLength(1)))
    }

    /// A reading to one decimal place, in the chosen unit: "214.7°".
    static func temp(_ celsius: Double?) -> String {
        guard let celsius else { return "–" }
        return TemperatureUnit.current.convert(celsius).formatted(.number.precision(.fractionLength(1))) + "°"
    }

    /// A whole-degree temperature in the chosen unit: "215°".
    static func deg(_ celsius: Double?) -> String {
        guard let celsius else { return "–" }
        return "\(degNumber(celsius))°"
    }

    /// Just the number, for layouts that show the unit separately.
    static func degNumber(_ celsius: Double?) -> String {
        guard let celsius else { return "–" }
        return TemperatureUnit.current.convert(celsius).formatted(.number.precision(.fractionLength(0)).grouping(.never))
    }

    static func bytes(_ value: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(value), countStyle: .file)
    }

    /// Filament length in mm → "12.34 m".
    static func filament(_ mm: Double?) -> String {
        guard let mm, mm > 0 else { return "–" }
        return (mm / 1000).formatted(.number.precision(.fractionLength(2))) + " m"
    }

    static func source(_ source: PrintTimeSource) -> String {
        switch source {
        case .printTimeGenius: "Print Time Genius"
        case .octoPrint: String(localized: "OctoPrint's estimate")
        case .pastPrints: String(localized: "from earlier prints")
        }
    }

    /// A number with a fixed number of decimals, written the way the app's language writes them ("9,12" in German).
    static func decimal(_ value: Double, _ digits: Int) -> String {
        value.formatted(.number.precision(.fractionLength(digits)))
    }

    static func number(_ value: Double?) -> String {
        guard let value else { return "?" }
        return value.formatted(.number.precision(.fractionLength(0...1)))
    }
}

/// How temperatures are shown. OctoPrint and printers always work in Celsius; only the display changes.
enum TemperatureUnit: String, CaseIterable, Identifiable {
    case celsius, fahrenheit

    static let defaultsKey = "temperature.unit"
    static var current: TemperatureUnit {
        UserDefaults.standard.string(forKey: defaultsKey).flatMap(TemperatureUnit.init(rawValue:)) ?? .celsius
    }

    var id: String { rawValue }
    var symbol: String { self == .celsius ? "°C" : "°F" }
    var title: LocalizedStringKey { self == .celsius ? "Celsius" : "Fahrenheit" }

    func convert(_ celsius: Double) -> Double { self == .celsius ? celsius : celsius * 9 / 5 + 32 }
}
