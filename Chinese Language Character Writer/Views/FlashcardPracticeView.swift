import SwiftUI
import UIKit
import QuartzCore

struct FlashcardPracticeView: View {
    @EnvironmentObject var store: LearningSetsStore
    @StateObject private var viewModel = DrawingViewModel()

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
    @AppStorage("showTopProbs") private var showTopProbs: Bool = false  // Debug overlay toggle
    @AppStorage("errorThreshold") private var errorThreshold: Double = 0.35  // Sensitivity (Fréchet error threshold)
    @State private var replayNonce: Int = 0  // Changing this replays the animation
    @State private var perfectStreakCount: Int = 0
    @State private var sessionAttempted: Set<Int> = []
    @State private var sessionPerfectCount: Int = 0
    @State private var showCongrats: Bool = false

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
                        .font(.system(size: 40)).bold()
                        .foregroundColor(Color("Blue 900"))
                        .padding(.top, 20)
                    
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
                                .font(.system(size: 24, weight: .medium))
                                .foregroundColor(Color("Blue 900"))
                                .multilineTextAlignment(.center)
                                .lineLimit(3)
                        }
                        .padding(.horizontal, 16)
                        
                        Spacer()
                        
                        // Placeholder for symmetry
                        Color.clear
                            .frame(width: 44, height: 44)
                        
                        Color.clear
                            .frame(width: 44, height: 44)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
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
                            
                            Spacer()
                            
                            // Side-by-side comparison view
                            HStack(spacing: 16) {
                                // Left: User's color-coded strokes
                                VStack(spacing: 8) {
                                    Text("Your Drawing")
                                        .font(.headline)
                                        .foregroundColor(Color("Blue 900"))
                                    
                                    ZStack {
                                        Color.white
                                        
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
                                    .overlay(alignment: .topLeading) {
                                        if showTopProbs, let result = analysisResult {
                                            VStack(alignment: .leading, spacing: 2) {
                                                ForEach(Array(result.strokeResults.enumerated()), id: \.offset) { idx, r in
                                                    Text(probabilityText(index: idx, probability: r.bestMatchProbability, error: r.rawError))
                                                        .font(.caption2.monospacedDigit())
                                                        .foregroundColor(Color("Blue 900"))
                                                }
                                            }
                                            .padding(6)
                                            .background(Color.white.opacity(0.85))
                                            .cornerRadius(8)
                                            .shadow(color: Color.black.opacity(0.1), radius: 3, x: 0, y: 1)
                                            .padding(6)
                                        }
                                    }
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color("Blue 700"), lineWidth: 2)
                                    )
                                }
                            }
                            
                            // Bottom panel: Reference Character
                            VStack(spacing: 8) {
                                Text("Reference Character")
                                    .font(.headline)
                                    .foregroundColor(Color("Blue 900"))
                                
                                ZStack {
                                    Color.white
                                    
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
                            // Undo button
                            Button(action: { _ = viewModel.undo() }) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.headline)
                                    .foregroundColor(Color("Blue 700"))
                                    .frame(width: 50)
                                    .padding(.vertical, 16)
                                    .background(Color.white)
                                    .cornerRadius(12)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(Color("Blue 700"), lineWidth: 2)
                                    )
                            }
                            .disabled(showFeedback)
                            .opacity(showFeedback ? 0.5 : 1.0)
                            
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
                // Apply updated settings when the sheet is dismissed
                guard !opened, showFeedback, !currentCharacter.isEmpty else { return }
                let userStrokes = viewModel.currentCharacter.strokes
                // Recompute bounding box in case size changed
                currentBoundingBox = calculateBoundingBox(for: userStrokes)
                analysisResult = StrokeAnalyzer.analyzeCharacter(
                    userStrokes: userStrokes,
                    character: currentCharacter,
                    boundingBox: currentBoundingBox,
                    errorThreshold: errorThreshold
                )
                checkIfPerfect()
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
    
    private func probabilityText(index: Int, probability: Double, error: Double) -> String {
        let percent = Int(probability * 100)
        let errRounded = (error * 1000).rounded() / 1000
        return "U\(index + 1): \(percent)% err:\(errRounded)"
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
            
            // Ink for completed strokes (draws one StrokePath for each stroke)
            ForEach(viewModel.currentCharacter.strokes, id: \.id) { stroke in
                StrokePath(stroke: stroke)
                    .stroke(
                        Color.black,
                        style: StrokeStyle(
                            lineWidth: 12,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
            }
            // Ink for live stroke
            if let live = viewModel.currentStroke {
                StrokePath(stroke: live)
                    .stroke(
                        Color.black.opacity(0.8),
                        style: StrokeStyle(
                            lineWidth: 12,
                            lineCap: .round,
                            lineJoin: .round
                        )
                    )
            }
        }
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    let pt = value.location
                    if viewModel.currentStroke == nil {
                        viewModel.beginStroke(at: pt)
                    } else {
                        viewModel.continueStroke(at: pt)
                    }
                }
                .onEnded { _ in
                    viewModel.endStroke()
                }
        )
    }
    
    // Color-coded feedback canvas
    private var coloredFeedbackCanvas: some View {
        GeometryReader { geometry in
            if let result = analysisResult {
                // Normalize strokes using the same bounding box as the analysis
                let normalizedStrokes = StrokeAnalyzer.normalizeUserStrokes(result.userStrokes, boundingBox: currentBoundingBox)
                let size = min(geometry.size.width, geometry.size.height)
                
                // User strokes
                ForEach(Array(normalizedStrokes.enumerated()), id: \.offset) { index, stroke in
                        let strokeColor = getStrokeColor(for: index, result: result)
                        
                        // Scale stroke to fit the box
                        Path { path in
                            let points = stroke.displayPoints.map { point in
                                CGPoint(
                                    x: point.location.x * size,
                                    y: point.location.y * size
                                )
                            }
                            
                            guard !points.isEmpty else { return }
                            
                            if points.count == 1 {
                                path.addEllipse(in: CGRect(x: points[0].x - 2, y: points[0].y - 2, width: 4, height: 4))
                            } else {
                                path.move(to: points[0])
                                for i in 1..<points.count {
                                    path.addLine(to: points[i])
                                }
                            }
                        }
                        .stroke(
                            strokeColor,
                            style: StrokeStyle(
                                lineWidth: 20,
                                lineCap: .round,
                                lineJoin: .round
                            )
                        )
                }
            }
        }
    }
    
    
    
    // Perfect Character Banner
    private var perfectCharacterBanner: some View {
        HStack {
            Image(systemName: "checkmark.seal.fill")
                .font(.title)
                .foregroundColor(.white)
            Text("Perfect Character!")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.white)
            Image(systemName: "checkmark.seal.fill")
                .font(.title)
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
                Text("Algorithm Parameters")
                    .font(.headline)
                    .foregroundColor(Color("Blue 900"))
                Spacer()
                Button(action: resetParameters) {
                    Text("Reset")
                        .font(.caption)
                        .foregroundColor(Color("Blue 700"))
                }
            }
            
            VStack(alignment: .leading, spacing: 12) {
                Text("Baseline Algorithm")
                    .font(.caption)
                    .foregroundColor(Color("Neutral 700"))
                Text("Fréchet distance + Optimal assignment")
                    .font(.caption)
                    .foregroundColor(Color("Neutral 700"))
                    .italic()
                
                // Bounding Box Size
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
                    Text("Size of drawing area guide box")
                        .font(.caption)
                        .foregroundColor(Color("Neutral 700"))
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
                    Text("Time per stroke in the right panel animation")
                        .font(.caption)
                        .foregroundColor(Color("Neutral 700"))
                }

                // Sensitivity (Error Threshold)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Sensitivity")
                            .font(.subheadline)
                        Spacer()
                        Text(String(format: "%.3f", errorThreshold))
                            .font(.subheadline.monospacedDigit())
                            .foregroundColor(Color("Blue 700"))
                    }
                    Slider(value: $errorThreshold, in: 0.25...0.40, step: 0.01)
                        .accentColor(Color("Blue 700"))
                    Text("Error threshold (Fréchet distance) for removing strokes")
                        .font(.caption)
                        .foregroundColor(Color("Neutral 700"))
                }

                // Debug: Show top probabilities
                Toggle(isOn: $showTopProbs) {
                    Text("Show Top Probabilities")
                        .font(.subheadline)
                }
                .toggleStyle(SwitchToggleStyle(tint: Color("Blue 700")))
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
                    // Matched: use user path and stroke color (green/yellow)
                    let userPath = createUserPath(from: userStrokes[uIdx], canvasSize: canvasSize, bbox: boundingBox)
                    outlineLayer.path = userPath.cgPath
                    outlineLayer.fillColor = UIColor.clear.cgColor
                    let r = strokeResults[uIdx]
                    let strokeUIColor: UIColor = {
                        if let matchedRef = r.bestMatchIndex, matchedRef == uIdx { return UIColor.systemGreen } else { return UIColor.systemYellow }
                    }()
                    outlineLayer.strokeColor = strokeUIColor.cgColor
                    outlineLayer.lineWidth = max(16, canvasSize * 0.05)
                    outlineLayer.lineCap = .round
                    outlineLayer.lineJoin = .round

                    // Mask follows user path
                    maskLayer.path = userPath.cgPath
                    maskLayer.strokeColor = UIColor.black.cgColor
                    maskLayer.fillColor = UIColor.clear.cgColor
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
            // 1) Full outline as filled shape
            let outlineLayer = CAShapeLayer()
            let outlinePath = createBezierPath(from: ref.svgPath, canvasSize: canvasSize)
            // If this ref stroke is matched, draw the user's path directly (scaled from original canvas size, no inset)
            if let uIdx = refToUser[refIndex], uIdx < userStrokes.count {
                let userPath = createUserPath(from: userStrokes[uIdx], canvasSize: canvasSize, bbox: boundingBox)
                outlineLayer.path = userPath.cgPath
                outlineLayer.fillColor = UIColor.clear.cgColor
                let r = strokeResults[uIdx]
                let strokeUIColor: UIColor = {
                    if let refIdx = r.bestMatchIndex, refIdx == uIdx { return UIColor.systemGreen } else { return UIColor.systemYellow }
                }()
                outlineLayer.strokeColor = strokeUIColor.cgColor
                outlineLayer.lineWidth = max(16, canvasSize * 0.05)
                outlineLayer.lineCap = .round
                outlineLayer.lineJoin = .round
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
            
            // Adaptive width: ensure small dot strokes get a sufficiently wide mask
            var lw = max(0.10 * canvasSize, 0.50 * maxDim)
            if medLen < (0.08 * canvasSize) {
                lw = max(lw, maxDim * 1.25)
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


