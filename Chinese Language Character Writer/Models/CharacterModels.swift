import Foundation

// MARK: - Substroke Model
struct CharacterSubstroke: Codable, Identifiable {
    let id = UUID()
    let direction: Double  // in radians, 0 = right, π/2 = up
    let length: Double     // normalized (0-1)
    let centerX: Double    // normalized X coordinate (0-1)
    let centerY: Double    // normalized Y coordinate (0-1)
    
    // For JSON encoding/decoding
    enum CodingKeys: String, CodingKey {
        case direction, length, centerX, centerY
    }
}

// MARK: - Data Model for JSON Parsing
struct CharacterDataModel: Codable {
    let character: String
    let strokeCount: Int
    let substrokeCount: Int
    let pointer: Int
    var substrokes: [CharacterSubstroke] = []  // Will be populated during processing
    
    // For JSON encoding/decoding
    enum CodingKeys: String, CodingKey {
        case character = "char"
        case strokeCount, substrokeCount, pointer, substrokes
    }
    
    // Custom initializer to parse from JSON array format
    init(from jsonArray: [Any]) {
        self.character = jsonArray[0] as? String ?? ""
        self.strokeCount = jsonArray[1] as? Int ?? 0
        self.substrokeCount = jsonArray[2] as? Int ?? 0
        self.pointer = jsonArray[3] as? Int ?? 0
        self.substrokes = []
    }
}

// MARK: - Main Character Model
struct Character: Identifiable, Codable {
    let id = UUID()
    let character: String
    let strokeCount: Int
    let substrokeCount: Int
    let pointer: Int
    let substrokes: [CharacterSubstroke]
    
    init(from data: CharacterDataModel) {
        self.character = data.character
        self.strokeCount = data.strokeCount
        self.substrokeCount = data.substrokeCount
        self.pointer = data.pointer
        self.substrokes = data.substrokes
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
