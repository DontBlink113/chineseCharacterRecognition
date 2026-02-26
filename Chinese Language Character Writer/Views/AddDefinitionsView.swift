import SwiftUI

struct AddDefinitionsView: View {
    @EnvironmentObject var store: LearningSetsStore
    @Environment(\.dismiss) private var dismiss
    
    let setId: UUID
    
    @State private var items: [FlashcardItem] = []
    @State private var newHanziText: String = ""
    @State private var showEmptySetAlert: Bool = false
    
    private var learningSet: LearningSet? {
        store.sets.first { $0.id == setId }
    }
    
    var body: some View {
        ZStack {
            Color("Secondary100")
                .ignoresSafeArea()
            
            ScrollView {
                VStack(spacing: 24) {
                    // Title
                    Text("Edit Character List")
                        .font(.system(size: 40)).bold()
                        .foregroundColor(Color("Primary900"))
                        .padding(.top, 20)
                    
                    if let set = learningSet {
                        Text(set.name)
                            .font(.title3)
                            .foregroundColor(Color("Neutral700"))
                    }
                    
                    // Add/remove characters section
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Add Characters")
                            .font(.headline)
                            .foregroundColor(Color("Primary900"))
                        HStack(spacing: 8) {
                            TextField("Type or paste characters (e.g., 你好)", text: $newHanziText)
                                .textFieldStyle(.roundedBorder)
                                .submitLabel(.done)
                                .onSubmit { addCharacters() }
                            Button(action: addCharacters) {
                                HStack(spacing: 6) {
                                    Image(systemName: "plus.circle.fill")
                                    Text("Add")
                                }
                                .font(.subheadline)
                                .foregroundColor(Color("Secondary100"))
                                .padding(.vertical, 8)
                                .padding(.horizontal, 12)
                                .background(Color("Primary700"))
                                .cornerRadius(8)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 24)

                    // Auto-generate all button
                    Button(action: autoGenerateAll) {
                        HStack {
                            Image(systemName: "sparkles")
                            Text("Auto-Generate All Definitions")
                        }
                        .font(.headline)
                        .foregroundColor(Color("Secondary100"))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color("Primary700"))
                        .cornerRadius(10)
                        .shadow(color: Color("Primary700").opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    
                    // Character cards
                    ForEach(items.indices, id: \.self) { index in
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text(items[index].hanzi)
                                    .font(.system(size: 36, weight: .bold))
                                    .foregroundColor(Color("Primary900"))
                                
                                Spacer()
                                
                                Button(action: {
                                    autoGenerateSingle(at: index)
                                }) {
                                    HStack {
                                        Image(systemName: "sparkles")
                                        Text("Auto")
                                    }
                                    .font(.caption)
                                    .foregroundColor(Color("Primary700"))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(Color.white)
                                    .cornerRadius(8)
                                }
                                .buttonStyle(.plain)

                                Button(action: { deleteItem(at: index) }) {
                                    Image(systemName: "trash")
                                        .foregroundColor(.red)
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 6)
                                        .background(Color.white)
                                        .cornerRadius(8)
                                }
                                .buttonStyle(.plain)
                            }
                            
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Definition")
                                    .font(.caption)
                                    .foregroundColor(Color("Neutral700"))
                                
                                TextEditor(text: $items[index].definition)
                                    .frame(minHeight: 80)
                                    .padding(8)
                                    .background(Color.white.opacity(0.9))
                                    .cornerRadius(8)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8)
                                            .stroke(Color("Primary700").opacity(0.3), lineWidth: 1)
                                    )
                            }
                        }
                        .padding(16)
                        .background(Color.white.opacity(0.7))
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                        .padding(.horizontal, 24)
                    }
                    
                    // Save button
                    Button(action: saveDefinitions) {
                        Text("Save Definitions")
                            .font(.headline)
                            .foregroundColor(Color("Secondary100"))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(Color("Primary700"))
                            .cornerRadius(10)
                            .shadow(color: Color("Primary700").opacity(0.3), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 24)
                    
                    Spacer(minLength: 40)
                }
            }
        }
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            loadItems()
        }
        .alert(isPresented: $showEmptySetAlert) {
            Alert(
                title: Text("Empty Set"),
                message: Text("This set has no characters. Delete this set?"),
                primaryButton: .destructive(Text("Delete")) { deleteSetAndDismiss() },
                secondaryButton: .cancel()
            )
        }
    }
    
    private func loadItems() {
        guard let set = learningSet else { return }
        
        // If items already exist, use them
        if let existingItems = set.items, !existingItems.isEmpty {
            items = existingItems
        } else {
            // Create items from characters
            let characters = extractHanzi(from: set.characters)
            items = characters.map { FlashcardItem(id: UUID(), hanzi: $0, definition: "") }
        }
    }
    
    private func autoGenerateSingle(at index: Int) {
        guard items.indices.contains(index) else { return }
        let dict = DictionaryService.shared
        let hanzi = items[index].hanzi
        print("Looking up: '\(hanzi)'")
        if let definition = dict.definition(for: hanzi) {
            print("Found: '\(definition)'")
            items[index].definition = definition
        } else {
            print("NOT FOUND")
            items[index].definition = "No definition found"
        }
    }
    
    private func autoGenerateAll() {
        print("=== AUTO GENERATE ALL ===")
        let dict = DictionaryService.shared
        // Test if dictionary has any entries
        let testChar = "的"
        print("Test lookup for '\(testChar)': \(dict.definition(for: testChar) ?? "NOT FOUND")")
        
        for i in items.indices {
            let hanzi = items[i].hanzi
            print("Looking up: '\(hanzi)'")
            if let definition = dict.definition(for: hanzi) {
                print("Found: '\(definition)'")
                items[i].definition = definition
            } else {
                print("NOT FOUND")
                items[i].definition = "No definition found"
            }
        }
        print("=== COMPLETE ===")
    }
    
    private func saveDefinitions() {
        guard var set = learningSet else { return }
        if items.isEmpty {
            showEmptySetAlert = true
            return
        }
        set.items = items
        // Keep characters in sync with items
        set.characters = items.map { $0.hanzi }.joined()
        store.update(set)
        dismiss()
    }

    private func addCharacters() {
        let chars = extractHanzi(from: newHanziText)
        guard !chars.isEmpty else { return }
        let existing = Set(items.map { $0.hanzi })
        var added = false
        for c in chars where !existing.contains(c) {
            items.append(FlashcardItem(hanzi: c, definition: ""))
            added = true
        }
        if added { newHanziText = "" }
    }

    private func deleteItem(at index: Int) {
        guard items.indices.contains(index) else { return }
        items.remove(at: index)
    }

    private func deleteSetAndDismiss() {
        guard let set = learningSet, let idx = store.sets.firstIndex(where: { $0.id == set.id }) else { return }
        let idxSet = IndexSet(integer: idx)
        store.remove(at: idxSet)
        dismiss()
    }
}

private func extractHanzi(from text: String) -> [String] {
    var seen = Set<String>()
    var result: [String] = []
    for scalar in text.unicodeScalars {
        let v = scalar.value
        if (0x4E00...0x9FFF).contains(v) || (0x3400...0x4DBF).contains(v) || (0xF900...0xFAFF).contains(v) {
            let s = String(scalar)
            if !seen.contains(s) {
                seen.insert(s)
                result.append(s)
            }
        }
    }
    return result
}
