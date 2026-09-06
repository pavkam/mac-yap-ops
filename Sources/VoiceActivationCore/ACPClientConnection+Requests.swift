// SPDX-FileCopyrightText: 2026 Alexandru Ciobanu (alex+git@ciobanu.org)
// SPDX-License-Identifier: MIT

import Foundation

extension ACPClientConnection {
    func start(
        restoration: AgentSessionRestorationRequest?,
        onRestoredEvent: @escaping @Sendable (AgentRestorationToken, AgentRunEvent) async -> Void,
        clientCapabilityFragments: [ACPJSONValue],
        afterRestorationResponseValidation: @escaping @Sendable () async -> Void
    ) async throws -> AgentSessionActivation {
        let startedAtUptime = DispatchTime.now().uptimeNanoseconds
        diagnostics.record(
            category: .acp,
            event: "acp_client.connection_started",
            fields: [
                "connection_id": connectionID.uuidString,
                "provider": configuration.preset.rawValue,
            ])

        do {
            try Task.checkCancellation()
            let clientCapabilities = try ACPClientCapabilities.compose(
                clientCapabilityFragments)
            let output = await transport.output()
            try Task.checkCancellation()
            receiveTask = Task {
                await self.receive(output)
            }
            let initializeResult = try await sendRequest(
                method: "initialize",
                params: .object([
                    "protocolVersion": .integer(1),
                    "clientCapabilities": clientCapabilities,
                    "clientInfo": .object([
                        "name": .string(Self.clientName),
                        "title": .string(Self.clientTitle),
                        "version": .string(Self.clientVersion),
                    ]),
                ]))
            try applyInitializeResult(initializeResult)
            try Task.checkCancellation()

            let activation: AgentSessionActivation
            if let restoration {
                switch AgentSessionRestorationPolicy.operation(
                    need: restoration.need,
                    capabilities: sessionRestorationCapabilities)
                {
                case .load:
                    activation = try await loadSession(
                        restoration,
                        deliversReplay: true,
                        onRestoredEvent: onRestoredEvent,
                        afterResponseValidation: afterRestorationResponseValidation)
                case .loadDiscardingReplay:
                    activation = try await loadSession(
                        restoration,
                        deliversReplay: false,
                        onRestoredEvent: onRestoredEvent,
                        afterResponseValidation: afterRestorationResponseValidation)
                case .resume:
                    activation = try await resumeSession(
                        restoration,
                        afterResponseValidation: afterRestorationResponseValidation)
                case .new:
                    activation = try await newSession(
                        restorationWasUnsupported: true)
                }
            } else {
                activation = try await newSession(restorationWasUnsupported: false)
            }
            try Task.checkCancellation()
            diagnostics.record(
                category: .acp,
                event: "acp_client.connection_ready",
                fields: [
                    "connection_id": connectionID.uuidString,
                    "duration_ms": String(Self.elapsedMilliseconds(since: startedAtUptime)),
                    "authentication_method_count": String(authenticationMethodNames.count),
                    "load_session": String(sessionRestorationCapabilities.loadSession),
                    "resume_session": String(sessionRestorationCapabilities.resumeSession),
                    "operation": activation.diagnosticOperation,
                ])
            return activation
        } catch {
            let detachedRestoration = detachRestoration()
            await discardRestoration(detachedRestoration)
            await close()
            diagnostics.record(
                category: .acp,
                event: "acp_client.connection_failed",
                level: .error,
                fields: [
                    "connection_id": connectionID.uuidString,
                    "duration_ms": String(Self.elapsedMilliseconds(since: startedAtUptime)),
                    "error_type": String(describing: type(of: error)),
                ])
            if Task.isCancelled || error is CancellationError {
                throw CancellationError()
            }
            if let capabilityError = error as? ACPClientCapabilitiesError {
                throw capabilityError
            }
            throw userSafeError(error)
        }
    }

    func applyInitializeResult(_ value: ACPJSONValue) throws {
        let result = try requiredObject(value, named: "initialize result")
        let protocolVersion = try requiredInteger(
            result["protocolVersion"],
            named: "protocolVersion")
        guard protocolVersion == 1 else {
            throw ACPClientError.incompatibleProtocol(selected: protocolVersion)
        }
        sessionRestorationCapabilities = try ACPSessionRestorationCapabilities.decode(
            from: result["agentCapabilities"])

        if let agentInfo = result["agentInfo"], agentInfo != .null {
            let information = try requiredObject(agentInfo, named: "agentInfo")
            let title = try optionalString(information["title"], named: "agentInfo.title")
            let name = try optionalString(information["name"], named: "agentInfo.name")
            agentName = title ?? name ?? configuration.displayName
        } else {
            agentName = configuration.displayName
        }

        guard let methodsValue = result["authMethods"] else {
            authenticationMethodNames = []
            return
        }
        let methods = try requiredArray(methodsValue, named: "authMethods")
        authenticationMethodNames =
            try methods
            .prefix(Self.maximumAdvertisedAuthenticationMethods)
            .map { methodValue in
                let method = try requiredObject(methodValue, named: "authMethods entry")
                return boundedText(
                    try requiredString(method["name"], named: "authMethods name"),
                    maximumBytes: Self.maximumDiagnosticBytes)
            }
    }

    func newSession(restorationWasUnsupported: Bool) async throws -> AgentSessionActivation {
        let result: ACPJSONValue
        do {
            result = try await sendRequest(
                method: "session/new",
                params: .object([
                    "cwd": .string(configuration.workingDirectory),
                    "mcpServers": .array([]),
                ]))
        } catch let error as ACPClientError {
            if case .remoteError(let code, _) = error, code == -32_000 {
                throw ACPClientError.authenticationRequired(methods: authenticationMethodNames)
            }
            throw error
        }

        let object = try requiredObject(result, named: "session/new result")
        let decodedSessionID = try validatedSessionID(
            object["sessionId"],
            named: "session/new sessionId")
        sessionID = decodedSessionID
        if restorationWasUnsupported {
            return .freshBecauseRestorationUnsupported(sessionID: decodedSessionID)
        }
        return .new(sessionID: decodedSessionID)
    }

    func loadSession(
        _ restoration: AgentSessionRestorationRequest,
        deliversReplay: Bool,
        onRestoredEvent: @escaping @Sendable (AgentRestorationToken, AgentRunEvent) async -> Void,
        afterResponseValidation: @escaping @Sendable () async -> Void
    ) async throws -> AgentSessionActivation {
        let delivery = AgentRunEventDelivery(mode: .staged) { event in
            await onRestoredEvent(restoration.token, event)
        }
        let state = ACPClientRestorationState(
            token: restoration.token,
            sessionID: restoration.sessionID,
            mode: .load(deliversReplay: deliversReplay),
            delivery: delivery)
        sessionID = restoration.sessionID
        activeRestoration = state

        do {
            let result = try await sendRestorationRequest(
                method: "session/load",
                params: restorationParameters(sessionID: restoration.sessionID),
                state: state)
            _ = try requiredObject(result, named: "session/load result")
            await afterResponseValidation()
            try ensureOpen()
            try Task.checkCancellation()
            guard activeRestoration === state, state.responseWasReceived else {
                throw terminalError ?? ACPClientError.connectionClosed
            }

            if deliversReplay {
                delivery.startConsuming()
                await delivery.finish(.drain)
            } else {
                await delivery.finish(.discard)
            }
            try Task.checkCancellation()
            guard activeRestoration === state else {
                throw terminalError ?? ACPClientError.connectionClosed
            }
            try ensureOpen()
            activeRestoration = nil
            return .loaded(sessionID: restoration.sessionID)
        } catch {
            let detached = detachRestoration(matching: state)
            await discardRestoration(detached)
            throw error
        }
    }

    func resumeSession(
        _ restoration: AgentSessionRestorationRequest,
        afterResponseValidation: @escaping @Sendable () async -> Void
    ) async throws -> AgentSessionActivation {
        let state = ACPClientRestorationState(
            token: restoration.token,
            sessionID: restoration.sessionID,
            mode: .resume)
        sessionID = restoration.sessionID
        activeRestoration = state

        do {
            let result = try await sendRestorationRequest(
                method: "session/resume",
                params: restorationParameters(sessionID: restoration.sessionID),
                state: state)
            _ = try requiredObject(result, named: "session/resume result")
            await afterResponseValidation()
            try ensureOpen()
            try Task.checkCancellation()
            guard activeRestoration === state, state.responseWasReceived else {
                throw terminalError ?? ACPClientError.connectionClosed
            }
            try ensureOpen()
            activeRestoration = nil
            return .resumed(sessionID: restoration.sessionID)
        } catch {
            let detached = detachRestoration(matching: state)
            await discardRestoration(detached)
            throw error
        }
    }

    func restorationParameters(sessionID: String) -> ACPJSONValue {
        .object([
            "sessionId": .string(sessionID),
            "cwd": .string(configuration.workingDirectory),
            "mcpServers": .array([]),
        ])
    }

    func sendRestorationRequest(
        method: String,
        params: ACPJSONValue,
        state: ACPClientRestorationState
    ) async throws -> ACPJSONValue {
        try ensureOpen()
        try Task.checkCancellation()
        let id = try reserveRequestID()
        state.requestID = id
        pendingRequestMethods[id] = method
        pendingRequestStartedAt[id] = DispatchTime.now().uptimeNanoseconds
        diagnostics.record(
            category: .acp,
            event: "acp_client.request_started",
            fields: [
                "connection_id": connectionID.uuidString,
                "request_id": requestIDDescription(id),
                "method": method,
            ])

        do {
            try await write(.request(id: id, method: method, params: params))
            try Task.checkCancellation()
        } catch {
            pendingRequests.removeValue(forKey: id)
            pendingRequestMethods.removeValue(forKey: id)
            pendingRequestStartedAt.removeValue(forKey: id)
            if error is CancellationError {
                throw error
            }
            let failure = ACPClientError.connectionClosed
            finalize(with: failure)
            await terminateTransport()
            throw failure
        }

        return try await waitForResponse(id: id)
    }

    func validatedSessionID(
        _ value: ACPJSONValue?,
        named name: String
    ) throws -> String {
        let identifier = try requiredString(value, named: name)
        guard !identifier.isEmpty,
              identifier.utf8.count <= ACPEventDecoder.maximumOpaqueIdentifierBytes
        else {
            throw ACPClientError.malformedResponse("Invalid session identifier.")
        }
        return identifier
    }

    func detachRestoration(
        matching expected: ACPClientRestorationState? = nil
    ) -> ACPClientRestorationState? {
        guard let current = activeRestoration,
              expected == nil || current === expected
        else {
            return nil
        }
        activeRestoration = nil
        return current
    }

    func discardRestoration(_ state: ACPClientRestorationState?) async {
        guard let state else {
            return
        }
        await state.delivery?.finish(.discard)
    }

    func cancelStartup() async {
        await close()
    }

    func sendRequest(
        method: String,
        params: ACPJSONValue?
    ) async throws -> ACPJSONValue {
        try ensureOpen()
        try Task.checkCancellation()
        let id = try reserveRequestID()
        pendingRequestMethods[id] = method
        pendingRequestStartedAt[id] = DispatchTime.now().uptimeNanoseconds
        diagnostics.record(
            category: .acp,
            event: "acp_client.request_started",
            fields: [
                "connection_id": connectionID.uuidString,
                "request_id": requestIDDescription(id),
                "method": method,
            ])

        do {
            try await write(.request(id: id, method: method, params: params))
            try Task.checkCancellation()
        } catch {
            pendingRequests.removeValue(forKey: id)
            pendingRequestMethods.removeValue(forKey: id)
            pendingRequestStartedAt.removeValue(forKey: id)
            if error is CancellationError {
                throw error
            }
            let failure = ACPClientError.connectionClosed
            finalize(with: failure)
            await terminateTransport()
            throw failure
        }

        return try await waitForResponse(id: id)
    }

    func sendPromptRequest(params: ACPJSONValue?) async throws -> ACPJSONValue {
        try ensureOpen()
        let id = try reserveRequestID()
        activePromptRequestID = id
        pendingRequestMethods[id] = "session/prompt"
        pendingRequestStartedAt[id] = DispatchTime.now().uptimeNanoseconds
        diagnostics.record(
            category: .acp,
            event: "acp_client.request_started",
            fields: [
                "connection_id": connectionID.uuidString,
                "request_id": requestIDDescription(id),
                "method": "session/prompt",
            ])

        do {
            try await write(.request(id: id, method: "session/prompt", params: params))
        } catch {
            pendingRequests.removeValue(forKey: id)
            pendingRequestMethods.removeValue(forKey: id)
            pendingRequestStartedAt.removeValue(forKey: id)
            let failure = ACPClientError.connectionClosed
            finalize(with: failure)
            await terminateTransport()
            throw failure
        }

        promptFrameWasPublished = true
        await sendCancelIfPromptWasPublished()
        return try await waitForResponse(id: id)
    }

    func reserveRequestID() throws -> ACPRequestID {
        guard nextRequestID < Int64.max else {
            throw ACPClientError.connectionClosed
        }

        let id = ACPRequestID.integer(nextRequestID)
        nextRequestID += 1
        pendingRequests[id] = PendingClientRequest()
        return id
    }

    func waitForResponse(id: ACPRequestID) async throws -> ACPJSONValue {
        try await withCheckedThrowingContinuation { continuation in
            guard var pending = pendingRequests[id] else {
                continuation.resume(throwing: terminalError ?? .connectionClosed)
                return
            }

            if let result = pending.bufferedResult {
                pendingRequests.removeValue(forKey: id)
                resume(continuation, with: result)
            } else {
                pending.continuation = continuation
                pendingRequests[id] = pending
            }
        }
    }

}
