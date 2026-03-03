import SwiftUI

// Style Constants for consistent styling across components
struct StyleConstants {
    // Colors - Glassmorphism Style
    static let cardGradient = LinearGradient( // Simulates frosted glass
        gradient: Gradient(stops: [
            .init(color: Color(NSColor.windowBackgroundColor).opacity(0.6), location: 0.0),
            .init(color: Color(NSColor.windowBackgroundColor).opacity(0.55), location: 0.70), // Hold start opacity longer
            .init(color: Color(NSColor.windowBackgroundColor).opacity(0.3), location: 1.0)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let cardGradientSelected = LinearGradient( // Selected glass, accent tint extends further
        gradient: Gradient(stops: [
            .init(color: Color.accentColor.opacity(0.3), location: 0.0),
            .init(color: Color.accentColor.opacity(0.25), location: 0.70), // Accent tint held longer
            .init(color: Color(NSColor.windowBackgroundColor).opacity(0.4), location: 1.0) // Blend to window bg at the end
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // Border Colors - Adaptive and subtle for glass effect
    static let cardBorder = LinearGradient(
        gradient: Gradient(colors: [
            Color(NSColor.quaternaryLabelColor).opacity(0.5), // Adaptive border color
            Color(NSColor.quaternaryLabelColor).opacity(0.3)  // Adaptive border color
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    static let cardBorderSelected = LinearGradient(
        gradient: Gradient(colors: [
            Color.accentColor.opacity(0.4),
            Color.accentColor.opacity(0.2)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
    
    // Shadows - Adaptive, soft and diffuse for a floating glass look
    static let shadowDefault = Color(NSColor.shadowColor).opacity(0.1)
    static let shadowSelected = Color(NSColor.shadowColor).opacity(0.15)
    
    // Corner Radius - Larger for a softer, glassy feel
    static let cornerRadius: CGFloat = 16
    
    // Button Style (Keeping this as is unless specified)
    static let buttonGradient = LinearGradient(
        colors: [Color.accentColor, Color.accentColor.opacity(0.8)],
        startPoint: .leading,
        endPoint: .trailing
    )
}

// Reusable background component
struct CardBackground: View {
    var isSelected: Bool
    var cornerRadius: CGFloat = StyleConstants.cornerRadius
    var useAccentGradientWhenSelected: Bool = false // This might need rethinking for pure glassmorphism
    
    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(
                useAccentGradientWhenSelected && isSelected ? 
                    StyleConstants.cardGradientSelected :
                    StyleConstants.cardGradient
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(
                        isSelected ? StyleConstants.cardBorderSelected : StyleConstants.cardBorder,
                        lineWidth: 1.5 // Slightly thicker border for a defined glass edge
                    )
            )
            .shadow(
                color: isSelected ? StyleConstants.shadowSelected : StyleConstants.shadowDefault,
                radius: isSelected ? 15 : 10, // Larger radius for softer, more diffuse shadows
                x: 0,
                y: isSelected ? 8 : 5      // Slightly more y-offset for a lifted look
            )
    }
} 