import Foundation

class CharacterAnalyzer {
    static let shared = CharacterAnalyzer()
    
    // In-memory storage for character data
    private var characterDatabase: [String: Character] = [:]
    
    // Scaling factor for written substroke normalized lengths
    var writtenLengthScale: Double = 0.7

    // Tunable weight for index-distance penalty when matching substrokes
    var indexProximityWeight: Double = 0.5

    // Tunable per-substroke-count mismatch penalty 
    var substrokeCountPenalty: Double = 0.06

    var lengthWeight: Double = 1.0

    var angleWeight: Double = 1.0

    var positionWeight: Double = 1.0

    // Weight for matching characters with discrepancies in substrokes
    var missingWeight: Double = 1.0 

    // Softmax temperature for converting costs to probabilities (lower => sharper)
    var softmaxTemperature: Double = 0.6
    
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
    //Given a character string, returns the corresponding Character model if available.
    func analyze(character: String) -> Character? {
        return characterDatabase[character]
    }
    
    func analyzeMultiple(characters: [String]) -> [Character] {
        return characters.compactMap { analyze(character: $0) }
    }
    
    // Find characters by stroke count
    func findCharacters(withStrokeCount strokeCount: Int) -> [Character] {
        return characterDatabase.values.filter { $0.strokeCount == strokeCount }
    }
    
    // Get all characters
    var allCharacters: [Character] {
        return Array(characterDatabase.values)
    }
    
    // Find the best matching dataset character to a written drawing by comparing substroke angles, positions, and lengths.
    // - Parameters:
    //   - drawing: The user's written character drawing.
    //   - candidateKeys: Optional list of Hanzi to restrict the search; defaults to top 100 common characters.
    // - Returns: Tuple of best matching dataset Character and its total cost (lower is better).
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
            let cost = assignmentCost(written: writtenSubstrokes, dataset: datasetSubs) //returns the character with the lowest cost
            if let current = best {
                if cost < current.1 { best = (candidate, cost) }
            } else {
                best = (candidate, cost)
            }
        }
        return best
    }

    /// Compute costs for all candidate characters against one written character 
    func candidateCosts(for drawing: CharacterDrawing, candidateKeys: [String]? = nil) -> [(character: Character, cost: Double)] {
        let keys = candidateKeys ?? commonCharacters
        let writtenStrokeCount = drawing.strokes.count
        let writtenSubstrokes = extractWrittenFeatures(from: drawing)
        guard !writtenSubstrokes.isEmpty else { return [] }
        let candidates: [Character] = keys.compactMap { key in characterDatabase[key] }
            .filter { abs($0.strokeCount - writtenStrokeCount) <= 2 }
        var results: [(Character, Double)] = []
        results.reserveCapacity(candidates.count)
        for candidate in candidates {
            let datasetSubs = extractDatasetFeatures(from: candidate)
            if datasetSubs.isEmpty { continue }
            let cost = assignmentCost(written: writtenSubstrokes, dataset: datasetSubs)
            results.append((candidate, cost))
        }
        return results
    }

    /// Convert costs to probabilities using softmax over negative cost
    func probabilities(for drawing: CharacterDrawing, candidateKeys: [String]? = nil, temperature: Double? = nil) -> [(character: Character, cost: Double, probability: Double)] {
        let pairs = candidateCosts(for: drawing, candidateKeys: candidateKeys)
        guard !pairs.isEmpty else { return [] }
        let tau = max(1e-6, temperature ?? softmaxTemperature)
        // Stability: shift by min cost
        let minCost = pairs.map { $0.cost }.min() ?? 0.0
        let logits = pairs.map { -( $0.cost - minCost ) / tau }
        let maxLogit = logits.max() ?? 0.0
        let exps = logits.map { exp($0 - maxLogit) }
        let denom = exps.reduce(0, +)
        let probs = exps.map { $0 / max(denom, 1e-12) }
        var results: [(Character, Double, Double)] = []
        results.reserveCapacity(pairs.count)
        for (idx, pair) in pairs.enumerated() {
            results.append((pair.character, pair.cost, probs[idx]))
        }
        // Sort by probability descending
        return results.sorted { $0.2 > $1.2 }
    }

    /// Best match picked by highest softmax probability
    func bestMatchByProbability(for drawing: CharacterDrawing, candidateKeys: [String]? = nil, temperature: Double? = nil) -> (character: Character, cost: Double, probability: Double)? {
        return probabilities(for: drawing, candidateKeys: candidateKeys, temperature: temperature).first
    }


    /*
    returns several posterior probabilities (one for each of the candidates for each of the candidate characters),
    incorporating prior probabilities based on character usage and intended string.
    */
    func probabilitiesWithPrior(for drawing: CharacterDrawing,
                                 atIndex index: Int,
                                 intended: String,
                                 candidateKeys: [String]? = nil,
                                 temperature: Double? = nil,
                                 inMass: Double = 0.1,
                                 decay: Double = 0.9) -> [(character: Character, cost: Double, likelihood: Double, prior: Double, posterior: Double)] {
        let pairs = candidateCosts(for: drawing, candidateKeys: candidateKeys)
        guard !pairs.isEmpty else { return [] }
        let tau = max(1e-6, temperature ?? softmaxTemperature)
        let minCost = pairs.map { $0.cost }.min() ?? 0.0
        let logits = pairs.map { -( $0.cost - minCost ) / tau }
        let maxLogit = logits.max() ?? 0.0
        let exps = logits.map { exp($0 - maxLogit) }
        let denom = exps.reduce(0, +)
        let likelihoods = exps.map { $0 / max(denom, 1e-12) }

        var intendedPositions: [String: [Int]] = [:]
        for (pos, ch) in intended.enumerated() {
            let s = String(ch)
            intendedPositions[s, default: []].append(pos)
        }

        var inWeights: [Double] = Array(repeating: 0.0, count: pairs.count)
        var inCount = 0
        for (i, pair) in pairs.enumerated() {
            let c = pair.character.character
            if let posList = intendedPositions[c] {
                inCount += 1
                var best = Int.max
                for p in posList { best = min(best, abs(p - index)) }
                let w = pow(max(1e-6, decay), Double(best))
                inWeights[i] = w
            }
        }

        let outCount = pairs.count - inCount
        let sumIn = inWeights.reduce(0, +)
        var priors: [Double] = Array(repeating: 0.0, count: pairs.count)
        if inCount > 0 && sumIn > 0 {
            for i in 0..<pairs.count {
                if inWeights[i] > 0 {
                    priors[i] = inMass * (inWeights[i] / sumIn)
                } else if outCount > 0 {
                    priors[i] = (1.0 - inMass) * (1.0 / Double(outCount))
                }
            }
        } else {
            for i in 0..<pairs.count { priors[i] = 1.0 / Double(pairs.count) }
        }

        var postRaw: [Double] = []
        postRaw.reserveCapacity(pairs.count)
        for i in 0..<pairs.count {
            postRaw.append(max(1e-12, priors[i]) * max(1e-12, likelihoods[i]))
        }
        let postDen = postRaw.reduce(0, +)
        let post = postRaw.map { $0 / max(1e-12, postDen) }

        var results: [(Character, Double, Double, Double, Double)] = []
        results.reserveCapacity(pairs.count)
        for i in 0..<pairs.count {
            results.append((pairs[i].character, pairs[i].cost, likelihoods[i], priors[i], post[i]))
        }
        return results.sorted { $0.4 > $1.4 }
    }

    func bestMatchByPosterior(for drawing: CharacterDrawing,
                              atIndex index: Int,
                              intended: String,
                              candidateKeys: [String]? = nil,
                              temperature: Double? = nil,
                              inMass: Double = 0.35,
                              decay: Double = 0.95) -> (character: Character, cost: Double, probability: Double)? {
        guard let top = probabilitiesWithPrior(for: drawing, atIndex: index, intended: intended, candidateKeys: candidateKeys, temperature: temperature, inMass: inMass, decay: decay).first else { return nil }
        return (top.character, top.cost, top.4)
    }
    

    /*
    This function matches written characters in a sentence including dependencies between character assignments

    gamma - penalty for exceeding character occurance limits
    decay - controls the change in prior based on the index of the character (favors characters near index i)
    */
    func bestSentenceByGlobalReuse(written: [CharacterDrawing],
                                   intended: String,
                                   candidateKeys: [String]? = nil,
                                   temperature: Double? = nil,
                                   inMass: Double = 0.35,
                                   decay: Double = 0.95,
                                   gamma: Double = 0.8) -> (assigned: [Character], logScore: Double) {
        
        let eps = 1e-12
        let logGamma = log(max(eps, gamma))
        var cap: [String: Int] = [:]
        for ch in intended { cap[String(ch), default: 0] += 1 }
        var keySet: Set<String> = Set(candidateKeys ?? commonCharacters)
        for ch in intended { keySet.insert(String(ch)) }
        let keys = Array(keySet)

        var lists: [[(Character, String, Double, Bool)]] = []
        lists.reserveCapacity(written.count)
        for (i, d) in written.enumerated() {
            let probs = probabilitiesWithPrior(for: d, atIndex: i, intended: intended, candidateKeys: keys, temperature: temperature, inMass: inMass, decay: decay)
            var arr: [(Character, String, Double, Bool)] = []
            var sawNonGoal = false
            
            //Search until find a character not in the intended sentence
            for item in probs {
                let key = item.character.character
                let isGoal = cap[key] != nil
                if !sawNonGoal {
                    let lp = log(max(eps, item.4))
                    arr.append((item.character, key, lp, isGoal))
                    if !isGoal { sawNonGoal = true }
                } else {
                    break
                }
            }
            if arr.isEmpty, let first = probs.first {
                let key = first.character.character
                let lp = log(max(eps, first.4))
                arr.append((first.character, key, lp, cap[key] != nil))
            }
            lists.append(arr)
        }

        var bestScore = -Double.greatestFiniteMagnitude
        var bestAssign: [Character] = []
        var usage: [String: Int] = [:]
        var bestPerPos: [Double] = lists.map { $0.map { $0.2 }.max() ?? log(eps) }
        func upperBound(from idx: Int) -> Double {
            var s = 0.0
            var k = idx
            while k < bestPerPos.count { s += bestPerPos[k]; k += 1 }
            return s
        }
        var current: [Character] = []
        
        //Find best assignment of characters to written characters based on priors and character usage constraints
        func dfs(_ idx: Int, _ score: Double) {
            if idx == lists.count {
                if score > bestScore { bestScore = score; bestAssign = current }
                return
            }
            let ub = score + upperBound(from: idx)
            if ub <= bestScore { return }
            for opt in lists[idx] {
                let key = opt.1
                var add = opt.2
                if opt.3 {
                    let u = usage[key] ?? 0
                    let c = cap[key] ?? 0
                    if u >= c { add += logGamma }
                    usage[key] = u + 1
                }
                current.append(opt.0)
                dfs(idx + 1, score + add)
                current.removeLast()
                if opt.3 {
                    let u = (usage[key] ?? 1) - 1
                    if u <= 0 { usage.removeValue(forKey: key) } else { usage[key] = u }
                }
            }
        }
        dfs(0, 0.0)
        return (bestAssign, bestScore)
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
            let scaledLen = writtenLengthScale * len
            return (angle: ang, nx: min(1, max(0, nx)), ny: min(1, max(0, ny)), length: min(1, max(0, scaledLen)))
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
                                missingPenalty: Double = CharacterAnalyzer.shared.missingWeight,
                                angleWeight: Double = CharacterAnalyzer.shared.angleWeight,
                                posWeight: Double = CharacterAnalyzer.shared.positionWeight,
                                lenWeight: Double = CharacterAnalyzer.shared.lengthWeight) -> Double {
        let m = written.count
        let n = dataset.count
        let size = max(m, n)
        
        // Build square cost matrix with padding
        var cost: [[Double]] = Array(repeating: Array(repeating: missingPenalty, count: size), count: size)
        for i in 0..<m {
            for j in 0..<n {
                let a = written[i]
                let b = dataset[j]
                let angDiff = angularDiff(a.0, b.0) / .pi // [0,1]
                let dx = a.1 - b.1, dy = a.2 - b.2
                let posDiff = sqrt(dx*dx + dy*dy) / sqrt(2.0) // [0,1]
                let lenDiff = abs(a.3 - b.3) // [0,1]
                // Index-distance penalty (0 when i==j, increases with |i-j|, normalized by size)
                let indexNorm = size > 1 ? Double(abs(i - j)) / Double(size - 1) : 0.0
                let indexTerm = indexProximityWeight * indexNorm
                cost[i][j] = angleWeight*angDiff + posWeight*posDiff + lenWeight*lenDiff + indexTerm
            }
        }
        // Length-weighted missing penalties for padded columns (dataset dummy)
        if n < size {
            for i in 0..<m {
                for j in n..<size {
                    let a = written[i]
                    cost[i][j] = missingPenalty * a.3 // a.3 is normalized (and scaled) length in [0,1]
                }
            }
        }
        // Length-weighted missing penalties for padded rows (written dummy)
        if m < size {
            for i in m..<size {
                for j in 0..<n {
                    let b = dataset[j]
                    cost[i][j] = missingPenalty * b.3 // b.3 is normalized dataset length in [0,1]
                }
            }
        }
        
        // Hungarian algorithm
        let assignment = hungarian(costMatrix: cost)
        var total = 0.0
        for (i, j) in assignment {
            total += cost[i][j]
        }
        // Explicit substroke-count penalty (no division by size)
        let discrepancy = abs(m - n)
        let extra = Double(discrepancy) * substrokeCountPenalty
        // Average per matched pair + explicit discrepancy penalty
        return total / Double(size) + extra
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
