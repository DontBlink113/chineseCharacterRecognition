import SwiftUI

struct DataAugmentationSheet: View {
    let originalEntry: ValidationEntry
    @Environment(\.dismiss) var dismiss
    @State private var selectedAugmentations: Set<AugmentationType> = []
    @State private var previewData: PreviewData?
    @State private var showingAlert = false
    @State private var alertMessage = ""
    
    struct PreviewData: Identifiable {
        let id = UUID()
        let entries: [ValidationEntry]
    }
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Original entry info
                originalEntrySection
                
                Divider()
                
                // Augmentation options
                ScrollView {
                    VStack(spacing: 16) {
                        Text("Select Augmentation Types")
                            .font(.headline)
                            .padding(.top)
                        
                        ForEach(AugmentationType.allCases, id: \.self) { type in
                            AugmentationOptionRow(
                                type: type,
                                isSelected: selectedAugmentations.contains(type),
                                onToggle: {
                                    if selectedAugmentations.contains(type) {
                                        selectedAugmentations.remove(type)
                                    } else {
                                        selectedAugmentations.insert(type)
                                    }
                                }
                            )
                        }
                    }
                    .padding()
                }
                
                Divider()
                
                // Action buttons
                actionButtonsSection
            }
            .navigationTitle("Data Augmentation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Augmentation", isPresented: $showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            .sheet(item: $previewData) { data in
                AugmentationPreviewSheet(
                    originalEntry: originalEntry,
                    augmentedEntries: data.entries,
                    onSave: saveAugmentedEntries
                )
            }
        }
    }
    
    private var originalEntrySection: some View {
        VStack(spacing: 8) {
            Text("Original Entry")
                .font(.headline)
            
            HStack(spacing: 16) {
                Text("Character: \(originalEntry.character)")
                    .font(.title)
                    .fontWeight(.bold)
                
                Text("\(originalEntry.userStrokes.count) strokes")
                    .font(.subheadline)
                    .foregroundColor(.gray)
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
    }
    
    private var actionButtonsSection: some View {
        VStack(spacing: 12) {
            Button(action: generatePreview) {
                HStack {
                    Image(systemName: "eye")
                    Text("Preview Augmentations")
                }
                .font(.headline)
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(selectedAugmentations.isEmpty ? Color.gray : Color.blue)
                .cornerRadius(12)
            }
            .disabled(selectedAugmentations.isEmpty)
            
            Text(estimatedCountMessage)
                .font(.caption)
                .foregroundColor(originalEntry.userStrokes.count < 2 ? .red : .gray)
        }
        .padding()
    }
    
    private var estimatedCountMessage: String {
        let strokeCount = originalEntry.userStrokes.count
        
        if strokeCount < 2 {
            return "⚠️ Need at least 2 strokes (entry has \(strokeCount))"
        }
        
        if selectedAugmentations.isEmpty {
            return "Select at least one augmentation type"
        }
        
        return "Will generate ~\(estimatedCount) variations"
    }
    
    private var estimatedCount: Int {
        var count = 0
        let strokeCount = originalEntry.userStrokes.count
        
        if selectedAugmentations.contains(.swapAdjacent) {
            count += max(0, strokeCount - 1) // Each adjacent pair
        }
        if selectedAugmentations.contains(.swapRandom) {
            count += min(5, strokeCount * (strokeCount - 1) / 4) // ~5 random swaps
        }
        if selectedAugmentations.contains(.reverseAll) {
            count += 1
        }
        if selectedAugmentations.contains(.removeOne) {
            count += strokeCount // One for each stroke removed
        }
        if selectedAugmentations.contains(.removeTwo) {
            count += min(10, strokeCount * (strokeCount - 1) / 2) // Up to 10 combinations
        }
        
        return count
    }
    
    private func generatePreview() {
        let strokeCount = originalEntry.userStrokes.count
        
        print("DEBUG: generatePreview called")
        print("DEBUG: Stroke count: \(strokeCount)")
        print("DEBUG: Selected augmentations: \(selectedAugmentations)")
        
        // Check if entry has enough strokes
        if strokeCount < 2 {
            alertMessage = "Cannot augment: Entry has only \(strokeCount) stroke(s). Need at least 2 strokes for augmentation."
            showingAlert = true
            return
        }
        
        // Check if selected augmentations are compatible
        var incompatibleTypes: [String] = []
        
        if selectedAugmentations.contains(.removeTwo) && strokeCount < 3 {
            incompatibleTypes.append("Remove Two (needs ≥3 strokes)")
        }
        
        if !incompatibleTypes.isEmpty {
            alertMessage = "Incompatible augmentations for \(strokeCount) strokes:\n" + incompatibleTypes.joined(separator: "\n")
            showingAlert = true
            return
        }
        
        let augmenter = DataAugmenter()
        let generatedEntries = augmenter.generateAugmentations(
            from: originalEntry,
            types: Array(selectedAugmentations)
        )
        
        print("DEBUG: Generated \(generatedEntries.count) entries")
        
        if generatedEntries.isEmpty {
            alertMessage = "No augmentations could be generated. Entry has \(strokeCount) strokes. Try different options."
            showingAlert = true
        } else {
            print("DEBUG: Setting previewData with \(generatedEntries.count) entries")
            previewData = PreviewData(entries: generatedEntries)
        }
    }
    
    private func saveAugmentedEntries(_ entries: [ValidationEntry]) {
        do {
            for entry in entries {
                try ValidationDatasetManager.shared.saveEntry(entry)
            }
            alertMessage = "Successfully saved \(entries.count) augmented entries!"
            showingAlert = true
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                dismiss()
            }
        } catch {
            alertMessage = "Failed to save entries: \(error.localizedDescription)"
            showingAlert = true
        }
    }
}

// MARK: - Augmentation Types

enum AugmentationType: String, CaseIterable {
    case swapAdjacent = "Swap Adjacent Strokes"
    case swapRandom = "Random Swaps"
    case reverseAll = "Reverse All Strokes"
    case removeOne = "Remove One Stroke"
    case removeTwo = "Remove Two Strokes"
    
    var description: String {
        switch self {
        case .swapAdjacent:
            return "Swap each pair of adjacent strokes (e.g., 0↔1, 1↔2, etc.)"
        case .swapRandom:
            return "Create ~5 random stroke order variations"
        case .reverseAll:
            return "Completely reverse the stroke order"
        case .removeOne:
            return "Create variations with each stroke removed one at a time"
        case .removeTwo:
            return "Create variations with pairs of strokes removed"
        }
    }
    
    var icon: String {
        switch self {
        case .swapAdjacent:
            return "arrow.left.arrow.right"
        case .swapRandom:
            return "shuffle"
        case .reverseAll:
            return "arrow.turn.up.left"
        case .removeOne:
            return "minus.circle"
        case .removeTwo:
            return "minus.circle.fill"
        }
    }
}

// MARK: - Augmentation Option Row

struct AugmentationOptionRow: View {
    let type: AugmentationType
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(systemName: type.icon)
                    .font(.title2)
                    .foregroundColor(isSelected ? .blue : .gray)
                    .frame(width: 30)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(type.rawValue)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Text(type.description)
                        .font(.caption)
                        .foregroundColor(.gray)
                        .multilineTextAlignment(.leading)
                }
                
                Spacer()
                
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundColor(isSelected ? .blue : .gray)
            }
            .padding()
            .background(isSelected ? Color.blue.opacity(0.1) : Color.white)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? Color.blue : Color.gray.opacity(0.3), lineWidth: 1)
            )
        }
    }
}

// MARK: - Preview Sheet

struct AugmentationPreviewSheet: View {
    let originalEntry: ValidationEntry
    let augmentedEntries: [ValidationEntry]
    let onSave: ([ValidationEntry]) -> Void
    
    @Environment(\.dismiss) var dismiss
    @State private var selectedEntries: Set<UUID> = []
    @State private var selectAll = true
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Header
                VStack(spacing: 8) {
                    Text("Generated \(augmentedEntries.count) Variations")
                        .font(.headline)
                    
                    Text("Original: \(originalEntry.character) (\(originalEntry.userStrokes.count) strokes)")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                    
                    Toggle("Select All", isOn: $selectAll)
                        .onChange(of: selectAll) { newValue in
                            if newValue {
                                selectedEntries = Set(augmentedEntries.map { $0.id })
                            } else {
                                selectedEntries.removeAll()
                            }
                        }
                        .padding(.horizontal)
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                
                Divider()
                
                // List of augmented entries
                List {
                    ForEach(Array(augmentedEntries.enumerated()), id: \.element.id) { index, entry in
                        AugmentedEntryRow(
                            index: index + 1,
                            entry: entry,
                            originalEntry: originalEntry,
                            isSelected: selectedEntries.contains(entry.id),
                            onToggle: {
                                if selectedEntries.contains(entry.id) {
                                    selectedEntries.remove(entry.id)
                                } else {
                                    selectedEntries.insert(entry.id)
                                }
                            }
                        )
                    }
                }
                
                Divider()
                
                // Save button
                Button(action: {
                    let entriesToSave = augmentedEntries.filter { selectedEntries.contains($0.id) }
                    onSave(entriesToSave)
                    dismiss()
                }) {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                        Text("Save \(selectedEntries.count) Entries")
                    }
                    .font(.headline)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(selectedEntries.isEmpty ? Color.gray : Color.green)
                    .cornerRadius(12)
                }
                .disabled(selectedEntries.isEmpty)
                .padding()
            }
            .navigationTitle("Preview")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onAppear {
                print("DEBUG: Preview sheet appeared with \(augmentedEntries.count) entries")
                selectedEntries = Set(augmentedEntries.map { $0.id })
            }
        }
    }
}

// MARK: - Augmented Entry Row

struct AugmentedEntryRow: View {
    let index: Int
    let entry: ValidationEntry
    let originalEntry: ValidationEntry
    let isSelected: Bool
    let onToggle: () -> Void
    
    var body: some View {
        Button(action: onToggle) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                        .foregroundColor(isSelected ? .blue : .gray)
                    
                    Text("Variation #\(index)")
                        .font(.headline)
                    
                    Spacer()
                    
                    Text("\(entry.userStrokes.count) strokes")
                        .font(.caption)
                        .foregroundColor(.gray)
                }
                
                // Show stroke mapping
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(entry.userStrokes) { stroke in
                            StrokeMappingBadge(
                                strokeIndex: stroke.strokeIndex,
                                groundTruthMatch: stroke.groundTruthMatch,
                                missingSubstrokes: stroke.missingSubstrokes
                            )
                        }
                    }
                }
                
                // Show what changed
                if let changeDescription = describeChange() {
                    Text(changeDescription)
                        .font(.caption)
                        .foregroundColor(.orange)
                        .italic()
                }
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func describeChange() -> String? {
        let origCount = originalEntry.userStrokes.count
        let newCount = entry.userStrokes.count
        
        if newCount < origCount {
            let removed = origCount - newCount
            return "Removed \(removed) stroke\(removed > 1 ? "s" : "")"
        } else if newCount == origCount {
            // Check if order changed
            let orderChanged = entry.userStrokes.enumerated().contains { index, stroke in
                stroke.strokeIndex != originalEntry.userStrokes[index].strokeIndex
            }
            if orderChanged {
                return "Stroke order changed"
            }
        }
        return nil
    }
}

// MARK: - Stroke Mapping Badge

struct StrokeMappingBadge: View {
    let strokeIndex: Int
    let groundTruthMatch: Int?
    let missingSubstrokes: [Int]
    
    var body: some View {
        VStack(spacing: 2) {
            HStack(spacing: 2) {
                Text("\(strokeIndex + 1)")
                    .font(.caption2)
                    .fontWeight(.bold)
                
                Image(systemName: "arrow.right")
                    .font(.system(size: 8))
                
                if let match = groundTruthMatch {
                    Text("R\(match + 1)")
                        .font(.caption2)
                        .fontWeight(.bold)
                } else {
                    Text("X")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
            }
            
            if !missingSubstrokes.isEmpty {
                Text("M:\(missingSubstrokes.map(String.init).joined(separator: ","))")
                    .font(.system(size: 6))
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(groundTruthMatch != nil ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
        .cornerRadius(4)
    }
}
