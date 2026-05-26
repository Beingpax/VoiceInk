import SwiftUI
import AppKit

struct WhisperModelCardView: View {
    let model: WhisperModel
    let isDownloaded: Bool
    let isCurrent: Bool
    let downloadProgress: [String: Double]
    let modelURL: URL?
    let isWarming: Bool
    
    // Actions
    var deleteAction: () -> Void
    var setDefaultAction: () -> Void
    var downloadAction: () -> Void
    
    private var isDownloading: Bool {
        downloadProgress.keys.contains(model.name + "_main") || 
        downloadProgress.keys.contains(model.name + "_coreml")
    }
    
    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            // Leading Premium Gradient Icon
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        colors: [Color.white, Color(red: 0.95, green: 0.95, blue: 0.99)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 48, height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.12), lineWidth: 1.5)
                    )
                
                Image(systemName: "waveform")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(LinearGradient(
                        colors: [Color(red: 0.54, green: 0.12, blue: 0.92), Color(red: 0.28, green: 0.58, blue: 0.95)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
            }
            
            // Main Text Content
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 8) {
                    Text(model.displayName)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                    
                    if model.displayName.contains("Base") {
                        Text("Recommended")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(Color(red: 0.28, green: 0.65, blue: 0.45))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color(red: 0.28, green: 0.65, blue: 0.45).opacity(0.1))
                            .cornerRadius(4)
                    }
                }
                
                // Metadata Row with Dot Ratings
                HStack(spacing: 12) {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                            .font(.system(size: 10))
                        Text(model.language)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))
                    
                    HStack(spacing: 4) {
                        Image(systemName: "internaldrive")
                            .font(.system(size: 10))
                        Text(model.size)
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))
                    
                    // Speed Dots (Green)
                    HStack(spacing: 4) {
                        Text("Speed")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))
                        
                        HStack(spacing: 2) {
                            let speedVal = Int(model.speed * 5)
                            ForEach(0..<5) { idx in
                                Circle()
                                    .fill(idx < speedVal ? Color(red: 0.28, green: 0.65, blue: 0.45) : Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.1))
                                    .frame(width: 5, height: 5)
                            }
                        }
                        
                        Text(String(format: "%.1f", model.speed * 10))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.5))
                    }
                    
                    // Accuracy Dots (Yellow/Orange)
                    HStack(spacing: 4) {
                        Text("Accuracy")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))
                        
                        HStack(spacing: 2) {
                            let accuracyVal = Int(model.accuracy * 5)
                            ForEach(0..<5) { idx in
                                Circle()
                                    .fill(idx < accuracyVal ? Color(red: 0.95, green: 0.65, blue: 0.15) : Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.1))
                                    .frame(width: 5, height: 5)
                            }
                        }
                        
                        Text(String(format: "%.1f", model.accuracy * 10))
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.5))
                    }
                }
                
                Text(model.description)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.5))
                    .lineLimit(1)
                    .padding(.top, 1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            
            Spacer()
            
            // Action Controls
            HStack(spacing: 12) {
                if isCurrent {
                    Text("Default Model")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(red: 0.28, green: 0.65, blue: 0.45))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(red: 0.28, green: 0.65, blue: 0.45).opacity(0.08))
                        .cornerRadius(6)
                } else if isDownloaded {
                    Button(action: setDefaultAction) {
                        Text("Set as Default")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.08))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                } else {
                    Button(action: downloadAction) {
                        HStack(spacing: 6) {
                            Text(isDownloading ? "Downloading..." : "Download")
                                .font(.system(size: 12, weight: .bold))
                            
                            Image(systemName: "arrow.down.circle")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(LinearGradient(
                            colors: [Color(red: 0.36, green: 0.28, blue: 0.88), Color(red: 0.54, green: 0.12, blue: 0.92)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .cornerRadius(8)
                        .shadow(color: Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.2), radius: 4, x: 0, y: 2)
                    }
                    .buttonStyle(.plain)
                    .disabled(isDownloading)
                }
                
                if isDownloaded {
                    Menu {
                        Button(action: deleteAction) {
                            Label("Delete Model", systemImage: "trash")
                        }
                        
                        Button {
                            if let modelURL = modelURL {
                                NSWorkspace.shared.selectFile(modelURL.path, inFileViewerRootedAtPath: "")
                            }
                        } label: {
                            Label("Show in Finder", systemImage: "folder")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))
                            .padding(8)
                            .background(Color.white)
                            .clipShape(Circle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 28, height: 28)
                }
            }
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isCurrent ? Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.15) : Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.04), lineWidth: isCurrent ? 1.5 : 1)
        )
        .shadow(color: Color.black.opacity(0.012), radius: 6, x: 0, y: 2)
    }
}

// MARK: - Imported Whisper Model Card View

struct ImportedWhisperModelCardView: View {
    let model: ImportedWhisperModel
    let isDownloaded: Bool
    let isCurrent: Bool
    let modelURL: URL?

    var deleteAction: () -> Void
    var setDefaultAction: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        colors: [Color.white, Color(red: 0.95, green: 0.95, blue: 0.99)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 48, height: 48)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.12), lineWidth: 1.5)
                    )
                
                Image(systemName: "folder.badge.gearshape")
                    .font(.system(size: 18))
                    .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                Text(model.displayName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                
                Text("Imported local model")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                if isCurrent {
                    Text("Default Model")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(red: 0.28, green: 0.65, blue: 0.45))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(Color(red: 0.28, green: 0.65, blue: 0.45).opacity(0.08))
                        .cornerRadius(6)
                } else if isDownloaded {
                    Button(action: setDefaultAction) {
                        Text("Set as Default")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.08))
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                
                if isDownloaded {
                    Menu {
                        Button(action: deleteAction) {
                            Label("Delete Model", systemImage: "trash")
                        }
                        Button {
                            if let modelURL = modelURL {
                                NSWorkspace.shared.selectFile(modelURL.path, inFileViewerRootedAtPath: "")
                            }
                        } label: {
                            Label("Show in Finder", systemImage: "folder")
                        }
                    } label: {
                        Image(systemName: "ellipsis")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))
                            .padding(8)
                            .background(Color.white)
                            .clipShape(Circle())
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .frame(width: 28, height: 28)
                }
            }
        }
        .padding(14)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isCurrent ? Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.15) : Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.04), lineWidth: isCurrent ? 1.5 : 1)
        )
        .shadow(color: Color.black.opacity(0.012), radius: 6, x: 0, y: 2)
    }
}
