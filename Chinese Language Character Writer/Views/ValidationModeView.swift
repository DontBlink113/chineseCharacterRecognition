import SwiftUI

struct ValidationModeView: View {
    @StateObject private var viewModel = DrawingViewModel()
    @Environment(\.dismiss) var dismiss
    
    @State private var characterInput: String = ""
    @State private var selectedCharacter: String = ""
    @State private var showingLabelingSheet = false
    @State private var strokeLabels: [Int: Int?] = [:] // strokeIndex -> referenceStrokeIndex (nil = extra)
    @State private var referenceStrokeCount: Int = 0
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingEntriesList = false
    @State private var capturedStrokes: [Stroke] = [] // Capture strokes before clearing
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                headerView
                drawingAreaView
                bottomControlsView
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Close") { dismiss() }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingEntriesList = true }) {
                        Image(systemName: "list.bullet")
                    }
                }
            }
            .sheet(isPresented: $showingLabelingSheet) {
                StrokeLabelingSheet(
                    strokes: capturedStrokes,
                    referenceStrokeCount: referenceStrokeCount,
                    character: selectedCharacter,
                    onSave: saveEntry
                )
            }
            .sheet(isPresented: $showingEntriesList) {
                ValidationEntriesListView()
            }
            .alert("Validation Mode", isPresented: $showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
        }
    }
    
    private var headerView: some View {
        VStack(spacing: 12) {
            Text("Validation Mode")
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(Color("Blue 900"))
            
            characterInputRow
        }
        .padding()
        .background(Color(red: 0.68, green: 0.85, blue: 0.9).opacity(0.3))
    }
    
    private var characterInputRow: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                Text("Character:")
                    .font(.headline)
                    .foregroundColor(Color("Blue 700"))
                
                TextField("Type pinyin or character", text: $characterInput)
                    .font(.system(size: 18))
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onChange(of: characterInput) { newValue in
                        // If it's a single Chinese character, select it immediately
                        if newValue.count == 1 && isChinese(newValue) {
                            selectedCharacter = newValue
                            updateReferenceStrokeCount()
                        } else {
                            selectedCharacter = ""
                            referenceStrokeCount = 0
                        }
                    }
                
                if !selectedCharacter.isEmpty {
                    Text(selectedCharacter)
                        .font(.system(size: 32))
                        .padding(.horizontal, 8)
                        .background(Color.green.opacity(0.2))
                        .cornerRadius(8)
                }
            }
            
            // Show character suggestions if typing
            if !characterInput.isEmpty && selectedCharacter.isEmpty {
                characterSuggestions
            }
            
            if referenceStrokeCount > 0 {
                Text("(\(referenceStrokeCount) ref strokes)")
                    .font(.caption)
                    .foregroundColor(Color("Neutral 700"))
            }
        }
    }
    
    private var characterSuggestions: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(extractHanziFromInput(characterInput), id: \.self) { char in
                    Button(action: {
                        selectedCharacter = char
                        characterInput = char
                        updateReferenceStrokeCount()
                    }) {
                        Text(char)
                            .font(.system(size: 28))
                            .padding(8)
                            .background(Color("Blue 700").opacity(0.1))
                            .cornerRadius(8)
                    }
                }
            }
        }
        .frame(height: 50)
    }
    
    private func isChinese(_ text: String) -> Bool {
        guard let scalar = text.unicodeScalars.first else { return false }
        let value = scalar.value
        return (0x4E00...0x9FFF).contains(value) || 
               (0x3400...0x4DBF).contains(value) || 
               (0xF900...0xFAFF).contains(value)
    }
    
    private func extractHanziFromInput(_ text: String) -> [String] {
        var result: [String] = []
        for scalar in text.unicodeScalars {
            let v = scalar.value
            if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0xF900...0xFAFF).contains(v) {
                result.append(String(scalar))
            }
        }
        return result
    }
    
    private var drawingAreaView: some View {
        ZStack {
            Color.white
            guideBoxView
            drawingCanvas
        }
    }
    
    private var guideBoxView: some View {
        GeometryReader { geometry in
            let boxSize: CGFloat = min(geometry.size.width, geometry.size.height) * 0.6
            let centerX = geometry.size.width / 2
            let centerY = geometry.size.height / 2
            
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color("Blue 700").opacity(0.4), lineWidth: 2)
                
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
    }
    
    private var bottomControlsView: some View {
        VStack(spacing: 12) {
            HStack(spacing: 12) {
                undoButton
                clearButton
            }
            confirmButton
        }
        .padding()
        .background(Color(red: 0.68, green: 0.85, blue: 0.9).opacity(0.3))
    }
    
    private var undoButton: some View {
        Button(action: { _ = viewModel.undo() }) {
            HStack {
                Image(systemName: "arrow.uturn.backward")
                Text("Undo")
            }
            .font(.subheadline)
            .foregroundColor(Color("Blue 700"))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.white)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color("Blue 700"), lineWidth: 1)
            )
        }
    }
    
    private var clearButton: some View {
        Button(action: { viewModel.clear() }) {
            HStack {
                Image(systemName: "trash")
                Text("Clear")
            }
            .font(.subheadline)
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(Color.white)
            .cornerRadius(8)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.red, lineWidth: 1)
            )
        }
    }
    
    private var confirmButton: some View {
        Button(action: confirmDrawing) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("Confirm & Label Strokes")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(canConfirm ? Color("Blue 700") : Color.gray)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
        }
        .disabled(!canConfirm)
    }
    
    private var drawingCanvas: some View {
        GeometryReader { _ in
            ForEach(viewModel.currentCharacter.strokes, id: \.id) { stroke in
                StrokePath(stroke: stroke)
                    .stroke(Color.black, lineWidth: 5)
            }
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
    
    private var canConfirm: Bool {
        !selectedCharacter.isEmpty && !viewModel.currentCharacter.strokes.isEmpty
    }
    
    private func confirmDrawing() {
        // Capture strokes BEFORE completing (which clears them)
        capturedStrokes = viewModel.currentCharacter.strokes
        print("DEBUG: Captured \(capturedStrokes.count) strokes")
        
        viewModel.completeCurrentCharacter()
        showingLabelingSheet = true
    }
    
    private func updateReferenceStrokeCount() {
        guard !selectedCharacter.isEmpty else {
            referenceStrokeCount = 0
            return
        }
        
        let graphicsData = StrokeAnalyzer.loadGraphicsData()
        if let refChar = graphicsData[selectedCharacter] {
            referenceStrokeCount = refChar.medians.count
        } else {
            referenceStrokeCount = 0
        }
    }
    
    private func saveEntry(labelsData: [Int: (Int?, [Int])]) {
        // Use captured strokes, not viewModel strokes (which are cleared)
        let strokes = capturedStrokes
        var labeledStrokes: [LabeledStroke] = []
        
        print("DEBUG: Saving entry with \(strokes.count) strokes")
        print("DEBUG: Labels data: \(labelsData)")
        
        for (index, stroke) in strokes.enumerated() {
            let (groundTruthMatch, missingSubstrokes) = labelsData[index] ?? (nil, [])
            print("DEBUG: Stroke \(index) -> match: \(groundTruthMatch?.description ?? "nil"), missing: \(missingSubstrokes)")
            let labeledStroke = LabeledStroke.from(
                stroke: stroke,
                strokeIndex: index,
                groundTruthMatch: groundTruthMatch,
                missingSubstrokes: missingSubstrokes
            )
            labeledStrokes.append(labeledStroke)
        }
        
        let entry = ValidationEntry(
            character: selectedCharacter,
            userStrokes: labeledStrokes,
            referenceStrokeCount: referenceStrokeCount
        )
        
        do {
            try ValidationDatasetManager.shared.saveEntry(entry)
            alertMessage = "Entry saved successfully!"
            showingAlert = true
            
            // Reset for next entry
            viewModel.clear()
            characterInput = ""
            selectedCharacter = ""
            referenceStrokeCount = 0
        } catch {
            alertMessage = "Failed to save entry: \(error.localizedDescription)"
            showingAlert = true
        }
    }
}

// MARK: - Stroke Labeling Sheet

struct StrokeLabelingSheet: View {
    let strokes: [Stroke]
    let referenceStrokeCount: Int
    let character: String
    let onSave: ([Int: (Int?, [Int])]) -> Void // (groundTruthMatch, missingSubstrokes)
    
    @Environment(\.dismiss) var dismiss
    @State private var labels: [Int: Int?] = [:]
    @State private var missingSubstrokes: [Int: Set<Int>] = [:] // strokeIndex -> set of missing substroke numbers
    
    var body: some View {
        NavigationView {
            VStack(spacing: 16) {
                headerSection
                strokeListSection
                saveButtonSection
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .onAppear {
            // Don't pre-initialize - let user select for each stroke
            print("DEBUG: Showing labeling sheet with \(strokes.count) strokes")
        }
    }
    
    private var headerSection: some View {
        VStack(spacing: 8) {
            Text("Label Your Strokes")
                .font(.title2)
                .fontWeight(.bold)
            
            Text("Character: \(character)")
                .font(.headline)
                .foregroundColor(Color("Blue 700"))
            
            HStack(spacing: 16) {
                Text("You drew: \(strokes.count) strokes")
                    .font(.subheadline)
                    .foregroundColor(Color("Blue 700"))
                
                Text("Reference: \(referenceStrokeCount) strokes")
                    .font(.subheadline)
                    .foregroundColor(Color("Green"))
            }
        }
        .padding()
    }
    
    private var strokeListSection: some View {
        ScrollView {
            VStack(spacing: 12) {
                ForEach(Array(strokes.enumerated()), id: \.offset) { index, stroke in
                    StrokeLabelRow(
                        strokeIndex: index,
                        referenceStrokeCount: referenceStrokeCount,
                        selectedMatch: Binding(
                            get: { 
                                if let value = labels[index] {
                                    return value
                                }
                                return nil // Not set yet
                            },
                            set: { labels[index] = $0 }
                        ),
                        missingSubstrokes: Binding(
                            get: { missingSubstrokes[index] ?? [] },
                            set: { missingSubstrokes[index] = $0 }
                        )
                    )
                }
            }
            .padding()
        }
    }
    
    private var saveButtonSection: some View {
        Button(action: {
            // Combine labels and missing substrokes
            var combinedData: [Int: (Int?, [Int])] = [:]
            for index in 0..<strokes.count {
                let match = labels[index] ?? nil
                let missing = Array(missingSubstrokes[index] ?? []).sorted()
                combinedData[index] = (match, missing)
            }
            onSave(combinedData)
            dismiss()
        }) {
            HStack {
                Image(systemName: "checkmark.circle.fill")
                Text("Save Entry")
            }
            .font(.headline)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(allStrokesLabeled ? Color.green : Color.gray)
            .cornerRadius(12)
        }
        .disabled(!allStrokesLabeled)
        .padding()
    }
    
    private var allStrokesLabeled: Bool {
        // Check that every stroke has been labeled
        for index in 0..<strokes.count {
            // labels[index] should exist in the dictionary
            guard labels.keys.contains(index) else {
                return false
            }
        }
        return true
    }
}

// MARK: - Stroke Label Row

struct StrokeLabelRow: View {
    let strokeIndex: Int
    let referenceStrokeCount: Int
    @Binding var selectedMatch: Int??
    @Binding var missingSubstrokes: Set<Int>
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                strokeLabel
                selectionMenu
                Spacer()
                statusIndicator
            }
            
            // Missing substrokes section (only show if stroke is matched)
            if let outerMatch = selectedMatch, outerMatch != nil {
                missingSubstrokesSection
            }
        }
        .padding()
        .background(Color.white)
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 2, x: 0, y: 1)
    }
    
    private var strokeLabel: some View {
        Text("Stroke \(strokeIndex + 1):")
            .font(.headline)
            .frame(width: 100, alignment: .leading)
    }
    
    private var selectionMenu: some View {
        Menu {
            ForEach(0..<referenceStrokeCount, id: \.self) { refIndex in
                Button("Ref Stroke \(refIndex + 1)") {
                    selectedMatch = refIndex
                }
            }
            Divider()
            Button("Extra (No Match)") {
                selectedMatch = .some(nil)
            }
        } label: {
            menuLabel
        }
    }
    
    private var menuLabel: some View {
        HStack {
            if let outerMatch = selectedMatch, let match = outerMatch {
                Text("Ref \(match + 1)")
                    .foregroundColor(Color("Blue 700"))
            } else if selectedMatch != nil {
                Text("Extra")
                    .foregroundColor(.orange)
            } else {
                Text("Select...")
                    .foregroundColor(.gray)
            }
            Image(systemName: "chevron.down")
                .font(.caption)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white)
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
        )
    }
    
    private var statusIndicator: some View {
        Group {
            if let outerMatch = selectedMatch, outerMatch != nil {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else if selectedMatch != nil {
                Image(systemName: "xmark.circle.fill")
                    .foregroundColor(.orange)
            }
        }
    }
    
    private var missingSubstrokesSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Missing Substrokes:")
                .font(.caption)
                .foregroundColor(.gray)
            
            HStack(spacing: 12) {
                ForEach(1...4, id: \.self) { substrokeNum in
                    Button(action: {
                        if missingSubstrokes.contains(substrokeNum) {
                            missingSubstrokes.remove(substrokeNum)
                        } else {
                            missingSubstrokes.insert(substrokeNum)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: missingSubstrokes.contains(substrokeNum) ? "checkmark.square.fill" : "square")
                                .foregroundColor(missingSubstrokes.contains(substrokeNum) ? .red : .gray)
                            Text("\(substrokeNum)")
                                .font(.caption)
                                .foregroundColor(missingSubstrokes.contains(substrokeNum) ? .red : .gray)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(missingSubstrokes.contains(substrokeNum) ? Color.red.opacity(0.1) : Color.gray.opacity(0.1))
                        .cornerRadius(6)
                    }
                }
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Helper Views

private struct StrokePath: Shape {
    let stroke: Stroke
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let points = stroke.displayPoints.map { $0.location }
        guard !points.isEmpty else { return path }
        
        path.move(to: points[0])
        for i in 1..<points.count {
            path.addLine(to: points[i])
        }
        
        return path
    }
}
