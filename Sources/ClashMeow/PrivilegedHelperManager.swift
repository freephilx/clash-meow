import Foundation
import Security
import ServiceManagement

enum PrivilegedHelperError: LocalizedError {
    case blessFailed(String)
    case connectionFailed
    case timeout(String)
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .blessFailed(let message):
            "安装特权助手失败：\(message)"
        case .connectionFailed:
            "无法连接特权助手"
        case .timeout(let operation):
            "特权助手调用超时：\(operation)"
        case .operationFailed(let message):
            message
        }
    }
}

final class PrivilegedHelperManager: @unchecked Sendable {
    static let shared = PrivilegedHelperManager()

    private var connection: NSXPCConnection?
    private let lock = NSLock()

    private init() {}

    var canInstallBundledHelper: Bool {
        Bundle.main.bundleURL.pathExtension == "app"
    }

    var isInstalled: Bool {
        SMJobCopyDictionary(kSMDomainSystemLaunchd, PrivilegedHelperConstants.bundleID as CFString) != nil
    }

    var needsInstallOrUpdate: Bool {
        !isInstalled || installedHelperVersion() != PrivilegedHelperConstants.helperVersion
    }

    func releasePorts(_ ports: Set<Int>, excludingPID: pid_t?) throws -> [String] {
        guard canInstallBundledHelper else {
            throw PrivilegedHelperError.blessFailed("当前进程不是 app bundle，跳过特权助手")
        }
        let portDescription = ports.sorted().map(String.init).joined(separator: ", ")
        debugLog("准备释放端口: \(portDescription)")
        try ensureInstalled()
        do {
            return try callReleasePorts(ports, excludingPID: excludingPID)
        } catch {
            debugLog("释放端口调用失败，将重试一次: \(error.localizedDescription)")
            invalidateConnection()
            usleep(300_000)
            return try callReleasePorts(ports, excludingPID: excludingPID)
        }
    }

    private func callReleasePorts(_ ports: Set<Int>, excludingPID: pid_t?) throws -> [String] {
        let proxy = try remoteProxy()
        let semaphore = DispatchSemaphore(value: 0)
        var responseLogs: [String] = []
        var responseError: NSError?
        debugLog("调用 helper releasePorts")
        proxy.releasePorts(
            ports.sorted().map { NSNumber(value: $0) },
            excludingPID: NSNumber(value: excludingPID ?? -1)
        ) { logs, error in
            responseLogs = logs
            responseError = error
            semaphore.signal()
        }
        guard semaphore.wait(timeout: .now() + 10) == .success else {
            invalidateConnection()
            throw PrivilegedHelperError.timeout("releasePorts")
        }
        if let responseError {
            throw PrivilegedHelperError.operationFailed(responseError.localizedDescription)
        }
        return responseLogs
    }

    private func ensureInstalled() throws {
        let installed = isInstalled
        debugLog("helper installed=\(installed)")
        if installed, !needsInstallOrUpdate {
            debugLog("helper 已安装且版本匹配")
            return
        }

        let authRef = try createAuthorizationRef()
        defer { AuthorizationFree(authRef, []) }
        try acquireBlessRights(authRef)

        if installed {
            debugLog("helper 需要更新，先移除旧版本")
            try removeInstalledHelper(authRef: authRef)
        }
        debugLog("开始安装 helper")
        try install(authRef: authRef)
        usleep(300_000)
        debugLog("helper 安装完成")
    }

    private func install(authRef: AuthorizationRef) throws {
        var blessError: Unmanaged<CFError>?
        let blessed = SMJobBless(
            kSMDomainSystemLaunchd,
            PrivilegedHelperConstants.bundleID as CFString,
            authRef,
            &blessError
        )
        guard blessed else {
            throw PrivilegedHelperError.blessFailed(Self.describeBlessError(blessError?.takeRetainedValue()))
        }
        debugLog("SMJobBless 成功")
        invalidateConnection()
    }

    private func remoteProxy() throws -> HelperXPCProtocol {
        lock.lock()
        if connection == nil {
            let conn = NSXPCConnection(
                machServiceName: PrivilegedHelperConstants.machServiceName,
                options: .privileged
            )
            conn.remoteObjectInterface = NSXPCInterface(with: HelperXPCProtocol.self)
            conn.invalidationHandler = { [weak self] in
                Self.debugLog("helper XPC 连接失效")
                self?.invalidateConnection()
            }
            conn.interruptionHandler = { [weak self] in
                Self.debugLog("helper XPC 连接中断")
                self?.invalidateConnection()
            }
            conn.resume()
            connection = conn
            debugLog("已创建 helper XPC 连接")
        }
        let conn = connection!
        lock.unlock()

        var proxyError: NSError?
        let proxy = conn.remoteObjectProxyWithErrorHandler { error in
            proxyError = error as NSError
        }
        guard let helper = proxy as? HelperXPCProtocol else {
            throw PrivilegedHelperError.connectionFailed
        }
        if let proxyError {
            throw proxyError
        }
        return helper
    }

    private func invalidateConnection() {
        lock.lock()
        connection?.invalidate()
        connection = nil
        lock.unlock()
    }

    private func installedHelperVersion(timeout: TimeInterval = 1) -> String? {
        guard isInstalled else { return nil }
        do {
            let proxy = try remoteProxy()
            let semaphore = DispatchSemaphore(value: 0)
            var value: String?
            debugLog("读取 helper 版本")
            proxy.version { version in
                value = version
                semaphore.signal()
            }
            guard semaphore.wait(timeout: .now() + timeout) == .success else {
                debugLog("读取 helper 版本超时")
                invalidateConnection()
                return nil
            }
            let versionDescription = value ?? "nil"
            debugLog("helper 版本=\(versionDescription)")
            return value
        } catch {
            debugLog("读取 helper 版本失败: \(error.localizedDescription)")
            invalidateConnection()
            return nil
        }
    }

    private func removeInstalledHelper(authRef: AuthorizationRef) throws {
        var removeError: Unmanaged<CFError>?
        let removed = SMJobRemove(
            kSMDomainSystemLaunchd,
            PrivilegedHelperConstants.bundleID as CFString,
            authRef,
            true,
            &removeError
        )
        guard removed else {
            throw PrivilegedHelperError.blessFailed("移除旧助手失败：\(Self.describeBlessError(removeError?.takeRetainedValue()))")
        }
        debugLog("SMJobRemove 成功")
        invalidateConnection()
    }

    private func createAuthorizationRef() throws -> AuthorizationRef {
        var authRef: AuthorizationRef?
        let status = AuthorizationCreate(nil, nil, [.interactionAllowed, .extendRights], &authRef)
        guard status == errAuthorizationSuccess, let authRef else {
            throw PrivilegedHelperError.blessFailed("无法创建授权（\(status)）")
        }
        debugLog("AuthorizationCreate 成功")
        return authRef
    }

    private func acquireBlessRights(_ authRef: AuthorizationRef) throws {
        try kSMRightBlessPrivilegedHelper.withCString { rightName in
            var authItem = AuthorizationItem(name: rightName, valueLength: 0, value: nil, flags: 0)
            try withUnsafeMutablePointer(to: &authItem) { itemPointer in
                var authRights = AuthorizationRights(count: 1, items: itemPointer)
                let status = AuthorizationCopyRights(
                    authRef,
                    &authRights,
                    nil,
                    [.interactionAllowed, .extendRights, .preAuthorize],
                    nil
                )
                guard status == errAuthorizationSuccess else {
                    if status == errAuthorizationCanceled {
                        throw PrivilegedHelperError.blessFailed("已取消管理员授权")
                    }
                    throw PrivilegedHelperError.blessFailed("无法获取 bless 授权（\(status)）")
                }
                debugLog("获取 bless 授权成功")
            }
        }
    }

    private static func describeBlessError(_ error: CFError?) -> String {
        guard let error else { return "未知错误" }
        let domain = CFErrorGetDomain(error) as String
        let code = CFErrorGetCode(error)
        let description = CFErrorCopyDescription(error) as String? ?? "未知错误"
        return "\(description)（\(domain) 错误 \(code)）"
    }

    private static func debugLog(_ message: String) {
        #if DEBUG
        print("[PrivilegedHelper] \(message)")
        #endif
    }

    private func debugLog(_ message: String) {
        Self.debugLog(message)
    }
}
