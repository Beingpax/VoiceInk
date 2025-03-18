import Foundation
import Combine
import os

// Helper for JSON decoding
enum JSON: Codable {
    case string(String)
    case number(Double)
    case boolean(Bool)
    case object([String: JSON])
    case array([JSON])
    case null
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        
        if container.decodeNil() {
            self = .null
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let number = try? container.decode(Double.self) {
            self = .number(number)
        } else if let bool = try? container.decode(Bool.self) {
            self = .boolean(bool)
        } else if let object = try? container.decode([String: JSON].self) {
            self = .object(object)
        } else if let array = try? container.decode([JSON].self) {
            self = .array(array)
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Cannot decode JSON value")
        }
    }
    
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        
        switch self {
        case .string(let string):
            try container.encode(string)
        case .number(let number):
            try container.encode(number)
        case .boolean(let bool):
            try container.encode(bool)
        case .object(let object):
            try container.encode(object)
        case .array(let array):
            try container.encode(array)
        case .null:
            try container.encodeNil()
        }
    }
    
    var value: Any {
        switch self {
        case .string(let string): return string
        case .number(let number): return number
        case .boolean(let bool): return bool
        case .null: return NSNull()
        case .array(let array): return array.map { $0.value }
        case .object(let dict): 
            var result: [String: Any] = [:]
            for (key, value) in dict {
                result[key] = value.value
            }
            return result
        }
    }
}

struct WorkflowResponse: Decodable {
    let workflow_id: String
    let workflow_args: [String: Any]
    
    enum CodingKeys: String, CodingKey {
        case workflow_id
        case workflow_args
    }
    
    init(workflow_id: String, workflow_args: [String: Any]) {
        self.workflow_id = workflow_id
        self.workflow_args = workflow_args
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        workflow_id = try container.decode(String.self, forKey: .workflow_id)
        
        // Decode workflow_args as a dictionary
        if let workflowArgsData = try? container.decode(Data.self, forKey: .workflow_args) {
            workflow_args = (try? JSONSerialization.jsonObject(with: workflowArgsData) as? [String: Any]) ?? [:]
        } else if let workflowArgsString = try? container.decode(String.self, forKey: .workflow_args),
                  let data = workflowArgsString.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            workflow_args = json
        } else {
            let workflowArgsDict = try container.decode([String: JSON].self, forKey: .workflow_args)
            var args: [String: Any] = [:]
            
            for (key, value) in workflowArgsDict {
                args[key] = value.value
            }
            
            workflow_args = args
        }
    }
}

struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    
    init(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
    
    init?(intValue: Int) {
        self.stringValue = "\(intValue)"
        self.intValue = intValue
    }
}

class WorkflowManager: ObservableObject {
    static let shared = WorkflowManager()
    
    private let logger = Logger(
        subsystem: "com.prakashjoshipax.VoiceInk",
        category: "workflow"
    )
    
    @Published var workflows: [Workflow] = []
    
    private let workflowsKey = "VoiceInkWorkflows"
    
    private init() {
        loadWorkflows()
    }
    
    // MARK: - Workflow Management
    
    func addWorkflow(_ workflow: Workflow) {
        workflows.append(workflow)
        saveWorkflows()
    }
    
    func updateWorkflow(_ workflow: Workflow) {
        if let index = workflows.firstIndex(where: { $0.id == workflow.id }) {
            workflows[index] = workflow
            saveWorkflows()
        }
    }
    
    func deleteWorkflow(withID id: UUID) {
        workflows.removeAll { $0.id == id }
        saveWorkflows()
    }
    
    func getWorkflow(withID id: UUID) -> Workflow? {
        return workflows.first { $0.id == id }
    }
    
    // MARK: - Workflow Execution
    
    func executeWorkflow(fromResponse jsonResponse: String) {
        logger.notice("🧬 Attempting to execute workflow from response: \(jsonResponse, privacy: .public)")
        
        // Try to parse the JSON response
        guard let jsonData = jsonResponse.data(using: .utf8) else {
            logger.error("❌ Failed to convert response to data")
            return
        }
        
        do {
            // First attempt to parse as a WorkflowResponse
            if let workflowResponse = try? JSONDecoder().decode(WorkflowResponse.self, from: jsonData) {
                processWorkflowResponse(workflowResponse)
            } else {
                // If that fails, try to parse as a generic JSON dictionary
                if let jsonDict = try JSONSerialization.jsonObject(with: jsonData) as? [String: Any],
                   let workflowId = jsonDict["workflow_id"] as? String,
                   let workflowArgs = jsonDict["workflow_args"] as? [String: Any] {
                    
                    let response = WorkflowResponse(workflow_id: workflowId, workflow_args: workflowArgs)
                    processWorkflowResponse(response)
                } else {
                    logger.error("❌ JSON structure doesn't match expected format")
                }
            }
        } catch {
            logger.error("❌ Error parsing workflow response: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    private func processWorkflowResponse(_ response: WorkflowResponse) {
        logger.notice("🧬 Processing workflow response with ID: \(response.workflow_id, privacy: .public)")
        
        // Extract the numeric part of the workflow_id (e.g., "w1" -> 1)
        guard let workflowIndex = Int(response.workflow_id.dropFirst(1)) else {
            logger.error("❌ Invalid workflow ID format: \(response.workflow_id, privacy: .public)")
            return
        }
        
        // Adjust for 1-based indexing used in the workflow IDs
        let arrayIndex = workflowIndex - 1
        
        // Check if the index is valid
        guard arrayIndex >= 0 && arrayIndex < workflows.count else {
            logger.error("❌ Workflow index out of bounds: \(arrayIndex, privacy: .public)")
            return
        }
        
        // Get the corresponding workflow
        let workflow = workflows[arrayIndex]
        logger.notice("🧬 Found workflow: \(workflow.name, privacy: .public)")
        
        // Get the shell script path and execute it
        if workflow.shellScriptPath.isEmpty {
            logger.error("❌ No shell script path specified for workflow. This is required.")
            return
        }
            
        executeShellScript(workflow: workflow, args: response.workflow_args)
    }
    
    private func executeShellScript(workflow: Workflow, args: [String: Any]) {
        let scriptPath = workflow.shellScriptPath
        
        // Check if the script exists and is executable
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: scriptPath) else {
            logger.error("❌ Shell script does not exist at path: \(scriptPath, privacy: .public)")
            return
        }
        
        // Check if the file is executable
        var isExecutable = false
        do {
            let attributes = try fileManager.attributesOfItem(atPath: scriptPath)
            if let permissions = attributes[.posixPermissions] as? NSNumber {
                isExecutable = (permissions.intValue & 0o100) != 0
            }
        } catch {
            logger.error("❌ Error checking script permissions: \(error.localizedDescription, privacy: .public)")
            return
        }
        
        if !isExecutable {
            logger.error("❌ Shell script is not executable: \(scriptPath, privacy: .public)")
            return
        }
        
        // Prepare environment variables for the script
        var environment = ProcessInfo.processInfo.environment
        
        // Create a serializable version of the args
        var serializableArgs: [String: Any] = [:]
        for (key, value) in args {
            if value is String || value is NSNumber || value is Bool || 
               value is [Any] || value is [String: Any] || value is NSNull {
                serializableArgs[key] = value
            } else if let describable = value as? CustomStringConvertible {
                serializableArgs[key] = describable.description
            } else {
                serializableArgs[key] = "\(value)"
            }
        }
        
        // Serialize workflow_args to JSON
        if let jsonData = try? JSONSerialization.data(withJSONObject: serializableArgs),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            environment["WORKFLOW_ARGS"] = jsonString
            logger.notice("📤 Setting WORKFLOW_ARGS: \(jsonString, privacy: .public)")
        } else {
            logger.error("❌ Failed to serialize workflow args to JSON")
        }
        
        // Set individual argument environment variables
        for (key, value) in args {
            let envKey = "WORKFLOW_ARG_\(key.uppercased())"
            
            // Convert value to string
            let stringValue: String
            if let stringValue1 = value as? String {
                // If it's a string, use it directly
                stringValue = stringValue1
            } else if let boolValue = value as? Bool {
                // If it's a boolean, convert to string
                stringValue = boolValue ? "true" : "false"
            } else if let numberValue = value as? NSNumber {
                // If it's a number, convert to string
                stringValue = numberValue.stringValue
            } else if let arrayValue = value as? [Any], let jsonData = try? JSONSerialization.data(withJSONObject: arrayValue, options: []),
                      let jsonString = String(data: jsonData, encoding: .utf8) {
                // If it's an array, convert to JSON string
                stringValue = jsonString
            } else if let dictValue = value as? [String: Any], let jsonData = try? JSONSerialization.data(withJSONObject: dictValue, options: []),
                      let jsonString = String(data: jsonData, encoding: .utf8) {
                // If it's a dictionary, convert to JSON string
                stringValue = jsonString
            } else if let value = value as? CustomStringConvertible {
                stringValue = value.description
            } else {
                stringValue = "\(value)"
            }
            
            environment[envKey] = stringValue
            logger.notice("📤 Setting \(envKey, privacy: .public): \(stringValue, privacy: .public)")
        }
        
        // Create and configure the process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [scriptPath]
        process.environment = environment
        
        // Set up pipes for stdout and stderr
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        do {
            logger.notice("🚀 Executing shell script: \(scriptPath, privacy: .public)")
            try process.run()
            
            // Read the output
            let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            if let output = String(data: outputData, encoding: .utf8), !output.isEmpty {
                logger.notice("📤 Script output: \(output, privacy: .public)")
            }
            
            // Read the error
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            if let error = String(data: errorData, encoding: .utf8), !error.isEmpty {
                logger.error("❌ Script error: \(error, privacy: .public)")
            }
            
            process.waitUntilExit()
            
            let status = process.terminationStatus
            if status == 0 {
                logger.notice("✅ Script executed successfully")
            } else {
                logger.error("❌ Script failed with status: \(status, privacy: .public)")
            }
        } catch {
            logger.error("❌ Failed to execute script: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    // MARK: - Persistence
    
    private func saveWorkflows() {
        do {
            let data = try JSONEncoder().encode(workflows)
            UserDefaults.standard.set(data, forKey: workflowsKey)
        } catch {
            print("Error saving workflows: \(error.localizedDescription)")
        }
    }
    
    private func loadWorkflows() {
        guard let data = UserDefaults.standard.data(forKey: workflowsKey) else {
            // No saved workflows, initialize with empty array
            workflows = []
            return
        }
        
        do {
            workflows = try JSONDecoder().decode([Workflow].self, from: data)
        } catch {
            print("Error loading workflows: \(error.localizedDescription)")
            workflows = []
        }
    }
}