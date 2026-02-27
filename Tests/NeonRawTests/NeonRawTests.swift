import Foundation
@testable import NeonRaw
import Testing

@Test func canCreateSession() throws {
    let session = try SessionHandle(baseURL: URL(string: "http://localhost")!)
    #expect(String(cString: ne_get_scheme(session.pointer)) == "http")
}

@Test func rawRequestFailsOnClosedPort() throws {
    let session = try SessionHandle(baseURL: URL(string: "http://127.0.0.1:1")!)

    do {
        _ = try session.request(.init(method: "GET", target: "/"))
        #expect(Bool(false), "request should fail on closed port")
    } catch {
        #expect(Bool(true))
    }
}
