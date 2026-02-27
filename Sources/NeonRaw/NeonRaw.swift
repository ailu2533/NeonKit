@_exported import CNeon
import CNeonShim
import Foundation

public struct NeonError: Error, Sendable, CustomStringConvertible {
    public let code: Int32
    public let message: String
    public let httpStatus: Int?

    public init(code: Int32, message: String, httpStatus: Int?) {
        self.code = code
        self.message = message
        self.httpStatus = httpStatus
    }

    public var description: String {
        "NeonError(code: \(code), httpStatus: \(httpStatus.map(String.init) ?? "nil"), message: \(message))"
    }
}

public struct Status: Sendable {
    public let code: Int
    public let klass: Int
    public let reason: String?
}

public struct URI: Sendable {
    public let scheme: String?
    public let host: String?
    public let port: UInt32
    public let path: String?
    public let query: String?
    public let fragment: String?
}

public struct PropertySet: Sendable {
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

public struct RawRequest: Sendable {
    public let method: String
    public let target: String
    public let headers: [(String, String)]
    public let body: Data?

    public init(method: String, target: String, headers: [(String, String)] = [], body: Data? = nil) {
        self.method = method
        self.target = target
        self.headers = headers
        self.body = body
    }
}

public struct RawResponse: Sendable {
    public let status: Status
    public let headers: [(String, String)]
    public let body: Data
}

public enum Depth: Int32, Sendable {
    case zero = 0
    case one = 1
    case infinite = 2
}

public struct ACLRule: Sendable {
    public enum Target: Sendable {
        case href(String)
        case property(String)
        case all
        case authenticated
        case unauthenticated
        case `self`
    }

    public enum Operation: Sendable {
        case grant
        case deny
    }

    public let target: Target
    public let operation: Operation
    public let privileges: UInt32

    public init(target: Target, operation: Operation, privileges: UInt32) {
        self.target = target
        self.operation = operation
        self.privileges = privileges
    }
}

@available(*, deprecated, message: "Use ACLRule with RFC3744 privileges")
public struct DeprecatedACLRule: Sendable {
    public enum Apply: Int32, Sendable {
        case href = 0
        case property = 1
        case all = 2
    }

    public enum Operation: Int32, Sendable {
        case grant = 0
        case deny = 1
    }

    public let apply: Apply
    public let operation: Operation
    public let principal: String
    public let canRead: Bool
    public let canReadACL: Bool
    public let canWrite: Bool
    public let canWriteACL: Bool
    public let canReadCurrentUserPrivilegeSet: Bool

    public init(
        apply: Apply,
        operation: Operation,
        principal: String,
        canRead: Bool,
        canReadACL: Bool,
        canWrite: Bool,
        canWriteACL: Bool,
        canReadCurrentUserPrivilegeSet: Bool
    ) {
        self.apply = apply
        self.operation = operation
        self.principal = principal
        self.canRead = canRead
        self.canReadACL = canReadACL
        self.canWrite = canWrite
        self.canWriteACL = canWriteACL
        self.canReadCurrentUserPrivilegeSet = canReadCurrentUserPrivilegeSet
    }
}

public struct LockToken: Sendable {
    public let path: String
    public let token: String
    public let owner: String?
    public let timeout: Int
}

public final class SessionHandle: @unchecked Sendable {
    public let pointer: OpaquePointer
    private var authContext: OpaquePointer?

    public init(baseURL: URL) throws {
        guard nk_global_init() == 0 else {
            throw NeonError(code: Int32(NE_ERROR), message: "failed to initialize neon global runtime", httpStatus: nil)
        }

        do {
            guard let host = baseURL.host else {
                throw NeonError(code: Int32(NE_ERROR), message: "baseURL host is missing", httpStatus: nil)
            }

            let scheme = baseURL.scheme ?? "https"
            let portValue = baseURL.port ?? ((scheme == "https") ? 443 : 80)
            let port = CUnsignedInt(portValue)

            guard let session = scheme.withCString({ schemePtr in
                host.withCString { hostPtr in
                    ne_session_create(schemePtr, hostPtr, port)
                }
            }) else {
                throw NeonError(code: Int32(NE_ERROR), message: "failed to create neon session", httpStatus: nil)
            }

            pointer = session
        } catch {
            nk_global_shutdown()
            throw error
        }
    }

    deinit {
        if let authContext {
            nk_auth_context_destroy(authContext)
        }
        ne_session_destroy(pointer)
        nk_global_shutdown()
    }

    public func closeConnection() {
        ne_close_connection(pointer)
    }

    public func setServerAuth(username: String, password: String) throws {
        if let authContext {
            nk_auth_context_destroy(authContext)
            self.authContext = nil
        }

        let created = username.withCString { userPtr in
            password.withCString { passPtr in
                nk_auth_context_create(userPtr, passPtr)
            }
        }

        guard let context = created else {
            throw NeonError(code: Int32(NE_ERROR), message: "failed to allocate auth context", httpStatus: nil)
        }

        authContext = context
        nk_session_set_server_auth(pointer, context)
    }

    public func setReadTimeout(_ timeout: Int) {
        ne_set_read_timeout(pointer, Int32(timeout))
    }

    public func setConnectTimeout(_ timeout: Int) {
        ne_set_connect_timeout(pointer, Int32(timeout))
    }

    public func setUserAgent(_ value: String) {
        value.withCString { ptr in
            ne_set_useragent(pointer, ptr)
        }
    }

    public func setProxy(host: String, port: UInt32) {
        host.withCString { hostPtr in
            ne_session_proxy(pointer, hostPtr, CUnsignedInt(port))
        }
    }

    public func request(_ request: RawRequest) throws -> RawResponse {
        var response = nk_response()

        let namesStorage = request.headers.map { strdup($0.0) }
        let valuesStorage = request.headers.map { strdup($0.1) }
        defer {
            for value in namesStorage {
                free(value)
            }
            for value in valuesStorage {
                free(value)
            }
        }

        let namePointers: [UnsafePointer<CChar>?] = namesStorage.map { ptr in
            ptr.map { UnsafePointer($0) }
        }
        let valuePointers: [UnsafePointer<CChar>?] = valuesStorage.map { ptr in
            ptr.map { UnsafePointer($0) }
        }

        let code = request.method.withCString { methodPtr in
            request.target.withCString { targetPtr in
                let dispatch: (_ bodyPtr: UnsafePointer<CChar>?, _ bodyLen: Int) -> Int32 = { bodyPtr, bodyLen in
                    namePointers.withUnsafeBufferPointer { nameBuffer in
                        valuePointers.withUnsafeBufferPointer { valueBuffer in
                            nk_dispatch_request(
                                self.pointer,
                                methodPtr,
                                targetPtr,
                                bodyPtr,
                                bodyLen,
                                nameBuffer.baseAddress,
                                valueBuffer.baseAddress,
                                namePointers.count,
                                &response
                            )
                        }
                    }
                }

                guard let body = request.body else {
                    return dispatch(nil, 0)
                }

                return body.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                    let bodyPtr = bytes.baseAddress?.assumingMemoryBound(to: CChar.self)
                    return dispatch(bodyPtr, body.count)
                }
            }
        }

        defer { nk_response_free(&response) }

        if code != NE_OK {
            let message = response.error.map { String(cString: $0) }
                ?? String(cString: ne_get_error(pointer))
            throw NeonError(code: Int32(code), message: message, httpStatus: response.status_code > 0 ? Int(response.status_code) : nil)
        }

        let body = response.body.map { Data(bytes: $0, count: Int(response.body_len)) } ?? Data()

        var headers: [(String, String)] = []
        if response.header_count > 0, let headerNames = response.header_names, let headerValues = response.header_values {
            for idx in 0 ..< Int(response.header_count) {
                guard let namePtr = headerNames[idx], let valuePtr = headerValues[idx] else { continue }
                headers.append((String(cString: namePtr), String(cString: valuePtr)))
            }
        }

        return RawResponse(
            status: Status(
                code: Int(response.status_code),
                klass: Int(response.status_class),
                reason: response.reason.map { String(cString: $0) }
            ),
            headers: headers,
            body: body
        )
    }

    public func get(path: String, fileDescriptor: Int32) throws {
        let code = path.withCString { pathPtr in
            ne_get(pointer, pathPtr, fileDescriptor)
        }
        try throwIfNeeded(code)
    }

    public func put(path: String, fileDescriptor: Int32) throws {
        let code = path.withCString { pathPtr in
            ne_put(pointer, pathPtr, fileDescriptor)
        }
        try throwIfNeeded(code)
    }

    public func put(path: String, data: Data) throws {
        let code = path.withCString { pathPtr in
            data.withUnsafeBytes { (bytes: UnsafeRawBufferPointer) in
                guard let base = bytes.baseAddress else {
                    return ne_putbuf(pointer, pathPtr, "", 0)
                }
                return ne_putbuf(pointer, pathPtr, base.assumingMemoryBound(to: CChar.self), data.count)
            }
        }
        try throwIfNeeded(code)
    }

    public func delete(path: String) throws {
        let code = path.withCString { pathPtr in
            ne_delete(pointer, pathPtr)
        }
        try throwIfNeeded(code)
    }

    public func copy(from source: String, to destination: String, overwrite: Bool = true, depth: Depth = .infinite) throws {
        let code = source.withCString { srcPtr in
            destination.withCString { dstPtr in
                ne_copy(pointer, overwrite ? 1 : 0, Int32(depth.rawValue), srcPtr, dstPtr)
            }
        }
        try throwIfNeeded(code)
    }

    public func move(from source: String, to destination: String, overwrite: Bool = true) throws {
        let code = source.withCString { srcPtr in
            destination.withCString { dstPtr in
                ne_move(pointer, overwrite ? 1 : 0, srcPtr, dstPtr)
            }
        }
        try throwIfNeeded(code)
    }

    public func makeCollection(path: String) throws {
        let code = path.withCString { pathPtr in
            ne_mkcol(pointer, pathPtr)
        }
        try throwIfNeeded(code)
    }

    public func options(path: String = "/") throws -> UInt32 {
        var caps: UInt32 = 0
        let code = path.withCString { ptr in
            ne_options2(pointer, ptr, &caps)
        }
        try throwIfNeeded(code)
        return caps
    }

    @available(*, deprecated, message: "Use options(path:) with ne_options2 capabilities")
    public func deprecatedOptions(path: String = "/") throws -> ne_server_capabilities {
        var caps = ne_server_capabilities()
        let code = path.withCString { ptr in
            ne_options(pointer, ptr, &caps)
        }
        try throwIfNeeded(code)
        return caps
    }

    public func propfind(path: String, depth: Depth = .one) throws -> [PropertySet] {
        var list = nk_prop_list()
        let code = path.withCString { ptr in
            nk_collect_propfind(pointer, ptr, Int32(depth.rawValue), &list)
        }

        defer { nk_prop_list_free(&list) }
        try throwIfNeeded(code)

        guard let items = list.items else {
            return []
        }

        return (0 ..< Int(list.count)).map { index in
            let item = items[index]
            return PropertySet(
                href: item.href.map { String(cString: $0) } ?? "",
                path: item.path.map { String(cString: $0) } ?? "",
                displayName: item.display_name.map { String(cString: $0) },
                etag: item.etag.map { String(cString: $0) },
                contentType: item.content_type.map { String(cString: $0) },
                contentLength: item.content_length >= 0 ? Int64(item.content_length) : nil,
                lastModified: parseHTTPDate(item.last_modified.map { String(cString: $0) }),
                isCollection: item.is_collection != 0,
                statusCode: Int(item.status_code)
            )
        }
    }

    public func lock(path: String, owner: String?, depth: Depth = .infinite, timeout: Int = 0) throws -> LockToken {
        guard let lock = ne_lock_create() else {
            throw NeonError(code: Int32(NE_ERROR), message: "failed to create lock object", httpStatus: nil)
        }
        defer { ne_lock_destroy(lock) }

        ne_fill_server_uri(pointer, &lock.pointee.uri)
        lock.pointee.uri.path = strdup(path)
        lock.pointee.depth = Int32(depth.rawValue)

        if let owner {
            lock.pointee.owner = strdup(owner)
        }
        if timeout != 0 {
            lock.pointee.timeout = timeout
        }

        let code = ne_lock(pointer, lock)
        try throwIfNeeded(code)

        return LockToken(
            path: path,
            token: lock.pointee.token.map { String(cString: $0) } ?? "",
            owner: lock.pointee.owner.map { String(cString: $0) },
            timeout: Int(lock.pointee.timeout)
        )
    }

    public func unlock(token: LockToken) throws {
        guard let lock = ne_lock_create() else {
            throw NeonError(code: Int32(NE_ERROR), message: "failed to create lock object", httpStatus: nil)
        }
        defer { ne_lock_destroy(lock) }

        ne_fill_server_uri(pointer, &lock.pointee.uri)
        lock.pointee.uri.path = strdup(token.path)
        lock.pointee.token = strdup(token.token)

        let code = ne_unlock(pointer, lock)
        try throwIfNeeded(code)
    }

    public func setACL(path: String, entries: [ACLRule]) throws {
        let converted = entries.map { rule -> ne_acl_entry in
            var entry = ne_acl_entry()
            switch rule.target {
            case let .href(value):
                entry.target = ne_acl_href
                entry.tname = strdup(value)
            case let .property(value):
                entry.target = ne_acl_property
                entry.tname = strdup(value)
            case .all:
                entry.target = ne_acl_all
                entry.tname = nil
            case .authenticated:
                entry.target = ne_acl_authenticated
                entry.tname = nil
            case .unauthenticated:
                entry.target = ne_acl_unauthenticated
                entry.tname = nil
            case .self:
                entry.target = ne_acl_self
                entry.tname = nil
            }

            entry.type = (rule.operation == .grant) ? ne_acl_grant : ne_acl_deny
            entry.privileges = CUnsignedInt(rule.privileges)
            return entry
        }

        let mutable = converted
        defer {
            for idx in mutable.indices {
                if let value = mutable[idx].tname {
                    free(value)
                }
            }
        }

        let code = path.withCString { pathPtr in
            mutable.withUnsafeBufferPointer { buffer in
                ne_acl3744_set(pointer, pathPtr, buffer.baseAddress, Int32(buffer.count))
            }
        }
        try throwIfNeeded(code)
    }

    @available(*, deprecated, message: "Use setACL(path:entries:) with RFC3744 ACL rules")
    public func deprecatedSetACL(path: String, entries: [DeprecatedACLRule]) throws {
        let principals = entries.map { strdup($0.principal) }
        defer {
            for principal in principals {
                free(principal)
            }
        }

        let legacyEntries = entries.enumerated().map { index, rule in
            var entry = nk_acl_legacy_entry()
            entry.apply = Int32(rule.apply.rawValue)
            entry.type = Int32(rule.operation.rawValue)
            entry.principal = principals[index].map { UnsafePointer($0) }
            entry.read = rule.canRead ? 1 : 0
            entry.read_acl = rule.canReadACL ? 1 : 0
            entry.write = rule.canWrite ? 1 : 0
            entry.write_acl = rule.canWriteACL ? 1 : 0
            entry.read_cuprivset = rule.canReadCurrentUserPrivilegeSet ? 1 : 0
            return entry
        }

        let code = path.withCString { pathPtr in
            legacyEntries.withUnsafeBufferPointer { buffer in
                nk_acl_set_legacy(pointer, pathPtr, buffer.baseAddress, Int32(buffer.count))
            }
        }
        try throwIfNeeded(code)
    }

    private func throwIfNeeded(_ code: Int32) throws {
        guard code == Int32(NE_OK) else {
            let message = String(cString: ne_get_error(pointer))
            throw NeonError(code: code, message: message, httpStatus: nil)
        }
    }
}

private func parseHTTPDate(_ value: String?) -> Date? {
    guard let value else { return nil }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
    return formatter.date(from: value)
}
