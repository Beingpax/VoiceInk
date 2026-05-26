import Foundation
import Network
import Combine
import OSLog

struct AgentPeer: Identifiable, Codable, Hashable {
    var id: String
    var name: String
    var status: String
    var lastActive: Date
    var role: String
}

struct AgentMessage: Identifiable, Codable, Hashable {
    var id: String = UUID().uuidString
    var senderId: String
    var senderName: String
    var recipientId: String // "all" or specific agent ID
    var content: String
    var timestamp: Date
}

enum RedisConnectionState: Equatable {
    case disconnected
    case connecting
    case connected
    case error(String)
}

class AgentBusService: ObservableObject {
    static let shared = AgentBusService()
    private let logger = Logger(subsystem: "com.prakashjoshipax.voiceink", category: "AgentBusService")
    
    @Published var connectionState: RedisConnectionState = .disconnected
    @Published var activePeers: [AgentPeer] = []
    @Published var messages: [AgentMessage] = []
    
    private var commandConnection: NWConnection?
    private var subConnection: NWConnection?
    private var isConnected = false
    
    private var heartbeatTimer: Timer?
    private var pollTimer: Timer?
    
    private let redisHost = "127.0.0.1"
    private let redisPort: UInt16 = 6379
    private let agentId = "voiceink-agent"
    private let agentName = "VoiceInk Mac Client"
    private let agentRole = "Speech-to-Text & UI Controller"
    
    private init() {
        connect()
    }
    
    func connect() {
        guard connectionState != .connecting && connectionState != .connected else { return }
        
        logger.notice("🔌 Initializing connection to local Redis Agent Bus on \(self.redisHost):\(self.redisPort)")
        connectionState = .connecting
        
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(redisHost), port: NWEndpoint.Port(rawValue: redisPort)!)
        let params = NWParameters.tcp
        
        // 1. Establish Command Connection
        let cmdConn = NWConnection(to: endpoint, using: params)
        commandConnection = cmdConn
        
        cmdConn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.logger.notice("✓ Command connection established!")
                self.setupSubscription()
            case .failed(let error):
                self.logger.error("❌ Command connection failed: \(error.localizedDescription, privacy: .public)")
                self.handleDisconnect(errorMsg: error.localizedDescription)
            case .cancelled:
                self.logger.notice("Command connection cancelled.")
            default:
                break
            }
        }
        cmdConn.start(queue: .global(qos: .userInitiated))
    }
    
    private func setupSubscription() {
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(redisHost), port: NWEndpoint.Port(rawValue: redisPort)!)
        let params = NWParameters.tcp
        
        let subConn = NWConnection(to: endpoint, using: params)
        subConnection = subConn
        
        subConn.stateUpdateHandler = { [weak self] state in
            guard let self = self else { return }
            switch state {
            case .ready:
                self.logger.notice("✓ Subscription connection established! Subscribing to channels...")
                self.subscribeToChannels()
            case .failed(let error):
                self.logger.error("❌ Subscription connection failed: \(error.localizedDescription, privacy: .public)")
                self.handleDisconnect(errorMsg: error.localizedDescription)
            case .cancelled:
                self.logger.notice("Subscription connection cancelled.")
            default:
                break
            }
        }
        subConn.start(queue: .global(qos: .userInitiated))
    }
    
    private func subscribeToChannels() {
        let subCommand = formatRESP(["SUBSCRIBE", "agent:bus:broadcast", "agent:bus:agent:\(agentId)"])
        guard let data = subCommand.data(using: .utf8) else { return }
        
        subConnection?.send(content: data, completion: .contentProcessed({ [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.logger.error("❌ Failed to send subscribe command: \(error.localizedDescription, privacy: .public)")
                self.handleDisconnect(errorMsg: error.localizedDescription)
                return
            }
            
            Task { @MainActor in
                self.connectionState = .connected
                self.isConnected = true
            }
            
            self.startTimers()
            self.receiveLoop()
            self.publishPresence()
            self.fetchPeers()
        }))
    }
    
    private func receiveLoop() {
        subConnection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, isComplete, error in
            guard let self = self else { return }
            
            if let data = data, !data.isEmpty {
                self.parseAndHandleSubscriptionData(data)
            }
            
            if isComplete || error != nil {
                self.handleDisconnect(errorMsg: error?.localizedDescription ?? "Subscription connection closed.")
            } else {
                self.receiveLoop()
            }
        }
    }
    
    private func parseAndHandleSubscriptionData(_ data: Data) {
        guard let string = String(data: data, encoding: .utf8) else { return }
        let lines = string.components(separatedBy: "\r\n")
        
        var index = 0
        while index < lines.count {
            let line = lines[index]
            if line.hasPrefix("*3") {
                if index + 6 < lines.count {
                    let type = lines[index + 2]
                    let channel = lines[index + 4]
                    let content = lines[index + 6]
                    
                    if type == "message" {
                        handleIncomingRawMessage(content, onChannel: channel)
                    }
                }
                index += 7
            } else {
                index += 1
            }
        }
    }
    
    private func handleIncomingRawMessage(_ rawString: String, onChannel channel: String) {
        guard let jsonData = rawString.data(using: .utf8) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        do {
            let message = try decoder.decode(AgentMessage.self, from: jsonData)
            Task { @MainActor in
                if !self.messages.contains(where: { $0.id == message.id }) {
                    self.messages.append(message)
                }
            }
        } catch {
            // Fallback for simple plaintext messages from other CLI tools
            let message = AgentMessage(
                senderId: "unknown",
                senderName: channel.contains("voiceink") ? "Private Message" : "Agent Broadcast",
                recipientId: channel.contains("voiceink") ? agentId : "all",
                content: rawString,
                timestamp: Date()
            )
            Task { @MainActor in
                self.messages.append(message)
            }
        }
    }
    
    func sendMessage(_ text: String, recipientId: String = "all") {
        let message = AgentMessage(
            senderId: agentId,
            senderName: agentName,
            recipientId: recipientId,
            content: text,
            timestamp: Date()
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        guard let jsonData = try? encoder.encode(message),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        
        let targetChannel = recipientId == "all" ? "agent:bus:broadcast" : "agent:bus:agent:\(recipientId)"
        let publishCommand = formatRESP(["PUBLISH", targetChannel, jsonString])
        
        guard let data = publishCommand.data(using: .utf8) else { return }
        
        commandConnection?.send(content: data, completion: .contentProcessed({ [weak self] error in
            if let error = error {
                self?.logger.error("❌ Failed to publish message: \(error.localizedDescription, privacy: .public)")
            } else {
                self?.logger.notice("✓ Published message to \(targetChannel, privacy: .public)")
                Task { @MainActor in
                    self?.messages.append(message)
                }
            }
        }))
    }
    
    private func startTimers() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.heartbeatTimer?.invalidate()
            self.pollTimer?.invalidate()
            
            // Presence heartbeat every 5 seconds
            self.heartbeatTimer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
                self?.publishPresence()
            }
            
            // Poll peer list every 7 seconds
            self.pollTimer = Timer.scheduledTimer(withTimeInterval: 7.0, repeats: true) { [weak self] _ in
                self?.fetchPeers()
            }
        }
    }
    
    func publishPresence() {
        let peer = AgentPeer(
            id: agentId,
            name: agentName,
            status: "Online",
            lastActive: Date(),
            role: agentRole
        )
        
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        
        guard let jsonData = try? encoder.encode(peer),
              let jsonString = String(data: jsonData, encoding: .utf8) else { return }
        
        // 1. SET agent presence key with 15 second expire
        let presenceCommand = formatRESP(["SET", "copilot:agent:\(agentId)", jsonString, "EX", "15"])
        guard let presenceData = presenceCommand.data(using: .utf8) else { return }
        commandConnection?.send(content: presenceData, completion: .contentProcessed({ _ in }))
        
        // 2. Refresh active index in Sorted Set
        let score = String(Int(Date().timeIntervalSince1970))
        let indexCommand = formatRESP(["ZADD", "copilot:agents:index", score, "copilot:agent:\(agentId)"])
        guard let indexData = indexCommand.data(using: .utf8) else { return }
        commandConnection?.send(content: indexData, completion: .contentProcessed({ _ in }))
    }
    
    func fetchPeers() {
        let keysCommand = formatRESP(["KEYS", "copilot:agent:*"])
        guard let keysData = keysCommand.data(using: .utf8) else { return }
        
        commandConnection?.send(content: keysData, completion: .contentProcessed({ [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.logger.error("❌ Failed to query active agent keys: \(error.localizedDescription, privacy: .public)")
                return
            }
            
            self.commandConnection?.receive(minimumIncompleteLength: 1, maximumLength: 16384) { [weak self] responseData, _, _, _ in
                guard let self = self, let responseData = responseData else { return }
                let keys = self.parseArrayResponse(responseData)
                guard !keys.isEmpty else {
                    Task { @MainActor in
                        self.activePeers = []
                    }
                    return
                }
                
                // MGET values
                let mgetCommand = self.formatRESP(["MGET"] + keys)
                guard let mgetData = mgetCommand.data(using: .utf8) else { return }
                
                self.commandConnection?.send(content: mgetData, completion: .contentProcessed({ [weak self] mgetError in
                    guard let self = self else { return }
                    if let mgetError = mgetError {
                        self.logger.error("❌ MGET failed: \(mgetError.localizedDescription)")
                        return
                    }
                    
                    self.commandConnection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] mgetRespData, _, _, _ in
                        guard let self = self, let mgetRespData = mgetRespData else { return }
                        let values = self.parseArrayResponse(mgetRespData)
                        
                        var peers: [AgentPeer] = []
                        let decoder = JSONDecoder()
                        decoder.dateDecodingStrategy = .iso8601
                        
                        for value in values {
                            if let valueData = value.data(using: .utf8) {
                                if let peer = try? decoder.decode(AgentPeer.self, from: valueData) {
                                    peers.append(peer)
                                } else if let dict = try? JSONSerialization.jsonObject(with: valueData) as? [String: Any] {
                                    let id = dict["id"] as? String ?? "unknown"
                                    let name = dict["name"] as? String ?? "Agent"
                                    let status = dict["status"] as? String ?? "Active"
                                    let role = dict["role"] as? String ?? "Coordinating"
                                    var date = Date()
                                    if let dateStr = dict["lastActive"] as? String {
                                        let formatter = ISO8601DateFormatter()
                                        date = formatter.date(from: dateStr) ?? Date()
                                    }
                                    peers.append(AgentPeer(id: id, name: name, status: status, lastActive: date, role: role))
                                }
                            }
                        }
                        
                        Task { @MainActor in
                            self.activePeers = peers.filter { $0.id != self.agentId }
                        }
                    }
                }))
            }
        }))
    }
    
    private func handleDisconnect(errorMsg: String) {
        guard isConnected else { return }
        
        logger.warning("⚠️ Disconnected from Redis: \(errorMsg, privacy: .public)")
        
        Task { @MainActor in
            self.connectionState = .error(errorMsg)
            self.isConnected = false
            self.activePeers = []
        }
        
        heartbeatTimer?.invalidate()
        pollTimer?.invalidate()
        
        commandConnection?.cancel()
        subConnection?.cancel()
        
        // Auto-reconnect after 8 seconds
        DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [weak self] in
            self?.connect()
        }
    }
    
    private func formatRESP(_ command: [String]) -> String {
        var resp = "*\(command.count)\r\n"
        for arg in command {
            resp += "$\(arg.utf8.count)\r\n\(arg)\r\n"
        }
        return resp
    }
    
    private func parseArrayResponse(_ data: Data) -> [String] {
        guard let string = String(data: data, encoding: .utf8) else { return [] }
        let lines = string.components(separatedBy: "\r\n")
        guard !lines.isEmpty, lines[0].hasPrefix("*") else { return [] }
        
        var results: [String] = []
        var i = 1
        while i < lines.count {
            let line = lines[i]
            if line.hasPrefix("$") {
                if i + 1 < lines.count {
                    let content = lines[i + 1]
                    if !content.hasPrefix("*") && !content.hasPrefix("$") && !content.isEmpty {
                        results.append(content)
                    }
                }
                i += 2
            } else {
                i += 1
            }
        }
        return results
    }
}
