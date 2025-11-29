import Foundation

class CharacterAnalyzer {
    static let shared = CharacterAnalyzer()
    
    // In-memory storage for character data
    private var characterDatabase: [String: Character] = [:]
    
    private init() {
        loadCharacterDatabase()
    }
    
    private func loadCharacterDatabase() {
        guard let url = Bundle.main.url(forResource: "mmah", withExtension: "json") else {
            print("Error: Could not find mmah.json in bundle")
            return
        }
        
        do {
            let data = try Data(contentsOf: url)
            // Parse the JSON
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               let charsArray = json["chars"] as? [[Any]],
               let substrokesBase64 = json["substrokes"] as? String,
               let substrokeData = Data(base64Encoded: substrokesBase64) {
                
                let binaryData = [UInt8](substrokeData)
                var characterModels: [CharacterDataModel] = []
                
                // First pass: Create all character models
                for charData in charsArray {
                    characterModels.append(CharacterDataModel(from: charData))
                }
                
                // Second pass: Process substrokes for each character
                for i in characterModels.indices {
                    var charModel = characterModels[i] // Create a mutable copy
                    
                    if charModel.substrokeCount > 0 {
                        charModel.substrokes = decodeSubstrokes(
                            pointer: charModel.pointer,
                            count: charModel.substrokeCount,
                            from: binaryData
                        )
                    }
                    
                    let character = Character(from: charModel)
                    characterDatabase[charModel.character] = character
                }
                
                print("Successfully loaded \(characterDatabase.count) characters with substroke data")
            } else {
                print("Error: Invalid JSON format in mmah.json or missing required fields")
            }
        } catch {
            print("Error loading or processing mmah.json: \(error)")
        }
    }
    
    func analyze(character: String) -> Character? {
        // Simple lookup - in a real app, this might include more complex analysis
        return characterDatabase[character]
    }
    
    func analyzeMultiple(characters: [String]) -> [Character] {
        return characters.compactMap { analyze(character: $0) }
    }
    
    // Find characters by stroke count
    func findCharacters(withStrokeCount strokeCount: Int) -> [Character] {
        return characterDatabase.values.filter { $0.strokeCount == strokeCount }
    }
    
    func getRandomCharacter() -> Character? {
        return characterDatabase.values.randomElement()
    }
    
    // Get a random character
    func randomCharacter() -> Character? {
        return characterDatabase.values.randomElement()
    }
    
    // Get all characters
    var allCharacters: [Character] {
        return Array(characterDatabase.values)
    }
    
    // MARK: - Substroke Processing
    
    private func decodeSubstrokes(pointer: Int, count: Int, from binaryData: [UInt8]) -> [CharacterSubstroke] {
        var substrokes: [CharacterSubstroke] = []
        let startByte = pointer  // Pointer is already at the correct position
        let endByte = startByte + (count * 3)  // Each substroke is 3 bytes
        
        guard endByte <= binaryData.count else {
            print("Error: Insufficient binary data for substrokes (requested bytes \(startByte)-\(endByte-1) but only have \(binaryData.count) bytes)")
            return []
        }
        
        for i in 0..<count {
            let baseIndex = startByte + (i * 3)
            
            let directionByte = binaryData[baseIndex]
            let lengthByte = binaryData[baseIndex + 1]
            let centerPacked = binaryData[baseIndex + 2]
            
            // Convert to actual values
            let direction = Double(directionByte) * (.pi * 2 / 256.0)
            let length = Double(lengthByte) / 255.0
            let centerX = Double((centerPacked & 0xF0) >> 4) / 15.0
            let centerY = Double(centerPacked & 0x0F) / 15.0
            
            let substroke = CharacterSubstroke(
                direction: direction,
                length: length,
                centerX: centerX,
                centerY: centerY
            )
            substrokes.append(substroke)
        }
        
        return substrokes
    }
}
