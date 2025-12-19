import SwiftUI

struct EditLearningSetView: View {
    @EnvironmentObject var store: LearningSetsStore
    @Environment(\.dismiss) private var dismiss
    
    enum Mode: String, CaseIterable, Identifiable { case manual = "Manual", bulk = "Bulk"; var id: String { rawValue } }
    
    @State private var name: String = ""
    @State private var mode: Mode = .manual
    
    // Manual entry
    @State private var manualChar: String = ""
    @State private var manualDefinition: String = ""
    @State private var manualCards: [FlashcardItem] = []
    
    // Bulk entry
    @State private var bulkInput: String = ""
    @State private var bulkCards: [FlashcardItem] = []
    
    var body: some View {
        Form {
            Section(header: Text("Set Details")) {
                TextField("Set Name", text: $name)
                Picker("Mode", selection: $mode) {
                    ForEach(Mode.allCases) { m in Text(m.rawValue).tag(m) }
                }
                .pickerStyle(.segmented)
            }
            
            if mode == .manual {
                manualSection
                if !manualCards.isEmpty { cardsList(cards: $manualCards) }
            } else {
                bulkSection
                if !bulkCards.isEmpty { cardsList(cards: $bulkCards) }
            }
            
            Section {
                Button(action: save) {
                    Text("Save Set")
                        .frame(maxWidth: .infinity)
                }
                .disabled(!canSave)
            }
        }
        .navigationTitle("New Flashcard Set")
        .navigationBarTitleDisplayMode(.inline)
    }
    
    private var manualSection: some View {
        Section(header: Text("Manual Entry (Quizlet-style)")) {
            HStack(spacing: 12) {
                TextField("Chinese (1 char)", text: Binding(
                    get: { manualChar },
                    set: { newValue in
                        // keep only first CJK scalar
                        let filtered = extractHanzi(from: newValue)
                        manualChar = filtered.first ?? ""
                    }
                ))
                .textInputAutocapitalization(.never)
                .disableAutocorrection(true)
                .frame(minWidth: 60)
                
                TextField("English definition", text: $manualDefinition)
                
                Button("Add") {
                    let c = manualChar.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !c.isEmpty else { return }
                    manualCards.append(FlashcardItem(hanzi: c, definition: manualDefinition))
                    manualChar = ""
                    manualDefinition = ""
                }
                .disabled(extractHanzi(from: manualChar).isEmpty)
            }
        }
    }
    
    private var bulkSection: some View {
        Section(header: Text("Bulk Paste"), footer: Text("Paste characters; we'll extract unique Hanzi. Then auto-fill definitions (placeholder for now), and you can edit.")) {
            TextEditor(text: $bulkInput)
                .frame(minHeight: 120)
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.25)))
            HStack {
                Button("Extract Characters") {
                    let chars = extractHanzi(from: bulkInput)
                    let existing = Set(bulkCards.map { $0.hanzi })
                    var list: [FlashcardItem] = bulkCards
                    for h in chars where !existing.contains(h) {
                        list.append(FlashcardItem(hanzi: h))
                    }
                    // keep input order
                    let order = chars
                    bulkCards = list.sorted { a, b in
                        (order.firstIndex(of: a.hanzi) ?? 0) < (order.firstIndex(of: b.hanzi) ?? 0)
                    }
                }
                Spacer()
                Button("Auto-fill Definitions") {
                    // Populate definitions from local dictionary if available
                    let dict = DictionaryService.shared
                    for i in bulkCards.indices {
                        if bulkCards[i].definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                            bulkCards[i].definition = dict.definition(for: bulkCards[i].hanzi) ?? ""
                        }
                    }
                }
            }
        }
    }
    
    private func cardsList(cards: Binding<[FlashcardItem]>) -> some View {
        Section(header: Text("Cards")) {
            ForEach(cards) { $item in
                HStack {
                    Text(item.hanzi)
                        .font(.title2)
                        .frame(width: 48)
                    TextField("Definition", text: $item.definition)
                }
            }
            .onDelete { offsets in
                cards.wrappedValue.remove(atOffsets: offsets)
            }
        }
    }
    
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (mode == .manual ? !manualCards.isEmpty : !bulkCards.isEmpty)
    }
    
    private func save() {
        let cards = mode == .manual ? manualCards : bulkCards
        store.addFlashcardSet(name: name, cards: cards)
        dismiss()
    }
}

private func extractHanzi(from text: String) -> [String] {
    var result: [String] = []
    var seen = Set<String>()
    for s in text.unicodeScalars {
        let v = s.value
        if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0xF900...0xFAFF).contains(v) {
            let ch = String(s)
            if !seen.contains(ch) { seen.insert(ch); result.append(ch) }
        }
    }
    return result
}
