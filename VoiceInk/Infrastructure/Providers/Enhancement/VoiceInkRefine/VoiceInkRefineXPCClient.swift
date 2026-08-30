import Foundation
import OSLog

private final class VoiceInkRefineXPCReply<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<Value, Error>?

    init(_ continuation: CheckedContinuation<Value, Error>) {
        self.continuation = continuation
    }

    func resolve(_ result: Result<Value, Error>) {
        lock.lock()
        let continuation = continuation
        self.continuation = nil
        lock.unlock()

        continuation?.resume(with: result)
    }
}

private final class VoiceInkRefineXPCCancellationHandle: @unchecked Sendable {
    private let connection: NSXPCConnection

    init(_ connection: NSXPCConnection) {
        self.connection = connection
    }

    func cancel() {
        connection.invalidate()
    }
}

private enum VoiceInkRefineXPCOperation {
    case prepare
    case enhance
}

private enum VoiceInkRefineXPCOperationWaiter {
    case standard(CheckedContinuation<Void, Never>)
    case cancellable(id: UUID, continuation: CheckedContinuation<Void, Error>)

    var id: UUID? {
        guard case .cancellable(let id, _) = self else { return nil }
        return id
    }

    func resume() {
        switch self {
        case .standard(let continuation):
            continuation.resume()
        case .cancellable(_, let continuation):
            continuation.resume()
        }
    }

    func cancel() {
        guard case .cancellable(_, let continuation) = self else { return }
        continuation.resume(throwing: CancellationError())
    }
}

actor VoiceInkRefineXPCClient {
    private static let warmGracePeriod: Duration = .seconds(10)

    private let logger = Logger(
        subsystem: "com.prakashjoshipax.voiceink",
        category: "VoiceInkRefineXPCClient"
    )

    private var connection: NSXPCConnection?
    private var connectionID: UUID?
    private var operationIsActive = false
    private var operationWaiters: [VoiceInkRefineXPCOperationWaiter] = []
    private var idleShutdownTask: Task<Void, Never>?
    private var idleShutdownToken: UUID?

    func prepare(modelDirectory: URL, systemPrompt: String) async throws {
        try await acquireCancellableOperation()
        defer { releaseOperation() }

        try Task.checkCancellation()
        cancelIdleShutdown()

        let request = VoiceInkRefinePrepareRequest(
            requestID: UUID(),
            modelDirectoryPath: modelDirectory.path,
            systemPrompt: systemPrompt
        )
        let requestData = try JSONEncoder().encode(request)
        let activeConnection = connectionForRequest()
        let cancellationHandle = VoiceInkRefineXPCCancellationHandle(activeConnection)

        do {
            try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    let reply = VoiceInkRefineXPCReply<Void>(continuation)
                    guard
                        let proxy = activeConnection.remoteObjectProxyWithErrorHandler({
                            error in
                            reply.resolve(.failure(error))
                        }) as? VoiceInkRefineXPCProtocol
                    else {
                        reply.resolve(
                            .failure(
                                makeVoiceInkRefineXPCError(
                                    .connectionFailed,
                                    description: "Could not create the VoiceInk Refine XPC proxy."
                                )
                            )
                        )
                        return
                    }

                    proxy.prepare(requestData as NSData) { error in
                        if let error {
                            reply.resolve(.failure(error))
                        } else {
                            reply.resolve(.success(()))
                        }
                    }
                }
            } onCancel: {
                cancellationHandle.cancel()
            }
            try Task.checkCancellation()
        } catch {
            invalidateIfCurrent(activeConnection)
            if Task.isCancelled {
                throw CancellationError()
            }
            logFailure(error, operation: .prepare)
            throw localizedError(error, operation: .prepare)
        }
    }

    func enhance(
        transcript: String,
        modelDirectory: URL,
        systemPrompt: String
    ) async throws -> String {
        try await acquireCancellableOperation()
        defer { releaseOperation() }

        try Task.checkCancellation()
        cancelIdleShutdown()

        let request = VoiceInkRefineEnhanceRequest(
            requestID: UUID(),
            modelDirectoryPath: modelDirectory.path,
            systemPrompt: systemPrompt,
            transcript: transcript
        )
        let requestData = try JSONEncoder().encode(request)
        let activeConnection = connectionForRequest()
        let cancellationHandle = VoiceInkRefineXPCCancellationHandle(activeConnection)

        do {
            let responseData: Data = try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    let reply = VoiceInkRefineXPCReply<Data>(continuation)
                    guard
                        let proxy = activeConnection.remoteObjectProxyWithErrorHandler({
                            error in
                            reply.resolve(.failure(error))
                        }) as? VoiceInkRefineXPCProtocol
                    else {
                        reply.resolve(
                            .failure(
                                makeVoiceInkRefineXPCError(
                                    .connectionFailed,
                                    description: "Could not create the VoiceInk Refine XPC proxy."
                                )
                            )
                        )
                        return
                    }

                    proxy.enhance(requestData as NSData) { responseData, error in
                        if let error {
                            reply.resolve(.failure(error))
                        } else if let responseData {
                            reply.resolve(.success(responseData as Data))
                        } else {
                            reply.resolve(
                                .failure(
                                    makeVoiceInkRefineXPCError(
                                        .invalidResponse,
                                        description:
                                            "VoiceInk Refine returned an empty response."
                                    )
                                )
                            )
                        }
                    }
                }
            } onCancel: {
                cancellationHandle.cancel()
            }
            try Task.checkCancellation()

            let response = try JSONDecoder().decode(
                VoiceInkRefineEnhanceResponse.self,
                from: responseData
            )
            guard response.requestID == request.requestID else {
                throw makeVoiceInkRefineXPCError(
                    .invalidResponse,
                    description: "VoiceInk Refine returned a mismatched response."
                )
            }

            scheduleIdleShutdown(for: activeConnection)
            return response.output
        } catch {
            invalidateIfCurrent(activeConnection)
            if Task.isCancelled {
                throw CancellationError()
            }
            logFailure(error, operation: .enhance)
            throw localizedError(error, operation: .enhance)
        }
    }

    func shutdown() async {
        cancelIdleShutdown()
        await acquireOperation()
        defer { releaseOperation() }

        cancelIdleShutdown()
        await shutdownCurrentConnection()
    }

    func shutdownPreparedModelIfNeeded() async {
        await acquireOperation()
        defer { releaseOperation() }

        guard idleShutdownTask == nil else { return }

        await shutdownCurrentConnection()
    }

    func keepPreparedModelWarmForRecording() {
        cancelIdleShutdown()
    }

    private func shutdownCurrentConnection() async {
        guard let activeConnection = connection else { return }
        connection = nil
        connectionID = nil

        await requestShutdown(of: activeConnection)
    }

    private func connectionForRequest() -> NSXPCConnection {
        if let connection {
            return connection
        }

        let identifier = UUID()
        let connection = NSXPCConnection(serviceName: voiceInkRefineXPCServiceName)
        connection.remoteObjectInterface = NSXPCInterface(
            with: VoiceInkRefineXPCProtocol.self
        )
        connection.interruptionHandler = { [weak self, weak connection] in
            guard let self, let connection else { return }
            Task {
                await self.connectionInterrupted(connection, identifier: identifier)
            }
        }
        connection.invalidationHandler = { [weak self, weak connection] in
            guard let self, let connection else { return }
            Task {
                await self.connectionInvalidated(connection, identifier: identifier)
            }
        }
        connection.resume()

        self.connection = connection
        connectionID = identifier
        return connection
    }

    private func scheduleIdleShutdown(for activeConnection: NSXPCConnection) {
        guard connection === activeConnection else { return }

        cancelIdleShutdown()
        let token = UUID()
        idleShutdownToken = token

        idleShutdownTask = Task { [weak self] in
            do {
                try await Task.sleep(for: Self.warmGracePeriod)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }
            await self?.idleShutdownTimerFired(
                token: token,
                expectedConnection: activeConnection
            )
        }
    }

    private func idleShutdownTimerFired(
        token: UUID,
        expectedConnection: NSXPCConnection
    ) async {
        guard idleShutdownToken == token else { return }

        await acquireOperation()
        defer { releaseOperation() }

        guard idleShutdownToken == token,
            connection === expectedConnection
        else {
            return
        }

        idleShutdownTask = nil
        idleShutdownToken = nil
        await shutdownCurrentConnection()
    }

    private func cancelIdleShutdown() {
        guard idleShutdownTask != nil || idleShutdownToken != nil else { return }

        idleShutdownTask?.cancel()
        idleShutdownTask = nil
        idleShutdownToken = nil
    }

    private func acquireOperation() async {
        guard operationIsActive else {
            operationIsActive = true
            return
        }

        await withCheckedContinuation { continuation in
            operationWaiters.append(.standard(continuation))
        }
    }

    private func acquireCancellableOperation() async throws {
        try Task.checkCancellation()

        guard operationIsActive else {
            operationIsActive = true
            return
        }

        let waiterID = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                guard !Task.isCancelled else {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                operationWaiters.append(
                    .cancellable(id: waiterID, continuation: continuation)
                )
            }
        } onCancel: {
            Task {
                await self.cancelOperationWaiter(id: waiterID)
            }
        }
    }

    private func cancelOperationWaiter(id: UUID) {
        guard let index = operationWaiters.firstIndex(where: { $0.id == id }) else {
            return
        }

        let waiter = operationWaiters.remove(at: index)
        waiter.cancel()
    }

    private func releaseOperation() {
        guard !operationWaiters.isEmpty else {
            operationIsActive = false
            return
        }

        operationWaiters.removeFirst().resume()
    }

    private func requestShutdown(of activeConnection: NSXPCConnection) async {
        _ = try? await withCheckedThrowingContinuation { continuation in
            let reply = VoiceInkRefineXPCReply<Void>(continuation)
            guard
                let proxy = activeConnection.remoteObjectProxyWithErrorHandler({
                    _ in
                    reply.resolve(.success(()))
                    activeConnection.invalidate()
                }) as? VoiceInkRefineXPCProtocol
            else {
                activeConnection.invalidate()
                reply.resolve(.success(()))
                return
            }

            proxy.shutdown {
                activeConnection.invalidate()
                reply.resolve(.success(()))
            }
        }
    }

    private func invalidateIfCurrent(_ activeConnection: NSXPCConnection) {
        if connection === activeConnection {
            connection = nil
            connectionID = nil
            cancelIdleShutdown()
        }
        activeConnection.invalidate()
    }

    private func localizedError(
        _ error: Error,
        operation: VoiceInkRefineXPCOperation
    ) -> Error {
        let nsError = error as NSError
        guard nsError.domain == voiceInkRefineXPCErrorDomain,
            let code = VoiceInkRefineXPCErrorCode(rawValue: nsError.code)
        else {
            return error
        }

        let description: String
        switch code {
        case .invalidRequest:
            description = String(localized: "VoiceInk Refine received an invalid request.")
        case .inferenceFailed:
            switch operation {
            case .prepare:
                description = String(localized: "VoiceInk Refine could not prepare the model.")
            case .enhance:
                description = String(
                    localized: "VoiceInk Refine could not complete the enhancement."
                )
            }
        case .invalidResponse:
            description = String(localized: "VoiceInk Refine returned an invalid response.")
        case .connectionFailed:
            description = String(localized: "Could not communicate with VoiceInk Refine.")
        }

        return makeVoiceInkRefineXPCError(code, description: description)
    }

    private func logFailure(
        _ error: Error,
        operation: VoiceInkRefineXPCOperation
    ) {
        let nsError = error as NSError
        let operationName: String
        switch operation {
        case .prepare:
            operationName = "prepare"
        case .enhance:
            operationName = "enhance"
        }
        logger.error(
            "VoiceInk Refine XPC \(operationName, privacy: .public) failed domain=\(nsError.domain, privacy: .public) code=\(nsError.code, privacy: .public) description=\(nsError.localizedDescription, privacy: .public)"
        )
    }

    private func connectionInterrupted(
        _ interruptedConnection: NSXPCConnection,
        identifier: UUID
    ) {
        guard connection === interruptedConnection, connectionID == identifier else {
            return
        }
        connection = nil
        connectionID = nil
        cancelIdleShutdown()
        logger.error(
            "VoiceInk Refine XPC connection interrupted id=\(identifier.uuidString, privacy: .public)"
        )
    }

    private func connectionInvalidated(
        _ invalidatedConnection: NSXPCConnection,
        identifier: UUID
    ) {
        guard connection === invalidatedConnection, connectionID == identifier else {
            return
        }
        connection = nil
        connectionID = nil
        cancelIdleShutdown()
    }
}
