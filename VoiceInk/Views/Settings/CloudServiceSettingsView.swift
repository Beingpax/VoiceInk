import SwiftUI

struct CloudServiceSettingsView: View {
    @State private var apiKey: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Enter your API Key for the Cloud Transcription Service. This key will be used to authenticate your requests.")
                .font(.subheadline)
                .foregroundColor(.gray)

            TextField("API Key", text: $apiKey)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .disableAutocorrection(true)

            Button("Save API Key") {
                UserDefaults.standard.set(apiKey, forKey: "cloudTranscriptionAPIKey")
                print("API Key saved to UserDefaults.")
                // Optionally, provide user feedback here, like an alert or a temporary message
            }
            .buttonStyle(.borderedProminent) // Using a more prominent style for the save button

            Spacer() // Pushes content to the top
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading) // Make VStack take available space
        .navigationTitle("Cloud Service API Key") // Sets a title if this view is used in a NavigationView
        .onAppear {
            if let savedAPIKey = UserDefaults.standard.string(forKey: "cloudTranscriptionAPIKey") {
                self.apiKey = savedAPIKey
                print("API Key loaded from UserDefaults.")
            } else {
                print("No API Key found in UserDefaults.")
            }
        }
    }
}

#Preview {
    CloudServiceSettingsView()
}
