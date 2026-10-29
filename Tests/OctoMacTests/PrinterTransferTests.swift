import Foundation
import Testing
@testable import OctoMac

struct PrinterTransferTests {
    let workshop = Instance(name: "Workshop", baseURL: URL(string: "http://octopi-workshop.local/")!, pushThrottle: 2,
                            filamentHex: "#8F7CFF", trustedCertificate: "AB:CD")
    let studio = Instance(name: "Studio", baseURL: URL(string: "https://studio.example/octoprint/")!, filamentHex: "#5CCB66")

    @Test func roundTripsWithoutSecrets() throws {
        let data = try PrinterList([workshop, studio]).data()
        let text = String(decoding: data, as: UTF8.self)
        // Nothing that could be a key or a sign-in, and not even OctoMac's own IDs.
        for word in ["apiKey", "api_key", "password", "header", workshop.id.uuidString] {
            #expect(!text.localizedCaseInsensitiveContains(word))
        }
        let list = try PrinterList.read(data)
        #expect(list.printers.map(\.name) == ["Workshop", "Studio"])
        #expect(list.printers.first?.pushThrottle == 2)
        #expect(list.printers.last?.pushThrottle == nil)
    }

    @Test func addsOnlyPrintersThatAreNew() throws {
        let list = try PrinterList.read(PrinterList([workshop, studio]).data())
        let already = Instance(name: "Mine", baseURL: URL(string: "HTTP://octopi-workshop.local/")!)
        let added = list.newInstances(alongside: [already])
        #expect(added.map(\.name) == ["Studio"])
        #expect(added.first?.filamentHex == "#5CCB66")
        #expect(added.first?.id != studio.id)
    }

    @Test func refusesOtherFiles() {
        #expect(throws: (any Error).self) { try PrinterList.read(Data(#"{"app": "Something", "version": 1, "printers": []}"#.utf8)) }
        #expect(throws: (any Error).self) { try PrinterList.read(Data("not json".utf8)) }
    }
}
