import SwiftUI

struct TrialMessageView: View {
    let message: String
    let type: MessageType
    var onAddLicenseKey: (() -> Void)? = nil
    
    enum MessageType {
        case licenseRequired
        case warning
        case expired
        case info
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 20))
                .foregroundColor(iconColor)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button(action: {
                    onAddLicenseKey?()
                }) {
                    Text("Enter License")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.bordered)

                Button(action: {
                    if let url = URL(string: "https://tryvoiceink.com/buy") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Text("Buy License")
                        .font(.system(size: 13, weight: .medium))
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(AppCardBackground(cornerRadius: 16))
    }
    
    private var icon: String {
        switch type {
        case .licenseRequired: return "checkmark.seal.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .expired: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        }
    }
    
    private var iconColor: Color {
        AppTheme.Text.secondary
    }
    
    private var title: String {
        switch type {
        case .licenseRequired: return "License Required"
        case .warning: return "Trial Ending Soon"
        case .expired: return "Trial Expired"
        case .info: return "Trial Active"
        }
    }
    
}
