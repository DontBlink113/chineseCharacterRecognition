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
    private let analyzer = CharacterAnalyzer.shared


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
                // Character mode toggle
                Button(action: {
                    viewModel.toggleCharacterMode()
                }) {
                    HStack {
                        Image(systemName: viewModel.isInCharacterMode ? "character.cursor.ibeam" : "character")
                        Text(viewModel.isInCharacterMode ? "Character Mode: ON" : "Character Mode: OFF")
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(viewModel.isInCharacterMode ? Color.blue : Color.gray)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .padding(.horizontal)
                
                HStack(spacing: 16) {
                    // Complete character button
                    Button(action: {
                        viewModel.completeCurrentCharacter()
                    }) {
                        Text("Complete Character")
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
                
                // Show Specific Character button (styled like "Show Random Character")
                Button(action: {
                    inputCharacter = ""
                    inputError = nil
                    showCharacterInput = true
                }) {
                    Text("Show Specific Character")
                        .font(.headline)
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .cornerRadius(10)
                }
                .padding(.horizontal)
                .sheet(isPresented: $showCharacterInput) {
                    NavigationView {
                        VStack(spacing: 16) {
                            Text("Enter a Chinese character")
                                .font(.headline)
                            TextField("e.g. 你", text: $inputCharacter)
                                .textFieldStyle(RoundedBorderTextFieldStyle())
                                .padding(.horizontal)
                            if let error = inputError {
                                Text(error)
                                    .foregroundColor(.red)
                                    .font(.footnote)
                            }
                            HStack {
                                Button("Cancel") {
                                    inputCharacter = ""
                                    inputError = nil
                                    showCharacterInput = false
                                }
                                Spacer()
                                Button("Show") {
                                    let query = inputCharacter.trimmingCharacters(in: .whitespacesAndNewlines)
                                    if query.isEmpty {
                                        inputError = "Please enter a character."
                                    } else if let result = analyzer.analyze(character: query) {
                                        datasetCharacter = result
                                        inputError = nil
                                        showCharacterInput = false
                                        withAnimation { isPanelVisible = true }
                                    } else {
                                        inputError = "Character not found in dataset."
                                    }
                                }
                            }
                            .padding(.horizontal)
                            Spacer()
                        }
                        .padding()
                    }
                }
            }
            .padding(.vertical, 8)
            .background(Color(UIColor.systemGroupedBackground))
            
            // Add View Data button
            Button(action: {
                showingCharacterData.toggle()
            }) {
                Text("View Character Data")
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
            }
            .padding(.horizontal)
            .disabled(viewModel.currentCharacter.strokes.isEmpty && viewModel.characters.isEmpty)
        }
        .overlay(alignment: .trailing) {
            if isPanelVisible {
                RightSidePanel(
                    datasetCharacter: datasetCharacter,
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
                            DatasetCharacterPanel(character: char)
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
            }
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
            
            // Substrokes
            if !character.substrokes.isEmpty {
                SubStrokesView(substrokes: character.substrokes)
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
