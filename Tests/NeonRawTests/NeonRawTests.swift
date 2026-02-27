import Foundation
import XCTest
@testable import NeonRaw

final class NeonRawTests: XCTestCase {
    func testCanCreateSession() throws {
        let session = try SessionHandle(baseURL: URL(string: "http://localhost")!)
        XCTAssertEqual(String(cString: ne_get_scheme(session.pointer)), "http")
    }

    func testRawRequestFailsOnClosedPort() throws {
        let session = try SessionHandle(baseURL: URL(string: "http://127.0.0.1:1")!)

        XCTAssertThrowsError(try session.request(.init(method: "GET", target: "/")))
    }
}
