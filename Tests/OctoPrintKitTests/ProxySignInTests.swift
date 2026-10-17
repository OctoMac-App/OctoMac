import Foundation
import Testing
@testable import OctoPrintKit

/// Reverse proxy sign-in: headers go to the printer's own host only, and proxy refusals get a clear error.
struct ProxySignInTests {
    private let client = OctoPrintClient(
        baseURL: URL(string: "https://printer.example.com/octoprint/")!, apiKey: "KEY",
        headers: ["Authorization": OctoPrintClient.basicAuthorization(user: "ada", password: "s3cret"), "CF-Access-Client-Id": "id"])

    @Test func requestsToThePrinterCarryTheSignIn() {
        let request = client.makeRequest(.get, "api/version")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Basic YWRhOnMzY3JldA==")
        #expect(request.value(forHTTPHeaderField: "CF-Access-Client-Id") == "id")
        #expect(request.value(forHTTPHeaderField: "X-Api-Key") == "KEY")
    }

    @Test func otherHostsGetNothing() {
        var request = URLRequest(url: URL(string: "http://camera.example.net/stream")!)
        client.authorize(&request)
        #expect(request.allHTTPHeaderFields?.isEmpty ?? true)
    }

    @Test func basicChallengeMeansSignInRequired() throws {
        let response = HTTPURLResponse(url: client.baseURL, statusCode: 401, httpVersion: nil,
                                       headerFields: ["WWW-Authenticate": "Basic realm=\"OctoPrint\""])!
        do {
            try OctoPrintClient.check(response, data: Data())
        } catch OctoPrintError.signInRequired {
        } catch {
            Issue.record("Expected signInRequired, got \(error)")
        }
    }

    @Test func signInPageIsNotOctoPrint() {
        let page = Data("<!DOCTYPE html><html><head><title>Sign in</title></head></html>".utf8)
        do {
            _ = try OctoPrintClient.decode(VersionInfo.self, from: page)
            Issue.record("Expected an error")
        } catch OctoPrintError.notOctoPrint {
        } catch {
            Issue.record("Expected notOctoPrint, got \(error)")
        }
    }
}
