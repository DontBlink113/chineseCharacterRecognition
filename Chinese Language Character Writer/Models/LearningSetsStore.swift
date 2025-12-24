import Foundation
import SwiftUI

struct LearningSet: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var characters: String
    var items: [FlashcardItem]? // Optional flashcard items (hanzi + definition)

    init(id: UUID = UUID(), name: String, characters: String, items: [FlashcardItem]? = nil) {
        self.id = id
        self.name = name
        self.characters = characters
        self.items = items
    }
    
    var hasDefinitions: Bool {
        guard let items = items, !items.isEmpty else { return false }
        // Check if at least one item has a non-empty definition
        return items.contains { !$0.definition.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

final class LearningSetsStore: ObservableObject {
    @Published private(set) var sets: [LearningSet] = [] {
        didSet { persist() }
    }
    @Published var activeSetId: UUID? { didSet { persistActive() } }

    var activeSet: LearningSet? {
        guard let id = activeSetId else { return nil }
        return sets.first { $0.id == id }
    }

    private let setsKey = "learning_sets_store_sets"
    private let activeKey = "learning_sets_store_active"

    init() {
        load()
    }

    func add(name: String, characters: String) {
        var cleaned = extractHanzi(from: characters).joined()
        if cleaned.isEmpty { return }
        let set = LearningSet(name: name.isEmpty ? "Untitled" : name, characters: cleaned)
        sets.append(set)
        if activeSetId == nil { activeSetId = set.id }
    }

    func addFlashcardSet(name: String, cards: [FlashcardItem]) {
        guard !cards.isEmpty else { return }
        // Derive characters string from items for backward compatibility
        let chars = cards.map { $0.hanzi }.joined()
        let set = LearningSet(name: name.isEmpty ? "Untitled" : name, characters: chars, items: cards)
        sets.append(set)
        if activeSetId == nil { activeSetId = set.id }
    }

    func remove(at offsets: IndexSet) {
        let ids = offsets.map { sets[$0].id }
        sets.remove(atOffsets: offsets)
        if let active = activeSetId, ids.contains(active) {
            activeSetId = sets.first?.id
        }
    }

    func setActive(_ set: LearningSet) { activeSetId = set.id }

    func update(_ set: LearningSet) {
        if let idx = sets.firstIndex(where: { $0.id == set.id }) {
            sets[idx] = set
        }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(sets) {
            UserDefaults.standard.set(data, forKey: setsKey)
        }
    }

    private func persistActive() {
        UserDefaults.standard.set(activeSetId?.uuidString, forKey: activeKey)
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: setsKey),
           let decoded = try? JSONDecoder().decode([LearningSet].self, from: data) {
            self.sets = decoded
        }
        if let idStr = UserDefaults.standard.string(forKey: activeKey), let id = UUID(uuidString: idStr) {
            self.activeSetId = id
        } else {
            self.activeSetId = sets.first?.id
        }
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
