import Foundation
import NeonRaw

public struct WebDAVClientConfiguration: Sendable {
    public var baseURL: URL
    public var username: String?
    public var password: String?
    public var userAgent: String?
    public var connectTimeout: Int
    public var readTimeout: Int

    public init(
        baseURL: URL,
        username: String? = nil,
        password: String? = nil,
        userAgent: String? = nil,
        connectTimeout: Int = 30,
        readTimeout: Int = 60
    ) {
        self.baseURL = baseURL
        self.username = username
        self.password = password
        self.userAgent = userAgent
        self.connectTimeout = connectTimeout
        self.readTimeout = readTimeout
    }
}

public struct WebDAVResource: Sendable {
    public let href: String
    public let path: String
    public let displayName: String?
    public let etag: String?
    public let contentType: String?
    public let contentLength: Int64?
    public let lastModified: Date?
    public let isCollection: Bool
    public let statusCode: Int
}

public enum WebDAVTransferDirection: Sendable {
    case upload
    case download
}

public enum WebDAVTransferEvent: Sendable {
    case started(direction: WebDAVTransferDirection, totalBytes: Int64?)
    case progress(direction: WebDAVTransferDirection, completedBytes: Int64, totalBytes: Int64?)
    case completed(direction: WebDAVTransferDirection)
}

public actor WebDAVClient {
    private let session: SessionHandle
    private let queue = DispatchQueue(label: "com.neonkit.webdav.session")

    public init(configuration: WebDAVClientConfiguration) throws {
        session = try SessionHandle(baseURL: configuration.baseURL)

        if let userAgent = configuration.userAgent {
            session.setUserAgent(userAgent)
        }

        session.setConnectTimeout(configuration.connectTimeout)
        session.setReadTimeout(configuration.readTimeout)

        if let username = configuration.username, let password = configuration.password {
            try session.setServerAuth(username: username, password: password)
        }
    }

    public func rawRequest(_ request: RawRequest) async throws -> RawResponse {
        try await performBlocking {
            try self.session.request(request)
        }
    }

    public func list(path: String, depth: Depth = .one) async throws -> [WebDAVResource] {
        try await performBlocking {
            try self.session.propfind(path: path, depth: depth).map {
                WebDAVResource(
                    href: $0.href,
                    path: $0.path,
                    displayName: $0.displayName,
                    etag: $0.etag,
                    contentType: $0.contentType,
                    contentLength: $0.contentLength,
                    lastModified: $0.lastModified,
                    isCollection: $0.isCollection,
                    statusCode: $0.statusCode
                )
            }
        }
    }

    public func downloadData(path: String) async throws -> Data {
        let response = try await rawRequest(RawRequest(method: "GET", target: path))
        guard response.status.code >= 200, response.status.code < 300 else {
            throw NeonError(
                code: Int32(NE_ERROR),
                message: "unexpected status \(response.status.code)",
                httpStatus: response.status.code
            )
        }
        return response.body
    }

    public func uploadData(_ data: Data, to path: String) async throws {
        let response = try await rawRequest(RawRequest(method: "PUT", target: path, body: data))
        guard response.status.code >= 200, response.status.code < 300 else {
            throw NeonError(
                code: Int32(NE_ERROR),
                message: "unexpected status \(response.status.code)",
                httpStatus: response.status.code
            )
        }
    }

    public func delete(path: String) async throws {
        try await performBlocking {
            try self.session.delete(path: path)
        }
    }

    public func makeCollection(path: String) async throws {
        try await performBlocking {
            try self.session.makeCollection(path: path)
        }
    }

    public func copy(from sourcePath: String, to destinationPath: String, overwrite: Bool = true, depth: Depth = .infinite) async throws {
        try await performBlocking {
            try self.session.copy(from: sourcePath, to: destinationPath, overwrite: overwrite, depth: depth)
        }
    }

    public func move(from sourcePath: String, to destinationPath: String, overwrite: Bool = true) async throws {
        try await performBlocking {
            try self.session.move(from: sourcePath, to: destinationPath, overwrite: overwrite)
        }
    }

    public func lock(path: String, owner: String? = nil, depth: Depth = .infinite, timeout: Int = 0) async throws -> LockToken {
        try await performBlocking {
            try self.session.lock(path: path, owner: owner, depth: depth, timeout: timeout)
        }
    }

    public func unlock(_ token: LockToken) async throws {
        try await performBlocking {
            try self.session.unlock(token: token)
        }
    }

    public func setACL(path: String, entries: [ACLRule]) async throws {
        try await performBlocking {
            try self.session.setACL(path: path, entries: entries)
        }
    }

    public func download(path: String, to fileURL: URL) -> AsyncThrowingStream<WebDAVTransferEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let data = try await self.downloadData(path: path)
                    continuation.yield(.started(direction: .download, totalBytes: Int64(data.count)))
                    try data.write(to: fileURL, options: .atomic)
                    continuation.yield(.progress(direction: .download, completedBytes: Int64(data.count), totalBytes: Int64(data.count)))
                    continuation.yield(.completed(direction: .download))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func upload(file fileURL: URL, to path: String) -> AsyncThrowingStream<WebDAVTransferEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let data = try Data(contentsOf: fileURL)
                    continuation.yield(.started(direction: .upload, totalBytes: Int64(data.count)))
                    try await self.uploadData(data, to: path)
                    continuation.yield(.progress(direction: .upload, completedBytes: Int64(data.count), totalBytes: Int64(data.count)))
                    continuation.yield(.completed(direction: .upload))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    public func close() {
        session.closeConnection()
    }

    private func performBlocking<T: Sendable>(_ operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try continuation.resume(returning: operation())
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }
}
