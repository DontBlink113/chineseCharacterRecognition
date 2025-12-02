import SwiftUI

struct CharacterDataView: View {
    let character: CharacterDrawing
    
    private func timeRangeString(from start: TimeInterval, to end: TimeInterval) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.timeStyle = .medium
        dateFormatter.dateStyle = .none
        
        let startDate = Date(timeIntervalSince1970: start)
        let endDate = Date(timeIntervalSince1970: end)
        
        return "\(dateFormatter.string(from: startDate)) - \(dateFormatter.string(from: endDate))"
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Character Summary
                VStack(alignment: .leading) {
                    Text("Character Summary")
                        .font(.headline)
                        .padding(.bottom, 4)
                    
                    HStack {
                        VStack(alignment: .leading) {
                            Text("\(character.strokes.count) strokes")
                            Text("\(character.totalSubstrokes) substrokes")
                            Text(String(format: "%.1f pts/sec", character.averageStrokeSpeed))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        VStack(alignment: .leading) {
                            Text("\(character.totalPoints) points")
                            Text(String(format: "%.2f sec", character.duration))
                            Text(timeRangeString(from: character.startTime, to: character.endTime))
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
                
                // Strokes List
                VStack(alignment: .leading, spacing: 16) {
                    Text("Strokes")
                        .font(.headline)
                    
                    ForEach(Array(character.strokes.enumerated()), id: \.offset) { index, stroke in
                        StrokeDetailView(stroke: stroke, strokeNumber: index + 1)
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(10)
            }
            .padding()
        }
        .navigationTitle("Character Data")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct StrokeDetailView: View {
    let stroke: Stroke
    let strokeNumber: Int
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Stroke \(strokeNumber)")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(stroke.points.count) points • \(stroke.substrokes.count) substrokes")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            if !stroke.substrokes.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(stroke.substrokes.enumerated()), id: \.offset) { index, substroke in
                        HStack {
                            Text("• Substroke \(index + 1):")
                                .font(.caption)
                            Text(String(format: "%.2f rad • ", substroke.angle))
                                .font(.caption.monospaced())
                            Text(String(format: "%.1f pts", substroke.magnitude))
                                .font(.caption.monospaced())
                            Text("@ (\(Int(substroke.center.x)), \(Int(substroke.center.y)))")
                                .font(.caption.monospaced())
                        }
                    }
                }
                .padding(.leading, 8)
            }
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(8)
    }
    
}

// MARK: - Preview

struct CharacterDataView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationView {
            CharacterDataView(character: createSampleCharacter())
        }
    }
    
    static func createSampleCharacter() -> CharacterDrawing {
        var character = CharacterDrawing()
        var stroke = Stroke()
        
        // Add some sample points
        for i in 0..<10 {
            stroke.addPoint(StrokePoint(location: CGPoint(x: i * 10, y: i * 5)))
        }
        
        // Trigger substroke detection
        stroke.detectSubstrokes()
        
        character.addStroke(stroke)
        return character
    }
}
