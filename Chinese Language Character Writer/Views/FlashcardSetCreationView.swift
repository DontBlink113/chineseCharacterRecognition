import SwiftUI

private func extractChineseCharacters(from text: String) -> String {
    var result = ""
    for scalar in text.unicodeScalars {
        let v = scalar.value
        if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0xF900...0xFAFF).contains(v) {
            result.unicodeScalars.append(scalar)
        }
    }
    return result
}

struct FlashcardSetCreationView: View {
    @EnvironmentObject var store: LearningSetsStore
    @Environment(\.dismiss) private var dismiss
    
    @State private var setName: String = ""
    @State private var cards: [FlashcardItem] = []
    @State private var showImportSheet: Bool = false
    
    var body: some View {
        ZStack {
            Color("Secondary100")
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Header with set name
                VStack(spacing: 12) {
                    TextField("Set Name", text: $setName)
                        .font(.title2)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.center)
                        .padding(12)
                        .background(Color.white.opacity(0.9))
                        .cornerRadius(10)
                        .padding(.horizontal, 24)
                }
                .padding(.vertical, 16)
                
                // Card count
                HStack {
                    Text("\(cards.count) cards")
                        .font(.subheadline)
                        .foregroundColor(Color("Primary700"))
                    Spacer()
                    Button(action: { showImportSheet = true }) {
                        HStack(spacing: 4) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Import CSV")
                        }
                        .font(.subheadline)
                        .foregroundColor(Color("Primary600"))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 12)
                
                // Cards list
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(cards.indices, id: \.self) { index in
                            CardRowView(
                                card: $cards[index],
                                onDelete: { cards.remove(at: index) }
                            )
                        }
                        // Add new card button
                        Button(action: addNewCard) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title3)
                                Text("Add Card")
                                    .fontWeight(.medium)
                            }
                            .foregroundColor(Color("Primary600"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .strokeBorder(Color("Primary600").opacity(0.5), lineWidth: 2)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color("Primary600").opacity(0.5), style: .init(lineWidth: 2, dash: [8, 4]))
                            )
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                    }
                    .padding(.bottom, 100)
                }
                
                Spacer()
            }
            // Bottom save button
            VStack {
                Spacer()
                Button(action: saveSet) {
                    Text("Save Set")
                        .font(.headline)
                        .foregroundColor(Color("Secondary100"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canSave ? Color("Primary600") : Color("Neutral400"))
                        .cornerRadius(12)
                }
                .disabled(!canSave)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
                .background(
                    LinearGradient(
                        colors: [Color("Secondary100").opacity(0), Color("Secondary100")],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(height: 100)
                    .allowsHitTesting(false)
                )
            }
        }
        .navigationTitle("New Flashcard Set")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showImportSheet) {
            CSVImportSheet(cards: $cards)
        }
    }
    
    private var canSave: Bool {
        !setName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        !cards.isEmpty &&
        cards.contains { !$0.hanzi.isEmpty }
    }
    
    private func addNewCard() {
        cards.append(FlashcardItem(hanzi: "", definition: ""))
    }
    
    private func saveSet() {
        let processedCards = cards.compactMap { card -> FlashcardItem? in
            let filteredHanzi = extractChineseCharacters(from: card.hanzi)
            guard !filteredHanzi.isEmpty else { return nil }
            return FlashcardItem(id: card.id, hanzi: filteredHanzi, definition: card.definition)
        }
        guard !processedCards.isEmpty else { return }
        
        store.addFlashcardSet(name: setName.trimmingCharacters(in: .whitespacesAndNewlines), cards: processedCards)
        dismiss()
    }
    
}

// MARK: - Card Row View

struct CardRowView: View {
    @Binding var card: FlashcardItem
    var onDelete: () -> Void
    
    var body: some View {
        HStack(spacing: 12) {
            VStack(spacing: 8) {
                TextField("Character", text: $card.hanzi)
                    .font(.title2)
                    .multilineTextAlignment(.center)
                    .frame(width: 60)
                    .padding(8)
                    .background(Color("Background100"))
                    .cornerRadius(8)
                
                Text("Term")
                    .font(.caption2)
                    .foregroundColor(Color("Primary700"))
            }
            
            VStack(spacing: 8) {
                TextField("Definition", text: $card.definition)
                    .font(.body)
                    .padding(10)
                    .background(Color("Background100"))
                    .cornerRadius(8)
                
                Text("Definition")
                    .font(.caption2)
                    .foregroundColor(Color("Primary700"))
            }
            
            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundColor(Color("Primary700"))
                    .padding(8)
            }
        }
        .padding(12)
        .background(Color("Background200"))
        .cornerRadius(12)
        .padding(.horizontal, 24)
    }
}

// MARK: - CSV Import Sheet

struct CSVImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var cards: [FlashcardItem]
    
    @State private var pasteText: String = ""
    @State private var selectedDelimiter: Delimiter = .comma
    @State private var previewCards: [FlashcardItem] = []
    
    enum Delimiter: String, CaseIterable {
        case comma = ","
        case tab = "Tab"
        case semicolon = ";"
        case pipe = "|"
        
        var separator: String {
            switch self {
            case .comma: return ","
            case .tab: return "\t"
            case .semicolon: return ";"
            case .pipe: return "|"
            }
        }
        
        var displayName: String {
            switch self {
            case .comma: return "Comma (,)"
            case .tab: return "Tab"
            case .semicolon: return "Semicolon (;)"
            case .pipe: return "Pipe (|)"
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ZStack {
                Color("Secondary100")
                    .ignoresSafeArea()
                
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // Instructions
                        Text("Paste your data below. Each line should contain a term and definition separated by your chosen delimiter.")
                            .font(.subheadline)
                            .foregroundColor(Color("Primary700"))
                            .padding(.horizontal, 24)
                        
                        // Delimiter picker
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Delimiter")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(Color("Primary900"))
                            
                            Picker("Delimiter", selection: $selectedDelimiter) {
                                ForEach(Delimiter.allCases, id: \.self) { delimiter in
                                    Text(delimiter.displayName).tag(delimiter)
                                }
                            }
                            .pickerStyle(.segmented)
                            .onChange(of: selectedDelimiter) {
                                parsePreview()
                            }
                        }
                        .padding(.horizontal, 24)
                        
                        // Paste box
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Paste Data")
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .foregroundColor(Color("Primary900"))
                            
                            TextEditor(text: $pasteText)
                                .frame(minHeight: 150)
                                .padding(8)
                                .background(Color("Background100"))
                                .cornerRadius(8)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color("Primary600").opacity(0.3), lineWidth: 1)
                                )
                                .onChange(of: pasteText) {
                                    parsePreview()
                                }
                        }
                        .padding(.horizontal, 24)
                        
                        // Preview
                        if !previewCards.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Preview (\(previewCards.count) cards)")
                                    .font(.subheadline)
                                    .fontWeight(.medium)
                                    .foregroundColor(Color("Primary900"))
                                
                                ForEach(previewCards.prefix(5)) { card in
                                    HStack {
                                        Text(card.hanzi)
                                            .font(.title3)
                                            .frame(width: 50)
                                        
                                        Image(systemName: "arrow.right")
                                            .foregroundColor(Color("Neutral400"))
                                        
                                        Text(card.definition)
                                            .font(.body)
                                            .foregroundColor(Color("Primary700"))
                                        
                                        Spacer()
                                    }
                                    .padding(10)
                                    .background(Color("Background200"))
                                    .cornerRadius(8)
                                }
                                
                                if previewCards.count > 5 {
                                    Text("... and \(previewCards.count - 5) more")
                                        .font(.caption)
                                        .foregroundColor(Color("Primary700"))
                                }
                            }
                            .padding(.horizontal, 24)
                        }
                        
                        Spacer(minLength: 100)
                    }
                    .padding(.top, 16)
                }
                
                // Import button
                VStack {
                    Spacer()
                    Button(action: importCards) {
                        Text("Import \(previewCards.count) Cards")
                            .font(.headline)
                            .foregroundColor(Color("Secondary100"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(previewCards.isEmpty ? Color("Neutral 400") : Color("Primary600"))
                            .cornerRadius(12)
                    }
                    .disabled(previewCards.isEmpty)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Import from CSV")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
    
    private func parsePreview() {
        let lines = pasteText.components(separatedBy: .newlines)
        previewCards = lines.compactMap { line -> FlashcardItem? in
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty else { return nil }
            
            let parts = trimmed.components(separatedBy: selectedDelimiter.separator)
            guard !parts.isEmpty else { return nil }
            
            let rawTerm = parts[0].trimmingCharacters(in: .whitespaces)
            let term = extractChineseCharacters(from: rawTerm)
            let definition = parts.count > 1 ? parts.dropFirst().joined(separator: selectedDelimiter.separator).trimmingCharacters(in: .whitespaces) : ""
            
            guard !term.isEmpty else { return nil }
            return FlashcardItem(hanzi: term, definition: definition)
        }
    }
    
    private func importCards() {
        cards.append(contentsOf: previewCards)
        dismiss()
    }
}

struct FlashcardSetCreationView_Previews: PreviewProvider {
    static var previews: some View {
        NavigationStack {
            FlashcardSetCreationView()
                .environmentObject(LearningSetsStore())
        }
    }
}
