import SwiftUI

struct TextToSpeechView: View {
    @ObservedObject var viewModel: TTSViewModel

    var body: some View {
        TTSWorkspaceView()
            .environmentObject(viewModel)
    }
}

#Preview {
    TextToSpeechView(viewModel: TTSViewModel())
}
