//
//  ContentView.swift
//  Chinese Language Character Writer
//
//  Created by Keane Haesle on 11/18/25.
//

import SwiftUI
import PencilKit

struct ContentView: View {
    @State private var canvasView = PKCanvasView()
    @State private var toolPicker = PKToolPicker()
    @State private var showAnalysis = false
    @State private var currentAnalysis: Character?
    @State private var showRandomCharacter = false
    @State private var randomCharacter: Character?
    
    private let viewModel = CharacterAnalysisViewModel()
    private let analyzer = CharacterAnalyzer.shared
    
    var body: some View {
        NavigationView {
            ZStack {
                // Lined Paper Background
                LinedPaperView()
                    .edgesIgnoringSafeArea(.all)
                
                // Main Content
                VStack {
                    // Drawing Canvas with native tool picker
                    CanvasView(canvasView: $canvasView, toolPicker: toolPicker)
                    
                    // Buttons Stack
                    VStack(spacing: 12) {
                        // Analysis button
                        Button(action: analyzeDrawing) {
                            Text("Analyze Character")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.blue)
                                .cornerRadius(10)
                        }
                        .disabled(canvasView.drawing.strokes.isEmpty)
                        .opacity(canvasView.drawing.strokes.isEmpty ? 0.5 : 1.0)
                    
                    }
                    .padding(.horizontal)
                    .padding(.bottom)
                }
                
                // Analysis overlay
                if let analysis = currentAnalysis, showAnalysis {
                    CharacterAnalysisView(analysis: analysis, isPresented: $showAnalysis)
                        .transition(.move(edge: .bottom))
                }
                
                // Random Character overlay
                if showRandomCharacter, let char = randomCharacter {
                    RandomCharacterView(character: char, isPresented: $showRandomCharacter)
                        .transition(.move(edge: .bottom))
                        .zIndex(1)
                }
            }
            .navigationTitle("Chinese Character Writer")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: clearCanvas) {
                        Image(systemName: "trash")
                    }
                }
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
        .onAppear {
            toolPicker.setVisible(true, forFirstResponder: canvasView)
            toolPicker.addObserver(canvasView)
            canvasView.becomeFirstResponder()
        }
    }
    
    private func analyzeDrawing() {
        // In a real app, you would use a proper character recognition model here
        // For now, we'll just show a sample analysis
        let sampleCharacter = "你" // This would come from character recognition
        viewModel.characters = [sampleCharacter]
        viewModel.analyzeCharacters()
        
        if let analysis = viewModel.analysisResults.first {
            currentAnalysis = analysis
            withAnimation {
                showAnalysis = true
            }
        }
    }
    
    
    private func clearCanvas() {
        canvasView.drawing = PKDrawing()
        withAnimation {
            showAnalysis = false
        }
    }
}

// MARK: - Character Header View
struct CharacterHeaderView: View {
    let onClose: () -> Void
    
    var body: some View {
        HStack {
            Text("Character Analysis")
                .font(.title2.bold())
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(.gray)
            }
        }
        .padding(.bottom, 8)
    }
}

// MARK: - Character Display View
struct CharacterDisplayView: View {
    let character: String
    
    var body: some View {
        Text(character)
            .font(.system(size: 80, weight: .medium))
            .frame(maxWidth: .infinity)
            .frame(height: 150)
            .background(Color.blue.opacity(0.1))
            .cornerRadius(12)
    }
}

// MARK: - Character Info View
struct CharacterInfoView: View {
    let strokeCount: Int
    let substrokeCount: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            InfoRow(title: "Stroke Count", value: "\(strokeCount)")
            InfoRow(title: "Substroke Count", value: "\(substrokeCount)")
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Substroke Item View
struct SubstrokeItemView: View {
    let index: Int
    let substroke: CharacterSubstroke
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(index + 1). Direction: \(String(format: "%.2f", substroke.direction)) rad")
            Text("   Length: \(String(format: "%.2f", substroke.length))")
            Text("   Center: (\(String(format: "%.2f", substroke.centerX)), \(String(format: "%.2f", substroke.centerY)))")
        }
        .font(.subheadline.monospaced())
        .padding()
        .background(index % 2 == 0 ? Color(.systemGray6) : Color(.systemBackground))
        .cornerRadius(8)
    }
}

// MARK: - Sub-strokes View
struct SubStrokesView: View {
    let substrokes: [CharacterSubstroke]
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeaderView(title: "Sub-strokes")
            
            ForEach(Array(substrokes.enumerated()), id: \.offset) { index, substroke in
                SubstrokeItemView(index: index, substroke: substroke)
            }
        }
        .padding(.top)
    }
}

// MARK: - Character Analysis View
struct CharacterAnalysisView: View {
    let analysis: Character
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Header
                    CharacterHeaderView {
                        isPresented = false
                    }
                    
                    // Character Display
                    CharacterDisplayView(character: analysis.character)
                    
                    // Character Info
                    CharacterInfoView(
                        strokeCount: analysis.strokeCount,
                        substrokeCount: analysis.substrokeCount
                    )
                    
                    // Sub-strokes Section
                    if !analysis.substrokes.isEmpty {
                        SubStrokesView(substrokes: analysis.substrokes)
                    }
                    
                    // Space for future sections
                    
                }
                .padding()
            }
            .shadow(color: .black.opacity(0.1), radius: 5, x: 0, y: 2)
            .padding()
        }
    }
}

// MARK: - Random Character View

struct RandomCharacterView: View {
    let character: Character
    @Binding var isPresented: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                Text("Character Details")
                    .font(.title2.bold())
                Spacer()
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundColor(.gray)
                }
            }
            .padding()
            
            Divider()
            
            ScrollView {
                VStack(spacing: 20) {
                    // Character Display
                    Text(character.character)
                        .font(.system(size: 100))
                        .frame(height: 150)
                        .frame(maxWidth: .infinity)
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                    
                    // Character Info
                    VStack(alignment: .leading, spacing: 12) {
                        InfoRow(title: "Stroke Count", value: "\(character.strokeCount)")
                        InfoRow(title: "Substroke Count", value: "\(character.substrokeCount)")
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                    
                    // Sub-strokes
                    if !character.substrokes.isEmpty {
                        SubStrokesView(substrokes: character.substrokes)
                    }
                }
                .padding()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: UIScreen.main.bounds.height * 0.8)
        .background(Color(.systemBackground))
        .cornerRadius(20)
        .shadow(radius: 10)
        .padding()
    }
}

// MARK: - Subviews

struct InfoRow: View {
    let title: String
    let value: String
    
    var body: some View {
        HStack {
            Text(title)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
    }
}

private struct SectionHeaderView: View {
        let title: String
        
        var body: some View {
            Text(title)
                .font(.headline)
                .foregroundColor(.primary)
        }
    }
    
private struct StatView: View {
    let value: String
    let label: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(.caption2)
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 16, weight: .semibold))
        }
    }
}

// MARK: - Lined Paper View

struct LinedPaperView: View {
        var lineSpacing: CGFloat = 44 // Slightly larger for better touch targets
        var lineColor: Color = .gray.opacity(0.3)
        
        var body: some View {
            GeometryReader { geometry in
                let lineCount = Int(geometry.size.height / lineSpacing) + 1
                
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(0..<lineCount, id: \.self) { _ in
                            Rectangle()
                                .frame(height: 1)
                                .foregroundColor(lineColor)
                                .padding(.horizontal, 40)
                            Spacer()
                                .frame(height: lineSpacing - 1)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    .background(Color.white)
                }
            }
            .background(Color(UIColor.systemGray6))
        }
    }
    
// MARK: - Preview

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
