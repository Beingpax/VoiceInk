import Foundation
import Combine

class WorkflowManager: ObservableObject {
    static let shared = WorkflowManager()
    
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