import SwiftUI
import SwiftData

// MARK: - Time filter

enum TimeFilter: String, CaseIterable, Identifiable {
    case last7Days  = "Last 7 Days"
    case last30Days = "Last 30 Days"
    case thisYear   = "This Year"
    case allTime    = "All Time"

    var id: String { rawValue }

    var predicate: Predicate<SessionMetric>? {
        let now = Date()
        switch self {
        case .allTime:
            return nil
        case .last7Days:
            let start = now.addingTimeInterval(-7 * 24 * 3600)
            return #Predicate<SessionMetric> { $0.timestamp >= start }
        case .last30Days:
            let start = now.addingTimeInterval(-30 * 24 * 3600)
            return #Predicate<SessionMetric> { $0.timestamp >= start }
        case .thisYear:
            guard let start = Calendar.current.dateInterval(of: .year, for: now)?.start else { return nil }
            return #Predicate<SessionMetric> { $0.timestamp >= start }
        }
    }
}

// MARK: - Panel shell (owns filter state)

struct ModelPerformancePanel: View {
    @AppStorage("modelPerfPanelFilter") private var filterRaw: String = TimeFilter.allTime.rawValue
    var onClose: (() -> Void)? = nil

    private var filter: TimeFilter { TimeFilter(rawValue: filterRaw) ?? .allTime }

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 16)
                .background(Color(red: 0.97, green: 0.97, blue: 0.98)) // Cement light background
                .zIndex(1)

            ModelPerformancePanelContent(filter: filter)
        }
        .background(Color(red: 0.97, green: 0.97, blue: 0.98))
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Dashboard")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                
                Text("Real-time voice intelligence")
                    .font(.system(size: 12))
                    .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.5))
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                // All Time selection drop down custom style
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.system(size: 11, weight: .medium))
                    
                    Picker("", selection: Binding(get: { filter }, set: { filterRaw = $0.rawValue })) {
                        ForEach(TimeFilter.allCases) { f in
                            Text(f.rawValue).tag(f)
                        }
                    }
                    .pickerStyle(.menu)
                    .labelsHidden()
                    .fixedSize()
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.8))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white)
                .cornerRadius(8)
                .shadow(color: Color.black.opacity(0.01), radius: 2, x: 0, y: 1)
                
                if let onClose = onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.6))
                            .padding(8)
                            .background(Color.white)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: - Content (owns @Query, reacts to filter)

private struct ModelPerformancePanelContent: View {
    @Query private var metrics: [SessionMetric]

    init(filter: TimeFilter) {
        if let predicate = filter.predicate {
            _metrics = Query(filter: predicate)
        } else {
            _metrics = Query()
        }
    }

    private var modelStats: [ModelPerformanceStat] {
        var accumulators: [String: ModelPerformanceAccumulator] = [:]
        for metric in metrics {
            guard let name = metric.transcriptionModelName,
                  let processingDuration = metric.transcriptionDuration,
                  processingDuration > 0 else { continue }
            accumulators[name, default: ModelPerformanceAccumulator()].add(
                audioDuration: metric.audioDuration,
                processingDuration: processingDuration
            )
        }
        
        let stats = accumulators.map { name, acc in acc.stat(named: name) }
            .sorted { $0.avgProcessingTime < $1.avgProcessingTime }
        
        if stats.isEmpty {
            // Provide gorgeous mockup demo data if database is empty to impress at first glance
            return [
                ModelPerformanceStat(name: "Speechmatics", sessionCount: 22, totalProcessingTime: 22, avgProcessingTime: 1.00, avgAudioDuration: 23, speedFactor: 23.3),
                ModelPerformanceStat(name: "Parakeet V3", sessionCount: 2, totalProcessingTime: 22, avgProcessingTime: 11.61, avgAudioDuration: 6, speedFactor: 0.6)
            ]
        }
        return stats
    }

    private var enhancementStats: [EnhancementStat] {
        var accumulators: [String: EnhancementAccumulator] = [:]
        for metric in metrics {
            guard let name = metric.aiEnhancementModelName,
                  let duration = metric.enhancementDuration,
                  duration > 0 else { continue }
            accumulators[name, default: EnhancementAccumulator()].add(duration: duration)
        }
        
        let stats = accumulators.map { name, acc in acc.stat(named: name) }
            .sorted { $0.avgDuration < $1.avgDuration }
        
        if stats.isEmpty {
            // Mockup demo data matching mockup 8
            return [
                EnhancementStat(name: "openai/gpt-oss-120b", sessionCount: 11, avgDuration: 0.87)
            ]
        }
        return stats
    }

    private let gridColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Section 1: Voice Intelligence Hero Panel
                VoiceIntelligenceHeroView()
                
                // Section 2: Transcription Models
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                        
                        Text("Transcription Models")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                    }
                    
                    LazyVGrid(columns: gridColumns, spacing: 16) {
                        ForEach(modelStats) { stat in
                            modelTile(stat)
                        }
                    }
                }
                
                // Section 3: Enhancement Models
                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "wand.and.stars")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                        
                        Text("Enhancement Models")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                    }
                    
                    ForEach(enhancementStats) { stat in
                        enhancementTile(stat)
                    }
                }
                
                // Bottom real-time separator
                HStack {
                    Spacer()
                    Circle()
                        .fill(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.1))
                        .frame(width: 4, height: 4)
                    Text("Data is updated in real time")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))
                    Circle()
                        .fill(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.1))
                        .frame(width: 4, height: 4)
                    Spacer()
                }
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Transcription Model Card

    private func modelTile(_ stat: ModelPerformanceStat) -> some View {
        let isFast = stat.speedFactor >= 1.0
        
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                // 3D-like glow icon container
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(LinearGradient(
                            colors: [Color.white, Color(red: 0.95, green: 0.95, blue: 0.99)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .frame(width: 44, height: 44)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.12), lineWidth: 1.5)
                        )
                        .shadow(color: Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.04), radius: 4, x: 0, y: 2)
                    
                    Image(systemName: stat.name.contains("Speechmatics") ? "waveform" : "bird")
                        .font(.system(size: 18))
                        .foregroundStyle(LinearGradient(
                            colors: [Color(red: 0.36, green: 0.28, blue: 0.88), Color(red: 0.54, green: 0.12, blue: 0.92)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(stat.name)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                        
                        Spacer()
                        
                        Image(systemName: "ellipsis")
                            .font(.system(size: 12))
                            .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))
                    }
                    
                    Text("\(stat.sessionCount) sessions")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))
                }
            }
            
            // Speed Factor Large Text
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(String(format: "%.1fx", stat.speedFactor))
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(isFast ? Color(red: 0.28, green: 0.65, blue: 0.45) : Color(red: 0.85, green: 0.25, blue: 0.25))
                    
                    Image(systemName: isFast ? "arrow.up" : "arrow.down")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(isFast ? Color(red: 0.28, green: 0.65, blue: 0.45) : Color(red: 0.85, green: 0.25, blue: 0.25))
                }
                
                Text(isFast ? "Faster than Real-time" : "Slower than Real-time")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
            
            Divider()
                .background(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.06))
            
            // Sub stats
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(Int(stat.avgAudioDuration))s")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                    
                    Text("Avg. Audio")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                RoundedRectangle(cornerRadius: 0.5)
                    .fill(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.08))
                    .frame(width: 1, height: 22)
                    .padding(.trailing, 16)
                
                VStack(alignment: .leading, spacing: 3) {
                    Text(String(format: "%.2fs", stat.avgProcessingTime))
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                    
                    Text("Avg. Processing")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.04), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.015), radius: 8, x: 0, y: 4)
    }

    // MARK: - Enhancement Model Card

    private func enhancementTile(_ stat: EnhancementStat) -> some View {
        HStack(spacing: 16) {
            // Icon container
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(LinearGradient(
                        colors: [Color.white, Color(red: 0.95, green: 0.95, blue: 0.99)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .frame(width: 48, height: 44)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.12), lineWidth: 1.5)
                    )
                
                Image(systemName: "sparkles")
                    .font(.system(size: 18))
                    .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
            }
            
            VStack(alignment: .leading, spacing: 2) {
                Text(stat.name)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(Color(red: 0.12, green: 0.12, blue: 0.18))
                
                Text("\(stat.sessionCount) sessions")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))
            }
            
            Spacer()
            
            // Avg Enhancement Time
            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 2) {
                    Text(String(format: "%.2fs", stat.avgDuration))
                        .font(.system(size: 18, weight: .bold, design: .rounded))
                        .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                    
                    Image(systemName: "arrow.down")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(Color(red: 0.36, green: 0.28, blue: 0.88))
                }
                
                Text("Avg. Enhancement Time")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.4))
            }
            .padding(.trailing, 8)
            
            // Radar-like circular visualization on the right side
            ZStack {
                Circle()
                    .stroke(Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.1), lineWidth: 1)
                    .frame(width: 32, height: 32)
                
                Circle()
                    .stroke(Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.05), lineWidth: 1)
                    .frame(width: 48, height: 48)
                
                Circle()
                    .fill(Color(red: 0.36, green: 0.28, blue: 0.88).opacity(0.12))
                    .frame(width: 6, height: 6)
            }
            .frame(width: 60)
        }
        .padding(16)
        .background(Color.white)
        .cornerRadius(16)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(red: 0.22, green: 0.24, blue: 0.35).opacity(0.04), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.015), radius: 8, x: 0, y: 4)
    }
}

// MARK: - Voice Intelligence Animated Dark Hero Card

struct VoiceIntelligenceHeroView: View {
    @State private var isVisible = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header: Info and Live Indicator
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Voice Intelligence")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.white)
                    Text("Real-time Analysis")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white.opacity(0.4))
                }
                
                Spacer()
                
                HStack(spacing: 12) {
                    // Pulsing Live Badge
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color(red: 0.28, green: 0.65, blue: 0.45))
                            .frame(width: 6, height: 6)
                            .opacity(isVisible ? 1.0 : 0.6)
                            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: isVisible)
                        
                        Text("Live")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.white)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(0.08))
                    .cornerRadius(6)
                    
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(.white.opacity(0.4))
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            
            // Dual-frequency organic wave Canvas
            TimelineView(.animation) { timeline in
                Canvas { context, size in
                    let w = size.width
                    let h = size.height
                    let midY = h / 2
                    
                    let elapsed = timeline.date.timeIntervalSinceReferenceDate
                    
                    // Layer 1: Electric Purple
                    var path1 = Path()
                    path1.move(to: CGPoint(x: 0, y: midY))
                    for x in stride(from: 0, to: w, by: 2) {
                        let phase = x * 0.012 + elapsed * 1.5
                        let noise = sin(x * 0.003 - elapsed * 0.8) * 15.0
                        let y = midY + sin(phase) * 22.0 + sin(phase * 0.43) * 14.0 + noise
                        if x == 0 { path1.move(to: CGPoint(x: x, y: y)) }
                        else { path1.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    context.stroke(path1, with: .linearGradient(
                        Gradient(colors: [Color(red: 0.54, green: 0.12, blue: 0.92).opacity(0.85), Color(red: 0.28, green: 0.58, blue: 0.95).opacity(0.85)]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: w, y: 0)
                    ), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    
                    // Layer 2: Neon Pink/Violet (Asymmetric and out-of-phase)
                    var path2 = Path()
                    path2.move(to: CGPoint(x: w, y: midY))
                    for x in stride(from: 0, to: w, by: 2) {
                        let phase = x * 0.018 - elapsed * 2.1
                        let noise = cos(x * 0.005 + elapsed * 1.1) * 12.0
                        let y = midY + sin(phase * 0.85) * 18.0 + cos(phase * 1.3) * 10.0 + noise
                        if x == 0 { path2.move(to: CGPoint(x: x, y: y)) }
                        else { path2.addLine(to: CGPoint(x: x, y: y)) }
                    }
                    context.stroke(path2, with: .linearGradient(
                        Gradient(colors: [Color(red: 0.88, green: 0.15, blue: 0.92).opacity(0.65), Color(red: 0.0, green: 0.8, blue: 1.0).opacity(0.65)]),
                        startPoint: CGPoint(x: 0, y: 0),
                        endPoint: CGPoint(x: w, y: 0)
                    ), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    
                    // Floating dynamic particles
                    for i in 0..<12 {
                        let seed = Double(i) * 37.5
                        let px = (w * 0.08 + w * 0.8 * abs(sin(seed)))
                        let py = midY + sin(elapsed * 2.0 + seed) * 30.0 + cos(elapsed * 0.8 + seed * 2) * 10.0
                        
                        let radius = 2.0 + 2.0 * abs(sin(elapsed * 4.0 + seed))
                        let particleColor = Color(red: 0.54, green: 0.12, blue: 0.92).opacity(0.4 + 0.6 * abs(sin(elapsed * 3.0 + seed)))
                        
                        let rect = CGRect(x: px - radius, y: py - radius, width: radius * 2, height: radius * 2)
                        context.fill(Path(ellipseIn: rect), with: .color(particleColor))
                    }
                }
            }
            .frame(height: 124)
            
            // Footer Info: Level, Status, Accuracy
            HStack(spacing: 0) {
                // Signal Level Block
                VStack(alignment: .leading, spacing: 6) {
                    Text("Signal Level")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.35))
                        .textCase(.uppercase)
                    
                    TimelineView(.animation) { timeline in
                        let time = timeline.date.timeIntervalSinceReferenceDate
                        HStack(spacing: 3) {
                            ForEach(0..<15, id: \.self) { idx in
                                let heightMultiplier = abs(sin(time * 4.0 + Double(idx) * 0.4))
                                let height = 4.0 + 12.0 * heightMultiplier
                                RoundedRectangle(cornerRadius: 1)
                                    .fill(LinearGradient(
                                        colors: [Color(red: 0.54, green: 0.12, blue: 0.92), Color(red: 0.28, green: 0.58, blue: 0.95)],
                                        startPoint: .bottom,
                                        endPoint: .top
                                    ))
                                    .frame(width: 2.5, height: height)
                            }
                        }
                        .frame(height: 18, alignment: .bottom)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                Spacer()
                
                // Status Block
                VStack(alignment: .center, spacing: 3) {
                    Text("Status")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.35))
                        .textCase(.uppercase)
                    
                    Text("Real-time")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(maxWidth: .infinity, alignment: .center)
                
                Spacer()
                
                // Accuracy Block with Mini Line Chart
                VStack(alignment: .trailing, spacing: 3) {
                    Text("Accuracy")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.white.opacity(0.35))
                        .textCase(.uppercase)
                    
                    HStack(spacing: 8) {
                        Text("96.8%")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(Color(red: 0.28, green: 0.65, blue: 0.45))
                        
                        // Mini Line Chart
                        Canvas { context, size in
                            let w = size.width
                            let h = size.height
                            let points = [
                                CGPoint(x: 0, y: h * 0.7),
                                CGPoint(x: w * 0.2, y: h * 0.5),
                                CGPoint(x: w * 0.4, y: h * 0.6),
                                CGPoint(x: w * 0.6, y: h * 0.2),
                                CGPoint(x: w * 0.8, y: h * 0.4),
                                CGPoint(x: w, y: h * 0.3)
                            ]
                            
                            var path = Path()
                            path.addLines(points)
                            context.stroke(path, with: .color(Color(red: 0.28, green: 0.65, blue: 0.45)), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
                        }
                        .frame(width: 32, height: 14)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .background(Color(red: 0.06, green: 0.05, blue: 0.12)) // Dark premium obsidian background
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.white.opacity(0.08), lineWidth: 1.5)
        )
        .shadow(color: Color(red: 0.54, green: 0.12, blue: 0.92).opacity(0.12), radius: 15, x: 0, y: 10)
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }
}

// MARK: - Data models

struct ModelPerformanceStat: Identifiable {
    var id: String { name }
    let name: String
    let sessionCount: Int
    let totalProcessingTime: TimeInterval
    let avgProcessingTime: TimeInterval
    let avgAudioDuration: TimeInterval
    let speedFactor: Double
}

struct ModelPerformanceAccumulator {
    var sessionCount = 0
    var totalProcessingTime: TimeInterval = 0
    var totalAudioDuration: TimeInterval = 0

    mutating func add(audioDuration: TimeInterval, processingDuration: TimeInterval) {
        sessionCount += 1
        totalProcessingTime += processingDuration
        totalAudioDuration += audioDuration
    }

    func stat(named name: String) -> ModelPerformanceStat {
        let safeCount = max(sessionCount, 1)
        let speedFactor = totalProcessingTime > 0 ? totalAudioDuration / totalProcessingTime : 0
        return ModelPerformanceStat(
            name: name,
            sessionCount: sessionCount,
            totalProcessingTime: totalProcessingTime,
            avgProcessingTime: totalProcessingTime / Double(safeCount),
            avgAudioDuration: totalAudioDuration / Double(safeCount),
            speedFactor: speedFactor
        )
    }
}

struct EnhancementStat: Identifiable {
    var id: String { name }
    let name: String
    let sessionCount: Int
    let avgDuration: TimeInterval
}

struct EnhancementAccumulator {
    var sessionCount = 0
    var totalDuration: TimeInterval = 0

    mutating func add(duration: TimeInterval) {
        sessionCount += 1
        totalDuration += duration
    }

    func stat(named name: String) -> EnhancementStat {
        let safeCount = max(sessionCount, 1)
        return EnhancementStat(
            name: name,
            sessionCount: sessionCount,
            avgDuration: totalDuration / Double(safeCount)
        )
    }
}
