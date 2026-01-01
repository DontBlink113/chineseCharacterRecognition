import SwiftUI

struct ValidationEntriesListView: View {
    @Environment(\.dismiss) var dismiss
    @State private var entries: [ValidationEntry] = []
    @State private var isLoading = true
    @State private var showingAlert = false
    @State private var alertMessage = ""
    @State private var showingDeleteConfirmation = false
    @State private var entryToDelete: ValidationEntry?
    @State private var showingShareSheet = false
    @State private var entryToAugment: ValidationEntry?
    @State private var showingClearAllConfirmation = false
    @State private var showingValidationTest = false
    @State private var isEditMode = false
    @State private var selectedEntries: Set<UUID> = []
    @State private var showingDeleteSelectedConfirmation = false
    
    var body: some View {
        NavigationView {
            Group {
                if isLoading {
                    ProgressView("Loading entries...")
                } else if entries.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "tray")
                            .font(.system(size: 60))
                            .foregroundColor(.gray)
                        Text("No validation entries yet")
                            .font(.headline)
                            .foregroundColor(.gray)
                        Text("Create entries in validation mode")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                } else {
                    List {
                        Section(header: sectionHeader) {
                            ForEach(entries) { entry in
                                HStack {
                                    if isEditMode {
                                        Button(action: {
                                            toggleSelection(entry.id)
                                        }) {
                                            Image(systemName: selectedEntries.contains(entry.id) ? "checkmark.circle.fill" : "circle")
                                                .foregroundColor(selectedEntries.contains(entry.id) ? .blue : .gray)
                                                .font(.title3)
                                        }
                                        .buttonStyle(BorderlessButtonStyle())
                                    }
                                    
                                    ValidationEntryRow(entry: entry)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    if isEditMode {
                                        toggleSelection(entry.id)
                                    }
                                }
                                .swipeActions(edge: .leading, allowsFullSwipe: false) {
                                    if !isEditMode {
                                        Button {
                                            entryToAugment = entry
                                        } label: {
                                            Label("Augment", systemImage: "wand.and.stars")
                                        }
                                        .tint(.blue)
                                    }
                                }
                                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                                    if !isEditMode {
                                        Button(role: .destructive) {
                                            entryToDelete = entry
                                            showingDeleteConfirmation = true
                                        } label: {
                                            Label("Delete", systemImage: "trash")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle(isEditMode ? "Select Entries" : "Validation Entries")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if isEditMode {
                        Button("Cancel") {
                            isEditMode = false
                            selectedEntries.removeAll()
                        }
                    } else {
                        Button("Close") {
                            dismiss()
                        }
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if isEditMode {
                        Button("Delete (\(selectedEntries.count))") {
                            showingDeleteSelectedConfirmation = true
                        }
                        .disabled(selectedEntries.isEmpty)
                        .foregroundColor(selectedEntries.isEmpty ? .gray : .red)
                    } else {
                        Button(action: {
                            isEditMode = true
                        }) {
                            Label("Select", systemImage: "checkmark.circle")
                        }
                        .disabled(entries.isEmpty)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !isEditMode {
                        Button {
                            showingValidationTest = true
                        } label: {
                            Label("Test Algorithm", systemImage: "checkmark.seal.fill")
                        }
                        .disabled(entries.isEmpty)
                    }
                }
                
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !isEditMode {
                        Menu {
                            Button(action: { showingShareSheet = true }) {
                            Label("Export Dataset", systemImage: "square.and.arrow.up")
                        }
                        
                        Button(role: .destructive) {
                            showingClearAllConfirmation = true
                        } label: {
                            Label("Clear All", systemImage: "trash")
                        }
                        
                        Button(action: loadEntries) {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        } label: {
                            Image(systemName: "ellipsis.circle")
                        }
                    }
                }
            }
            .onAppear {
                loadEntries()
            }
            .alert("Validation Entries", isPresented: $showingAlert) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(alertMessage)
            }
            .confirmationDialog("Delete Entry", isPresented: $showingDeleteConfirmation, presenting: entryToDelete) { entry in
                Button("Delete", role: .destructive) {
                    deleteEntry(entry)
                }
                Button("Cancel", role: .cancel) { }
            } message: { entry in
                Text("Delete entry for '\(entry.character)'?")
            }
            .sheet(isPresented: $showingShareSheet) {
                ShareSheet(activityItems: [ValidationDatasetManager.shared.getFileURL()])
            }
            .sheet(item: $entryToAugment) { entry in
                DataAugmentationSheet(originalEntry: entry)
                    .onDisappear {
                        loadEntries() // Refresh after augmentation
                    }
            }
            .confirmationDialog(
                "Clear All Entries",
                isPresented: $showingClearAllConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear All \(entries.count) Entries", role: .destructive) {
                    clearAll()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently delete all \(entries.count) validation entries. This action cannot be undone.")
            }
            .sheet(isPresented: $showingValidationTest) {
                ValidationTestView()
            }
            .confirmationDialog(
                "Delete Selected Entries",
                isPresented: $showingDeleteSelectedConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete \(selectedEntries.count) Entries", role: .destructive) {
                    deleteSelectedEntries()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This will permanently delete \(selectedEntries.count) selected entries. This action cannot be undone.")
            }
        }
    }
    
    private var sectionHeader: some View {
        HStack {
            Text("Total Entries: \(entries.count)")
            if isEditMode && !entries.isEmpty {
                Spacer()
                Button(selectedEntries.count == entries.count ? "Deselect All" : "Select All") {
                    if selectedEntries.count == entries.count {
                        selectedEntries.removeAll()
                    } else {
                        selectedEntries = Set(entries.map { $0.id })
                    }
                }
                .font(.caption)
                .foregroundColor(.blue)
            }
        }
    }
    
    private func toggleSelection(_ id: UUID) {
        if selectedEntries.contains(id) {
            selectedEntries.remove(id)
        } else {
            selectedEntries.insert(id)
        }
    }
    
    private func loadEntries() {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let loadedEntries = try ValidationDatasetManager.shared.loadEntries()
                DispatchQueue.main.async {
                    self.entries = loadedEntries.sorted { $0.timestamp > $1.timestamp }
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.alertMessage = "Failed to load entries: \(error.localizedDescription)"
                    self.showingAlert = true
                    self.isLoading = false
                }
            }
        }
    }
    
    private func deleteEntry(_ entry: ValidationEntry) {
        do {
            try ValidationDatasetManager.shared.deleteEntry(entry.id)
            entries.removeAll { $0.id == entry.id }
            alertMessage = "Entry deleted"
            showingAlert = true
        } catch {
            alertMessage = "Failed to delete entry: \(error.localizedDescription)"
            showingAlert = true
        }
    }
    
    private func clearAll() {
        do {
            try ValidationDatasetManager.shared.clearAll()
            entries.removeAll()
            alertMessage = "All entries cleared successfully"
            showingAlert = true
        } catch {
            alertMessage = "Failed to clear entries: \(error.localizedDescription)"
            showingAlert = true
        }
    }
    
    private func deleteSelectedEntries() {
        let count = selectedEntries.count
        var successCount = 0
        var failCount = 0
        
        for entryId in selectedEntries {
            do {
                try ValidationDatasetManager.shared.deleteEntry(entryId)
                entries.removeAll { $0.id == entryId }
                successCount += 1
            } catch {
                failCount += 1
            }
        }
        
        selectedEntries.removeAll()
        isEditMode = false
        
        if failCount == 0 {
            alertMessage = "Successfully deleted \(successCount) entries"
        } else {
            alertMessage = "Deleted \(successCount) entries, failed to delete \(failCount) entries"
        }
        showingAlert = true
    }
}

// MARK: - Entry Row

struct ValidationEntryRow: View {
    let entry: ValidationEntry
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(entry.character)
                    .font(.system(size: 32))
                    .fontWeight(.bold)
                
                Spacer()
                
                VStack(alignment: .trailing, spacing: 4) {
                    Text(entry.timestamp, style: .date)
                        .font(.caption)
                        .foregroundColor(.gray)
                    Text(entry.timestamp, style: .time)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }
            
            HStack(spacing: 16) {
                Label("\(entry.userStrokes.count) strokes", systemImage: "pencil.line")
                    .font(.subheadline)
                    .foregroundColor(Color("Blue 700"))
                
                Label("\(entry.referenceStrokeCount) ref", systemImage: "doc.text")
                    .font(.subheadline)
                    .foregroundColor(Color("Green"))
            }
            
            // Show stroke labels
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(entry.userStrokes) { stroke in
                        StrokeLabelBadge(stroke: stroke)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

struct StrokeLabelBadge: View {
    let stroke: LabeledStroke
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                Text("\(stroke.strokeIndex + 1)")
                    .font(.caption2)
                    .fontWeight(.bold)
                
                Image(systemName: "arrow.right")
                    .font(.caption2)
                
                if let match = stroke.groundTruthMatch {
                    Text("R\(match + 1)")
                        .font(.caption2)
                        .fontWeight(.bold)
                } else {
                    Text("X")
                        .font(.caption2)
                        .fontWeight(.bold)
                }
            }
            
            // Show missing substrokes if any
            if !stroke.missingSubstrokes.isEmpty {
                Text("Missing: \(stroke.missingSubstrokes.map(String.init).joined(separator: ","))")
                    .font(.system(size: 8))
                    .foregroundColor(.red)
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(stroke.groundTruthMatch != nil ? Color.green.opacity(0.2) : Color.orange.opacity(0.2))
        .cornerRadius(4)
    }
}

// MARK: - Share Sheet

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let controller = UIActivityViewController(
            activityItems: activityItems,
            applicationActivities: nil
        )
        return controller
    }
    
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
