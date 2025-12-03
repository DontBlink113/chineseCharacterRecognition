import SwiftUI

struct StrokeTestView: View {
    @StateObject private var viewModel = DrawingViewModel()
    @State private var showInfo = false
    @State private var showingCharacterData = false
    @State private var selectedCharacter: CharacterDrawing?

    // State for showing a specific dataset character
    @State private var showCharacterInput = false
    @State private var inputCharacter: String = ""
    @State private var datasetCharacter: Character?
    @State private var inputError: String?
    @State private var isPanelVisible: Bool = true
    @State private var bestMatchCost: Double? = nil
    private let analyzer = CharacterAnalyzer.shared

    @AppStorage("learningCharacters") private var learningCharsInput: String = ""
    @State private var showLearningInput = false
    @State private var learningCharsDraft: String = ""
    @State private var learningInputError: String?

    private var learningCandidateKeys: [String] {
        extractHanzi(from: learningCharsInput)
    }

    @State private var generatedSentence: GeneratedSentence? = nil
    @State private var isGeneratingSentence: Bool = false
    @State private var generationError: String? = nil

    @State private var lastSentenceCharCount: Int = 0
    @State private var lastSentenceSubstrokeTotal: Int = 0

    @State private var isComparing: Bool = false
    @State private var comparisonEnglish: String = ""
    @State private var comparisonChineseTarget: String = ""
    @State private var comparisonError: String? = nil
    @State private var comparisonInterpreted: String? = nil
    @State private var isPreparingComparison: Bool = false


    //This array contains the completed characters
    private var allCharacters: [CharacterDrawing] {
        var characters = viewModel.characters
        if !viewModel.currentCharacter.strokes.isEmpty {
            characters.append(viewModel.currentCharacter)
        }
        return characters
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Drawing Canvas
            ZStack {
                Color.white
                
                // Draw all completed characters
                ForEach(viewModel.characters) { character in
                    CharacterView(character: character)
                }
                
                // Draw current character
                CharacterView(character: viewModel.currentCharacter)
                
                // Draw current stroke in progress
                if let stroke = viewModel.currentStroke {
                    StrokeView(stroke: stroke)
                        .stroke(Color.blue, lineWidth: 3)
                }
                
                // Visualize substrokes
                if showInfo {
                    ForEach(viewModel.currentCharacter.strokes.flatMap { $0.substrokes }) { substroke in
                        SubstrokeInfoView(substroke: substroke)
                    }
                }
            }
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let point = value.location
                        if value.translation == .zero {
                            viewModel.beginStroke(at: point)
                        } else {
                            viewModel.continueStroke(at: point)
                        }
                    }
                    .onEnded { _ in
                        viewModel.endStroke()
                    }
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Controls
            VStack(spacing: 16) {
                // Start Comparison (auto-generate English + Chinese via OpenAI)
                Button(action: {
                    comparisonError = nil
                    comparisonInterpreted = nil
                    comparisonEnglish = ""
                    comparisonChineseTarget = ""
                    let allowed = learningCandidateKeys
                    if allowed.isEmpty {
                        showLearningInput = true
                        return
                    }
                    isPreparingComparison = true
                    Task {
                        defer { isPreparingComparison = false }
                        do {
                            let generator = try OpenAISentenceGenerator()
                            let result = try await generator.generate(allowed: allowed)
                            comparisonEnglish = result.english
                            comparisonChineseTarget = result.chinese
                            lastSentenceCharCount = 0
                            lastSentenceSubstrokeTotal = 0
                            isComparing = true
                            viewModel.startSentence()
                        } catch let err as SentenceGenError {
                            switch err {
                            case .missingAPIKey:
                                comparisonError = "Missing OpenAI API key. Add OPENAI_API_KEY to Info.plist."
                            case .emptyAllowedSet:
                                comparisonError = "Please set your learning characters first."
                            case .validationFailed:
                                comparisonError = "Model produced characters outside your learning set. Try again."
                            case .invalidResponse:
                                comparisonError = "Invalid response from the API."
                            }
                        } catch {
                            comparisonError = "Failed to prepare comparison. Check connection and try again."
                        }
                    }
                }) {
                    HStack {
                        if isPreparingComparison { ProgressView().progressViewStyle(.circular) }
                        Text(isComparing ? "Comparison Active" : "Start Comparison")
                            .font(.headline)
                    }
                    .foregroundColor(.white)
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(isComparing ? Color.blue : Color.indigo)
                    .cornerRadius(10)
                }
                .padding(.horizontal)

                HStack(spacing: 12) {
                    Button(action: {
                        viewModel.startSentence()
                        lastSentenceCharCount = 0
                        lastSentenceSubstrokeTotal = 0
                    }) {
                        Text("Start Sentence")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(viewModel.isRecordingSentence ? Color.gray : Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .disabled(viewModel.isRecordingSentence)

                    Button(action: {
                        let result = viewModel.endSentence()
                        lastSentenceCharCount = result.1.count
                        lastSentenceSubstrokeTotal = result.0.map { $0.count }.reduce(0, +)
                        if isComparing {
                            let interpreted = interpretWritten(from: result.1)
                            comparisonInterpreted = interpreted
                            isComparing = false
                        }
                    }) {
                        Text("End Sentence")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(viewModel.isRecordingSentence ? Color.orange : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    .disabled(!viewModel.isRecordingSentence)
                }
                .padding(.horizontal)
                if viewModel.isRecordingSentence {
                    HStack {
                        Text("Recording sentence: \(viewModel.currentSentence.count) chars")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                } else if lastSentenceCharCount > 0 {
                    HStack {
                        Text("Saved sentence: \(lastSentenceCharCount) chars, \(lastSentenceSubstrokeTotal) substrokes")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal)
                }

                if let err = comparisonError {
                    Text(err)
                        .foregroundColor(.red)
                        .font(.footnote)
                        .padding(.horizontal)
                }

                if isComparing || comparisonInterpreted != nil {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack { Text("English Prompt:").bold(); Spacer() }
                        Text(comparisonEnglish.isEmpty ? "—" : comparisonEnglish)
                        HStack { Text("Intended Chinese:").bold(); Spacer() }
                        Text(comparisonChineseTarget.isEmpty ? "—" : comparisonChineseTarget)
                        HStack { Text("Interpreted Chinese:").bold(); Spacer() }
                        Text(comparisonInterpreted ?? "(write sentence, then End Sentence)")
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                    .padding(.horizontal)
                }
                
                
                HStack(spacing: 16) {
                    // Complete character button
                    Button(action: {
                        viewModel.completeCurrentCharacter()
                    }) {
                        Text(viewModel.isRecordingSentence ? "Save Character" : "Complete Character")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    
                    // Toggle info view
                    Button(action: {
                        withAnimation {
                            showInfo.toggle()
                        }
                    }) {
                        Image(systemName: "info.circle")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(showInfo ? Color.orange : Color.gray)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                    
                    // Clear button
                    Button(action: {
                        viewModel.clear()
                    }) {
                        Image(systemName: "trash")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.red)
                            .foregroundColor(.white)
                            .cornerRadius(10)
                    }
                }
                .padding(.horizontal)
                
                // Removed: Show Specific Character and sheet

                Button(action: {
                    learningCharsDraft = learningCharsInput
                    learningInputError = nil
                    showLearningInput = true
                }) {
                    Text("Set Learning Characters")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                .sheet(isPresented: $showLearningInput) {
                    NavigationView {
                        VStack(spacing: 16) {
                            Text("Enter characters you are learning")
                                .font(.headline)
                            TextEditor(text: $learningCharsDraft)
                                .frame(minHeight: 120)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                                )
                                .padding(.horizontal)
                            if let err = learningInputError {
                                Text(err)
                                    .foregroundColor(.red)
                                    .font(.footnote)
                            }
                            HStack {
                                Button("Cancel") {
                                    showLearningInput = false
                                }
                                Spacer()
                                Button("Save") {
                                    let extracted = extractHanzi(from: learningCharsDraft)
                                    if extracted.isEmpty {
                                        learningInputError = "Please enter Chinese characters only."
                                    } else {
                                        learningCharsInput = extracted.joined()
                                        showLearningInput = false
                                    }
                                }
                            }
                            .padding(.horizontal)
                            Spacer()
                        }
                        .padding()
                    }
                }
                HStack {
                    Text("Learning set: \(learningCandidateKeys.count) chars")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Button("Clear") {
                        learningCharsInput = ""
                    }
                    .font(.caption)
                }
                .padding(.horizontal)
                
                // Removed: Find Best Match, Generate Sentence and results
            }
            .padding(.vertical, 8)
            .background(Color(UIColor.systemGroupedBackground))
            
            // Removed: View Character Data button
        }
        .overlay(alignment: .trailing) {
            if isPanelVisible {
                RightSidePanel(
                    datasetCharacter: datasetCharacter,
                    matchCost: bestMatchCost,
                    showingDrawnData: showingCharacterData,
                    currentCharacter: viewModel.currentCharacter,
                    lastCompleted: viewModel.characters.last,
                    onClose: { withAnimation { isPanelVisible = false } }
                )
                .frame(width: 360)
                .background(Color(.systemBackground))
                .shadow(radius: 4)
            } else {
                // Small floating button to restore the panel
                Button(action: { withAnimation { isPanelVisible = true } }) {
                    Image(systemName: "sidebar.left")
                        .font(.title3)
                        .padding(10)
                        .background(Color(.systemBackground))
                        .clipShape(Capsule())
                        .shadow(radius: 2)
                        .padding(.trailing, 8)
                }
            }
        }
    }

    private func interpretWritten(from drawings: [CharacterDrawing]) -> String {
        let keys = learningCandidateKeys
        var result = ""
        for d in drawings {
            if let match = analyzer.bestMatch(for: d, candidateKeys: keys.isEmpty ? nil : keys) {
                result.append(match.character.character)
            } else {
                result.append("□")
            }
        }
        return result
    }
}

private func extractHanzi(from text: String) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for scalar in text.unicodeScalars {
        let v = scalar.value
        if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0xF900...0xFAFF).contains(v) {
            let s = String(scalar)
            if !seen.contains(s) {
                seen.insert(s)
                result.append(s)
            }
        }
    }
    return result
}

// MARK: - Helper Views

private struct CharacterView: View {
    let character: CharacterDrawing
    
    var body: some View {
        ForEach(character.strokes) { stroke in
            StrokeView(stroke: stroke)
                .stroke(Color.black, lineWidth: 3)
        }
    }
}

private struct StrokeView: Shape {
    let stroke: Stroke
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard let firstPoint = stroke.points.first else { return path }
        
        path.move(to: firstPoint.location)
        
        for point in stroke.points.dropFirst() {
            path.addLine(to: point.location)
        }
        
        return path
    }
}

private struct SubstrokeInfoView: View {
    let substroke: Stroke.Substroke
    
    private var directionArrow: some View {
        guard substroke.points.count >= 2 else { return AnyView(EmptyView()) }
        
        let start = substroke.points[0].location
        let end = substroke.points[substroke.points.count - 1].location
        
        return AnyView(
            Path { path in
                path.move(to: start)
                path.addLine(to: end)
                
                // Draw arrow head
                let angle = atan2(end.y - start.y, end.x - start.x)
                let arrowLength: CGFloat = 15
                let arrowAngle = CGFloat.pi / 6 // 30 degrees
                
                let arrowLine1 = CGPoint(
                    x: end.x - arrowLength * cos(angle - arrowAngle),
                    y: end.y - arrowLength * sin(angle - arrowAngle)
                )
                
                let arrowLine2 = CGPoint(
                    x: end.x - arrowLength * cos(angle + arrowAngle),
                    y: end.y - arrowLength * sin(angle + arrowAngle)
                )
                
                path.move(to: end)
                path.addLine(to: arrowLine1)
                path.move(to: end)
                path.addLine(to: arrowLine2)
            }
            .stroke(Color.red, lineWidth: 1)
        )
    }
    
    var body: some View {
        ZStack {
            // Draw substroke in red
            Path { path in
                guard let first = substroke.points.first else { return }
                path.move(to: first.location)
                
                for point in substroke.points.dropFirst() {
                    path.addLine(to: point.location)
                }
            }
            .stroke(Color.red, lineWidth: 2)
            
            // Draw direction arrow
            directionArrow
            
            // Draw center point
            Circle()
                .fill(Color.green)
                .frame(width: 8, height: 8)
                .position(substroke.center)
            
            // Draw info text
            Text(String(format: "%.2f rad, %.1f", substroke.angle, substroke.magnitude))
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.black)
                .padding(4)
                .background(Color.white.opacity(0.7))
                .cornerRadius(4)
                .position(x: substroke.center.x, y: substroke.center.y + 20)
        }
    }
}

// MARK: - Right Side Panel

private struct RightSidePanel: View {
    let datasetCharacter: Character?
    let matchCost: Double?
    let showingDrawnData: Bool
    let currentCharacter: CharacterDrawing
    let lastCompleted: CharacterDrawing?
    let onClose: () -> Void
    
    private var drawnCharacterToShow: CharacterDrawing? {
        guard showingDrawnData else { return nil }
        if !currentCharacter.strokes.isEmpty { return currentCharacter }
        return lastCompleted
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Details Panel")
                    .font(.headline)
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "sidebar.right")
                        .font(.headline)
                        .foregroundColor(.secondary)
                }
            }
            .padding()
            Divider()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Dataset Character Section
                    Section {
                        if let char = datasetCharacter {
                            DatasetCharacterPanel(character: char, matchCost: matchCost)
                        } else {
                            Text("No dataset character selected.")
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Text("Dataset Character")
                            .font(.subheadline.bold())
                            .foregroundColor(.secondary)
                    }
                    
                    // Drawn Character Section
                    Section {
                        if let drawn = drawnCharacterToShow {
                            CharacterDataView(character: drawn)
                        } else if showingDrawnData {
                            Text("No drawn character available yet.")
                                .foregroundColor(.secondary)
                        } else {
                            Text("Tap 'View Character Data' to show details for your drawing here.")
                                .foregroundColor(.secondary)
                        }
                    } header: {
                        Text("Drawn Character")
                            .font(.subheadline.bold())
                            .foregroundColor(.secondary)
                    }
                }
                .padding()
            }
        }
    }
}

private struct DatasetCharacterPanel: View {
    let character: Character
    let matchCost: Double?
    
    // Compute per-character bounding box over dataset substroke centers (0..1 space)
    private var bbox: (minX: Double, maxX: Double, minY: Double, maxY: Double) {
        let xs = character.substrokes.map { $0.centerX }
        let ys = character.substrokes.map { $0.centerY }
        let minX = xs.min() ?? 0.0
        let maxX = xs.max() ?? 1.0
        let minY = ys.min() ?? 0.0
        let maxY = ys.max() ?? 1.0
        return (minX, maxX, minY, maxY)
    }
    
    private func renorm(_ value: Double, minX: Double, maxX: Double) -> Double {
        guard maxX > minX else { return 0.5 }
        let n = (value - minX) / (maxX - minX)
        return Swift.min(1.0, Swift.max(0.0, n))
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Big character display
            Text(character.character)
                .font(.system(size: 80))
                .frame(maxWidth: .infinity)
                .frame(height: 140)
                .background(Color(.systemGray6))
                .cornerRadius(12)
            
            // Stats
            VStack(alignment: .leading, spacing: 12) {
                InfoRow(title: "Stroke Count", value: "\(character.strokeCount)")
                InfoRow(title: "Substroke Count", value: "\(character.substrokeCount)")
                if let cost = matchCost {
                    InfoRow(title: "Match Cost", value: String(format: "%.3f", cost))
                }
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            // Substrokes (raw and bbox-normalized centers)
            if !character.substrokes.isEmpty {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Sub-strokes (dataset)")
                        .font(.subheadline.bold())
                        .foregroundColor(.secondary)
                    
                    ForEach(Array(character.substrokes.enumerated()), id: \.offset) { index, s in
                        let nx = renorm(s.centerX, minX: bbox.minX, maxX: bbox.maxX)
                        let ny = renorm(s.centerY, minX: bbox.minY, maxX: bbox.maxY)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(index + 1). dir: \(String(format: "%.2f", s.direction)) rad  len: \(String(format: "%.2f", s.length))")
                                .font(.caption.monospaced())
                            Text("    raw center: (\(String(format: "%.2f", s.centerX)), \(String(format: "%.2f", s.centerY)))  bbox: (\(String(format: "%.2f", nx)), \(String(format: "%.2f", ny)))")
                                .font(.caption.monospaced())
                        }
                        .padding(6)
                        .background(index % 2 == 0 ? Color(.systemGray6) : Color(.systemBackground))
                        .cornerRadius(6)
                    }
                }
            }
        }
    }
}

// MARK: - Preview

struct StrokeTestView_Previews: PreviewProvider {
    static var previews: some View {
        StrokeTestView()
    }
}
