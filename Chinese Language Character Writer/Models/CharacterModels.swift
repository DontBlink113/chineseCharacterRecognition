import Foundation

// MARK: - Data Model for JSON Parsing
struct CharacterDataModel: Codable {
    let character: String
    let strokeCount: Int
    let pointer: Int
    
    // For JSON encoding/decoding
    enum CodingKeys: String, CodingKey {
        case character = "char"
        case strokeCount, pointer
    }
    
    // Custom initializer to parse from JSON array format
    init(from jsonArray: [Any]) {
        self.character = jsonArray[0] as? String ?? ""
        self.strokeCount = jsonArray[1] as? Int ?? 0
        self.pointer = jsonArray[3] as? Int ?? 0
    }
}

// MARK: - Main Character Model
struct Character: Identifiable, Codable {
    let id = UUID()
    let character: String
    let strokeCount: Int
    let pointer: Int
    
    init(from data: CharacterDataModel) {
        self.character = data.character
        self.strokeCount = data.strokeCount
        self.pointer = data.pointer
    }
}

// MARK: - Database Wrapper
struct CharacterDatabase: Codable {
    let characters: [CharacterDataModel]
    
    // Helper to create a dictionary for quick lookup
    func toDictionary() -> [String: Character] {
        var dict = [String: Character]()
        for charData in characters {
            dict[charData.character] = Character(from: charData)
        }
        return dict
    }
}
