import SwiftUI
import UIKit
import QuartzCore

private struct VariableWidthStrokeView: View {
    let stroke: Stroke
    let color: Color
    
    var body: some View {
        Canvas { context, _ in
            let pts = stroke.displayPoints
            guard !pts.isEmpty else { return }
            func widthFor(_ pressure: CGFloat, _ speed: CGFloat) -> CGFloat {
                let minW: CGFloat = 8.0
                let maxW: CGFloat = 28.0
                let v0: CGFloat = 1500.0 // characteristic speed (pts/sec)
                let v = max(0.0, speed)
                let factor = 1.0 / (1.0 + v / v0)
                return minW + (maxW - minW) * pressure * factor
            }
            if pts.count == 1 {
                let w = widthFor(pts[0].pressure, pts[0].speed)
                let p = pts[0].location
                let rect = CGRect(x: p.x - w/2, y: p.y - w/2, width: w, height: w)
                context.fill(Path(ellipseIn: rect), with: .color(color))
            } else {
                var prevW: CGFloat = 0
                for i in 1..<pts.count {
                    let p0 = pts[i-1]
                    let p1 = pts[i]
                    let speed = max(0.001, (p0.speed + p1.speed) * 0.5)
                    let pressure = (p0.pressure + p1.pressure) * 0.5
                    var w = widthFor(pressure, speed)
                    if prevW > 0 { w = 0.7 * prevW + 0.3 * w }
                    prevW = w
                    var seg = Path()
                    seg.move(to: p0.location)
                    seg.addLine(to: p1.location)
                    context.stroke(seg, with: .color(color), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
                }
            }
        }
    }
}

private struct TouchCaptureView: UIViewRepresentable {
    var onBegan: (CGPoint, CGFloat) -> Void
    var onMoved: (CGPoint, CGFloat) -> Void
    var onEnded: () -> Void
    
    class TouchView: UIView {
        var onBegan: ((CGPoint, CGFloat) -> Void)?
        var onMoved: ((CGPoint, CGFloat) -> Void)?
        var onEnded: (() -> Void)?
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            isMultipleTouchEnabled = false
            backgroundColor = .clear
        }
        required init?(coder: NSCoder) { super.init(coder: coder) }
        
        override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = touches.first else { return }
            let p = t.type == .pencil ? (t.maximumPossibleForce > 0 ? t.force / t.maximumPossibleForce : 1.0) : 1.0
            let loc = t.location(in: self)
            onBegan?(loc, max(0.0, min(1.0, p)))
        }
        override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
            guard let t = touches.first else { return }
            let p = t.type == .pencil ? (t.maximumPossibleForce > 0 ? t.force / t.maximumPossibleForce : 1.0) : 1.0
            let loc = t.location(in: self)
            onMoved?(loc, max(0.0, min(1.0, p)))
        }
        override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
            onEnded?()
        }
        override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
            onEnded?()
        }
    }
    
    func makeUIView(context: Context) -> TouchView {
        let v = TouchView()
        v.onBegan = onBegan
        v.onMoved = onMoved
        v.onEnded = onEnded
        return v
    }
    
    func updateUIView(_ uiView: TouchView, context: Context) {
        uiView.onBegan = onBegan
        uiView.onMoved = onMoved
        uiView.onEnded = onEnded
    }
}

struct FlashcardPracticeView: View {
    @EnvironmentObject var store: LearningSetsStore
    @StateObject private var viewModel = DrawingViewModel()
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedSetId: UUID? = nil
    @State private var shuffle: Bool = false
    @State private var inSession: Bool = false

    @State private var currentIndex: Int = 0
    @State private var currentPrompt: String = ""
    @State private var currentCharacter: String = ""
    @State private var analysisResult: CharacterAnalysisResult? = nil
    @State private var showFeedback: Bool = false
    @State private var isPerfectCharacter: Bool = false
    @State private var canvasSize: CGFloat = 400  // Actual canvas size for bounding box calculation
    @State private var currentBoundingBox: CGRect? = nil  // Bounding box used for current analysis
    
    // Tunable parameters (baseline algorithm)
    @State private var showSettings: Bool = false
    @AppStorage("boundingBoxSize") private var boundingBoxSize: Double = 0.8  // Persisted size of guide box
    @AppStorage("secondsPerStroke") private var secondsPerStroke: Double = 0.6  // Persisted animation speed
    @AppStorage("errorThreshold") private var errorThreshold: Double = 0.35  // Sensitivity (Fréchet error threshold)
    @State private var replayNonce: Int = 0  // Changing this replays the animation
    @State private var perfectStreakCount: Int = 0
    @State private var sessionAttempted: Set<Int> = []
    @State private var sessionPerfectCount: Int = 0
    @State private var showCongrats: Bool = false
    @State private var snapshotUserStrokes: [Stroke] = []
    @State private var snapshotBoundingBox: CGRect? = nil
    @State private var prevStreakBeforeFinish: Int = 0

    private var selectedSet: LearningSet? {
        if let id = selectedSetId { return store.sets.first { $0.id == id } }
        return store.activeSet
    }

    private var flashcardItems: [FlashcardItem] {
        guard let s = selectedSet, let items = s.items else { return [] }
        return items
    }

    private var setsWithDefinitions: [LearningSet] {
        store.sets.filter { $0.hasDefinitions }
    }

    private var learningSetSelection: Binding<UUID?> {
        Binding(
            get: { selectedSetId ?? store.activeSetId },
            set: { selectedSetId = $0 }
        )
    }

    // MARK: - Setup UI Components
    
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Image(systemName: "tray")
                .font(.system(size: 48))
                .foregroundColor(Color("Neutral 700"))
            Text("No sets with definitions")
                .font(.headline)
                .foregroundColor(Color("Blue 900"))
            Text("Add definitions to a learning set to practice flashcards")
                .font(.subheadline)
                .foregroundColor(Color("Neutral 700"))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }
    
    private var pickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Learning Set")
                .font(.subheadline)
                .foregroundColor(Color("Blue 900"))
            
            Picker("Learning Set", selection: learningSetSelection) {
                ForEach(setsWithDefinitions) { set in
                    Text(set.name).tag(Optional(set.id))
                }
            }
            .pickerStyle(.menu)
            .padding(12)
            .background(Color.white.opacity(0.9))
            .cornerRadius(8)
            
            if let set = selectedSet {
                Text("\(flashcardItems.count) flashcards")
                    .font(.caption)
                    .foregroundColor(Color("Neutral 700"))
            }
        }
    }
    
    private var crosshairOverlay: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            Path { path in
                path.move(to: CGPoint(x: 0, y: h / 2))
                path.addLine(to: CGPoint(x: w, y: h / 2))
                path.move(to: CGPoint(x: w / 2, y: 0))
                path.addLine(to: CGPoint(x: w / 2, y: h))
            }
            .stroke(Color("Blue 700").opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
        }
        .allowsHitTesting(false)
    }
    
    private var shuffleToggle: some View {
        HStack {
            Text("Shuffle cards")
                .foregroundColor(Color("Blue 900"))
            Spacer()
            Toggle("", isOn: $shuffle)
                .labelsHidden()
        }
        .padding(12)
        .background(Color.white.opacity(0.7))
        .cornerRadius(8)
    }
    
    private var startButton: some View {
        Button(action: startSession) {
            Text("Start Practice")
                .font(.headline)
                .foregroundColor(Color("Sand 100"))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color("Blue 700"))
                .cornerRadius(10)
                .shadow(color: Color("Blue 700").opacity(0.3), radius: 8, x: 0, y: 4)
        }
        .disabled(selectedSet?.hasDefinitions != true)
        .opacity(selectedSet?.hasDefinitions == true ? 1.0 : 0.6)
    }
    
    private var setupContentView: some View {
        Group {
            if setsWithDefinitions.isEmpty {
                emptyStateView
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    pickerSection
                    shuffleToggle
                    startButton
                }
            }
        }
    }
    
    private var setupCard: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Setup")
                .font(.title2).bold()
                .foregroundColor(Color("Blue 900"))
            
            setupContentView
        }
        .padding(20)
        .background(Color.white.opacity(0.7))
        .cornerRadius(16)
        .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
        .padding(.horizontal, 24)
    }
    
    private var setupUI: some View {
        ZStack {
            Color(red: 0.68, green: 0.85, blue: 0.9)
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    Text("Flashcard Practice")
                        .font(.system(size: horizontalSizeClass == .compact ? 28 : 40)).bold()
                        .foregroundColor(Color("Blue 900"))
                        .padding(.top, horizontalSizeClass == .compact ? 8 : 20)
                    
                    setupCard
                    
                    Spacer(minLength: 40)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
    }
    
    // MARK: - In-Session UI
    private var inSessionUI: some View {
        VStack(spacing: 0) {                    
                    // Top control bar
                    HStack(spacing: 16) {
                        if !showFeedback {
                            Button(action: { _ = viewModel.undo() }) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.title3)
                                    .foregroundColor(Color("Blue 700"))
                                    .frame(width: 44, height: 44)
                                    .background(Color.white)
                                    .clipShape(Circle())
                                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                            }
                            
                            Button(action: { viewModel.clear() }) {
                                Image(systemName: "trash")
                                    .font(.title3)
                                    .foregroundColor(.red)
                                    .frame(width: 44, height: 44)
                                    .background(Color.white)
                                    .clipShape(Circle())
                                    .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                            }
                        }
                        Button(action: { 
                            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                                showSettings.toggle()
                            }
                        }) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.title3)
                                .foregroundColor(Color("Blue 700"))
                                .frame(width: 44, height: 44)
                                .background(showSettings ? Color("Blue 700").opacity(0.2) : Color.white)
                                .clipShape(Circle())
                                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                        }
                        
                        Spacer()
                        
                        // Definition prompt - centered
                        VStack(spacing: 8) {
                            Text(currentPrompt)
                                .font(.system(size: horizontalSizeClass == .compact ? 18 : 24, weight: .medium))
                                .foregroundColor(Color("Blue 900"))
                                .multilineTextAlignment(.center)
                                .lineLimit(horizontalSizeClass == .compact ? 4 : 3)
                                .minimumScaleFactor(0.7)
                        }
                        .padding(.horizontal, 16)
                        
                        Spacer()
                        
                        // Placeholder for symmetry
                        Color.clear
                            .frame(width: 44, height: 44)
                        
                        Color.clear
                            .frame(width: 44, height: 44)
                    }
                    .padding(.horizontal, horizontalSizeClass == .compact ? 16 : 24)
                    .padding(.vertical, horizontalSizeClass == .compact ? 12 : 16)
                    .background(Color(red: 0.68, green: 0.85, blue: 0.9).opacity(0.3))
                    
                    // Settings shown in a separate sheet now; no inline panel here
                    HStack(spacing: 12) {
                        let total = max(1, flashcardItems.count)
                        ProgressView(value: Double(min(currentIndex, total)), total: Double(total))
                            .accentColor(Color("Blue 700"))
                        Text("\(min(currentIndex + 1, total))/\(total)")
                            .font(.caption.monospacedDigit())
                            .foregroundColor(Color("Blue 900"))
                        Spacer()
                        HStack(spacing: 6) {
                            Image(systemName: "flame.fill")
                                .foregroundColor(.orange)
                            Text("\(perfectStreakCount)")
                                .font(.caption.monospacedDigit())
                                .foregroundColor(Color("Blue 900"))
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.7))
                    // Drawing area for feedback
                    if showFeedback {
                        VStack(spacing: 0) {
                            // Perfect Character Banner
                            if isPerfectCharacter {
                                perfectCharacterBanner
                                    .transition(.move(edge: .top).combined(with: .opacity))
                            }
                            
                            if horizontalSizeClass == .compact {
                                ScrollView {
                                    Group {
                                        let tile = min(UIScreen.main.bounds.width - 48, 400)
                                        VStack(spacing: 20) {
                                            VStack(spacing: 8) {
                                                Text("Your Drawing")
                                                    .font(.headline)
                                                    .foregroundColor(Color("Blue 900"))
                                                
                                                ZStack {
                                                    Color.white
                                                    
                                                    crosshairOverlay
                                                    
                                                    coloredFeedbackCanvas
                                                }
                                                .frame(width: tile, height: tile)
                                                .cornerRadius(12)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(Color("Blue 700"), lineWidth: 2)
                                                )
                                            }
                                            
                                            VStack(spacing: 8) {
                                                Text("True Character")
                                                    .font(.headline)
                                                    .foregroundColor(Color("Blue 900"))
                                                
                                                ZStack {
                                                    Color.white
                                                    
                                                    crosshairOverlay
                                                    
                                                    // Hybrid animation: user's correct strokes + reference for misses
                                                    GeometryReader { geo in
                                                        if let result = analysisResult {
                                                            // Quantize size to reduce layout-churn replays on settings toggle
                                                            let size = floor(min(geo.size.width, geo.size.height) / 8.0) * 8.0
                                                            let duration = max(0.1, Double(result.referenceStrokes.count) * secondsPerStroke)
                                                            ReferenceStrokeMaskAnimationView(
                                                                referenceStrokes: result.referenceStrokes,
                                                                userStrokes: result.userStrokes,
                                                                strokeResults: result.strokeResults,
                                                                originalCanvasSize: canvasSize,
                                                                boundingBox: currentBoundingBox,
                                                                canvasSize: size,
                                                                totalDuration: duration,
                                                                replayNonce: replayNonce,
                                                                pause: showSettings
                                                            )
                                                            .id(replayNonce)
                                                        }
                                                    }
                                                }
                                                .frame(width: tile, height: tile)
                                                .cornerRadius(12)
                                                .overlay(alignment: .topTrailing) {
                                                    Button(action: { replayNonce += 1 }) {
                                                        Image(systemName: "arrow.clockwise")
                                                            .foregroundColor(Color("Blue 700"))
                                                            .padding(8)
                                                            .background(Color.white.opacity(0.9))
                                                            .clipShape(Circle())
                                                            .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
                                                    }
                                                    .padding(6)
                                                }
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(Color("Blue 700"), lineWidth: 2)
                                                )
                                            }
                                            
                                            // Bottom panel: Reference Character
                                            VStack(spacing: 8) {
                                                Text("Reference Character")
                                                    .font(.headline)
                                                    .foregroundColor(Color("Blue 900"))
                                                
                                                ZStack {
                                                    Color.white
                                                    
                                                    crosshairOverlay
                                                    
                                                    trueCharacterCanvas
                                                }
                                                .frame(width: tile, height: tile)
                                                .cornerRadius(12)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: 12)
                                                        .stroke(Color("Blue 700").opacity(0.3), lineWidth: 2)
                                                )
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding(.vertical, 12)
                                    }
                                }
                                .padding(.horizontal, 16)
                            } else {
                                Spacer()
                                
                                // Side-by-side comparison view
                                GeometryReader { outerGeo in
                                    HStack(spacing: 16) {
                                    // Left: User's color-coded strokes
                                    VStack(spacing: 8) {
                                        Text("Your Drawing")
                                            .font(.headline)
                                            .foregroundColor(Color("Blue 900"))
                                        
                                        ZStack {
                                            Color.white
                                            
                                            crosshairOverlay
                                            
                                            coloredFeedbackCanvas
                                        }
                                        .aspectRatio(1.0, contentMode: .fit)
                                        .cornerRadius(12)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color("Blue 700"), lineWidth: 2)
                                        )
                                    }
                                    
                                    // Right: Animated true character (mask-based reveal)
                                    VStack(spacing: 8) {
                                        Text("True Character")
                                            .font(.headline)
                                            .foregroundColor(Color("Blue 900"))
                                        
                                        ZStack {
                                            Color.white
                                            
                                            crosshairOverlay
                                            
                                            // Hybrid animation: user's correct strokes + reference for misses
                                            GeometryReader { geo in
                                                if let result = analysisResult {
                                                    // Quantize size to reduce layout-churn replays on settings toggle
                                                    let size = floor(min(geo.size.width, geo.size.height) / 8.0) * 8.0
                                                    let duration = max(0.1, Double(result.referenceStrokes.count) * secondsPerStroke)
                                                    ReferenceStrokeMaskAnimationView(
                                                        referenceStrokes: result.referenceStrokes,
                                                        userStrokes: result.userStrokes,
                                                        strokeResults: result.strokeResults,
                                                        originalCanvasSize: canvasSize,
                                                        boundingBox: currentBoundingBox,
                                                        canvasSize: size,
                                                        totalDuration: duration,
                                                        replayNonce: replayNonce,
                                                        pause: showSettings
                                                    )
                                                    .id(replayNonce)
                                                }
                                            }
                                        }
                                        .aspectRatio(1.0, contentMode: .fit)
                                        .cornerRadius(12)
                                        .overlay(alignment: .topTrailing) {
                                            Button(action: { replayNonce += 1 }) {
                                                Image(systemName: "arrow.clockwise")
                                                    .foregroundColor(Color("Blue 700"))
                                                    .padding(8)
                                                    .background(Color.white.opacity(0.9))
                                                    .clipShape(Circle())
                                                    .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
                                            }
                                            .padding(6)
                                        }
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 12)
                                                .stroke(Color("Blue 700"), lineWidth: 2)
                                        )
                                    }
                                    }
                                    .padding(.horizontal, outerGeo.size.width * 0.05)
                                    .padding(.top, 150)
                                }
                                
                                Spacer()
                                
                                // Bottom panel: Reference Character
                                VStack(spacing: 8) {
                                    Text("Reference Character")
                                        .font(.headline)
                                        .foregroundColor(Color("Blue 900"))
                                    
                                    ZStack {
                                        Color.white
                                        
                                        crosshairOverlay
                                        
                                        trueCharacterCanvas
                                    }
                                    .frame(width: 150, height: 150)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color("Blue 700").opacity(0.3), lineWidth: 2)
                                    )
                                }
                                .padding(.top, 16)
                                
                                Spacer()
                            }
                        }
                    } else {
                        // Single drawing area when not in feedback mode
                        ZStack {
                            Color.white
                            
                            // Guide box with subtle grid (adjustable size)
                            GeometryReader { geometry in
                                let canvasSize: CGFloat = min(geometry.size.width, geometry.size.height)
                                let boxSize: CGFloat = canvasSize * CGFloat(boundingBoxSize)
                                let centerX = geometry.size.width / 2
                                let centerY = geometry.size.height / 2
                                
                                ZStack {
                                    // Outer box
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color("Blue 700").opacity(0.5), lineWidth: 2)
                                    
                                    // Center cross guides
                                    Path { path in
                                        path.move(to: CGPoint(x: 0, y: boxSize / 2))
                                        path.addLine(to: CGPoint(x: boxSize, y: boxSize / 2))
                                        path.move(to: CGPoint(x: boxSize / 2, y: 0))
                                        path.addLine(to: CGPoint(x: boxSize / 2, y: boxSize))
                                    }
                                    .stroke(Color("Blue 700").opacity(0.2), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                                }
                                .frame(width: boxSize, height: boxSize)
                                .position(x: centerX, y: centerY)
                            }
                            
                            drawingCanvas
                        }
                    }
                    
                    // Bottom action bar and feedback
                    VStack(spacing: 0) {
                        // Feedback display
                        if showFeedback {
                            VStack(spacing: 12) {
                                // Color Legend
                                HStack(spacing: 16) {
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(Color.green)
                                            .frame(width: 12, height: 12)
                                        Text("Correct")
                                            .font(.caption)
                                            .foregroundColor(Color("Blue 900"))
                                    }
                                    
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(Color.yellow)
                                            .frame(width: 12, height: 12)
                                        Text("Wrong Order")
                                            .font(.caption)
                                            .foregroundColor(Color("Blue 900"))
                                    }
                                    
                                    HStack(spacing: 4) {
                                        Circle()
                                            .fill(Color.red)
                                            .frame(width: 12, height: 12)
                                        Text("Incorrect")
                                            .font(.caption)
                                            .foregroundColor(Color("Blue 900"))
                                    }
                                }
                                .padding(.vertical, 8)
                                .padding(.horizontal, 16)
                                .background(Color.white.opacity(0.7))
                                .cornerRadius(8)
                            }
                            .padding(16)
                            .background(Color.white.opacity(0.9))
                            .cornerRadius(12)
                            .padding(.horizontal, 24)
                            .padding(.top, 12)
                        }
                        
                        HStack(spacing: 12) {
                            // Back / Retry button
                            Button(action: {
                                if showFeedback {
                                    // If last attempt was not perfect, restore previous streak
                                    if !isPerfectCharacter {
                                        perfectStreakCount = prevStreakBeforeFinish
                                    }
                                    // Exit feedback to drawing mode for current character
                                    showFeedback = false
                                    analysisResult = nil
                                    isPerfectCharacter = false
                                    currentBoundingBox = nil
                                    viewModel.clear()
                                } else {
                                    previousCard()
                                }
                            }) {
                                HStack {
                                    Image(systemName: "arrow.left")
                                    Text(showFeedback ? "Back to Draw" : "Back")
                                }
                                .font(.headline)
                                .foregroundColor(Color("Blue 700"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.white)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color("Blue 700"), lineWidth: 2)
                                )
                                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                            }
                            .disabled(!showFeedback && !shuffle && currentIndex == 0)
                            .opacity(!showFeedback && !shuffle && currentIndex == 0 ? 0.5 : 1.0)
                            
                            Button(action: finishCharacter) {
                                HStack {
                                    Image(systemName: "checkmark.circle.fill")
                                    Text("Check")
                                }
                                .font(.headline)
                                .foregroundColor(Color("Sand 100"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color("Blue 700"))
                                .cornerRadius(12)
                                .shadow(color: Color("Blue 700").opacity(0.3), radius: 8, x: 0, y: 4)
                            }
                            .disabled(showFeedback)
                            .opacity(showFeedback ? 0.5 : 1.0)
                            
                            Button(action: nextCard) {
                                HStack {
                                    Text("Next")
                                    Image(systemName: "arrow.right")
                                }
                                .font(.headline)
                                .foregroundColor(Color("Blue 700"))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(Color.white)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color("Blue 700"), lineWidth: 2)
                                )
                                .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .background(Color(red: 0.68, green: 0.85, blue: 0.9).opacity(0.3))
                    }
                }
                .overlay( Group { if showCongrats { congratulationsOverlay } })
    }

    var body: some View {
        content
            .onAppear {
                if selectedSetId == nil { selectedSetId = store.activeSetId }
                if !inSession && !flashcardItems.isEmpty {
                    prepareInitialPrompt()
                }
            }
            .sheet(isPresented: $showSettings) { settingsSheet }
            .onChange(of: showSettings) { opened in
                if opened {
                    // Snapshot inputs while entering settings
                    snapshotUserStrokes = analysisResult?.userStrokes ?? viewModel.currentCharacter.strokes
                    snapshotBoundingBox = currentBoundingBox
                } else {
                    // Apply updated settings when the sheet is dismissed
                    guard showFeedback, !currentCharacter.isEmpty else { return }
                    let userStrokes = snapshotUserStrokes.isEmpty ? (analysisResult?.userStrokes ?? viewModel.currentCharacter.strokes) : snapshotUserStrokes
                    let bbox = snapshotBoundingBox ?? currentBoundingBox
                    analysisResult = StrokeAnalyzer.analyzeCharacter(
                        userStrokes: userStrokes,
                        character: currentCharacter,
                        boundingBox: bbox,
                        errorThreshold: errorThreshold
                    )
                    currentBoundingBox = bbox
                    checkIfPerfect()
                    // Rebuild once to ensure the hybrid uses updated matches
                    replayNonce += 1
                }
            }
    }
    
    @ViewBuilder
    private var content: some View {
        if !inSession {
            setupUI
        } else {
            inSessionUI
        }
    }
    
    

    //Canvas and corresponding drawing
    private var drawingCanvas: some View {
        GeometryReader { geometry in
            // Capture canvas size for bounding box calculation
            Color.clear
                .onAppear {
                    let size = min(geometry.size.width, geometry.size.height)
                    if size > 0 {
                        canvasSize = size
                    }
                }
                .onChange(of: geometry.size) { newSize in
                    let size = min(newSize.width, newSize.height)
                    if size > 0 {
                        canvasSize = size
                    }
                }
            
            ForEach(viewModel.currentCharacter.strokes, id: \.id) { stroke in
                VariableWidthStrokeView(stroke: stroke, color: Color.black)
            }
            if let live = viewModel.currentStroke {
                VariableWidthStrokeView(stroke: live, color: Color.black.opacity(0.8))
            }
        }
        .contentShape(Rectangle())
        .overlay(
            TouchCaptureView(
                onBegan: { pt, pressure in
                    if viewModel.currentStroke == nil {
                        viewModel.beginStrokeWithPressure(at: pt, pressure: pressure)
                    } else {
                        viewModel.continueStrokeWithPressure(at: pt, pressure: pressure)
                    }
                },
                onMoved: { pt, pressure in
                    if viewModel.currentStroke == nil {
                        viewModel.beginStrokeWithPressure(at: pt, pressure: pressure)
                    } else {
                        viewModel.continueStrokeWithPressure(at: pt, pressure: pressure)
                    }
                },
                onEnded: {
                    viewModel.endStroke()
                }
            )
        )
    }
    
    // Color-coded feedback canvas
    private var coloredFeedbackCanvas: some View {
        GeometryReader { geometry in
            if let result = analysisResult {
                // Normalize strokes using the same bounding box as the analysis
                let normalizedStrokes = StrokeAnalyzer.normalizeUserStrokes(result.userStrokes, boundingBox: currentBoundingBox)
                let size = min(geometry.size.width, geometry.size.height)
                
                ForEach(Array(normalizedStrokes.enumerated()), id: \.offset) { index, stroke in
                    let strokeColor = getStrokeColor(for: index, result: result)
                    Canvas { context, _ in
                        let pts = stroke.displayPoints
                        guard !pts.isEmpty else { return }
                        func widthFor(_ pressure: CGFloat, _ speed: CGFloat) -> CGFloat {
                            let minW: CGFloat = 8.0
                            let maxW: CGFloat = 28.0
                            let v0: CGFloat = 1500.0
                            let v = max(0.0, speed)
                            let factor = 1.0 / (1.0 + v / v0)
                            return minW + (maxW - minW) * pressure * factor
                        }
                        if pts.count == 1 {
                            let w = widthFor(pts[0].pressure, pts[0].speed)
                            let p = CGPoint(x: pts[0].location.x * size, y: pts[0].location.y * size)
                            let rect = CGRect(x: p.x - w/2, y: p.y - w/2, width: w, height: w)
                            context.fill(Path(ellipseIn: rect), with: .color(strokeColor))
                        } else {
                            var prevW: CGFloat = 0
                            for i in 1..<pts.count {
                                let p0n = pts[i-1]
                                let p1n = pts[i]
                                let p0 = CGPoint(x: p0n.location.x * size, y: p0n.location.y * size)
                                let p1 = CGPoint(x: p1n.location.x * size, y: p1n.location.y * size)
                                let speed = max(0.001, (p0n.speed + p1n.speed) * 0.5)
                                let pressure = (p0n.pressure + p1n.pressure) * 0.5
                                var w = widthFor(pressure, speed)
                                if prevW > 0 { w = 0.7 * prevW + 0.3 * w }
                                prevW = w
                                var seg = Path()
                                seg.move(to: p0)
                                seg.addLine(to: p1)
                                context.stroke(seg, with: .color(strokeColor), style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
                            }
                        }
                    }
                }
            }
        }
    }
    
    
    
    // Perfect Character Banner
    private var perfectCharacterBanner: some View {
        HStack {
            Text("Perfect Character!")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 16)
        .background(
            LinearGradient(
                gradient: Gradient(colors: [Color.green, Color.green.opacity(0.8)]),
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .cornerRadius(16)
        .shadow(color: Color.green.opacity(0.5), radius: 10, x: 0, y: 5)
        .padding(.top, 20)
    }
    
    // True character canvas - shows complete reference character from dataset
    private var trueCharacterCanvas: some View {
        GeometryReader { geometry in
            if let result = analysisResult {
                let size = min(geometry.size.width, geometry.size.height)
                
                // Draw all reference strokes as filled shapes
                ForEach(0..<result.referenceStrokes.count, id: \.self) { index in
                    ReferenceStrokeShape(
                        referenceStroke: result.referenceStrokes[index],
                        canvasSize: size
                    )
                    .fill(Color.black)
                }
            }
        }
    }

    // ----- below are helper functions -----
    
    // Determine stroke color based on correctness
    private func getStrokeColor(for userStrokeIndex: Int, result: CharacterAnalysisResult) -> Color {
        guard userStrokeIndex < result.strokeResults.count else { return .red }
        
        let strokeResult = result.strokeResults[userStrokeIndex]
        
        // Check if stroke is matched
        guard let matchedRefIndex = strokeResult.bestMatchIndex else {
            return .red // No match = red
        }
        
        // Check if it's in the correct position (user stroke index matches reference stroke index)
        if matchedRefIndex == userStrokeIndex {
            return .green // Correct position = green
        } else {
            return .yellow // Correct stroke but wrong order = yellow
        }
    }


    private func startSession() {
        guard !flashcardItems.isEmpty else { return }
        inSession = true
        prepareInitialPrompt()
        viewModel.clear()
        perfectStreakCount = 0
        sessionAttempted.removeAll()
        sessionPerfectCount = 0
        showCongrats = false
        prevStreakBeforeFinish = 0
    }

    private func prepareInitialPrompt() {
        if shuffle {
            currentIndex = Int.random(in: 0..<flashcardItems.count)
        } else {
            currentIndex = 0
        }
        if !flashcardItems.isEmpty {
            let item = flashcardItems[currentIndex]
            currentPrompt = item.definition
            currentCharacter = item.hanzi
        }
    }

    private func finishCharacter() {
        // Perform stroke analysis with baseline algorithm
        let userStrokes = viewModel.currentCharacter.strokes
        
        if !currentCharacter.isEmpty {
            // Calculate the bounding box based on the visual guide box
            // Store it so feedback views can use the same normalization
            currentBoundingBox = calculateBoundingBox(for: userStrokes)
            
            analysisResult = StrokeAnalyzer.analyzeCharacter(
                userStrokes: userStrokes,
                character: currentCharacter,
                boundingBox: currentBoundingBox,
                errorThreshold: errorThreshold
            )
            showFeedback = true
            
            // Check if character is perfect
            checkIfPerfect()
            
            // Start animation
        }
        
        // Remember streak before applying result so we can restore on retry
        prevStreakBeforeFinish = perfectStreakCount
        
        viewModel.completeCurrentCharacter()
        if isPerfectCharacter {
            perfectStreakCount += 1
        } else {
            perfectStreakCount = 0
        }
        // Track session completion and perfects
        sessionAttempted.insert(currentIndex)
        if isPerfectCharacter { sessionPerfectCount += 1 }
        if sessionAttempted.count >= flashcardItems.count {
            showCongrats = true
        }
    }

    private func restartSet() {
        sessionAttempted.removeAll()
        sessionPerfectCount = 0
        perfectStreakCount = 0
        analysisResult = nil
        showFeedback = false
        viewModel.clear()
        prevStreakBeforeFinish = 0
        if shuffle {
            currentIndex = Int.random(in: 0..<flashcardItems.count)
        } else {
            currentIndex = 0
        }
        if !flashcardItems.isEmpty {
            let item = flashcardItems[currentIndex]
            currentPrompt = item.definition
            currentCharacter = item.hanzi
        }
        showCongrats = false
    }

    private var congratulationsOverlay: some View {
        ZStack {
            Color.black.opacity(0.4).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "star.circle.fill")
                    .font(.system(size: 48))
                    .foregroundColor(Color("Blue 700"))
                Text("Congratulations!")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(Color("Blue 900"))
                let total = max(1, flashcardItems.count)
                Text("Perfect characters: \(sessionPerfectCount)/\(total)")
                    .font(.headline.monospacedDigit())
                    .foregroundColor(Color("Blue 700"))
                HStack(spacing: 12) {
                    Button(action: { showCongrats = false }) {
                        Text("Close")
                            .foregroundColor(Color("Blue 700"))
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .background(Color.white)
                            .cornerRadius(10)
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color("Blue 700"), lineWidth: 1))
                    }
                    Button(action: restartSet) {
                        HStack { Image(systemName: "arrow.clockwise"); Text("Restart Set") }
                            .foregroundColor(Color.white)
                            .padding(.vertical, 10)
                            .padding(.horizontal, 16)
                            .background(Color("Blue 700"))
                            .cornerRadius(10)
                    }
                }
            }
            .padding(24)
            .background(Color.white)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.2), radius: 16, x: 0, y: 8)
            .padding(.horizontal, 24)
        }
    }
    
    /// Calculate the bounding box for stroke normalization based on the visual guide box
    private func calculateBoundingBox(for strokes: [Stroke]) -> CGRect? {
        guard !strokes.isEmpty else { return nil }
        
        // Use the actual canvas size captured from GeometryReader
        // Calculate the bounding box size and position (centered, matching the visual guide box)
        let boxSize = canvasSize * CGFloat(boundingBoxSize)
        let boxMinX = (canvasSize - boxSize) / 2
        let boxMinY = (canvasSize - boxSize) / 2
        
        print("📦 Bounding box: canvas=\(canvasSize), boxSize=\(boxSize), origin=(\(boxMinX), \(boxMinY))")
        
        return CGRect(x: boxMinX, y: boxMinY, width: boxSize, height: boxSize)
    }
    
    
    
    // Check if all strokes are correct and in the right order
    private func checkIfPerfect() {
        guard let result = analysisResult else {
            isPerfectCharacter = false
            return
        }
        
        // All strokes must be matched and in correct positions
        let allCorrect = result.strokeResults.enumerated().allSatisfy { index, strokeResult in
            guard let matchedRefIndex = strokeResult.bestMatchIndex else { return false }
            return matchedRefIndex == index
        }
        
        // Also check that we have the right number of strokes
        let correctCount = result.userStrokes.count == result.referenceStrokes.count
        
        isPerfectCharacter = allCorrect && correctCount
        
        // Animate banner appearance
        if isPerfectCharacter {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                // Banner will appear
            }
        }
    }
    
    // Settings panel view (baseline algorithm)
    private var settingsPanel: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Spacer()
                Button(action: resetParameters) {
                    Text("Reset")
                        .font(.caption)
                        .foregroundColor(Color.white)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(Color("Blue 700"))
                        .cornerRadius(8)
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Bounding Box Size")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.0f%%", boundingBoxSize * 100))
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(Color("Blue 700"))
                    }

                    Slider(value: $boundingBoxSize, in: 0.2...1.0, step: 0.05)
                        .accentColor(Color("Blue 700"))
                }

                // Animation Speed
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Animation Speed")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.1fs / stroke", secondsPerStroke))
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(Color("Blue 700"))
                    }
                    Slider(value: $secondsPerStroke, in: 0.10...1.50, step: 0.05)
                        .accentColor(Color("Blue 700"))
                }
                // Sensitivity (Error Threshold)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Error Tolerance")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.3f", errorThreshold))
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(Color("Blue 700"))
                    }
                    Slider(value: $errorThreshold, in: 0.25...0.40, step: 0.01)
                        .accentColor(Color("Blue 700"))
                }
            }
        }
        .padding(16)
        .background(Color.white.opacity(0.95))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.15), radius: 8, x: 0, y: 4)
        .padding(.horizontal, 24)
        .padding(.top, 8)
    }

    // Settings sheet wrapper to isolate heavy UI updates and freeze animation/content underneath
    private var settingsSheet: some View {
        NavigationStack {
            ScrollView {
                settingsPanel
                    .padding(.top, 12)
            }
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { showSettings = false }
                }
            }
        }
    }
    
    private func resetParameters() {
        boundingBoxSize = 0.8
        secondsPerStroke = 0.5
        errorThreshold = 0.3
    }

    private func nextCard() {
        guard !flashcardItems.isEmpty else { return }
        
        // Clear feedback, animation, and perfect banner
        showFeedback = false
        analysisResult = nil
        isPerfectCharacter = false
        currentBoundingBox = nil
        
        if shuffle {
            currentIndex = Int.random(in: 0..<flashcardItems.count)
        } else {
            currentIndex = (currentIndex + 1) % flashcardItems.count
        }
        let item = flashcardItems[currentIndex]
        currentPrompt = item.definition
        currentCharacter = item.hanzi
        viewModel.clear()
    }

    private func previousCard() {
        guard !flashcardItems.isEmpty else { return }

        // If not shuffling and already at the first card, do nothing (preserve current state)
        if !shuffle && currentIndex == 0 { return }

        // Clear feedback and state only when navigating
        showFeedback = false
        analysisResult = nil
        isPerfectCharacter = false
        currentBoundingBox = nil

        // Shuffle jumps randomly; otherwise step back without wrapping
        if shuffle {
            currentIndex = Int.random(in: 0..<flashcardItems.count)
        } else {
            currentIndex = currentIndex - 1
        }
        let item = flashcardItems[currentIndex]
        currentPrompt = item.definition
        currentCharacter = item.hanzi
        viewModel.clear()
    }
}

// MARK: - Reference Stroke Shape


// MARK: - CAShapeLayer Stroke Animation

/// UIViewRepresentable that uses CAShapeLayer with proper strokeEnd animation
struct StrokeAnimationView: UIViewRepresentable {
    let referenceStrokes: [ReferenceStroke]
    let canvasSize: CGFloat
    let animationDuration: Double
    let currentProgress: Double
    
    func makeUIView(context: Context) -> StrokeAnimationContainerView {
        let view = StrokeAnimationContainerView()
        view.backgroundColor = .clear
        return view
    }
    
    func updateUIView(_ uiView: StrokeAnimationContainerView, context: Context) {
        uiView.updateAnimation(
            referenceStrokes: referenceStrokes,
            canvasSize: canvasSize,
            animationDuration: animationDuration,
            currentProgress: currentProgress
        )
    }
}

class StrokeAnimationContainerView: UIView {
    private var strokeLayers: [CAShapeLayer] = []
    private var lastProgress: Double = 0
    
    func updateAnimation(referenceStrokes: [ReferenceStroke], canvasSize: CGFloat, animationDuration: Double, currentProgress: Double) {
        // If this is a restart (progress went back to 0), rebuild everything
        if currentProgress < lastProgress {
            rebuildLayers(referenceStrokes: referenceStrokes, canvasSize: canvasSize)
        }
        lastProgress = currentProgress
        
        // If layers don't exist yet, build them
        if strokeLayers.isEmpty {
            rebuildLayers(referenceStrokes: referenceStrokes, canvasSize: canvasSize)
        }
        
        // Update strokeEnd for each layer based on progress
        let strokeCount = referenceStrokes.count
        guard strokeCount > 0 else { return }
        
        let timePerStroke = animationDuration / Double(strokeCount)
        
        for (index, layer) in strokeLayers.enumerated() {
            let strokeStartTime = Double(index) * timePerStroke
            let strokeEndTime = strokeStartTime + timePerStroke
            let currentTime = currentProgress * animationDuration
            
            let strokeEnd: CGFloat
            if currentTime < strokeStartTime {
                strokeEnd = 0
            } else if currentTime >= strokeEndTime {
                strokeEnd = 1
            } else {
                strokeEnd = CGFloat((currentTime - strokeStartTime) / timePerStroke)
            }
            
            // Update without animation (SwiftUI is handling the animation)
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.strokeEnd = strokeEnd
            CATransaction.commit()
        }
    }
    
    private func rebuildLayers(referenceStrokes: [ReferenceStroke], canvasSize: CGFloat) {
        // Remove old layers
        strokeLayers.forEach { $0.removeFromSuperlayer() }
        strokeLayers.removeAll()
        
        // Create a layer for each stroke
        for refStroke in referenceStrokes {
            let path = createPathFromMedianPoints(refStroke.medianPoints, canvasSize: canvasSize)
            
            let shapeLayer = CAShapeLayer()
            shapeLayer.path = path.cgPath
            shapeLayer.strokeColor = UIColor.black.cgColor
            shapeLayer.fillColor = UIColor.clear.cgColor
            shapeLayer.lineWidth = 18
            shapeLayer.lineCap = .round
            shapeLayer.lineJoin = .round
            shapeLayer.strokeEnd = 0
            
            layer.addSublayer(shapeLayer)
            strokeLayers.append(shapeLayer)
        }
    }
    
    private func createPathFromMedianPoints(_ points: [CGPoint], canvasSize: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        guard !points.isEmpty else { return path }
        
        // Scale points to canvas
        let scaledPoints = points.map { CGPoint(x: $0.x * canvasSize, y: $0.y * canvasSize) }
        
        path.move(to: scaledPoints[0])
        for i in 1..<scaledPoints.count {
            path.addLine(to: scaledPoints[i])
        }
        
        return path
    }
}

// New StrokePath shape used by drawingCanvas to render user strokes
private struct StrokePath: Shape {
    let stroke: Stroke
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Use displayPoints to get resampled points with timestamps if available
        let points = stroke.displayPoints.map { $0.location }
        guard !points.isEmpty else { return path }
        
        if points.count == 1 {
            let p = points[0]
            path.addEllipse(in: CGRect(x: p.x - 2, y: p.y - 2, width: 4, height: 4))
            return path
        }
        
        path.move(to: points[0])
        for i in 1..<points.count {
            path.addLine(to: points[i])
        }
        return path
    }
}

/// Static shape for displaying complete reference stroke (no animation)
private struct ReferenceStrokeShape: Shape {
    let referenceStroke: ReferenceStroke
    let canvasSize: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Parse SVG path and draw complete stroke
        let segments = parseSVGPath(referenceStroke.svgPath)
        
        for segment in segments {
            switch segment {
            case .moveTo(let point):
                let scaled = scaleAndFlipPoint(point)
                path.move(to: scaled)
            case .lineTo(let point):
                let scaled = scaleAndFlipPoint(point)
                path.addLine(to: scaled)
            case .quadCurve(let control, let end):
                let scaledControl = scaleAndFlipPoint(control)
                let scaledEnd = scaleAndFlipPoint(end)
                path.addQuadCurve(to: scaledEnd, control: scaledControl)
            case .cubicCurve(let control1, let control2, let end):
                let scaledControl1 = scaleAndFlipPoint(control1)
                let scaledControl2 = scaleAndFlipPoint(control2)
                let scaledEnd = scaleAndFlipPoint(end)
                path.addCurve(to: scaledEnd, control1: scaledControl1, control2: scaledControl2)
            case .closePath:
                path.closeSubpath()
            }
        }
        
        return path
    }
    
    private func scaleAndFlipPoint(_ point: CGPoint) -> CGPoint {
        // svgPath is normalized to [0,1]; draw within 80% inner box with 10% padding on each side
        let inset: CGFloat = 0.10
        let scale: CGFloat = 1.0 - inset * 2.0
        return CGPoint(
            x: (point.x * scale + inset) * canvasSize,
            y: (point.y * scale + inset) * canvasSize
        )
    }
    
    private func parseSVGPath(_ svgPath: String) -> [SVGPathSegment] {
        var segments: [SVGPathSegment] = []
        let components = svgPath.split(separator: " ")
        var i = 0
        var currentPoint = CGPoint.zero
        
        while i < components.count {
            let command = String(components[i])
            
            switch command {
            case "M":
                if i + 2 < components.count,
                   let x = Double(components[i + 1]),
                   let y = Double(components[i + 2]) {
                    currentPoint = CGPoint(x: x, y: y)
                    segments.append(.moveTo(currentPoint))
                    i += 3
                } else { i += 1 }
            case "L":
                if i + 2 < components.count,
                   let x = Double(components[i + 1]),
                   let y = Double(components[i + 2]) {
                    currentPoint = CGPoint(x: x, y: y)
                    segments.append(.lineTo(currentPoint))
                    i += 3
                } else { i += 1 }
            case "Q":
                if i + 4 < components.count,
                   let x1 = Double(components[i + 1]),
                   let y1 = Double(components[i + 2]),
                   let x = Double(components[i + 3]),
                   let y = Double(components[i + 4]) {
                    segments.append(.quadCurve(control: CGPoint(x: x1, y: y1), end: CGPoint(x: x, y: y)))
                    i += 5
                } else { i += 1 }
            case "C":
                if i + 6 < components.count,
                   let x1 = Double(components[i + 1]),
                   let y1 = Double(components[i + 2]),
                   let x2 = Double(components[i + 3]),
                   let y2 = Double(components[i + 4]),
                   let x = Double(components[i + 5]),
                   let y = Double(components[i + 6]) {
                    segments.append(.cubicCurve(control1: CGPoint(x: x1, y: y1), control2: CGPoint(x: x2, y: y2), end: CGPoint(x: x, y: y)))
                    i += 7
                } else { i += 1 }
            case "Z":
                segments.append(.closePath)
                i += 1
            default:
                i += 1
            }
        }
        return segments
    }
}

/// Represents a segment in an SVG path
private enum SVGPathSegment {
    case moveTo(CGPoint)
    case lineTo(CGPoint)
    case quadCurve(control: CGPoint, end: CGPoint)
    case cubicCurve(control1: CGPoint, control2: CGPoint, end: CGPoint)
    case closePath
}

// MARK: - Reference Stroke Mask Animation (outline + median reveal)
struct ReferenceStrokeMaskAnimationView: UIViewRepresentable {
    let referenceStrokes: [ReferenceStroke]
    let userStrokes: [Stroke]
    let strokeResults: [StrokeAnalysisResult]
    let originalCanvasSize: CGFloat
    let boundingBox: CGRect?
    let canvasSize: CGFloat
    let totalDuration: Double
    let replayNonce: Int
    let pause: Bool
    let debug: Bool = false
    let debugShowBounds: Bool = false
    
    func makeUIView(context: Context) -> ReferenceMaskAnimationContainerView {
        let view = ReferenceMaskAnimationContainerView()
        view.backgroundColor = .clear
        return view
    }
    
    func updateUIView(_ uiView: ReferenceMaskAnimationContainerView, context: Context) {
        uiView.renderAndAnimate(
            referenceStrokes: referenceStrokes,
            userStrokes: userStrokes,
            strokeResults: strokeResults,
            originalCanvasSize: originalCanvasSize,
            boundingBox: boundingBox,
            canvasSize: canvasSize,
            totalDuration: totalDuration,
            replayNonce: replayNonce,
            pause: pause,
            debug: debug,
            debugShowBounds: debugShowBounds
        )
    }
}

final class ReferenceMaskAnimationContainerView: UIView {
    // Cache to avoid unintended replays on unrelated state changes
    private var built = false
    private var prevReplayNonce: Int = -1
    private var prevCanvasSize: CGFloat = 0
    private var prevDuration: Double = 0
    private var prevRefCount: Int = 0
    private var prevUserCount: Int = 0
    // Keep references to layers so we can update them without rebuilding/restarting animation
    private var outlineLayers: [CAShapeLayer] = []
    private var maskLayers: [CAShapeLayer] = []
    private var isPaused: Bool = false
    
    func renderAndAnimate(referenceStrokes: [ReferenceStroke], userStrokes: [Stroke], strokeResults: [StrokeAnalysisResult], originalCanvasSize: CGFloat, boundingBox: CGRect?, canvasSize: CGFloat, totalDuration: Double, replayNonce: Int, pause: Bool, debug: Bool, debugShowBounds: Bool) {
        guard !referenceStrokes.isEmpty else { return }
        layer.masksToBounds = false

        // Apply pause/resume without restarting animations
        if pause && !isPaused {
            let pausedTime = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0
            layer.timeOffset = pausedTime
            isPaused = true
        } else if !pause && isPaused {
            let pausedTime = layer.timeOffset
            layer.speed = 1
            layer.timeOffset = 0
            layer.beginTime = 0
            let timeSincePause = layer.convertTime(CACurrentMediaTime(), from: nil) - pausedTime
            layer.beginTime = timeSincePause
            isPaused = false
        }

        // Build a reverse lookup: refIndex -> matched user stroke index
        var refToUser: [Int: Int] = [:]
        for (uIdx, r) in strokeResults.enumerated() {
            if r.isMatched, let refIdx = r.bestMatchIndex {
                refToUser[refIdx] = uIdx
            }
        }

        // Determine if we actually need to rebuild/replay
        // Only rebuild when explicitly requested (replay button) or when stroke sets change.
        let needsRebuild = (!built)
            || (replayNonce != prevReplayNonce)
            || (prevRefCount != referenceStrokes.count)
            || (prevUserCount != userStrokes.count)

        if !needsRebuild {
            // Update existing layers in place to reflect changed matches without restarting animation
            guard outlineLayers.count == referenceStrokes.count, maskLayers.count == referenceStrokes.count else { return }
            for (refIndex, ref) in referenceStrokes.enumerated() {
                let outlineLayer = outlineLayers[refIndex]
                let maskLayer = maskLayers[refIndex]

                if let uIdx = refToUser[refIndex], uIdx < userStrokes.count {
                    // Matched: render per-segment stroked sublayers for the user's stroke
                    let userPath = createUserPath(from: userStrokes[uIdx], canvasSize: canvasSize, bbox: boundingBox)
                    let r = strokeResults[uIdx]
                    let strokeUIColor: UIColor = {
                        if let matchedRef = r.bestMatchIndex, matchedRef == uIdx { return UIColor.systemGreen } else { return UIColor.systemYellow }
                    }()
                    outlineLayer.path = nil
                    outlineLayer.fillColor = nil
                    outlineLayer.strokeColor = nil
                    outlineLayer.lineWidth = 0
                    // Replace existing segment sublayers
                    outlineLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
                    let segs = buildSegmentSublayers(stroke: userStrokes[uIdx], canvasSize: canvasSize, bbox: boundingBox, color: strokeUIColor)
                    segs.forEach { outlineLayer.addSublayer($0) }

                    // Mask follows the user's median path for reveal
                    maskLayer.path = userPath.cgPath
                    maskLayer.strokeColor = UIColor.black.cgColor
                    maskLayer.fillColor = UIColor.clear.cgColor
                    // Ensure mask width is large enough to cover the thickest outline
                    if let bb = boundingBox, bb.width > 0, bb.height > 0 {
                        let widthScale = canvasSize / max(bb.width, bb.height)
                        let maxW: CGFloat = 28.0
                        maskLayer.lineWidth = max(1, widthScale * maxW * 2.2)
                    }
                    maskLayer.lineCap = .round
                    maskLayer.lineJoin = .round
                } else {
                    // Unmatched: revert to reference outline and median mask
                    let outlinePath = createBezierPath(from: ref.svgPath, canvasSize: canvasSize)
                    outlineLayer.path = outlinePath.cgPath
                    outlineLayer.fillColor = UIColor.black.cgColor
                    outlineLayer.strokeColor = nil

                    let medianPath = createStrokePath(from: ref.medianPoints, canvasSize: canvasSize)
                    maskLayer.path = medianPath.cgPath
                    maskLayer.strokeColor = UIColor.black.cgColor
                    maskLayer.fillColor = UIColor.clear.cgColor
                }
                // Do NOT modify maskLayer.strokeEnd; keep current animation progress
            }
            return
        }

        // Clear previous layers only when genuinely rebuilding
        layer.sublayers?.forEach { $0.removeFromSuperlayer() }
        outlineLayers.removeAll()
        maskLayers.removeAll()
        for (refIndex, ref) in referenceStrokes.enumerated() {
            // 1) Full outline as filled shape (reference), or user's per-segment stroked sublayers when matched
            let outlineLayer = CAShapeLayer()
            let outlinePath = createBezierPath(from: ref.svgPath, canvasSize: canvasSize)
            // If this ref stroke is matched, draw the user's path directly (scaled from original canvas size, no inset)
            if let uIdx = refToUser[refIndex], uIdx < userStrokes.count {
                let userPath = createUserPath(from: userStrokes[uIdx], canvasSize: canvasSize, bbox: boundingBox)
                let r = strokeResults[uIdx]
                let strokeUIColor: UIColor = {
                    if let refIdx = r.bestMatchIndex, refIdx == uIdx { return UIColor.systemGreen } else { return UIColor.systemYellow }
                }()
                outlineLayer.path = nil
                outlineLayer.fillColor = nil
                outlineLayer.strokeColor = nil
                outlineLayer.lineWidth = 0
                let segs = buildSegmentSublayers(stroke: userStrokes[uIdx], canvasSize: canvasSize, bbox: boundingBox, color: strokeUIColor)
                segs.forEach { outlineLayer.addSublayer($0) }
            } else {
                outlineLayer.path = outlinePath.cgPath
                outlineLayer.fillColor = UIColor.black.cgColor
                outlineLayer.strokeColor = nil
            }
            outlineLayer.frame = bounds
            outlineLayer.contentsScale = UIScreen.main.scale
            
            // Outline bounds to estimate local thickness requirement
            let bbox = outlinePath.bounds
            let maxDim = max(bbox.width, bbox.height)
            let medLen = medianLength(ref.medianPoints, canvasSize: canvasSize)
            
            // 2) Reveal mask: use user path (no inset) for matched strokes; otherwise median path (with 10% inset)
            let maskLayer = CAShapeLayer()
            if let uIdx = refToUser[refIndex], uIdx < userStrokes.count {
                let userMaskPath = createUserPath(from: userStrokes[uIdx], canvasSize: canvasSize, bbox: boundingBox)
                maskLayer.path = userMaskPath.cgPath
            } else {
                maskLayer.path = createStrokePath(from: ref.medianPoints, canvasSize: canvasSize).cgPath
            }
            maskLayer.strokeColor = UIColor.black.cgColor
            maskLayer.fillColor = UIColor.clear.cgColor
            
            var lw: CGFloat
            if let _ = refToUser[refIndex], let bb = boundingBox, bb.width > 0, bb.height > 0 {
                let widthScale = canvasSize / max(bb.width, bb.height)
                let maxUserWidth: CGFloat = 28.0
                let safety: CGFloat = 2.2
                lw = max(1, maxUserWidth * widthScale * safety)
            } else {
                var fallback = max(0.10 * canvasSize, 0.50 * maxDim)
                if medLen < (0.08 * canvasSize) {
                    fallback = max(fallback, maxDim * 1.25)
                }
                lw = fallback
            }
            maskLayer.lineWidth = lw
            
            maskLayer.lineCap = .round
            maskLayer.lineJoin = .round
            maskLayer.strokeEnd = 0
            maskLayer.frame = outlineLayer.bounds
            maskLayer.contentsScale = UIScreen.main.scale
            
            outlineLayer.mask = maskLayer
            layer.addSublayer(outlineLayer)
            self.outlineLayers.append(outlineLayer)
            self.maskLayers.append(maskLayer)
            
            if debug {
                let debugMask = CAShapeLayer()
                debugMask.path = maskLayer.path
                debugMask.strokeColor = UIColor.red.withAlphaComponent(0.6).cgColor
                debugMask.fillColor = UIColor.clear.cgColor
                debugMask.lineWidth = maskLayer.lineWidth
                debugMask.lineCap = .round
                debugMask.lineJoin = .round
                debugMask.frame = outlineLayer.bounds
                debugMask.zPosition = 1000
                layer.addSublayer(debugMask)
            }
            
            if debugShowBounds {
                let rect = outlinePath.bounds
                let rectPath = UIBezierPath(rect: rect)
                let dbg = CAShapeLayer()
                dbg.path = rectPath.cgPath
                dbg.strokeColor = UIColor.blue.withAlphaComponent(0.6).cgColor
                dbg.fillColor = UIColor.clear.cgColor
                dbg.lineWidth = 2
                dbg.lineDashPattern = [6, 4]
                dbg.frame = outlineLayer.bounds
                dbg.zPosition = 999
                layer.addSublayer(dbg)
            }
        }
        
        // 3) Animate masks sequentially
        let count = max(1, maskLayers.count)
        let per = max(0.05, totalDuration / Double(count))
        let base = layer.convertTime(CACurrentMediaTime(), from: nil)
        for (idx, m) in maskLayers.enumerated() {
            let anim = CABasicAnimation(keyPath: "strokeEnd")
            anim.fromValue = 0
            anim.toValue = 1
            anim.duration = per
            anim.beginTime = base + (Double(idx) * per)
            anim.timingFunction = CAMediaTimingFunction(name: .linear)
            anim.fillMode = .forwards
            anim.isRemovedOnCompletion = false
            m.add(anim, forKey: "reveal")
            // Keep model at 0; animation + fillMode will display progress and final state
        }

        // If paused after rebuild, immediately pause animations
        if pause {
            let pausedTime = layer.convertTime(CACurrentMediaTime(), from: nil)
            layer.speed = 0
            layer.timeOffset = pausedTime
            isPaused = true
        } else {
            isPaused = false
        }

        // Cache current config
        built = true
        prevReplayNonce = replayNonce
        prevCanvasSize = canvasSize
        prevDuration = totalDuration
        prevRefCount = referenceStrokes.count
        prevUserCount = userStrokes.count
    }
    
    // Helpers
    private func medianLength(_ points: [CGPoint], canvasSize: CGFloat) -> CGFloat {
        guard points.count > 1 else { return 0 }
        var len: CGFloat = 0
        var prev = CGPoint(x: points[0].x * canvasSize, y: points[0].y * canvasSize)
        for i in 1..<points.count {
            let p = CGPoint(x: points[i].x * canvasSize, y: points[i].y * canvasSize)
            let dx = p.x - prev.x
            let dy = p.y - prev.y
            len += sqrt(dx*dx + dy*dy)
            prev = p
        }
        return len
    }
    private func createBezierPath(from svgPath: String, canvasSize: CGFloat) -> UIBezierPath {
        let path = UIBezierPath()
        let components = svgPath.split(separator: " ")
        var i = 0
        while i < components.count {
            let cmd = String(components[i])
            switch cmd {
            case "M":
                if i + 2 < components.count,
                   let x = Double(components[i+1]),
                   let y = Double(components[i+2]) {
                    path.move(to: scaleAndFlipPoint(CGPoint(x: x, y: y), canvasSize: canvasSize))
                    i += 3
                } else { i += 1 }
            case "L":
                if i + 2 < components.count,
                   let x = Double(components[i+1]),
                   let y = Double(components[i+2]) {
                    path.addLine(to: scaleAndFlipPoint(CGPoint(x: x, y: y), canvasSize: canvasSize))
                    i += 3
                } else { i += 1 }
            case "Q":
                if i + 4 < components.count,
                   let x1 = Double(components[i+1]),
                   let y1 = Double(components[i+2]),
                   let x = Double(components[i+3]),
                   let y = Double(components[i+4]) {
                    let c = scaleAndFlipPoint(CGPoint(x: x1, y: y1), canvasSize: canvasSize)
                    let e = scaleAndFlipPoint(CGPoint(x: x, y: y), canvasSize: canvasSize)
                    path.addQuadCurve(to: e, controlPoint: c)
                    i += 5
                } else { i += 1 }
            case "C":
                if i + 6 < components.count,
                   let x1 = Double(components[i+1]), let y1 = Double(components[i+2]),
                   let x2 = Double(components[i+3]), let y2 = Double(components[i+4]),
                   let x = Double(components[i+5]), let y = Double(components[i+6]) {
                    let c1 = scaleAndFlipPoint(CGPoint(x: x1, y: y1), canvasSize: canvasSize)
                    let c2 = scaleAndFlipPoint(CGPoint(x: x2, y: y2), canvasSize: canvasSize)
                    let e  = scaleAndFlipPoint(CGPoint(x: x,  y: y), canvasSize: canvasSize)
                    path.addCurve(to: e, controlPoint1: c1, controlPoint2: c2)
                    i += 7
                } else { i += 1 }
            case "Z":
                path.close()
                i += 1
            default:
                i += 1
            }
        }
        return path
    }
    
    private func createStrokePath(from points: [CGPoint], canvasSize: CGFloat) -> UIBezierPath {
        let p = UIBezierPath()
        guard !points.isEmpty else { return p }
        // Apply 10% inset on each side (draw within 80% centered box)
        let inset: CGFloat = 0.10
        let scale: CGFloat = 1.0 - inset * 2.0
        let scaled = points.map { pt in
            CGPoint(
                x: (pt.x * scale + inset) * canvasSize,
                y: (pt.y * scale + inset) * canvasSize
            )
        }
        p.move(to: scaled[0])
        for i in 1..<scaled.count { p.addLine(to: scaled[i]) }
        return p
    }
    
    // Build CAShapeLayer sublayers for each consecutive point pair with per-segment variable widths (round caps/joins)
    private func buildSegmentSublayers(stroke: Stroke, canvasSize: CGFloat, bbox: CGRect?, color: UIColor) -> [CAShapeLayer] {
        var pts = stroke.displayPoints
        if pts.isEmpty { pts = stroke.points }
        guard pts.count > 0 else { return [] }

        func mapPoint(_ pt: CGPoint) -> CGPoint? {
            if let bb = bbox, bb.width > 0, bb.height > 0 {
                let nx = (pt.x - bb.minX) / bb.width
                let ny = (pt.y - bb.minY) / bb.height
                return CGPoint(x: nx * canvasSize, y: ny * canvasSize)
            }
            return nil
        }

        func widthFor(_ a: StrokePoint, _ b: StrokePoint) -> CGFloat {
            let pressure = max(0, min(1, (a.pressure + b.pressure) * 0.5))
            let speed = max(0.001, (a.speed + b.speed) * 0.5)
            let minW: CGFloat = 8.0
            let maxW: CGFloat = 28.0
            let v0: CGFloat = 1500.0
            let v = speed
            let factor = 1.0 / (1.0 + v / v0)
            return (minW + (maxW - minW) * pressure * factor)
        }

        var layers: [CAShapeLayer] = []
        if pts.count == 1 {
            if let p = mapPoint(pts[0].location) {
                let w = max(1.0, widthFor(pts[0], pts[0]))
                let r = w * 0.5
                let circle = UIBezierPath(ovalIn: CGRect(x: p.x - r, y: p.y - r, width: w, height: w))
                let l = CAShapeLayer()
                l.path = circle.cgPath
                l.fillColor = color.cgColor
                l.strokeColor = nil
                l.contentsScale = UIScreen.main.scale
                layers.append(l)
            }
            return layers
        }

        var prevW: CGFloat = 0
        for i in 0..<(pts.count - 1) {
            let a = pts[i]
            let b = pts[i + 1]
            guard let pa = mapPoint(a.location), let pb = mapPoint(b.location) else { continue }
            var w = widthFor(a, b)
            if prevW > 0 { w = 0.7 * prevW + 0.3 * w }
            prevW = w

            let segPath = UIBezierPath()
            segPath.move(to: pa)
            segPath.addLine(to: pb)

            let l = CAShapeLayer()
            l.path = segPath.cgPath
            l.strokeColor = color.cgColor
            l.fillColor = UIColor.clear.cgColor
            l.lineWidth = w
            l.lineCap = .round
            l.lineJoin = .round
            l.contentsScale = UIScreen.main.scale
            layers.append(l)
        }
        return layers
    }
    

    private func createUserPath(from stroke: Stroke, canvasSize: CGFloat, bbox: CGRect?) -> UIBezierPath {
        let p = UIBezierPath()
        // Use displayPoints for fidelity (time-series as drawn)
        let pts = stroke.displayPoints.map { $0.location }
        guard !pts.isEmpty, let bb = bbox, bb.width > 0, bb.height > 0 else { return p }

        // Map via guide bounding box WITHOUT inset so it fills the panel like the left view
        let scaled = pts.map { pt in
            let nx = (pt.x - bb.minX) / bb.width
            let ny = (pt.y - bb.minY) / bb.height
            return CGPoint(
                x: nx * canvasSize,
                y: ny * canvasSize
            )
        }

        if scaled.count == 1 {
            let c = scaled[0]
            p.addArc(withCenter: c, radius: max(1, canvasSize * 0.01), startAngle: 0, endAngle: CGFloat.pi * 2, clockwise: true)
            return p
        }
        p.move(to: scaled[0])
        for i in 1..<scaled.count { p.addLine(to: scaled[i]) }
        return p
    }
    
    private func createVariableWidthOutlinePath(from stroke: Stroke, canvasSize: CGFloat, bbox: CGRect?) -> UIBezierPath {
        // Prefer displayPoints for fidelity; fall back to points
        var pts = stroke.displayPoints
        if pts.isEmpty { pts = stroke.points }
        // Single-point stroke => filled circle
        if pts.count == 1 {
            let sp = pts[0]
            func widthFor(_ pressure: CGFloat, _ speed: CGFloat) -> CGFloat {
                let minW: CGFloat = 8.0
                let maxW: CGFloat = 28.0
                let v0: CGFloat = 1500.0
                let v = max(0.0, speed)
                let factor = 1.0 / (1.0 + v / v0)
                return minW + (maxW - minW) * pressure * factor
            }
            let p = UIBezierPath()
            let c: CGPoint = {
                if let bb = bbox, bb.width > 0, bb.height > 0 {
                    let nx = (sp.location.x - bb.minX) / bb.width
                    let ny = (sp.location.y - bb.minY) / bb.height
                    return CGPoint(x: nx * canvasSize, y: ny * canvasSize)
                } else {
                    return CGPoint(x: sp.location.x * canvasSize, y: sp.location.y * canvasSize)
                }
            }()
            let r = widthFor(sp.pressure, sp.speed) * 0.5
            p.addArc(withCenter: c, radius: r, startAngle: 0, endAngle: .pi * 2, clockwise: true)
            p.close()
            return p
        }

        // Mapping helper
        let mapPoint: (CGPoint) -> CGPoint = { pt in
            if let bb = bbox, bb.width > 0, bb.height > 0 {
                let nx = (pt.x - bb.minX) / bb.width
                let ny = (pt.y - bb.minY) / bb.height
                return CGPoint(x: nx * canvasSize, y: ny * canvasSize)
            } else {
                return CGPoint(x: pt.x * canvasSize, y: pt.y * canvasSize)
            }
        }
        func widthFor(_ a: StrokePoint, _ b: StrokePoint) -> CGFloat {
            let pressure = max(0, min(1, (a.pressure + b.pressure) * 0.5))
            let speed = max(0.001, (a.speed + b.speed) * 0.5)
            let minW: CGFloat = 8.0
            let maxW: CGFloat = 28.0
            let v0: CGFloat = 1500.0
            let v = speed
            let factor = 1.0 / (1.0 + v / v0)
            return (minW + (maxW - minW) * pressure * factor)
        }

        // Build left/right outlines
        var left: [CGPoint] = []
        var right: [CGPoint] = []
        var prevW: CGFloat = 0
        for i in 0..<(pts.count - 1) {
            let a = pts[i]
            let b = pts[i + 1]
            let pa = mapPoint(a.location)
            let pb = mapPoint(b.location)
            let dx = pb.x - pa.x
            let dy = pb.y - pa.y
            let len = max(1e-6, sqrt(dx*dx + dy*dy))
            var w = widthFor(a, b)
            if prevW > 0 { w = 0.7 * prevW + 0.3 * w }
            prevW = w
            let nx = -dy / len
            let ny =  dx / len
            let hx = nx * (w * 0.5)
            let hy = ny * (w * 0.5)
            let la = CGPoint(x: pa.x + hx, y: pa.y + hy)
            let ra = CGPoint(x: pa.x - hx, y: pa.y - hy)
            let lb = CGPoint(x: pb.x + hx, y: pb.y + hy)
            let rb = CGPoint(x: pb.x - hx, y: pb.y - hy)
            if i == 0 {
                left.append(la)
                right.append(ra)
            }
            left.append(lb)
            right.append(rb)
        }

        // Create round caps at ends by appending circles (helps cover joins)
        let outline = UIBezierPath()
        if let first = left.first { outline.move(to: first) }
        for i in 1..<left.count { outline.addLine(to: left[i]) }
        for i in stride(from: right.count - 1, through: 0, by: -1) { outline.addLine(to: right[i]) }
        outline.close()

        // Add end caps
        let startCenter = mapPoint(pts.first!.location)
        let endCenter = mapPoint(pts.last!.location)
        // Use first and last segment widths
        let wStart = widthFor(pts[0], pts[1]) * 0.5
        let wEnd = widthFor(pts[pts.count-2], pts[pts.count-1]) * 0.5
        //outline.addArc(withCenter: startCenter, radius: wStart, startAngle: 0, endAngle: .pi * 2, clockwise: true)
        // outline.addArc(withCenter: endCenter, radius: wEnd, startAngle: 0, endAngle: .pi * 2, clockwise: true)

        return outline
    }
    private func scaleAndFlipPoint(_ point: CGPoint, canvasSize: CGFloat) -> CGPoint {
        // svgPath has been normalized to [0,1] in StrokeAnalyzer; draw within 80% inner box with 10% padding
        let inset: CGFloat = 0.10
        let scale: CGFloat = 1.0 - inset * 2.0
        return CGPoint(
            x: (point.x * scale + inset) * canvasSize,
            y: (point.y * scale + inset) * canvasSize
        )
    }
}


