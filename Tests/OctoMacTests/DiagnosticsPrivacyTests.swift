import Foundation
import Testing
@testable import OctoMac

/// Bug reports go on public GitHub issues, so the diagnostics must never include anything personal.
/// This builds printers full of recognisable private details and checks none of them reach the report.
@MainActor
struct DiagnosticsPrivacyTests {
    private let secrets = [
        "Secret Garage Printer",          // printer name
        "secret-host.example",            // address
        "192.168.77.42",                  // address
        "SECRETAPIKEY0123456789ABCDEF",   // API key
        "c0ffee",                         // trusted certificate fingerprint
        "maker",                          // OctoPrint user (set by the demo data)
        "gridfinity",                     // file names (from the demo data)
        "spool_holder",
        "pegboard",
    ]

    @Test func reportLeavesOutPersonalDetails() {
        var printing = Instance(name: "Secret Garage Printer", baseURL: URL(string: "https://secret-host.example:8443/octoprint/")!)
        printing.trustedCertificate = "c0ffee" + String(repeating: "ab", count: 29)
        let idle = Instance(name: "Secret Garage Printer 2", baseURL: URL(string: "http://192.168.77.42/")!)

        let first = PrinterSession(instance: printing, apiKey: "SECRETAPIKEY0123456789ABCDEF")
        first.loadDemo(.printing)
        let second = PrinterSession(instance: idle, apiKey: "SECRETAPIKEY0123456789ABCDEF")
        second.loadDemo(.ready)

        let report = Diagnostics.report(printers: [(printing, first), (idle, second)], isDemo: false, notifications: .authorized)

        // The report still says something useful...
        #expect(report.contains("Printer 1"))
        #expect(report.contains("OctoPrint 1.10.3"))
        // ...and nothing personal.
        for secret in secrets {
            #expect(!report.localizedCaseInsensitiveContains(secret), "The diagnostics contain \(secret)")
        }
    }
}
