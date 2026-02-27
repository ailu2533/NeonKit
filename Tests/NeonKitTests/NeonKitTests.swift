import Foundation
@testable import NeonKit
import Testing

@Test func clientInitialization() throws {
    let config = WebDAVClientConfiguration(baseURL: URL(string: "http://localhost")!)
    _ = try WebDAVClient(configuration: config)
    #expect(Bool(true))
}
