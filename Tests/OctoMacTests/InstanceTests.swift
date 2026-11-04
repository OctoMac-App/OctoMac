import Foundation
import Testing
@testable import OctoMac

struct InstanceTests {
    /// Printer lists saved before the network ID was remembered still load.
    @Test func olderSavedPrintersLoad() throws {
        let json = #"[{"id":"6F9619FF-8B86-D011-B42D-00C04FC964FF","name":"Workshop","baseURL":"http://octopi.local/","pushThrottle":1}]"#
        let instances = try JSONDecoder().decode([Instance].self, from: Data(json.utf8))
        #expect(instances.first?.name == "Workshop")
        #expect(instances.first?.networkID == nil)
    }

    @Test func networkIDIsSaved() throws {
        var instance = Instance(name: "Workshop", baseURL: URL(string: "http://octopi.local/")!)
        instance.networkID = "bacdcb9b-0000-4000-8000-000000000000"
        let decoded = try JSONDecoder().decode(Instance.self, from: JSONEncoder().encode(instance))
        #expect(decoded.networkID == instance.networkID)
    }
}
