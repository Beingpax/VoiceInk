import SwiftUI

struct VisualSettingsView: View {
    @EnvironmentObject private var recorderUIManager: RecorderUIManager
    
    // Waveform & HUD Customization Storage
    @AppStorage("miniRecorderWidth") private var miniRecorderWidth = 420.0
    @AppStorage("miniRecorderHeight") private var miniRecorderHeight = 180.0
    @AppStorage("visualizerWaveformHeight") private var visualizerWaveformHeight = 75.0
    @AppStorage("visualizerSpeed") private var visualizerSpeed = 1.0
    @AppStorage("visualizerParticleColor") private var visualizerParticleColor = "orange"
    @AppStorage("visualizerParticleShape") private var visualizerParticleShape = "orbiting"
    
    // New Aesthetics Storage
    @AppStorage("miniRecorderPlacement") private var miniRecorderPlacement = "bottom"
    @AppStorage("miniRecorderXOffset") private var miniRecorderXOffset = 0.0
    @AppStorage("miniRecorderYOffset") private var miniRecorderYOffset = 0.0
    @AppStorage("miniRecorderOpacity") private var miniRecorderOpacity = 0.95
    @AppStorage("visualizerMovementType") private var visualizerMovementType = "alien"
    @AppStorage("visualizerLineTheme") private var visualizerLineTheme = "cyber"

    var body: some View {
        Form {
            Section("HUD Frame & Geometry") {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("HUD Panel Width") {
                        HStack {
                            Slider(value: $miniRecorderWidth, in: 360...600, step: 10)
                            Text("\(Int(miniRecorderWidth)) px")
                                .frame(width: 55, alignment: .trailing)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    
                    LabeledContent("HUD Panel Height") {
                        HStack {
                            Slider(value: $miniRecorderHeight, in: 140...300, step: 10)
                            Text("\(Int(miniRecorderHeight)) px")
                                .frame(width: 55, alignment: .trailing)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    
                    LabeledContent("Background Opacity") {
                        HStack {
                            Slider(value: $miniRecorderOpacity, in: 0.1...1.0, step: 0.05)
                            Text(String(format: "%.0f%%", miniRecorderOpacity * 100))
                                .frame(width: 55, alignment: .trailing)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("HUD Screen Placement") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Starting Position", selection: $miniRecorderPlacement) {
                        Text("Top Center").tag("top")
                        Text("Screen Center").tag("center")
                        Text("Bottom Center").tag("bottom")
                    }
                    .pickerStyle(.segmented)
                    
                    LabeledContent("Horizontal Offset (X)") {
                        HStack {
                            Slider(value: $miniRecorderXOffset, in: -500...500, step: 10)
                            Text("\(Int(miniRecorderXOffset)) px")
                                .frame(width: 55, alignment: .trailing)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    
                    LabeledContent("Vertical Offset (Y)") {
                        HStack {
                            Slider(value: $miniRecorderYOffset, in: -500...500, step: 10)
                            Text("\(Int(miniRecorderYOffset)) px")
                                .frame(width: 55, alignment: .trailing)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Waveform Animation") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Movement Style", selection: $visualizerMovementType) {
                        Text("Alien Organic").tag("alien")
                        Text("Classic Sine Ribbon").tag("classic")
                    }
                    .pickerStyle(.segmented)
                    
                    Picker("Color Theme", selection: $visualizerLineTheme) {
                        Text("Cyber Purple").tag("cyber")
                        Text("Sunset Glow").tag("sunset")
                        Text("Matrix Green").tag("matrix")
                        Text("Aurora Borealis").tag("aurora")
                        Text("Monochrome Slate").tag("mono")
                    }
                    
                    LabeledContent("Waveform Height") {
                        HStack {
                            Slider(value: $visualizerWaveformHeight, in: 40...150, step: 5)
                            Text("\(Int(visualizerWaveformHeight)) px")
                                .frame(width: 55, alignment: .trailing)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                    
                    LabeledContent("Wave Velocity (Speed)") {
                        HStack {
                            Slider(value: $visualizerSpeed, in: 0.2...3.0, step: 0.1)
                            Text(String(format: "%.1fx", visualizerSpeed))
                                .frame(width: 55, alignment: .trailing)
                                .font(.system(.body, design: .monospaced))
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Glow Particles") {
                VStack(alignment: .leading, spacing: 10) {
                    Picker("Glow Particle Color", selection: $visualizerParticleColor) {
                        Text("Sci-Fi Orange").tag("orange")
                        Text("Electric Purple").tag("purple")
                        Text("Neon Indigo").tag("indigo")
                        Text("Star White").tag("white")
                    }
                    
                    Picker("Glow Particle Movement", selection: $visualizerParticleShape) {
                        Text("Orbiting Orbit").tag("orbiting")
                        Text("Floating Drift").tag("floating")
                        Text("Breathing Pulse").tag("scaling")
                        Text("Static Matrix").tag("static")
                    }
                }
                .padding(.vertical, 4)
            }

            Section {
                Button("Reset Visual Customizations") {
                    miniRecorderWidth = 420.0
                    miniRecorderHeight = 180.0
                    visualizerWaveformHeight = 75.0
                    visualizerSpeed = 1.0
                    visualizerParticleColor = "orange"
                    visualizerParticleShape = "orbiting"
                    miniRecorderPlacement = "bottom"
                    miniRecorderXOffset = 0.0
                    miniRecorderYOffset = 0.0
                    miniRecorderOpacity = 0.95
                    visualizerMovementType = "alien"
                    visualizerLineTheme = "cyber"
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(Color(NSColor.controlBackgroundColor))
    }
}
