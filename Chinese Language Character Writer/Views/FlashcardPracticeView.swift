import SwiftUI

struct FlashcardPracticeView: View {
    @EnvironmentObject var store: LearningSetsStore
    @StateObject private var viewModel = DrawingViewModel()

    @State private var selectedSetId: UUID? = nil
    @State private var shuffle: Bool = false
    @State private var inSession: Bool = false

    @State private var currentIndex: Int = 0
    @State private var currentPrompt: String = ""
    @State private var currentCharacter: String = ""

    private var selectedSet: LearningSet? {
        if let id = selectedSetId { return store.sets.first { $0.id == id } }
        return store.activeSet
    }

    private var flashcardItems: [FlashcardItem] {
        guard let s = selectedSet, let items = s.items else { return [] }
        return items
    }

    var body: some View {
        Group {
            if !inSession {
                // Setup UI
                ZStack {
                    Color(red: 0.68, green: 0.85, blue: 0.9)
                        .ignoresSafeArea()
                    
                    ScrollView {
                        VStack(spacing: 24) {
                            // Title
                            Text("Flashcard Practice")
                                .font(.system(size: 40)).bold()
                                .foregroundColor(Color("Blue 900"))
                                .padding(.top, 20)
                            
                            // Setup Card
                            VStack(alignment: .leading, spacing: 20) {
                                Text("Setup")
                                    .font(.title2).bold()
                                    .foregroundColor(Color("Blue 900"))
                                
                                if store.sets.filter({ $0.hasDefinitions }).isEmpty {
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
                                } else {
                                    VStack(alignment: .leading, spacing: 12) {
                                        Text("Learning Set")
                                            .font(.subheadline)
                                            .foregroundColor(Color("Blue 900"))
                                        
                                        Picker("Learning Set", selection: Binding(
                                            get: { selectedSetId ?? store.activeSetId },
                                            set: { selectedSetId = $0 }
                                        )) {
                                            ForEach(store.sets.filter { $0.hasDefinitions }) { set in
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
                            }
                            .padding(20)
                            .background(Color.white.opacity(0.7))
                            .cornerRadius(16)
                            .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 4)
                            .padding(.horizontal, 24)
                            
                            Spacer(minLength: 40)
                        }
                    }
                }
                .navigationBarTitleDisplayMode(.inline)
            } else {
                // In-session UI
                VStack(spacing: 0) {
                    // Top control bar
                    HStack(spacing: 16) {
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
                    
                    // Drawing area
                    ZStack {
                        Color.white
                        
                        // Guide box with subtle grid
                        GeometryReader { geometry in
                            let boxSize: CGFloat = min(geometry.size.width, geometry.size.height) * 0.45
                            let centerX = geometry.size.width / 2
                            let centerY = geometry.size.height / 2
                            
                            ZStack {
                                // Outer box
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color("Blue 700").opacity(0.4), lineWidth: 2)
                                
                                // Center cross guides
                                Path { path in
                                    path.move(to: CGPoint(x: 0, y: boxSize / 2))
                                    path.addLine(to: CGPoint(x: boxSize, y: boxSize / 2))
                                    path.move(to: CGPoint(x: boxSize / 2, y: 0))
                                    path.addLine(to: CGPoint(x: boxSize / 2, y: boxSize))
                                }
                                .stroke(Color("Blue 700").opacity(0.15), style: StrokeStyle(lineWidth: 1, dash: [5, 5]))
                            }
                            .frame(width: boxSize, height: boxSize)
                            .position(x: centerX, y: centerY)
                        }
                        
                        // Drawing canvas
                        drawingCanvas
                    }
                    
                    // Bottom action bar
                    HStack(spacing: 12) {
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
                .navigationTitle("Flashcards")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
        .onAppear {
            if selectedSetId == nil { selectedSetId = store.activeSetId }
            if !inSession && !flashcardItems.isEmpty {
                prepareInitialPrompt()
            }
        }
    }


    private var drawingCanvas: some View {
        GeometryReader { _ in
            // Ink for completed strokes
            ForEach(viewModel.currentCharacter.strokes, id: \.id) { stroke in
                StrokePath(stroke: stroke)
                    .stroke(Color.black, lineWidth: 5)
            }
            // Ink for live stroke
            if let live = viewModel.currentStroke {
                StrokePath(stroke: live)
                    .stroke(Color.black.opacity(0.8), lineWidth: 5)
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


    private func startSession() {
        guard !flashcardItems.isEmpty else { return }
        inSession = true
        prepareInitialPrompt()
        viewModel.clear()
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
        viewModel.completeCurrentCharacter()
        // Analysis intentionally omitted for now per request
    }

    private func nextCard() {
        guard !flashcardItems.isEmpty else { return }
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

// MARK: - Notebook background and stroke path helpers

private struct NotebookBackground: View {
    var body: some View {
        GeometryReader { geo in
            let spacing: CGFloat = 36
            let count = Int(geo.size.height / spacing)
            Path { p in
                for i in 0...count {
                    let y = CGFloat(i) * spacing
                    p.move(to: CGPoint(x: 0, y: y))
                    p.addLine(to: CGPoint(x: geo.size.width, y: y))
                }
            }
            .stroke(Color.blue.opacity(0.15), lineWidth: 1)
        }
    }
}

private struct StrokePath: Shape {
    let stroke: Stroke
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = stroke.displayPoints.map { $0.location }
        guard points.count > 0 else { return path }
        
        if points.count == 1 {
            // Single point - draw a small circle
            path.addEllipse(in: CGRect(x: points[0].x - 2, y: points[0].y - 2, width: 4, height: 4))
            return path
        }
        
        if points.count == 2 {
            // Two points - draw a line
            path.move(to: points[0])
            path.addLine(to: points[1])
            return path
        }
        
        // Three or more points - use smooth curves
        path.move(to: points[0])
        
        // Use quadratic curves for smoothing
        for i in 1..<points.count {
            let current = points[i]
            let previous = points[i - 1]
            
            // Calculate midpoint for smooth curve
            let midPoint = CGPoint(
                x: (previous.x + current.x) / 2,
                y: (previous.y + current.y) / 2
            )
            
            if i == 1 {
                // First segment - curve from start to midpoint
                path.addQuadCurve(to: midPoint, control: previous)
            } else {
                // Subsequent segments - curve to midpoint using previous point as control
                path.addQuadCurve(to: midPoint, control: previous)
            }
        }
        
        // Final segment to last point
        if let last = points.last, points.count > 1 {
            let secondLast = points[points.count - 2]
            path.addQuadCurve(to: last, control: secondLast)
        }
        
        return path
    }
}

// Extract unique CJK characters from a string
private func extractHanzi(from text: String) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for scalar in text.unicodeScalars {
        let v = scalar.value
        if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0xF900...0xFAFF).contains(v) {
            let s = String(scalar)
            if !seen.contains(s) { seen.insert(s); result.append(s) }
        }
    }
    return result
}
