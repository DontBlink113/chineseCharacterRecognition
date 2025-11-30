import SwiftUI

struct StrokeTestView: View {
    @StateObject private var viewModel = DrawingViewModel()
    @State private var showInfo = false
    @State private var showingCharacterData = false
    @State private var selectedCharacter: CharacterDrawing?
    
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
            }
            .padding(.vertical, 8)
            .background(Color(UIColor.systemGroupedBackground))
            
            // Add View Data button
            Button(action: {
                showingCharacterData = true
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
            .sheet(isPresented: $showingCharacterData) {
                NavigationView {
                    if !viewModel.currentCharacter.strokes.isEmpty {
                        CharacterDataView(character: viewModel.currentCharacter)
                    } else if let lastCharacter = viewModel.characters.last {
                        CharacterDataView(character: lastCharacter)
                    }
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
            Text(String(format: "%.1f°, %.1f", substroke.angle * 180 / .pi, substroke.magnitude))
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(.black)
                .padding(4)
                .background(Color.white.opacity(0.7))
                .cornerRadius(4)
                .position(x: substroke.center.x, y: substroke.center.y + 20)
        }
    }
}

// MARK: - Preview

struct StrokeTestView_Previews: PreviewProvider {
    static var previews: some View {
        StrokeTestView()
    }
}
