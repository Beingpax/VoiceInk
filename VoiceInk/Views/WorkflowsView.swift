import SwiftUI

struct WorkflowsView: View {
    @EnvironmentObject private var workflowManager: WorkflowManager
    @State private var workflowName: String = ""
    @State private var workflowPrompt: String = ""
    @State private var workflowJsonOutput: String = "{}"
    @State private var workflowShellScriptPath: String = ""
    @State private var selectedWorkflow: Workflow?
    @State private var showDeleteAlert = false
    @State private var isEditing = false
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header
                VStack(alignment: .leading, spacing: 8) {
                    Text("Workflows")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Create and manage custom automation workflows")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                
                Divider()
                
                // Workflow form
                VStack(alignment: .leading, spacing: 16) {
                    Text(isEditing ? "Edit Workflow" : "New Workflow")
                        .font(.headline)
                    
                    // Name
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Name")
                            .font(.headline)
                        
                        TextField("Enter workflow name", text: $workflowName)
                            .textFieldStyle(.roundedBorder)
                    }
                    
                    // Prompt
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Prompt")
                            .font(.headline)
                        
                        TextEditor(text: $workflowPrompt)
                            .font(.body)
                            .padding(8)
                            .frame(height: 120)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                    }
                    
                    // JSON Output template
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Expected JSON Output")
                            .font(.headline)
                        
                        TextEditor(text: $workflowJsonOutput)
                            .font(.body)
                            .padding(8)
                            .frame(height: 120)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.secondary.opacity(0.2), lineWidth: 1)
                            )
                        
                        Text("Define the expected format for the output as JSON")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Shell Script Path
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Shell Script Path")
                            .font(.headline)
                        
                        TextField("Enter absolute path to shell script", text: $workflowShellScriptPath)
                            .textFieldStyle(.roundedBorder)
                        
                        Text("Script will be executed when this workflow is triggered")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    // Buttons
                    HStack {
                        if isEditing {
                            Button("Cancel") {
                                resetForm()
                            }
                            .buttonStyle(.bordered)
                        }
                        
                        Spacer()
                        
                        Button(isEditing ? "Update Workflow" : "Add Workflow") {
                            if isEditing {
                                updateWorkflow()
                            } else {
                                addWorkflow()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(workflowName.isEmpty || workflowPrompt.isEmpty || workflowShellScriptPath.isEmpty)
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(NSColor.controlBackgroundColor))
                )
                
                // Existing workflows section
                if !workflowManager.workflows.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Your Workflows")
                            .font(.headline)
                            .padding(.top, 8)
                        
                        ForEach(workflowManager.workflows) { workflow in
                            WorkflowCard(workflow: workflow) {
                                // Edit action
                                loadWorkflow(workflow)
                            } onDelete: {
                                // Delete action
                                selectedWorkflow = workflow
                                showDeleteAlert = true
                            }
                        }
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "arrow.triangle.branch")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                        
                        Text("No workflows yet")
                            .font(.headline)
                        
                        Text("Create your first workflow to get started")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                }
            }
            .padding(24)
        }
        .alert("Delete Workflow", isPresented: $showDeleteAlert) {
            Button("Cancel", role: .cancel) {}
            Button("Delete", role: .destructive) {
                if let workflow = selectedWorkflow {
                    workflowManager.deleteWorkflow(withID: workflow.id)
                    selectedWorkflow = nil
                }
            }
        } message: {
            Text("Are you sure you want to delete this workflow? This action cannot be undone.")
        }
    }
    
    private func addWorkflow() {
        let newWorkflow = Workflow(
            name: workflowName,
            prompt: workflowPrompt,
            jsonOutput: workflowJsonOutput,
            shellScriptPath: workflowShellScriptPath
        )
        
        workflowManager.addWorkflow(newWorkflow)
        resetForm()
    }
    
    private func updateWorkflow() {
        guard let id = selectedWorkflow?.id else { return }
        
        let updatedWorkflow = Workflow(
            id: id,
            name: workflowName,
            prompt: workflowPrompt,
            jsonOutput: workflowJsonOutput,
            shellScriptPath: workflowShellScriptPath
        )
        
        workflowManager.updateWorkflow(updatedWorkflow)
        resetForm()
    }
    
    private func loadWorkflow(_ workflow: Workflow) {
        selectedWorkflow = workflow
        workflowName = workflow.name
        workflowPrompt = workflow.prompt
        workflowJsonOutput = workflow.jsonOutput
        workflowShellScriptPath = workflow.shellScriptPath
        isEditing = true
    }
    
    private func resetForm() {
        selectedWorkflow = nil
        workflowName = ""
        workflowPrompt = ""
        workflowJsonOutput = "{}"
        workflowShellScriptPath = ""
        isEditing = false
    }
}

struct WorkflowCard: View {
    let workflow: Workflow
    let onEdit: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(workflow.name)
                    .font(.headline)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                            .foregroundColor(.accentColor)
                    }
                    .buttonStyle(.borderless)
                    
                    Button(action: onDelete) {
                        Image(systemName: "trash")
                            .foregroundColor(.red)
                    }
                    .buttonStyle(.borderless)
                }
            }
            
            Divider()
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Prompt:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(workflow.prompt)
                    .font(.body)
                    .lineLimit(3)
                    .truncationMode(.tail)
                
                Text("JSON Output:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text(workflow.jsonOutput)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .lineLimit(3)
                    .truncationMode(.tail)
                
                if !workflow.shellScriptPath.isEmpty {
                    Text("Shell Script:")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    Text(workflow.shellScriptPath)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.textBackgroundColor).opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
    }
}

#Preview {
    WorkflowsView()
        .environmentObject(WorkflowManager.shared)
}