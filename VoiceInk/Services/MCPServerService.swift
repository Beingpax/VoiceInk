import Network
import Foundation
import os
import AVFoundation

@MainActor
class DictationSessionManager {
    static let shared = DictationSessionManager()
    
    private var pendingContinuation: CheckedContinuation<String, Never>?
    private var observer: NSObjectProtocol?
    
    func waitForDictation() async -> String {
        // Cancel any previous pending dictation first
        if let prev = pendingContinuation {
            pendingContinuation = nil
            prev.resume(returning: "")
        }
        
        if let obs = observer {
            NotificationCenter.default.removeObserver(obs)
            observer = nil
        }
        
        return await withCheckedContinuation { continuation in
            self.pendingContinuation = continuation
            
            // Set up notification observer for completed transcription
            self.observer = NotificationCenter.default.addObserver(
                forName: .transcriptionCompleted,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                guard let self = self else { return }
                guard let transcription = notification.object as? Transcription else { return }
                
                // Extract final text
                let resultText: String
                if let enhanced = transcription.enhancedText, !enhanced.isEmpty {
                    resultText = enhanced
                } else {
                    resultText = transcription.text
                }
                
                let trimmed = resultText.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed == Transcription.canceledTranscriptionText {
                    self.resumePending(with: "Dictation was canceled.")
                } else {
                    self.resumePending(with: trimmed)
                }
            }
        }
    }
    
    func resumePending(with text: String) {
        if let continuation = pendingContinuation {
            pendingContinuation = nil
            continuation.resume(returning: text)
        }
        if let obs = observer {
            NotificationCenter.default.removeObserver(obs)
            observer = nil
        }
    }
}

class MCPServerService {
    static let shared = MCPServerService()
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "MCPServerService")
    
    private var listener: NWListener?
    private var activeConnections: [UUID: NWConnection] = [:]
    private var sseSessions: [String: UUID] = [:] // session_id -> Connection UUID
    private let queue = DispatchQueue(label: "com.prakashjoshipax.voiceink.mcp", qos: .default)
    
    private init() {}
    
    func start(port: Int) {
        stop()
        
        do {
            let nwPort = NWEndpoint.Port(rawValue: UInt16(port))!
            let params = NWParameters.tcp
            if let ipOpts = params.defaultProtocolStack.internetProtocol as? NWProtocolIP.Options {
                ipOpts.version = .any
            }
            let listener = try NWListener(using: params, on: nwPort)
            self.listener = listener
            
            listener.stateUpdateHandler = { [weak self] state in
                guard let self = self else { return }
                switch state {
                case .ready:
                    self.logger.notice("🚀 MCP Server listening on port \(port)")
                case .failed(let error):
                    self.logger.error("❌ MCP Server failed: \(error.localizedDescription)")
                case .cancelled:
                    self.logger.notice("🛑 MCP Server cancelled")
                default:
                    break
                }
            }
            
            listener.newConnectionHandler = { [weak self] connection in
                self?.handleNewConnection(connection)
            }
            
            listener.start(queue: queue)
        } catch {
            logger.error("❌ Failed to start MCP Server: \(error.localizedDescription)")
        }
    }
    
    func stop() {
        listener?.cancel()
        listener = nil
        
        for (_, conn) in activeConnections {
            conn.cancel()
        }
        activeConnections.removeAll()
        sseSessions.removeAll()
        logger.notice("🛑 MCP Server stopped")
    }
    
    private func handleNewConnection(_ connection: NWConnection) {
        let connectionId = UUID()
        activeConnections[connectionId] = connection
        
        connection.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .failed, .cancelled:
                self.queue.async {
                    self.activeConnections.removeValue(forKey: connectionId)
                    if let key = self.sseSessions.first(where: { $1 == connectionId })?.key {
                        self.sseSessions.removeValue(forKey: key)
                    }
                }
            default:
                break
            }
        }
        
        connection.start(queue: queue)
        readRequest(connectionId: connectionId, connection: connection, accumulatedData: Data())
    }
    
    private func readRequest(connectionId: UUID, connection: NWConnection, accumulatedData: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, context, isComplete, error in
            guard let self = self else { return }
            if let error = error {
                self.logger.error("Receive error: \(error.localizedDescription)")
                connection.cancel()
                return
            }
            
            var newData = accumulatedData
            if let data = data {
                newData.append(data)
            }
            
            if let headersRange = newData.range(of: Data([13, 10, 13, 10])) {
                let headerData = newData.subdata(in: 0..<headersRange.lowerBound)
                let bodyData = newData.subdata(in: headersRange.upperBound..<newData.count)
                
                if let headerStr = String(data: headerData, encoding: .utf8) {
                    self.processRequest(connectionId: connectionId, connection: connection, headerStr: headerStr, bodyData: bodyData, newData: newData)
                } else {
                    self.sendHTTPResponse(connection: connection, statusCode: 400, statusText: "Bad Request", body: "Invalid Headers")
                }
            } else {
                if isComplete {
                    connection.cancel()
                } else {
                    self.readRequest(connectionId: connectionId, connection: connection, accumulatedData: newData)
                }
            }
        }
    }
    
    private func processRequest(connectionId: UUID, connection: NWConnection, headerStr: String, bodyData: Data, newData: Data) {
        let lines = headerStr.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            sendHTTPResponse(connection: connection, statusCode: 400, statusText: "Bad Request", body: "Invalid Request Line")
            return
        }
        
        let requestParts = requestLine.components(separatedBy: " ")
        guard requestParts.count >= 2 else {
            sendHTTPResponse(connection: connection, statusCode: 400, statusText: "Bad Request", body: "Invalid Request Line")
            return
        }
        
        let method = requestParts[0].uppercased()
        let fullPath = requestParts[1]
        
        var contentLength = 0
        for line in lines {
            let parts = line.components(separatedBy: ":")
            if parts.count >= 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" {
                contentLength = Int(parts[1].trimmingCharacters(in: .whitespaces)) ?? 0
                break
            }
        }
        
        if method == "OPTIONS" {
            sendOPTIONSResponse(connection: connection)
            return
        }
        
        if method == "GET" && (fullPath.hasPrefix("/sse") || fullPath == "/") {
            startSSESession(connectionId: connectionId, connection: connection)
            return
        }
        
        if method == "POST" && fullPath.hasPrefix("/message") {
            if bodyData.count < contentLength {
                let remaining = contentLength - bodyData.count
                connection.receive(minimumIncompleteLength: remaining, maximumLength: remaining) { [weak self] moreData, _, isComplete, error in
                    guard let self = self else { return }
                    if let error = error {
                        self.logger.error("Receive body error: \(error.localizedDescription)")
                        connection.cancel()
                        return
                    }
                    var fullBody = bodyData
                    if let moreData = moreData {
                        fullBody.append(moreData)
                    }
                    self.handlePOSTMessage(connection: connection, fullPath: fullPath, bodyData: fullBody)
                }
            } else {
                let actualBody = bodyData.subdata(in: 0..<contentLength)
                handlePOSTMessage(connection: connection, fullPath: fullPath, bodyData: actualBody)
            }
            return
        }
        
        sendHTTPResponse(connection: connection, statusCode: 404, statusText: "Not Found", body: "Not Found")
    }
    
    private func startSSESession(connectionId: UUID, connection: NWConnection) {
        let sessionId = UUID().uuidString.lowercased()
        sseSessions[sessionId] = connectionId
        
        let headers = """
        HTTP/1.1 200 OK\r
        Content-Type: text/event-stream\r
        Cache-Control: no-cache\r
        Connection: keep-alive\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Headers: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        \r
        """
        
        guard let headerData = headers.data(using: .utf8) else {
            connection.cancel()
            return
        }
        
        connection.send(content: headerData, completion: .contentProcessed { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.logger.error("Error sending SSE headers: \(error.localizedDescription)")
                connection.cancel()
                return
            }
            self.sendSSEEvent(connection: connection, event: "endpoint", data: "/message?session_id=\(sessionId)")
        })
    }
    
    private func handlePOSTMessage(connection: NWConnection, fullPath: String, bodyData: Data) {
        let response = """
        HTTP/1.1 200 OK\r
        Content-Type: text/plain\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Headers: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Content-Length: 2\r
        \r
        OK
        """
        if let responseData = response.data(using: .utf8) {
            connection.send(content: responseData, completion: .contentProcessed { _ in })
        }
        
        guard let json = try? JSONSerialization.jsonObject(with: bodyData, options: []) as? [String: Any] else {
            logger.error("Failed to parse POST body as JSON")
            return
        }
        
        guard let urlComponents = URLComponents(string: "http://localhost\(fullPath)"),
              let sessionId = urlComponents.queryItems?.first(where: { $0.name == "session_id" })?.value else {
            logger.error("Missing session_id in message post path")
            return
        }
        
        queue.async { [weak self] in
            self?.processJSONRPC(sessionId: sessionId, request: json)
        }
    }
    
    private func processJSONRPC(sessionId: String, request: [String: Any]) {
        guard let method = request["method"] as? String,
              let id = request["id"] else {
            return
        }
        
        let idString = String(describing: id)
        logger.notice("📥 Received MCP Request: \(method, privacy: .public), id: \(idString, privacy: .public)")
        
        var responseResult: [String: Any]?
        var responseError: [String: Any]?
        
        switch method {
        case "initialize":
            responseResult = [
                "protocolVersion": "2024-11-05",
                "capabilities": [
                    "tools": [:]
                ],
                "serverInfo": [
                    "name": "VoiceInkMCP",
                    "version": "1.0.0"
                ]
            ]
            
        case "tools/list":
            responseResult = [
                "tools": [
                    [
                        "name": "ask_user_dictation",
                        "description": "Prompts the user with specific clarification or verification questions by voice, triggers voice recording, and returns the transcribed user response. Essential when there are critical ambiguities or decisions to make.",
                        "inputSchema": [
                            "type": "object",
                            "properties": [
                                "questions": [
                                    "type": "array",
                                    "items": [
                                        "type": "string"
                                    ],
                                    "description": "The list of questions to present or speak aloud to the user."
                                ]
                            ],
                            "required": ["questions"]
                        ]
                    ]
                ]
            ]
            
        case "tools/call":
            guard let params = request["params"] as? [String: Any],
                  let toolName = params["name"] as? String else {
                responseError = [
                    "code": -32602,
                    "message": "Invalid params"
                ]
                break
            }
            
            if toolName == "ask_user_dictation" {
                let arguments = params["arguments"] as? [String: Any]
                let questions = arguments?["questions"] as? [String] ?? []
                handleDictationToolCall(sessionId: sessionId, requestId: id, questions: questions)
                return
            } else {
                responseError = [
                    "code": -32601,
                    "message": "Tool not found: \(toolName)"
                ]
            }
            
        default:
            responseError = [
                "code": -32601,
                "message": "Method not found: \(method)"
            ]
        }
        
        sendJSONRPCResponse(sessionId: sessionId, id: id, result: responseResult, error: responseError)
    }
    
    private func handleDictationToolCall(sessionId: String, requestId: Any, questions: [String]) {
        Task { @MainActor in
            if UserDefaults.standard.bool(forKey: "speakAIQuestionsAloud") && !questions.isEmpty {
                let fullText = questions.joined(separator: ". ")
                let synthesizer = AVSpeechSynthesizer()
                let utterance = AVSpeechUtterance(string: fullText)
                utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
                synthesizer.speak(utterance)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
            
            if !(RecorderUIManager.shared?.isMiniRecorderVisible ?? false) {
                await RecorderUIManager.shared?.toggleMiniRecorder()
            }
            
            let transcribedResult = await DictationSessionManager.shared.waitForDictation()
            
            let contentItem: [String: Any] = ["type": "text", "text": transcribedResult]
            let result: [String: Any] = ["content": [contentItem]]
            
            self.queue.async { [weak self] in
                self?.sendJSONRPCResponse(sessionId: sessionId, id: requestId, result: result, error: nil)
            }
        }
    }
    
    private func sendJSONRPCResponse(sessionId: String, id: Any, result: [String: Any]?, error: [String: Any]?) {
        var response: [String: Any] = [
            "jsonrpc": "2.0",
            "id": id
        ]
        if let result = result {
            response["result"] = result
        }
        if let error = error {
            response["error"] = error
        }
        
        guard let sseConnId = sseSessions[sessionId],
              let connection = activeConnections[sseConnId] else {
            logger.error("No active SSE connection found for session: \(sessionId)")
            return
        }
        
        guard let jsonData = try? JSONSerialization.data(withJSONObject: response, options: []),
              let jsonStr = String(data: jsonData, encoding: .utf8) else {
            return
        }
        
        sendSSEEvent(connection: connection, event: "message", data: jsonStr)
    }
    
    private func sendSSEEvent(connection: NWConnection, event: String, data: String) {
        let eventString = "event: \(event)\ndata: \(data)\n\n"
        guard let eventData = eventString.data(using: .utf8) else { return }
        
        connection.send(content: eventData, completion: .contentProcessed { [weak self] error in
            if let error = error {
                self?.logger.error("Error sending SSE event: \(error.localizedDescription)")
                connection.cancel()
            }
        })
    }
    
    private func sendOPTIONSResponse(connection: NWConnection) {
        let response = """
        HTTP/1.1 204 No Content\r
        Access-Control-Allow-Origin: *\r
        Access-Control-Allow-Headers: *\r
        Access-Control-Allow-Methods: GET, POST, OPTIONS\r
        Access-Control-Max-Age: 86400\r
        \r
        """
        if let responseData = response.data(using: .utf8) {
            connection.send(content: responseData, completion: .contentProcessed { _ in
                connection.cancel()
            } )
        }
    }
    
    private func sendHTTPResponse(connection: NWConnection, statusCode: Int, statusText: String, body: String) {
        let response = """
        HTTP/1.1 \(statusCode) \(statusText)\r
        Content-Type: text/plain\r
        Access-Control-Allow-Origin: *\r
        Content-Length: \(body.utf8.count)\r
        \r
        \(body)
        """
        if let responseData = response.data(using: .utf8) {
            connection.send(content: responseData, completion: .contentProcessed { _ in
                connection.cancel()
            } )
        }
    }
}
