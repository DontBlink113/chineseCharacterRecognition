import SwiftUI

struct FlashcardPracticeView: View {
    @EnvironmentObject var store: LearningSetsStore
    @StateObject private var viewModel = DrawingViewModel()

    @State private var selectedSetId: UUID? = nil
    @State private var shuffle: Bool = false
    @State private var inSession: Bool = false

    @State private var currentIndex: Int = 0
    @State private var currentPrompt: String = ""

    private var selectedSet: LearningSet? {
        if let id = selectedSetId { return store.sets.first { $0.id == id } }
        return store.activeSet
    }

    private var charactersInSet: [String] {
        guard let s = selectedSet else { return [] }
        return extractHanzi(from: s.characters)
    }

    var body: some View {
        VStack(spacing: 12) {
            if !inSession { //conditional view
                // Setup UI
                
                Form {
                    Section(header: Text("Select Set")) {
                        if store.sets.isEmpty {
                            Text("No sets available. Create one on the Home screen or Manage in the writer.")
                                .foregroundColor(.secondary)
                        } else {
                            Picker("Learning Set", selection: Binding(
                                get: { selectedSetId ?? store.activeSetId },
                                set: { selectedSetId = $0 }
                            )) {
                                ForEach(store.sets) { set in
                                    Text(set.name).tag(Optional(set.id))
                                }
                            }
                            Toggle("Shuffle", isOn: $shuffle)
                        }
                    }
                    Section {
                        Button(action: startSession) {
                            Text("Start Flashcards")
                                .frame(maxWidth: .infinity)
                        }
                        .disabled(charactersInSet.isEmpty)
                    }
                }
            } else {
                // In-session UI
                header
                drawingCanvas
                controls
            }
        }
        .navigationTitle("Flashcards")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if selectedSetId == nil { selectedSetId = store.activeSetId }
            if !inSession && !charactersInSet.isEmpty {
                prepareInitialPrompt()
            }
        }
    }

    private var header: some View {
        VStack(spacing: 8) {

            Text(currentPrompt)
                .font(.system(size: 44, weight: .bold))
                .foregroundColor(.blue)
                .padding(.horizontal)
        }
    }

    private var drawingCanvas: some View {
        ZStack {
            NotebookBackground()
                .foregroundColor(Color.blue.opacity(0.08))
                .ignoresSafeArea(edges: .bottom)

            GeometryReader { _ in
                // Ink for completed strokes
                ForEach(viewModel.currentCharacter.strokes, id: \.id) { stroke in
                    StrokePath(stroke: stroke)
                        .stroke(Color.primary, lineWidth: 4)
                }
                // Ink for live stroke
                if let live = viewModel.currentStroke {
                    StrokePath(stroke: live)
                        .stroke(Color.primary.opacity(0.8), lineWidth: 4)
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
            .padding()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var controls: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                Button(action: { _ = viewModel.undo() }) {
                    Label("Undo", systemImage: "arrow.uturn.left")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: { viewModel.clear() }) {
                    Label("Clear", systemImage: "trash")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
            .padding(.horizontal)

            Button(action: finishCharacter) {
                Text("Feedback")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .padding(.horizontal)

            Button(action: nextCard) {
                Text("Next")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .padding(.horizontal)
            .padding(.bottom, 8)
        }
    }

    private func startSession() {
        guard !charactersInSet.isEmpty else { return }
        inSession = true
        prepareInitialPrompt()
        viewModel.clear()
    }

    private func prepareInitialPrompt() {
        if shuffle {
            currentIndex = Int.random(in: 0..<charactersInSet.count)
        } else {
            currentIndex = 0
        }
        currentPrompt = charactersInSet.isEmpty ? "" : charactersInSet[currentIndex]
    }

    private func finishCharacter() {
        viewModel.completeCurrentCharacter()
        // Analysis intentionally omitted for now per request
    }

    private func nextCard() {
        guard !charactersInSet.isEmpty else { return }
        if shuffle {
            currentIndex = Int.random(in: 0..<charactersInSet.count)
        } else {
            currentIndex = (currentIndex + 1) % charactersInSet.count
        }
        currentPrompt = charactersInSet[currentIndex]
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
        guard let first = stroke.points.first else { return path }
        path.move(to: first.location)
        for pt in stroke.points.dropFirst() {
            path.addLine(to: pt.location)
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
