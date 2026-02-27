import Foundation
import XCTest
@testable import NeonKit

final class NeonKitTests: XCTestCase {
    func testClientInitialization() throws {
        let config = WebDAVClientConfiguration(baseURL: URL(string: "http://localhost")!)
        _ = try WebDAVClient(configuration: config)
        XCTAssertTrue(true)
    }
}
