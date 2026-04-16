import SwiftUI

struct OnboardingView: View {
    @Binding var hasCompletedOnboarding: Bool
    @State private var textOpacity: CGFloat = 0
    @State private var showSecondaryElements = false
    @State private var showPermissions = false
    
    // Animation timing
    private let animationDelay = 0.2
    private let textAnimationDuration = 0.6
    
    var body: some View {
        ZStack {
            GeometryReader { geometry in
                ZStack {
                    // Reusable background
                    OnboardingBackgroundView()
                    
                    // Content container
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(spacing: 0) {
                            // Content Area
                            VStack(spacing: 60) {
                                Spacer()
                                    .frame(height: 40)
                                
                                // Title and subtitle
                                VStack(spacing: 16) {
                                    Text("Welcome to the Future of Typing")
                                        .font(.system(size: min(geometry.size.width * 0.055, 42), weight: .bold, design: .rounded))
                                        .foregroundStyle(.white)
                                        .opacity(textOpacity)
                                        .multilineTextAlignment(.center)
                                        .padding(.horizontal)
                                    
                                    Text("A New Way to Type")
                                        .font(.system(size: min(geometry.size.width * 0.032, 24), weight: .medium, design: .rounded))
                                        .foregroundStyle(.white.opacity(0.7))
                                        .opacity(textOpacity)
                                        .multilineTextAlignment(.center)
                                }
                                
                                if showSecondaryElements {
                                    // Typewriter roles animation
                                    TypewriterRoles()
                                        .frame(height: 160)
                                        .transition(.scale.combined(with: .opacity))
                                        .padding(.horizontal, 40)
                                }
                            }
                            .padding(.top, geometry.size.height * 0.15)
                            
                            Spacer(minLength: geometry.size.height * 0.2)
                            
                            // Bottom navigation
                            if showSecondaryElements {
                                VStack(spacing: 20) {
                                    Button(action: {
                                        withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) {
                                            showPermissions = true
                                        }
                                    }) {
                                        Text("Get Started")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(.black)
                                            .frame(width: min(geometry.size.width * 0.3, 200), height: 50)
                                            .background(Color.white)
                                            .clipShape(.rect(cornerRadius: 25))
                                    }
                                    .buttonStyle(ScaleButtonStyle())
                                    
                                    SkipButton(text: "Skip Tour") {
                                        hasCompletedOnboarding = true
                                    }
                                }
                                .padding(.bottom, 35)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }
                        }
                    }
                }
            }
            
            if showPermissions {
                OnboardingPermissionsView(hasCompletedOnboarding: $hasCompletedOnboarding)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
            }
        }
        .onAppear {
            startAnimations()
        }
    }
    
    private func startAnimations() {
        // Text fade in
        withAnimation(.easeOut(duration: textAnimationDuration).delay(animationDelay)) {
            textOpacity = 1
        }
        
        // Show secondary elements
        DispatchQueue.main.asyncAfter(deadline: .now() + animationDelay * 3) {
            withAnimation(.spring(response: 0.5, dampingFraction: 0.8)) {
                showSecondaryElements = true
            }
        }
    }
}

// MARK: - Supporting Views
struct TypewriterRoles: View {
    private let roles = [
        "Your Writing Assistant",
        "Your Vibe-Coding Assistant",
        "Works Everywhere on Mac with a click",
        "100% offline & private",
       
    ]
    
    @State private var displayedText = ""
    @State private var currentIndex = 0
    @State private var showCursor = true
    @State private var isTyping = false
    @State private var isDeleting = false
    
    // Animation timing
    private let typingSpeed = 0.05  // Time between each character
    private let deleteSpeed = 0.03   // Faster deletion
    private let pauseDuration = 1.0  // How long to show completed text
    private let cursorBlinkSpeed = 0.6
    
    var body: some View {
        VStack {
            HStack(spacing: 0) {
                Text(displayedText)
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.accentColor,
                                Color.accentColor.opacity(0.8),
                                Color.white.opacity(0.9)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                
                // Blinking cursor
                Text("|")
                    .font(.system(size: 42, weight: .bold, design: .rounded))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [
                                Color.accentColor,
                                Color.accentColor.opacity(0.8)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .opacity(showCursor ? 1 : 0)
                    .animation(.easeInOut(duration: cursorBlinkSpeed).repeatForever(), value: showCursor)
            }
            .multilineTextAlignment(.center)
            .shadow(color: Color.accentColor.opacity(0.5), radius: 15, x: 0, y: 0)
            .padding(.horizontal)
        }
        .frame(maxWidth: .infinity)
        .onAppear {
            startTypingAnimation()
            // Start cursor blinking
            withAnimation(.easeInOut(duration: cursorBlinkSpeed).repeatForever()) {
                showCursor.toggle()
            }
        }
    }
    
    private func startTypingAnimation() {
        guard currentIndex < roles.count else { return }
        let targetText = roles[currentIndex]
        isTyping = true
        
        // Type out the text
        var charIndex = 0
        func typeNextCharacter() {
            guard charIndex < targetText.count else {
                // Typing complete, pause then delete
                isTyping = false
                DispatchQueue.main.asyncAfter(deadline: .now() + pauseDuration) {
                    startDeletingAnimation()
                }
                return
            }
            
            let nextChar = String(targetText[targetText.index(targetText.startIndex, offsetBy: charIndex)])
            displayedText += nextChar
            charIndex += 1
            
            // Schedule next character
            DispatchQueue.main.asyncAfter(deadline: .now() + typingSpeed) {
                typeNextCharacter()
            }
        }
        
        typeNextCharacter()
    }
    
    private func startDeletingAnimation() {
        isDeleting = true
        
        func deleteNextCharacter() {
            guard !displayedText.isEmpty else {
                isDeleting = false
                currentIndex = (currentIndex + 1) % roles.count
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    startTypingAnimation()
                }
                return
            }
            
            displayedText.removeLast()
            
            // Schedule next deletion
            DispatchQueue.main.asyncAfter(deadline: .now() + deleteSpeed) {
                deleteNextCharacter()
            }
        }
        
        deleteNextCharacter()
    }
}

struct SkipButton: View {
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.2))
        }
        .buttonStyle(.plain)
    }
}

struct OnboardingBackgroundView: View {
    @State private var glowOpacity: CGFloat = 0
    @State private var glowScale: CGFloat = 0.8
    @State private var particlesActive = false
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Base background with black gradient
                Color.black
                    .overlay(
                        LinearGradient(
                            colors: [
                                Color.black,
                                Color.black.opacity(0.8),
                                Color.black.opacity(0.6)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                
                // Animated glow effect
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: min(geometry.size.width, geometry.size.height) * 0.4)
                    .blur(radius: 100)
                    .opacity(glowOpacity)
                    .scaleEffect(glowScale)
                    .position(
                        x: geometry.size.width * 0.5,
                        y: geometry.size.height * 0.3
                    )
                
                // Enhanced particles with reduced opacity
                ParticlesView(isActive: $particlesActive)
                    .opacity(0.2)
                    .drawingGroup()
            }
        }
        .onAppear {
            startAnimations()
        }
    }
    
    private func startAnimations() {
        // Glow animation
        withAnimation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true)) {
            glowOpacity = 0.3
            glowScale = 1.2
        }
        
        // Start particles
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            particlesActive = true
        }
    }
}

// MARK: - Particles
struct ParticlesView: View {
    @Binding var isActive: Bool
    let particleCount = 60 // Increased particle count
    
    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let timeOffset = timeline.date.timeIntervalSinceReferenceDate
                
                for i in 0..<particleCount {
                    let position = particlePosition(index: i, time: timeOffset, size: size)
                    let opacity = particleOpacity(index: i, time: timeOffset)
                    let scale = particleScale(index: i, time: timeOffset)
                    
                    context.opacity = opacity
                    context.fill(
                        Circle().path(in: CGRect(
                            x: position.x - scale/2,
                            y: position.y - scale/2,
                            width: scale,
                            height: scale
                        )),
                        with: .color(.white)
                    )
                }
            }
        }
        .opacity(isActive ? 1 : 0)
    }
    
    private func particlePosition(index: Int, time: TimeInterval, size: CGSize) -> CGPoint {
        let relativeIndex = Double(index) / Double(particleCount)
        let speed = 0.3 // Slower, more graceful movement
        let radius = min(size.width, size.height) * 0.45
        
        let angle = time * speed + relativeIndex * .pi * 4
        let x = sin(angle) * radius + size.width * 0.5
        let y = cos(angle * 0.5) * radius + size.height * 0.5
        
        return CGPoint(x: x, y: y)
    }
    
    private func particleOpacity(index: Int, time: TimeInterval) -> Double {
        let relativeIndex = Double(index) / Double(particleCount)
        return (sin(time + relativeIndex * .pi * 2) + 1) * 0.3 // Reduced opacity for subtlety
    }
    
    private func particleScale(index: Int, time: TimeInterval) -> CGFloat {
        let relativeIndex = Double(index) / Double(particleCount)
        let baseScale: CGFloat = 3
        return baseScale + sin(time * 2 + relativeIndex * .pi) * 2
    }
}

// MARK: - Button Style
struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Preview
#Preview {
    OnboardingView(hasCompletedOnboarding: .constant(false))
} 

