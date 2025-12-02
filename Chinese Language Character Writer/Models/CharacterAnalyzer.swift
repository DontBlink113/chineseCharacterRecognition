import Foundation

class CharacterAnalyzer {
    static let shared = CharacterAnalyzer()
    
    // In-memory storage for character data
    private var characterDatabase: [String: Character] = [:]
    
    // Top 100 common characters to search over by default (provided by user)
    private let commonCharacters: [String] = [
        "的","一","了","不","人","我","在","有","他","这","中","大","来","上","国","个","到","说","们","为","子","和","地","出","道","时","年","得","就","下","生","自","会","去","之","用","也","你","对","多","工","可","里","后","小","心","学","么","能","起","天","其","想","看","下","还","么","请","位","做","当","没","再","前","开","因","同","日","手","发","成","方","经","动","面","起","间","话","很","所","最","新","现","分","明","将","些","如","入","先","长","实","两","主","从"
    ]
    
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
    
    // MARK: - Matching Logic
    
    /// Find the best matching dataset character to a written drawing by comparing substroke angles, positions, and lengths.
    /// - Parameters:
    ///   - drawing: The user's written character drawing.
    ///   - candidateKeys: Optional list of Hanzi to restrict the search; defaults to top 100 common characters.
    /// - Returns: Tuple of best matching dataset Character and its total cost (lower is better).
    func bestMatch(for drawing: CharacterDrawing, candidateKeys: [String]? = nil) -> (character: Character, cost: Double)? {
        // Build candidate list
        let keys = candidateKeys ?? commonCharacters
        let writtenStrokeCount = drawing.strokes.count
        
        // Precompute written substroke features
        let writtenSubstrokes = extractWrittenFeatures(from: drawing)
        guard !writtenSubstrokes.isEmpty else { return nil }
        
        // Filter dataset by stroke count within ±2 and existing in DB
        let candidates: [Character] = keys.compactMap { key in characterDatabase[key] }
            .filter { abs($0.strokeCount - writtenStrokeCount) <= 2 }
        guard !candidates.isEmpty else { return nil }
        
        var best: (Character, Double)? = nil
        for candidate in candidates {
            let datasetSubs = extractDatasetFeatures(from: candidate)
            if datasetSubs.isEmpty { continue }
            let cost = assignmentCost(written: writtenSubstrokes, dataset: datasetSubs)
            if let current = best {
                if cost < current.1 { best = (candidate, cost) }
            } else {
                best = (candidate, cost)
            }
        }
        return best
    }
    
    // Feature extraction for written substrokes (angles in radians, centers bbox-normalized, lengths normalized 0..1 by max magnitude)
    private func extractWrittenFeatures(from drawing: CharacterDrawing) -> [(angle: Double, nx: Double, ny: Double, length: Double)] {
        // Collect all substrokes and centers
        let allSubs = drawing.strokes.flatMap { $0.substrokes }
        guard !allSubs.isEmpty else { return [] }
        
        // Bounding box from substroke centers
        let centers = allSubs.map { $0.center }
        let xs = centers.map { Double($0.x) }
        let ys = centers.map { Double($0.y) }
        let minX = xs.min() ?? 0, maxX = xs.max() ?? 1
        let minY = ys.min() ?? 0, maxY = ys.max() ?? 1
        let w = max(1e-6, maxX - minX)
        let h = max(1e-6, maxY - minY)
        
        // Normalize lengths by max magnitude
        let maxMag = max(1e-6, allSubs.map { Double($0.magnitude) }.max() ?? 1e-6)
        
        return allSubs.map { s in
            let nx = (Double(s.center.x) - minX) / w
            let ny = (Double(s.center.y) - minY) / h
            let ang = Double(s.angle)
            let len = Double(s.magnitude) / maxMag
            return (angle: ang, nx: min(1, max(0, nx)), ny: min(1, max(0, ny)), length: min(1, max(0, len)))
        }
    }
    
    // Feature extraction for dataset substrokes (angles, centers bbox-normalized per character, lengths already 0..1)
    private func extractDatasetFeatures(from character: Character) -> [(angle: Double, nx: Double, ny: Double, length: Double)] {
        let subs = character.substrokes
        guard !subs.isEmpty else { return [] }
        let xs = subs.map { $0.centerX }
        let ys = subs.map { $0.centerY }
        let minX = xs.min() ?? 0.0, maxX = xs.max() ?? 1.0
        let minY = ys.min() ?? 0.0, maxY = ys.max() ?? 1.0
        let w = max(1e-6, maxX - minX)
        let h = max(1e-6, maxY - minY)
        
        return subs.map { s in
            let nx = (s.centerX - minX) / w
            let ny = (s.centerY - minY) / h
            return (angle: s.direction, nx: Swift.min(1, Swift.max(0, nx)), ny: Swift.min(1, Swift.max(0, ny)), length: s.length)
        }
    }
    
    // Total assignment cost using Hungarian algorithm with optional skips via padding and missing-penalty
    private func assignmentCost(written: [(angle: Double, nx: Double, ny: Double, length: Double)],
                                dataset: [(angle: Double, nx: Double, ny: Double, length: Double)],
                                missingPenalty: Double = 0.5,
                                angleWeight: Double = 1.0,
                                posWeight: Double = 1.0,
                                lenWeight: Double = 1.0) -> Double {
        let m = written.count
        let n = dataset.count
        let size = max(m, n)
        
        func pairCost(_ a: (Double, Double, Double, Double), _ b: (Double, Double, Double, Double)) -> Double {
            let angDiff = angularDiff(a.0, b.0) / .pi // normalize to [0,1]
            let dx = a.1 - b.1, dy = a.2 - b.2
            let posDiff = sqrt(dx*dx + dy*dy) / sqrt(2.0) // [0,1]
            let lenDiff = abs(a.3 - b.3) // [0,1]
            return angleWeight*angDiff + posWeight*posDiff + lenWeight*lenDiff
        }
        
        // Build square cost matrix with padding
        var cost: [[Double]] = Array(repeating: Array(repeating: missingPenalty, count: size), count: size)
        for i in 0..<m {
            for j in 0..<n {
                cost[i][j] = pairCost(written[i], dataset[j])
            }
        }
        
        // Hungarian algorithm
        let assignment = hungarian(costMatrix: cost)
        var total = 0.0
        for (i, j) in assignment {
            total += cost[i][j]
        }
        // Average per matched pair for scale invariance
        return total / Double(size)
    }
    
    private func angularDiff(_ a: Double, _ b: Double) -> Double {
        let diff = abs(a - b).truncatingRemainder(dividingBy: 2*Double.pi)
        return min(diff, 2*Double.pi - diff)
    }
    
    // Hungarian algorithm for minimization
    // Returns an array of assigned pairs (row, col)
    private func hungarian(costMatrix: [[Double]]) -> [(Int, Int)] {
        let n = costMatrix.count
        guard n > 0 else { return [] }
        var u = Array(repeating: 0.0, count: n + 1)
        var v = Array(repeating: 0.0, count: n + 1)
        var p = Array(repeating: 0, count: n + 1)
        var way = Array(repeating: 0, count: n + 1)
        
        for i in 1...n {
            p[0] = i
            var j0 = 0
            var minv = Array(repeating: Double.greatestFiniteMagnitude, count: n + 1)
            var used = Array(repeating: false, count: n + 1)
            repeat {
                used[j0] = true
                let i0 = p[j0]
                var delta = Double.greatestFiniteMagnitude
                var j1 = 0
                for j in 1...n {
                    if used[j] { continue }
                    let cur = costMatrix[i0-1][j-1] - u[i0] - v[j]
                    if cur < minv[j] { minv[j] = cur; way[j] = j0 }
                    if minv[j] < delta { delta = minv[j]; j1 = j }
                }
                for j in 0...n {
                    if used[j] { u[p[j]] += delta; v[j] -= delta }
                    else { minv[j] -= delta }
                }
                j0 = j1
            } while p[j0] != 0
            repeat {
                let j1 = way[j0]
                p[j0] = p[j1]
                j0 = j1
            } while j0 != 0
        }
        var assignment: [(Int, Int)] = []
        for j in 1...n {
            if p[j] != 0 { assignment.append((p[j]-1, j-1)) }
        }
        return assignment
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
