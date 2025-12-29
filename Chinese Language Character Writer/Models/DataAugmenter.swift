import Foundation

class DataAugmenter {
    
    /// Generate augmented variations of a validation entry
    func generateAugmentations(from entry: ValidationEntry, types: [AugmentationType]) -> [ValidationEntry] {
        var augmentedEntries: [ValidationEntry] = []
        
        for type in types {
            switch type {
            case .swapAdjacent:
                augmentedEntries.append(contentsOf: generateAdjacentSwaps(from: entry))
            case .swapRandom:
                augmentedEntries.append(contentsOf: generateRandomSwaps(from: entry))
            case .reverseAll:
                if let reversed = generateReversed(from: entry) {
                    augmentedEntries.append(reversed)
                }
            case .removeOne:
                augmentedEntries.append(contentsOf: generateRemoveOne(from: entry))
            case .removeTwo:
                augmentedEntries.append(contentsOf: generateRemoveTwo(from: entry))
            }
        }
        
        return augmentedEntries
    }
    
    // MARK: - Swap Adjacent
    
    private func generateAdjacentSwaps(from entry: ValidationEntry) -> [ValidationEntry] {
        var results: [ValidationEntry] = []
        let strokes = entry.userStrokes
        
        guard strokes.count >= 2 else { return results }
        
        // Swap each adjacent pair
        for i in 0..<(strokes.count - 1) {
            var newStrokes = strokes
            newStrokes.swapAt(i, i + 1)
            
            // Reindex the strokes
            let reindexed = reindexStrokes(newStrokes)
            
            let newEntry = ValidationEntry(
                character: entry.character,
                userStrokes: reindexed,
                referenceStrokeCount: entry.referenceStrokeCount
            )
            results.append(newEntry)
        }
        
        return results
    }
    
    // MARK: - Random Swaps
    
    private func generateRandomSwaps(from entry: ValidationEntry) -> [ValidationEntry] {
        var results: [ValidationEntry] = []
        let strokes = entry.userStrokes
        
        guard strokes.count >= 2 else { return results }
        
        let swapCount = min(5, strokes.count * (strokes.count - 1) / 4)
        
        for _ in 0..<swapCount {
            var newStrokes = strokes
            
            // Perform 1-3 random swaps
            let numSwaps = Int.random(in: 1...min(3, strokes.count / 2))
            var swappedIndices: Set<Int> = []
            
            for _ in 0..<numSwaps {
                var idx1 = Int.random(in: 0..<strokes.count)
                var idx2 = Int.random(in: 0..<strokes.count)
                
                // Ensure we don't swap the same index or already swapped indices
                var attempts = 0
                while (idx1 == idx2 || swappedIndices.contains(idx1) || swappedIndices.contains(idx2)) && attempts < 10 {
                    idx1 = Int.random(in: 0..<strokes.count)
                    idx2 = Int.random(in: 0..<strokes.count)
                    attempts += 1
                }
                
                if idx1 != idx2 {
                    newStrokes.swapAt(idx1, idx2)
                    swappedIndices.insert(idx1)
                    swappedIndices.insert(idx2)
                }
            }
            
            // Reindex the strokes
            let reindexed = reindexStrokes(newStrokes)
            
            let newEntry = ValidationEntry(
                character: entry.character,
                userStrokes: reindexed,
                referenceStrokeCount: entry.referenceStrokeCount
            )
            results.append(newEntry)
        }
        
        return results
    }
    
    // MARK: - Reverse All
    
    private func generateReversed(from entry: ValidationEntry) -> ValidationEntry? {
        let strokes = entry.userStrokes
        
        guard strokes.count >= 2 else { return nil }
        
        let reversed = Array(strokes.reversed())
        let reindexed = reindexStrokes(reversed)
        
        return ValidationEntry(
            character: entry.character,
            userStrokes: reindexed,
            referenceStrokeCount: entry.referenceStrokeCount
        )
    }
    
    // MARK: - Remove One Stroke
    
    private func generateRemoveOne(from entry: ValidationEntry) -> [ValidationEntry] {
        var results: [ValidationEntry] = []
        let strokes = entry.userStrokes
        
        guard strokes.count >= 2 else { return results }
        
        // Create a variation for each stroke removed
        for i in 0..<strokes.count {
            var newStrokes = strokes
            newStrokes.remove(at: i)
            
            // Reindex the remaining strokes
            let reindexed = reindexStrokes(newStrokes)
            
            let newEntry = ValidationEntry(
                character: entry.character,
                userStrokes: reindexed,
                referenceStrokeCount: entry.referenceStrokeCount
            )
            results.append(newEntry)
        }
        
        return results
    }
    
    // MARK: - Remove Two Strokes
    
    private func generateRemoveTwo(from entry: ValidationEntry) -> [ValidationEntry] {
        var results: [ValidationEntry] = []
        let strokes = entry.userStrokes
        
        guard strokes.count >= 3 else { return results }
        
        // Generate up to 10 combinations of removing 2 strokes
        var combinations: [(Int, Int)] = []
        
        for i in 0..<strokes.count {
            for j in (i + 1)..<strokes.count {
                combinations.append((i, j))
            }
        }
        
        // Shuffle and take up to 10
        combinations.shuffle()
        let selectedCombinations = Array(combinations.prefix(10))
        
        for (idx1, idx2) in selectedCombinations {
            var newStrokes = strokes
            
            // Remove in reverse order to maintain indices
            newStrokes.remove(at: idx2)
            newStrokes.remove(at: idx1)
            
            // Reindex the remaining strokes
            let reindexed = reindexStrokes(newStrokes)
            
            let newEntry = ValidationEntry(
                character: entry.character,
                userStrokes: reindexed,
                referenceStrokeCount: entry.referenceStrokeCount
            )
            results.append(newEntry)
        }
        
        return results
    }
    
    // MARK: - Helper Methods
    
    /// Reindex strokes to have sequential strokeIndex values starting from 0
    private func reindexStrokes(_ strokes: [LabeledStroke]) -> [LabeledStroke] {
        return strokes.enumerated().map { index, stroke in
            LabeledStroke(
                id: UUID(), // Generate new ID for augmented stroke
                strokeIndex: index,
                points: stroke.points,
                groundTruthMatch: stroke.groundTruthMatch,
                missingSubstrokes: stroke.missingSubstrokes
            )
        }
    }
}
