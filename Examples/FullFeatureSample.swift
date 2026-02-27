import Foundation
import NeonKit

@main
struct FullFeatureSample {
    static func main() async throws {
        let config = WebDAVClientConfiguration(
            baseURL: URL(string: "https://dav.example.com")!,
            username: "user",
            password: "pass",
            userAgent: "NeonKitSample/1.0"
        )

        let client = try WebDAVClient(configuration: config)

        try await client.makeCollection(path: "/demo/")
        try await client.uploadData(Data("hello".utf8), to: "/demo/hello.txt")
        _ = try await client.list(path: "/demo/", depth: .one)

        let token = try await client.lock(path: "/demo/hello.txt", owner: "sample")
        try await client.unlock(token)

        try await client.setACL(
            path: "/demo/hello.txt",
            entries: [ACLRule(target: .authenticated, operation: .grant, privileges: UInt32(NE_ACL_READ))]
        )

        try await client.delete(path: "/demo/hello.txt")
        try await client.delete(path: "/demo/")
    }
}
